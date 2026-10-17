#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_AirPicture_fnc_ClassProfile") exitWith {
    diag_log "CLASH BOOT | WARNING | rear-base-cram-classification-missing | no rear-base air defence";
    false
};

ITW_CLASH_RearBaseCRAMStarted = true;
ITW_CLASH_RearBaseCRAMVersion = 5;
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

    v4 (Hark, 2026-10-17: "actually implement the actual cram... cram for both
    of us"): neither faction lists a C-RAM, so every run fell back, BLUFOR to a
    Cheetah and GUER to a Titan static. The class is now a real C-RAM first:
    an autonomous static gun, radar-guided, firing guns and no missiles (the
    Praetorian 1C in vanilla; any mod's by the same test), from the side's own
    statics if it has one, else from the game's config, preferring one built
    for the faction's own equipment side. The old ladder stays as the fallback
    for a modset with none at all. An autonomous piece is crewed by its own
    AI joined to a group of the side, the way the support UAVs are.

    v5 (Hark, 2026-10-17, the first v4 run: the same Cheetah and Titan as
    before): v4 found no C-RAM at all. It counted a gun as anti-air only when
    its round's airLock is 2. The Praetorian's, read in that run's console:
    ammo_AAA_Gun35mm_AA, airLock 1, aiAmmoUsageFlags 256, and the piece filed
    as EdSubcat_Turrets. aiAmmoUsageFlags is the engine telling its own AI
    what a round is for, and 256 alone is "air". A C-RAM is now an autonomous
    static, not artillery, with no anti-air missile, whose unguided gun can
    engage aircraft (airLock 1 or 2) and is meant for them: a round used
    against air and nothing on the ground, or airLock 2, or a radar of its
    own, or filed as anti-air. The usage flags are what keep the autonomous
    HMG and GMG turrets out: their rounds are also for infantry and vehicles.
    The scan says once, per candidate, why each autonomous piece was or was
    not taken (rear-cram-cram-scan).
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
// v4: a real C-RAM before any other piece. False goes back to the v3 ladder.
ITW_CLASH_RearBaseCRAMPreferCRAM = missionNamespace getVariable ["ITW_CLASH_RearBaseCRAMPreferCRAM",true];
// v4: the game's C-RAM classes, found once.
ITW_CLASH_RearBaseCRAMClassesFound = nil;

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
/*
    v5. What a round is for, as the engine's own AI reads it: the
    aiAmmoUsageFlags sum (32 infantry, 64 light vehicles, 128 armour,
    256 air), a number or a "64 + 128" string in config.
*/
ITW_CLASH_RearBaseCRAM_fnc_UsageFlags = {
    params ["_ammo"];
    private _entry = configFile >> "CfgAmmo" >> _ammo >> "aiAmmoUsageFlags";
    if (isNumber _entry) exitWith {getNumber _entry};
    private _sum = 0;
    {_sum = _sum + parseNumber _x} forEach ((getText _entry) splitString "+ ");
    _sum
};

/*
    v5. What the class's own guns can do against aircraft, over its unguided
    rounds: [highest airLock (0 cannot, 1 air and ground, 2 air only),
    whether one that can engage aircraft is used against air and nothing on
    the ground].
*/
ITW_CLASH_RearBaseCRAM_fnc_GunAir = {
    params ["_class"];
    private _lock = 0;
    private _airUse = false;
    {
        private _ammo = getText (configFile >> "CfgMagazines" >> _x >> "ammo");
        if (_ammo isEqualTo "" || {[_ammo] call ITW_CLASH_AirPicture_fnc_AmmoIsGuided}) then {continue};
        private _roundLock = getNumber (configFile >> "CfgAmmo" >> _ammo >> "airLock");
        _lock = _lock max _roundLock;
        private _flags = [_ammo] call ITW_CLASH_RearBaseCRAM_fnc_UsageFlags;
        if (_roundLock >= 1 && {((floor (_flags / 256)) mod 2) == 1} && {((floor (_flags / 32)) mod 8) == 0}) then {
            _airUse = true;
        };
    } forEach ([_class] call ITW_CLASH_AirPicture_fnc_ConfigMagazines);
    [_lock,_airUse]
};

/*
    v5. A C-RAM, by what it is rather than what it is called. "" when it is
    one, else why not:
      a public static weapon, autonomous (isUav), not artillery, with no
      anti-air missile (so not a SAM site), whose unguided gun can engage
      aircraft, and that is meant for them: a round the AI uses against air
      and nothing on the ground (the Praetorian's), an air-only round
      (airLock 2), a radar of its own, or filed as anti-air (EdSubcat_AAs).
    The usage flags are what leave out the autonomous HMG and GMG turrets.
*/
ITW_CLASH_RearBaseCRAM_fnc_CRAMWhy = {
    params ["_class"];
    if (!(_class isEqualType "") || {!isClass (configFile >> "CfgVehicles" >> _class)}) exitWith {"no-class"};
    private _config = configFile >> "CfgVehicles" >> _class;
    if (getNumber (_config >> "scope") < 2) exitWith {"not-public"};
    if (getNumber (_config >> "isUav") != 1) exitWith {"not-autonomous"};
    if !(_class isKindOf "StaticWeapon") exitWith {"not-static"};
    if (getNumber (_config >> "artilleryScanner") == 1) exitWith {"artillery"};
    private _profile = [_class] call ITW_CLASH_AirPicture_fnc_ClassProfile;
    if (_profile get "antiAirMissile") exitWith {"missile"};
    ([_class] call ITW_CLASH_RearBaseCRAM_fnc_GunAir) params ["_lock","_airUse"];
    if (_lock < 1) exitWith {"no-air-gun"};
    if (_airUse) exitWith {""};
    if (_lock >= 2) exitWith {""};
    if (_profile get "radar") exitWith {""};
    if ((toLowerANSI getText (_config >> "editorSubcategory")) isEqualTo "edsubcat_aas") exitWith {""};
    "not-built-for-air"
};

ITW_CLASH_RearBaseCRAM_fnc_IsCRAM = {
    params ["_class"];
    ([_class] call ITW_CLASH_RearBaseCRAM_fnc_CRAMWhy) isEqualTo ""
};

/*
    v4. Every C-RAM the game has, radar pieces first. Scanned once.
    v5: says why each autonomous ground piece was or was not taken.
*/
ITW_CLASH_RearBaseCRAM_fnc_CRAMClasses = {
    if (!isNil "ITW_CLASH_RearBaseCRAMClassesFound") exitWith {ITW_CLASH_RearBaseCRAMClassesFound};
    private _candidates = ("getNumber (_x >> 'scope') >= 2 && {getNumber (_x >> 'isUav') == 1}" configClasses (configFile >> "CfgVehicles")) apply {configName _x};
    _candidates = _candidates select {!(_x isKindOf "Air")};
    private _found = [];
    private _scan = [];
    {
        private _why = [_x] call ITW_CLASH_RearBaseCRAM_fnc_CRAMWhy;
        if (_why isEqualTo "") then {_found pushBack _x};
        if ((count _scan) < 40) then {
            _scan pushBack [
                _x,if (_why isEqualTo "") then {"cram"} else {_why},
                if (_why in ["no-class","not-public","not-autonomous","not-static"]) then {[]} else {[_x] call ITW_CLASH_RearBaseCRAM_fnc_GunAir},
                getText (configFile >> "CfgVehicles" >> _x >> "editorSubcategory")
            ];
        };
    } forEach _candidates;
    ["cram-scan",[count _candidates,_scan]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
    private _radar = _found select {([_x] call ITW_CLASH_AirPicture_fnc_ClassProfile) get "radar"};
    ITW_CLASH_RearBaseCRAMClassesFound = _radar + (_found - _radar);
    ["cram-classes",[ITW_CLASH_RearBaseCRAMClassesFound]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
    ITW_CLASH_RearBaseCRAMClassesFound
};

/*
    v4. The side's C-RAM: one of its own statics if it fields one; else one
    built for the side its faction's equipment comes from (GUER here is
    equipped as NATO, so it gets NATO's); else any. "" when the game has none.
*/
ITW_CLASH_RearBaseCRAM_fnc_SelectCRAM = {
    params ["_side","_friendly"];
    private _own = (missionNamespace getVariable [if (_friendly) then {"va_pStaticAAClasses"} else {"va_eStaticAAClasses"},[]]) apply {
        [_x] call ITW_CLASH_Generation_fnc_NormalizeClass
    };
    _own = _own select {[_x] call ITW_CLASH_RearBaseCRAM_fnc_IsCRAM};
    if (_own isNotEqualTo []) exitWith {_own#0};
    private _all = call ITW_CLASH_RearBaseCRAM_fnc_CRAMClasses;
    if (_all isEqualTo []) exitWith {""};
    private _crewTypes = if (isNil "ITW_CLASH_Checkbook_fnc_GetCrewTypes") then {[]} else {
        ([_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes) param [0,[]]
    };
    private _equipmentSide = if (_crewTypes isEqualTo []) then {-1} else {
        getNumber (configFile >> "CfgVehicles" >> (_crewTypes#0) >> "side")
    };
    private _matching = _all select {getNumber (configFile >> "CfgVehicles" >> _x >> "side") == _equipmentSide};
    if (_matching isNotEqualTo []) exitWith {_matching#0};
    _all#0
};

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
    private _cram = if (ITW_CLASH_RearBaseCRAMPreferCRAM) then {
        [_side,_friendly] call ITW_CLASH_RearBaseCRAM_fnc_SelectCRAM
    } else {""};
    if (_cram isNotEqualTo "") exitWith {_cram};

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
/*
    Which of the faction's crew classes mans a static launcher.

    This used to be _crewTypes#0 - whatever the faction list happened to put
    first - and Hark photographed the result: a GUER Mini-Spike emplacement
    manned by a helicopter pilot in a flight helmet.

    Checkbook_fnc_GetCrewTypes asks FactionUnits for role "Crewman"
    (DualHALCheckbook.sqf:1041), and in Arma's own configs a pilot carries
    role = "Crewman" exactly as a vehicle crewman does - both are vehicle
    crew as far as the role taxonomy is concerned. So the list legitimately
    contains pilots, and taking index 0 blindly made the choice a coin flip
    decided by config order. On this faction the pilot sorted first, so EVERY
    emplacement got one, deterministically.

    editorSubcategory is what actually separates them: Arma files pilots under
    EdSubcat_Pilots and crewmen under EdSubcat_Men, and mods overwhelmingly
    follow suit. The classname is checked too, because a mod that sets no
    subcategory usually still says "pilot" in the class.

    Fail-open, and deliberately so: if every candidate looks like a pilot, one
    is used anyway. A pilot in the seat is a cosmetic fault. An uncrewed
    launcher is a real one - it reads as its CONFIG side, which on this
    mission is the bug this whole module exists to prevent.
*/
ITW_CLASH_RearBaseCRAM_fnc_IsPilotClass = {
    params ["_class"];
    if (!(_class isEqualType "") || {_class isEqualTo ""}) exitWith {false};
    private _subcat = toLowerANSI getText (
        configFile >> "CfgVehicles" >> _class >> "editorSubcategory"
    );
    if (_subcat isNotEqualTo "" && {["pilot",_subcat,false] call BIS_fnc_inString}) exitWith {
        true
    };
    ["pilot",toLowerANSI _class,false] call BIS_fnc_inString
};

ITW_CLASH_RearBaseCRAM_fnc_GunnerType = {
    params ["_crewTypes"];
    if (_crewTypes isEqualTo []) exitWith {""};
    private _ground = _crewTypes select {
        !([_x] call ITW_CLASH_RearBaseCRAM_fnc_IsPilotClass)
    };
    if (_ground isNotEqualTo []) exitWith {_ground#0};
    ["pilot-gunner-fallback",[_crewTypes#0,count _crewTypes]] call
        ITW_CLASH_RearBaseCRAM_fnc_Log;
    _crewTypes#0
};

/*
    v4. An autonomous piece (a C-RAM) has no seat a soldier can take: its own
    AI crew is created and joined to a group of this side, as the support
    UAVs are (ITW_CLASH_Supports_fnc_SpawnAircraft). The group then becomes
    what the soldier's group was: ours, never HAL's.
*/
ITW_CLASH_RearBaseCRAM_fnc_CrewAutonomous = {
    params ["_side","_veh"];
    createVehicleCrew _veh;
    private _crew = (crew _veh) select {alive _x};
    if (_crew isEqualTo []) exitWith {
        ["no-crew",[toUpperANSI str _side,typeOf _veh]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };
    private _native = group (_crew#0);
    private _group = createGroup [_side,true];
    _crew joinSilent _group;
    if (!isNull _native && {_native isNotEqualTo _group} && {(units _native) isEqualTo []}) then {deleteGroup _native};
    _veh setVariable ["ITW_CLASH_ForcedSide",_side,true];
    if (isNull (gunner _veh)) exitWith {
        {deleteVehicle _x} forEach _crew;
        deleteGroup _group;
        ["no-gunner-seat",[toUpperANSI str _side,typeOf _veh]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };
    [_side,_group] call ITW_CLASH_RearBaseCRAM_fnc_Settle;
    [_group]
};

// The crew's group: on watch, and on the commander's never-send lists.
ITW_CLASH_RearBaseCRAM_fnc_Settle = {
    params ["_side","_group"];
    _group setVariable ["ITW_CLASH_RearBaseCRAM",true];
    _group setBehaviour "COMBAT";
    _group setCombatMode "RED";
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
};

ITW_CLASH_RearBaseCRAM_fnc_Crew = {
    params ["_side","_veh"];
    if (isNull _veh || {!alive _veh}) exitWith {[]};
    if (getNumber (configOf _veh >> "isUav") == 1) exitWith {[_side,_veh] call ITW_CLASH_RearBaseCRAM_fnc_CrewAutonomous};

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
    private _gunnerType = [_crewTypes] call ITW_CLASH_RearBaseCRAM_fnc_GunnerType;
    private _gunner = _group createUnit [_gunnerType,_position,[],0,"NONE"];
    if (isNull _gunner) exitWith {
        deleteGroup _group;
        ["no-crew",[toUpperANSI str _side,typeOf _veh]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };
    _gunner moveInGunner _veh;
    // Ours now, whatever the config says. Stamped before the seat check so a
    // hull that fails to crew still carries our answer for any reader that
    // looks at it before it is cleaned up.
    _veh setVariable ["ITW_CLASH_ForcedSide",_side,true];
    if (isNull (gunner _veh)) exitWith {
        deleteVehicle _gunner;
        deleteGroup _group;
        ["no-gunner-seat",[toUpperANSI str _side,typeOf _veh]] call ITW_CLASH_RearBaseCRAM_fnc_Log;
        []
    };

    {_gunner disableAI _x} forEach ["PATH","FSM"];
    [_side,_group] call ITW_CLASH_RearBaseCRAM_fnc_Settle;
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
        ([_class] call ITW_CLASH_AirPicture_fnc_ClassProfile) get "radar",
        [_class] call ITW_CLASH_RearBaseCRAM_fnc_IsCRAM
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
    "CLASH BOOT | rear-base-cram-ready | version=%1 respawn=%2 offset=%3 poll=%4 classSource=%6 autonomousCrewJoined=true halRegistered=false impasseBilled=false vehDefStamped=false gunnerOnly=true maxRecrews=%5 crewLossRecrews=true replaceAtOriginalPosition=true",
    ITW_CLASH_RearBaseCRAMVersion,
    ITW_CLASH_RearBaseCRAMRespawn,
    ITW_CLASH_RearBaseCRAMOffset,
    ITW_CLASH_RearBaseCRAMPoll,
    ITW_CLASH_RearBaseCRAMMaxRecrews,
    if (ITW_CLASH_RearBaseCRAMPreferCRAM) then {"cram-then-faction-static-aa-then-faction-aa-vehicle"} else {"faction-static-aa-then-faction-aa-vehicle"}
];
true
