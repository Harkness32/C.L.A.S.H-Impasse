#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALTaxonomyStarted",false]) exitWith {true};
ITW_CLASH_HALTaxonomyStarted = true;
ITW_CLASH_HALTaxonomyVersion = 4;
ITW_CLASH_HALTaxonomyReady = false;

/*
    One owner for "what does HAL think this vehicle is".

    HAL composes every class bucket the same way, in HQSitRep.sqf:116 onward and
    again in HAC_fnc.sqf:5483:

        _LArmorAT_class = RHQ_LArmorAT + RYD_WS_LArmorAT_class - RHQs_LArmorAT
                          ^autofill      ^curated seed           ^exclusion

    All three are plain mission-namespace arrays and RHQs_* starts empty
    (VarInit.sqf:104), so the seed and the exclusion list are a sanctioned
    interface for authoring the taxonomy without touching the mod - the same
    character as the RydHQ_Order global.

    Why author it at all: the curated RYD_WS_* lists are vanilla-era and cover
    what the mission actually fields only partly. In run4, 15 of the 61 classes
    in play were absent from them, including the two Rooikat variants (4173
    mentions between them), the AT Prowler, the LAT rifleman and the Littlebird.

    HAL does handle that: RydxHQ_RHQAutoFill defaults true and RYD_PresentRHQ
    classifies unknown classes from config every SitRep cycle. This module is
    not a rescue, it is a better-informed source for the part CLASH already
    decides for itself - ClassProfile is a cached config walk over magazines,
    ammo and sensors, and ProtectionGrade is a concept HAL has no equivalent of.

    How it avoids fighting the autofill rather than racing it: RYD_PresentRHQ
    rebuilds RYD_WS_AllClasses from eleven of the seed lists and only
    classifies classes NOT already in it, so a class we seed into a primary
    bucket is skipped by the autofill entirely. Those eleven are Inf, Art,
    HArmor, MArmor, LArmor, Cars, Air, Naval, Static, Support and Other - note
    they do NOT include LArmorAT, ATinf, AAinf, StaticAA or StaticAT. So a
    Rooikat seeded only into LArmorAT would still be autofilled; it has to go
    into LArmor as well. That is not a workaround, it is the taxonomy's own
    shape: every class gets one PRIMARY bucket plus any CAPABILITY buckets.

    Scope is deliberately the part CLASH knows cold - armour, AT, AA, air,
    artillery and statics. Infantry roles beyond AT and AA, cargo, crew, recon
    and SpecFor stay with the autofill: recon and special forces are semantic
    rather than config-visible, and asserting them here would be inventing
    confidence we do not have.

    Authority: where this module has an opinion it wins, because the seed
    suppresses the autofill for that class. That makes a wrong answer here
    HAL's only answer, so every decision is logged, and a class we cannot place
    confidently is left alone rather than guessed at.

    v4, one exception to the scope above: an aircraft whose weapons are all on
    pylons. HAL decides "armed" once per class from the config magazines and
    its top-level turrets', less its flare list (HAC_fnc2.sqf, RYD_PresentRHQ).
    A pylon is in neither, so the stub-wing Ghost Hawk, guns and rockets all on
    pylons, is filed as an unarmed transport: RHQ_NCAir, and RHQ_NCCargo for
    its seats. Its group then sits on RydHQ_NCAirG and RydHQ_NCCargoG, and
    HAL never puts it in AttackAv (HQOrders.sqf:159-213).

    The Air seed only prevents that when it lands before HAL's autofill first
    sees the class, which is a race this module's poll can lose. Hark,
    2026-10-17: "stub wing helicopters no longer move out". Run 2 at 04:49:
    spawned 4:57:25, seeded 4:58:00, and they flew. Run 4: spawned 17:15:26,
    seeded 17:15:46, and the next run's air-idle report had both GUER ones on
    NCAirG and NCCargoG. So such a class is EXCLUDED from NCAir and NCCargo
    (RHQs_NCAir, RHQs_NCCargo), which HAL subtracts every situation report
    whoever filed it first. Never seeded, and only for this case: an aircraft
    HAL can see a gun on is HAL's call, transport or not (the curated
    door-gun Ghost Hawk stays a transport).
*/

ITW_CLASH_HALTaxonomyEnabled = missionNamespace getVariable [
    "ITW_CLASH_HALTaxonomyEnabled",true
];
// Observation only: classify and log, write nothing. The kill switch.
ITW_CLASH_HALTaxonomyAdvisoryOnly = missionNamespace getVariable [
    "ITW_CLASH_HALTaxonomyAdvisoryOnly",false
];
ITW_CLASH_HALTaxonomyPoll = missionNamespace getVariable [
    "ITW_CLASH_HALTaxonomyPoll",60
];

// class -> [primary, capabilities, grade]. Also the "already decided" set, so
// a class costs its config walk once per mission rather than once per poll.
ITW_CLASH_HALTaxonomyDecided = createHashMap;

// The buckets this module is willing to speak for. Anything outside this list
// is the autofill's business and is never seeded or excluded here.
ITW_CLASH_HALTaxonomyPrimaries = ["Inf","Art","HArmor","LArmor","Cars","Air","Naval","Static"];
ITW_CLASH_HALTaxonomyCapabilities = ["LArmorAT","ATinf","AAinf","StaticAA","StaticAT"];
// v4: excluded, never seeded, for an aircraft armed only on its pylons.
ITW_CLASH_HALTaxonomyPylonAirExclusions = ["NCAir","NCCargo"];
// HAL's own flare list, as RYD_PresentRHQ subtracts it (HAC_fnc2.sqf:2327).
ITW_CLASH_HALTaxonomyHALFlareMagazines = [
    "Laserbatteries","60Rnd_CMFlareMagazine","120Rnd_CMFlareMagazine","240Rnd_CMFlareMagazine",
    "60Rnd_CMFlare_Chaff_Magazine","120Rnd_CMFlare_Chaff_Magazine","240Rnd_CMFlare_Chaff_Magazine",
    "192Rnd_CMFlare_Chaff_Magazine","168Rnd_CMFlare_Chaff_Magazine","300Rnd_CMFlare_Chaff_Magazine"
];

ITW_CLASH_HALTaxonomy_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["hal-taxonomy-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH HAL TAXONOMY | %1 | %2",_event,_payload];
    };
};

/*
    The classification. One primary bucket, zero or more capability buckets.

    Returns [] when CLASH has no confident opinion, which is the signal to
    leave the class to the autofill.
*/
ITW_CLASH_HALTaxonomy_fnc_Classify = {
    params ["_class"];
    if (_class isEqualTo "" || {!isClass (configFile >> "CfgVehicles" >> _class)}) exitWith {[]};
    if (isNil "ITW_CLASH_AirPicture_fnc_ClassProfile") exitWith {[]};

    private _profile = [_class] call ITW_CLASH_AirPicture_fnc_ClassProfile;
    private _antiArmor = _profile get "antiArmor";
    private _antiAir = _profile get "antiAir";

    private _isMan = _class isKindOf "Man";
    private _isStatic = _class isKindOf "StaticWeapon";
    private _isAir = _class isKindOf "Air";
    private _isShip = _class isKindOf "Ship";
    // Impasse and HAL both treat an artillery piece by its scanner, not its
    // chassis: that is what makes it indirect fire rather than a tank.
    private _isArtillery = (getNumber (configFile >> "CfgVehicles" >> _class >> "artilleryScanner")) > 0;

    private _grade = if (isNil "ITW_CLASH_AirPicture_fnc_ProtectionGrade") then {0} else {
        [_class] call ITW_CLASH_AirPicture_fnc_ProtectionGrade
    };

    private _primary = "";
    private _capabilities = [];

    if (_isMan) then {
        _primary = "Inf";
        // Guided versus unguided is a real distinction for standoff AT and is
        // deliberately NOT made here: HAL's ATinf bucket does not model it,
        // and conflating them in a bucket that cannot express it would hide
        // the problem rather than solve it. It belongs with the AT team work.
        if (_antiArmor) then {_capabilities pushBack "ATinf"};
        if (_antiAir) then {_capabilities pushBack "AAinf"};
    } else {
        if (_isStatic) then {
            _primary = "Static";
            if (_antiAir) then {_capabilities pushBack "StaticAA"};
            if (_antiArmor) then {_capabilities pushBack "StaticAT"};
        } else {
            if (_isAir) then {
                _primary = "Air";
            } else {
                if (_isShip) then {
                    _primary = "Naval";
                } else {
                    if (_isArtillery) then {
                        _primary = "Art";
                    } else {
                        if (!(_class isKindOf "LandVehicle")) exitWith {};
                        /*
                            Grade alone is not the armour question.

                            ProtectionGrade reads the config `armor` value,
                            which in Arma is STRUCTURAL HITPOINTS, not armour
                            protection - a big heavy truck scores higher than a
                            small hard one. Run5 proved it: grade 1 held both
                            the Rooikat and Marshall (right) and
                            truck_01_transport, truck_01_covered, three MRAP
                            variants and the armed Prowler (wrong). HAL's own
                            autofill puts those Car-based classes in RHQ_Cars
                            correctly, so this module was overriding a right
                            answer with a worse one.

                            Light armour therefore needs grade AND corroboration:
                            either a chassis the engine itself calls armour, or
                            the ability to actually fight armour. A truck is
                            neither. The Rooikat is the second - which is the
                            whole reason this module exists, since HAL cannot
                            see it (its AT test is guided-only and a tank gun
                            carries no lock).
                        */
                        private _armouredChassis = _class isKindOf "Tank"
                            || {_class isKindOf "Wheeled_APC_F"};
                        /*
                            HArmor requires the ability to kill armour.

                            HArmor is not a description of protection, it is a
                            DISPATCH POOL, and it is the one HAL sends at
                            tanks (HAC_fnc.sqf:1382). A vehicle that is heavily
                            armoured but cannot hurt armour does not belong
                            there - Hark's words: "namers should not be sent
                            against armor, they are heavily armored but their
                            gun cannot do at stuff."

                            run6 showed the same fault on two more: the tracked
                            CRV (an engineering vehicle) and the tracked AA
                            variant both landed in HArmor with no LArmorAT, so
                            a repair vehicle and an air defence vehicle were
                            both being dispatched against tanks.

                            Demotion to LArmor costs nothing, which is why it
                            is the right home: LArmorG appears in every pool
                            HArmorG does - Inf, Cars, Art, Static - except
                            Armor. So such a vehicle keeps every role it can
                            actually perform and loses only the one it cannot.
                        */
                        _primary = switch (true) do {
                            case (
                                _grade >= 2
                                && {_class isKindOf "Tank"}
                                && {_antiArmor}
                            ): {"HArmor"};
                            case (_grade >= 1 && {_armouredChassis || {_antiArmor}}): {"LArmor"};
                            default {"Cars"};
                        };
                        /*
                            LArmorAT is a PROMOTION, not a label for tank
                            destroyers.

                            HAL's anti-armour response pool is
                            [airCAS, HArmorG, LArmorATG, ATInfG]
                            (HAC_fnc.sqf:1382). Note what is absent: LArmorG.
                            Plain light armour is never sent at tanks, and
                            LArmorAT is the exception that lets a light hull
                            which CAN kill armour be counted as an armour
                            answer anyway.

                            So it is added only where the primary is LArmor.
                            A tank is already in HArmor, which is already in
                            that pool at the same weight - adding it here too
                            would enter the same vehicle twice and double its
                            dispatch weight against armour.
                        */
                        if (_primary isEqualTo "LArmor" && {_antiArmor}) then {
                            _capabilities pushBack "LArmorAT";
                        };
                    };
                };
            };
        };
    };

    if (_primary isEqualTo "") exitWith {[]};
    [_primary,_capabilities,_grade]
};

/*
    Write one class's verdict into HAL's own arrays.

    For every bucket this module speaks for, the class is either seeded or
    excluded - never both, since RHQs_* subtracts from the composed list and
    would cancel our own seed.
*/
ITW_CLASH_HALTaxonomy_fnc_Apply = {
    params ["_class","_primary","_capabilities"];
    private _mine = _capabilities + [_primary];
    private _seeded = [];
    private _excluded = [];

    {
        private _bucket = _x;
        private _seedVar = "RYD_WS_" + _bucket + "_class";
        private _excludeVar = "RHQs_" + _bucket;
        private _seed = +(missionNamespace getVariable [_seedVar,[]]);
        private _exclude = +(missionNamespace getVariable [_excludeVar,[]]);

        if (_bucket in _mine) then {
            // Ours: make sure it is seeded and not being subtracted back out.
            if !(_class in _seed) then {_seed pushBack _class; _seeded pushBack _bucket};
            _exclude = _exclude - [_class];
        } else {
            // Not ours: strip it, including anything the autofill already put
            // here before we had an opinion.
            _seed = _seed - [_class];
            if !(_class in _exclude) then {_exclude pushBack _class; _excluded pushBack _bucket};
        };

        missionNamespace setVariable [_seedVar,_seed];
        missionNamespace setVariable [_excludeVar,_exclude];
    } forEach (ITW_CLASH_HALTaxonomyPrimaries + ITW_CLASH_HALTaxonomyCapabilities);

    [_seeded,_excluded]
};

/*
    v4. The weapons an aircraft carries that HAL's autofill cannot see: its
    default rack (each pylon's attachment), when HAL's own armed test finds
    nothing but flares. [] when HAL can see a weapon, or there is none on the
    rack either.
*/
ITW_CLASH_HALTaxonomy_fnc_PylonOnlyWeapons = {
    params ["_class"];
    private _cfg = configFile >> "CfgVehicles" >> _class;
    if !(isClass _cfg) exitWith {[]};
    // HAL's test, as written: the class's magazines plus each top-level
    // turret's, less its flare list.
    private _halMags = getArray (_cfg >> "magazines");
    {
        _halMags append getArray (_x >> "magazines");
    } forEach ("true" configClasses (_cfg >> "Turrets"));
    if ((_halMags - ITW_CLASH_HALTaxonomyHALFlareMagazines) isNotEqualTo []) exitWith {[]};
    private _rack = ("true" configClasses (_cfg >> "Components" >> "TransportPylonsComponent" >> "Pylons")) apply {
        getText (_x >> "attachment")
    };
    _rack = _rack select {_x isNotEqualTo "" && {!(_x in ITW_CLASH_HALTaxonomyHALFlareMagazines)}};
    _rack arrayIntersect _rack
};

// v4. Take it off HAL's non-combat air and cargo lists, through the exclusion
// HAL subtracts each situation report. Returns the lists it was newly put on.
ITW_CLASH_HALTaxonomy_fnc_ArmPylonAir = {
    params ["_class"];
    private _excluded = [];
    {
        private _excludeVar = "RHQs_" + _x;
        private _exclude = +(missionNamespace getVariable [_excludeVar,[]]);
        if !(_class in _exclude) then {
            _exclude pushBack _class;
            _excluded pushBack _x;
        };
        missionNamespace setVariable [_excludeVar,_exclude];
    } forEach ITW_CLASH_HALTaxonomyPylonAirExclusions;
    _excluded
};

// Every class actually present, both sides. The lists are classname lists
// shared by all commanders, so there is no per-side taxonomy to build: a
// Rooikat is a Rooikat whoever owns it.
ITW_CLASH_HALTaxonomy_fnc_Present = {
    private _classes = [];
    {
        if (alive _x) then {
            private _class = toLowerANSI (typeOf _x);
            if (_class isNotEqualTo "") then {_classes pushBackUnique _class};
        };
    } forEach (vehicles + allUnits);
    _classes
};

ITW_CLASH_HALTaxonomy_fnc_Sweep = {
    private _new = 0;
    {
        private _class = _x;
        if (_class in ITW_CLASH_HALTaxonomyDecided) then {continue};

        private _verdict = [_class] call ITW_CLASH_HALTaxonomy_fnc_Classify;
        if (_verdict isEqualTo []) then {
            // No confident opinion. Record the decision so it is not retried
            // every poll, and leave the class to the autofill.
            ITW_CLASH_HALTaxonomyDecided set [_class,["<autofill>",[],-1]];
            ["deferred",[_class]] call ITW_CLASH_HALTaxonomy_fnc_Log;
            continue
        };
        _verdict params ["_primary","_capabilities","_grade"];
        ITW_CLASH_HALTaxonomyDecided set [_class,_verdict];
        _new = _new + 1;
        private _rack = if (_primary isEqualTo "Air") then {
            [_class] call ITW_CLASH_HALTaxonomy_fnc_PylonOnlyWeapons
        } else {[]};

        if (ITW_CLASH_HALTaxonomyAdvisoryOnly) then {
            ["would-classify",[_class,_primary,_capabilities,_grade]] call
                ITW_CLASH_HALTaxonomy_fnc_Log;
            if (_rack isNotEqualTo []) then {
                ["would-arm-pylon-air",[_class,_rack]] call ITW_CLASH_HALTaxonomy_fnc_Log;
            };
            continue
        };

        ([_class,_primary,_capabilities] call ITW_CLASH_HALTaxonomy_fnc_Apply)
            params ["_seeded","_excluded"];
        ["classified",[_class,_primary,_capabilities,_grade,_seeded,_excluded]] call
            ITW_CLASH_HALTaxonomy_fnc_Log;
        if (_rack isNotEqualTo []) then {
            ["armed-pylon-air",[
                _class,_rack,[_class] call ITW_CLASH_HALTaxonomy_fnc_ArmPylonAir
            ]] call ITW_CLASH_HALTaxonomy_fnc_Log;
        };
    } forEach (call ITW_CLASH_HALTaxonomy_fnc_Present);
    _new
};

[] spawn {
    scriptName "ITW_CLASH_HALTaxonomy";
    waitUntil {
        sleep 1;
        (
            !isNil "ITW_CLASH_AirPicture_fnc_ClassProfile"
            && {!isNil "ITW_CLASH_AirPicture_fnc_ProtectionGrade"}
            && {!isNil "RYD_WS_Inf_class"}
        ) || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    ITW_CLASH_HALTaxonomyReady = true;
    diag_log format [
        "CLASH BOOT | hal-taxonomy-ready | version=%1 advisoryOnly=%2 poll=%3 primaries=%4 capabilities=%5 autofillSuppressedForSeeded=true halUntouched=true pylonOnlyAirExcludedFrom=%6",
        ITW_CLASH_HALTaxonomyVersion,
        ITW_CLASH_HALTaxonomyAdvisoryOnly,
        ITW_CLASH_HALTaxonomyPoll,
        ITW_CLASH_HALTaxonomyPrimaries joinString ",",
        ITW_CLASH_HALTaxonomyCapabilities joinString ",",
        ITW_CLASH_HALTaxonomyPylonAirExclusions joinString ","
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_HALTaxonomyEnabled) then {
            private _new = call ITW_CLASH_HALTaxonomy_fnc_Sweep;
            if (_new > 0) then {
                ["swept",[_new,count ITW_CLASH_HALTaxonomyDecided]] call
                    ITW_CLASH_HALTaxonomy_fnc_Log;
            };
        };
        sleep ITW_CLASH_HALTaxonomyPoll;
    };
};

true
