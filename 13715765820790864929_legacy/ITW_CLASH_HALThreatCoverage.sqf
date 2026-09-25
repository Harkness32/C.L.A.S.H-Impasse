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
// causal target through the procurement transaction, then performs the exact
// native dispatcher handoff: Busy=true, remove from AttackAv, RYD_GoLaunch.
// From that point GoAtt* owns geometry, chatter, engagement and RTB.
ITW_CLASH_HALThreatCoverage_fnc_DispatchPurchased = {
    params ["_hq","_reply","_targetGroup","_kind","_capability"];
    if (
        isNull _hq || {isNull _targetGroup} || {
            (_reply getOrDefault ["status",""]) != "APPROVED"
        }
    ) exitWith {false};
    if (isNil "RYD_GoLaunch" || {isNil "RYD_Spawn"}) exitWith {false};

    private _asset = _reply getOrDefault ["asset",objNull];
    if (isNull _asset || {!alive _asset}) exitWith {false};

    private _crew = crew _asset;
    if (_crew isEqualTo []) exitWith {false};
    private _group = group (_crew#0);
    if (isNull _group || {({alive _x} count units _group) <= 0}) exitWith {false};

    private _targetLeader = leader _targetGroup;
    if (isNull _targetLeader || {!alive _targetLeader}) exitWith {false};
    private _target = vehicle _targetLeader;
    if (isNull _target || {!alive _target}) exitWith {false};

    private _capabilityKey = toUpperANSI _capability;
    private _pattern = switch (_capabilityKey) do {
        case "GROUND_ATTACK_LIGHT": {
            private _vehicleKind = if (!isNil "ITW_CLASH_Generation_fnc_ClassKind") then {
                [typeOf _asset] call ITW_CLASH_Generation_fnc_ClassKind
            } else {
                if (_asset isKindOf "Tank") then {"TANK"} else {
                    if (_asset isKindOf "Car") then {"CAR"} else {"OTHER"}
                }
            };
            switch (_vehicleKind) do {
                case "TANK": {"ARM"};
                case "CAR": {"INF"};
                default {""};
            }
        };
        case "CAS_AIRCRAFT": {
            if (toUpperANSI _kind == "AIR") then {"AIRCAP"} else {"AIR"}
        };
        default {""};
    };
    if (_pattern == "") exitWith {
        ["immediate-dispatch-unsupported",[
            _reply getOrDefault ["requestId",""],_kind,_capabilityKey,typeOf _asset
        ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
        false
    };

    private _launcher = [_pattern] call RYD_GoLaunch;
    if !(_launcher isEqualType {}) exitWith {false};

    _group setVariable ["Busy" + str _group,true];
    _hq setVariable [
        "RydHQ_AttackAv",
        (_hq getVariable ["RydHQ_AttackAv",[]]) - [_group]
    ];
    [_hq,_group,_targetGroup,_kind] call
        ITW_CLASH_HALThreatCoverage_fnc_Commit;

    [[_group,_target,_hq],_launcher] call RYD_Spawn;

    ["immediate-dispatch",[
        _reply getOrDefault ["requestId",""],
        _kind,_capabilityKey,_pattern,typeOf _asset,
        groupId _group,groupId _targetGroup,
        round (_asset distance2D _target)
    ]] call ITW_CLASH_HALThreatCoverage_fnc_Log;
    diag_log format [
        "CLASH THREAT COVERAGE | immediate HAL task | %1 (%2) -> %3 | target=%4",
        typeOf _asset,_pattern,[_kind] call ITW_CLASH_HALThreatCoverage_fnc_DescribeKind,
        groupId _targetGroup
    ];
    true
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
    private _reference = if (!isNull _targetGroup && {!isNull leader _targetGroup}) then {
        getPosATL (vehicle leader _targetGroup)
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
    private _aaInfUsable  = [(_hq getVariable ["RydHQ_AAInfG", []]),_hq] call ITW_CLASH_HALThreatCoverage_fnc_UsableGroups;

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
            !isNull _x && {!isNull leader _x} && {alive leader _x}
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
                        private _mode = if (_capability == "CAS_AIRCRAFT") then {"AIR"} else {"GROUND"};
                        diag_log format [
                            "%1 at %2, requesting %3",
                            [_kind] call ITW_CLASH_HALThreatCoverage_fnc_DescribeKind,
                            getPosATL (vehicle leader _targetGroup),
                            _capability
                        ];
                        [_hq,_capability,_mode,_kind,_targetGroup] call
                            ITW_CLASH_HALThreatCoverage_fnc_Request;
                    };
                };
            };
        };
    } forEach _demandCategories;

    // Air/AIRCAP - its own case, not part of the generic table above: HAL's
    // "Air" dispatch pool is airCAP+AAInfG (HAC_fnc.sqf's "Air" case), not
    // airCAS. Same OR-coverage fix applies here: AAInfG having usable
    // squads means HAL already has a legitimate answer, even with RCAP
    // empty - only request when BOTH are genuinely dry. A Checkbook-bought
    // CAS_AIRCRAFT asset registers into both RCAS and RCAP (see
    // ForceGeneration.sqf), so requesting it here is still the right ask.
    private _airDemand = (_hq getVariable ["RydHQ_EnAir", []]) select {
        !isNull _x && {!isNull leader _x} && {alive leader _x}
    };
    if (count _airDemand > 0 && {count _airCapUsable <= 0} && {count _aaInfUsable <= 0}) then {
        private _targetIndex = _airDemand findIf {
            !([_hq,_x,"Air"] call
                ITW_CLASH_HALThreatCoverage_fnc_CommitmentActive)
        };
        if (_targetIndex >= 0) then {
            private _targetGroup = _airDemand#_targetIndex;
            private _cooldownKey = "ITW_CLASH_ThreatCoverageRetryAt_Air_Cap";
            if (time >= (_hq getVariable [_cooldownKey,0])) then {
                _hq setVariable [_cooldownKey,time + 45];
                diag_log format [
                    "%1 at %2, requesting %3",
                    ["Air"] call ITW_CLASH_HALThreatCoverage_fnc_DescribeKind,
                    getPosATL (vehicle leader _targetGroup),
                    "CAS_AIRCRAFT"
                ];
                [_hq,"CAS_AIRCRAFT","AIR","Air",_targetGroup] call
                    ITW_CLASH_HALThreatCoverage_fnc_Request;
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
