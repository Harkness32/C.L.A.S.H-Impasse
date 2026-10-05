#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_FOBGarrisonSweepStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_FOBGarrisonSweepReady",false]
};

ITW_CLASH_FOBGarrisonSweepStarted = true;
ITW_CLASH_FOBGarrisonSweepReady = false;
ITW_CLASH_FOBGarrisonSweepVersion = 1;
scriptName "ITW_CLASH_FOBGarrisonSweep";

/*
    Clear out a FOB the front has left behind.

    Hark: "on front change, any fob that isn't a forward or rear fob now, we
    should wipe the garrison so the new troops can be spawned. only the units
    that are in the radius of the fob, like sentries, etc etc"

    This is the DESTRUCTIVE sibling of the locked-objective release in
    ITW_CLASH.sqf. The two look similar and are not:

      locked objective  -> RELEASE. The ground still matters, the garrison is
                           simply leashed to something that cannot be taken, so
                           the groups are handed back to HAL to use elsewhere.
      stale FOB         -> WIPE. The ground no longer matters at all, and the
                           point is not to re-task those men but to get their
                           slots back, because the AI cap is what stops fresh
                           troops spawning at the FOBs that are now live.

    Which FOBs are live is not decided here. ITW_CLASH_Generation_fnc_Resolve
    already owns the campaign graph and returns forwardBase and rearBase for a
    side in one call, so this asks it rather than building a second geography
    model that could disagree with the first.

    Deletion is not reversible, so the exclusions are deliberately broad:
    anything with a player in it, anything a lifecycle owner has reserved,
    the commander, the air defence FOBAirDefence placed on purpose, and
    anything mounted in a vehicle - a crewed vehicle is an asset the checkbook
    paid for, and freeing an infantry slot is not worth destroying one.
*/

ITW_CLASH_FOBGarrisonSweepEnabled = missionNamespace getVariable [
    "ITW_CLASH_FOBGarrisonSweepEnabled",true
];
// A FOB is a small thing. Sentries dug in around it are what this is for, not
// a squad that happens to be passing a kilometre away. There is no canonical
// base radius anywhere in Impasse or C.L.A.S.H. to borrow, so this is a
// judgement: the Queen concentration Hark photographed spans rather more than
// 200m. Near-misses are counted in the sweep line so the number can be tuned
// from one run instead of guessed twice.
ITW_CLASH_FOBGarrisonSweepRadius = missionNamespace getVariable [
    "ITW_CLASH_FOBGarrisonSweepRadius",300
];
// A ceiling per front change, so a graph that goes wrong cannot empty the map
// in one pass. Hitting it is logged loudly.
ITW_CLASH_FOBGarrisonSweepMax = missionNamespace getVariable [
    "ITW_CLASH_FOBGarrisonSweepMax",24
];
ITW_CLASH_FOBGarrisonSweepPoll = missionNamespace getVariable [
    "ITW_CLASH_FOBGarrisonSweepPoll",5
];

ITW_CLASH_FOBGarrisonSweep_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["fob-garrison-sweep-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH FOB GARRISON SWEEP | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["fob-garrison-sweep",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

/*
    The bases this side is still using, straight from the campaign graph.

    Both ground and air are asked for, because a side can stage armour from one
    base and aircraft from another, and wiping the one that is only an air node
    would be exactly the mistake this is meant to avoid. An UNRESOLVED answer
    contributes nothing, which means a graph that cannot answer leaves every
    base in the keep set and the sweep does nothing at all.
*/
ITW_CLASH_FOBGarrisonSweep_fnc_LiveBases = {
    params ["_side"];
    private _live = [];
    if (isNil "ITW_CLASH_Generation_fnc_Resolve") exitWith {[-1]};

    {
        private _resolved = [_side,"TRANSPORT",_x,[]] call ITW_CLASH_Generation_fnc_Resolve;
        if (_resolved isEqualType createHashMap && {
            (_resolved getOrDefault ["status",""]) isEqualTo "RESOLVED"
        }) then {
            _live pushBackUnique (_resolved getOrDefault ["forwardBase",-1]);
            _live pushBackUnique (_resolved getOrDefault ["rearBase",-1]);
        };
    } forEach ["FORWARD","REAR","FORWARD_AIR","REAR_AIR"];

    // Nothing resolved: refuse to name any base stale rather than guess.
    if (_live isEqualTo []) exitWith {[-1]};
    _live
};

ITW_CLASH_FOBGarrisonSweep_fnc_IsSweepable = {
    params ["_group","_unit"];
    if (isNull _group || {isNull _unit} || {!alive _unit}) exitWith {false};
    if (isPlayer _unit) exitWith {false};
    if (((units _group) findIf {isPlayer _x}) >= 0) exitWith {false};
    // Mounted: a crewed vehicle is an asset, not a sentry.
    if (vehicle _unit != _unit) exitWith {false};
    if !(_unit isKindOf "CAManBase") exitWith {false};
    if (!isNil "ITW_CLASH_fnc_IsCommanderGroup" && {
        [_group] call ITW_CLASH_fnc_IsCommanderGroup
    }) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" && {
        [_group] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved
    }) exitWith {false};
    if ((_group getVariable ["ITW_CLASH_FOBAirDefence",""]) isNotEqualTo "") exitWith {false};
    true
};

/*
    One side, one pass.

    Garrison membership is the definition of "manning this FOB" - it is what
    HAL's own leash reads (HAC_fnc.sqf:1593) - so the candidates are that
    side's RydHQ_Garrison and nothing else. A group merely standing near a
    stale FOB is passing through and is left alone.
*/
ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide = {
    params ["_side"];
    if (isNil "ITW_Bases" || {ITW_Bases isEqualTo []}) exitWith {0};
    if (isNil "ITW_CLASH_fnc_GetCommanderForSide") exitWith {0};

    private _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;
    if (isNull _hq) exitWith {0};

    private _live = [_side] call ITW_CLASH_FOBGarrisonSweep_fnc_LiveBases;
    if (_live isEqualTo [-1]) exitWith {
        ["skipped",[toUpperANSI str _side,"graph-unresolved"]] call
            ITW_CLASH_FOBGarrisonSweep_fnc_Log;
        0
    };

    private _stale = [];
    {
        private _index = _forEachIndex;
        if (_index in _live) then {continue};
        private _base = _x;
        if !(_base isEqualType []) then {continue};
        if (count _base <= ITW_BASE_SPAWNED) then {continue};
        if !(_base#ITW_BASE_SPAWNED) then {continue};
        private _pos = _base#ITW_BASE_POS;
        if (_pos isEqualTo []) then {continue};
        _stale pushBack [_index,_pos];
    } forEach ITW_Bases;
    if (_stale isEqualTo []) exitWith {0};

    private _garrison = +(_hq getVariable ["RydHQ_Garrison",[]]);
    if (_garrison isEqualTo []) exitWith {0};

    private _wiped = 0;
    private _nearMiss = 0;
    private _groupsTouched = [];
    private _capped = false;
    {
        private _group = _x;
        if (isNull _group) then {continue};
        if (_wiped >= ITW_CLASH_FOBGarrisonSweepMax) then {_capped = true};
        if (_capped) then {continue};

        {
            private _baseIndex = _x#0;
            private _basePos = _x#1;
            private _sweepable = (units _group) select {
                alive _x && {[_group,_x] call ITW_CLASH_FOBGarrisonSweep_fnc_IsSweepable}
            };
            private _inside = _sweepable select {
                (getPosATL _x) distance2D _basePos <= ITW_CLASH_FOBGarrisonSweepRadius
            };
            if (_inside isEqualTo []) then {
                // Just outside: counted so the radius can be judged from the
                // log rather than from a second screenshot.
                _nearMiss = _nearMiss + (count (_sweepable select {
                    (getPosATL _x) distance2D _basePos
                        <= ITW_CLASH_FOBGarrisonSweepRadius * 2
                }));
                continue
            };

            {
                deleteVehicle _x;
                _wiped = _wiped + 1;
            } forEach _inside;
            _groupsTouched pushBackUnique [[_group] call ITW_CLASH_fnc_GroupId,_baseIndex];
        } forEach _stale;
    } forEach _garrison;

    if (_wiped == 0) exitWith {
        if (_nearMiss > 0) then {
            ["radius-near-miss",[
                toUpperANSI str _side,_nearMiss,
                ITW_CLASH_FOBGarrisonSweepRadius,_stale apply {_x#0}
            ]] call ITW_CLASH_FOBGarrisonSweep_fnc_Log;
        };
        0
    };

    // Anything emptied is no longer a garrison, and an empty group lingering in
    // HAL's list is a slot it believes it has.
    private _survivors = _garrison select {
        !isNull _x && {({alive _x} count units _x) > 0}
    };
    _hq setVariable ["RydHQ_Garrison",_survivors];
    {
        if (!isNull _x && {units _x isEqualTo []}) then {deleteGroup _x};
    } forEach _garrison;

    ["wiped",[
        toUpperANSI str _side,_wiped,_nearMiss,_groupsTouched,
        _stale apply {_x#0},_live,
        ITW_CLASH_FOBGarrisonSweepRadius
    ]] call ITW_CLASH_FOBGarrisonSweep_fnc_Log;
    if (_capped) then {
        diag_log format [
            "CLASH FOB GARRISON SWEEP | WARNING | sweep-capped | side=%1 max=%2 | the campaign graph named an unexpected number of stale bases; nothing further was deleted this pass",
            toUpperANSI str _side,ITW_CLASH_FOBGarrisonSweepMax
        ];
    };
    _wiped
};

ITW_CLASH_FOBGarrisonSweep_fnc_Sweep = {
    private _total = 0;
    private _sides = [];
    if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
    if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
    {
        _total = _total + ([_x] call ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide);
    } forEach _sides;
    _total
};

if (!ITW_CLASH_FOBGarrisonSweepEnabled) exitWith {
    ["disabled",[]] call ITW_CLASH_FOBGarrisonSweep_fnc_Log;
    false
};

[] spawn {
    scriptName "ITW_CLASH_FOBGarrisonSweep_watch";
    waitUntil {
        sleep 1;
        (!isNil "ITW_ZoneIndex" && {!isNil "ITW_Bases"} && {!isNil "ITW_CLASH_Generation_fnc_Resolve"})
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    private _lastZone = ITW_ZoneIndex;

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_FOBGarrisonSweepPoll;
        if (!isNil "ITW_ZoneIndex" && {ITW_ZoneIndex != _lastZone}) then {
            private _from = _lastZone;
            _lastZone = ITW_ZoneIndex;
            // Let the graph settle on the new front before asking it which
            // bases are live; resolving mid-transition is how the wrong base
            // gets called stale.
            sleep 10;
            private _wiped = call ITW_CLASH_FOBGarrisonSweep_fnc_Sweep;
            ["front-changed",[_from,ITW_ZoneIndex,_wiped]] call
                ITW_CLASH_FOBGarrisonSweep_fnc_Log;
        };
    };
};

ITW_CLASH_FOBGarrisonSweepReady = true;
diag_log format [
    "CLASH BOOT | fob-garrison-sweep-ready | version=%1 radius=%2 max=%3 trigger=front-change graphOwner=Generation_fnc_Resolve destructive=true excludes=players,lifecycle,commander,fob-air-defence,mounted",
    ITW_CLASH_FOBGarrisonSweepVersion,
    ITW_CLASH_FOBGarrisonSweepRadius,
    ITW_CLASH_FOBGarrisonSweepMax
];
true
