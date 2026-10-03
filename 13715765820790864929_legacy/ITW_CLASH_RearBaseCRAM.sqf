#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_AirPicture_fnc_ClassProfile") exitWith {
    diag_log "CLASH BOOT | WARNING | rear-base-cram-classification-missing | no rear-base air defence";
    false
};

ITW_CLASH_RearBaseCRAMStarted = true;
ITW_CLASH_RearBaseCRAMVersion = 2;
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
// Replaced five minutes after the VEHICLE is destroyed, per the decided rule.
// Set to 0 to never replace it: a rear base cleared of air defence then stays
// cleared for the rest of the mission.
//
// This timer is for a destroyed vehicle only. Losing the gunner is not losing
// the emplacement, and used to be treated as though it were - see fnc_Maintain.
ITW_CLASH_RearBaseCRAMRespawn = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMRespawn",300];
// An intact but uncrewed piece is re-crewed in place rather than replaced. The
// bound exists so a piece that cannot be crewed at all - no seat, no faction
// crewman - does not retry for the rest of the mission.
ITW_CLASH_RearBaseCRAMMaxRecrews = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMMaxRecrews",3];
// Placed off the rear spawn point so it never blocks Impasse's own vehicle
// spawning, but well inside the base.
ITW_CLASH_RearBaseCRAMOffset = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMOffset",80];
// Host override, per side, when a specific piece is wanted. Empty means
// discover it from the faction.
ITW_CLASH_RearBaseCRAMPlayerClass = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMPlayerClass",""];
ITW_CLASH_RearBaseCRAMEnemyClass = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMEnemyClass",""];

// sideKey -> [vehicle, group, destroyedAt, position, recrews]
// Sides already told they have nothing to emplace.
ITW_CLASH_RearBaseCRAMSilenced = [];
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

    private _usable = {
        params ["_pool"];
        (_pool apply {
            [_x] call ITW_CLASH_Generation_fnc_NormalizeClass
        }) select {
            _x isEqualType "" && {_x isNotEqualTo ""}
            && {isClass (configFile >> "CfgVehicles" >> _x)}
        }
    };

    private _classes = [
        if (_friendly) then {
            missionNamespace getVariable ["va_pStaticAAClasses",[]]
        } else {
            missionNamespace getVariable ["va_eStaticAAClasses",[]]
        }
    ] call _usable;

    // Most factions field no StaticAAWeapon at all. In a 70 minute run this
    // selection failed on all 134 polls for both sides and the rear bases were
    // never covered once, so a static-only rule is not a rule, it is an
    // outage. Fall back to the faction's own AA vehicle, which is the same
    // substitution Impasse makes for itself at VehicleArrays.sqf:734.
    //
    // It is crewed with a gunner and no driver, exactly as a static is, so it
    // sits where it is placed and cannot be driven off. ITW_CLASH_CRAM keeps
    // the SPAA overwatch sweep from adopting it and walking it to a sector.
    if (_classes isEqualTo []) then {
        _classes = [
            if (_friendly) then {
                missionNamespace getVariable ["va_pAAClasses",[]]
            } else {
                missionNamespace getVariable ["va_eAAClasses",[]]
            }
        ] call _usable;
        if (_classes isNotEqualTo []) then {
            // Parenthesised: "call f get x" does not bind the way it reads.
            if (!isNil "ITW_CLASH_AirPicture_fnc_ClassProfile") then {
                _classes = _classes select {
                    ([_x] call ITW_CLASH_AirPicture_fnc_ClassProfile) get "antiAir"
                };
            };
        };
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

/*
    Put a gunner in the seat, in a group of this side's own.

    Separated from the spawn because an uncrewed piece is re-crewed in place.
    It also matters that this never leaves the vehicle empty on failure: an
    uncrewed vehicle takes its CONFIG side, not the side of whoever placed it,
    so an empty B_APC_Tracked_01_AA_F standing in GUER's rear base reads as a
    BLUFOR asset to everything that asks. On a mission where both factions are
    NATO-equipped - which this one is, GUER's entire order of battle is B_* -
    that is also indistinguishable to the player.

    Returns [group] on success, [] on failure. The caller decides what to do
    with the hull; nothing here deletes the vehicle.
*/
ITW_CLASH_RearBaseCRAM_fnc_Crew = {
    params ["_side","_veh"];
    if (isNull _veh || {!alive _veh}) exitWith {[]};

    private _crewTypes = [];
    if (!isNil "ITW_CLASH_Checkbook_fnc_GetCrewTypes") then {
        ([_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes) params [["_crew",[]]];
        _crewTypes = _crew;
    };
    if (_crewTypes isEqualTo []) exitWith {
        ["no-faction-crew",[toUpperANSI str _side,typeOf _veh]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };

    private _position = getPosATL _veh;
    private _group = createGroup [_side,true];
    private _gunner = _group createUnit [_crewTypes#0,_position,[],0,"NONE"];
    if (isNull _gunner) exitWith {
        deleteGroup _group;
        ["no-crew",[toUpperANSI str _side,typeOf _veh]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };
    _gunner moveInGunner _veh;
    if (isNull (gunner _veh)) exitWith {
        deleteVehicle _gunner;
        deleteGroup _group;
        ["no-gunner-seat",[toUpperANSI str _side,typeOf _veh]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };

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
    [_group]
};

ITW_CLASH_RearBaseCRAM_fnc_Spawn = {
    params ["_side"];
    private _class = [_side] call ITW_CLASH_RearBaseCRAM_fnc_SelectClass;
    if (_class isEqualTo "") exitWith {
        // Once per side. The class pools do not change mid-mission, so this
        // answer will not either: the unfixed version said it 268 times in one
        // run, a third of every line the loud debugger printed.
        private _key = toUpperANSI str _side;
        if !(_key in ITW_CLASH_RearBaseCRAMSilenced) then {
            ITW_CLASH_RearBaseCRAMSilenced pushBack _key;
            ["no-candidate",[_key]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        };
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

    // This is what counter-air coverage reads: weight 1.0 inside a 3 km
    // umbrella, ahead of the radar weighting, because a C-RAM's reach is short.
    _veh setVariable ["ITW_CLASH_CRAM",true,true];

    // A static needs someone in the seat, and an uncrewed hull reads as its
    // config side - so a failure to crew deletes the vehicle rather than
    // leaving a side-ambiguous piece standing in the base.
    private _crewed = [_side,_veh] call ITW_CLASH_RearBaseCRAM_fnc_Crew;
    if (_crewed isEqualTo []) exitWith {
        deleteVehicle _veh;
        []
    };

    ["placed",[
        toUpperANSI str _side,_class,_position apply {round _x},
        ([_class] call ITW_CLASH_AirPicture_fnc_ClassProfile) get "radar"
    ]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
    [_veh,_crewed#0,0,_position,0]
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

    _entry params ["_veh","_group","_destroyedAt","_position",["_recrews",0]];

    /*
        Losing the gunner is not losing the emplacement.

        This used to read

            _dead = isNull _veh || {!alive _veh} || {isNull (gunner _veh)}

        which made killing the crew with small arms mark an intact vehicle as
        destroyed. Five minutes later the replacement path deleted a working
        gun and built a new one - the respawn Hark saw - and in the meantime the
        intact hull stood there uncrewed, which means it read as its CONFIG
        side. GUER's piece is a B_APC_Tracked_01_AA_F because GUER's whole
        order of battle is NATO here, so an uncrewed one is a BLUFOR asset
        sitting in GUER's rear base. One bug, both symptoms.
    */
    if (alive _veh && {isNull (gunner _veh)}) exitWith {
        if (_recrews >= ITW_CLASH_RearBaseCRAMMaxRecrews) exitWith {
            // Cannot be crewed at all. Remove the hull rather than leave a
            // side-ambiguous vehicle standing, and let the destroyed path
            // decide whether anything replaces it.
            ["recrew-exhausted",[_key,_recrews]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
            deleteVehicle _veh;
            _entry set [0,objNull];
            false
        };
        if (!isNull _group && {units _group isEqualTo []}) then {deleteGroup _group};
        private _crewed = [_side,_veh] call ITW_CLASH_RearBaseCRAM_fnc_Crew;
        _entry set [4,_recrews + 1];
        if (_crewed isEqualTo []) exitWith {false};
        _entry set [1,_crewed#0];
        ["recrewed",[_key,typeOf _veh,_recrews + 1]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        true
    };

    if (alive _veh) exitWith {false};

    if (_destroyedAt <= 0) exitWith {
        // Just lost. Leave the wreck where it is - a player who cleared the rear
        // base should be able to see that they did - and start the clock.
        _entry set [2,time];
        ["destroyed",[_key,ITW_CLASH_RearBaseCRAMRespawn]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        false
    };
    // Zero means a rear base cleared of air defence stays cleared.
    if (ITW_CLASH_RearBaseCRAMRespawn <= 0) exitWith {false};
    if ((time - _destroyedAt) < ITW_CLASH_RearBaseCRAMRespawn) exitWith {false};

    if (!isNull _veh) then {deleteVehicle _veh};
    if (!isNull _group && {units _group isEqualTo []}) then {deleteGroup _group};
    ITW_CLASH_RearBaseCRAMs deleteAt _key;
    private _fresh = [_side] call ITW_CLASH_RearBaseCRAM_fnc_Spawn;
    if (_fresh isNotEqualTo []) then {
        // Replaced where the original stood, not wherever the base graph now
        // resolves: re-resolving made a replacement appear at a different base
        // after a zone flip, which reads as the emplacement teleporting.
        _fresh set [3,_position];
        ITW_CLASH_RearBaseCRAMs set [_key,_fresh];
        ["replaced",[_key,_position apply {round _x}]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
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
    "CLASH BOOT | rear-base-cram-ready | version=%1 respawn=%2 offset=%3 poll=%4 classSource=faction-static-aa-then-faction-aa-vehicle halRegistered=false impasseBilled=false vehDefStamped=false gunnerOnly=true maxRecrews=%5 crewLossRecrews=true replaceAtOriginalPosition=true",
    ITW_CLASH_RearBaseCRAMVersion,
    ITW_CLASH_RearBaseCRAMRespawn,
    ITW_CLASH_RearBaseCRAMOffset,
    ITW_CLASH_RearBaseCRAMPoll,
    ITW_CLASH_RearBaseCRAMMaxRecrews
];
true
