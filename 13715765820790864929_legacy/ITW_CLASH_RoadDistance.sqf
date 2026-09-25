#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_RoadDistanceStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_RoadDistanceReady",false]
};

ITW_CLASH_RoadDistanceStarted = true;
ITW_CLASH_RoadDistanceReady = false;
ITW_CLASH_RoadDistanceVersion = 1;

/*
    Genuinely honest distance between two points, not straight-line. Answers
    "how far is this support call, really" for dispatch-mode decisions - a
    demand across a river or behind a mountain range should read as far even
    if it happens to be numerically close by air.

    Deliberately NOT a whole-map cached road graph (that would be real,
    separate, reusable-project-wide infrastructure, worth building on its own
    terms - see docs/CLASH_HAL_DISPATCH_PATCH.md history). This is a bounded,
    on-demand, two-point query: expand outward from both ends via the native
    roadsConnectingTo adjacency until they meet or the search budget runs
    out, then throw the search state away. Fine to run once per demand
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

ITW_CLASH_RoadDistance_fnc_Nearest = {
    params ["_pos","_candidates"];
    private _best = _candidates#0;
    private _bestDist = _pos distance2D _best;
    {
        private _d = _pos distance2D _x;
        if (_d < _bestDist) then {_best = _x; _bestDist = _d};
    } forEach _candidates;
    _best
};

// [posA, posB] -> NUMBER (real road-following distance in meters), or -1 if
// no road exists near one/both ends, or the search budget runs out before
// the two ends connect. -1 means "don't trust this as close" - a caller
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

    private _startRoad = [_posA,_startCandidates] call ITW_CLASH_RoadDistance_fnc_Nearest;
    private _endRoad = [_posB,_endCandidates] call ITW_CLASH_RoadDistance_fnc_Nearest;

    // Same local road cluster - no graph search needed, straight line between
    // the two points is a fine approximation over this short a stretch.
    if (_startRoad distance2D _endRoad < ITW_CLASH_RoadDistanceSearchRadius) exitWith {
        _posA distance2D _posB
    };

    // Bounded Dijkstra. No priority queue - a linear scan of a capped open
    // list is trivial at this node budget and this call frequency.
    private _knownCost = createHashMap;
    private _startKey = str _startRoad;
    _knownCost set [_startKey,0];
    private _open = [[_startRoad,0]];
    private _visited = [];
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

        if (!(_current in _visited) && {_currentCost <= ITW_CLASH_RoadDistanceMaxDistance}) then {
            _visited pushBack _current;
            _nodesExpanded = _nodesExpanded + 1;

            if (_current distance2D _endRoad < ITW_CLASH_RoadDistanceSearchRadius) then {
                _result = _currentCost + (_current distance2D _posB);
            } else {
                {
                    if (!(_x in _visited)) then {
                        private _edgeCost = _currentCost + (_current distance2D _x);
                        private _key = str _x;
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
