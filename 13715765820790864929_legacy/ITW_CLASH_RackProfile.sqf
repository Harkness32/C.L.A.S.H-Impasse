#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_RackProfileStarted",false]) exitWith {true};

ITW_CLASH_RackProfileStarted = true;
ITW_CLASH_RackProfileVersion = 1;
ITW_CLASH_RackProfileReady = false;

/*
    What a vehicle can actually shoot, read from what it is carrying now.

    One reader for every C.L.A.S.H. layer that has to know: the HAL helicopter
    attack (ITW_CLASH_HeliAttack.sqf) sizes its orbit from it, and the
    supports guided pass picks its weapon with it. Built from the 2026-10-16
    session with the stub-wing Ghost Hawk (the MH-80 DAP from Game Update
    2.22): its only weapon was DAGR-M, which the AI fires only from 300 m
    (Medium_AI) or 600 m (Far_AI), and HAL held it 15 to 200 m from its
    target. Nothing on that airframe could fire where it was being flown. The
    lesson generalises to any rack on any modlist, so this reads the rack
    instead of knowing airframes.

    Per weapon with rounds left, from the live magazines (pylons included):
      - flags: the ammo's aiAmmoUsageFlags, which is what the AI itself uses
        to pick targets (64 infantry, 128 vehicles, 256 air, 512 armour). The
        DAGR-M's own flags are 64 + 128 and its anti-armour bit sits on its
        submunition, so the parent's flags are read first. A mod that leaves
        them at 0 falls back to the submunition, then to hit and splash.
      - bands: the min and max range of each fire mode the AI can use. Modes
        that reach under 50 m (the 0 to 2 m Burst and LOAL modes) are the
        config's way of keeping a mode for players and are ignored.
      - lock: how it guides. An IR or laser seeker with no manual control
        cannot be fired at infantry: men give no IR return and nobody is
        lasing for a HAL aircraft.
      - aim: FIXED (a pylon, or a gun on the pilot's seat: the airframe has
        to point at the target) or TURRET (a gunner who aims on his own).

    Reads config and live state only. Moves, writes and decides nothing.
*/

// A fire mode the AI can use reaches at least this far.
ITW_CLASH_RackAIModeMinReach = missionNamespace getVariable ["ITW_CLASH_RackAIModeMinReach",50];
// A turret that traverses less than this is a fixed gun for aiming purposes.
ITW_CLASH_RackTurretMinSpan = missionNamespace getVariable ["ITW_CLASH_RackTurretMinSpan",60];
// Margin over a band's inner edge when sizing an orbit.
ITW_CLASH_RackRadiusMargin = missionNamespace getVariable ["ITW_CLASH_RackRadiusMargin",1.2];
ITW_CLASH_RackRadiusMin = missionNamespace getVariable ["ITW_CLASH_RackRadiusMin",250];
ITW_CLASH_RackRadiusMax = missionNamespace getVariable ["ITW_CLASH_RackRadiusMax",1500];

// ammo -> [flags, lock, simulation]
ITW_CLASH_RackAmmoCache = createHashMap;
// weapon -> [[min,max],...]
ITW_CLASH_RackBandCache = createHashMap;
// class|weapons -> true, so a profile is logged once per loadout
ITW_CLASH_RackLogged = createHashMap;

// The targets a type of contact is, as aiAmmoUsageFlags bits.
ITW_CLASH_RackTypeBits = createHashMapFromArray [
    ["INFANTRY",[64]],
    ["VEHICLE",[128]],
    ["ARMOR",[512]],
    // A static weapon is engaged as a light vehicle or as men, whichever the
    // weapon allows.
    ["STATIC",[128,64]]
];

ITW_CLASH_Rack_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["rack-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH RACK | %1 | %2",_event,_payload];
    };
};

// Number or "64 + 128" text, the way configs write it.
ITW_CLASH_Rack_fnc_ConfigFlags = {
    params ["_entry"];
    if (isNumber _entry) exitWith {getNumber _entry};
    if (!isText _entry) exitWith {0};
    private _sum = 0;
    {_sum = _sum + parseNumber _x} forEach ((getText _entry) splitString "+ ");
    _sum
};

ITW_CLASH_Rack_fnc_HasBit = {
    params ["_flags","_bit"];
    ((floor (_flags / _bit)) mod 2) == 1
};

// [flags, lock, simulation] for an ammo class. Cached.
ITW_CLASH_Rack_fnc_Ammo = {
    params ["_ammo"];
    if (_ammo in ITW_CLASH_RackAmmoCache) exitWith {ITW_CLASH_RackAmmoCache get _ammo};
    private _config = configFile >> "CfgAmmo" >> _ammo;
    private _simulation = toLowerANSI getText (_config >> "simulation");
    private _flags = [_config >> "aiAmmoUsageFlags"] call ITW_CLASH_Rack_fnc_ConfigFlags;
    if (_flags <= 0) then {
        private _sub = _config >> "submunitionAmmo";
        if (isText _sub) then {
            _flags = [configFile >> "CfgAmmo" >> getText _sub >> "aiAmmoUsageFlags"] call
                ITW_CLASH_Rack_fnc_ConfigFlags;
        };
    };
    if (_flags <= 0) then {
        // HAL's own autofill test: heavy hit is anti-armour, splash is soft.
        _flags = switch (true) do {
            case (getNumber (_config >> "hit") >= 150): {128 + 512};
            case (getNumber (_config >> "indirectHit") > 0): {64 + 128};
            default {64 + 128};
        };
    };
    private _lock = switch (true) do {
        case (getNumber (_config >> "manualControl") > 0): {"MANUAL"};
        case (getNumber (_config >> "ace_missileguidance" >> "enabled") > 0): {"ACE"};
        case (getNumber (_config >> "irLock") > 0 && {getNumber (_config >> "laserLock") > 0}): {"IR_LASER"};
        case (getNumber (_config >> "irLock") > 0): {"IR"};
        case (getNumber (_config >> "laserLock") > 0): {"LASER"};
        case (getNumber (_config >> "airLock") > 0): {"AIR"};
        default {"NONE"};
    };
    private _result = [_flags,_lock,_simulation];
    ITW_CLASH_RackAmmoCache set [_ammo,_result];
    _result
};

// Ammo the profile never counts as a weapon.
ITW_CLASH_Rack_fnc_IsCountermeasure = {
    params ["_weapon","_simulation"];
    if (_simulation in ["shotcm","shotsmoke","shotsmokex","shotilluminating","laserdesignate","shotnvgmarker"]) exitWith {true};
    (["CMFlareLauncher","SmokeLauncher","Laserdesignator_mounted","CarHorn"] findIf {
        _weapon isKindOf [_x,configFile >> "CfgWeapons"]
    }) >= 0
};

// The AI-usable range bands of a weapon, over all its muzzles. Cached.
ITW_CLASH_Rack_fnc_Bands = {
    params ["_weapon",["_ammo",""]];
    if (_weapon in ITW_CLASH_RackBandCache) exitWith {ITW_CLASH_RackBandCache get _weapon};
    private _config = configFile >> "CfgWeapons" >> _weapon;
    private _bands = [];
    private _muzzles = getArray (_config >> "muzzles");
    if (_muzzles isEqualTo []) then {_muzzles = ["this"]};
    {
        private _muzzle = if (_x isEqualTo "this") then {_config} else {_config >> _x};
        private _modes = getArray (_muzzle >> "modes");
        if (_modes isEqualTo []) then {_modes = ["this"]};
        {
            private _mode = if (_x isEqualTo "this") then {_muzzle} else {_muzzle >> _x};
            private _min = getNumber (_mode >> "minRange");
            private _max = getNumber (_mode >> "maxRange");
            if (_max >= ITW_CLASH_RackAIModeMinReach) then {_bands pushBackUnique [_min max 0,_max]};
        } forEach _modes;
    } forEach _muzzles;
    if (_bands isEqualTo [] && {_ammo isNotEqualTo ""}) then {
        // No AI mode at all: the missile's own lock distances, then a guess.
        private _ammoConfig = configFile >> "CfgAmmo" >> _ammo;
        private _min = getNumber (_ammoConfig >> "missileLockMinDistance");
        private _max = getNumber (_ammoConfig >> "missileLockMaxDistance");
        _bands = if (_max > _min && {_max > 0}) then {[[_min max 0,_max]]} else {[[50,1500]]};
        ["band-fallback",[_weapon,_ammo,_bands]] call ITW_CLASH_Rack_fnc_Log;
    };
    ITW_CLASH_RackBandCache set [_weapon,_bands];
    _bands
};

// The weapon a magazine is loaded in on this turret: its pylon weapon, or the
// turret weapon that takes it (magazine wells included).
ITW_CLASH_Rack_fnc_WeaponFor = {
    params ["_veh","_magazine","_turret"];
    private _weapon = getText (configFile >> "CfgMagazines" >> _magazine >> "pylonWeapon");
    if (_weapon isNotEqualTo "") exitWith {[_weapon,true]};
    private _found = "";
    {
        private _candidate = _x;
        if (
            _magazine in (compatibleMagazines _candidate)
            || {_magazine in getArray (configFile >> "CfgWeapons" >> _candidate >> "magazines")}
        ) exitWith {_found = _candidate};
    } forEach (_veh weaponsTurret _turret);
    [_found,false]
};

ITW_CLASH_Rack_fnc_Aim = {
    params ["_veh","_turret","_pylon"];
    if (_pylon || {_turret isEqualTo [-1]}) exitWith {"FIXED"};
    private _config = [_veh,_turret] call BIS_fnc_turretConfig;
    if (isNull _config) exitWith {"TURRET"};
    private _span = getNumber (_config >> "maxTurn") - getNumber (_config >> "minTurn");
    if (_span < ITW_CLASH_RackTurretMinSpan) exitWith {"FIXED"};
    "TURRET"
};

/*
    The live rack: one entry per weapon and seat with rounds left,
    [weapon, ammo, turret, rounds, flags, bands, lock, aim].
*/
ITW_CLASH_Rack_fnc_Entries = {
    params ["_veh"];
    if (isNull _veh || {!alive _veh}) exitWith {[]};
    private _byKey = createHashMap;
    {
        _x params ["_magazine","_turret",["_rounds",0]];
        if (_rounds <= 0) then {continue};
        private _ammo = getText (configFile >> "CfgMagazines" >> _magazine >> "ammo");
        if (_ammo isEqualTo "") then {continue};
        ([_veh,_magazine,_turret] call ITW_CLASH_Rack_fnc_WeaponFor) params ["_weapon","_pylon"];
        if (_weapon isEqualTo "") then {continue};
        ([_ammo] call ITW_CLASH_Rack_fnc_Ammo) params ["_flags","_lock","_simulation"];
        if ([_weapon,_simulation] call ITW_CLASH_Rack_fnc_IsCountermeasure) then {continue};
        private _key = _weapon + "|" + str _turret;
        private _entry = _byKey getOrDefault [_key,[]];
        if (_entry isEqualTo []) then {
            _byKey set [_key,[
                _weapon,_ammo,_turret,_rounds,_flags,
                [_weapon,_ammo] call ITW_CLASH_Rack_fnc_Bands,
                _lock,
                [_veh,_turret,_pylon] call ITW_CLASH_Rack_fnc_Aim
            ]];
        } else {
            _entry set [3,(_entry#3) + _rounds];
        };
    } forEach (magazinesAllTurrets _veh);
    values _byKey
};

// Can this entry be used against this type of contact?
ITW_CLASH_Rack_fnc_Usable = {
    params ["_entry","_type"];
    _entry params ["","","","_rounds","_flags","","_lock"];
    if (_rounds <= 0) exitWith {false};
    private _bits = ITW_CLASH_RackTypeBits getOrDefault [_type,[]];
    private _bit = _bits findIf {[_flags,_x] call ITW_CLASH_Rack_fnc_HasBit};
    if (_bit < 0) exitWith {false};
    // A seeker needs a return or a spot; men give neither to a HAL aircraft.
    if ((_bits#_bit) == 64 && {!(_lock in ["NONE","MANUAL"])}) exitWith {false};
    true
};

/*
    The orbit for a set of usable entries: the radius whose whole ring sits
    inside the most AI bands, smallest first on a tie, and whether to keep
    moving (a gunner can shoot from the orbit) or hold a station on it (only
    the airframe can aim). On a stepped orbit the closest pass is mid-leg, at
    R x cos(step/2), so that is what has to clear a band's inner edge.

    Returns [radius, mode] or [-1,""] when nothing usable is on the rack.
*/
ITW_CLASH_Rack_fnc_Orbit = {
    params ["_usable",["_step",45]];
    if (_usable isEqualTo []) exitWith {[-1,""]};
    private _inner = cos (_step / 2);
    private _candidates = [];
    {
        {
            _x params ["_min","_max"];
            private _radius = ((_min / _inner) * ITW_CLASH_RackRadiusMargin) max ITW_CLASH_RackRadiusMin;
            if (_radius <= _max) then {_candidates pushBackUnique round _radius};
        } forEach (_x#5);
    } forEach _usable;
    if (_candidates isEqualTo []) then {_candidates = [ITW_CLASH_RackRadiusMin]};
    _candidates sort true;

    private _best = _candidates#0;
    private _bestScore = -1;
    {
        private _radius = _x;
        private _score = {
            ((_x#5) findIf {
                ((_x#0) <= (_radius * _inner)) && {_radius <= (_x#1)}
            }) >= 0
        } count _usable;
        if (_score > _bestScore) then {_bestScore = _score; _best = _radius};
    } forEach _candidates;

    private _radius = (_best max ITW_CLASH_RackRadiusMin) min ITW_CLASH_RackRadiusMax;
    private _mode = if ((_usable findIf {(_x#7) isEqualTo "TURRET"}) >= 0) then {"ORBIT"} else {"STATION"};
    [_radius,_mode]
};

/*
    The whole profile for a flight: entries across its aircraft, and per
    contact type [usable count, radius, mode]. Logged once per class and
    loadout, so a modded rack that reads oddly shows why in the RPT.
*/
ITW_CLASH_Rack_fnc_Profile = {
    params ["_flight",["_step",45]];
    private _entries = [];
    {_entries append ([_x] call ITW_CLASH_Rack_fnc_Entries)} forEach _flight;
    private _types = createHashMap;
    {
        private _type = _x;
        private _usable = _entries select {[_x,_type] call ITW_CLASH_Rack_fnc_Usable};
        ([_usable,_step] call ITW_CLASH_Rack_fnc_Orbit) params ["_radius","_mode"];
        _types set [_type,[count _usable,_radius,_mode]];
    } forEach (keys ITW_CLASH_RackTypeBits);

    private _class = if (_flight isEqualTo []) then {""} else {typeOf (_flight#0)};
    private _signature = _class + "|" + ((_entries apply {_x#0}) joinString ",");
    if !(_signature in ITW_CLASH_RackLogged) then {
        ITW_CLASH_RackLogged set [_signature,true];
        ["profile",[
            _class,
            (_entries select [0,8]) apply {
                [_x#0,_x#4,_x#5,_x#6,_x#7,_x#3]
            },
            (keys _types) apply {[_x] + (_types get _x)}
        ]] call ITW_CLASH_Rack_fnc_Log;
    };
    [_entries,_types]
};

// A guided anti-armour missile: a missile that is flagged for armour, on
// itself or its warhead, and that has a seeker or manual guidance.
ITW_CLASH_Rack_fnc_IsGuidedAntiArmour = {
    params ["_ammo"];
    if (_ammo isEqualTo "") exitWith {false};
    ([_ammo] call ITW_CLASH_Rack_fnc_Ammo) params ["_flags","_lock","_simulation"];
    if (_simulation isNotEqualTo "shotmissile") exitWith {false};
    if (_lock in ["NONE","AIR"]) exitWith {false};
    private _armour = [_flags,512] call ITW_CLASH_Rack_fnc_HasBit;
    if (!_armour) then {
        private _sub = configFile >> "CfgAmmo" >> _ammo >> "submunitionAmmo";
        if (isText _sub) then {
            _armour = [
                [configFile >> "CfgAmmo" >> getText _sub >> "aiAmmoUsageFlags"] call ITW_CLASH_Rack_fnc_ConfigFlags,
                512
            ] call ITW_CLASH_Rack_fnc_HasBit;
        };
    };
    _armour
};

ITW_CLASH_RackProfileReady = true;
diag_log format [
    "CLASH BOOT | rack-profile-ready | version=%1 aiModeMinReach=%2 turretMinSpan=%3 radius=%4-%5 margin=%6 liveLoadout=true observeOnly=true",
    ITW_CLASH_RackProfileVersion,
    ITW_CLASH_RackAIModeMinReach,
    ITW_CLASH_RackTurretMinSpan,
    ITW_CLASH_RackRadiusMin,
    ITW_CLASH_RackRadiusMax,
    ITW_CLASH_RackRadiusMargin
];
true
