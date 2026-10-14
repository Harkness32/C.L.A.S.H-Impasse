#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsStrikeStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-strike-core-missing | strike passes not started";
    false
};

ITW_CLASH_SupportsStrikeStarted = true;
ITW_CLASH_SupportsStrikeVersion = 1;
ITW_CLASH_SupportsStrikeReady = false;

/*
    Commander supports: the strike pass. Bomb pass, guided pass and carpet.

    A real aircraft flies every strike. It spawns in flight after the setup
    delay, flies a straight CARELESS line through the aim point, and either
    releases or breaks off. If it dies before releasing, the bombs never fall
    and the money is gone; that is the counterplay.

    Unguided release is timed by ballistic fall time from the jet's height and
    speed, not by a fixed distance, and aimed at the target's LATEST REPORTED
    position, re-read from the knowledge layer just before release. Every bomb
    is given the aircraft as its shooter, so kills are credited to it.

    The guided pass acquires on site. The ground's report brings the jet to the
    area; the jet's own sensors and crew make the kill decision. Nothing valid
    in the scan window: it breaks off, egresses, and the money comes back.
    setMissileTarget is used only as the fallback when fireAtTarget will not
    fire, and only at a target the jet itself acquired.
*/

ITW_CLASH_SupportsStrikeBombClass = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeBombClass","Bo_Mk82"];
ITW_CLASH_SupportsStrikeBombCount = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeBombCount",4];
// Along-track spacing of a bomb pass's stick, metres.
ITW_CLASH_SupportsStrikeBombSpacing = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeBombSpacing",15];
ITW_CLASH_SupportsStrikeHeightBomb = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeHeightBomb",250];
ITW_CLASH_SupportsStrikeHeightCarpet = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeHeightCarpet",400];
ITW_CLASH_SupportsStrikeHeightGuided = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeHeightGuided",600];
ITW_CLASH_SupportsStrikeSpawnSpeed = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeSpawnSpeed",100];
// Carpet: 21 bombs, 15 m apart along track, five lanes 40 m apart across it.
ITW_CLASH_SupportsStrikeCarpetSpacing = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeCarpetSpacing",15];
ITW_CLASH_SupportsStrikeCarpetLane = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeCarpetLane",40];
// A pass more than this wide of the aim at release is not a pass.
ITW_CLASH_SupportsStrikeCrossLimit = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeCrossLimit",250];
ITW_CLASH_SupportsStrikeRunTimeout = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeRunTimeout",180];
ITW_CLASH_SupportsStrikeScanRange = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeScanRange",3000];
ITW_CLASH_SupportsStrikeScanCap = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeScanCap",500];
ITW_CLASH_SupportsStrikeScanMin = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeScanMin",150];
ITW_CLASH_SupportsStrikeScanWindow = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeScanWindow",20];
ITW_CLASH_SupportsStrikeShots = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeShots",2];
// How long after release the effect is measured, for the log only.
ITW_CLASH_SupportsStrikeEffectDelay = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeEffectDelay",15];

ITW_CLASH_SupportsStrikeGuidedClasses = createHashMap;

ITW_CLASH_SupportsStrike_fnc_Log = {
    params ["_event",["_payload",[]]];
    ["strike-" + _event,_payload] call ITW_CLASH_Supports_fnc_Log;
};

// A guided anti-armor missile: a missile whose ammo is flagged for armor.
ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor = {
    params ["_ammo"];
    if (_ammo isEqualTo "") exitWith {false};
    private _config = configFile >> "CfgAmmo" >> _ammo;
    if ((toLowerANSI getText (_config >> "simulation")) isNotEqualTo "shotmissile") exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo") exitWith {
        [_ammo] call ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo
    };
    getNumber (_config >> "airLock") < 2 && {getNumber (_config >> "hit") >= 200}
};

/*
    Can this class fly a guided pass, by its config: class magazines and the
    magazines its default pylons carry. Cached per class.
*/
ITW_CLASH_SupportsStrike_fnc_ClassGuided = {
    params ["_class"];
    if (_class in ITW_CLASH_SupportsStrikeGuidedClasses) exitWith {
        ITW_CLASH_SupportsStrikeGuidedClasses get _class
    };
    private _config = configFile >> "CfgVehicles" >> _class;
    private _magazines = +(getArray (_config >> "magazines"));
    {
        private _attachment = getText (_x >> "attachment");
        if (_attachment isNotEqualTo "") then {_magazines pushBack _attachment};
    } forEach ("isClass _x" configClasses (_config >> "Components" >> "TransportPylonsComponent" >> "Pylons"));
    private _guided = (_magazines findIf {
        [getText (configFile >> "CfgMagazines" >> _x >> "ammo")] call ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor
    }) >= 0;
    ITW_CLASH_SupportsStrikeGuidedClasses set [_class,_guided];
    _guided
};

/*
    The spawned jet's own guided anti-armor weapon with rounds left:
    [weapon, magazine, ammo, turret], or [].
*/
ITW_CLASH_SupportsStrike_fnc_GuidedWeapon = {
    params ["_veh"];
    private _found = [];
    {
        _x params ["_magazine","_turret",["_rounds",0]];
        if (_rounds <= 0) then {continue};
        private _ammo = getText (configFile >> "CfgMagazines" >> _magazine >> "ammo");
        if !([_ammo] call ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor) then {continue};
        private _weapon = getText (configFile >> "CfgMagazines" >> _magazine >> "pylonWeapon");
        if (_weapon isEqualTo "") then {
            {
                if (_magazine in getArray (configFile >> "CfgWeapons" >> _x >> "magazines")) exitWith {_weapon = _x};
            } forEach (_veh weaponsTurret _turret);
        };
        if (_weapon isNotEqualTo "") exitWith {_found = [_weapon,_magazine,_ammo,_turret]};
    } forEach (magazinesAllTurrets _veh);
    _found
};

/*
    How far ahead an unguided bomb released now will land: horizontal speed
    times fall time from the jet's height above the aim, with its vertical
    speed. No drag: the bombs are dumb, and so is the estimate.
*/
ITW_CLASH_SupportsStrike_fnc_Lead = {
    params ["_veh","_aim"];
    private _velocity = velocity _veh;
    private _horizontal = vectorMagnitude [_velocity#0,_velocity#1,0];
    private _height = (((getPosASL _veh)#2) - (getTerrainHeightASL _aim)) max 1;
    private _vz = _velocity#2;
    private _fall = (_vz + sqrt ((_vz * _vz) + (2 * 9.81 * _height))) / 9.81;
    _horizontal * _fall
};

ITW_CLASH_SupportsStrike_fnc_DropBomb = {
    params ["_veh","_lateral"];
    private _position = (getPosASL _veh)
        vectorAdd ((_veh vectorModelToWorld [1,0,0]) vectorMultiply _lateral)
        vectorAdd [0,0,-5];
    private _bomb = createVehicle [ITW_CLASH_SupportsStrikeBombClass,[0,0,2000],[],0,"CAN_COLLIDE"];
    if (isNull _bomb) exitWith {objNull};
    _bomb setPosASL _position;
    _bomb setVectorDirAndUp [vectorDir _veh,vectorUp _veh];
    _bomb setVelocity (velocity _veh);
    _bomb setShotParents [_veh,driver _veh];
    _bomb
};

/*
    The release pattern: [along offset from the aim, lateral offset], sorted so
    the bomb that must leave first is first. A bomb meant to land short of the
    aim is released earlier.
*/
ITW_CLASH_SupportsStrike_fnc_Pattern = {
    params ["_flavor"];
    private _pattern = [];
    if (_flavor isEqualTo "CARPET") then {
        // Antistasi's carpet layout, centred on the aim.
        for "_i" from 0 to 20 do {
            private _side = switch (true) do {
                case (_i < 3): {_i - 1};
                case (_i < 18): {((_i - 3) mod 5) - 2};
                default {_i - 19};
            };
            _pattern pushBack [
                (_i * ITW_CLASH_SupportsStrikeCarpetSpacing) - (10 * ITW_CLASH_SupportsStrikeCarpetSpacing),
                _side * ITW_CLASH_SupportsStrikeCarpetLane
            ];
        };
    } else {
        private _count = ITW_CLASH_SupportsStrikeBombCount max 1;
        for "_i" from 0 to (_count - 1) do {
            _pattern pushBack [(_i - ((_count - 1) / 2)) * ITW_CLASH_SupportsStrikeBombSpacing,0];
        };
    };
    [_pattern,[],{_x#0},"ASCEND"] call BIS_fnc_sortBy
};

// For the log only: how many of the target's entities died after the strike.
ITW_CLASH_SupportsStrike_fnc_Effect = {
    params ["_support","_entities"];
    [_support,_entities] spawn {
        params ["_support","_entities"];
        sleep ITW_CLASH_SupportsStrikeEffectDelay;
        ["effect",[
            _support get "id",_support get "sign",_support get "flavor",
            count _entities,{!alive _x} count _entities
        ]] call ITW_CLASH_SupportsStrike_fnc_Log;
    };
};

ITW_CLASH_SupportsStrike_fnc_UnguidedPass = {
    params ["_support","_veh","_group","_heading"];
    private _side = _support get "side";
    private _keys = (_support get "target") getOrDefault ["keys",[]];
    private _flavor = _support get "flavor";
    private _aim = +(_support get "aim");
    private _pattern = [_flavor] call ITW_CLASH_SupportsStrike_fnc_Pattern;
    private _first = (_pattern#0)#0;
    private _checked = false;
    private _released = 0;
    private _entities = [];
    private _result = [];
    private _deadline = time + ITW_CLASH_SupportsStrikeRunTimeout;
    private _footprint = [_flavor,"footprint",50] call ITW_CLASH_Supports_fnc_RowNumber;

    while {_result isEqualTo []} do {
        sleep 0.02;
        if (!alive _veh || {!canMove _veh} || {isNull driver _veh}) exitWith {
            _result = if (_released > 0) then {
                ["DONE",format ["partial-%1/%2",_released,count _pattern]]
            } else {["LOST","aircraft-lost"]};
        };
        if (time > _deadline) exitWith {
            _result = if (_released > 0) then {
                ["DONE",format ["partial-%1/%2",_released,count _pattern]]
            } else {["BREAKOFF","never-reached"]};
        };
        ([getPosATL _veh,_aim,_heading] call ITW_CLASH_Supports_fnc_AlongCross) params ["_along","_cross"];
        private _lead = [_veh,_aim] call ITW_CLASH_SupportsStrike_fnc_Lead;

        // The release check, once, a few seconds before the first bomb: the
        // latest report, re-aimed; danger close against our people now.
        if (!_checked && {_along <= (_lead - _first + 600)}) then {
            _checked = true;
            ([_side,_keys,0] call ITW_CLASH_Supports_fnc_TargetNow) params ["_now","_r","_alive","_targets"];
            switch (true) do {
                case (_alive == 0): {_result = ["BREAKOFF","TARGET_GONE"]};
                case (_r > ITW_CLASH_SupportsUncertaintyLimit): {_result = ["BREAKOFF","TOO_UNCERTAIN"]};
                case ([[_side] call ITW_CLASH_Supports_fnc_Friendlies,_now,_footprint] call ITW_CLASH_Supports_fnc_DangerClose): {
                    _result = ["BREAKOFF","DANGER_CLOSE"];
                };
                default {
                    ["release-check",[
                        _support get "id",_flavor,round (_aim distance2D _now),round _r,_alive
                    ]] call ITW_CLASH_SupportsStrike_fnc_Log;
                    _aim = _now;
                    _entities = _targets;
                };
            };
        };
        if (_result isNotEqualTo []) exitWith {};
        if (_cross > ITW_CLASH_SupportsStrikeCrossLimit && {_along <= (_lead - _first)}) exitWith {
            _result = if (_released > 0) then {["DONE","partial-wide"]} else {["BREAKOFF","passed-wide"]};
        };

        // Every bomb whose moment has come.
        while {_released < count _pattern && {_along <= (_lead - ((_pattern#_released)#0))}} do {
            [_veh,(_pattern#_released)#1] call ITW_CLASH_SupportsStrike_fnc_DropBomb;
            _released = _released + 1;
        };
        if (_released >= count _pattern) exitWith {_result = ["DONE",format ["released-%1",_released]]};
        // Well past the last release point with bombs left: the line was lost.
        if (_along < (_lead - ((_pattern#((count _pattern) - 1))#0) - 300)) exitWith {
            _result = if (_released > 0) then {["DONE","partial-overflown"]} else {["BREAKOFF","overflown"]};
        };
    };
    if ((_result#0) isEqualTo "DONE") then {
        [_veh,8,0.5] call ITW_CLASH_Supports_fnc_Flares;
        [_support,_entities] call ITW_CLASH_SupportsStrike_fnc_Effect;
        ["released",[
            _support get "id",_support get "sign",_flavor,_released,count _pattern,
            round speed _veh,round ((getPosATL _veh)#2),_result#1
        ]] call ITW_CLASH_SupportsStrike_fnc_Log;
    };
    _result
};

/*
    The guided pass. Inbound with radar on; within scan range, the jet's own
    sensors and its crew's knowledge are searched for enemy vehicles around the
    report, inside a radius sized by how far the target could have moved.
*/
ITW_CLASH_SupportsStrike_fnc_GuidedPass = {
    params ["_support","_veh","_group","_heading"];
    private _side = _support get "side";
    private _hq = _support get "hq";
    private _report = +(_support get "aim");
    private _scanRadius = ((_support getOrDefault ["uncertainty",0]) max ITW_CLASH_SupportsStrikeScanMin)
        min ITW_CLASH_SupportsStrikeScanCap;
    _veh setVehicleRadar 1;

    private _deadline = time + ITW_CLASH_SupportsStrikeRunTimeout;
    waitUntil {
        sleep 0.5;
        !alive _veh
        || {(_veh distance2D _report) <= ITW_CLASH_SupportsStrikeScanRange}
        || {time > _deadline}
    };
    if (!alive _veh || {!canMove _veh}) exitWith {["LOST","aircraft-lost"]};
    if (time > _deadline) exitWith {["BREAKOFF","never-reached"]};

    private _friendlies = [_side] call ITW_CLASH_Supports_fnc_Friendlies;
    private _footprint = [_support get "flavor","footprint",50] call ITW_CLASH_Supports_fnc_RowNumber;
    private _target = objNull;
    private _scanUntil = time + ITW_CLASH_SupportsStrikeScanWindow;
    private _seen = 0;
    while {isNull _target && {time < _scanUntil} && {alive _veh}} do {
        private _pool = [];
        {
            _x params [["_object",objNull],"",["_relationship",""]];
            if (!isNull _object && {_relationship isEqualTo "enemy"}) then {_pool pushBackUnique _object};
        } forEach (getSensorTargets _veh);
        if (!isNull driver _veh) then {
            {_pool pushBackUnique _x} forEach ((driver _veh) targets [true,ITW_CLASH_SupportsStrikeScanRange + 2000]);
        };
        private _valid = _pool select {
            alive _x
            && {_x isKindOf "LandVehicle"}
            && {(_x distance2D _report) <= _scanRadius}
            && {!terrainIntersectASL [getPosASL _veh,(getPosASL _x) vectorAdd [0,0,2]]}
            && {!([_friendlies,getPosATL _x,_footprint] call ITW_CLASH_Supports_fnc_DangerClose)}
            && {!([_hq,[_x]] call ITW_CLASH_Supports_fnc_ETBAnswering)}
        };
        _seen = _seen max (count _pool);
        if (_valid isNotEqualTo []) then {
            _target = ([_valid,[],{_x distance2D _report},"ASCEND"] call BIS_fnc_sortBy)#0;
        } else {
            sleep 1;
        };
    };
    if (!alive _veh || {!canMove _veh}) exitWith {["LOST","aircraft-lost"]};
    if (isNull _target) exitWith {
        ["scan-empty",[_support get "id",_support get "sign",round _scanRadius,_seen]] call
            ITW_CLASH_SupportsStrike_fnc_Log;
        ["BREAKOFF","no-target-found"]
    };

    private _weapon = [_veh] call ITW_CLASH_SupportsStrike_fnc_GuidedWeapon;
    if (_weapon isEqualTo []) exitWith {["BREAKOFF","no-guided-ammo"]};
    _weapon params ["_weaponClass","_magazine","_ammo"];

    _group reveal [_target,4];
    _group setCombatMode "RED";
    private _pilot = driver _veh;
    _pilot enableAI "TARGET";
    _pilot doTarget _target;
    sleep 1;

    private _fired = 0;
    private _fallbacks = 0;
    // setMissileTarget arrived in Arma 2.10.
    private _canSteer = (productVersion param [2,0]) >= 210;
    for "_shot" from 1 to ITW_CLASH_SupportsStrikeShots do {
        if (!alive _veh || {!alive _target}) exitWith {};
        if (_veh fireAtTarget [_target,_weaponClass]) then {
            _fired = _fired + 1;
        } else {
            if (_canSteer) then {
                private _origin = (getPosASL _veh) vectorAdd ((vectorDir _veh) vectorMultiply 8) vectorAdd [0,0,-2];
                private _toward = _origin vectorFromTo (getPosASL _target);
                private _missile = createVehicle [_ammo,[0,0,2000],[],0,"CAN_COLLIDE"];
                if (!isNull _missile) then {
                    _missile setPosASL _origin;
                    _missile setVectorDirAndUp [_toward,[0,0,1]];
                    _missile setVelocity ((velocity _veh) vectorAdd (_toward vectorMultiply 30));
                    _missile setShotParents [_veh,_pilot];
                    _missile setMissileTarget _target;
                    _fired = _fired + 1;
                    _fallbacks = _fallbacks + 1;
                };
            };
        };
        sleep 2;
    };
    _group setCombatMode "BLUE";
    _pilot disableAI "TARGET";
    if (_fired == 0) exitWith {["BREAKOFF","could-not-fire"]};

    [_veh,8,0.5] call ITW_CLASH_Supports_fnc_Flares;
    [_support,[_target]] call ITW_CLASH_SupportsStrike_fnc_Effect;
    ["guided-fired",[
        _support get "id",_support get "sign",typeOf _target,
        round (_target distance2D _report),round _scanRadius,_fired,_fallbacks,_magazine
    ]] call ITW_CLASH_SupportsStrike_fnc_Log;
    ["DONE",format ["fired-%1-fallback-%2",_fired,_fallbacks]]
};

ITW_CLASH_SupportsStrike_fnc_Run = {
    params ["_support"];
    private _side = _support get "side";
    private _flavor = _support get "flavor";
    private _class = _support get "class";
    if (_class isEqualTo "") then {
        _class = ([_side,_flavor] call ITW_CLASH_Supports_fnc_PickClass) param [0,""];
    };
    if (_class isEqualTo "") exitWith {["REVOKED","NO_AIRCRAFT"]};

    private _aim = _support get "aim";
    private _spawn = _support get "spawn";
    private _height = switch (_flavor) do {
        case "CARPET": {ITW_CLASH_SupportsStrikeHeightCarpet};
        case "GUIDED": {ITW_CLASH_SupportsStrikeHeightGuided};
        default {ITW_CLASH_SupportsStrikeHeightBomb};
    };
    private _heading = _spawn getDir _aim;
    private _start = [_spawn#0,_spawn#1,_height];

    ([_support,_class,_start,_heading,ITW_CLASH_SupportsStrikeSpawnSpeed] call
        ITW_CLASH_Supports_fnc_SpawnAircraft) params ["_veh","_group"];
    if (isNull _veh) exitWith {["REVOKED","SPAWN_FAILED"]};
    [_veh] call ITW_CLASH_Supports_fnc_StripAirToAir;

    _veh flyInHeight _height;
    private _floor = (getTerrainHeightASL _aim) + _height;
    _veh flyInHeightASL [_floor,_floor,_floor];
    {deleteWaypoint _x} forEachReversed (waypoints _group);
    private _wp = _group addWaypoint [_aim getPos [3000,_heading],0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 300;

    private _result = if (_flavor isEqualTo "GUIDED") then {
        [_support,_veh,_group,_heading] call ITW_CLASH_SupportsStrike_fnc_GuidedPass
    } else {
        [_support,_veh,_group,_heading] call ITW_CLASH_SupportsStrike_fnc_UnguidedPass
    };
    // A lost aircraft has nothing to egress; anything else flies home and goes.
    [_veh,_group,_aim,_heading] spawn ITW_CLASH_Supports_fnc_Egress;
    _result
};

ITW_CLASH_SupportsStrikeReady = true;
diag_log format [
    "CLASH BOOT | supports-strike-ready | version=%1 bomb=%2x%3 spacing=%4m heights=%5/%6/%7 carpet=21x%8m/%9m lanes crossLimit=%10 scan=%11m cap=%12m window=%13s shots=%14 releaseByFallTime=true reAimAtRelease=true",
    ITW_CLASH_SupportsStrikeVersion,
    ITW_CLASH_SupportsStrikeBombClass,
    ITW_CLASH_SupportsStrikeBombCount,
    ITW_CLASH_SupportsStrikeBombSpacing,
    ITW_CLASH_SupportsStrikeHeightBomb,
    ITW_CLASH_SupportsStrikeHeightCarpet,
    ITW_CLASH_SupportsStrikeHeightGuided,
    ITW_CLASH_SupportsStrikeCarpetSpacing,
    ITW_CLASH_SupportsStrikeCarpetLane,
    ITW_CLASH_SupportsStrikeCrossLimit,
    ITW_CLASH_SupportsStrikeScanRange,
    ITW_CLASH_SupportsStrikeScanCap,
    ITW_CLASH_SupportsStrikeScanWindow,
    ITW_CLASH_SupportsStrikeShots
];
true
