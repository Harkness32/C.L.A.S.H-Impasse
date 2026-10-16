#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsStrikeStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-strike-core-missing | strike passes not started";
    false
};

ITW_CLASH_SupportsStrikeStarted = true;
ITW_CLASH_SupportsStrikeVersion = 3;
ITW_CLASH_SupportsStrikeReady = false;

/*
    Commander supports: the strike pass. Bomb pass, guided pass and carpet.

    A real aircraft flies every strike. It spawns in flight after the setup
    delay, flies a straight CARELESS line through the aim point, and either
    releases or breaks off. If it dies before releasing, the bombs never fall
    and the money is gone; that is the counterplay.

    Unguided release is timed by ballistic fall time from the jet's height and
    speed, and every bomb leaves the aircraft with the aircraft's own velocity,
    so it arcs forward the way a real stick does. Every bomb is given the
    aircraft as its shooter, so kills are credited to it.

    v2, after the audit:
      - The jet lines up on the latest report about 3 km out: the aircraft is
        steered onto the target, never the bombs moved onto it.
      - The final check, a few seconds before the first bomb, re-reads the
        report along the line only; whatever the jet cannot fix by then is a
        physical miss, or a break-off if it is more than the cross limit.
      - Release runs every frame, outside the scheduler, so a busy server can
        no longer make a stick late. Bombs are always created at the aircraft;
        one whose point has already been passed by more than the skip distance
        is not dropped at all.
      - Each bomb's explosion is logged against where the no-drag model said it
        would land and against where the pattern wanted it, with how late it
        left. The first live runs measure drag and timing separately before
        anything is fitted (ITW_CLASH_SupportsStrikeReleaseBias stays 0).
      - The guided pass fires only inside the launch envelope at the moment of
        each shot: range, on the nose, line of sight.

    The guided pass acquires on site. The ground's report brings the jet to the
    area; the jet's own sensors and crew make the kill decision. Nothing valid
    in the scan: it breaks off, egresses, and the money comes back.
    setMissileTarget is used only as the fallback when fireAtTarget will not
    fire, and only at a target the jet itself acquired, inside the envelope.
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
// Distance still to fly when the jet lines up on the latest report.
ITW_CLASH_SupportsStrikeApproachUpdate = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeApproachUpdate",3000];
// The final check happens this far before the first release point.
ITW_CLASH_SupportsStrikeCheckLead = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeCheckLead",600];
// A bomb whose release point the jet has already passed by more than this is
// not dropped: a late bomb is a miss, not a bomb conjured behind the jet.
ITW_CLASH_SupportsStrikeSkipDistance = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeSkipDistance",30];
// Bombs leave this far under the aircraft; the fall time counts from there.
ITW_CLASH_SupportsStrikeDropOffset = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeDropOffset",5];
// Metres added to the computed lead. Positive releases earlier, so bombs land
// shorter. Stays 0 until the impact log has separated drag from timing.
ITW_CLASH_SupportsStrikeReleaseBias = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeReleaseBias",0];
ITW_CLASH_SupportsStrikeImpactLog = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeImpactLog",true];
ITW_CLASH_SupportsStrikeScanRange = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeScanRange",3000];
ITW_CLASH_SupportsStrikeScanCap = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeScanCap",500];
ITW_CLASH_SupportsStrikeScanMin = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeScanMin",150];
ITW_CLASH_SupportsStrikeScanWindow = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeScanWindow",20];
ITW_CLASH_SupportsStrikeShots = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeShots",2];
// Launch envelope. The missile's own lock distances are used when its config
// has them; these are the fallbacks. The cone is half-angle off the nose.
ITW_CLASH_SupportsStrikeMinRange = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeMinRange",800];
ITW_CLASH_SupportsStrikeMaxRange = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeMaxRange",5000];
ITW_CLASH_SupportsStrikeFireCone = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeFireCone",40];
// How long after release the effect is measured, for the log only.
ITW_CLASH_SupportsStrikeEffectDelay = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeEffectDelay",15];

ITW_CLASH_SupportsStrikeGuidedClasses = createHashMap;
// support id -> [bombs, sum model along, sum model cross, sum aim along, sum aim cross]
ITW_CLASH_SupportsStrikeImpacts = createHashMap;
ITW_CLASH_SupportsStrikeTestSerial = 0;

ITW_CLASH_SupportsStrike_fnc_Log = {
    params ["_event",["_payload",[]]];
    ["strike-" + _event,_payload] call ITW_CLASH_Supports_fnc_Log;
};

// A guided anti-armor missile: a missile whose ammo is flagged for armor.
// The rack profile is the one reader for this since v3: it also asks for a
// seeker or manual guidance, so an unguided rocket flagged for armour is no
// longer a "guided" weapon. The body below is its fallback.
ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor = {
    params ["_ammo"];
    if (_ammo isEqualTo "") exitWith {false};
    if (!isNil "ITW_CLASH_Rack_fnc_IsGuidedAntiArmour") exitWith {
        [_ammo] call ITW_CLASH_Rack_fnc_IsGuidedAntiArmour
    };
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
        private _weapon = if (!isNil "ITW_CLASH_Rack_fnc_WeaponFor") then {
            ([_veh,_magazine,_turret] call ITW_CLASH_Rack_fnc_WeaponFor)#0
        } else {
            getText (configFile >> "CfgMagazines" >> _magazine >> "pylonWeapon")
        };
        if (_weapon isEqualTo "") then {
            {
                if (_magazine in getArray (configFile >> "CfgWeapons" >> _x >> "magazines")) exitWith {_weapon = _x};
            } forEach (_veh weaponsTurret _turret);
        };
        if (_weapon isNotEqualTo "") exitWith {_found = [_weapon,_magazine,_ammo,_turret]};
    } forEach (magazinesAllTurrets _veh);
    _found
};

// Time to fall _height metres starting at vertical speed _vz (up positive).
ITW_CLASH_SupportsStrike_fnc_FallTime = {
    params ["_vz","_height"];
    (_vz + sqrt ((_vz * _vz) + (2 * 9.81 * (_height max 1)))) / 9.81
};

/*
    How far ahead an unguided bomb released now will land: horizontal speed
    times fall time from where the bomb leaves (the drop offset under the
    jet) to the aim's height, with the jet's vertical speed. No drag: whether
    the bomb has any is what the impact log is for.
*/
ITW_CLASH_SupportsStrike_fnc_Lead = {
    params ["_veh","_aim"];
    private _velocity = velocity _veh;
    private _horizontal = vectorMagnitude [_velocity#0,_velocity#1,0];
    private _height = ((getPosASL _veh)#2) - ITW_CLASH_SupportsStrikeDropOffset - (getTerrainHeightASL _aim);
    _horizontal * ([_velocity#2,_height] call ITW_CLASH_SupportsStrike_fnc_FallTime)
};

// One waypoint 3 km past the aim on the run heading, replacing the rest.
ITW_CLASH_SupportsStrike_fnc_LineUp = {
    params ["_group","_aim","_heading"];
    {deleteWaypoint _x} forEachReversed (waypoints _group);
    private _wp = _group addWaypoint [_aim getPos [3000,_heading],0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 300;
    _group setCurrentWaypoint _wp;
    _wp
};

/*
    One bomb, created at the aircraft with the aircraft's velocity. With the
    release state given, it also records where the no-drag model says it will
    land and where the pattern wanted it, for the impact log.
*/
ITW_CLASH_SupportsStrike_fnc_DropBomb = {
    params ["_veh","_lateral",["_state",createHashMap],["_index",-1],["_overshoot",0]];
    private _position = (getPosASL _veh)
        vectorAdd ((_veh vectorModelToWorld [1,0,0]) vectorMultiply _lateral)
        vectorAdd [0,0,-ITW_CLASH_SupportsStrikeDropOffset];
    private _bomb = createVehicle [ITW_CLASH_SupportsStrikeBombClass,[0,0,2000],[],0,"CAN_COLLIDE"];
    if (isNull _bomb) exitWith {objNull};
    _bomb setPosASL _position;
    _bomb setVectorDirAndUp [vectorDir _veh,vectorUp _veh];
    private _velocity = velocity _veh;
    _bomb setVelocity _velocity;
    _bomb setShotParents [_veh,driver _veh];

    // Projectile event handlers arrived in Arma 2.10.
    if (
        ITW_CLASH_SupportsStrikeImpactLog
        && {count _state > 0}
        && {_index >= 0}
        && {(productVersion param [2,0]) >= 210}
    ) then {
        private _aim = _state get "aim";
        private _heading = _state get "heading";
        private _offset = ((_state get "pattern")#_index)#0;
        private _fall = [_velocity#2,(_position#2) - (getTerrainHeightASL _aim)] call
            ITW_CLASH_SupportsStrike_fnc_FallTime;
        private _predicted = [(_position#0) + (_velocity#0) * _fall,(_position#1) + (_velocity#1) * _fall];
        private _intended = [
            (_aim#0) + (_offset * sin _heading) + (_lateral * cos _heading),
            (_aim#1) + (_offset * cos _heading) - (_lateral * sin _heading)
        ];
        _bomb setVariable ["ITW_CLASH_SupportsImpact",[
            _state get "id",_index,_predicted,_intended,
            (_velocity#0) atan2 (_velocity#1),_heading,
            round ((_position#2) - (getTerrainHeightASL _aim)),
            vectorMagnitude [_velocity#0,_velocity#1,0],_overshoot
        ]];
        _bomb addEventHandler ["Explode",ITW_CLASH_SupportsStrike_fnc_Impact];
    };
    _bomb
};

/*
    Where a bomb really went off, split along and across: against the no-drag
    model's prediction from its own release (drag and model error only), and
    against the pattern point it was meant for (that, plus how late it left
    and how far off the line the jet was). Log only.
*/
ITW_CLASH_SupportsStrike_fnc_Impact = {
    params ["_projectile","_position"];
    private _impact = _projectile getVariable ["ITW_CLASH_SupportsImpact",[]];
    if (_impact isEqualTo []) exitWith {};
    _impact params ["_id","_index","_predicted","_intended","_track","_heading","_altitude","_speed","_overshoot"];
    private _split = {
        params ["_from","_to","_bearing"];
        private _dx = (_to#0) - (_from#0);
        private _dy = (_to#1) - (_from#1);
        [(_dx * sin _bearing) + (_dy * cos _bearing),(_dx * cos _bearing) - (_dy * sin _bearing)]
    };
    ([_predicted,_position,_track] call _split) params ["_modelAlong","_modelCross"];
    ([_intended,_position,_heading] call _split) params ["_aimAlong","_aimCross"];
    private _stats = ITW_CLASH_SupportsStrikeImpacts getOrDefault [_id,[0,0,0,0,0],true];
    _stats set [0,(_stats#0) + 1];
    _stats set [1,(_stats#1) + _modelAlong];
    _stats set [2,(_stats#2) + _modelCross];
    _stats set [3,(_stats#3) + _aimAlong];
    _stats set [4,(_stats#4) + _aimCross];
    ["impact",[
        _id,_index,round _modelAlong,round _modelCross,round _aimAlong,round _aimCross,
        _altitude,round _speed,(round (_overshoot * 10)) / 10
    ]] call ITW_CLASH_SupportsStrike_fnc_Log;
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

// For the log only: what died, and where the bombs went, after the strike.
ITW_CLASH_SupportsStrike_fnc_Effect = {
    params ["_support","_entities"];
    [_support,_entities] spawn {
        params ["_support","_entities"];
        sleep ITW_CLASH_SupportsStrikeEffectDelay;
        private _id = _support get "id";
        ["effect",[
            _id,_support get "sign",_support get "flavor",
            count _entities,{!alive _x} count _entities
        ]] call ITW_CLASH_SupportsStrike_fnc_Log;
        private _stats = ITW_CLASH_SupportsStrikeImpacts getOrDefault [_id,[]];
        if (_stats isNotEqualTo [] && {(_stats#0) > 0}) then {
            private _n = _stats#0;
            ["impact-summary",[
                _id,_support get "flavor",_n,
                round ((_stats#1) / _n),round ((_stats#2) / _n),
                round ((_stats#3) / _n),round ((_stats#4) / _n)
            ]] call ITW_CLASH_SupportsStrike_fnc_Log;
        };
        ITW_CLASH_SupportsStrikeImpacts deleteAt _id;
    };
};

/*
    The release, run every frame by a mission event handler so the scheduler
    cannot make it late. Every bomb whose moment has come leaves the jet now;
    one whose point is already passed by more than the skip distance stays on
    the rail. Removes itself when the pattern is done or the jet is gone.
*/
ITW_CLASH_SupportsStrike_fnc_ReleaseFrame = {
    private _state = _thisArgs select 0;
    if ((_state get "done") isNotEqualTo "") exitWith {
        removeMissionEventHandler ["EachFrame",_thisEventHandler];
    };
    private _veh = _state get "veh";
    if (!alive _veh || {!canMove _veh} || {isNull driver _veh}) exitWith {
        _state set ["done","lost"];
        removeMissionEventHandler ["EachFrame",_thisEventHandler];
    };
    private _aim = _state get "aim";
    private _pattern = _state get "pattern";
    private _along = ([getPosATL _veh,_aim,_state get "heading"] call ITW_CLASH_Supports_fnc_AlongCross) select 0;
    private _lead = ([_veh,_aim] call ITW_CLASH_SupportsStrike_fnc_Lead) + ITW_CLASH_SupportsStrikeReleaseBias;
    private _next = _state get "next";
    while {_next < count _pattern && {_along <= (_lead - ((_pattern#_next)#0))}} do {
        (_pattern#_next) params ["_offset","_lateral"];
        private _overshoot = (_lead - _offset) - _along;
        if (_overshoot > ITW_CLASH_SupportsStrikeSkipDistance) then {
            _state set ["skipped",(_state get "skipped") + 1];
        } else {
            [_veh,_lateral,_state,_next,_overshoot] call ITW_CLASH_SupportsStrike_fnc_DropBomb;
            _state set ["released",(_state get "released") + 1];
            (_state get "overshoots") pushBack _overshoot;
        };
        _next = _next + 1;
        _state set ["next",_next];
    };
    if (_next >= count _pattern) then {
        _state set ["done","complete"];
        removeMissionEventHandler ["EachFrame",_thisEventHandler];
    };
};

ITW_CLASH_SupportsStrike_fnc_UnguidedPass = {
    params ["_support","_veh","_group","_heading"];
    private _side = _support get "side";
    private _keys = (_support get "target") getOrDefault ["keys",[]];
    private _flavor = _support get "flavor";
    private _test = _support getOrDefault ["test",false];
    private _aim = +(_support get "aim");
    private _pattern = [_flavor] call ITW_CLASH_SupportsStrike_fnc_Pattern;
    private _first = (_pattern#0)#0;
    private _footprint = [_flavor,"footprint",50] call ITW_CLASH_Supports_fnc_RowNumber;
    private _lined = false;
    private _armed = false;
    private _entities = [];
    private _result = [];
    private _deadline = time + ITW_CLASH_SupportsStrikeRunTimeout;

    // The approach, on the scheduler: line up, then the final check.
    while {_result isEqualTo [] && {!_armed}} do {
        sleep 0.1;
        if (!alive _veh || {!canMove _veh} || {isNull driver _veh}) exitWith {_result = ["LOST","aircraft-lost"]};
        if (time > _deadline) exitWith {_result = ["BREAKOFF","never-reached"]};
        ([getPosATL _veh,_aim,_heading] call ITW_CLASH_Supports_fnc_AlongCross) params ["_along","_cross"];
        private _lead = ([_veh,_aim] call ITW_CLASH_SupportsStrike_fnc_Lead) + ITW_CLASH_SupportsStrikeReleaseBias;

        // About 3 km out: the latest report, and the aircraft's line pointed
        // through it. The jet is steered; the bombs are never moved.
        if (!_lined && {_along <= ITW_CLASH_SupportsStrikeApproachUpdate}) then {
            _lined = true;
            if (_test) exitWith {};
            private _ahead = _along / (((speed _veh) / 3.6) max 1);
            ([_side,_keys,_ahead] call ITW_CLASH_Supports_fnc_TargetNow) params ["_now","_r","_alive"];
            switch (true) do {
                case (_alive == 0): {_result = ["BREAKOFF","TARGET_GONE"]};
                case (_r > ITW_CLASH_SupportsUncertaintyLimit): {_result = ["BREAKOFF","TOO_UNCERTAIN"]};
                case ([[_side] call ITW_CLASH_Supports_fnc_Friendlies,_now,_footprint] call ITW_CLASH_Supports_fnc_DangerClose): {
                    _result = ["BREAKOFF","DANGER_CLOSE"];
                };
                default {
                    private _shift = _aim distance2D _now;
                    _aim = _now;
                    _heading = (getPosATL _veh) getDir _aim;
                    [_group,_aim,_heading] call ITW_CLASH_SupportsStrike_fnc_LineUp;
                    _support set ["aim",+_aim];
                    _support set ["heading",_heading];
                    ["lined-up",[_support get "id",_flavor,round _shift,round _r,_alive]] call
                        ITW_CLASH_SupportsStrike_fnc_Log;
                };
            };
        };
        if (_result isNotEqualTo []) exitWith {};

        // A few seconds before the first bomb: the latest report once more and
        // danger close against our people now. The aircraft keeps its line,
        // so only the timing follows the report; what is left off the line is
        // a physical miss, and more than the cross limit is no pass at all.
        if (_along <= (_lead - _first + ITW_CLASH_SupportsStrikeCheckLead)) then {
            if (!_test) then {
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
            private _wide = ([getPosATL _veh,_aim,_heading] call ITW_CLASH_Supports_fnc_AlongCross) select 1;
            if (_wide > ITW_CLASH_SupportsStrikeCrossLimit) exitWith {_result = ["BREAKOFF","passed-wide"]};
            _support set ["aim",+_aim];
            _armed = true;
        };
    };
    if (_result isNotEqualTo []) exitWith {_result};

    // The release itself, every frame.
    private _state = createHashMapFromArray [
        ["id",_support get "id"],["veh",_veh],["aim",+_aim],["heading",_heading],["pattern",_pattern],
        ["next",0],["released",0],["skipped",0],["overshoots",[]],["done",""]
    ];
    private _handler = addMissionEventHandler ["EachFrame",ITW_CLASH_SupportsStrike_fnc_ReleaseFrame,[_state]];
    private _until = time + 60;
    waitUntil {
        sleep 0.2;
        ((_state get "done") isNotEqualTo "") || {time > _until}
    };
    // Unscheduled, so the handler cannot finish and free its index in between.
    isNil {
        if ((_state get "done") isEqualTo "") then {
            removeMissionEventHandler ["EachFrame",_handler];
            _state set ["done","timeout"];
        };
    };

    private _released = _state get "released";
    private _skipped = _state get "skipped";
    private _done = _state get "done";
    _result = switch (true) do {
        case (_released == 0 && {_done isEqualTo "lost"}): {["LOST","aircraft-lost"]};
        case (_released == 0): {["BREAKOFF",format ["nothing-released-%1-skipped-%2",_done,_skipped]]};
        case (_released < count _pattern): {
            ["DONE",format ["partial-%1/%2-skipped-%3-%4",_released,count _pattern,_skipped,_done]]
        };
        default {["DONE",format ["released-%1",_released]]};
    };
    if ((_result#0) isEqualTo "DONE") then {
        private _overshoots = _state get "overshoots";
        private _late = 0;
        {_late = _late + _x} forEach _overshoots;
        [_veh,8,0.5] call ITW_CLASH_Supports_fnc_Flares;
        [_support,_entities] call ITW_CLASH_SupportsStrike_fnc_Effect;
        ["released",[
            _support get "id",_support get "sign",_flavor,_released,count _pattern,_skipped,
            round speed _veh,round ((getPosATL _veh)#2),
            (round ((_late / ((count _overshoots) max 1)) * 10)) / 10,_result#1
        ]] call ITW_CLASH_SupportsStrike_fnc_Log;
    };
    _result
};

// The missile's own lock distances where its config has them.
ITW_CLASH_SupportsStrike_fnc_AmmoRange = {
    params ["_ammo"];
    private _config = configFile >> "CfgAmmo" >> _ammo;
    private _min = getNumber (_config >> "missileLockMinDistance");
    if (_min <= 0) then {_min = ITW_CLASH_SupportsStrikeMinRange};
    private _max = getNumber (_config >> "missileLockMaxDistance");
    if (_max <= 0) then {_max = ITW_CLASH_SupportsStrikeMaxRange};
    [_min,_max max (_min + 100)]
};

// Can this jet launch at this target right now: "" or why not.
ITW_CLASH_SupportsStrike_fnc_Envelope = {
    params ["_veh","_target","_ammo"];
    if (isNull _target || {!alive _target}) exitWith {"TARGET_DEAD"};
    ([_ammo] call ITW_CLASH_SupportsStrike_fnc_AmmoRange) params ["_min","_max"];
    private _range = _veh distance _target;
    if (_range < _min) exitWith {"TOO_CLOSE"};
    if (_range > _max) exitWith {"TOO_FAR"};
    private _relative = _veh getRelDir _target;
    if ((_relative min (360 - _relative)) > ITW_CLASH_SupportsStrikeFireCone) exitWith {"OFF_NOSE"};
    if (terrainIntersectASL [getPosASL _veh,(getPosASL _target) vectorAdd [0,0,2]]) exitWith {"NO_LINE_OF_SIGHT"};
    ""
};

/*
    The guided pass. Inbound with radar on; within scan range, the jet's own
    sensors and its crew's knowledge are searched for enemy vehicles around the
    report, inside a radius sized by how far the target could have moved. A
    target is valid only if it could be launched at right now, and the scan
    ends once the report is inside the missile's minimum range.
*/
ITW_CLASH_SupportsStrike_fnc_GuidedPass = {
    params ["_support","_veh","_group","_heading"];
    private _side = _support get "side";
    private _hq = _support get "hq";
    private _report = +(_support get "aim");
    private _scanRadius = ((_support getOrDefault ["uncertainty",0]) max ITW_CLASH_SupportsStrikeScanMin)
        min ITW_CLASH_SupportsStrikeScanCap;
    _veh setVehicleRadar 1;

    private _weapon = [_veh] call ITW_CLASH_SupportsStrike_fnc_GuidedWeapon;
    if (_weapon isEqualTo []) exitWith {["BREAKOFF","no-guided-ammo"]};
    _weapon params ["_weaponClass","_magazine","_ammo"];
    ([_ammo] call ITW_CLASH_SupportsStrike_fnc_AmmoRange) params ["_minRange"];

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
    private _ended = "window";
    while {isNull _target && {time < _scanUntil} && {alive _veh}} do {
        private _along = ([getPosATL _veh,_report,_heading] call ITW_CLASH_Supports_fnc_AlongCross) select 0;
        if (_along < _minRange) exitWith {_ended = "inside-min-range"};
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
            && {([_veh,_x,_ammo] call ITW_CLASH_SupportsStrike_fnc_Envelope) isEqualTo ""}
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
        ["scan-empty",[_support get "id",_support get "sign",round _scanRadius,_seen,_ended]] call
            ITW_CLASH_SupportsStrike_fnc_Log;
        ["BREAKOFF","no-target-found"]
    };

    _group reveal [_target,4];
    _group setCombatMode "RED";
    private _pilot = driver _veh;
    _pilot enableAI "TARGET";
    _pilot doTarget _target;
    sleep 1;

    private _fired = 0;
    private _fallbacks = 0;
    private _refused = "";
    // setMissileTarget arrived in Arma 2.10.
    private _canSteer = (productVersion param [2,0]) >= 210;
    for "_shot" from 1 to ITW_CLASH_SupportsStrikeShots do {
        if (!alive _veh) exitWith {};
        // The envelope at the instant of each launch, not when it was found.
        _refused = [_veh,_target,_ammo] call ITW_CLASH_SupportsStrike_fnc_Envelope;
        if (_refused isNotEqualTo "") exitWith {};
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
    if (_fired == 0) exitWith {["BREAKOFF",format ["could-not-fire-%1",_refused]]};

    [_veh,8,0.5] call ITW_CLASH_Supports_fnc_Flares;
    [_support,[_target]] call ITW_CLASH_SupportsStrike_fnc_Effect;
    ["guided-fired",[
        _support get "id",_support get "sign",typeOf _target,
        round (_target distance2D _report),round _scanRadius,_fired,_fallbacks,_magazine,_refused
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
    // A console test pass may set its own height and speed.
    if ((_support getOrDefault ["height",-1]) > 0) then {_height = _support get "height"};
    private _kph = _support getOrDefault ["kph",-1];
    private _speed = if (_kph > 0) then {_kph / 3.6} else {ITW_CLASH_SupportsStrikeSpawnSpeed};
    private _heading = _spawn getDir _aim;
    private _start = [_spawn#0,_spawn#1,_height];

    ([_support,_class,_start,_heading,_speed] call
        ITW_CLASH_Supports_fnc_SpawnAircraft) params ["_veh","_group"];
    if (isNull _veh) exitWith {["REVOKED","SPAWN_FAILED"]};
    [_veh] call ITW_CLASH_Supports_fnc_StripAirToAir;
    if (_kph > 0) then {_veh limitSpeed _kph};

    _veh flyInHeight _height;
    private _floor = (getTerrainHeightASL _aim) + _height;
    _veh flyInHeightASL [_floor,_floor,_floor];
    [_group,_aim,_heading] call ITW_CLASH_SupportsStrike_fnc_LineUp;
    _support set ["heading",_heading];

    private _result = if (_flavor isEqualTo "GUIDED") then {
        [_support,_veh,_group,_heading] call ITW_CLASH_SupportsStrike_fnc_GuidedPass
    } else {
        [_support,_veh,_group,_heading] call ITW_CLASH_SupportsStrike_fnc_UnguidedPass
    };
    // On past the target, a turn on the colder side, and home. A lost
    // aircraft is left where it fell.
    [
        _veh,_group,_support get "aim",_support getOrDefault ["heading",_heading],4000,300,_support
    ] spawn ITW_CLASH_Supports_fnc_Egress;
    _result
};

/*
    A strike flown from the debug console, outside the economy: no ledger, no
    lane, no knowledge checks, for calibrating the release against the impact
    log at chosen heights and speeds. Server only. Returns the test id.

        [east, getMarkerPos "target", "BOMB", 250, 90, 500] call
            ITW_CLASH_SupportsStrike_fnc_TestPass;

    Heading is the direction of the run (random if negative); speed in km/h
    limits the jet (its own if negative).
*/
ITW_CLASH_SupportsStrike_fnc_TestPass = {
    params ["_side","_position",["_flavor","BOMB"],["_height",-1],["_heading",-1],["_kph",-1],["_class",""]];
    if (!isServer) exitWith {""};
    if !(_flavor in ITW_CLASH_SupportsStrikeFlavors) exitWith {""};
    if (_class isEqualTo "") then {
        _class = ([_side,_flavor] call ITW_CLASH_Supports_fnc_PickClass) param [0,""];
    };
    if (_class isEqualTo "") exitWith {
        ["test-refused",[_side,_flavor,"no-aircraft"]] call ITW_CLASH_SupportsStrike_fnc_Log;
        ""
    };
    if (_heading < 0) then {_heading = random 360};
    private _aim = [_position#0,_position#1,0];
    private _spawn = _aim getPos [[_flavor] call ITW_CLASH_Supports_fnc_SpawnDistance,_heading + 180];
    ITW_CLASH_SupportsStrikeTestSerial = ITW_CLASH_SupportsStrikeTestSerial + 1;
    private _hq = if (isNil "ITW_CLASH_fnc_GetCommanderForSide") then {grpNull} else {
        [_side] call ITW_CLASH_fnc_GetCommanderForSide
    };
    private _support = createHashMapFromArray [
        ["id",format ["TEST-%1",ITW_CLASH_SupportsStrikeTestSerial]],["side",_side],["hq",_hq],
        ["sign","TEST"],["flavor",_flavor],["routine","STRIKE"],["lane","TEST"],
        ["objective",-1],["reason","TEST"],["aim",_aim],["target",createHashMap],
        ["origin",_spawn],["spawn",_spawn],["corridor","TEST"],["class",_class],
        ["price",0],["state","TEST"],["reservedAt",time],["assets",[]],["groups",[]],
        ["uncertainty",ITW_CLASH_SupportsStrikeScanMin],
        ["test",true],["height",_height],["kph",_kph]
    ];
    ["test-started",[_support get "id",_side,_flavor,_class,_aim apply {round _x},round _heading,_height,_kph]] call
        ITW_CLASH_SupportsStrike_fnc_Log;
    [_support] spawn {
        params ["_support"];
        scriptName "ITW_CLASH_SupportsStrike_TestPass";
        private _outcome = [_support] call ITW_CLASH_SupportsStrike_fnc_Run;
        ["test-outcome",[_support get "id",_support get "flavor",_outcome]] call ITW_CLASH_SupportsStrike_fnc_Log;
    };
    _support get "id"
};

// What the bomb is, by its own config, so the first impact logs can be read
// against it: simulation type and air friction above all.
private _bombConfig = configFile >> "CfgAmmo" >> ITW_CLASH_SupportsStrikeBombClass;
["ammo",[
    ITW_CLASH_SupportsStrikeBombClass,isClass _bombConfig,
    getText (_bombConfig >> "simulation"),
    getNumber (_bombConfig >> "airFriction"),
    getNumber (_bombConfig >> "sideAirFriction"),
    getNumber (_bombConfig >> "maxSpeed"),
    getNumber (_bombConfig >> "thrust"),
    getNumber (_bombConfig >> "thrustTime"),
    getNumber (_bombConfig >> "timeToLive")
]] call ITW_CLASH_SupportsStrike_fnc_Log;

ITW_CLASH_SupportsStrikeReady = true;
diag_log format [
    "CLASH BOOT | supports-strike-ready | version=%1 bomb=%2x%3 spacing=%4m heights=%5/%6/%7 carpet=21x%8m/%9m lanes crossLimit=%10 scan=%11m cap=%12m window=%13s shots=%14 lineUpAt=%15m skip=%16m bias=%17m fireCone=%18 releaseByFallTime=true releaseEachFrame=true bombsAlwaysAtJet=true impactLog=%19",
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
    ITW_CLASH_SupportsStrikeShots,
    ITW_CLASH_SupportsStrikeApproachUpdate,
    ITW_CLASH_SupportsStrikeSkipDistance,
    ITW_CLASH_SupportsStrikeReleaseBias,
    ITW_CLASH_SupportsStrikeFireCone,
    ITW_CLASH_SupportsStrikeImpactLog
];
true
