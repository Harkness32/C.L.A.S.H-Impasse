#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALThreatCoverageStarted",false]) exitWith {true};
ITW_CLASH_HALThreatCoverageStarted = true;
ITW_CLASH_HALThreatCoverageVersion = 6;
ITW_CLASH_HALThreatCoverageReady = false;

/*
    Threat coverage, on the Emerging Threats Budget.

    Version 5 asked Impasse for a counter through the Checkbook, across twelve
    of HAL's dispatch categories. It could not win: Impasse's own spawner shares
    those rows and empties them first, so 4 of 117 threat purchases went through
    in the 81-minute peer run of 2026-09-25, and what each commander fielded was
    Impasse's random pick rather than HAL's decision. Combat buys now leave
    Impasse's rows entirely and go to the ETB.

    That means fewer needs, on purpose. The ETB answers two: anti-armor and
    counter-air, the gaps the baseline army structurally cannot close. Enemy
    infantry, cars, statics, artillery and cargo never open ETB demand - those
    stay the baseline army's job, and HAL already hunts them with what Impasse
    builds.

    This file owns demand, and the instant reactions to an air signal. It asks
    for a NEED, never a vehicle type: the ETB decides whether a counter can be
    paid for and Force Generation decides what can be built. A demand is one
    open need per commander per capability, carrying the threat that caused it,
    so ten enemy tanks open one anti-armor demand and not ten purchases, and HAL
    no longer has to re-ask every cycle.

    Threats are classified from the vehicle, not from HAL's categories: HAL is
    the source of WHICH enemies are known (invariant 2) and nothing more,
    because its own categories file a Rhino as a car and a Bobcat as heavy
    armor. See ITW_CLASH_AirPicture.sqf, which owns every such test.
*/

ITW_CLASH_ThreatCoveragePoll = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoveragePoll",20
];
// Ground demand has to persist before it is funded: the first skirmish should
// not spend the starting reserve on a blip, and both commanders had demands by
// minute 6 of the peer run.
ITW_CLASH_ThreatCoverageGroundPersistence = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageGroundPersistence",90
];
// Grace before a demand closes, so ages mean something as HAL loses and regains
// contact. A demand that reopens inside its grace keeps its age.
ITW_CLASH_ThreatCoverageGroundGrace = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageGroundGrace",180
];
ITW_CLASH_ThreatCoverageAirGrace = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageAirGrace",300
];
// A provider type that HAL would not employ is not tried again for this demand
// for a while: the next purchase tries the other one.
ITW_CLASH_ThreatCoverageFailureMemory = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageFailureMemory",600
];
ITW_CLASH_ThreatCoverageCommitmentTimeout = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageCommitmentTimeout",900
];
// An asset still driving to its demand counts as committed to it, or the air
// lane - which has no funding wait - buys a second SPAA at the next pacing
// interval while the first is still on the road.
ITW_CLASH_ThreatCoverageEnRouteWindow = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageEnRouteWindow",600
];
// Weights. Four launcher squads equal one dedicated asset: at full weight
// Impasse's launcher dispersion would cover almost any armor threat on paper,
// at zero we would ignore that AI launcher teams do kill armor.
ITW_CLASH_ThreatCoverageInfantryWeight = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageInfantryWeight",0.25
];
ITW_CLASH_ThreatCoverageAAInfantryUmbrella = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageAAInfantryUmbrella",3000
];
// The cue players hear when the other side has spotted the counter-air it
// bought. Player high command stays disabled: HAL alone employs ETB assets.
ITW_CLASH_ThreatCoverageAirWarning = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageAirWarning",true
];

ITW_CLASH_ThreatCoverageDemands = createHashMap;
ITW_CLASH_ThreatCoverageCommitments = createHashMap;
ITW_CLASH_ThreatCoverageZoneSignature = -1;

ITW_CLASH_HALThreatCoverage_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-threat-coverage-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL THREAT COVERAGE | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_HALThreatCoverage_fnc_SideKey = {
    params ["_side"];
    toUpperANSI str _side
};

ITW_CLASH_HALThreatCoverage_fnc_ThreatKey = {
    params ["_object"];
    if (isNull _object) exitWith {""};
    private _group = if (_object isEqualType grpNull) then {_object} else {
        group effectiveCommander _object
    };
    if (isNull _group) exitWith {str _object};
    groupId _group
};

ITW_CLASH_HALThreatCoverage_fnc_DescribeNeed = {
    params ["_need"];
    switch (_need) do {
        case "ANTI_ARMOR": {"enemy armor"};
        case "COUNTER_AIR": {"enemy combat aircraft"};
        default {_need};
    }
};

// ----------------------------------------------------------------- threats

/*
    Anti-armor threats: every enemy HAL knows about that our own test calls an
    armored vehicle carrying anti-armor weapons, rechecked as alive and still
    known at evaluation. HAL's lists refresh once per cycle, so a dead tank can
    still sit in them.
*/
ITW_CLASH_HALThreatCoverage_fnc_ArmorThreats = {
    params ["_hq"];
    if (isNull _hq || {isNil "ITW_CLASH_AirPicture_fnc_IsArmoredThreat"}) exitWith {[]};
    private _known = _hq getVariable ["RydHQ_KnEnemies",[]];
    private _threats = [];
    {
        private _veh = vehicle _x;
        if (isNull _veh || {!alive _veh}) then {continue};
        if (_veh in _threats) then {continue};
        if !([_veh] call ITW_CLASH_AirPicture_fnc_IsArmoredThreat) then {continue};
        _threats pushBack _veh;
    } forEach _known;
    _threats
};

// Counter-air threats come from the air picture, which is the only thing fast
// enough to see them. Each entry carries whether it may be funded at once.
ITW_CLASH_HALThreatCoverage_fnc_AirThreats = {
    params ["_hq"];
    if (isNull _hq || {isNil "ITW_CLASH_AirPicture_fnc_Hostiles"}) exitWith {[]};
    [_hq] call ITW_CLASH_AirPicture_fnc_Hostiles
};

// --------------------------------------------------------------- responders

ITW_CLASH_HALThreatCoverage_fnc_UsableGroups = {
    params ["_groups","_hq"];
    private _attackAv = _hq getVariable ["RydHQ_AttackAv",[]];
    private _NCVeh = _hq getVariable ["RydHQ_NCVeh",[]];
    _groups select {
        !isNull _x
        && {alive (leader _x)}
        && {_x in _attackAv}
        && {!(_x getVariable [("Busy" + str _x),false])}
        && {!(_x getVariable ["Unable",false])}
        && {([_x,_NCVeh] call RYD_AmmoCount) > 0}
        && {(vehicle (leader _x)) == (leader _x) || {canMove (vehicle (leader _x))}}
    }
};

/*
    A group carrying a launcher it can still fire. HAL counts any squad with an
    AT soldier as AT infantry (HAC_fnc2.sqf:727,758), and Impasse's launcher
    dispersion puts one in most squads, so "has a launcher" alone is not a
    responder - it has to be loaded.
*/
ITW_CLASH_HALThreatCoverage_fnc_HasLoadedLauncher = {
    params ["_group",["_kind","AT"]];
    if (isNull _group) exitWith {false};
    if (isNil "ITW_CLASH_AirPicture_fnc_IsAntiAirAmmo" || {
        isNil "ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo"
    }) exitWith {false};
    private _test = if (_kind isEqualTo "AA") then {
        ITW_CLASH_AirPicture_fnc_IsAntiAirAmmo
    } else {
        ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo
    };
    private _index = (units _group) findIf {
        private _unit = _x;
        alive _unit && {(secondaryWeapon _unit) isNotEqualTo ""} && {
            private _magazines = (magazines _unit) + (secondaryWeaponMagazine _unit);
            (_magazines findIf {
                [getText (configFile >> "CfgMagazines" >> _x >> "ammo")] call _test
            }) >= 0
        }
    };
    _index >= 0
};

// Committed to a demand while still travelling: bought for this need, not yet
// tasked, and inside the en-route window. A counter that has not arrived is
// still an answer on its way.
ITW_CLASH_HALThreatCoverage_fnc_EnRoute = {
    params ["_side","_need"];
    if (isNil "ITW_CLASH_ETB_fnc_Assets") exitWith {0};
    private _count = 0;
    {
        if ((_x get "need") isEqualTo _need && {
            (time - (_x get "purchasedAt")) <= ITW_CLASH_ThreatCoverageEnRouteWindow
        }) then {
            private _veh = _x get "vehicle";
            if (!isNull _veh && {alive _veh}) then {_count = _count + 1};
        };
    } forEach ([_side] call ITW_CLASH_ETB_fnc_Assets);
    _count
};

/*
    Anti-armor coverage. A vehicle or aircraft with live anti-armor ammo counts
    1, but only if HAL can actually use it or is already using it against armor:
    a squad tasked against the objective's infantry is not an armor answer.
    Launcher squads count a quarter each.
*/
ITW_CLASH_HALThreatCoverage_fnc_ArmorCoverage = {
    params ["_hq","_threats"];
    private _side = side _hq;
    private _coverage = 0;
    private _counted = [];

    private _pools = (_hq getVariable ["RydHQ_LArmorG",[]])
        + (_hq getVariable ["RydHQ_HArmorG",[]])
        + (_hq getVariable ["RydHQ_LArmorATG",[]])
        + (_hq getVariable ["RydHQ_CarsG",[]]);
    private _airPools = [_hq] call ITW_CLASH_HALThreatCoverage_fnc_EffectiveAirPools;
    _pools = _pools + (_airPools#0);

    {
        private _group = _x;
        if (isNull _group || {_group in _counted}) then {continue};
        private _veh = vehicle leader _group;
        if (isNull _veh || {!alive _veh}) then {continue};
        if (isNil "ITW_CLASH_AirPicture_fnc_WeaponProfile") then {continue};
        if !(([_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile) get "antiArmor") then {continue};
        private _usable = ([[_group],_hq] call ITW_CLASH_HALThreatCoverage_fnc_UsableGroups) isNotEqualTo [];
        private _tasked = [_hq,_group,_threats,"ANTI_ARMOR"] call
            ITW_CLASH_HALThreatCoverage_fnc_TaskedAgainst;
        if (!_usable && {!_tasked}) then {continue};
        _counted pushBack _group;
        _coverage = _coverage + 1;
    } forEach _pools;

    {
        private _group = _x;
        if (isNull _group || {_group in _counted}) then {continue};
        if !([_group,"AT"] call ITW_CLASH_HALThreatCoverage_fnc_HasLoadedLauncher) then {continue};
        _counted pushBack _group;
        _coverage = _coverage + ITW_CLASH_ThreatCoverageInfantryWeight;
    } forEach (_hq getVariable ["RydHQ_ATInfG",[]]);

    _coverage + ([_side,"ANTI_ARMOR"] call ITW_CLASH_HALThreatCoverage_fnc_EnRoute)
};

/*
    Counter-air coverage. Fighters count 1 wherever they are - they fly. Every
    ground answer counts only for enemy aircraft inside its own umbrella, which
    is what keeps the earlier map-wide AA count (commit 0689ac9) from coming
    back: an AA squad on the far side of the map covers nothing.

    Air defence weights come from ITW_CLASH_AirPicture.sqf, read off the weapon
    itself, so modded statics work without class lists. Counting the rear-base
    C-RAM is deliberate: an enemy jet circling our rear base should not buy a
    fighter, and once it moves over the front it leaves the umbrella.
*/
ITW_CLASH_HALThreatCoverage_fnc_AirCoverage = {
    params ["_hq","_threats"];
    private _side = side _hq;
    private _coverage = 0;
    private _positions = _threats apply {_x#1};
    if (_positions isEqualTo []) exitWith {0};

    private _covers = {
        params ["_position","_umbrella"];
        (_positions findIf {(_x distance2D _position) <= _umbrella}) >= 0
    };

    private _counted = [];
    private _airPools = [_hq] call ITW_CLASH_HALThreatCoverage_fnc_EffectiveAirPools;
    {
        private _group = _x;
        if (isNull _group || {_group in _counted}) then {continue};
        private _veh = vehicle leader _group;
        if (isNil "ITW_CLASH_AirPicture_fnc_IsFighter") then {continue};
        if !([_veh] call ITW_CLASH_AirPicture_fnc_IsFighter) then {continue};
        private _usable = ([[_group],_hq] call ITW_CLASH_HALThreatCoverage_fnc_UsableGroups) isNotEqualTo [];
        private _tasked = [_hq,_group,_threats,"COUNTER_AIR"] call
            ITW_CLASH_HALThreatCoverage_fnc_TaskedAgainst;
        if (!_usable && {!_tasked}) then {continue};
        _counted pushBack _group;
        _coverage = _coverage + 1;
    } forEach (_airPools#1);

    // Every air defence on the side, vehicle or static, weighted and local.
    private _seen = [];
    {
        private _veh = vehicle _x;
        if (isNull _veh || {!alive _veh} || {_veh in _seen}) then {continue};
        _seen pushBack _veh;
        if (isNil "ITW_CLASH_AirPicture_fnc_AirDefenceProfile") then {continue};
        ([_veh] call ITW_CLASH_AirPicture_fnc_AirDefenceProfile) params ["_kind","_weight","_umbrella"];
        if (_kind isEqualTo "" || {_weight <= 0}) then {continue};
        // A MANPAD is counted through its group below, not per soldier.
        if (_kind isEqualTo "MANPAD") then {continue};
        if !([getPosATL _veh,_umbrella] call _covers) then {continue};
        _coverage = _coverage + _weight;
    } forEach (
        // Vehicles and statics only. A MANPAD soldier is counted through his
        // group below, and walking every man on the side every poll to find
        // out he is not a SAM site is not worth the frames.
        vehicles select {
            !isNull _x && {alive _x} && {
                private _commander = effectiveCommander _x;
                !isNull _commander && {side (group _commander) isEqualTo _side}
            }
        }
    );

    {
        private _group = _x;
        if (isNull _group) then {continue};
        if !([_group,"AA"] call ITW_CLASH_HALThreatCoverage_fnc_HasLoadedLauncher) then {continue};
        private _leader = leader _group;
        if (isNull _leader) then {continue};
        if !([getPosATL (vehicle _leader),ITW_CLASH_ThreatCoverageAAInfantryUmbrella] call _covers) then {continue};
        _coverage = _coverage + ITW_CLASH_ThreatCoverageInfantryWeight;
    } forEach (_hq getVariable ["RydHQ_AAInfG",[]]);

    _coverage + ([_side,"COUNTER_AIR"] call ITW_CLASH_HALThreatCoverage_fnc_EnRoute)
};

/*
    Coverage is observed, not assumed. Our offer hands HAL the commander's whole
    group pool, so HAL may task a different group than the one we bought: a
    threat is covered only when some capable responder is actually tasked
    against it, which is what the commitment map records at offer time.
*/
ITW_CLASH_HALThreatCoverage_fnc_TaskedAgainst = {
    params ["_hq","_group","_threats","_need"];
    if (isNull _group) exitWith {false};
    if !(_group getVariable ["Busy" + str _group,false]) exitWith {false};
    private _target = _group getVariable ["ITW_CLASH_ThreatCoverageTarget",objNull];
    private _committedNeed = _group getVariable ["ITW_CLASH_ThreatCoverageNeed",""];
    private _committedAt = _group getVariable ["ITW_CLASH_ThreatCoverageCommittedAt",0];
    if (_committedNeed isNotEqualTo _need) exitWith {false};
    if ((time - _committedAt) > ITW_CLASH_ThreatCoverageCommitmentTimeout) exitWith {false};
    if (isNull _target) exitWith {false};
    private _keys = _threats apply {
        [if (_x isEqualType []) then {_x#0} else {_x}] call
            ITW_CLASH_HALThreatCoverage_fnc_ThreatKey
    };
    ([_target] call ITW_CLASH_HALThreatCoverage_fnc_ThreatKey) in _keys
};

ITW_CLASH_HALThreatCoverage_fnc_Commit = {
    params ["_group","_target","_need"];
    if (isNull _group) exitWith {false};
    _group setVariable ["ITW_CLASH_ThreatCoverageTarget",_target];
    _group setVariable ["ITW_CLASH_ThreatCoverageNeed",_need];
    _group setVariable ["ITW_CLASH_ThreatCoverageCommittedAt",time];
    true
};

// HAL's own RYD_Dispatcher merges eligible general-purpose air into BOTH airCAS
// and airCAP on top of the dedicated pools (HAC_fnc.sqf's RYD_Dispatcher). A
// naive RCAS+BAirG read undercounts what HAL can actually field, which used to
// buy aircraft HAL did not need.
ITW_CLASH_HALThreatCoverage_fnc_EffectiveAirPools = {
    params ["_hq"];
    private _airCAS = +(_hq getVariable ["RydHQ_RCAS",[]]);
    private _airCAP = +(_hq getVariable ["RydHQ_RCAP",[]]);
    private _BAir   = _hq getVariable ["RydHQ_BAirG",[]];
    private _air    = (_hq getVariable ["RydHQ_AirG",[]]) - (
        (_hq getVariable ["RydHQ_NCAirG",[]])
        + (_hq getVariable ["RydHQ_NCrewInfG",[]])
        + (_hq getVariable ["RydHQ_AmmoDrop",[]])
    );
    {if !(_x in _airCAS) then {_airCAS pushBack _x}} forEach _BAir;
    {if !(_x in (_airCAP + _airCAS)) then {_airCAS pushBack _x; _airCAP pushBack _x}} forEach _air;
    [_airCAS,_airCAP]
};

// ------------------------------------------------------------------ demands

ITW_CLASH_HALThreatCoverage_fnc_Demands = {
    params ["_side"];
    private _key = [_side] call ITW_CLASH_HALThreatCoverage_fnc_SideKey;
    private _demands = ITW_CLASH_ThreatCoverageDemands getOrDefault [_key,createHashMap];
    if (count _demands == 0) then {
        ITW_CLASH_ThreatCoverageDemands set [_key,_demands];
    };
    _demands
};

/*
    Open, refresh or close the demand for one need.

    A demand keeps its age while it is merely unseen, so ages mean something as
    HAL loses and regains contacts; it is dropped once the grace period passes,
    and a demand that reopens inside its grace keeps the age it had.
*/
ITW_CLASH_HALThreatCoverage_fnc_Refresh = {
    params ["_hq","_need","_threats","_shortfall",["_immediate",false]];
    private _side = side _hq;
    private _demands = [_side] call ITW_CLASH_HALThreatCoverage_fnc_Demands;
    private _demand = _demands getOrDefault [_need,createHashMap];
    private _grace = if (_need isEqualTo "COUNTER_AIR") then {
        ITW_CLASH_ThreatCoverageAirGrace
    } else {
        ITW_CLASH_ThreatCoverageGroundGrace
    };
    private _result = createHashMap;
    private _covered = _shortfall <= 0 || {_threats isEqualTo []};

    // Covered or unseen: keep the demand while it is inside its grace, so ages
    // mean something as HAL loses and regains contacts, then drop it.
    if (_covered && {count _demand > 0}) then {
        _demand set ["shortfall",_shortfall];
        if ((time - (_demand get "lastSeenAt")) >= _grace) then {
            _demands deleteAt _need;
            ["demand-closed",[
                _hq getVariable ["RydHQ_CodeSign","?"],_need,
                round (time - (_demand get "openedAt"))
            ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
        } else {
            _result = _demand;
        };
    };

    if (!_covered) then {
        private _threat = if ((_threats#0) isEqualType []) then {(_threats#0)#0} else {_threats#0};
        private _key = [_threat] call ITW_CLASH_HALThreatCoverage_fnc_ThreatKey;
        if (count _demand == 0) then {
            _demand = createHashMapFromArray [
                ["need",_need],
                ["threat",_threat],
                ["threatKey",_key],
                ["openedAt",time],
                ["ageAt",time],
                ["lastSeenAt",time],
                ["shortfall",_shortfall],
                ["failed",createHashMap],
                ["immediate",_immediate]
            ];
            _demands set [_need,_demand];
            ["demand-opened",[
                _hq getVariable ["RydHQ_CodeSign","?"],_need,_key,
                (round (_shortfall * 100)) / 100,_immediate
            ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
        } else {
            _demand set ["threat",_threat];
            _demand set ["threatKey",_key];
            _demand set ["lastSeenAt",time];
            _demand set ["shortfall",_shortfall];
            if (_immediate) then {_demand set ["immediate",true]};
        };
        _result = _demand;
    };
    _result
};

// Funded: a ground demand has to have persisted; the first air response is
// funded at once, which is the whole point of the fast air lane.
ITW_CLASH_HALThreatCoverage_fnc_Funded = {
    params ["_demand"];
    if (count _demand == 0) exitWith {false};
    if ((_demand get "need") isEqualTo "COUNTER_AIR") exitWith {
        (_demand get "immediate") || {
            (time - (_demand get "openedAt")) >= ITW_CLASH_ThreatCoverageGroundPersistence
        }
    };
    (time - (_demand get "openedAt")) >= ITW_CLASH_ThreatCoverageGroundPersistence
};

ITW_CLASH_HALThreatCoverage_fnc_ProviderFailed = {
    params ["_demand","_capability"];
    ((_demand get "failed") getOrDefault [_capability,0]) > time
};

ITW_CLASH_HALThreatCoverage_fnc_MarkProviderFailed = {
    params ["_hq","_demand","_capability"];
    (_demand get "failed") set [_capability,time + ITW_CLASH_ThreatCoverageFailureMemory];
    ["provider-failed",[
        _hq getVariable ["RydHQ_CodeSign","?"],_demand get "need",_capability,
        ITW_CLASH_ThreatCoverageFailureMemory
    ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
    true
};

// A zone change invalidates every demand and every failure memory: different
// objectives, different geometry, different enemies.
ITW_CLASH_HALThreatCoverage_fnc_ZoneGuard = {
    private _zone = missionNamespace getVariable ["ITW_ZoneIndex",-1];
    if (_zone isEqualTo ITW_CLASH_ThreatCoverageZoneSignature) exitWith {false};
    ITW_CLASH_ThreatCoverageZoneSignature = _zone;
    ITW_CLASH_ThreatCoverageDemands = createHashMap;
    ITW_CLASH_ThreatCoverageCommitments = createHashMap;
    ["demands-cleared",["zone-change",_zone]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
    true
};

// -------------------------------------------------------- existing answers

/*
    Hand a group to HAL against the threat that caused the demand. HAL decides:
    the group enters AttackAv and RYD_Dispatcher is offered the commander's
    whole pool, keeping HAL's own terrain, weather, AT and AA resignation. If
    HAL declines, the group stays available and counts as coverage next poll.
*/
ITW_CLASH_HALThreatCoverage_fnc_Offer = {
    params ["_hq","_group","_threat","_need",["_source","offer"]];
    if (isNull _group || {({alive _x} count units _group) <= 0}) exitWith {false};
    if (isNull _threat || {!alive _threat}) exitWith {false};

    private _attackAv = +(_hq getVariable ["RydHQ_AttackAv",[]]);
    _attackAv pushBackUnique _group;
    _hq setVariable ["RydHQ_AttackAv",_attackAv];
    _group setVariable ["Busy" + str _group,false];

    private _targetGroup = group effectiveCommander _threat;
    if (isNull _targetGroup) exitWith {false};
    private _kind = if (_need isEqualTo "COUNTER_AIR") then {"Air"} else {"Armor"};

    if (!isNil "RYD_Dispatcher") then {
        private _snipersG  = _hq getVariable ["RydHQ_snipersG",[]];
        private _NCrewInfG = (_hq getVariable ["RydHQ_NCrewInfG",[]]) -
            (_hq getVariable ["RydHQ_SpecForG",[]]);
        private _air = (_hq getVariable ["RydHQ_AirG",[]]) - (
            (_hq getVariable ["RydHQ_NCAirG",[]])
            + (_hq getVariable ["RydHQ_NCrewInfG",[]])
            + (_hq getVariable ["RydHQ_AmmoDrop",[]])
        );
        private _cars = (_hq getVariable ["RydHQ_CarsG",[]]) - (
            (_hq getVariable ["RydHQ_ATInfG",[]])
            + (_hq getVariable ["RydHQ_AAInfG",[]])
            + (_hq getVariable ["RydHQ_SupportG",[]])
            + (_hq getVariable ["RydHQ_NCCargoG",[]])
        );
        private _fPool = [
            _snipersG,
            _NCrewInfG,
            _air,
            _hq getVariable ["RydHQ_LArmorG",[]],
            _hq getVariable ["RydHQ_HArmorG",[]],
            _cars,
            _hq getVariable ["RydHQ_LArmorATG",[]],
            _hq getVariable ["RydHQ_ATInfG",[]],
            _hq getVariable ["RydHQ_AAInfG",[]],
            _hq getVariable ["RydHQ_Recklessness",0.5],
            _hq getVariable ["RydHQ_AttackAv",[]],
            _hq getVariable ["RydHQ_Garrison",[]],
            _hq getVariable ["RydHQ_GarrR",500],
            _hq getVariable ["RydHQ_FlankAv",[]],
            _hq getVariable ["RydHQ_AirG",[]],
            _hq getVariable ["RydHQ_NCVeh",[]],
            _hq getVariable ["RydHQ_NavalG",[]],
            _hq getVariable ["RydHQ_RCAS",[]],
            _hq getVariable ["RydHQ_RCAP",[]],
            _hq getVariable ["RydHQ_BAirG",[]]
        ];
        private _risk = if (_need isEqualTo "COUNTER_AIR") then {[0,0,75]} else {[50,0,85]};
        ([
            [_targetGroup],_kind,_hq,_risk#0,_risk#1,_risk#2,
            _hq getVariable ["RydHQ_AAthreat",[]],
            _hq getVariable ["RydHQ_ATthreat",[]],
            (_hq getVariable ["RydHQ_EnHArmor",[]]) +
                (_hq getVariable ["RydHQ_EnLArmorAT",[]]),
            _fPool
        ]) call RYD_Dispatcher;
    };

    private _busy = _group getVariable ["Busy" + str _group,false];
    if (_busy) then {
        [_group,_threat,_need] call ITW_CLASH_HALThreatCoverage_fnc_Commit;
    };
    ["offer",[
        _hq getVariable ["RydHQ_CodeSign","?"],_need,_source,
        typeOf (vehicle leader _group),groupId _group,
        [_threat] call ITW_CLASH_HALThreatCoverage_fnc_ThreatKey,
        if (_busy) then {"hal-selected"} else {"available"}
    ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
    _busy
};

// ETB assets already bought for this need that HAL has left without a task.
// Survival is rewarded: one of these is re-offered before any new purchase.
ITW_CLASH_HALThreatCoverage_fnc_IdleAssets = {
    params ["_hq","_need"];
    if (isNil "ITW_CLASH_ETB_fnc_Assets") exitWith {[]};
    private _NCVeh = _hq getVariable ["RydHQ_NCVeh",[]];
    ([side _hq] call ITW_CLASH_ETB_fnc_Assets) select {
        (_x get "need") isEqualTo _need
        && {
            private _group = _x get "group";
            private _veh = _x get "vehicle";
            !isNull _group && {!isNull _veh} && {alive _veh} && {canMove _veh}
            && {!(_group getVariable ["Busy" + str _group,false])}
            && {!(_group getVariable ["Resting" + str _group,false])}
            && {!(_group getVariable ["Unable",false])}
            && {!(_group getVariable ["ITW_CLASH_ResupplyClaimed",false])}
            && {!(_group getVariable ["ITW_CLASH_SPAAOverwatch",false])}
            && {([_group,_NCVeh] call RYD_AmmoCount) > 0}
        }
    }
};

// ------------------------------------------------------------- provider choice

/*
    Which provider answers this need. For counter-air it is whichever the
    faction can field, CAP first when an airport exists because it is the fast
    answer (1-3 minutes against an SPAA's drive). For anti-armor the AA corridor
    decides: cold favours CAS because it arrives fastest, contested is a random
    pick, and hot or air-denied is ground only - a CAS aircraft sent into live
    air defence is a gift.
*/
ITW_CLASH_HALThreatCoverage_fnc_ChooseProvider = {
    params ["_hq","_demand","_threat"];
    private _need = _demand get "need";
    private _side = side _hq;
    private _options = ([_need] call ITW_CLASH_Generation_fnc_ETBProvidersFor) select {
        !([_demand,_x] call ITW_CLASH_HALThreatCoverage_fnc_ProviderFailed)
    };
    if (_options isEqualTo []) exitWith {["","all-providers-failed"]};

    if (_need isEqualTo "COUNTER_AIR") exitWith {
        // CAP if we own an airport, SPAA otherwise: SPAA is what gives a side
        // without an airport a counter-air answer at all.
        private _friendly = !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide};
        private _ownsAirport = if (isNil "ITW_ObjOwnsAirport") then {false} else {
            _friendly call ITW_ObjOwnsAirport
        };
        if (_ownsAirport && {"CAP_AIRCRAFT" in _options}) exitWith {["CAP_AIRCRAFT","airport-owned"]};
        if ("SPAA" in _options) exitWith {["SPAA","no-airport-or-cap-failed"]};
        [_options#0,"only-option"]
    };

    private _ground = "GROUND_ANTI_ARMOR" in _options;
    private _cas = "ANTI_ARMOR_CAS" in _options;
    if (!_cas) exitWith {
        if (_ground) then {["GROUND_ANTI_ARMOR","cas-failed"]} else {["","all-providers-failed"]}
    };

    private _corridor = createHashMap;
    if (!isNil "ITW_CLASH_AirPicture_fnc_ClassifyCorridor") then {
        private _origin = getPosATL leader _hq;
        if (!isNil "ITW_CLASH_Generation_fnc_Resolve") then {
            private _generation = [
                _side,"ANTI_ARMOR_CAS","REAR_AIR",getPosATL _threat
            ] call ITW_CLASH_Generation_fnc_Resolve;
            if ((_generation getOrDefault ["status",""]) isEqualTo "RESOLVED") then {
                _origin = +(_generation getOrDefault ["origin",_origin]);
            };
        };
        _corridor = [_hq,_origin,getPosATL _threat] call
            ITW_CLASH_AirPicture_fnc_ClassifyCorridor;
    };
    private _state = _corridor getOrDefault ["state","CONTESTED"];
    if (_state in ["HOT","AIR_DENIED"]) exitWith {
        if (_ground) then {
            ["GROUND_ANTI_ARMOR","corridor-" + toLowerANSI _state]
        } else {
            ["","corridor-" + toLowerANSI _state]
        }
    };
    if (_state isEqualTo "COLD") exitWith {["ANTI_ARMOR_CAS","corridor-cold"]};
    if (!_ground) exitWith {["ANTI_ARMOR_CAS","corridor-contested"]};
    if (random 1 < 0.5) exitWith {["ANTI_ARMOR_CAS","corridor-contested"]};
    ["GROUND_ANTI_ARMOR","corridor-contested"]
};

// ------------------------------------------------------------------ the buy

/*
    One gate for every purchase, in the order the design fixes:
      an active responder already answers it, or
      an idle earlier purchase is re-offered, or
      the ETB is asked - once per pacing interval.
*/
ITW_CLASH_HALThreatCoverage_fnc_Cover = {
    params ["_hq","_demand","_threats"];
    private _side = side _hq;
    private _need = _demand get "need";
    private _threat = _demand get "threat";
    if (isNull _threat || {!alive _threat}) exitWith {["THREAT_GONE",""]};

    // Survival is rewarded: an asset already bought for this need and left idle
    // is offered again before any new money is spent.
    private _idle = [_hq,_need] call ITW_CLASH_HALThreatCoverage_fnc_IdleAssets;
    if (_idle isNotEqualTo []) exitWith {
        private _nearest = ([_idle,[],{
            (getPosATL (_x get "vehicle")) distance2D (getPosATL _threat)
        },"ASCEND"] call BIS_fnc_sortBy)#0;
        [_hq,_nearest get "group",_threat,_need,"idle-reoffer"] call
            ITW_CLASH_HALThreatCoverage_fnc_Offer;
        ["IDLE_RESPONDER_REOFFERED",_nearest get "capability"]
    };

    if ([_side] call ITW_CLASH_ETB_fnc_Paced) exitWith {["PACING",""]};

    ([_hq,_demand,_threat] call ITW_CLASH_HALThreatCoverage_fnc_ChooseProvider) params [
        "_capability","_choiceReason"
    ];
    if (_capability isEqualTo "") exitWith {["NO_CANDIDATE",_choiceReason]};

    private _threatKey = [_threat] call ITW_CLASH_HALThreatCoverage_fnc_ThreatKey;
    diag_log format [
        "%1 at %2, the ETB is asked for %3 (%4)",
        [_need] call ITW_CLASH_HALThreatCoverage_fnc_DescribeNeed,
        getPosATL _threat,_capability,_choiceReason
    ];

    private _reply = [
        _hq,_capability,_need,_threatKey,_threat,getPosATL _threat
    ] call ITW_CLASH_Generation_fnc_ETBFulfil;
    private _status = _reply get "status";

    ["request-result",[
        _hq getVariable ["RydHQ_CodeSign","?"],_need,_capability,_choiceReason,
        _status,_reply get "reason",_threatKey
    ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;

    if (_status isNotEqualTo "APPROVED") exitWith {[_reply get "reason",_capability]};

    // Queue rotation: this need's age resets after a purchase, so a permanent
    // anti-armor shortfall cannot starve counter-air.
    _demand set ["ageAt",time];
    _demand set ["immediate",false];

    private _asset = _reply get "asset";
    private _group = _reply getOrDefault ["group",grpNull];
    if (isNull _group && {!isNull _asset}) then {_group = group effectiveCommander _asset};

    if (_capability isEqualTo "SPAA") then {
        // The one exception to HAL owning employment: CLASH places SPAA in
        // overwatch behind the front and never sends it forward.
        if (!isNil "ITW_CLASH_SPAAOverwatch_fnc_Adopt") then {
            [_group,_hq,getPosATL _threat] call ITW_CLASH_SPAAOverwatch_fnc_Adopt;
        };
    } else {
        private _tasked = [_hq,_group,_threat,_need,"purchase"] call
            ITW_CLASH_HALThreatCoverage_fnc_Offer;
        if (!_tasked) then {
            // HAL took the asset but tasked nothing capable against the threat.
            // Remember that this provider type did not work for this demand, so
            // the next purchase tries the other one.
            [_hq,_demand,_capability] call ITW_CLASH_HALThreatCoverage_fnc_MarkProviderFailed;
        };
    };

    if (_need isEqualTo "COUNTER_AIR") then {
        [_hq,_asset] call ITW_CLASH_HALThreatCoverage_fnc_WarnOpposingPlayers;
    };
    ["PROVIDED",_capability]
};

/*
    The player cue. When a side buys counter-air and the other side has spotted
    it, that side's players hear a short warning: the air war stays readable, a
    player jet gets roughly the same 1-3 minutes an AI one does, and nobody is
    told about an aircraft they have not seen.
*/
ITW_CLASH_HALThreatCoverage_fnc_WarnOpposingPlayers = {
    params ["_hq","_asset"];
    if (!ITW_CLASH_ThreatCoverageAirWarning || {isNull _asset}) exitWith {false};
    if (!(_asset isKindOf "Air") || {isNil "ITW_CLASH_AirPicture_fnc_Observers"}) exitWith {false};
    private _buyer = side _hq;
    [_buyer,_asset] spawn {
        params ["_buyer","_asset"];
        scriptName "ITW_CLASH_ThreatCoverageAirWarning";
        private _deadline = time + 600;
        private _targets = [];
        {
            if (!isNil _x) then {
                private _side = missionNamespace getVariable [_x,sideUnknown];
                if (_side isNotEqualTo _buyer) then {_targets pushBackUnique _side};
            };
        } forEach ["ITW_PlayerSide","ITW_EnemySide"];
        if (_targets isEqualTo []) exitWith {};

        waitUntil {
            sleep 5;
            isNull _asset || {!alive _asset} || {time >= _deadline} || {
                private _spotted = false;
                {
                    private _hqOther = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
                    if (!isNull _hqOther) then {
                        private _observers = [_hqOther] call ITW_CLASH_AirPicture_fnc_Observers;
                        if ([_asset,_observers] call ITW_CLASH_AirPicture_fnc_IsKnown) then {
                            _spotted = true;
                        };
                    };
                } forEach _targets;
                _spotted
            }
        };
        if (isNull _asset || {!alive _asset} || {time >= _deadline}) exitWith {};

        private _players = allPlayers select {alive _x && {(side (group _x)) in _targets}};
        if (_players isEqualTo []) exitWith {};
        {
            ["enemy fighters inbound"] remoteExec ["hint",_x];
        } forEach _players;
        ["air-warning",[
            toUpperANSI str _buyer,typeOf _asset,count _players
        ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
    };
    true
};

/*
    The instant reactions to an air signal, before anything is bought. Deciding
    takes 5-20 seconds but a bought counter still has to travel, so what is
    already on the map is what hurts the jet in its first minute:
      - re-offer any idle fighter or air defence against the aircraft;
      - publish the sector so new helicopter lift stays out of it.

    Flights already under way continue and nothing is recalled: that is the
    decided direction. Which thresholds close a corridor is Hark's call, so this
    only publishes what the air picture already classifies as hard-kill and
    leaves the lift rules to the helicopter tiers.
*/
ITW_CLASH_HALThreatCoverage_fnc_AirReaction = {
    params ["_hq","_threats"];
    if (_threats isEqualTo []) exitWith {false};
    private _threat = (_threats#0)#0;
    if (isNull _threat) exitWith {false};

    private _idle = [_hq,"COUNTER_AIR"] call ITW_CLASH_HALThreatCoverage_fnc_IdleAssets;
    {
        [_hq,_x get "group",_threat,"COUNTER_AIR","air-signal-reoffer"] call
            ITW_CLASH_HALThreatCoverage_fnc_Offer;
    } forEach _idle;

    // The sector where enemy air is operating, for the lift rules and for
    // SPAA placement. Nothing is recalled.
    _hq setVariable ["ITW_CLASH_AirAlarmPosition",getPosATL _threat];
    _hq setVariable ["ITW_CLASH_AirAlarmAt",time];
    ["air-reaction",[
        _hq getVariable ["RydHQ_CodeSign","?"],typeOf _threat,
        (getPosATL _threat) apply {round _x},count _idle,count _threats
    ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
    true
};

// ---------------------------------------------------------------- evaluation

ITW_CLASH_HALThreatCoverage_fnc_Evaluate = {
    params ["_hq"];
    if (isNull _hq || {
        !(missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false])
    } || {
        !(missionNamespace getVariable ["ITW_CLASH_ETBReady",false])
    }) exitWith {false};
    private _side = side _hq;

    private _armorThreats = [_hq] call ITW_CLASH_HALThreatCoverage_fnc_ArmorThreats;
    private _airThreats = [_hq] call ITW_CLASH_HALThreatCoverage_fnc_AirThreats;

    private _armorCoverage = [_hq,_armorThreats] call ITW_CLASH_HALThreatCoverage_fnc_ArmorCoverage;
    private _airCoverage = [_hq,_airThreats] call ITW_CLASH_HALThreatCoverage_fnc_AirCoverage;

    if (_airThreats isNotEqualTo []) then {
        [_hq,_airThreats] call ITW_CLASH_HALThreatCoverage_fnc_AirReaction;
    };

    private _armorDemand = [
        _hq,"ANTI_ARMOR",_armorThreats,(count _armorThreats) - _armorCoverage
    ] call ITW_CLASH_HALThreatCoverage_fnc_Refresh;
    private _airImmediate = (_airThreats findIf {_x#5}) >= 0;
    private _airDemand = [
        _hq,"COUNTER_AIR",_airThreats,(count _airThreats) - _airCoverage,_airImmediate
    ] call ITW_CLASH_HALThreatCoverage_fnc_Refresh;

    // Who gets the money: the oldest persistent demand the ETB can afford,
    // never the order of the code. The first counter-air response jumps the
    // queue, because queue order would otherwise defeat the fast air lane.
    private _queue = [];
    {
        if (count _x > 0 && {[_x] call ITW_CLASH_HALThreatCoverage_fnc_Funded}) then {
            _queue pushBack _x;
        };
    } forEach [_armorDemand,_airDemand];
    if (_queue isEqualTo []) exitWith {true};

    private _jumper = _queue findIf {
        (_x get "need") isEqualTo "COUNTER_AIR" && {_x get "immediate"}
    };
    if (_jumper > 0) then {
        private _first = _queue#_jumper;
        _queue deleteAt _jumper;
        _queue insert [0,[_first]];
    };
    if (_jumper < 0) then {
        _queue = [_queue,[],{_x get "ageAt"},"ASCEND"] call BIS_fnc_sortBy;
    };

    private _spent = false;
    {
        private _demand = _x;
        if (_spent) exitWith {};
        private _threats = if ((_demand get "need") isEqualTo "COUNTER_AIR") then {
            _airThreats
        } else {
            _armorThreats
        };
        ([_hq,_demand,_threats] call ITW_CLASH_HALThreatCoverage_fnc_Cover) params [
            "_result","_detail"
        ];
        if (_result isEqualTo "PROVIDED") then {
            _spent = true;
            // Anything older that could not afford its counter has now been
            // spent past: after one bypass the money is held for it.
            {
                if ((_x get "ageAt") < (_demand get "ageAt")) then {
                    [_side,_x get "need",[_side,_x get "need"] call
                        ITW_CLASH_Generation_fnc_ETBCheapestPrice] call
                        ITW_CLASH_ETB_fnc_MarkBypassed;
                };
            } forEach _queue;
        };
        if (_result isEqualTo "INSUFFICIENT_ETB") then {
            {
                if ((_x get "ageAt") > (_demand get "ageAt")) exitWith {
                    // A younger demand exists that may spend instead: mark this
                    // one bypassed so escrow starts if it happens again.
                    [_side,_demand get "need",[_side,_demand get "need"] call
                        ITW_CLASH_Generation_fnc_ETBCheapestPrice] call
                        ITW_CLASH_ETB_fnc_MarkBypassed;
                };
            } forEach _queue;
        };
    } forEach _queue;

    ["evaluated",[
        _hq getVariable ["RydHQ_CodeSign","?"],
        count _armorThreats,(round (_armorCoverage * 100)) / 100,
        count _airThreats,(round (_airCoverage * 100)) / 100,
        count _queue,_spent
    ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
    true
};

[] spawn {
    scriptName "ITW_CLASH_HALThreatCoverageBootstrap";
    waitUntil {
        sleep 1;
        !isNil "ITW_CLASH_fnc_GetCommanderForSide" || {
            missionNamespace getVariable ["ITW_GameOver",false]
        }
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        call ITW_CLASH_HALThreatCoverage_fnc_ZoneGuard;
        private _sides = [];
        if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
        if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};

        {
            private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
            if (!isNull _hq) then {
                [_hq] call ITW_CLASH_HALThreatCoverage_fnc_Evaluate;
            };
        } forEach _sides;

        sleep ITW_CLASH_ThreatCoveragePoll;
    };
};

ITW_CLASH_HALThreatCoverageReady = true;
diag_log format [
    "CLASH BOOT | hal-threat-coverage-ready | version=%1 needs=ANTI_ARMOR,COUNTER_AIR providers=GROUND_ANTI_ARMOR,ANTI_ARMOR_CAS,CAP_AIRCRAFT,SPAA funding=etb impasseRowsBilled=false threatClassification=vehicle observedCoverage=true failureMemory=%2 groundPersistence=%3 airLane=immediate",
    ITW_CLASH_HALThreatCoverageVersion,
    ITW_CLASH_ThreatCoverageFailureMemory,
    ITW_CLASH_ThreatCoverageGroundPersistence
];

true
