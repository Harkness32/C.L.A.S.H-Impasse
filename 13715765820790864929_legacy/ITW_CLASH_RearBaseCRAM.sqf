#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_AirPicture_fnc_ClassProfile") exitWith {
    diag_log "CLASH BOOT | WARNING | rear-base-cram-classification-missing | no rear-base air defence";
    false
};

ITW_CLASH_RearBaseCRAMStarted = true;
ITW_CLASH_RearBaseCRAMVersion = 1;
ITW_CLASH_RearBaseCRAMReady = false;

/*
    Rear-base C-RAM.

    One static air defence piece at each side's rear base, outside HAL and
    unbilled. It exists to make one specific thing true: an enemy aircraft
    circling a side's rear base should not be what makes that commander buy a
    fighter. Counter-air coverage already counts a C-RAM at weight 1.0 inside a
    3 km umbrella (ITW_CLASH_AirPicture.sqf), so once this stands, a jet over the
    rear is covered and the demand does not open; the moment it moves over the
    front it leaves the umbrella and the demand opens normally.

    It is also the readable half of the air war for players: rear bases are
    no-go for air, about 3 km around each side's rear base only - a fixed and
    learnable danger zone rather than a map-wide no-fly rule.

    Deliberately:
      - No Impasse ticket is spent and no ITW_VehDef is stamped. It is furniture,
        not a purchase, and it must not count against anything.
      - It is never registered with HAL and never enters a dispatch pool. HAL
        does not employ it and cannot send it anywhere.
      - It is destructible. Players who want the rear opened up can open it, and
        it comes back five minutes later.
      - The class comes from the side's own faction, discovered by Impasse's own
        static-AA scan (VehicleArrays.sqf: va_pStaticAAClasses /
        va_eStaticAAClasses), preferring a radar piece. No hard-coded class, so
        a modded faction gets its own.
*/

ITW_CLASH_RearBaseCRAMEnabled = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMEnabled",true];
ITW_CLASH_RearBaseCRAMPoll = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMPoll",30];
// Replaced five minutes after it is destroyed, per the decided rule.
ITW_CLASH_RearBaseCRAMRespawn = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMRespawn",300];
// Placed off the rear spawn point so it never blocks Impasse's own vehicle
// spawning, but well inside the base.
ITW_CLASH_RearBaseCRAMOffset = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMOffset",80];
// Host override, per side, when a specific piece is wanted. Empty means
// discover it from the faction.
ITW_CLASH_RearBaseCRAMPlayerClass = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMPlayerClass",""];
ITW_CLASH_RearBaseCRAMEnemyClass = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMEnemyClass",""];

// sideKey -> [vehicle, group, destroyedAt, position]
ITW_CLASH_RearBaseCRAMs = createHashMap;

ITW_CLASH_RearBaseCRAM_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["rear-cram-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH REAR CRAM | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["rear-cram",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

/*
    The side's own best static air defence. Impasse already walks each faction's
    config for StaticAAWeapon classes, so this is a preference over a list that
    exists rather than a new class list: a radar piece first (a real C-RAM or SAM
    site), then anything that can shoot at aircraft.
*/
ITW_CLASH_RearBaseCRAM_fnc_SelectClass = {
    params ["_side"];
    private _friendly = !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide};
    private _override = if (_friendly) then {
        ITW_CLASH_RearBaseCRAMPlayerClass
    } else {
        ITW_CLASH_RearBaseCRAMEnemyClass
    };
    if (_override isNotEqualTo "" && {isClass (configFile >> "CfgVehicles" >> _override)}) exitWith {
        _override
    };

    private _pool = if (_friendly) then {
        missionNamespace getVariable ["va_pStaticAAClasses",[]]
    } else {
        missionNamespace getVariable ["va_eStaticAAClasses",[]]
    };
    private _classes = (_pool apply {
        [_x] call ITW_CLASH_Generation_fnc_NormalizeClass
    }) select {
        _x isEqualType "" && {_x isNotEqualTo ""} && {isClass (configFile >> "CfgVehicles" >> _x)}
    };
    if (_classes isEqualTo []) exitWith {""};

    private _radar = _classes select {
        ([_x] call ITW_CLASH_AirPicture_fnc_ClassProfile) get "radar"
    };
    if (_radar isNotEqualTo []) exitWith {_radar#0};
    _classes#0
};

// The rear base for this side, off Impasse's own base graph - the same node an
// ETB ground purchase stages at.
ITW_CLASH_RearBaseCRAM_fnc_RearPosition = {
    params ["_side"];
    if (isNil "ITW_CLASH_Generation_fnc_Resolve") exitWith {[]};
    private _generation = [_side,"SPAA","REAR",[]] call ITW_CLASH_Generation_fnc_Resolve;
    if ((_generation getOrDefault ["status",""]) isNotEqualTo "RESOLVED") exitWith {[]};
    private _rear = +(_generation getOrDefault ["rearPosition",[]]);
    if (_rear isEqualTo []) exitWith {[]};
    if (count _rear < 3) then {_rear pushBack 0};

    // Off the spawn point, so Impasse's own vehicle spawning is never blocked.
    private _position = [
        _rear,ITW_CLASH_RearBaseCRAMOffset,ITW_CLASH_RearBaseCRAMOffset * 2,
        6,0,0.35,0
    ] call BIS_fnc_findSafePos;
    if (_position isEqualTo [] || {_position isEqualTo [0]}) then {_position = _rear};
    if (count _position < 3) then {_position pushBack 0};
    _position
};

ITW_CLASH_RearBaseCRAM_fnc_Spawn = {
    params ["_side"];
    private _class = [_side] call ITW_CLASH_RearBaseCRAM_fnc_SelectClass;
    if (_class isEqualTo "") exitWith {
        ["no-candidate",[toUpperANSI str _side]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };
    private _position = [_side] call ITW_CLASH_RearBaseCRAM_fnc_RearPosition;
    if (_position isEqualTo []) exitWith {[]};

    private _veh = createVehicle [_class,_position,[],0,"CAN_COLLIDE"];
    if (isNull _veh) exitWith {
        ["spawn-failed",[toUpperANSI str _side,_class]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };
    _veh setVectorUp surfaceNormal (getPosATL _veh);

    // A static needs someone in the seat. Crew from the side's own faction, in
    // a group of its own that HAL is never told about.
    private _crewTypes = [];
    if (!isNil "ITW_CLASH_Checkbook_fnc_GetCrewTypes") then {
        ([_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes) params [["_crew",[]]];
        _crewTypes = _crew;
    };
    if (_crewTypes isEqualTo []) exitWith {
        deleteVehicle _veh;
        ["no-faction-crew",[toUpperANSI str _side,_class]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };

    private _group = createGroup [_side,true];
    private _gunner = _group createUnit [_crewTypes#0,_position,[],0,"NONE"];
    if (isNull _gunner) exitWith {
        deleteVehicle _veh;
        deleteGroup _group;
        ["no-crew",[toUpperANSI str _side,_class]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };
    _gunner moveInGunner _veh;
    if (isNull (gunner _veh)) exitWith {
        deleteVehicle _gunner;
        deleteVehicle _veh;
        deleteGroup _group;
        ["no-gunner-seat",[toUpperANSI str _side,_class]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };

    // This is what counter-air coverage reads: weight 1.0 inside a 3 km
    // umbrella, ahead of the radar weighting, because a C-RAM's reach is short.
    _veh setVariable ["ITW_CLASH_CRAM",true,true];
    // Furniture, not a purchase: no ITW_VehDef, no ETB asset mark, no HAL
    // registration. Held out of HAL's dispatch pools defensively in case
    // something else tries to adopt the group.
    _group setVariable ["ITW_CLASH_RearBaseCRAM",true];
    _group setBehaviour "COMBAT";
    _group setCombatMode "RED";
    {_gunner disableAI _x} forEach ["PATH","FSM"];
    private _hq = if (isNil "ITW_CLASH_fnc_GetCommanderForSide") then {grpNull} else {
        [_side] call ITW_CLASH_fnc_GetCommanderForSide
    };
    if (!isNull _hq) then {
        {
            private _arr = +(_hq getVariable [_x,[]]);
            _arr pushBackUnique _group;
            _hq setVariable [_x,_arr];
        } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];
    };

    ["placed",[
        toUpperANSI str _side,_class,_position apply {round _x},
        ([_class] call ITW_CLASH_AirPicture_fnc_ClassProfile) get "radar"
    ]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
    [_veh,_group,0,_position]
};

ITW_CLASH_RearBaseCRAM_fnc_Maintain = {
    params ["_side"];
    private _key = toUpperANSI str _side;
    private _entry = ITW_CLASH_RearBaseCRAMs getOrDefault [_key,[]];

    if (_entry isEqualTo []) exitWith {
        private _fresh = [_side] call ITW_CLASH_RearBaseCRAM_fnc_Spawn;
        if (_fresh isNotEqualTo []) then {ITW_CLASH_RearBaseCRAMs set [_key,_fresh]};
        _fresh isNotEqualTo []
    };

    _entry params ["_veh","_group","_destroyedAt","_position"];
    private _dead = isNull _veh || {!alive _veh} || {isNull (gunner _veh)};
    if (!_dead) exitWith {false};

    if (_destroyedAt <= 0) exitWith {
        // Just lost. Leave the wreck where it is - a player who cleared the rear
        // base should be able to see that they did - and start the clock.
        _entry set [2,time];
        ["destroyed",[_key,ITW_CLASH_RearBaseCRAMRespawn]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        false
    };
    if ((time - _destroyedAt) < ITW_CLASH_RearBaseCRAMRespawn) exitWith {false};

    if (!isNull _veh) then {deleteVehicle _veh};
    if (!isNull _group && {units _group isEqualTo []}) then {deleteGroup _group};
    ITW_CLASH_RearBaseCRAMs deleteAt _key;
    private _fresh = [_side] call ITW_CLASH_RearBaseCRAM_fnc_Spawn;
    if (_fresh isNotEqualTo []) then {
        ITW_CLASH_RearBaseCRAMs set [_key,_fresh];
        ["replaced",[_key]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
    };
    _fresh isNotEqualTo []
};

[] spawn {
    scriptName "ITW_CLASH_RearBaseCRAM";
    waitUntil {
        sleep 1;
        (
            !isNil "ITW_PlayerSide" && {!isNil "ITW_EnemySide"}
            && {missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false]}
        ) || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_RearBaseCRAMEnabled) then {
            {
                [_x] call ITW_CLASH_RearBaseCRAM_fnc_Maintain;
            } forEach [ITW_PlayerSide,ITW_EnemySide];
        };
        sleep ITW_CLASH_RearBaseCRAMPoll;
    };
};

ITW_CLASH_RearBaseCRAMReady = true;
diag_log format [
    "CLASH BOOT | rear-base-cram-ready | version=%1 respawn=%2 offset=%3 poll=%4 classSource=faction-static-aa halRegistered=false impasseBilled=false vehDefStamped=false",
    ITW_CLASH_RearBaseCRAMVersion,
    ITW_CLASH_RearBaseCRAMRespawn,
    ITW_CLASH_RearBaseCRAMOffset,
    ITW_CLASH_RearBaseCRAMPoll
];
true
