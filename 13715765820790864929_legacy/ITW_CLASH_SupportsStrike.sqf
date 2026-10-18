#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsStrikeStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-strike-core-missing | strike passes not started";
    false
};

ITW_CLASH_SupportsStrikeStarted = true;
ITW_CLASH_SupportsStrikeVersion = 6;
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

    v4: the bomb pass acquires on site too. From the moment it spawns the
    bomber looks, once a second, for something it has acquired itself near
    the report: a track on its own sensors, or a sighting by its own crew
    since the pass began. The ground's contacts are revealed to the crew so
    they know where to look, but a reveal is never a sighting: targetKnowledge
    gives a revealed, unseen target no sighting time, and only a sighting
    time after the pass began counts. The best one by the bomb's class
    weights becomes the aim, led by its own estimated velocity to the moment
    the bombs arrive, and the jet is re-lined onto it while it has run left
    to turn. The release itself is unchanged. Nothing acquired by the final
    check: the report is bombed if it is still good enough (the 300 m limit),
    otherwise the jet breaks off and the money comes back. Carpet and console
    test passes fly the report exactly as before.

    v5, from the first live releases (2026-10-17):
      - The stick landed 250 m to the side: the jet re-lined 2.4 km out at
        200 m/s, never settled on the new line, and the 250 m cross limit let
        it drop anyway. A bomb pass is now held to its footprint (50 m) off
        the line, at the final check and again on the frame the first bomb
        would leave; off by more, nothing is dropped and the money comes back.
        Re-lining needs ITW_CLASH_SupportsStrikeRelineSeconds of flight left
        before the final check, not a distance; the bomb pass is held to
        550 km/h and spawns 6 km out (core) so that time exists.
      - All four bombs landed 112 to 119 m long of the no-drag model, within
        3 m of each other: Arma's Mk82 carries further than a plain drop. The
        lead is scaled by ITW_CLASH_SupportsStrikeReleaseScale (1.08, about
        that 115 m at 196 m/s from 266 m); the impact log still measures
        against the raw model, so the scale can be refitted.
      - A pass that breaks off turns away from the side the target is on,
        from where it is, instead of flying on over it: the A-10 that broke
        off passed 460 m from the Cheetah it was meant to bomb and was lost.
      - Every break-off is logged with its geometry: how far out, how far off
        the line, the line and the track, and how many missiles came at it.
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
// v5: a bomb pass's own limit, its footprint: four bombs 15 m apart do
// nothing 60 m off the line. Carpet keeps the limit above.
ITW_CLASH_SupportsStrikeCrossLimitBomb = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeCrossLimitBomb",50];
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
// v5: the lead times this. Above 1 releases earlier. Fitted from the first
// live stick (2026-10-17): 115 m long at 196 m/s from 266 m, about 8% of the
// lead. Physically it should grow with speed and fall time, so a fraction,
// not metres. Refit from the impact log at other speeds and heights.
ITW_CLASH_SupportsStrikeReleaseScale = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeReleaseScale",1.08];
// v5: a bomb pass is flown no faster than this (km/h), so it has time to
// acquire, and to turn onto what it acquired.
ITW_CLASH_SupportsStrikeBombKph = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeBombKph",550];
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

// v4, the bomb pass's own acquisition.
// How strongly the ground's contacts are revealed to the bomber's crew.
ITW_CLASH_SupportsStrikeRevealValue = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeRevealValue",1.5];
// Seconds between looks.
ITW_CLASH_SupportsStrikeBombScanInterval = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeBombScanInterval",1];
// The jet is re-lined onto an acquired target only with this many seconds of
// flight left before the final check (v5; v4 used 1800 m, which at 200 m/s
// was 2 s), and only when the aim moved more than the shift.
ITW_CLASH_SupportsStrikeRelineSeconds = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeRelineSeconds",10];
ITW_CLASH_SupportsStrikeRelineShift = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeRelineShift",25];
// Velocity from two fixes at least the sample apart and inside the window,
// seconds; the lead never moves the aim further than the cap, metres.
ITW_CLASH_SupportsStrikeLeadSample = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeLeadSample",4];
ITW_CLASH_SupportsStrikeLeadWindow = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeLeadWindow",10];
ITW_CLASH_SupportsStrikeLeadCap = missionNamespace getVariable ["ITW_CLASH_SupportsStrikeLeadCap",250];

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
//
// v6: and it has a motor. Arma simulates a bomb as a missile without thrust
// (Bo_Mk82: shotMissile, thrust 0, thrustTime 0), so a laser or cluster bomb
// with an armour flag passed as a guided missile. On 2026-10-18 the guided
// pass flew the Black Wasp and Wipeout cluster variants and launched their
// CBU-85s with fireAtTarget from missile range, 600 m up: the Rooikat it was
// aimed at lived. The pass fires from standoff, which only a powered round
// can reach; bombs are the bomb pass's.
ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor = {
    params ["_ammo"];
    if (_ammo isEqualTo "") exitWith {false};
    private _motor = configFile >> "CfgAmmo" >> _ammo;
    if ((getNumber (_motor >> "thrust")) <= 0 && {(getNumber (_motor >> "thrustTime")) <= 0}) exitWith {false};
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
    private _found = _magazines findIf {
        [getText (configFile >> "CfgMagazines" >> _x >> "ammo")] call ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor
    };
    private _guided = _found >= 0;
    ITW_CLASH_SupportsStrikeGuidedClasses set [_class,_guided];
    // v6: once per class, which jets can fly the guided pass and with what.
    ["guided-class",[_class,_guided,if (_guided) then {_magazines#_found} else {""}]] call
        ITW_CLASH_SupportsStrike_fnc_Log;
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
    _horizontal * ([_velocity#2,_height] call ITW_CLASH_SupportsStrike_fnc_FallTime) * ITW_CLASH_SupportsStrikeReleaseScale
};

// v5. How far off the line a pass of this flavor may be and still release.
ITW_CLASH_SupportsStrike_fnc_CrossLimit = {
    params ["_flavor"];
    if (_flavor isEqualTo "BOMB") exitWith {ITW_CLASH_SupportsStrikeCrossLimitBomb};
    ITW_CLASH_SupportsStrikeCrossLimit
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
    ([getPosATL _veh,_aim,_state get "heading"] call ITW_CLASH_Supports_fnc_AlongCross) params ["_along","_cross"];
    private _lead = ([_veh,_aim] call ITW_CLASH_SupportsStrike_fnc_Lead) + ITW_CLASH_SupportsStrikeReleaseBias;
    private _next = _state get "next";
    // v5: the line once more, on the frame the first bomb would leave; a jet
    // that drifted off it since the final check drops nothing. The handler
    // goes on the next frame, by the check at the top.
    if (_next == 0 && {_along <= (_lead - ((_pattern#0)#0))} && {_cross > (_state get "crossLimit")}) exitWith {
        _state set ["wide",_cross];
        _state set ["done","wide"];
    };
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

/*
    v4. The crew's own most recent sighting of _object since _since, as
    [position, when, error], or []. Known of is not seen: a target that was
    only revealed to them has no sighting time, so it never passes.
*/
ITW_CLASH_SupportsStrike_fnc_CrewSighting = {
    params ["_veh","_object","_since"];
    private _best = [];
    {
        private _intel = _x targetKnowledge _object;
        if !(_intel isEqualType [] && {count _intel >= 7}) then {continue};
        _intel params ["","","_seen","","","_error","_position"];
        if !(_seen isEqualType 0 && {_seen >= _since} && {_seen <= (time + 1)}) then {continue};
        if !(_position isEqualType [] && {count _position >= 2}) then {continue};
        if (_best isEqualTo [] || {_seen > (_best#1)}) then {
            _best = [[_position#0,_position#1,0],_seen,if (_error isEqualType 0) then {_error max 0} else {0}];
        };
    } forEach ((crew _veh) select {alive _x});
    _best
};

/*
    v4. Where the bomber has _object now, by its own means: [position, when,
    how, error], or []. A track on the jet's own sensors is its measurement
    of the object, so it reads the object; a crew sighting is where the crew
    last saw it, with the engine's own error. A live track wins, being fresher.
*/
ITW_CLASH_SupportsStrike_fnc_BombFix = {
    params ["_veh","_object","_since"];
    if (isNull _object || {!alive _object}) exitWith {[]};
    private _tracked = ((getSensorTargets _veh) findIf {
        ((_x param [0,objNull]) isEqualTo _object) && {(_x param [2,""]) isEqualTo "enemy"}
    }) >= 0;
    if (_tracked) exitWith {
        private _position = getPosATL _object;
        [[_position#0,_position#1,0],time,"SENSOR",0]
    };
    private _sight = [_veh,_object,_since] call ITW_CLASH_SupportsStrike_fnc_CrewSighting;
    if (_sight isEqualTo []) exitWith {[]};
    [_sight#0,_sight#1,"SIGHT",_sight#2]
};

/*
    v4. One look: the best target the bomber has acquired itself near the
    report. Candidates are its sensor tracks and its crew's known enemies;
    each must have a fix of its own (fnc_BombFix), lie inside the scan, be
    clear of our own people and not already answered by an ETB responder.
    Ranked by the bomb's class weights (vehicles and statics above infantry),
    then the ground's own contacts first, then nearest the report.
    Returns [object or objNull, fix, class, candidates looked at].
*/
ITW_CLASH_SupportsStrike_fnc_BombScan = {
    params ["_veh","_hq","_report","_radius","_since","_wanted","_friendlies","_footprint"];
    private _pool = [];
    {
        _x params [["_object",objNull],"",["_relationship",""]];
        if (!isNull _object && {_relationship isEqualTo "enemy"}) then {_pool pushBackUnique _object};
    } forEach (getSensorTargets _veh);
    private _reach = (_veh distance2D _report) + _radius + 500;
    // A man in a vehicle is the vehicle, as the knowledge layer keys it.
    {
        {_pool pushBackUnique (vehicle _x)} forEach (_x targets [true,_reach]);
    } forEach ((crew _veh) select {alive _x});
    private _weights = (["BOMB"] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["weights",createHashMap];
    private _ranked = [];
    {
        private _object = _x;
        if (!alive _object) then {continue};
        private _class = [_object] call ITW_CLASH_Knowledge_fnc_Class;
        if (_class in ["","AIR"]) then {continue};
        private _fix = [_veh,_object,_since] call ITW_CLASH_SupportsStrike_fnc_BombFix;
        if (_fix isEqualTo []) then {continue};
        if (((_fix#0) distance2D _report) > _radius) then {continue};
        if ([_friendlies,_fix#0,_footprint] call ITW_CLASH_Supports_fnc_DangerClose) then {continue};
        if ([_hq,[_object]] call ITW_CLASH_Supports_fnc_ETBAnswering) then {continue};
        // The bomb's own table, read at rest for anything with wheels or
        // tracks; infantry as moving, so a vehicle or a static outranks it.
        private _bucket = switch (_class) do {
            case "INFANTRY": {"INF_MOVING"};
            case "STATIC": {"STATIC_DUG"};
            default {"VEH_PARKED"};
        };
        private _weight = _weights getOrDefault [_bucket,0];
        if (_weight <= 0) then {continue};
        _ranked pushBack [_weight,[1,0] select (_object in _wanted),(_fix#0) distance2D _report,_object,_fix,_class];
    } forEach _pool;
    if (_ranked isEqualTo []) exitWith {[objNull,[],"",count _pool]};
    private _best = ([_ranked,[],{((-(_x#0)) * 1e7) + ((_x#1) * 1e5) + (_x#2)},"ASCEND"] call BIS_fnc_sortBy)#0;
    [_best#3,_best#4,_best#5,count _pool]
};

/*
    v4. The aim for an acquired target: its latest fix, moved on by its own
    estimated velocity until the bombs arrive. The velocity comes from two of
    the jet's own fixes at least the lead sample apart, clamped to the class's
    speed allowance in the knowledge layer, so a jumpy fix cannot fling the
    aim. The bombs travel forward at the jet's ground speed, so they arrive
    when the jet would have flown the run left: _along over that speed, plus
    the age of the fix. Returns [aim, lead metres, estimated speed].
*/
ITW_CLASH_SupportsStrike_fnc_BombAim = {
    params ["_veh","_fix","_base","_class","_along"];
    private _position = +(_fix#0);
    private _velocity = [0,0,0];
    private _dt = (_fix#1) - (_base#1);
    if (_dt >= ITW_CLASH_SupportsStrikeLeadSample) then {
        _velocity = (_position vectorDiff (_base#0)) vectorMultiply (1 / _dt);
        _velocity set [2,0];
        private _cap = [_class] call ITW_CLASH_Knowledge_fnc_Speed;
        private _speed = vectorMagnitude _velocity;
        if (_speed > _cap) then {_velocity = _velocity vectorMultiply (_cap / (_speed max 0.001))};
    };
    private _ground = velocity _veh;
    private _groundSpeed = vectorMagnitude [_ground#0,_ground#1,0];
    private _until = ((time - (_fix#1)) max 0) + ((_along max 0) / (_groundSpeed max 1));
    private _shift = _velocity vectorMultiply _until;
    private _length = vectorMagnitude _shift;
    if (_length > ITW_CLASH_SupportsStrikeLeadCap) then {
        _shift = _shift vectorMultiply (ITW_CLASH_SupportsStrikeLeadCap / _length);
    };
    private _aim = _position vectorAdd _shift;
    _aim set [2,0];
    [_aim,vectorMagnitude _shift,vectorMagnitude _velocity]
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

    // v4: the bomb pass acquires on site. Carpet and console test passes fly
    // the report as before.
    private _acquire = (_flavor in ITW_CLASH_SupportsAcquireFlavors) && {!_test};
    // v5: a live pass is held to its flavor's line; a console calibration
    // pass to the old 250 m, so a drifting run still gives its impacts.
    private _crossLimit = if (_test) then {ITW_CLASH_SupportsStrikeCrossLimit} else {
        [_flavor] call ITW_CLASH_SupportsStrike_fnc_CrossLimit
    };
    private _hq = _support getOrDefault ["hq",grpNull];
    private _report = +_aim;
    private _scanRadius = ((_support getOrDefault ["uncertainty",0]) max ITW_CLASH_SupportsStrikeScanMin)
        min ITW_CLASH_SupportsStrikeScanCap;
    private _since = time;
    private _wanted = [];
    private _target = objNull;
    private _targetClass = "";
    private _fixes = [];
    private _nextLook = 0;
    private _looks = 0;
    private _seen = 0;
    private _lastLine = -1e10;
    if (_acquire) then {
        _veh setVehicleRadar 1;
        {
            private _entity = ([_side,_x] call ITW_CLASH_Knowledge_fnc_Record) getOrDefault ["entity",objNull];
            if (!isNull _entity && {alive _entity}) then {_wanted pushBackUnique _entity};
        } forEach _keys;
        // Where to look. A reveal is never a sighting, so it acquires nothing.
        {_group reveal [_x,ITW_CLASH_SupportsStrikeRevealValue]} forEach _wanted;
        // Let the crew watch for what they were not told about as well. The
        // group stays CARELESS and BLUE: it looks, it never engages.
        {_x enableAI "AUTOTARGET"} forEach (units _group);
        // A sighting must come after the reveal, never from it.
        _since = time + 1;
        ["bomb-scan-start",[
            _support get "id",_support get "sign",count _wanted,round _scanRadius,round (_veh distance2D _report)
        ]] call ITW_CLASH_SupportsStrike_fnc_Log;
    };

    // The approach, on the scheduler: line up, then the final check.
    while {_result isEqualTo [] && {!_armed}} do {
        sleep 0.1;
        if (!alive _veh || {!canMove _veh} || {isNull driver _veh}) exitWith {_result = ["LOST","aircraft-lost"]};
        if (time > _deadline) exitWith {_result = ["BREAKOFF","never-reached"]};
        ([getPosATL _veh,_aim,_heading] call ITW_CLASH_Supports_fnc_AlongCross) params ["_along","_cross"];
        private _lead = ([_veh,_aim] call ITW_CLASH_SupportsStrike_fnc_Lead) + ITW_CLASH_SupportsStrikeReleaseBias;

        // About 3 km out: the latest report, and the aircraft's line pointed
        // through it. The jet is steered; the bombs are never moved. With a
        // target already acquired, the line goes through that instead, and the
        // report is only where the jet was told to look.
        if (!_lined && {_along <= ITW_CLASH_SupportsStrikeApproachUpdate}) then {
            _lined = true;
            if (_test) exitWith {};
            private _ahead = _along / (((speed _veh) / 3.6) max 1);
            ([_side,_keys,_ahead,_acquire] call ITW_CLASH_Supports_fnc_TargetNow) params ["_now","_r","_alive"];
            private _how = "report";
            if (_acquire && {!isNull _target} && {alive _target}) then {
                private _fix = _fixes select ((count _fixes) - 1);
                _now = ([_veh,_fix,_fixes#0,_targetClass,_along] call ITW_CLASH_SupportsStrike_fnc_BombAim)#0;
                _r = _fix#3;
                _alive = 1;
                _how = _fix#2;
            };
            switch (true) do {
                case (_alive == 0): {_result = ["BREAKOFF","TARGET_GONE"]};
                // A pass that looks for itself does not need the report tight yet.
                case (!_acquire && {_r > ITW_CLASH_SupportsUncertaintyLimit}): {_result = ["BREAKOFF","TOO_UNCERTAIN"]};
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
                    _lastLine = time;
                    ["lined-up",[_support get "id",_flavor,round _shift,round _r,_alive,_how]] call
                        ITW_CLASH_SupportsStrike_fnc_Log;
                };
            };
        };
        if (_result isNotEqualTo []) exitWith {};

        // v4: the bomber's own look, once a scan interval. What it acquires is
        // tracked from then on; while there is run left to turn, the jet is
        // re-lined onto it.
        if (_acquire && {time >= _nextLook}) then {
            _nextLook = time + ITW_CLASH_SupportsStrikeBombScanInterval;
            if (!isNull _target && {!alive _target}) then {
                ["bomb-target-lost",[_support get "id",typeOf _target,round _along]] call ITW_CLASH_SupportsStrike_fnc_Log;
                _target = objNull;
                _fixes = [];
            };
            if (isNull _target) then {
                _looks = _looks + 1;
                ([
                    _veh,_hq,_report,_scanRadius,_since,_wanted,
                    [_side] call ITW_CLASH_Supports_fnc_Friendlies,_footprint
                ] call ITW_CLASH_SupportsStrike_fnc_BombScan) params ["_found","_fix","_class","_pool"];
                _seen = _seen max _pool;
                if (!isNull _found) then {
                    _target = _found;
                    _targetClass = _class;
                    _fixes = [_fix];
                    ["bomb-acquired",[
                        _support get "id",_support get "sign",typeOf _found,_class,_fix#2,
                        round ((_fix#0) distance2D _report),round _scanRadius,round _along,
                        round (time - _since),_looks,_found in _wanted,_pool
                    ]] call ITW_CLASH_SupportsStrike_fnc_Log;
                };
            } else {
                private _fix = [_veh,_target,_since] call ITW_CLASH_SupportsStrike_fnc_BombFix;
                private _last = _fixes select ((count _fixes) - 1);
                if (_fix isNotEqualTo [] && {(_fix#1) > (_last#1)}) then {
                    _fixes pushBack _fix;
                    private _latest = _fix#1;
                    _fixes = _fixes select {(_latest - (_x#1)) <= ITW_CLASH_SupportsStrikeLeadWindow};
                };
            };
            // v5: only with time left to settle on the new line before the
            // final check, at the speed it is flying.
            private _ground = velocity _veh;
            private _toCheck = (_along - (_lead - _first + ITW_CLASH_SupportsStrikeCheckLead))
                / ((vectorMagnitude [_ground#0,_ground#1,0]) max 1);
            if (
                !isNull _target
                && {_lined}
                && {_toCheck >= ITW_CLASH_SupportsStrikeRelineSeconds}
                && {(time - _lastLine) >= 3}
            ) then {
                private _fix = _fixes select ((count _fixes) - 1);
                private _toward = ([_veh,_fix,_fixes#0,_targetClass,_along] call ITW_CLASH_SupportsStrike_fnc_BombAim)#0;
                private _moved = _toward distance2D _aim;
                if (_moved > ITW_CLASH_SupportsStrikeRelineShift) then {
                    _aim = _toward;
                    _heading = (getPosATL _veh) getDir _aim;
                    [_group,_aim,_heading] call ITW_CLASH_SupportsStrike_fnc_LineUp;
                    _support set ["aim",+_aim];
                    _support set ["heading",_heading];
                    _lastLine = time;
                    ["bomb-relined",[_support get "id",round _moved,round _along,_fix#2,round _toCheck]] call
                        ITW_CLASH_SupportsStrike_fnc_Log;
                };
            };
        };

        // A few seconds before the first bomb: the latest report once more and
        // danger close against our people now. The aircraft keeps its line,
        // so only the timing follows the report; what is left off the line is
        // a physical miss, and more than the cross limit is no pass at all.
        if (_along <= (_lead - _first + ITW_CLASH_SupportsStrikeCheckLead)) then {
            if (!_test) then {
                if (!isNull _target && {!alive _target}) then {_target = objNull};
                if (_acquire && {!isNull _target}) then {
                    // The acquired target, where the jet has it now, led to impact.
                    private _fix = _fixes select ((count _fixes) - 1);
                    ([_veh,_fix,_fixes#0,_targetClass,_along] call ITW_CLASH_SupportsStrike_fnc_BombAim) params ["_now","_shift","_speed"];
                    if ([[_side] call ITW_CLASH_Supports_fnc_Friendlies,_now,_footprint] call ITW_CLASH_Supports_fnc_DangerClose) exitWith {
                        _result = ["BREAKOFF","DANGER_CLOSE"];
                    };
                    ["release-check",[
                        _support get "id",_flavor,round (_aim distance2D _now),round (_fix#3),1,_fix#2
                    ]] call ITW_CLASH_SupportsStrike_fnc_Log;
                    ["bomb-release-fix",[
                        _support get "id",typeOf _target,_targetClass,_fix#2,round (time - (_fix#1)),count _fixes,
                        round _shift,(round (_speed * 10)) / 10,round (_now distance2D _report)
                    ]] call ITW_CLASH_SupportsStrike_fnc_Log;
                    _aim = _now;
                    _entities = [_target];
                } else {
                    ([_side,_keys,0] call ITW_CLASH_Supports_fnc_TargetNow) params ["_now","_r","_alive","_targets"];
                    // Nothing acquired: the report, only if it is still good
                    // enough to drop on. Otherwise no pass, and a refund.
                    if (_acquire) then {
                        private _usable = _alive > 0 && {_r <= ITW_CLASH_SupportsUncertaintyLimit};
                        ["scan-empty",[
                            _support get "id",_support get "sign",round _scanRadius,_seen,
                            if (_usable) then {"bomb-report"} else {"bomb-breakoff"},_looks,round _r
                        ]] call ITW_CLASH_SupportsStrike_fnc_Log;
                        if (!_usable) then {_result = ["BREAKOFF","no-target-found"]};
                    };
                    if (_result isNotEqualTo []) exitWith {};
                    switch (true) do {
                        case (_alive == 0): {_result = ["BREAKOFF","TARGET_GONE"]};
                        case (_r > ITW_CLASH_SupportsUncertaintyLimit): {_result = ["BREAKOFF","TOO_UNCERTAIN"]};
                        case ([[_side] call ITW_CLASH_Supports_fnc_Friendlies,_now,_footprint] call ITW_CLASH_Supports_fnc_DangerClose): {
                            _result = ["BREAKOFF","DANGER_CLOSE"];
                        };
                        default {
                            ["release-check",[
                                _support get "id",_flavor,round (_aim distance2D _now),round _r,_alive,"report"
                            ]] call ITW_CLASH_SupportsStrike_fnc_Log;
                            _aim = _now;
                            _entities = _targets;
                        };
                    };
                };
            };
            if (_result isNotEqualTo []) exitWith {};
            private _wide = ([getPosATL _veh,_aim,_heading] call ITW_CLASH_Supports_fnc_AlongCross) select 1;
            if (_wide > _crossLimit) exitWith {_result = ["BREAKOFF","passed-wide"]};
            _support set ["aim",+_aim];
            _armed = true;
        };
    };
    // Looking is over, hit or miss: back to a crew that watches nothing.
    if (_acquire) then {{_x disableAI "AUTOTARGET"} forEach (units _group)};
    if (_result isNotEqualTo []) exitWith {_result};

    // The release itself, every frame.
    private _state = createHashMapFromArray [
        ["id",_support get "id"],["veh",_veh],["aim",+_aim],["heading",_heading],["pattern",_pattern],
        ["next",0],["released",0],["skipped",0],["overshoots",[]],["done",""],
        ["crossLimit",_crossLimit],["wide",-1]
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
            && {!([_friendlies,getPosATL _x,_footprint,"GUIDED"] call ITW_CLASH_Supports_fnc_DangerClose)}
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
    if (_kph > 0) then {_veh limitSpeed _kph} else {
        if (_flavor isEqualTo "BOMB") then {_veh limitSpeed ITW_CLASH_SupportsStrikeBombKph};
    };
    // v5: for the break-off line, how many missiles came at it.
    _veh setVariable ["ITW_CLASH_StrikeMissiles",0];
    private _missileHandler = _veh addEventHandler ["IncomingMissile",{
        (_this#0) setVariable ["ITW_CLASH_StrikeMissiles",((_this#0) getVariable ["ITW_CLASH_StrikeMissiles",0]) + 1];
    }];

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
    if (!isNull _veh) then {_veh removeEventHandler ["IncomingMissile",_missileHandler]};
    private _brokeOff = (_result param [0,""]) isEqualTo "BREAKOFF" && {alive _veh};
    if (_brokeOff) then {
        // v5: why it broke off, in geometry: how far out, how far off the
        // line, the line it was given and the track it was flying, and the
        // missiles that came at it.
        private _lineHeading = _support getOrDefault ["heading",_heading];
        ([getPosATL _veh,_support get "aim",_lineHeading] call ITW_CLASH_Supports_fnc_AlongCross) params ["_along","_cross"];
        private _v = velocity _veh;
        ["breakoff-geometry",[
            _support get "id",_flavor,_result param [1,""],round _along,round _cross,
            round _lineHeading,round (((_v#0) atan2 (_v#1)) + 360) mod 360,
            _veh getVariable ["ITW_CLASH_StrikeMissiles",0],round ((getPosATL _veh)#2),round (speed _veh)
        ]] call ITW_CLASH_SupportsStrike_fnc_Log;
    };
    // Delivered: on past the target, a turn on the colder side, and home.
    // Broken off (v5): away from the side the target is on, from where it is,
    // never on over it. A lost aircraft is left where it fell.
    if (_brokeOff) then {
        private _away = if ((_veh getRelDir (_support get "aim")) <= 180) then {(getDir _veh) - 100} else {(getDir _veh) + 100};
        [_veh,_group,getPosATL _veh,_away,4000,300,_support] spawn ITW_CLASH_Supports_fnc_Egress;
    } else {
        [
            _veh,_group,_support get "aim",_support getOrDefault ["heading",_heading],4000,300,_support
        ] spawn ITW_CLASH_Supports_fnc_Egress;
    };
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
    "CLASH BOOT | supports-strike-ready | version=%1 bomb=%2x%3 spacing=%4m heights=%5/%6/%7 carpet=21x%8m/%9m lanes crossLimit=%10 scan=%11m cap=%12m window=%13s shots=%14 lineUpAt=%15m skip=%16m bias=%17m fireCone=%18 releaseByFallTime=true releaseEachFrame=true bombsAlwaysAtJet=true impactLog=%19 bombAcquires=%20 reveal=%21 reline=%22s/%23m lead=%24s/%25s/%26m crossLimitBomb=%27m releaseScale=%28 bombKph=%29 breakoffTurnsAway=true guidedNeedsMotor=true",
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
    ITW_CLASH_SupportsStrikeImpactLog,
    "BOMB" in ITW_CLASH_SupportsAcquireFlavors,
    ITW_CLASH_SupportsStrikeRevealValue,
    ITW_CLASH_SupportsStrikeRelineSeconds,
    ITW_CLASH_SupportsStrikeRelineShift,
    ITW_CLASH_SupportsStrikeLeadSample,
    ITW_CLASH_SupportsStrikeLeadWindow,
    ITW_CLASH_SupportsStrikeLeadCap,
    ITW_CLASH_SupportsStrikeCrossLimitBomb,
    ITW_CLASH_SupportsStrikeReleaseScale,
    ITW_CLASH_SupportsStrikeBombKph
];
true
