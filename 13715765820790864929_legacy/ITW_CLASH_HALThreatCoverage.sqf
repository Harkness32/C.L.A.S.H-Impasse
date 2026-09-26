#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALThreatCoverageStarted",false]) exitWith {true};
ITW_CLASH_HALThreatCoverageStarted = true;
ITW_CLASH_HALThreatCoverageVersion = 5;
ITW_CLASH_HALThreatCoverageReady = false;

// Same role as ITW_CLASH_HALLogistics.sqf, for a different gap: HQOrders.sqf
// tallies AAInf/StaticAA/StaticAT/Support/Cargo threat but (unlike Recon/Inf/
// Armor/etc.) never calls RYD_Dispatcher for them, so HAL never decides it
// needs anything for these - there is no native HAL_Supp*-style call to wrap.
// This evaluates HAL's own public demand (RydHQ_En*) against HAL's own public
// supply pools directly, on its own interval, and requests replenishment
// through the same Checkbook seam HALLogistics already uses. It does not read
// or depend on the separate CLASH_HAL_Additions addon that answers these
// threats tactically - both read the same public RydHQ_* state independently.
//
// GENERALIZED beyond the original 5: HAL's original 9 dispatch categories
// (Recon/ATInf/Inf/Armor/Cars/Art/Air/Static/Naval) can run their own
// response pools just as dry - RydHQ_ATInfG empty against a real armor push
// isn't unique to StaticAT, it happens on the plain Armor threat path too.
// This file now covers 12 of those ~14 total categories:
//   - the original 5 (AAInf/StaticAA/StaticAT/Support/Cargo)
//   - ATInf/Inf/Armor/Cars/Art/Static, added here, each checked against
//     ground and/or air depending on what RYD_Dispatcher's own response pool
//     for that kind actually contains (HAC_fnc.sqf's switch - not guessed)
//   - Air, handled as its own case just below the loop because its real
//     pool wants RydHQ_RCAP specifically, not RydHQ_RCAS/BAirG like every
//     other "air" case here
// Deliberately NOT covered:
//   - Recon (SNP+INF pool only - no vehicle capability applies; a sniper/
//     infantry gap isn't something to buy through this seam)
//   - Naval (RydHQ_allNaval only - no NAVAL capability/provider exists;
//     would need a third vehicle capability, new classlists, new
//     RegisterAsset routing - real scope, deliberately deferred, not an
//     oversight)
//
// ATInfG/AAInfG deficits (Armor/Air threat + empty specialist infantry pool)
// need no separate handling here - ITW_CLASH_InfantryDemand.sqf's watcher
// already reads RydHQ_EnHArmor/EnLArmorAT/EnAir + RydHQ_ATInfG/AAInfG
// directly, independent of which dispatch category the armor/air belongs
// to, so it was already covering both the old and new categories without
// any change.
//
// Two vehicle capabilities cover all of it, matching the doctrine already
// chosen for the tactical side (see docs/CLASH_HAL_DISPATCH_PATCH.md):
// GROUND_ATTACK_LIGHT for ground-pool gaps, CAS_AIRCRAFT for air-pool gaps
// (RCAS and, since this revision, RCAP - see ForceGeneration.sqf).
ITW_CLASH_ThreatCoverageBootstrapInterval = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageBootstrapInterval",20
];
ITW_CLASH_ThreatCoverageCommitmentTimeout = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageCommitmentTimeout",900
];
ITW_CLASH_ThreatCoverageCommitments = createHashMap;
// Usable coverage is sampled once per pass, so without a per-capability
// interval every kind that falls back to CAS could each buy in one pass. How
// many may exist is ITW's call: its per-row caps and spawn-adjustment params
// are enforced at billing (ForceGeneration's SelectBillingDefs).
ITW_CLASH_ThreatCoverageBuyInterval = missionNamespace getVariable [
    "ITW_CLASH_ThreatCoverageBuyInterval",90
];

ITW_CLASH_HALThreatCoverage_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-threat-coverage-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL THREAT COVERAGE | %1 | %2",_event,_payload];
    };
};


ITW_CLASH_HALThreatCoverage_fnc_CommitmentKey = {
    params ["_hq","_targetGroup","_kind"];
    format ["%1|%2|%3",str _hq,str _targetGroup,toUpperANSI _kind]
};

// A purchased unit that HAL is already employing against the exact threat that
// caused the purchase counts as coverage even though native HAL correctly
// removes it from AttackAv and marks it Busy for the duration of that task.
// Without this second notion of coverage, immediate tasking turns the next
// 20-second coverage poll into another purchase request.
ITW_CLASH_HALThreatCoverage_fnc_CommitmentActive = {
    params ["_hq","_targetGroup","_kind"];
    if (isNull _hq || {isNull _targetGroup}) exitWith {false};

    private _key = [_hq,_targetGroup,_kind] call
        ITW_CLASH_HALThreatCoverage_fnc_CommitmentKey;
    private _entry = ITW_CLASH_ThreatCoverageCommitments getOrDefault [_key,[]];
    if (_entry isEqualTo [] || {count _entry < 4}) exitWith {false};

    _entry params ["_responder","_target","_committedKind","_committedAt"];

    private _targetAlive = !isNull _target && {
        ({alive _x} count units _target) > 0
    };
    private _responderAlive = !isNull _responder && {
        ({alive _x} count units _responder) > 0
    };
    private _busy = _responderAlive && {
        _responder getVariable ["Busy" + str _responder,false]
    };
    private _physical = false;
    if (_responderAlive) then {
        private _veh = vehicle leader _responder;
        _physical = !isNull _veh && {
            alive _veh && {
                _veh isEqualTo leader _responder || {canMove _veh}
            }
        };
    };
    private _fresh = (time - _committedAt) <=
        ITW_CLASH_ThreatCoverageCommitmentTimeout;
    private _sameTarget = _target isEqualTo _targetGroup;
    private _sameKind = toUpperANSI _committedKind == toUpperANSI _kind;

    private _active = _targetAlive && {_responderAlive} && {_busy} &&
        {_physical} && {_fresh} && {_sameTarget} && {_sameKind};

    if (!_active) then {
        ITW_CLASH_ThreatCoverageCommitments deleteAt _key;
        if (!isNull _responder) then {
            _responder setVariable ["ITW_CLASH_ThreatCoverageTarget",nil];
            _responder setVariable ["ITW_CLASH_ThreatCoverageKind",nil];
            _responder setVariable ["ITW_CLASH_ThreatCoverageCommittedAt",nil];
        };
    };
    _active
};

ITW_CLASH_HALThreatCoverage_fnc_Commit = {
    params ["_hq","_responder","_targetGroup","_kind"];
    private _key = [_hq,_targetGroup,_kind] call
        ITW_CLASH_HALThreatCoverage_fnc_CommitmentKey;
    ITW_CLASH_ThreatCoverageCommitments set [
        _key,[_responder,_targetGroup,_kind,time]
    ];
    _responder setVariable ["ITW_CLASH_ThreatCoverageTarget",_targetGroup];
    _responder setVariable ["ITW_CLASH_ThreatCoverageKind",_kind];
    _responder setVariable ["ITW_CLASH_ThreatCoverageCommittedAt",time];
};

// Preserve HAL ownership of the mission itself. C.L.A.S.H. only carries the
// causal target through the procurement transaction and makes the new group
// immediately available. Native categories are re-offered to RYD_Dispatcher;
// the five HAL gaps are re-offered to CLASH HAL Additions' responder. Those
// selectors retain HAL's terrain/weather/AT/AA resignation before GoAtt* owns
// geometry, chatter, engagement and RTB.
ITW_CLASH_HALThreatCoverage_fnc_DispatchPurchased = {
    params ["_hq","_reply","_targetGroup","_kind","_capability"];
    if (
        isNull _hq || {isNull _targetGroup} || {
            (_reply getOrDefault ["status",""]) != "APPROVED"
        }
    ) exitWith {false};

    private _asset = _reply getOrDefault ["asset",objNull];
    if (isNull _asset || {!alive _asset}) exitWith {false};

    private _crew = crew _asset;
    if (_crew isEqualTo []) exitWith {false};
    [
        _hq,group (_crew#0),_targetGroup,_kind,_capability,
        _reply getOrDefault ["requestId",""]
    ] call ITW_CLASH_HALThreatCoverage_fnc_Offer
};

// Shared by fresh purchases and idle earlier ones: HAL decides, CLASH only
// makes the group available against the causal threat.
ITW_CLASH_HALThreatCoverage_fnc_Offer = {
    params ["_hq","_group","_targetGroup","_kind","_capability","_ref"];
    if (isNull _group || {({alive _x} count units _group) <= 0}) exitWith {false};
    private _asset = vehicle leader _group;

    private _targetLeader = leader _targetGroup;
    if (isNull _targetLeader || {!alive _targetLeader}) exitWith {false};

    // Newly registered groups do not necessarily enter AttackAv until HAL's
    // next HQOrders pass. Make this one immediately available, then let HAL's
    // own dispatcher/responder decide whether it is tactically acceptable.
    // If HAL declines because of terrain/weather/AT/AA risk, the group simply
    // remains in AttackAv and therefore counts as available coverage next poll.
    private _attackAv = +(_hq getVariable ["RydHQ_AttackAv",[]]);
    _attackAv pushBackUnique _group;
    _hq setVariable ["RydHQ_AttackAv",_attackAv];
    _group setVariable ["Busy" + str _group,false];

    private _nativeKinds = ["ATInf","Inf","Armor","Cars","Art","Static","Air"];
    private _gapKinds = ["AAInf","StaticAA","StaticAT","Support","Cargo"];
    private _attempted = false;

    if (_kind in _nativeKinds && {!isNil "RYD_Dispatcher"}) then {
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
        private _risk = switch (_kind) do {
            case "ATInf": {[0,0,85]};
            case "Inf": {[75,80,85]};
            case "Armor": {[50,0,85]};
            case "Cars": {[75,80,85]};
            case "Art": {[70,75,75]};
            case "Air": {[0,0,75]};
            default {[75,80,85]}; // Static
        };
        private _constant = [
            _hq getVariable ["RydHQ_AAthreat",[]],
            _hq getVariable ["RydHQ_ATthreat",[]],
            (_hq getVariable ["RydHQ_EnHArmor",[]]) +
                (_hq getVariable ["RydHQ_EnLArmorAT",[]]),
            _fPool
        ];
        ([
            [_targetGroup],_kind,_hq,_risk#0,_risk#1,_risk#2
        ] + _constant) call RYD_Dispatcher;
        _attempted = true;
    };

    if (_kind in _gapKinds) then {
        if (!isNil "CLASH_fnc_HALAdd_Respond") then {
            private _snipersG  = _hq getVariable ["RydHQ_snipersG",[]];
            private _NCrewInfG = (_hq getVariable ["RydHQ_NCrewInfG",[]]) -
                (_hq getVariable ["RydHQ_SpecForG",[]]);
            private _LArmorG = _hq getVariable ["RydHQ_LArmorG",[]];
            private _HArmorG = _hq getVariable ["RydHQ_HArmorG",[]];
            private _cars = (_hq getVariable ["RydHQ_CarsG",[]]) - (
                (_hq getVariable ["RydHQ_ATInfG",[]])
                + (_hq getVariable ["RydHQ_AAInfG",[]])
                + (_hq getVariable ["RydHQ_SupportG",[]])
            );
            private _airPools = [_hq] call
                ITW_CLASH_HALThreatCoverage_fnc_EffectiveAirPools;
            private _airCAS = _airPools#0;

            private _policy = switch (_kind) do {
                case "AAInf": {
                    [[
                        [_snipersG,0.5,"SNP"],[_LArmorG,1,"ARM"],
                        [_cars,1,"INF"],[_NCrewInfG,0.5,"INF"]
                    ],0,0,85]
                };
                case "StaticAA": {
                    [[
                        [_LArmorG,1,"ARM"],[_HArmorG,1,"ARM"],
                        [_cars,1,"INF"],[_NCrewInfG,0.5,"INF"],
                        [_snipersG,0.5,"SNP"]
                    ],0,0,85]
                };
                case "StaticAT": {
                    [[
                        [_airCAS,2,"AIR"],[_NCrewInfG,0.5,"INF"],
                        [_snipersG,0.5,"SNP"]
                    ],75,80,0]
                };
                case "Support": {
                    [[
                        [_cars,1,"INF"],[_airCAS,1,"AIR"],
                        [_LArmorG,0.5,"ARM"]
                    ],75,80,85]
                };
                default {
                    [[
                        [_cars,1,"INF"],[_airCAS,1,"AIR"],
                        [_NCrewInfG,0.5,"INF"]
                    ],75,80,85]
                };
            };
            [
                [_targetGroup],_kind,_hq,_policy#0,
                _policy#1,_policy#2,_policy#3
            ] call CLASH_fnc_HALAdd_Respond;
            _attempted = true;
        } else {
            ["immediate-dispatch-addon-missing",[
                _ref,_kind,typeOf _asset
            ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
        };
    };

    private _busy = _group getVariable ["Busy" + str _group,false];
    if (_busy) then {
        [_hq,_group,_targetGroup,_kind] call
            ITW_CLASH_HALThreatCoverage_fnc_Commit;
        ["immediate-dispatch",[
            _ref,
            _kind,toUpperANSI _capability,typeOf _asset,
            groupId _group,groupId _targetGroup,
            "hal-selected"
        ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
        diag_log format [
            "CLASH THREAT COVERAGE | HAL immediately committed %1 to %2 | target=%3",
            typeOf _asset,
            [_kind] call ITW_CLASH_HALThreatCoverage_fnc_DescribeKind,
            groupId _targetGroup
        ];
    } else {
        ["immediate-ready",[
            _ref,
            _kind,toUpperANSI _capability,typeOf _asset,
            groupId _group,groupId _targetGroup,_attempted
        ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
        diag_log format [
            "CLASH THREAT COVERAGE | %1 available to HAL immediately; no forced task | kind=%2 target=%3",
            typeOf _asset,_kind,groupId _targetGroup
        ];
    };
    _attempted
};

// Revised: alive/Busy/Unable alone was looser than HAL's actual notion of
// "usable" - a dry or non-AttackAv group would have counted as coverage,
// causing under-provisioning (HAL can't actually use it, but this file
// thought the threat was already answered). Now also requires RydHQ_AttackAv
// membership, real ammo (RYD_AmmoCount, the same check RYD_Dispatcher itself
// uses), and that a mounted group's vehicle can actually move. Not
// attempting to reproduce RYD_Dispatcher's full stochastic terrain/
// resignation scoring - that's a deliberate simplification, not an oversight.
ITW_CLASH_HALThreatCoverage_fnc_UsableGroups = {
    params ["_groups","_hq"];
    private _attackAv = _hq getVariable ["RydHQ_AttackAv", []];
    private _NCVeh = _hq getVariable ["RydHQ_NCVeh", []];
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

// HAL's own RYD_Dispatcher merges eligible general-purpose air (RydHQ_AirG,
// minus non-combat/crew/ammo-drop exclusions) into BOTH airCAS and airCAP on
// top of the dedicated RydHQ_RCAS/RydHQ_RCAP/RydHQ_BAirG pools
// (HAC_fnc.sqf's RYD_Dispatcher, ~line 1354-1362). A naive RCAS+BAirG-only
// read undercounts what HAL can actually field, which was causing this file
// to buy aircraft HAL didn't actually need. One shared helper instead of
// duplicating the merge per call site.
ITW_CLASH_HALThreatCoverage_fnc_EffectiveAirPools = {
    params ["_hq"];
    private _airCAS = +(_hq getVariable ["RydHQ_RCAS", []]);
    private _airCAP = +(_hq getVariable ["RydHQ_RCAP", []]);
    private _BAir   = _hq getVariable ["RydHQ_BAirG", []];
    private _air    = (_hq getVariable ["RydHQ_AirG", []]) - (
        (_hq getVariable ["RydHQ_NCAirG", []])
        + (_hq getVariable ["RydHQ_NCrewInfG", []])
        + (_hq getVariable ["RydHQ_AmmoDrop", []])
    );
    { if !(_x in _airCAS) then { _airCAS pushBack _x; }; } forEach _BAir;
    { if !(_x in (_airCAP + _airCAS)) then { _airCAS pushBack _x; _airCAP pushBack _x; }; } forEach _air;
    [_airCAS,_airCAP]
};

// Plain-language kind -> phrase, for the human-readable RPT lines below.
// Purely cosmetic - every structured diag_log elsewhere in this file is
// unaffected and remains the thing anything automated should parse.
ITW_CLASH_HALThreatCoverage_fnc_DescribeKind = {
    params ["_kind"];
    switch (_kind) do {
        case "AAInf":    {"AA infantry"};
        case "StaticAA": {"a static AA position"};
        case "StaticAT": {"a static AT position"};
        case "Support":  {"an enemy support column"};
        case "Cargo":    {"enemy cargo/logistics"};
        case "ATInf":    {"AT infantry"};
        case "Inf":      {"enemy infantry"};
        case "Armor":    {"heavy armor"};
        case "Cars":     {"technicals"};
        case "Art":      {"enemy artillery"};
        case "Static":   {"fortified positions"};
        case "Air":      {"enemy aircraft"};
        default {_kind};
    }
};

ITW_CLASH_HALThreatCoverage_fnc_Request = {
    params ["_hq","_capability","_mode",["_kind",""],["_targetGroup",grpNull]];
    if (isNull _hq || {isNil "ITW_CLASH_fnc_RequestCapability"}) exitWith {createHashMap};
    private _side = side _hq;
    private _reference = if (!isNull _targetGroup && {!isNull (leader _targetGroup)}) then {
        getPosATL (vehicle (leader _targetGroup))
    } else {
        getPosATL leader _hq
    };
    private _requirements = createHashMapFromArray [
        ["hq",_hq],
        ["side",_side],
        ["mode",_mode],
        ["profile",if (_mode == "AIR") then {"REAR_AIR"} else {"REAR"}],
        ["reference",_reference],
        ["threatGroup",_targetGroup],
        ["threatKind",_kind]
    ];
    private _reply = [
        _capability,_hq,_requirements,"HIGH"
    ] call ITW_CLASH_fnc_RequestCapability;
    if ((_reply getOrDefault ["status",""]) == "APPROVED") then {
        diag_log format [
            "Request approved for %1 for %2",
            _capability,
            [_kind] call ITW_CLASH_HALThreatCoverage_fnc_DescribeKind
        ];
        if (!isNull _targetGroup) then {
            [_hq,_reply,_targetGroup,_kind,_capability] call
                ITW_CLASH_HALThreatCoverage_fnc_DispatchPurchased;
        };
    };
    ["request-result",[
        _hq getVariable ["RydHQ_CodeSign","?"],
        _capability,
        _mode,
        _reply getOrDefault ["status","INVALID"],
        _reply getOrDefault ["reason","invalid-result"],
        _reply getOrDefault ["requestId",""],
        if (isNull _targetGroup) then {""} else {groupId _targetGroup}
    ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
    _reply
};

// Checkbook purchases of this capability for this HQ that can still fight.
ITW_CLASH_HALThreatCoverage_fnc_Bought = {
    params ["_hq","_capability"];
    private _side = side _hq;
    allGroups select {
        side _x == _side
        && {_x getVariable ["ITW_CLASH_CheckbookAsset",false]}
        && {(_x getVariable ["ITW_CLASH_GenerationCapability",""]) == _capability}
        && {alive leader _x}
        && {
            private _veh = vehicle leader _x;
            _veh != leader _x && {alive _veh} && {canMove _veh}
        }
    }
};

// Bought earlier and left without a task (live run: helicopters hovering at
// their spawn), as opposed to on a HAL mission, resting or being resupplied.
ITW_CLASH_HALThreatCoverage_fnc_Idle = {
    params ["_groups","_hq"];
    private _NCVeh = _hq getVariable ["RydHQ_NCVeh",[]];
    _groups select {
        !(_x getVariable ["Busy" + str _x,false])
        && {!(_x getVariable ["Resting" + str _x,false])}
        && {!(_x getVariable ["Unable",false])}
        && {!(_x getVariable ["ITW_CLASH_ResupplyClaimed",false])}
        && {([_x,_NCVeh] call RYD_AmmoCount) > 0}
    }
};

// One gate for every purchase: re-offer an idle earlier purchase to HAL
// first, then buy at most once per capability per interval.
ITW_CLASH_HALThreatCoverage_fnc_Cover = {
    params ["_hq","_capability","_kind","_targetGroup"];
    private _idle = [
        [_hq,_capability] call ITW_CLASH_HALThreatCoverage_fnc_Bought,_hq
    ] call ITW_CLASH_HALThreatCoverage_fnc_Idle;
    if (_idle isNotEqualTo []) exitWith {
        private _nearest = ([
            _idle,[vehicle leader _targetGroup],
            {(vehicle leader _x) distance2D _input0},"ASCEND"
        ] call BIS_fnc_sortBy)#0;
        [_hq,_nearest,_targetGroup,_kind,_capability,"idle-reoffer"] call
            ITW_CLASH_HALThreatCoverage_fnc_Offer
    };

    private _buyKey = "ITW_CLASH_ThreatCoverageBuyAt_" + _capability;
    if (time < (_hq getVariable [_buyKey,0])) exitWith {false};
    _hq setVariable [_buyKey,time + ITW_CLASH_ThreatCoverageBuyInterval];

    private _mode = if (_capability == "CAS_AIRCRAFT") then {"AIR"} else {"GROUND"};
    diag_log format [
        "%1 at %2, requesting %3",
        [_kind] call ITW_CLASH_HALThreatCoverage_fnc_DescribeKind,
        getPosATL (vehicle (leader _targetGroup)),
        _capability
    ];
    [_hq,_capability,_mode,_kind,_targetGroup] call
        ITW_CLASH_HALThreatCoverage_fnc_Request;
    true
};

ITW_CLASH_HALThreatCoverage_fnc_Evaluate = {
    params ["_hq"];
    if (isNull _hq || {
        !(missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false])
    }) exitWith {false};

    private _snipersG  = _hq getVariable ["RydHQ_snipersG", []];
    private _NCrewInfG = (_hq getVariable ["RydHQ_NCrewInfG", []]) - (_hq getVariable ["RydHQ_SpecForG", []]);
    private _LArmorG   = _hq getVariable ["RydHQ_LArmorG", []];
    private _HArmorG   = _hq getVariable ["RydHQ_HArmorG", []];
    private _cars      = (_hq getVariable ["RydHQ_CarsG", []]) - ((_hq getVariable ["RydHQ_ATInfG", []]) + (_hq getVariable ["RydHQ_AAInfG", []]) + (_hq getVariable ["RydHQ_SupportG", []]));

    private _airPools = [_hq] call ITW_CLASH_HALThreatCoverage_fnc_EffectiveAirPools;
    private _airCAS = _airPools#0;
    private _airCAP = _airPools#1;

    private _groundPool = (_LArmorG + _HArmorG + _NCrewInfG + _snipersG + _cars);
    private _groundUsable = [_groundPool,_hq] call ITW_CLASH_HALThreatCoverage_fnc_UsableGroups;
    private _airUsable    = [_airCAS,_hq] call ITW_CLASH_HALThreatCoverage_fnc_UsableGroups;
    private _airCapUsable = [_airCAP,_hq] call ITW_CLASH_HALThreatCoverage_fnc_UsableGroups;

    // Revised from "check ground and air independently, buy either that's
    // missing" to "does HAL have ANY usable responder among the buckets this
    // category's real RYD_Dispatcher pool actually contains - if so, don't
    // spend at all." A single rifle squad shouldn't be able to justify
    // buying both an IFV and a CAS aircraft just because neither modality
    // happens to be sitting fully idle. Only when every relevant bucket is
    // genuinely empty does this request ONE capability - the doctrinally
    // preferred one, not both. For every dual-bucket category below that's
    // CAS_AIRCRAFT: RYD_Dispatcher weights the AIR entry highest (2) in
    // every one of Inf/Armor/Cars/Art/Static's real pools, so it's not an
    // arbitrary pick.
    private _demandCategories =
    [
        // [ "RydHQ_En<x> variable", cooldown-key label, check ground?, check air?, capability if neither covered ]
        // -- original 5, single-bucket by doctrine (see docs) --
        ["RydHQ_EnAAinf",    "AAInf",    true,  false, "GROUND_ATTACK_LIGHT"],
        ["RydHQ_EnStaticAA", "StaticAA", true,  false, "GROUND_ATTACK_LIGHT"],
        ["RydHQ_EnStaticAT", "StaticAT", false, true,  "CAS_AIRCRAFT"],
        ["RydHQ_EnSupport",  "Support",  true,  false, "GROUND_ATTACK_LIGHT"],
        ["RydHQ_EnCargo",    "Cargo",    true,  false, "GROUND_ATTACK_LIGHT"],
        // -- generalized to HAL's original dispatch categories --
        ["RydHQ_EnATinf",    "ATInf",    true,  true,  "CAS_AIRCRAFT"],  // pool: SNP+AIR+INF (ground bucket approximates SNP+INF; no ARM in the real pool, so air is the only vehicle-capability fit)
        ["RydHQ_EnInf",      "Inf",      true,  true,  "CAS_AIRCRAFT"],  // pool: ARM+ARM+SNP+INF+AIR+INF
        ["RydHQ_EnHArmor",   "Armor",    true,  true,  "CAS_AIRCRAFT"],  // pool: AIR+ARM+ARM+INF(ATInfG, handled separately by InfantryDemand)
        ["RydHQ_EnCars",     "Cars",     true,  true,  "CAS_AIRCRAFT"],  // pool: ARM+INF+ARM+AIR+INF
        ["RydHQ_EnArt",      "Art",      true,  true,  "CAS_AIRCRAFT"],  // pool: AIR+ARM+INF+ARM+INF
        ["RydHQ_EnStatic",   "Static",   true,  true,  "CAS_AIRCRAFT"]   // pool: AIR+ARM+SNP+INF+ARM+INF
    ];

    {
        _x params ["_demandVar","_kind","_checkGround","_checkAir","_capability"];
        private _demand = (_hq getVariable [_demandVar, []]) select {
            !isNull _x && {!isNull (leader _x)} && {alive (leader _x)}
        };
        if (count _demand > 0) then {
            private _anyUsable = false;
            if (_checkGround && {count _groundUsable > 0}) then {_anyUsable = true};
            if (_checkAir && {count _airUsable > 0}) then {_anyUsable = true};
            if (!_anyUsable) then {
                // Find the first threat in this HAL category that is not
                // already being answered by a purchased responder. Busy
                // responders deliberately count here even though they are
                // absent from AttackAv - that is exactly what "on mission"
                // means in native HAL.
                private _targetIndex = _demand findIf {
                    !([_hq,_x,_kind] call
                        ITW_CLASH_HALThreatCoverage_fnc_CommitmentActive)
                };
                if (_targetIndex >= 0) then {
                    private _targetGroup = _demand#_targetIndex;
                    private _cooldownKey = "ITW_CLASH_ThreatCoverageRetryAt_" + _kind;
                    if (time >= (_hq getVariable [_cooldownKey,0])) then {
                        _hq setVariable [_cooldownKey,time + 45];
                        [_hq,_capability,_kind,_targetGroup] call
                            ITW_CLASH_HALThreatCoverage_fnc_Cover;
                    };
                };
            };
        };
    } forEach _demandCategories;

    // Air/AIRCAP - its own case, not part of the generic table above: HAL's
    // "Air" dispatch pool is airCAP+AAInfG (HAC_fnc.sqf's "Air" case), not
    // airCAS. Only usable airCAP counts as coverage: AA infantry does not
    // hold air parity (live peer run: an enemy Black Wasp killed BLUFOR's
    // helicopters and no air request was ever raised). A Checkbook-bought
    // CAS_AIRCRAFT asset registers into both RCAS and RCAP (see
    // ForceGeneration.sqf), so requesting it here is still the right ask.
    private _airDemand = (_hq getVariable ["RydHQ_EnAir", []]) select {
        !isNull _x && {!isNull (leader _x)} && {alive (leader _x)}
    };
    if (count _airDemand > 0 && {count _airCapUsable <= 0}) then {
        private _targetIndex = _airDemand findIf {
            !([_hq,_x,"Air"] call
                ITW_CLASH_HALThreatCoverage_fnc_CommitmentActive)
        };
        if (_targetIndex >= 0) then {
            private _targetGroup = _airDemand#_targetIndex;
            private _cooldownKey = "ITW_CLASH_ThreatCoverageRetryAt_Air_Cap";
            if (time >= (_hq getVariable [_cooldownKey,0])) then {
                _hq setVariable [_cooldownKey,time + 45];
                [_hq,"CAS_AIRCRAFT","Air",_targetGroup] call
                    ITW_CLASH_HALThreatCoverage_fnc_Cover;
            };
        };
    };

    true
};

[] spawn {
    scriptName "ITW_CLASH_HALThreatCoverageBootstrap";
    waitUntil {
        sleep 1;
        !isNil "ITW_CLASH_fnc_GetCommanderForSide"
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        private _sides = [];
        if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
        if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};

        {
            private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
            if (!isNull _hq) then {
                [_hq] call ITW_CLASH_HALThreatCoverage_fnc_Evaluate;
            };
        } forEach _sides;

        sleep ITW_CLASH_ThreatCoverageBootstrapInterval;
    };
};

ITW_CLASH_HALThreatCoverageReady = true;
diag_log format [
    "CLASH BOOT | hal-threat-coverage-ready | version=%1 categories=AAInf,StaticAA,StaticAT,Support,Cargo,ATInf,Inf,Armor,Cars,Art,Static,Air capabilities=GROUND_ATTACK_LIGHT,CAS_AIRCRAFT providersRegistered=true immediateHALHandoff=true activeCommitmentCoverage=true notCovered=Recon,Naval",
    ITW_CLASH_HALThreatCoverageVersion
];

true
