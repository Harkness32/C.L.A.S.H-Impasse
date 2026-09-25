#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_RoadDistanceStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_RoadDistanceReady",false]
};

ITW_CLASH_RoadDistanceStarted = true;
ITW_CLASH_RoadDistanceReady = false;
ITW_CLASH_RoadDistanceVersion = 2;

/*
    Genuinely honest distance between two points, not straight-line. Answers
    "how far is this support call, really" for dispatch-mode decisions - a
    demand across a river or behind a mountain range should read as far even
    if it happens to be numerically close by air.

    Deliberately NOT a whole-map cached road graph (that would be real,
    separate, reusable-project-wide infrastructure, worth building on its own
    terms - see docs/CLASH_HAL_DISPATCH_PATCH.md history). This is a bounded,
    on-demand, two-point query: expand outward from the roads near A via the
    native roadsConnectingTo adjacency until a road near B is actually reached
    or the search budget runs out, then throw the search state away. Proximity
    never counts as connection. Fine to run once per demand
    evaluation (a 20-45s interval, not a hot path); not fine to run every
    tick or keep resident in memory.

    Checked first whether ITW already had something usable for this
    (ITW_AtkRoadMap, ITW_Attack.sqf:2724-2750) - it doesn't. That structure
    caches nearby roads for vehicle SPAWN PLACEMENT deconfliction, not route
    or distance. Confirmed by reading it, not assumed from the name.
*/

ITW_CLASH_RoadDistanceMaxNodes = missionNamespace getVariable [
    "ITW_CLASH_RoadDistanceMaxNodes",300
];
ITW_CLASH_RoadDistanceMaxDistance = missionNamespace getVariable [
    "ITW_CLASH_RoadDistanceMaxDistance",20000
];
ITW_CLASH_RoadDistanceSearchRadius = missionNamespace getVariable [
    "ITW_CLASH_RoadDistanceSearchRadius",300
];

ITW_CLASH_RoadDistance_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["road-distance-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH ROAD DISTANCE | %1 | %2",_event,_payload];
    };
};

// [posA, posB] -> NUMBER (off-road access legs plus real road-following
// distance, in meters), or -1 if no road exists near one/both ends, or the
// search budget runs out before a road near B is reached through actual road
// connectivity. -1 means "don't trust this as close" - a caller
// deciding near/far should treat it the same as "far" (force air), not as
// zero or as a fallback to straight-line, since -1 specifically means ground
// access here is unproven, not merely unmeasured.
ITW_CLASH_RoadDistance_fnc_Calculate = {
    params ["_posA","_posB"];

    private _startCandidates = _posA nearRoads ITW_CLASH_RoadDistanceSearchRadius;
    private _endCandidates = _posB nearRoads ITW_CLASH_RoadDistanceSearchRadius;
    if (_startCandidates isEqualTo [] || {_endCandidates isEqualTo []}) exitWith {
        ["no-road-access",[_posA,_posB]] call ITW_CLASH_RoadDistance_fnc_Log;
        -1
    };

    // Every road near B is a possible exit, costed by its off-road leg to B.
    // Reaching one pushes a virtual goal entry (objNull); the search ends when
    // that goal is popped, so the answer is a true shortest path rather than
    // the first road that happens to lie near B.
    private _exitCost = createHashMap;
    {_exitCost set [str _x,_posB distance2D _x]} forEach _endCandidates;

    // Bounded multi-source Dijkstra: every road near A starts at its off-road
    // leg from A. No priority queue - a linear scan of a capped open list is
    // trivial at this node budget and this call frequency.
    private _knownCost = createHashMap;
    private _open = [];
    {
        private _entry = _posA distance2D _x;
        _knownCost set [str _x,_entry];
        _open pushBack [_x,_entry];
    } forEach _startCandidates;
    private _visited = createHashMap;
    private _result = -1;
    private _nodesExpanded = 0;

    while {
        count _open > 0
        && {_nodesExpanded < ITW_CLASH_RoadDistanceMaxNodes}
        && {_result < 0}
    } do {
        private _bestIdx = 0;
        private _bestCost = (_open#0)#1;
        {
            if ((_x#1) < _bestCost) then {_bestCost = _x#1; _bestIdx = _foreachIndex};
        } forEach _open;
        private _current = (_open#_bestIdx)#0;
        private _currentCost = (_open#_bestIdx)#1;
        _open deleteAt _bestIdx;

        if (isNull _current) then {
            _result = _currentCost;
        } else {
            private _currentKey = str _current;
            if (!(_currentKey in _visited) && {_currentCost <= ITW_CLASH_RoadDistanceMaxDistance}) then {
                _visited set [_currentKey,true];
                _nodesExpanded = _nodesExpanded + 1;

                private _exit = _exitCost getOrDefault [_currentKey,-1];
                if (_exit >= 0) then {_open pushBack [objNull,_currentCost + _exit]};

                {
                    private _key = str _x;
                    if !(_key in _visited) then {
                        private _edgeCost = _currentCost + (_current distance2D _x);
                        private _known = _knownCost getOrDefault [_key,1e10];
                        if (_edgeCost < _known) then {
                            _knownCost set [_key,_edgeCost];
                            _open pushBack [_x,_edgeCost];
                        };
                    };
                } forEach (roadsConnectingTo _current);
            };
        };
    };

    if (_result < 0) then {
        ["search-exhausted",[_posA,_posB,_nodesExpanded]] call ITW_CLASH_RoadDistance_fnc_Log;
    };
    _result
};

ITW_CLASH_RoadDistanceReady = true;
diag_log format [
    "CLASH BOOT | road-distance-ready | version=%1 maxNodes=%2 maxDistance=%3 searchRadius=%4",
    ITW_CLASH_RoadDistanceVersion,
    ITW_CLASH_RoadDistanceMaxNodes,
    ITW_CLASH_RoadDistanceMaxDistance,
    ITW_CLASH_RoadDistanceSearchRadius
];

true
