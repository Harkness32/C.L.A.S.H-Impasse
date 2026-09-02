#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerDemandNativeInterceptorsStarted",false]) exitWith {true};

ITW_CLASH_PlayerDemandNativeInterceptorsStarted = true;
ITW_CLASH_PlayerDemandNativeInterceptorsReady = false;
ITW_CLASH_PlayerDemandNativeInterceptorsVersion = 6;

// Load execution ownership first, then reservation/liveness policy, then the
// ammo-validity correction required by call-scoped ExReAmmo filtering. Each
// layer binds asynchronously once DemandDispatch has installed its primitives.
if (fileExists "ITW_CLASH_PlayerDemandExecutionHardening.sqf") then {
    call compile preprocessFileLineNumbers "ITW_CLASH_PlayerDemandExecutionHardening.sqf";
} else {
    diag_log "CLASH BOOT | player-demand-execution-hardening-missing | native interceptors remain fail-open";
};
if (fileExists "ITW_CLASH_PlayerDemandReservationHardening.sqf") then {
    call compile preprocessFileLineNumbers "ITW_CLASH_PlayerDemandReservationHardening.sqf";
} else {
    diag_log "CLASH BOOT | player-demand-reservation-hardening-missing | native interceptors remain fail-open";
};
if (fileExists "ITW_CLASH_PlayerDemandAmmoValidityHardening.sqf") then {
    call compile preprocessFileLineNumbers "ITW_CLASH_PlayerDemandAmmoValidityHardening.sqf";
} else {
    diag_log "CLASH BOOT | player-demand-ammo-validity-hardening-missing | native interceptors remain fail-open";
};

// HAL has already selected this ammo target and inserted the target group into
// ASupportedG immediately before calling GoAmmoSupp. Publish/find the exact
// demand first, then use the demand-specific dispatcher so decline cooldowns and
// AI fallback windows apply equally to passive offers and native takeover.
ITW_CLASH_PlayerDemandNative_fnc_TakeAmmo = {
    params ["_hq","_target"];
    if (isNull _hq || {isNull _target}) exitWith {false};
    private _targetGroup = [_target] call ITW_CLASH_PlayerDemand_fnc_TargetGroup;
    if (isNull _targetGroup) exitWith {false};

    private _name = [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId;
    private _demandId = [
        "LOGISTICS","LOGISTICS_AMMO","LOGISTICS_AMMO|" + str _targetGroup,
        _hq,_target,
        "HAL Logistics: Ammunition Delivery",
        format ["HAL reports %1 requires ammunition support. Deliver an ammunition package to the marked recipient.",_name],
        "Acquire a sling-capable helicopter that can lift the ammunition package.",
        getPosATL _target
    ] call ITW_CLASH_PlayerDemand_fnc_Publish;
    if (_demandId isEqualTo "") exitWith {false};

    private _candidate = [_demandId] call ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup;
    if (isNull _candidate) exitWith {
        ["native-takeover-deferred-to-ai",[
            _demandId,"LOGISTICS_AMMO",_name,"no-demand-eligible-player"
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        false
    };

    private _supportedBefore = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
    private _nativeOwned = _targetGroup in _supportedBefore;
    if (_nativeOwned) then {
        _hq setVariable ["RydHQ_ASupportedG",_supportedBefore - [_targetGroup]];
    };

    private _reserved = [_demandId,_candidate] call ITW_CLASH_PlayerDemand_fnc_Reserve;
    if (!_reserved && {_nativeOwned}) then {
        private _restore = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
        _restore pushBackUnique _targetGroup;
        _hq setVariable ["RydHQ_ASupportedG",_restore];
    };
    if (_reserved) then {
        ["native-assignment-taken-over",[
            _demandId,"LOGISTICS_AMMO",
            [_candidate] call ITW_CLASH_PlayerDemand_fnc_GroupId,
            _name,"native-ASupportedG-cleared-on-handoff"
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    };
    _reserved
};

// Same handoff rule for severe medical support. SupportedG is cleared only
// when the exact native assignment is replaced by a player MEDEVAC reservation;
// the durable reservation lives on the C.L.A.S.H. casualty-group marker.
ITW_CLASH_PlayerDemandNative_fnc_TakeMedevac = {
    params ["_hq","_casualty"];
    if (isNull _hq || {isNull _casualty}) exitWith {false};
    if !([_casualty] call ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty) exitWith {false};

    private _targetGroup = group _casualty;
    if (isNull _targetGroup) exitWith {false};
    private _deliveredAt = _targetGroup getVariable ["ITW_CLASH_PlayerMedevacDeliveredAt",-1];
    if (_deliveredAt >= 0 && {
        time - _deliveredAt < ITW_CLASH_PlayerDemandMedevacDeliveredCooldown
    }) exitWith {false};

    private _name = [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId;
    private _demandId = [
        "MEDEVAC","MEDEVAC_SEVERE","MEDEVAC_SEVERE|" + str _targetGroup,
        _hq,_casualty,
        "HAL MEDEVAC: Casualty Extraction",
        format ["HAL reports severe casualties in %1. Reach the casualty position, evacuate the surviving severe casualties, and return them to a live friendly base.",_name],
        "Acquire any living movable vehicle with sufficient passenger capacity for the evacuees.",
        getPosATL _casualty
    ] call ITW_CLASH_PlayerDemand_fnc_Publish;
    if (_demandId isEqualTo "") exitWith {false};

    private _candidate = [_demandId] call ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup;
    if (isNull _candidate) exitWith {
        ["native-takeover-deferred-to-ai",[
            _demandId,"MEDEVAC_SEVERE",_name,"no-demand-eligible-player"
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        false
    };

    private _supportedBefore = +(_hq getVariable ["RydHQ_SupportedG",[]]);
    private _nativeOwned = _targetGroup in _supportedBefore;
    if (_nativeOwned) then {
        _hq setVariable ["RydHQ_SupportedG",_supportedBefore - [_targetGroup]];
    };

    private _reserved = [_demandId,_candidate] call ITW_CLASH_PlayerDemand_fnc_Reserve;
    if (!_reserved && {_nativeOwned}) then {
        private _restore = +(_hq getVariable ["RydHQ_SupportedG",[]]);
        _restore pushBackUnique _targetGroup;
        _hq setVariable ["RydHQ_SupportedG",_restore];
    };
    if (_reserved) then {
        ["native-assignment-taken-over",[
            _demandId,"MEDEVAC_SEVERE",
            [_candidate] call ITW_CLASH_PlayerDemand_fnc_GroupId,
            _name,"native-SupportedG-cleared-on-handoff"
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    };
    _reserved
};

ITW_CLASH_PlayerDemandNative_fnc_BlockReservedAmmoRace = {
    params ["_hq","_target"];
    if (isNull _hq || {isNull _target}) exitWith {false};
    private _targetGroup = [_target] call ITW_CLASH_PlayerDemand_fnc_TargetGroup;
    if (isNull _targetGroup) exitWith {false};
    private _demandId = _targetGroup getVariable [
        "ITW_CLASH_PlayerAmmoDemandReservation",""
    ];
    if (_demandId isEqualTo "") exitWith {false};
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0 || {
        !((_demand getOrDefault ["state",""]) in ["RESERVED","EXECUTING"])
    }) exitWith {false};

    // SuppAmmo may have selected this target in the same scheduler slice before
    // the call-scoped ExReAmmo wrapper saw the new reservation. Remove only the
    // native assignment marker it just wrote and swallow this duplicate handoff.
    private _supported = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
    if (_targetGroup in _supported) then {
        _hq setVariable ["RydHQ_ASupportedG",_supported - [_targetGroup]];
    };
    ["native-reserved-race-blocked",[
        _demandId,"LOGISTICS_AMMO",
        [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    true
};

ITW_CLASH_PlayerDemandNative_fnc_BlockReservedMedevacRace = {
    params ["_hq","_casualty"];
    if (isNull _hq || {isNull _casualty}) exitWith {false};
    private _targetGroup = group _casualty;
    if (isNull _targetGroup) exitWith {false};
    private _demandId = _targetGroup getVariable [
        "ITW_CLASH_PlayerMedevacDemandReservation",""
    ];
    if (_demandId isEqualTo "") exitWith {false};
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0 || {
        !((_demand getOrDefault ["state",""]) in ["RESERVED","EXECUTING"])
    }) exitWith {false};

    private _supported = +(_hq getVariable ["RydHQ_SupportedG",[]]);
    if (_targetGroup in _supported) then {
        _hq setVariable ["RydHQ_SupportedG",_supported - [_targetGroup]];
    };
    ["native-reserved-race-blocked",[
        _demandId,"MEDEVAC_SEVERE",
        [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerDemandNativeInterceptorsBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerDemandDispatchReady",false]
            && {missionNamespace getVariable ["ITW_CLASH_PlayerDemandExecutionHardeningReady",false]}
            && {missionNamespace getVariable ["ITW_CLASH_PlayerDemandReservationHardeningReady",false]}
            && {missionNamespace getVariable ["ITW_CLASH_PlayerDemandAmmoValidityHardeningReady",false]}
            && {missionNamespace getVariable ["ITW_CLASH_PlayerTaskSupportReady",false]}
            && {!isNil "HAL_GoAmmoSupp"}
            && {!isNil "HAL_GoMedSupp"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-demand-native-interceptors-bind-timeout | native support execution retained";
    };

    ITW_CLASH_PlayerDemandNative_fnc_GoAmmoSuppBase = HAL_GoAmmoSupp;
    HAL_GoAmmoSupp = {
        private _vehicle = _this param [0,objNull];
        private _target = _this param [1,objNull];
        private _hq = _this param [6,grpNull];

        if (!isNull _hq && {!isNull _target} && {
            [_hq,_target] call ITW_CLASH_PlayerDemandNative_fnc_BlockReservedAmmoRace
        }) exitWith {};

        private _providerGroup = grpNull;
        if (!isNull _vehicle) then {
            private _driver = assignedDriver _vehicle;
            if (isNull _driver) then {_driver = driver _vehicle};
            if (!isNull _driver) then {_providerGroup = group _driver};
        };
        private _providerHuman = !isNull _providerGroup && {
            (units _providerGroup findIf {isPlayer _x}) >= 0
        };

        // Existing PlayerTaskSupport owns the already-capable human provider
        // fast path. Demand-first takeover is for HAL-selected AI providers.
        if (!_providerHuman && {!isNull _hq} && {!isNull _target}) then {
            if ([_hq,_target] call ITW_CLASH_PlayerDemandNative_fnc_TakeAmmo) exitWith {};
        };

        private _targetGroup = if (isNull _target) then {grpNull} else {
            [_target] call ITW_CLASH_PlayerDemand_fnc_TargetGroup
        };
        private _nativeToken = "";
        if (!_providerHuman && {!isNull _targetGroup}) then {
            _nativeToken = format [
                "NATIVE-AMMO-%1-%2",
                round (diag_tickTime * 1000),
                [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
            ];
            _targetGroup setVariable [
                "ITW_CLASH_NativeAmmoExecution",_nativeToken
            ];
            ["native-ai-execution-started",[
                _nativeToken,
                [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId,
                if (isNull _providerGroup) then {"<null>"} else {
                    [_providerGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
                }
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        };

        private _nativeResult = true;
        private _nativeResultDefined = !(isNil {
            _nativeResult = _this call ITW_CLASH_PlayerDemandNative_fnc_GoAmmoSuppBase;
        });

        if (_nativeToken isNotEqualTo "" && {!isNull _targetGroup}) then {
            if ((_targetGroup getVariable [
                "ITW_CLASH_NativeAmmoExecution",""
            ]) == _nativeToken) then {
                _targetGroup setVariable ["ITW_CLASH_NativeAmmoExecution",nil];
            };
            ["native-ai-execution-ended",[
                _nativeToken,
                [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        };

        if (_nativeResultDefined) then {_nativeResult}
    };

    ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase = HAL_GoMedSupp;
    HAL_GoMedSupp = {
        private _casualty = _this param [1,objNull];
        private _hq = _this param [3,grpNull];

        if (!isNull _hq && {!isNull _casualty} && {
            [_hq,_casualty] call ITW_CLASH_PlayerDemandNative_fnc_BlockReservedMedevacRace
        }) exitWith {};

        if (!isNull _hq && {!isNull _casualty} && {
            [_casualty] call ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty
        }) then {
            if ([_hq,_casualty] call ITW_CLASH_PlayerDemandNative_fnc_TakeMedevac) exitWith {};
        };
        _this call ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase
    };

    ITW_CLASH_PlayerDemandNativeInterceptorsReady = true;
    diag_log format [
        "CLASH BOOT | player-demand-native-interceptors-ready | version=%1 ammoAIHandoff=true severeMedicalHandoff=true exactDemandDispatch=true markerAuthority=true nativeAmmoExecutionMarker=true callScopedNativeExclusion=true sameCycleRaceGuard=true specialistExecutionOwnership=true nativeFailOpen=true",
        ITW_CLASH_PlayerDemandNativeInterceptorsVersion
    ];

    // If HAL has demand but no provider was selected, the native handoff above
    // never fires. Observe HAL's published need arrays and offer those requests
    // to subscribers without inventing a second target-selection model.
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 2;
        if (!missionNamespace getVariable ["ITW_CLASH_HALReady",false]) then {continue};
        private _hq = missionNamespace getVariable ["ITW_CLASH_BLUFORHQ",grpNull];
        if (isNull _hq) then {continue};

        [_hq,+(_hq getVariable ["RydHQ_Hollow",[]])] call
            ITW_CLASH_PlayerDemand_fnc_OnAmmoDemand;
        private _severe = +(_hq getVariable ["RydHQ_Wounded",[]]);
        _severe = _severe select {
            [_x] call ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty
        };
        [_hq,_severe] call ITW_CLASH_PlayerDemand_fnc_OnMedicalDemand;
    };
};

// Player-initiated tasking is a follow-on layer stacked on top of the demand-
// first tranche. Loading it here guarantees PlayerTaskSupport and the shared
// one-owner lifecycle exist before request adapters become available, while the
// adapters themselves remain readiness-gated and fail closed.
if (fileExists "ITW_CLASH_PlayerTaskRequests.sqf") then {
    call compile preprocessFileLineNumbers "ITW_CLASH_PlayerTaskRequests.sqf";
    if (fileExists "ITW_CLASH_PlayerTaskRequestArtillery.sqf") then {
        call compile preprocessFileLineNumbers "ITW_CLASH_PlayerTaskRequestArtillery.sqf";
    } else {
        diag_log "CLASH BOOT | player-task-request-artillery-missing | ARTILLERY request remains unavailable";
    };
} else {
    diag_log "CLASH BOOT | player-task-request-router-missing | player-initiated tasking disabled";
};

true