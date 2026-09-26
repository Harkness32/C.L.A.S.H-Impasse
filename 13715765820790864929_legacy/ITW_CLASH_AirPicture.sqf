#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AirPictureStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo") exitWith {
    diag_log "CLASH BOOT | WARNING | air-picture-anti-armour-test-missing | air picture not started";
    false
};

ITW_CLASH_AirPictureStarted = true;
ITW_CLASH_AirPictureVersion = 1;
ITW_CLASH_AirPictureReady = false;

/*
    The air picture: observation only.

    HAL refreshes its enemy lists once per cycle (3-6 minutes), which is far
    too slow for a jet over the rear - in the 2026-09-25 peer run a Black Wasp
    worked BLUFOR's helicopters and no air request was ever raised. This file
    runs HAL's OWN "known enemy" test (HAC_fnc2.sqf:262-306, knowsAbout >= 0.05
    against the side's own units) on a 5-second clock, for enemy aircraft only,
    and publishes what it sees. HAL's cycle is untouched and there is no cheat
    vision: an aircraft nobody has seen is not in the picture.

    It emits a signal and nothing else. It never opens a demand, buys, tasks or
    moves anything: ThreatCoverage turns the signal into a counter-air demand,
    and the ETB only ever sees that demand.

    It also owns classification from the vehicle itself, because HAL's
    categories are wrong often enough to count threats with: HAL files a Rhino
    (a 120 mm tank killer) as a car and a Bobcat (an engineering vehicle) as
    heavy armor (RHQLibrary.sqf:279-309, then HAC_fnc2.sqf:2386-2390 by base
    class). Every question of "what is this vehicle" - armored threat, combat
    aircraft, air defence and its umbrella, the helicopter threat tier - is
    answered here from weapons, ammo and sensors, so modded factions work
    without class lists.
*/

ITW_CLASH_AirPictureEnabled = missionNamespace getVariable ["ITW_CLASH_AirPictureEnabled",true];
ITW_CLASH_AirPicturePoll = missionNamespace getVariable ["ITW_CLASH_AirPicturePoll",5];
// A sighting alone has to hold for this long before it is worth funding; a
// kill by enemy air is immediate (see the EntityKilled handler below).
ITW_CLASH_AirPictureSightingGrace = missionNamespace getVariable ["ITW_CLASH_AirPictureSightingGrace",15];
// Jets fly sortie loops, so a contact is kept for this long after it was last
// seen before the picture drops it.
ITW_CLASH_AirPictureUnseenTimeout = missionNamespace getVariable ["ITW_CLASH_AirPictureUnseenTimeout",300];
ITW_CLASH_AirPictureKnowledgeThreshold = missionNamespace getVariable ["ITW_CLASH_AirPictureKnowledgeThreshold",0.05];
/*
    Open question for Hark (the HAL front postdates the ETB design): HAL's
    dispatcher ignores threats outside a commander's front, which is what stops
    the Agios Dionysios loop. Aircraft cross a front in seconds, so by default
    the air picture does not apply it. Set this false to leash counter-air to
    the front like every ground threat.
*/
ITW_CLASH_AirPictureIgnoreFront = missionNamespace getVariable ["ITW_CLASH_AirPictureIgnoreFront",true];
// Four or more loaded air-to-air missiles is a fighter, not a CAS jet with a
// self-defence pair: only the former closes a helicopter corridor.
ITW_CLASH_AirPictureHardKillMissiles = missionNamespace getVariable ["ITW_CLASH_AirPictureHardKillMissiles",4];
ITW_CLASH_AirPictureManpadUmbrella = missionNamespace getVariable ["ITW_CLASH_AirPictureManpadUmbrella",3000];
ITW_CLASH_AirPictureStaticGunUmbrella = missionNamespace getVariable ["ITW_CLASH_AirPictureStaticGunUmbrella",1500];
ITW_CLASH_AirPictureRadarUmbrella = missionNamespace getVariable ["ITW_CLASH_AirPictureRadarUmbrella",5000];
ITW_CLASH_AirPictureSPAAUmbrella = missionNamespace getVariable ["ITW_CLASH_AirPictureSPAAUmbrella",3500];
ITW_CLASH_AirPictureCRAMUmbrella = missionNamespace getVariable ["ITW_CLASH_AirPictureCRAMUmbrella",3000];
// Hard-kill envelopes, for the corridor gate and the helicopter tiers.
ITW_CLASH_AirPictureGroundEnvelope = missionNamespace getVariable ["ITW_CLASH_AirPictureGroundEnvelope",4000];
ITW_CLASH_AirPictureFighterEnvelope = missionNamespace getVariable ["ITW_CLASH_AirPictureFighterEnvelope",6000];
// Two helicopters lost close together in a short window close that area,
// whatever shot them down: it catches a MANPADS nest and air defence nobody saw.
ITW_CLASH_AirPictureLossRadius = missionNamespace getVariable ["ITW_CLASH_AirPictureLossRadius",1500];
ITW_CLASH_AirPictureLossWindow = missionNamespace getVariable ["ITW_CLASH_AirPictureLossWindow",600];
ITW_CLASH_AirPictureLossClosure = missionNamespace getVariable ["ITW_CLASH_AirPictureLossClosure",600];

// Contacts per side: sideKey -> (contact key -> [aircraft,position,firstSeenAt,
// lastSeenAt,tier,immediate]).
ITW_CLASH_AirPictureContacts = createHashMap;
// Air losses: [position,time,class] - the loss counter's raw material.
ITW_CLASH_AirPictureLosses = [];

ITW_CLASH_AirPicture_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["air-picture-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH AIR PICTURE | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_AirPicture_fnc_SideKey = {
    params ["_side"];
    toUpperANSI str _side
};

// HAL's own anti-air designation: airLock above 1 means the round can engage
// air, which is how HAL auto-classifies AA vehicles (HAC_fnc2.sqf:2697).
ITW_CLASH_AirPicture_fnc_IsAntiAirAmmo = {
    params ["_ammo"];
    if (_ammo isEqualTo "") exitWith {false};
    (getNumber (configFile >> "CfgAmmo" >> _ammo >> "airLock")) > 1
};

// Gun or missile, from the round's own simulation, so a modded static works
// without a class list.
ITW_CLASH_AirPicture_fnc_AmmoIsGuided = {
    params ["_ammo"];
    if (_ammo isEqualTo "") exitWith {false};
    private _simulation = toLowerANSI getText (configFile >> "CfgAmmo" >> _ammo >> "simulation");
    _simulation in ["shotmissile","shotrocket","shotsubmunitions"]
};

// Anything that explodes rather than merely hitting: a door gunner's bullets
// are not ground attack, an unguided rocket pod is.
ITW_CLASH_AirPicture_fnc_AmmoIsOrdnance = {
    params ["_ammo"];
    if (_ammo isEqualTo "") exitWith {false};
    private _config = configFile >> "CfgAmmo" >> _ammo;
    private _simulation = toLowerANSI getText (_config >> "simulation");
    if (_simulation in ["shotmissile","shotrocket","shotbomb","shotsubmunitions"]) exitWith {true};
    (getNumber (_config >> "explosive")) > 0 && {(getNumber (_config >> "indirectHit")) > 5}
};

// Every magazine the vehicle really carries, turrets and pylons, as
// [magazine, turret path, rounds]. Same shape the echelon rule reads.
ITW_CLASH_AirPicture_fnc_Magazines = {
    params ["_veh"];
    if (isNull _veh) exitWith {[]};
    private _entries = ((magazinesAllTurrets _veh) apply {[_x#0,_x#1,_x#2]}) select {_x#0 != ""};
    {_entries pushBack [_x,"pylon",-1]} forEach ((getPylonMagazines _veh) - [""]);
    _entries
};

// What this vehicle can actually do, read off the vehicle: anti-armor from the
// engine's own ammo flag (the same test the echelon rule uses), anti-air from
// airLock, radar from the sensor components. Loaded rounds only, so a fighter
// that has shot its missiles drops a tier.
ITW_CLASH_AirPicture_fnc_WeaponProfile = {
    params ["_veh"];
    private _profile = createHashMapFromArray [
        ["antiArmor",false],["antiAir",false],["antiAirGun",false],
        ["antiAirMissile",false],["airToAirMissiles",0],["ordnance",false],
        ["armed",false],["radar",false]
    ];
    if (isNull _veh) exitWith {_profile};

    {
        _x params ["_magazine","","_rounds"];
        private _ammo = getText (configFile >> "CfgMagazines" >> _magazine >> "ammo");
        if (_ammo isEqualTo "") then {continue};
        // A pylon reports -1 rounds; a turret magazine with none left is spent.
        if (_rounds == 0) then {continue};
        _profile set ["armed",true];
        if ([_ammo] call ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo) then {
            _profile set ["antiArmor",true];
        };
        if ([_ammo] call ITW_CLASH_AirPicture_fnc_AmmoIsOrdnance) then {
            _profile set ["ordnance",true];
        };
        if ([_ammo] call ITW_CLASH_AirPicture_fnc_IsAntiAirAmmo) then {
            _profile set ["antiAir",true];
            if ([_ammo] call ITW_CLASH_AirPicture_fnc_AmmoIsGuided) then {
                _profile set ["antiAirMissile",true];
                private _count = getNumber (configFile >> "CfgMagazines" >> _magazine >> "count");
                if (_rounds > 0) then {_count = _rounds};
                _profile set ["airToAirMissiles",(_profile get "airToAirMissiles") + (_count max 1)];
            } else {
                _profile set ["antiAirGun",true];
            };
        };
    } forEach ([_veh] call ITW_CLASH_AirPicture_fnc_Magazines);

    private _sensors = configFile >> "CfgVehicles" >> typeOf _veh >> "Components" >>
        "SensorsManagerComponent" >> "Components";
    if (isClass _sensors) then {
        private _radar = ("true" configClasses _sensors) findIf {
            private _kind = toLowerANSI getText (_x >> "class");
            _kind in ["activeradarsensorcomponent","passiveradarsensorcomponent"]
        };
        if (_radar >= 0) then {_profile set ["radar",true]};
    };
    _profile
};

/*
    The anti-armor threat test, ours and not HAL's: an armored vehicle (tank or
    wheeled-APC base) carrying anti-armor weapons. HAL would miss every Rhino
    and count every Bobcat, so in the peer run its count would have been wrong
    in both directions (about 13 Rhinos and 8 Bobcats on the field).
*/
ITW_CLASH_AirPicture_fnc_IsArmoredThreat = {
    params ["_veh"];
    if (isNull _veh || {!alive _veh}) exitWith {false};
    private _class = typeOf _veh;
    private _armored = _class isKindOf "Tank" || {_class isKindOf "Wheeled_APC_F"};
    if (!_armored) exitWith {false};
    ([_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile) get "antiArmor"
};

// A combat aircraft is one that can hurt something: ground-attack ordnance,
// anti-armor ammo or air-to-air missiles. A door-gun transport carries none of
// those and is not counter-air demand.
ITW_CLASH_AirPicture_fnc_IsCombatAircraft = {
    params ["_veh"];
    if (isNull _veh || {!alive _veh} || {!(_veh isKindOf "Air")}) exitWith {false};
    private _profile = [_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile;
    (_profile get "antiArmor") || {_profile get "ordnance"} || {_profile get "antiAirMissile"}
};

// A fighter for coverage purposes: fixed-wing with air-to-air weapons.
ITW_CLASH_AirPicture_fnc_IsFighter = {
    params ["_veh"];
    if (isNull _veh || {!alive _veh} || {!(_veh isKindOf "Plane")}) exitWith {false};
    ([_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile) get "antiAirMissile"
};

/*
    SPAA: a ground vehicle whose weapons engage air and not armor. An IFV with
    an incidental AA ability does not qualify - it is an armor answer that
    happens to elevate, and HAL would send it forward.
*/
ITW_CLASH_AirPicture_fnc_IsSPAA = {
    params ["_veh"];
    if (isNull _veh || {!alive _veh} || {_veh isKindOf "Air"} || {_veh isKindOf "StaticWeapon"}) exitWith {false};
    private _profile = [_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile;
    (_profile get "antiAir") && {!(_profile get "antiArmor")}
};

/*
    Air defence, with the weight and umbrella it contributes to counter-air
    coverage. A static gun or launcher is one fixed, visible weapon, so it
    counts no more than a MANPAD squad; a radar SAM site genuinely denies
    airspace, so it counts like SPAA. Every one of them counts only for enemy
    aircraft inside its own umbrella - an AA squad on the far side of the map
    covers nothing, which is what made the earlier map-wide count wrong
    (commit 0689ac9).
*/
ITW_CLASH_AirPicture_fnc_AirDefenceProfile = {
    params ["_veh"];
    private _none = ["",0,0];
    if (isNull _veh || {!alive _veh}) exitWith {_none};
    private _profile = [_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile;
    if !(_profile get "antiAir") exitWith {_none};

    if (_veh getVariable ["ITW_CLASH_CRAM",false]) exitWith {
        ["CRAM",1,ITW_CLASH_AirPictureCRAMUmbrella]
    };
    if (_profile get "radar") exitWith {
        ["RADAR_SAM",1,ITW_CLASH_AirPictureRadarUmbrella]
    };
    if (_veh isKindOf "StaticWeapon") exitWith {
        if (_profile get "antiAirMissile") then {
            ["STATIC_AA_LAUNCHER",0.25,ITW_CLASH_AirPictureManpadUmbrella]
        } else {
            ["STATIC_AA_GUN",0.25,ITW_CLASH_AirPictureStaticGunUmbrella]
        }
    };
    if ([_veh] call ITW_CLASH_AirPicture_fnc_IsSPAA) exitWith {
        ["SPAA",1,ITW_CLASH_AirPictureSPAAUmbrella]
    };
    // A man carrying a launcher, or a vehicle that also kills armor: neither is
    // dedicated air defence.
    if (_veh isKindOf "CAManBase") exitWith {
        ["MANPAD",0.25,ITW_CLASH_AirPictureManpadUmbrella]
    };
    _none
};

/*
    Helicopter threat tier, classified from the vehicle like the armor fix.
    Most air defence changes HOW helicopters fly, not WHETHER they fly: only a
    system built to kill aircraft closes a corridor.
      TOLERATED: MANPADS, static AA guns, CAS jets and gunships with a
                 self-defence pair, unarmed aircraft. Never blocks; near the
                 landing zone it makes the LZ hot.
      HARD_KILL: dedicated AA vehicles, radar SAM sites, and fighters with four
                 or more loaded air-to-air missiles. Closes the corridor.
*/
ITW_CLASH_AirPicture_fnc_ThreatTier = {
    params ["_veh"];
    if (isNull _veh || {!alive _veh}) exitWith {["NONE",0]};
    private _profile = [_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile;

    if (_veh isKindOf "Air") exitWith {
        if (
            (_profile get "antiAirMissile")
            && {(_profile get "airToAirMissiles") >= ITW_CLASH_AirPictureHardKillMissiles}
        ) then {
            ["HARD_KILL",ITW_CLASH_AirPictureFighterEnvelope]
        } else {
            ["TOLERATED",0]
        }
    };
    if !(_profile get "antiAir") exitWith {["NONE",0]};
    if (_profile get "radar") exitWith {["HARD_KILL",ITW_CLASH_AirPictureRadarUmbrella]};
    if ([_veh] call ITW_CLASH_AirPicture_fnc_IsSPAA) exitWith {
        ["HARD_KILL",ITW_CLASH_AirPictureGroundEnvelope]
    };
    ["TOLERATED",0]
};

ITW_CLASH_AirPicture_fnc_ContactKey = {
    params ["_veh"];
    if (isNull _veh) exitWith {""};
    private _key = netId _veh;
    if (_key isEqualTo "" || {_key isEqualTo "0:0"}) then {_key = str _veh};
    _key
};

// Every unit whose knowledge counts for this commander: its own groups' units
// plus the HQ, exactly the set HAL's own known-enemy pass walks.
ITW_CLASH_AirPicture_fnc_Observers = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};
    private _side = side _hq;
    private _observers = [];
    {
        if (_x getVariable ["Ryd_NoReports",false]) then {continue};
        {
            if (alive _x) then {_observers pushBack _x};
        } forEach units _x;
    } forEach ((allGroups select {side _x == _side}) + [_hq]);
    _observers
};

ITW_CLASH_AirPicture_fnc_IsKnown = {
    params ["_veh","_observers"];
    if (isNull _veh) exitWith {false};
    (_observers findIf {
        (_x knowsAbout _veh) >= ITW_CLASH_AirPictureKnowledgeThreshold
    }) >= 0
};

// Enemy combat aircraft this commander can legitimately see, updated in place.
ITW_CLASH_AirPicture_fnc_Update = {
    params ["_hq"];
    if (isNull _hq) exitWith {false};
    private _side = side _hq;
    private _key = [_side] call ITW_CLASH_AirPicture_fnc_SideKey;
    private _contacts = ITW_CLASH_AirPictureContacts getOrDefault [_key,createHashMap,true];
    private _observers = [_hq] call ITW_CLASH_AirPicture_fnc_Observers;
    private _front = _hq getVariable ["RydHQ_Front",locationNull];
    private _applyFront = !ITW_CLASH_AirPictureIgnoreFront && {!isNull _front};

    private _seen = [];
    {
        private _veh = _x;
        if !([_veh] call ITW_CLASH_AirPicture_fnc_IsCombatAircraft) then {continue};
        if !([_veh,_observers] call ITW_CLASH_AirPicture_fnc_IsKnown) then {continue};
        private _position = getPosATL _veh;
        if (_applyFront && {!(_position in _front)}) then {continue};

        private _contactKey = [_veh] call ITW_CLASH_AirPicture_fnc_ContactKey;
        _seen pushBackUnique _contactKey;
        private _entry = _contacts getOrDefault [_contactKey,[]];
        ([_veh] call ITW_CLASH_AirPicture_fnc_ThreatTier) params ["_tier"];
        if (_entry isEqualTo []) then {
            _contacts set [_contactKey,[_veh,_position,time,time,_tier,false]];
            ["contact-opened",[
                _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,
                _position apply {round _x},_tier
            ]] call ITW_CLASH_AirPicture_fnc_Log;
        } else {
            _entry set [1,_position];
            _entry set [3,time];
            _entry set [4,_tier];
        };
    } forEach (
        // Crewed aircraft only, and their crew's side, not the vehicle's
        // faction: an empty airframe on the apron is not a threat.
        vehicles select {
            _x isKindOf "Air" && {alive _x} && {
                private _commander = effectiveCommander _x;
                !isNull _commander && {alive _commander} && {
                    [side _commander,_side] call BIS_fnc_sideIsEnemy
                }
            }
        }
    );

    // Contacts are kept past the last sighting: jets fly sortie loops, and
    // dropping one the moment it turns away would reopen the demand every pass.
    {
        _y params ["_veh","","","_lastSeenAt"];
        if (
            isNull _veh
            || {!alive _veh}
            || {!(_x in _seen) && {(time - _lastSeenAt) > ITW_CLASH_AirPictureUnseenTimeout}}
        ) then {
            _contacts deleteAt _x;
            ["contact-closed",[
                _hq getVariable ["RydHQ_CodeSign","?"],
                if (isNull _veh) then {"<gone>"} else {typeOf _veh},
                round (time - _lastSeenAt)
            ]] call ITW_CLASH_AirPicture_fnc_Log;
        };
    } forEach (+_contacts);
    true
};

/*
    The signal, and the whole public contract: known hostile combat air for
    this commander, as [aircraft,position,firstSeenAt,lastSeenAt,tier,funded].
    "funded" is the only judgment in it - a sighting alone has to hold for the
    grace period, a kill by enemy air counts at once - and it is what lets
    ThreatCoverage fund the first air response with no wait.
*/
ITW_CLASH_AirPicture_fnc_Hostiles = {
    params ["_hq"];
    if (isNull _hq || {!ITW_CLASH_AirPictureEnabled}) exitWith {[]};
    private _key = [side _hq] call ITW_CLASH_AirPicture_fnc_SideKey;
    private _contacts = ITW_CLASH_AirPictureContacts getOrDefault [_key,createHashMap];
    private _result = [];
    {
        _y params ["_veh","_position","_firstSeenAt","_lastSeenAt","_tier","_immediate"];
        if (isNull _veh || {!alive _veh}) then {continue};
        private _funded = _immediate || {
            (time - _firstSeenAt) >= ITW_CLASH_AirPictureSightingGrace
        };
        _result pushBack [_veh,+_position,_firstSeenAt,_lastSeenAt,_tier,_funded];
    } forEach _contacts;
    _result
};

// Enemy air defence this commander knows about, as [vehicle,tier,envelope].
// Read from HAL's own knowledge, so nothing is conjured.
ITW_CLASH_AirPicture_fnc_KnownAirDefence = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};
    private _result = [];
    {
        private _veh = vehicle _x;
        if (isNull _veh || {!alive _veh} || {_veh isKindOf "Air"}) then {continue};
        ([_veh] call ITW_CLASH_AirPicture_fnc_ThreatTier) params ["_tier","_envelope"];
        if (_tier isEqualTo "HARD_KILL") then {_result pushBack [_veh,_tier,_envelope]};
    } forEach (_hq getVariable ["RydHQ_KnEnemies",[]]);
    _result
};

// An air loss, wherever it happened and whatever caused it.
ITW_CLASH_AirPicture_fnc_RecordLoss = {
    params ["_veh"];
    if (isNull _veh) exitWith {false};
    ITW_CLASH_AirPictureLosses pushBack [getPosATL _veh,time,typeOf _veh];
    ITW_CLASH_AirPictureLosses = ITW_CLASH_AirPictureLosses select {
        (time - (_x#1)) <= (ITW_CLASH_AirPictureLossWindow + ITW_CLASH_AirPictureLossClosure)
    };
    ["air-loss",[typeOf _veh,(getPosATL _veh) apply {round _x}]] call
        ITW_CLASH_AirPicture_fnc_Log;
    true
};

/*
    Loss counter: two aircraft lost within ITW_CLASH_AirPictureLossRadius of
    each other inside the window close that area for the closure period,
    whatever shot them down. It catches a MANPADS nest the commander keeps
    feeding, and air defence nobody has seen.
*/
ITW_CLASH_AirPicture_fnc_LossClosed = {
    params ["_position"];
    if (_position isEqualTo []) exitWith {false};
    private _recent = ITW_CLASH_AirPictureLosses select {
        (time - (_x#1)) <= ITW_CLASH_AirPictureLossClosure
        && {((_x#0) distance2D _position) <= ITW_CLASH_AirPictureLossRadius}
    };
    if (count _recent < 2) exitWith {false};
    // The two have to be close to each other in time as well as in space.
    private _newest = 0;
    private _oldest = 1e12;
    {
        _newest = _newest max (_x#1);
        _oldest = _oldest min (_x#1);
    } forEach _recent;
    (_newest - _oldest) <= ITW_CLASH_AirPictureLossWindow
};

/*
    The corridor from our air spawn to a threat, for the AA corridor gate.
    Thunder Run already classifies a corridor for a specific helicopter
    (ITW_CLASH_ThunderRun_Core.sqf:227-310) - that is the same question with
    countermeasures and a real airframe in it. This is the doctrine-level
    version: HAL's AA list holds lock-on SPAA such as Cheetah and Tigris
    (RHQLibrary.sqf:86, plus auto-classified lock-on AA), but not AA vehicles
    armed only with guns, and it knows nothing about where we have been losing
    helicopters. Both are added here.
      COLD:       CAS first - it arrives fastest.
      CONTESTED:  random among valid providers.
      HOT:        ground only.
      AIR_DENIED: ground only.
*/
ITW_CLASH_AirPicture_fnc_ClassifyCorridor = {
    params ["_hq","_origin","_destination"];
    private _result = createHashMapFromArray [
        ["state","COLD"],["reason","corridor-clear"],
        ["aaDistance",1e12],["airDistance",1e12]
    ];
    if (
        isNull _hq || {_origin isEqualTo []} || {_destination isEqualTo []}
        || {isNil "ITW_CLASH_ThunderRun_fnc_CorridorStats"}
        || {isNil "RYD_PointToSecDst"}
    ) exitWith {
        _result set ["reason","corridor-unavailable"];
        _result
    };

    // HAL's own AA list, plus the gun-only AA vehicles it never files, plus
    // radar SAM sites: everything that is actually built to kill aircraft.
    private _groups = +(_hq getVariable ["RydHQ_AAthreat",[]]);
    {
        _x params ["_veh"];
        private _group = group effectiveCommander _veh;
        if (!isNull _group) then {_groups pushBackUnique _group};
    } forEach ([_hq] call ITW_CLASH_AirPicture_fnc_KnownAirDefence);

    private _aa = [_origin,_destination,_groups] call ITW_CLASH_ThunderRun_fnc_CorridorStats;
    _aa params ["_aaDistance","_aa1500","_aa1000"];
    _result set ["aaDistance",_aaDistance];

    // Enemy fighters on the route deny it outright: a CAS aircraft sent into
    // one is a gift, and the ETB has a ground answer for the same need.
    private _airDistance = 1e12;
    {
        _x params ["_veh","_position"];
        if ([_veh] call ITW_CLASH_AirPicture_fnc_IsFighter) then {
            private _distance = [_origin,_destination,_position] call RYD_PointToSecDst;
            if (_distance >= 0 && {_distance < _airDistance}) then {_airDistance = _distance};
        };
    } forEach ([_hq] call ITW_CLASH_AirPicture_fnc_Hostiles);
    _result set ["airDistance",_airDistance];

    if (_airDistance < ITW_CLASH_AirPictureFighterEnvelope) exitWith {
        _result set ["state","AIR_DENIED"];
        _result set ["reason","enemy-fighter-corridor"];
        _result
    };
    if ([_destination] call ITW_CLASH_AirPicture_fnc_LossClosed) exitWith {
        _result set ["state","AIR_DENIED"];
        _result set ["reason","recent-losses"];
        _result
    };
    if (_aa1000 >= 3 || {_aa1500 >= 4}) exitWith {
        _result set ["state","AIR_DENIED"];
        _result set ["reason","aa-concentration"];
        _result
    };
    if (_aaDistance < 1500) exitWith {
        _result set ["state","HOT"];
        _result set ["reason","aa-hot-corridor"];
        _result
    };
    if (_aaDistance < ITW_CLASH_AirPictureGroundEnvelope) exitWith {
        _result set ["state","CONTESTED"];
        _result set ["reason","aa-contested-corridor"];
        _result
    };
    _result
};

/*
    The kill trigger. A commander should not have to wait out the sighting
    grace period after an enemy aircraft has already killed something of ours:
    that contact is funded the moment it happens, and the loss is recorded for
    the corridor's loss counter whatever killed it.
*/
ITW_CLASH_AirPicture_fnc_OnKill = {
    params [["_killed",objNull],["_killer",objNull]];
    if (isNull _killed) exitWith {false};
    private _victim = vehicle _killed;
    if (_victim isKindOf "Air" && {_killed isEqualTo effectiveCommander _victim}) then {
        [_victim] call ITW_CLASH_AirPicture_fnc_RecordLoss;
    };
    if (isNull _killer) exitWith {false};
    private _shooter = vehicle _killer;
    if !([_shooter] call ITW_CLASH_AirPicture_fnc_IsCombatAircraft) exitWith {false};
    private _shooterCommander = effectiveCommander _shooter;
    if (isNull _shooterCommander) then {_shooterCommander = _killer};
    if !([side _shooterCommander,side _killed] call BIS_fnc_sideIsEnemy) exitWith {false};

    private _key = [side _killed] call ITW_CLASH_AirPicture_fnc_SideKey;
    private _contacts = ITW_CLASH_AirPictureContacts getOrDefault [_key,createHashMap,true];
    private _contactKey = [_shooter] call ITW_CLASH_AirPicture_fnc_ContactKey;
    private _entry = _contacts getOrDefault [_contactKey,[]];
    ([_shooter] call ITW_CLASH_AirPicture_fnc_ThreatTier) params ["_tier"];
    if (_entry isEqualTo []) then {
        _contacts set [_contactKey,[_shooter,getPosATL _shooter,time,time,_tier,true]];
    } else {
        _entry set [1,getPosATL _shooter];
        _entry set [3,time];
        _entry set [5,true];
    };
    ["kill-trigger",[
        toUpperANSI str (side _killed),typeOf _shooter,typeOf _victim,
        (getPosATL _shooter) apply {round _x}
    ]] call ITW_CLASH_AirPicture_fnc_Log;
    true
};

addMissionEventHandler ["EntityKilled",{
    params [["_killed",objNull],["_killer",objNull]];
    if (ITW_CLASH_AirPictureEnabled) then {
        [_killed,_killer] call ITW_CLASH_AirPicture_fnc_OnKill;
    };
}];

[] spawn {
    scriptName "ITW_CLASH_AirPicture";
    waitUntil {
        sleep 1;
        !isNil "ITW_CLASH_fnc_GetCommanderForSide" || {
            missionNamespace getVariable ["ITW_GameOver",false]
        }
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_AirPictureEnabled) then {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            {
                private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
                if (!isNull _hq) then {
                    [_hq] call ITW_CLASH_AirPicture_fnc_Update;
                };
            } forEach _sides;
        };
        sleep ITW_CLASH_AirPicturePoll;
    };
};

ITW_CLASH_AirPictureReady = true;
diag_log format [
    "CLASH BOOT | air-picture-ready | version=%1 poll=%2 grace=%3 unseen=%4 knowledge=%5 ignoreFront=%6 observeOnly=true halCycleUntouched=true classification=vehicle",
    ITW_CLASH_AirPictureVersion,
    ITW_CLASH_AirPicturePoll,
    ITW_CLASH_AirPictureSightingGrace,
    ITW_CLASH_AirPictureUnseenTimeout,
    ITW_CLASH_AirPictureKnowledgeThreshold,
    ITW_CLASH_AirPictureIgnoreFront
];
true
