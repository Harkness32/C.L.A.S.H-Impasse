#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerDemandNativeInterceptorsStarted",false]) exitWith {true};

ITW_CLASH_PlayerDemandNativeInterceptorsStarted = true;
ITW_CLASH_PlayerDemandNativeInterceptorsReady = false;
ITW_CLASH_PlayerDemandNativeInterceptorsVersion = 2;

// Load the post-bind execution ownership correction before any native support
// handoff can be intercepted. The hardening file waits for DemandDispatchReady
// and then makes specialist executors authoritative once a job is EXECUTING.
if (fileExists "ITW_CLASH_PlayerDemandExecutionHardening.sqf") then {
    call compile preprocessFileLineNumbers "ITW_CLASH_PlayerDemandExecutionHardening.sqf";
} else {
    diag_log "CLASH BOOT | player-demand-execution-hardening-missing | native interceptors remain fail-open";
};

ITW_CLASH_PlayerDemandNative_fnc_FindCandidate = {
    params ["_channel"];
    private _found = grpNull;
    {
        if (isNull _x) then {continue};
        if ([_x,_channel] call ITW_CLASH_PlayerTasks_fnc_CanAcceptJob) exitWith {
            _found = _x;
        };
    } forEach +ITW_CLASH_PlayerTaskGroups;
    _found
};

ITW_CLASH_PlayerDemandNative_fnc_TakeAmmo = {
    params ["_hq","_target"];
    if (isNull _hq || {isNull _target}) exitWith {false};
    private _candidate = ["LOGISTICS"] call ITW_CLASH_PlayerDemandNative_fnc_FindCandidate;
    if (isNull _candidate) exitWith {false};

    private _targetGroup = [_target] call ITW_CLASH_PlayerDemand_fnc_TargetGroup;
    if (isNull _targetGroup) exitWith {false};
    private _supportedBefore = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
    private _nativeOwned = _targetGroup in _supportedBefore;
    if (_nativeOwned) then {
        _hq setVariable ["RydHQ_ASupportedG",_supportedBefore - [_targetGroup]];
    };

    private _name = [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId;
    private _demandId = [
        "LOGISTICS","LOGISTICS_AMMO","LOGISTICS_AMMO|" + str _targetGroup,
        _hq,_target,
        "HAL Logistics: Ammunition Delivery",
        format ["HAL reports %1 requires ammunition support. Deliver an ammunition package to the marked recipient.",_name],
        "Acquire a sling-capable helicopter that can lift the ammunition package.",
        getPosATL _target
    ] call ITW_CLASH_PlayerDemand_fnc_Publish;

    private _reserved = _demandId isNotEqualTo "" && {
        [_demandId,_candidate] call ITW_CLASH_PlayerDemand_fnc_Reserve
    };
    if (!_reserved && {_nativeOwned}) then {
        private _restore = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
        _restore pushBackUnique _targetGroup;
        _hq setVariable ["RydHQ_ASupportedG",_restore];
    };
    if (_reserved) then {
        ["native-assignment-taken-over",[
            _demandId,"LOGISTICS_AMMO",
            [_candidate] call ITW_CLASH_PlayerDemand_fnc_GroupId,
            _name
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    };
    _reserved
};

ITW_CLASH_PlayerDemandNative_fnc_TakeMedevac = {
    params ["_hq","_casualty"];
    if (isNull _hq || {isNull _casualty}) exitWith {false};
    if !([_casualty] call ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty) exitWith {false};
    private _candidate = ["MEDEVAC"] call ITW_CLASH_PlayerDemandNative_fnc_FindCandidate;
    if (isNull _candidate) exitWith {false};

    private _targetGroup = group _casualty;
    if (isNull _targetGroup) exitWith {false};
    private _deliveredAt = _targetGroup getVariable ["ITW_CLASH_PlayerMedevacDeliveredAt",-1];
    if (_deliveredAt >= 0 && {
        time - _deliveredAt < ITW_CLASH_PlayerDemandMedevacDeliveredCooldown
    }) exitWith {false};

    private _supportedBefore = +(_hq getVariable ["RydHQ_SupportedG",[]]);
    private _nativeOwned = _targetGroup in _supportedBefore;
    if (_nativeOwned) then {
        _hq setVariable ["RydHQ_SupportedG",_supportedBefore - [_targetGroup]];
    };

    private _name = [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId;
    private _demandId = [
        "MEDEVAC","MEDEVAC_SEVERE","MEDEVAC_SEVERE|" + str _targetGroup,
        _hq,_casualty,
        "HAL MEDEVAC: Casualty Extraction",
        format ["HAL reports severe casualties in %1. Reach the casualty position, evacuate the surviving severe casualties, and return them to a live friendly base.",_name],
        "Acquire any living movable vehicle with sufficient passenger capacity for the evacuees.",
        getPosATL _casualty
    ] call ITW_CLASH_PlayerDemand_fnc_Publish;

    private _reserved = _demandId isNotEqualTo "" && {
        [_demandId,_candidate] call ITW_CLASH_PlayerDemand_fnc_Reserve
    };
    if (!_reserved && {_nativeOwned}) then {
        private _restore = +(_hq getVariable ["RydHQ_SupportedG",[]]);
        _restore pushBackUnique _targetGroup;
        _hq setVariable ["RydHQ_SupportedG",_restore];
    };
    if (_reserved) then {
        ["native-assignment-taken-over",[
            _demandId,"MEDEVAC_SEVERE",
            [_candidate] call ITW_CLASH_PlayerDemand_fnc_GroupId,
            _name
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    };
    _reserved
};

[] spawn {
    scriptName "ITW_CLASH_PlayerDemandNativeInterceptorsBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerDemandDispatchReady",false]
            && {missionNamespace getVariable ["ITW_CLASH_PlayerDemandExecutionHardeningReady",false]}
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
        _this call ITW_CLASH_PlayerDemandNative_fnc_GoAmmoSuppBase
    };

    ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase = HAL_GoMedSupp;
    HAL_GoMedSupp = {
        private _casualty = _this param [1,objNull];
        private _hq = _this param [3,grpNull];
        if (!isNull _hq && {!isNull _casualty} && {
            [_casualty] call ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty
        }) then {
            if ([_hq,_casualty] call ITW_CLASH_PlayerDemandNative_fnc_TakeMedevac) exitWith {};
        };
        _this call ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase
    };

    ITW_CLASH_PlayerDemandNativeInterceptorsReady = true;
    diag_log format [
        "CLASH BOOT | player-demand-native-interceptors-ready | version=%1 ammoAIHandoff=true severeMedicalHandoff=true specialistExecutionOwnership=true nativeFailOpen=true",
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

true