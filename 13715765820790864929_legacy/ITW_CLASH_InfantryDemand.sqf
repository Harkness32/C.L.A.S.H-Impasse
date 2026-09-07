#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_InfantryDemandStarted",false]) exitWith {true};
ITW_CLASH_InfantryDemandStarted = true;
ITW_CLASH_InfantryDemandVersion = 1;
ITW_CLASH_InfantryDemandReady = false;

// Infantry gets no ForceGeneration-style provider - Impasse's own manpower
// loop (ITW_Attack.sqf, the "Infantry AI Spawner" block gated on
// _activeAiCnt < _maxAiRightNow) already continuously replenishes it, fully
// independent of HAL. A second spawn path would double the manpower system,
// not extend it. Instead: a one-shot, side-scoped advisory demand
// (AT/AA/RECON), consulted only at the exact point Impasse is about to pick
// a squad template (ITW_Attack.sqf, `selectRandom _squadTypes`). Impasse
// still decides everything else - cap, position, timing, fallback. This file
// never spawns, never touches RydHQ_*, never reserves manpower.
ITW_CLASH_InfantryDemandBySide = createHashMap;
ITW_CLASH_InfantryDemandExpirySeconds = missionNamespace getVariable [
    "ITW_CLASH_InfantryDemandExpirySeconds",120
];

ITW_CLASH_InfantryDemand_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["infantry-demand-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH INFANTRY DEMAND | %1 | %2",_event,_payload];
    };
};

// Called by the HAL-state watcher below (or anything else) to raise a
// one-shot demand. A demand already pending for this side is not overwritten
// - first legitimate deficit wins until it's consumed or expires.
ITW_CLASH_InfantryDemand_fnc_SetDemand = {
    params ["_side","_kind"];
    private _existing = ITW_CLASH_InfantryDemandBySide getOrDefault [str _side,createHashMap];
    if ((_existing getOrDefault ["kind",""]) != "") exitWith {false};
    ITW_CLASH_InfantryDemandBySide set [str _side,createHashMapFromArray [
        ["kind",_kind],
        ["raisedAt",time],
        ["expiresAt",time + ITW_CLASH_InfantryDemandExpirySeconds]
    ]];
    ["demand-raised",[str _side,_kind]] call ITW_CLASH_InfantryDemand_fnc_Log;
    true
};

// HAL's ACTUAL live role vocabulary - mirrors HQSitRep.sqf:119-127 exactly
// (RHQ_ATInf + RYD_WS_ATinf_class - RHQs_ATInf), not just the static
// RHQLibrary.sqf baseline. RHQ_*/RHQs_* are this mission's own per-faction
// additions/exclusions on top of that baseline - skipping them would miss
// exactly the modded-faction classes HAL itself accounts for. All three
// pieces are plain missionNamespace globals in HQSitRep.sqf (no getVariable
// prefix there), safe to read the same way from outside a SitRep cycle.
// Lowercased on the way out: ITW_Attack.sqf stores _squadTypes classnames via
// toLowerANSI, so an un-lowercased vocabulary would silently fail every
// arrayIntersect below even when a real match exists.
ITW_CLASH_InfantryDemand_fnc_Vocabulary = {
    params ["_kind"];
    private _raw = switch (_kind) do {
        case "AT": {
            (missionNamespace getVariable ["RHQ_ATInf",[]])
            + (missionNamespace getVariable ["RYD_WS_ATinf_class",[]])
            - (missionNamespace getVariable ["RHQs_ATInf",[]])
        };
        case "AA": {
            (missionNamespace getVariable ["RHQ_AAInf",[]])
            + (missionNamespace getVariable ["RYD_WS_AAinf_class",[]])
            - (missionNamespace getVariable ["RHQs_AAInf",[]])
        };
        case "RECON": {
            (missionNamespace getVariable ["RHQ_Recon",[]])
            + (missionNamespace getVariable ["RYD_WS_recon_class",[]])
            - (missionNamespace getVariable ["RHQs_Recon",[]])
        };
        default {[]};
    };
    _raw apply {toLowerANSI _x}
};

// The hook. Called from ITW_Attack.sqf immediately before its own
// `selectRandom _squadTypes` fallback, only when _squadTypes is non-empty
// (Impasse's own 50%-coverage safety valve already ran before this is ever
// reached). Returns [] to mean "no preference, do your normal thing" - the
// exact same result as CLASH never having been consulted at all.
ITW_CLASH_fnc_SelectInfantryTemplate = {
    params ["_squadTypes","_side"];
    private _demand = ITW_CLASH_InfantryDemandBySide getOrDefault [str _side,createHashMap];
    private _kind = _demand getOrDefault ["kind",""];
    if (_kind == "") exitWith {[]};

    if (time > (_demand getOrDefault ["expiresAt",0])) exitWith {
        ITW_CLASH_InfantryDemandBySide set [str _side,createHashMap];
        ["demand-expired",[str _side,_kind]] call ITW_CLASH_InfantryDemand_fnc_Log;
        []
    };

    private _vocab = [_kind] call ITW_CLASH_InfantryDemand_fnc_Vocabulary;
    if (_vocab isEqualTo []) exitWith {
        ["demand-no-vocabulary",[str _side,_kind]] call ITW_CLASH_InfantryDemand_fnc_Log;
        []
    };

    // No weighting - this is a one-shot request, not a standing bias. "Tilt
    // the odds across the whole pool" was the right idea for a lingering
    // preference; it's the wrong idea here, and weighting instead of
    // filtering was exactly what let a non-matching template win the roll
    // while still being logged (and consumed) as fulfilled. Filter to
    // legitimately matching templates first, pick uniformly among only
    // those, and only THEN is the demand actually satisfied.
    private _matches = _squadTypes select {count (_x arrayIntersect _vocab) > 0};

    if (_matches isEqualTo []) exitWith {
        // Respect Impasse's own fallback philosophy: if this faction has no
        // legitimate matching template, don't synthesize one - let it fall
        // through to selectRandom _squadTypes exactly as if CLASH weren't
        // here. Demand stays pending (not consumed) so a later attempt (a
        // different squadTypes pool, or the faction's templates changing)
        // can still succeed before expiry.
        ["demand-no-matching-template",[str _side,_kind]] call
            ITW_CLASH_InfantryDemand_fnc_Log;
        []
    };

    private _selected = +(selectRandom _matches);

    // One-shot: consumed only here, on an actual matching pick - never on a
    // miss, and never on a roll that happened to land on an ordinary squad.
    ITW_CLASH_InfantryDemandBySide set [str _side,createHashMap];
    ["demand-fulfilled",[str _side,_kind,count _selected]] call
        ITW_CLASH_InfantryDemand_fnc_Log;
    _selected
};

// HAL-state watcher: the same self-contained poll shape as
// ITW_CLASH_HALThreatCoverage.sqf. Reads HAL's own public demand
// (RydHQ_En*) and HAL's own public capability pools (RydHQ_ATInfG,
// RydHQ_AAInfG) directly - no dependency on ThreatCoverage or the addon,
// same reasoning: both read the same public state independently.
ITW_CLASH_InfantryDemand_fnc_Evaluate = {
    params ["_hq"];
    if (isNull _hq) exitWith {false};
    private _side = side _hq;

    private _armorPresent = (count (_hq getVariable ["RydHQ_EnHArmor",[]])) > 0
        || {(count (_hq getVariable ["RydHQ_EnLArmorAT",[]])) > 0};
    private _atCapable = (count (_hq getVariable ["RydHQ_ATInfG",[]])) > 0;
    if (_armorPresent && {!_atCapable}) then {
        [_side,"AT"] call ITW_CLASH_InfantryDemand_fnc_SetDemand;
    };

    private _airPresent = (count (_hq getVariable ["RydHQ_EnAir",[]])) > 0;
    private _aaCapable = (count (_hq getVariable ["RydHQ_AAInfG",[]])) > 0;
    if (_airPresent && {!_aaCapable}) then {
        [_side,"AA"] call ITW_CLASH_InfantryDemand_fnc_SetDemand;
    };
    true
};

[] spawn {
    scriptName "ITW_CLASH_InfantryDemandBootstrap";
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
                [_hq] call ITW_CLASH_InfantryDemand_fnc_Evaluate;
            };
        } forEach _sides;

        sleep 30;
    };
};

ITW_CLASH_InfantryDemandReady = true;
diag_log format [
    "CLASH BOOT | infantry-demand-ready | version=%1 kinds=AT,AA hook=selectInfantryTemplate provider=none spawnPath=impasse-native",
    ITW_CLASH_InfantryDemandVersion
];

true
