#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AirDefenceRosterStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_AirDefenceRosterReady",false]
};

ITW_CLASH_AirDefenceRosterStarted = true;
ITW_CLASH_AirDefenceRosterReady = false;
ITW_CLASH_AirDefenceRosterVersion = 1;
scriptName "ITW_CLASH_AirDefenceRoster";

/*
    Who gets to be the enemy's air defence.

    Hark, repeatedly: "GEUR's spaa spawns as bluefor at all times, if it dies,
    it respawns as blufor."

    It was never a side-assignment bug. Both spawn paths set the side
    correctly - ITW_AtkSpawnVeh does createGroup [_side,false] and deletes the
    hull outright if crew fails, and RearBaseCRAM_fnc_Crew does
    createGroup [_side,true]. GUER was being handed a vehicle that IS BLUFOR,
    and then correctly crewed with GUER.

    VehicleArrays.sqf:723 derives the enemy AA list by filtering the enemy
    TANK list, and whitelists one classname by hand:

        _threat#2 > 0.9 || {_class in ["B_APC_Tracked_01_AA_F"]}

    B_APC_Tracked_01_AA_F is the Cheetah. The whitelist exists because the
    config `threat` array did not recognise a purpose-built SPAA - note the
    Cheetah sits in va_eTankClasses at all, meaning its own editorSubcategory
    is not "aa" either, so neither of the two tests upstream could find it.
    Someone papered over a bad capability test with a classname.

    It reaches GUER because the class lists admit it: VehicleArrays.sqf:160,
    vehicle mode 0 ("full"), sets _isEnemyFaction = !_isGlobalCivFaction, so
    every non-civilian vehicle in the game is eligible for the enemy list
    whatever its config side. GUER's whole order of battle is B_* on this
    mission, so the Cheetah is in the enemy tank list, the whitelist passes,
    and GUER's air defence is a NATO vehicle on every spawn and every respawn.

    Both of the enemy's AA sources read those lists, which is why it is
    everywhere: RearBaseCRAM.sqf:112 (statics, preferred) then :130 (mobile),
    and ITW_Targets.sqf:749 for zone AA.

    What this module does instead: rank candidates by what they can actually
    shoot down, read from magazine and ammo config via
    ITW_CLASH_AirPicture_fnc_ClassProfile - the same machinery that fixed the
    Namer's armour classification - and prefer a class whose config side is
    the owning side's. A cross-side hull stays available as an explicit last
    resort rather than a first pick, and says so loudly when it is used.

    Faction-agnostic on purpose. The next faction's SPAA is found on its
    weapons, so it does not have to be subcategorised "aa", does not have to
    score above 0.9 on a threat array, and does not have to be named here.

    It rewrites two mission-namespace lists once and owns nothing else. It
    never empties a list: ITW_Targets.sqf:27 reads emptiness as "this mission
    has no AA to destroy", so leaving a list worse than we found it would
    silently delete a side task.
*/

ITW_CLASH_AirDefenceRosterEnabled = missionNamespace getVariable [
    "ITW_CLASH_AirDefenceRosterEnabled",true
];
// Allow a borrowed hull from another side when the owning side has no air
// defence of its own. Turning this off is "side-correct or nothing".
ITW_CLASH_AirDefenceRosterAllowCrossSide = missionNamespace getVariable [
    "ITW_CLASH_AirDefenceRosterAllowCrossSide",true
];
ITW_CLASH_AirDefenceRosterTimeout = missionNamespace getVariable [
    "ITW_CLASH_AirDefenceRosterTimeout",180
];

ITW_CLASH_AirDefenceRoster_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["air-defence-roster-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH AIR DEFENCE ROSTER | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["air-defence-roster",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

// VehicleArrays stores either a classname or [classname,...]. Every consumer
// hands the whole entry to ITW_AtkSpawnVeh, which indexes it, so entries are
// carried through intact and only read here.
ITW_CLASH_AirDefenceRoster_fnc_ClassOf = {
    params ["_entry"];
    if (_entry isEqualType []) exitWith {
        if (_entry isEqualTo []) then {""} else {_entry#0}
    };
    if (_entry isEqualType "") exitWith {_entry};
    ""
};

/*
    The config side of a class, as a side ID: 0 OPFOR, 1 BLUFOR, 2 GREENFOR,
    3 civilian, -1 unknown.

    CSLA ships `side` as a string, which VehicleArrays.sqf:115 already has to
    work around, so a non-numeric value is read rather than assumed.
*/
ITW_CLASH_AirDefenceRoster_fnc_ConfigSideNum = {
    params ["_class"];
    if (_class isEqualTo "") exitWith {-1};
    private _entry = configFile >> "CfgVehicles" >> _class >> "side";
    if (isNumber _entry) exitWith {getNumber _entry};
    if (isText _entry) exitWith {
        switch (toLowerANSI getText _entry) do {
            case "teast": {0};
            case "twest": {1};
            case "tguerrila": {2};
            case "tguerrilla": {2};
            case "tcivilian": {3};
            default {-1};
        }
    };
    -1
};

/*
    How good an air defence answer is this, for this side?

    0  own side, guided          - a real SPAA
    1  own side, gun only        - flak, or a gun that happens to take AA ammo
    2  another side, guided
    3  another side, gun only
    -1 cannot engage aircraft at all

    Guided outranks gun because the gun tier includes things that are only
    incidentally anti-air, and side outranks capability because a borrowed
    hull is visibly the wrong army and reads as the wrong side the moment its
    crew is killed.
*/
ITW_CLASH_AirDefenceRoster_fnc_Tier = {
    params ["_entry","_expectedSideNum"];
    private _class = [_entry] call ITW_CLASH_AirDefenceRoster_fnc_ClassOf;
    if (_class isEqualTo "") exitWith {-1};
    if (isNil "ITW_CLASH_AirPicture_fnc_ClassProfile") exitWith {-1};

    private _profile = [_class] call ITW_CLASH_AirPicture_fnc_ClassProfile;
    if !(_profile get "antiAir") exitWith {-1};

    private _guided = _profile get "antiAirMissile";
    private _sideNum = [_class] call ITW_CLASH_AirDefenceRoster_fnc_ConfigSideNum;
    // An unknown config side is treated as the owning side's own. A mod that
    // does not declare one is not evidence of the wrong army.
    private _ownSide = _sideNum < 0 || {_sideNum == _expectedSideNum};

    if (_ownSide) exitWith {if (_guided) then {0} else {1}};
    if (_guided) then {2} else {3}
};

/*
    Pick the best tier that has anything in it, and keep every entry at that
    tier so the consumers still get a choice.
*/
ITW_CLASH_AirDefenceRoster_fnc_Rank = {
    params ["_pool","_expectedSideNum"];
    private _tiers = [[],[],[],[]];
    private _rejected = 0;
    {
        private _tier = [_x,_expectedSideNum] call ITW_CLASH_AirDefenceRoster_fnc_Tier;
        if (_tier < 0) then {_rejected = _rejected + 1} else {
            private _bucket = _tiers#_tier;
            if !(_x in _bucket) then {_bucket pushBack _x};
        };
    } forEach _pool;

    private _maxTier = if (ITW_CLASH_AirDefenceRosterAllowCrossSide) then {3} else {1};
    private _chosen = [];
    private _chosenTier = -1;
    for "_t" from 0 to _maxTier do {
        if (_chosenTier < 0 && {(_tiers#_t) isNotEqualTo []}) then {
            _chosen = _tiers#_t;
            _chosenTier = _t;
        };
    };
    [_chosen,_chosenTier,[count (_tiers#0),count (_tiers#1),count (_tiers#2),count (_tiers#3)],_rejected]
};

/*
    Correct one list in place.

    Fail-open in the strongest sense: the list is only written when a ranked
    answer exists, so every failure path leaves the mission exactly as Impasse
    built it.
*/
ITW_CLASH_AirDefenceRoster_fnc_Correct = {
    params ["_listVar","_poolVars","_expectedSideNum","_label"];
    private _before = +(missionNamespace getVariable [_listVar,[]]);

    private _pool = [];
    {
        {
            private _class = [_x] call ITW_CLASH_AirDefenceRoster_fnc_ClassOf;
            if (_class isNotEqualTo "" && {!(_x in _pool)}) then {_pool pushBack _x};
        } forEach (missionNamespace getVariable [_x,[]]);
    } forEach _poolVars;

    if (_pool isEqualTo []) exitWith {
        ["skipped",[_label,"empty-candidate-pool",_poolVars]] call
            ITW_CLASH_AirDefenceRoster_fnc_Log;
        false
    };

    ([_pool,_expectedSideNum] call ITW_CLASH_AirDefenceRoster_fnc_Rank) params [
        "_chosen","_tier","_counts","_rejected"
    ];

    if (_chosen isEqualTo []) exitWith {
        ["kept",[
            _label,"no-ranked-candidate",count _before,_counts,_rejected,
            ITW_CLASH_AirDefenceRosterAllowCrossSide
        ]] call ITW_CLASH_AirDefenceRoster_fnc_Log;
        false
    };

    missionNamespace setVariable [_listVar,_chosen];

    private _dropped = _before select {!(_x in _chosen)};
    ["corrected",[
        _label,_tier,count _before,count _chosen,_counts,_rejected,
        (_dropped apply {[_x] call ITW_CLASH_AirDefenceRoster_fnc_ClassOf})
    ]] call ITW_CLASH_AirDefenceRoster_fnc_Log;

    if (_tier >= 2) then {
        diag_log format [
            "CLASH AIR DEFENCE ROSTER | WARNING | cross-side-air-defence | list=%1 side=%2 classes=%3 | this side has no air defence of its own; the hull is another army's and will read as that side if its crew is killed",
            _label,
            _expectedSideNum,
            (_chosen apply {[_x] call ITW_CLASH_AirDefenceRoster_fnc_ClassOf})
        ];
    };
    true
};

if (!ITW_CLASH_AirDefenceRosterEnabled) exitWith {
    ["disabled",[]] call ITW_CLASH_AirDefenceRoster_fnc_Log;
    ITW_CLASH_AirDefenceRosterReady = false;
    false
};

[] spawn {
    scriptName "ITW_CLASH_AirDefenceRoster_boot";

    // VehicleArrays.sqf is execVM'd from ITW_Start.sqf:562, so it is scheduled
    // and async relative to init.sqf's C.L.A.S.H. chain. Its own completion
    // flag is the only honest way to know the lists are final rather than
    // half-built - va_eAAClasses is initialised to [] at its line 93, so
    // "defined" would fire several hundred lines too early.
    private _deadline = time + ITW_CLASH_AirDefenceRosterTimeout;
    waitUntil {
        sleep 0.25;
        (
            (missionNamespace getVariable ["ITW_CLASH_VehicleArraysReady",false])
            && {missionNamespace getVariable ["ITW_CLASH_AirPictureReady",false]}
            && {!isNil "ITW_EnemySide"}
        )
        || {time >= _deadline}
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    if !(missionNamespace getVariable ["ITW_CLASH_VehicleArraysReady",false]) exitWith {
        ["failed",["vehicle-arrays-not-ready"]] call ITW_CLASH_AirDefenceRoster_fnc_Log;
        diag_log "CLASH BOOT | WARNING | air-defence-roster-failed | reason=vehicle-arrays-not-ready | stock Impasse AA lists retained";
    };
    if !(missionNamespace getVariable ["ITW_CLASH_AirPictureReady",false]) exitWith {
        ["failed",["air-picture-not-ready"]] call ITW_CLASH_AirDefenceRoster_fnc_Log;
        diag_log "CLASH BOOT | WARNING | air-defence-roster-failed | reason=air-picture-not-ready | stock Impasse AA lists retained";
    };
    if (isNil "ITW_EnemySide") exitWith {
        ["failed",["no-enemy-side"]] call ITW_CLASH_AirDefenceRoster_fnc_Log;
    };

    private _expectedSideNum = ITW_EnemySide call BIS_fnc_sideID;

    /*
        Two lists, because the rear base reads statics FIRST
        (RearBaseCRAM.sqf:112 before :130). Correcting only the mobile list
        would leave the emplacement Hark actually sees untouched.

        The candidate pools are deliberately the enemy's OWN lists. This
        module never widens what the enemy may field - it only reorders and
        filters what Impasse already decided they could have.
    */
    private _mobile = [
        "va_eAAClasses",
        ["va_eAAClasses","va_eTankClasses","va_eApcClasses"],
        _expectedSideNum,
        "enemy-mobile"
    ] call ITW_CLASH_AirDefenceRoster_fnc_Correct;

    private _static = [
        "va_eStaticAAClasses",
        ["va_eStaticAAClasses","va_eStaticClasses"],
        _expectedSideNum,
        "enemy-static"
    ] call ITW_CLASH_AirDefenceRoster_fnc_Correct;

    ITW_CLASH_AirDefenceRosterReady = true;
    diag_log format [
        "CLASH BOOT | air-defence-roster-ready | version=%1 enemySide=%2 sideId=%3 mobileCorrected=%4 staticCorrected=%5 mobile=%6 static=%7 allowCrossSide=%8 capabilityTest=ClassProfile neverEmpties=true",
        ITW_CLASH_AirDefenceRosterVersion,
        ITW_EnemySide,
        _expectedSideNum,
        _mobile,
        _static,
        (missionNamespace getVariable ["va_eAAClasses",[]]) apply {
            [_x] call ITW_CLASH_AirDefenceRoster_fnc_ClassOf
        },
        (missionNamespace getVariable ["va_eStaticAAClasses",[]]) apply {
            [_x] call ITW_CLASH_AirDefenceRoster_fnc_ClassOf
        },
        ITW_CLASH_AirDefenceRosterAllowCrossSide
    ];
};

true
