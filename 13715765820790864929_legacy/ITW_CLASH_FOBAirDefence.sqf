#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_FOBAirDefenceStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_HALThreatCoverage_fnc_HasLoadedLauncher") exitWith {
    diag_log "CLASH BOOT | WARNING | fob-air-defence-launcher-test-missing | AA squads stay where they stand";
    false
};

ITW_CLASH_FOBAirDefenceStarted = true;
ITW_CLASH_FOBAirDefenceVersion = 1;
ITW_CLASH_FOBAirDefenceReady = false;

/*
    AA teams garrison FOBs.

    HAL already hands AT, AA and sniper squads to its own garrison routine every
    60 seconds (HAC_fnc2.sqf:1513-1516), but that routine digs a group in
    WHEREVER IT ALREADY STANDS (HAL\Garrison.sqf:41,
    `_pos = getPosATL (vehicle (leader _unitG))`). Nothing in HAL or Impasse ever
    sends an AA squad to a FOB, so a side's MANPADS sit wherever they spawned and
    the rear stays open to air.

    This file only does the part that is missing: it walks an idle AA squad to a
    FOB and then hands it to HAL's routine, by putting it in RydHQ_Garrison once
    it has arrived. HAL digs it in from there. No garrison behaviour is
    reimplemented and no HAL file is touched.

    Two things fall out of it for free:
      - Counter-air coverage counts them automatically. The rule already weights
        an AA squad with a loaded launcher at 0.25 inside a 3 km umbrella, so a
        garrisoned FOB team covers aircraft working that FOB and nothing else.
      - Players get readable counterplay: avoid the FOBs, or suppress the teams
        first. It is a learnable danger zone, not a map-wide rule.

    The squad has to ARRIVE before it is handed over, because HAL digs in where
    the group stands - hand it over early and it digs in halfway down the road.
*/

ITW_CLASH_FOBAirDefenceEnabled = missionNamespace getVariable ["ITW_CLASH_FOBAirDefenceEnabled",true];
ITW_CLASH_FOBAirDefencePoll = missionNamespace getVariable ["ITW_CLASH_FOBAirDefencePoll",45];
ITW_CLASH_FOBAirDefenceArrival = missionNamespace getVariable ["ITW_CLASH_FOBAirDefenceArrival",75];
// Give up on a walk that is clearly not happening and free the squad.
ITW_CLASH_FOBAirDefenceTimeout = missionNamespace getVariable ["ITW_CLASH_FOBAirDefenceTimeout",900];
// Cover the rear FOB as well as the forward one. The rear is where an enemy jet
// loiters unopposed, so it is worth a team.
ITW_CLASH_FOBAirDefenceIncludeRear = missionNamespace getVariable ["ITW_CLASH_FOBAirDefenceIncludeRear",true];

// sideKey -> (fob key -> [group, position, state, sinceTime])
ITW_CLASH_FOBAirDefenceAssignments = createHashMap;

// Release the launcher teams once a mobile SPAA holds the back line.
ITW_CLASH_FOBAirDefenceYieldToSPAA = missionNamespace getVariable [
    "ITW_CLASH_FOBAirDefenceYieldToSPAA",true
];
// How many mobile SPAA count as holding it. One, matching the back line's own
// cap: the doctrine keeps exactly one, so requiring more would never release.
ITW_CLASH_FOBAirDefenceSPAAFloor = missionNamespace getVariable [
    "ITW_CLASH_FOBAirDefenceSPAAFloor",1
];

ITW_CLASH_FOBAirDefence_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["fob-air-defence-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH FOB AIR DEFENCE | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["fob-air-defence",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

ITW_CLASH_FOBAirDefence_fnc_FOBKey = {
    params ["_position"];
    format ["%1|%2",round ((_position#0) / 50),round ((_position#1) / 50)]
};

// This side's FOBs, off Impasse's own base graph - the same nodes the front and
// an ETB ground purchase resolve.
ITW_CLASH_FOBAirDefence_fnc_FOBs = {
    params ["_side"];
    if (isNil "ITW_CLASH_Generation_fnc_Resolve" || {
        isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds"
    }) exitWith {[]};
    private _positions = [];
    {
        if (_x < 0 || {_x >= count ITW_Objectives}) then {continue};
        private _reference = +(ITW_Objectives#_x#ITW_OBJ_POS);
        private _generation = [
            _side,"SPAA","FORWARD",_reference
        ] call ITW_CLASH_Generation_fnc_Resolve;
        if ((_generation getOrDefault ["status",""]) isNotEqualTo "RESOLVED") then {continue};
        {
            private _position = +(_generation getOrDefault [_x,[]]);
            if (_position isEqualTo []) then {continue};
            if (count _position < 3) then {_position pushBack 0};
            if ((_positions findIf {(_x distance2D _position) < 100}) < 0) then {
                _positions pushBack _position;
            };
        } forEach (
            if (ITW_CLASH_FOBAirDefenceIncludeRear) then {
                ["forwardPosition","rearPosition"]
            } else {
                ["forwardPosition"]
            }
        );
    } forEach (call ITW_CLASH_Generation_fnc_ActiveObjectiveIds);
    _positions
};

/*
    An AA squad worth walking: it has a launcher it can fire, HAL is not using
    it, and it is not already doing this job somewhere else. A squad HAL has
    tasked is left alone - the air defence gap is not worth pulling a squad off a
    mission for.
*/
/*
    Does a vehicle already hold the back line?

    An AA squad walked to a FOB is a squad not in the fight, and a mobile SPAA
    on overwatch covers the same sky far better: it relocates as the front
    moves, it re-points at the nearest known hostile every poll, and it is not
    three riflemen with a launcher. Where one is held, the launcher teams are
    better employed as infantry.

    The rear-base C-RAM does not count. It is bolted to one spot by design -
    gunner, no driver - so it covers the base and nothing else, and leaving the
    FOBs to it would be covering a different place than the one at risk.
*/
ITW_CLASH_FOBAirDefence_fnc_BacklineCovered = {
    params ["_hq"];
    if (isNull _hq) exitWith {false};
    if (!ITW_CLASH_FOBAirDefenceYieldToSPAA) exitWith {false};
    if (isNil "ITW_CLASH_SPAAOverwatch_fnc_Held") exitWith {false};
    private _held = ([side _hq] call ITW_CLASH_SPAAOverwatch_fnc_Held) select {
        !(vehicle leader _x getVariable ["ITW_CLASH_CRAM",false])
    };
    (count _held) >= ITW_CLASH_FOBAirDefenceSPAAFloor
};

ITW_CLASH_FOBAirDefence_fnc_Candidates = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};
    // A mobile SPAA already covers this commander's back line, so its launcher
    // teams are released to fight rather than walked to a FOB.
    if ([_hq] call ITW_CLASH_FOBAirDefence_fnc_BacklineCovered) exitWith {[]};
    (_hq getVariable ["RydHQ_AAInfG",[]]) select {
        private _group = _x;
        !isNull _group
        && {({alive _x} count units _group) > 0}
        && {((units _group) findIf {isPlayer _x}) < 0}
        && {!(_group getVariable ["Busy" + str _group,false])}
        && {!(_group getVariable ["Unable",false])}
        && {!(_group getVariable ["Resting" + str _group,false])}
        && {(_group getVariable ["ITW_CLASH_FOBAirDefence",""]) isEqualTo ""}
        && {[_group,"AA"] call ITW_CLASH_HALThreatCoverage_fnc_HasLoadedLauncher}
    }
};

// Walk it there. Nothing is garrisoned yet: HAL's routine would dig it in on the
// spot, so the handover waits for arrival.
ITW_CLASH_FOBAirDefence_fnc_Send = {
    params ["_hq","_group","_position"];
    if (isNull _group || {_position isEqualTo []}) exitWith {false};
    private _key = [_position] call ITW_CLASH_FOBAirDefence_fnc_FOBKey;
    _group setVariable ["ITW_CLASH_FOBAirDefence",_key];
    _group setVariable ["Garrisoned" + str _group,false];

    if (!isNil "RYD_WPdel") then {[_group] call RYD_WPdel};
    private _waypoint = _group addWaypoint [_position,0];
    _waypoint setWaypointType "MOVE";
    _waypoint setWaypointBehaviour "AWARE";
    _waypoint setWaypointCombatMode "YELLOW";
    _waypoint setWaypointSpeed "NORMAL";
    (leader _group) doMove _position;

    ["sent",[
        _hq getVariable ["RydHQ_CodeSign","?"],groupId _group,
        _position apply {round _x},
        round ((getPosATL (vehicle (leader _group))) distance2D _position)
    ]] call ITW_CLASH_FOBAirDefence_fnc_Log;
    true
};

/*
    Arrived: hand it to HAL. RydHQ_Garrison membership plus a cleared Garrisoned
    flag is exactly what HAL's own routine consumes on its next 60-second pass,
    and it digs the group in where it now stands - the FOB.
*/
ITW_CLASH_FOBAirDefence_fnc_HandOver = {
    params ["_hq","_group","_position"];
    if (isNull _hq || {isNull _group}) exitWith {false};
    if (!isNil "RYD_WPdel") then {[_group] call RYD_WPdel};

    private _garrison = +(_hq getVariable ["RydHQ_Garrison",[]]);
    _garrison pushBackUnique _group;
    _hq setVariable ["RydHQ_Garrison",_garrison];
    _group setVariable ["Garrisoned" + str _group,false];
    _group setVariable ["NOGarrisoned" + str _group,false];

    ["handed-to-hal-garrison",[
        _hq getVariable ["RydHQ_CodeSign","?"],groupId _group,
        _position apply {round _x},count _garrison
    ]] call ITW_CLASH_FOBAirDefence_fnc_Log;
    true
};

ITW_CLASH_FOBAirDefence_fnc_Release = {
    params ["_group",["_reason","released"]];
    if (isNull _group) exitWith {false};
    _group setVariable ["ITW_CLASH_FOBAirDefence",""];
    ["released",[groupId _group,_reason]] call ITW_CLASH_FOBAirDefence_fnc_Log;
    true
};

ITW_CLASH_FOBAirDefence_fnc_Maintain = {
    params ["_hq"];
    if (isNull _hq) exitWith {false};
    private _side = side _hq;
    private _sideKey = toUpperANSI str _side;
    private _assignments = ITW_CLASH_FOBAirDefenceAssignments getOrDefault [_sideKey,createHashMap];
    if (count _assignments == 0) then {
        ITW_CLASH_FOBAirDefenceAssignments set [_sideKey,_assignments];
    };

    private _fobs = [_side] call ITW_CLASH_FOBAirDefence_fnc_FOBs;
    private _live = _fobs apply {[_x] call ITW_CLASH_FOBAirDefence_fnc_FOBKey};

    // Drop assignments whose squad died, or whose FOB is no longer ours. Keys
    // only, and the entry is fetched live: `+` is a deep copy, so an entry
    // reached through one cannot be updated, and this loop deletes from the very
    // map it walks.
    {
        private _key = _x;
        private _entry = _assignments getOrDefault [_key,[]];
        if (_entry isEqualTo []) then {continue};
        _entry params ["_group","","_state","_since"];
        private _gone = isNull _group || {({alive _x} count units _group) <= 0};
        private _stale = !(_key in _live);
        private _timedOut = _state isEqualTo "MOVING" && {
            (time - _since) > ITW_CLASH_FOBAirDefenceTimeout
        };
        if (_gone || {_stale} || {_timedOut}) then {
            if (!_gone) then {
                [_group,if (_stale) then {"fob-lost"} else {"walk-timed-out"}] call
                    ITW_CLASH_FOBAirDefence_fnc_Release;
            };
            _assignments deleteAt _key;
        };
    } forEach (keys _assignments);

    // Walk in progress: hand over on arrival, writing the new state into the
    // live entry.
    {
        private _entry = _assignments getOrDefault [_x,[]];
        if (_entry isEqualTo []) then {continue};
        _entry params ["_group","_position","_state"];
        if (_state isNotEqualTo "MOVING") then {continue};
        private _leader = leader _group;
        if (isNull _leader) then {continue};
        if ((getPosATL (vehicle _leader)) distance2D _position > ITW_CLASH_FOBAirDefenceArrival) then {continue};
        if ([_hq,_group,_position] call ITW_CLASH_FOBAirDefence_fnc_HandOver) then {
            _entry set [2,"GARRISONED"];
            _entry set [3,time];
        };
    } forEach (keys _assignments);

    // Fill an empty FOB with the nearest idle AA squad.
    private _candidates = [_hq] call ITW_CLASH_FOBAirDefence_fnc_Candidates;
    {
        private _position = _x;
        private _key = [_position] call ITW_CLASH_FOBAirDefence_fnc_FOBKey;
        if ((_assignments getOrDefault [_key,[]]) isNotEqualTo []) then {continue};
        if (_candidates isEqualTo []) then {continue};
        private _sorted = [_candidates,[],{
            (getPosATL (vehicle (leader _x))) distance2D _position
        },"ASCEND"] call BIS_fnc_sortBy;
        private _group = _sorted#0;
        _candidates = _candidates - [_group];
        if ([_hq,_group,_position] call ITW_CLASH_FOBAirDefence_fnc_Send) then {
            _assignments set [_key,[_group,+_position,"MOVING",time]];
        };
    } forEach _fobs;
    true
};

[] spawn {
    scriptName "ITW_CLASH_FOBAirDefence";
    waitUntil {
        sleep 1;
        (
            !isNil "ITW_CLASH_fnc_GetCommanderForSide"
            && {missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false]}
        ) || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_FOBAirDefenceEnabled) then {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            {
                private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
                if (!isNull _hq) then {
                    [_hq] call ITW_CLASH_FOBAirDefence_fnc_Maintain;
                };
            } forEach _sides;
        };
        sleep ITW_CLASH_FOBAirDefencePoll;
    };
};

ITW_CLASH_FOBAirDefenceReady = true;
diag_log format [
    "CLASH BOOT | fob-air-defence-ready | version=%1 perFOB=1 arrival=%2 includeRear=%3 poll=%4 garrisonOwner=HAL halFilesUntouched=true",
    ITW_CLASH_FOBAirDefenceVersion,
    ITW_CLASH_FOBAirDefenceArrival,
    ITW_CLASH_FOBAirDefenceIncludeRear,
    ITW_CLASH_FOBAirDefencePoll
];
true
