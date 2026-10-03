#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SPAAOverwatchStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_AirPicture_fnc_IsSPAA") exitWith {
    diag_log "CLASH BOOT | WARNING | spaa-overwatch-classification-missing | SPAA stays under HAL";
    false
};

ITW_CLASH_SPAAOverwatchStarted = true;
ITW_CLASH_SPAAOverwatchVersion = 1;
ITW_CLASH_SPAAOverwatchReady = false;

/*
    SPAA overwatch: the one exception to "HAL owns employment".

    An air defence vehicle is only worth what it denies. HAL treats one as
    another armored group and sends it forward into an attack, where it dies to
    the ground fight it was never bought for - and in trace 3 that is also why
    two Impasse-spawned Cheetahs could not be counted as counter-air coverage:
    nothing guaranteed they would still be behind the front when the enemy
    helicopters arrived.

    So the doctrine covers EVERY SPAA on a side, not just the ones the ETB
    bought. Impasse spawns Cheetahs and Tigrises of its own, and unless they
    obey the same rule the coverage count cannot trust them and the commander
    buys a third SPAA it does not need.

    The rules:
      - SPAA never enters HAL's attack, flank or recon pools, and HAL never
        sends it anywhere.
      - CLASH places it behind the front, within engagement range of the sector
        where enemy air is operating, and at least a standoff distance from the
        nearest known enemy ground unit.
      - It relocates as the front moves, and only ever withdraws when
        threatened; it never advances into contact.
      - It counts as counter-air coverage only for enemy aircraft inside its
        umbrella, never map-wide. That part is ITW_CLASH_HALThreatCoverage.sqf's
        to count; this file only guarantees the position it counts from.

    It is a slow answer either way: it drives from the rear base, so a CAP jet
    is the fast one where an airport exists. What it buys is permanence.
*/

ITW_CLASH_SPAAOverwatchPoll = missionNamespace getVariable ["ITW_CLASH_SPAAOverwatchPoll",30];
// At least this far from the nearest known enemy ground unit: close enough to
// cover the sector, far enough not to be in the ground fight.
ITW_CLASH_SPAAOverwatchStandoff = missionNamespace getVariable ["ITW_CLASH_SPAAOverwatchStandoff",1500];
// How far behind the front line it sits when there is no air to cover.
ITW_CLASH_SPAAOverwatchDepth = missionNamespace getVariable ["ITW_CLASH_SPAAOverwatchDepth",1200];
// Only move for a real change, or it spends the war driving between positions.
ITW_CLASH_SPAAOverwatchHysteresis = missionNamespace getVariable ["ITW_CLASH_SPAAOverwatchHysteresis",600];
// Threatened: enemy ground this close means withdraw, which is the only
// movement toward anything the doctrine allows it to refuse.
ITW_CLASH_SPAAOverwatchWithdrawAt = missionNamespace getVariable ["ITW_CLASH_SPAAOverwatchWithdrawAt",800];
ITW_CLASH_SPAAOverwatchAdoptImpasse = missionNamespace getVariable ["ITW_CLASH_SPAAOverwatchAdoptImpasse",true];
// How many mobile AA a commander keeps in its back line. One tracks the air
// picture on its own - fnc_Sector re-points it at the nearest known hostile
// aircraft every poll - so a second adds no cover it did not already have, it
// just parks another vehicle. In the first run one commander held two Cheetahs
// while the other held one, and neither of the pair was bought: both came from
// Impasse's own spawner and this sweep adopted every SPAA it found.
//
// Over the cap, a vehicle is left with HAL rather than held. That is a real
// trade - HAL has no SPAA doctrine and will dispatch it as armor - so the cap
// is the dial to raise if the spares are seen dying forward.
ITW_CLASH_SPAAOverwatchMaxPerSide = missionNamespace getVariable [
    "ITW_CLASH_SPAAOverwatchMaxPerSide",1
];
// What HAL itself reveals at: awareness, not a firing solution.
ITW_CLASH_SPAAOverwatchCueLevel = missionNamespace getVariable [
    "ITW_CLASH_SPAAOverwatchCueLevel",2
];

ITW_CLASH_SPAAOverwatchGroups = [];

// What this commander already holds. Counted live rather than tracked, so a
// loss frees the slot at the next sweep with no bookkeeping to go stale.
ITW_CLASH_SPAAOverwatch_fnc_Held = {
    params ["_side"];
    ITW_CLASH_SPAAOverwatchGroups select {
        !isNull _x
        && {side _x isEqualTo _side}
        && {({alive _x} count units _x) > 0}
        && {
            private _veh = vehicle leader _x;
            !isNull _veh && {alive _veh}
        }
    }
};

ITW_CLASH_SPAAOverwatch_fnc_AtCapacity = {
    params ["_side"];
    (count ([_side] call ITW_CLASH_SPAAOverwatch_fnc_Held)) >= ITW_CLASH_SPAAOverwatchMaxPerSide
};

/*
    Cue the gun to the track.

    fnc_Sector points an SPAA at the nearest hostile aircraft the commander
    knows about and fnc_Station drives it there on RED - without ever telling
    the group those aircraft exist. It arrives in the right place, facing the
    right way, having to acquire from scratch.

    The commander's air picture is built from side-wide observation already
    (fnc_Observers asks every living unit on the side), so handing its tracks to
    that side's air defence is the one piece of sharing an air defence network
    is actually for. Level 2, the same as HAL's own Rev.sqf: awareness, not a
    firing solution - range and line of sight still decide whether it shoots.
*/
ITW_CLASH_SPAAOverwatch_fnc_Cue = {
    params ["_hq","_group"];
    if (isNull _hq || {isNull _group}) exitWith {0};
    if (isNil "ITW_CLASH_AirPicture_fnc_Hostiles") exitWith {0};
    private _tracks = ([_hq] call ITW_CLASH_AirPicture_fnc_Hostiles) apply {_x#0};
    _tracks = _tracks select {!isNull _x && {alive _x}};
    if (_tracks isEqualTo []) exitWith {0};
    {
        private _unit = _x;
        {
            _unit reveal [_x,ITW_CLASH_SPAAOverwatchCueLevel];
        } forEach _tracks;
    } forEach ((units _group) select {alive _x});
    count _tracks
};

ITW_CLASH_SPAAOverwatch_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["spaa-overwatch-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH SPAA OVERWATCH | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["spaa-overwatch",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

// Take a group out of every pool HAL dispatches from, and keep it out. This is
// what "HAL never sends it anywhere" means in HAL's own state.
ITW_CLASH_SPAAOverwatch_fnc_Detach = {
    params ["_group","_hq"];
    if (isNull _group || {isNull _hq}) exitWith {false};
    {
        private _pool = (+(_hq getVariable [_x,[]])) - [_group];
        _hq setVariable [_x,_pool];
    } forEach [
        "RydHQ_AttackAv","RydHQ_FlankAv","RydHQ_LArmorG","RydHQ_HArmorG",
        "RydHQ_LArmorATG","RydHQ_CarsG","RydHQ_ReconAv"
    ];
    if (!isNil "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership") then {
        [_group,["NoAttack","NoRecon","NoDef"],true] call
            ITW_CLASH_CommanderParity_fnc_SetConstraintMembership;
    } else {
        {
            private _arr = +(_hq getVariable [_x,[]]);
            _arr pushBackUnique _group;
            _hq setVariable [_x,_arr];
        } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];
    };
    true
};

// Adopt a group into the doctrine. Called by ThreatCoverage for an ETB
// purchase, and by the sweep below for Impasse's own SPAA.
ITW_CLASH_SPAAOverwatch_fnc_Adopt = {
    params ["_group","_hq",["_sector",[]]];
    if (isNull _group || {isNull _hq}) exitWith {false};
    private _veh = vehicle leader _group;
    if (isNull _veh || {!alive _veh}) exitWith {false};
    if !([_veh] call ITW_CLASH_AirPicture_fnc_IsSPAA) exitWith {false};
    // A rear-base C-RAM is an emplacement that happens to be a vehicle. It is
    // crewed with a gunner and no driver so it cannot be driven anywhere, and
    // adopting it would both consume a back-line slot and try to walk it to a
    // sector it can never reach.
    if (_veh getVariable ["ITW_CLASH_CRAM",false]) exitWith {false};
    // Already holding enough. Enforced here rather than at each caller, so the
    // sweep and a purchase cannot disagree about the limit.
    if (
        !(_group in ITW_CLASH_SPAAOverwatchGroups)
        && {[side _hq] call ITW_CLASH_SPAAOverwatch_fnc_AtCapacity}
    ) exitWith {false};

    _group setVariable ["ITW_CLASH_SPAAOverwatch",true];
    _veh setVariable ["ITW_CLASH_SPAAOverwatch",true,true];
    if (_sector isNotEqualTo []) then {
        _group setVariable ["ITW_CLASH_SPAASector",+_sector];
    };
    [_group,_hq] call ITW_CLASH_SPAAOverwatch_fnc_Detach;
    ITW_CLASH_SPAAOverwatchGroups pushBackUnique _group;

    ["adopted",[
        _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,groupId _group,
        if (_sector isEqualTo []) then {[]} else {_sector apply {round _x}}
    ]] call ITW_CLASH_SPAAOverwatch_fnc_Log;
    true
};

// The sector this commander's SPAA should cover: where enemy air is actually
// operating, if the air picture has anything, otherwise the front's own centre.
ITW_CLASH_SPAAOverwatch_fnc_Sector = {
    params ["_hq","_group"];
    private _sector = _group getVariable ["ITW_CLASH_SPAASector",[]];
    private _hostiles = if (isNil "ITW_CLASH_AirPicture_fnc_Hostiles") then {[]} else {
        [_hq] call ITW_CLASH_AirPicture_fnc_Hostiles
    };
    if (_hostiles isNotEqualTo []) exitWith {
        // The nearest known hostile aircraft to where it already stands: an
        // SPAA that chases the furthest contact covers nothing on the way.
        private _leader = leader _group;
        private _from = if (isNull _leader) then {_sector} else {getPosATL (vehicle _leader)};
        private _sorted = [_hostiles,[],{
            if (_from isEqualTo []) then {0} else {(_x#1) distance2D _from}
        },"ASCEND"] call BIS_fnc_sortBy;
        +((_sorted#0)#1)
    };
    if (_sector isNotEqualTo []) exitWith {_sector};
    private _alarm = _hq getVariable ["ITW_CLASH_AirAlarmPosition",[]];
    if (_alarm isNotEqualTo []) exitWith {+_alarm};
    []
};

// Every enemy ground unit this commander knows about, for the standoff.
ITW_CLASH_SPAAOverwatch_fnc_NearestKnownGround = {
    params ["_hq","_position"];
    private _nearest = 1e12;
    {
        private _veh = vehicle _x;
        if (isNull _veh || {!alive _veh} || {_veh isKindOf "Air"}) then {continue};
        private _distance = (getPosATL _veh) distance2D _position;
        if (_distance < _nearest) then {_nearest = _distance};
    } forEach (_hq getVariable ["RydHQ_KnEnemies",[]]);
    _nearest
};

/*
    Where it should stand: behind the front, on the line from the rear base
    toward the sector, as far forward as the standoff allows. Walking back
    along that line rather than sideways keeps it between its own rear and the
    air it is covering, which is where the aircraft will be.
*/
ITW_CLASH_SPAAOverwatch_fnc_Position = {
    params ["_hq","_group","_sector"];
    private _side = side _hq;
    private _rear = [];
    if (!isNil "ITW_CLASH_Generation_fnc_Resolve") then {
        private _generation = [
            _side,"SPAA","REAR",if (_sector isEqualTo []) then {[]} else {_sector}
        ] call ITW_CLASH_Generation_fnc_Resolve;
        if ((_generation getOrDefault ["status",""]) isEqualTo "RESOLVED") then {
            _rear = +(_generation getOrDefault ["rearPosition",[]]);
        };
    };
    if (_rear isEqualTo []) then {
        private _leader = leader _hq;
        if (!isNull _leader) then {_rear = getPosATL _leader};
    };
    if (_rear isEqualTo [] || {_sector isEqualTo []}) exitWith {[]};

    private _distance = _rear distance2D _sector;
    private _direction = _rear getDir _sector;
    // Start just behind the sector and walk back until the standoff holds.
    private _step = 250;
    private _travel = (_distance - ITW_CLASH_SPAAOverwatchDepth) max 0;
    private _position = [];
    while {_travel >= 0 && {_position isEqualTo []}} do {
        private _candidate = _rear getPos [_travel,_direction];
        if (count _candidate < 3) then {_candidate pushBack 0};
        if (
            ([_hq,_candidate] call ITW_CLASH_SPAAOverwatch_fnc_NearestKnownGround)
                >= ITW_CLASH_SPAAOverwatchStandoff
        ) then {
            _position = _candidate;
        };
        _travel = _travel - _step;
    };
    // Nothing on that line clears the standoff: stay at the rear rather than
    // advance into contact.
    if (_position isEqualTo []) then {_position = +_rear};
    if (count _position < 3) then {_position pushBack 0};
    _position
};

ITW_CLASH_SPAAOverwatch_fnc_Station = {
    params ["_hq","_group"];
    if (isNull _group || {({alive _x} count units _group) <= 0}) exitWith {false};
    private _veh = vehicle leader _group;
    if (isNull _veh || {!alive _veh} || {!canMove _veh}) exitWith {false};

    // HAL must not have it back, whatever else happened this cycle.
    [_group,_hq] call ITW_CLASH_SPAAOverwatch_fnc_Detach;

    private _sector = [_hq,_group] call ITW_CLASH_SPAAOverwatch_fnc_Sector;
    private _here = getPosATL _veh;
    private _threatened = ([_hq,_here] call ITW_CLASH_SPAAOverwatch_fnc_NearestKnownGround)
        < ITW_CLASH_SPAAOverwatchWithdrawAt;
    private _target = [_hq,_group,_sector] call ITW_CLASH_SPAAOverwatch_fnc_Position;
    if (_target isEqualTo []) exitWith {false};

    private _station = _group getVariable ["ITW_CLASH_SPAAStation",[]];
    private _moved = _station isEqualTo [] || {
        (_station distance2D _target) > ITW_CLASH_SPAAOverwatchHysteresis
    };
    if (!_moved && {!_threatened}) exitWith {false};
    // Never advance into contact: a new station is only taken when it is no
    // closer to the enemy than standing still, or when we are withdrawing.
    if (!_threatened && {
        ([_hq,_target] call ITW_CLASH_SPAAOverwatch_fnc_NearestKnownGround)
            < ([_hq,_here] call ITW_CLASH_SPAAOverwatch_fnc_NearestKnownGround)
    }) exitWith {false};

    _group setVariable ["ITW_CLASH_SPAAStation",+_target];
    _group setVariable ["Busy" + str _group,false];
    private _waypoints = waypoints _group;
    for "_i" from ((count _waypoints) - 1) to 0 step -1 do {
        deleteWaypoint (_waypoints#_i);
    };
    private _waypoint = _group addWaypoint [_target,0];
    _waypoint setWaypointType "MOVE";
    _waypoint setWaypointBehaviour "AWARE";
    _waypoint setWaypointCombatMode "RED";
    _waypoint setWaypointSpeed "NORMAL";
    _group setCombatMode "RED";
    _group setBehaviour "AWARE";

    private _cued = [_hq,_group] call ITW_CLASH_SPAAOverwatch_fnc_Cue;

    ["stationed",[
        _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,groupId _group,
        _target apply {round _x},
        if (_sector isEqualTo []) then {[]} else {_sector apply {round _x}},
        if (_threatened) then {"withdraw"} else {"relocate"},
        _cued
    ]] call ITW_CLASH_SPAAOverwatch_fnc_Log;
    true
};

// Impasse spawns SPAA of its own and hands it to HAL. The doctrine has to cover
// those too, or the coverage count cannot trust them and the commander buys a
// counter it already has.
ITW_CLASH_SPAAOverwatch_fnc_Sweep = {
    params ["_hq"];
    if (isNull _hq || {!ITW_CLASH_SPAAOverwatchAdoptImpasse}) exitWith {0};
    private _side = side _hq;
    private _adopted = 0;
    private _passed = 0;
    {
        private _group = _x;
        if (_group getVariable ["ITW_CLASH_SPAAOverwatch",false]) then {continue};
        if (((units _group) findIf {isPlayer _x}) >= 0) then {continue};
        private _veh = vehicle leader _group;
        if (isNull _veh || {!alive _veh}) then {continue};
        if !([_veh] call ITW_CLASH_AirPicture_fnc_IsSPAA) then {continue};
        // Only a capacity refusal is over-cap. A C-RAM is refused too, and
        // counting it here reported "over-cap 1, holding 0" - a cap that looked
        // broken when it was the emplacement guard doing its job.
        if ([_group,_hq] call ITW_CLASH_SPAAOverwatch_fnc_Adopt) then {
            _adopted = _adopted + 1;
        } else {
            if (
                !(vehicle leader _group getVariable ["ITW_CLASH_CRAM",false])
                && {[_side] call ITW_CLASH_SPAAOverwatch_fnc_AtCapacity}
            ) then {
                _passed = _passed + 1;
            };
        };
    } forEach (allGroups select {side _x isEqualTo _side});

    // Said once per change, not once per poll: a side that permanently owns a
    // spare would otherwise repeat this every 30 seconds for the whole mission.
    if (_passed != (_hq getVariable ["ITW_CLASH_SPAAOverwatchPassed",-1])) then {
        _hq setVariable ["ITW_CLASH_SPAAOverwatchPassed",_passed];
        if (_passed > 0) then {
            ["over-cap",[
                _hq getVariable ["RydHQ_CodeSign","?"],
                _passed,
                count ([_side] call ITW_CLASH_SPAAOverwatch_fnc_Held),
                ITW_CLASH_SPAAOverwatchMaxPerSide
            ]] call ITW_CLASH_SPAAOverwatch_fnc_Log;
        };
    };
    _adopted
};

[] spawn {
    scriptName "ITW_CLASH_SPAAOverwatch";
    waitUntil {
        sleep 1;
        !isNil "ITW_CLASH_fnc_GetCommanderForSide" || {
            missionNamespace getVariable ["ITW_GameOver",false]
        }
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        private _sides = [];
        if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
        if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
        {
            private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
            if (!isNull _hq) then {
                [_hq] call ITW_CLASH_SPAAOverwatch_fnc_Sweep;
                {
                    if (side _x isEqualTo (side _hq)) then {
                        [_hq,_x] call ITW_CLASH_SPAAOverwatch_fnc_Station;
                    };
                } forEach ITW_CLASH_SPAAOverwatchGroups;
            };
        } forEach _sides;
        ITW_CLASH_SPAAOverwatchGroups = ITW_CLASH_SPAAOverwatchGroups select {
            !isNull _x && {({alive _x} count units _x) > 0}
        };
        sleep ITW_CLASH_SPAAOverwatchPoll;
    };
};

ITW_CLASH_SPAAOverwatchReady = true;
diag_log format [
    "CLASH BOOT | spaa-overwatch-ready | version=%1 standoff=%2 depth=%3 withdrawAt=%4 poll=%5 adoptImpasseSPAA=%6 maxPerSide=%7 halDispatchPools=none neverAdvances=true",
    ITW_CLASH_SPAAOverwatchVersion,
    ITW_CLASH_SPAAOverwatchStandoff,
    ITW_CLASH_SPAAOverwatchDepth,
    ITW_CLASH_SPAAOverwatchWithdrawAt,
    ITW_CLASH_SPAAOverwatchPoll,
    ITW_CLASH_SPAAOverwatchAdoptImpasse,
    ITW_CLASH_SPAAOverwatchMaxPerSide
];
true
