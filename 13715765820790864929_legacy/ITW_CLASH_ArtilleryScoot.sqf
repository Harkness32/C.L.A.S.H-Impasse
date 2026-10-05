#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ArtilleryScootStarted",false]) exitWith {true};

ITW_CLASH_ArtilleryScootStarted = true;
ITW_CLASH_ArtilleryScootVersion = 2;
ITW_CLASH_ArtilleryScootReady = false;

/*
    Shoot and scoot.

    An AI gun line fires from the same grid square for the whole mission. That
    is free information for anyone who can count: the first salvo tells you
    where the battery is, and it will still be there an hour later. It also
    makes counter-battery trivial and artillery raids a formality.

    This displaces a gun after it has fired, between missions and never during
    one. HAL already counts rounds for us - it puts a Fired handler on every
    artillery piece, but RydHQ_ShotFired2 is per-mission and HAL zeroes it at
    HAC_fnc.sqf:2811, so this module counts rounds itself with its own Fired
    handler (fnc_Watch).

    It is the counterplay to ITW_CLASH_CounterBattery.sqf, and that file is the
    counterplay to this one: a fix is taken on where a gun WAS, and a gun that
    moves survives the raid that fix buys. A gun that sits still does not.

    What it does not do, on the same principle as a committed flight: it never
    changes a mission. It moves a gun that has finished shooting and is waiting
    for the next call, and HAL fires the next mission from wherever the gun now
    stands. A gun mid-mission, a gun a player crews, and a gun HAL has marked
    busy are all left alone.
*/

ITW_CLASH_ArtilleryScootEnabled = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootEnabled",true];
ITW_CLASH_ArtilleryScootPoll = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootPoll",20];
// Rounds a gun may send from one position before it has to move.
ITW_CLASH_ArtilleryScootRounds = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootRounds",6];
// Quiet time that marks the end of a fire mission. Moving mid-mission would
// scatter the salvo and fight HAL's own tasking.
ITW_CLASH_ArtilleryScootSettle = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootSettle",45];
// How far it goes. Far enough that a fix on the old position is useless, near
// enough that it keeps the same targets in range.
ITW_CLASH_ArtilleryScootMin = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootMin",250];
ITW_CLASH_ArtilleryScootMax = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootMax",600];
// Never scoot more often than this, whatever the round count says.
ITW_CLASH_ArtilleryScootCooldown = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootCooldown",240];
// Give up on a move that is not happening and let the gun fire from where it is.
ITW_CLASH_ArtilleryScootTimeout = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootTimeout",300];
// Stay at least this far from the nearest known enemy ground unit.
ITW_CLASH_ArtilleryScootStandoff = missionNamespace getVariable ["ITW_CLASH_ArtilleryScootStandoff",1200];

ITW_CLASH_ArtilleryScoot_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["artillery-scoot-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH ARTILLERY SCOOT | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["artillery-scoot",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

// Every gun this commander owns, from HAL's own artillery pool.
ITW_CLASH_ArtilleryScoot_fnc_Guns = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};
    private _guns = [];
    {
        private _group = _x;
        if (isNull _group) then {continue};
        if (((units _group) findIf {isPlayer _x}) >= 0) then {continue};
        private _veh = vehicle leader _group;
        if (isNull _veh || {!alive _veh} || {!canMove _veh}) then {continue};
        _guns pushBack [_group,_veh];
    } forEach (_hq getVariable ["RydHQ_ArtG",[]]);
    _guns
};

/*
    Has this gun earned a move? It has to have sent enough rounds from where it
    stands, and the mission has to be over - a gun still shooting keeps
    shooting.
*/
/*
    Count the rounds ourselves.

    This module used to read HAL's RydHQ_ShotFired2 as a running total. It is
    not one. HAC_fnc.sqf:2800-2811 fires RydHQ_ShotsToFire rounds, waits for the
    count to reach them or 15s to pass, and then sets it back to ZERO:

        _vh setVariable ["RydHQ_ShotFired2",0];

    It is a per-mission counter, alive for about fifteen seconds. Against it the
    two gates here could never both be true: a move needs six rounds since the
    baseline AND the count unchanged for forty-five seconds, and the only value
    that survives forty-five seconds is the zero HAL just wrote. Every gun
    returned "under-threshold" for the whole mission. Nothing has ever scooted.

    A Fired handler is the honest source: it is monotonic, nobody else resets
    it, and it survives the end of a fire mission, which is exactly the moment
    this module wants to act on. ITW_CLASH_CounterBattery.sqf:183 puts its own
    Fired handler on the same guns for a different purpose; one handler each is
    cheaper than one module reaching into the other's bookkeeping.
*/
ITW_CLASH_ArtilleryScoot_fnc_Watch = {
    params ["_veh"];
    if (isNull _veh || {!alive _veh}) exitWith {false};
    if (_veh getVariable ["ITW_CLASH_ArtilleryScootWatched",false]) exitWith {true};
    _veh setVariable ["ITW_CLASH_ArtilleryScootWatched",true];
    _veh setVariable ["ITW_CLASH_ArtilleryScootFired",0];
    _veh addEventHandler ["Fired",{
        params ["_unit"];
        _unit setVariable [
            "ITW_CLASH_ArtilleryScootFired",
            (_unit getVariable ["ITW_CLASH_ArtilleryScootFired",0]) + 1
        ];
    }];
    ["watching",[typeOf _veh]] call ITW_CLASH_ArtilleryScoot_fnc_Log;
    true
};

ITW_CLASH_ArtilleryScoot_fnc_ShouldMove = {
    params ["_group","_veh"];
    if (_group getVariable ["ITW_CLASH_ArtilleryScootMoving",false]) exitWith {[false,"already-moving"]};
    if (time < (_group getVariable ["ITW_CLASH_ArtilleryScootNextAt",0])) exitWith {[false,"cooldown"]};

    // Our own monotonic count, minus what it had read at the last move. NOT
    // RydHQ_ShotFired2, which HAL zeroes at the end of every fire mission.
    private _total = _veh getVariable ["ITW_CLASH_ArtilleryScootFired",-1];
    if !(_total isEqualType 0) exitWith {[false,"no-counter"]};
    if (_total < 0) exitWith {[false,"not-watched-yet"]};
    private _baseline = _group getVariable ["ITW_CLASH_ArtilleryScootBaseline",0];
    private _since = _total - _baseline;
    if (_since < ITW_CLASH_ArtilleryScootRounds) exitWith {[false,"under-threshold"]};

    // End of mission: the round count has to have stopped climbing.
    private _lastSeen = _group getVariable ["ITW_CLASH_ArtilleryScootSeenTotal",-1];
    private _lastChange = _group getVariable ["ITW_CLASH_ArtilleryScootChangedAt",0];
    if (_total != _lastSeen) exitWith {
        _group setVariable ["ITW_CLASH_ArtilleryScootSeenTotal",_total];
        _group setVariable ["ITW_CLASH_ArtilleryScootChangedAt",time];
        [false,"still-firing"]
    };
    if ((time - _lastChange) < ITW_CLASH_ArtilleryScootSettle) exitWith {[false,"settling"]};
    if (_group getVariable ["Busy" + str _group,false]) exitWith {[false,"hal-busy"]};
    [true,"fired-" + str _since]
};

// Somewhere else nearby, no closer to the enemy, on a road where there is one.
ITW_CLASH_ArtilleryScoot_fnc_NextPosition = {
    params ["_hq","_veh"];
    private _here = getPosATL _veh;
    private _nearestKnown = {
        params ["_position"];
        private _nearest = 1e12;
        {
            private _enemy = vehicle _x;
            if (isNull _enemy || {!alive _enemy} || {_enemy isKindOf "Air"}) then {continue};
            private _distance = (getPosATL _enemy) distance2D _position;
            if (_distance < _nearest) then {_nearest = _distance};
        } forEach (_hq getVariable ["RydHQ_KnEnemies",[]]);
        _nearest
    };
    private _hereSafety = [_here] call _nearestKnown;

    private _best = [];
    for "_attempt" from 1 to 12 do {
        private _distance = ITW_CLASH_ArtilleryScootMin
            + random (ITW_CLASH_ArtilleryScootMax - ITW_CLASH_ArtilleryScootMin);
        private _candidate = _here getPos [_distance,random 360];
        if (count _candidate < 3) then {_candidate pushBack 0};
        private _safety = [_candidate] call _nearestKnown;
        // Never displace toward the enemy, and keep the standoff.
        if (_safety < ITW_CLASH_ArtilleryScootStandoff) then {continue};
        if (_safety < _hereSafety) then {continue};
        if (surfaceIsWater _candidate) then {continue};
        private _roads = _candidate nearRoads 120;
        if (_roads isNotEqualTo []) then {
            _candidate = getPosATL (_roads#0);
            if (count _candidate < 3) then {_candidate pushBack 0};
        };
        _best = _candidate;
    };
    _best
};

ITW_CLASH_ArtilleryScoot_fnc_Move = {
    params ["_hq","_group","_veh","_reason"];
    private _target = [_hq,_veh] call ITW_CLASH_ArtilleryScoot_fnc_NextPosition;
    if (_target isEqualTo []) exitWith {
        // Nowhere better to stand: firing from here beats driving into contact.
        _group setVariable ["ITW_CLASH_ArtilleryScootNextAt",time + ITW_CLASH_ArtilleryScootCooldown];
        ["no-position",[typeOf _veh,groupId _group]] call ITW_CLASH_ArtilleryScoot_fnc_Log;
        false
    };

    private _from = getPosATL _veh;
    _group setVariable ["ITW_CLASH_ArtilleryScootMoving",true];
    _group setVariable ["ITW_CLASH_ArtilleryScootStartedAt",time];
    if (!isNil "RYD_WPdel") then {[_group] call RYD_WPdel};
    private _waypoint = _group addWaypoint [_target,0];
    _waypoint setWaypointType "MOVE";
    _waypoint setWaypointBehaviour "SAFE";
    _waypoint setWaypointSpeed "FULL";
    (leader _group) doMove _target;

    ["displacing",[
        _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,groupId _group,
        _from apply {round _x},_target apply {round _x},
        round (_from distance2D _target),_reason
    ]] call ITW_CLASH_ArtilleryScoot_fnc_Log;
    true
};

// Watch a move to its end, then let the gun be a gun again.
ITW_CLASH_ArtilleryScoot_fnc_Settle = {
    params ["_group","_veh"];
    if !(_group getVariable ["ITW_CLASH_ArtilleryScootMoving",false]) exitWith {false};
    private _startedAt = _group getVariable ["ITW_CLASH_ArtilleryScootStartedAt",0];
    private _arrived = (expectedDestination (leader _group)) param [0,[]];
    private _done = false;
    if (_arrived isEqualType [] && {count _arrived > 2}) then {
        _done = (getPosATL _veh) distance2D _arrived < 60;
    } else {
        _done = true;
    };
    if (!_done && {(time - _startedAt) < ITW_CLASH_ArtilleryScootTimeout}) exitWith {false};

    _group setVariable ["ITW_CLASH_ArtilleryScootMoving",false];
    _group setVariable [
        "ITW_CLASH_ArtilleryScootBaseline",
        _veh getVariable ["ITW_CLASH_ArtilleryScootFired",0]
    ];
    _group setVariable ["ITW_CLASH_ArtilleryScootNextAt",time + ITW_CLASH_ArtilleryScootCooldown];
    _group setVariable ["ITW_CLASH_ArtilleryScootSeenTotal",-1];
    // A new position is a new fire base: tell anyone who was holding a fix.
    _veh setVariable ["ITW_CLASH_ArtilleryMovedAt",time,true];
    if (!isNil "RYD_WPdel") then {[_group] call RYD_WPdel};

    ["in-position",[
        typeOf _veh,groupId _group,(getPosATL _veh) apply {round _x},
        if (_done) then {"arrived"} else {"timed-out"}
    ]] call ITW_CLASH_ArtilleryScoot_fnc_Log;
    true
};

[] spawn {
    scriptName "ITW_CLASH_ArtilleryScoot";
    waitUntil {
        sleep 1;
        !isNil "ITW_CLASH_fnc_GetCommanderForSide" || {
            missionNamespace getVariable ["ITW_GameOver",false]
        }
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_ArtilleryScootEnabled) then {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            {
                private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
                if (!isNull _hq) then {
                    {
                        _x params ["_group","_veh"];
                        [_veh] call ITW_CLASH_ArtilleryScoot_fnc_Watch;
                        if !([_group,_veh] call ITW_CLASH_ArtilleryScoot_fnc_Settle) then {
                            ([_group,_veh] call ITW_CLASH_ArtilleryScoot_fnc_ShouldMove) params [
                                "_should","_reason"
                            ];
                            if (_should) then {
                                [_hq,_group,_veh,_reason] call ITW_CLASH_ArtilleryScoot_fnc_Move;
                            };
                        };
                    } forEach ([_hq] call ITW_CLASH_ArtilleryScoot_fnc_Guns);
                };
            } forEach _sides;
        };
        sleep ITW_CLASH_ArtilleryScootPoll;
    };
};

ITW_CLASH_ArtilleryScootReady = true;
diag_log format [
    "CLASH BOOT | artillery-scoot-ready | version=%1 rounds=%2 settle=%3 range=%4-%5 cooldown=%6 standoff=%7 missionUnchanged=true",
    ITW_CLASH_ArtilleryScootVersion,
    ITW_CLASH_ArtilleryScootRounds,
    ITW_CLASH_ArtilleryScootSettle,
    ITW_CLASH_ArtilleryScootMin,
    ITW_CLASH_ArtilleryScootMax,
    ITW_CLASH_ArtilleryScootCooldown,
    ITW_CLASH_ArtilleryScootStandoff
];
true
