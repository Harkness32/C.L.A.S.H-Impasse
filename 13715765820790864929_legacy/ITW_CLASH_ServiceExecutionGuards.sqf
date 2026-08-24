if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ServiceExecutionGuardsStarted",false]) exitWith {true};
ITW_CLASH_ServiceExecutionGuardsStarted = true;
ITW_CLASH_ServiceExecutionGuardsVersion = 1;
ITW_CLASH_ServiceExecutionGuardsReady = false;

ITW_CLASH_ServiceExecution_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_ServiceStability_fnc_Log") then {
        ["execution-" + _event,_payload] call ITW_CLASH_ServiceStability_fnc_Log;
    } else {
        diag_log format ["CLASH SERVICE EXECUTION | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_ServiceExecution_fnc_Reject = {
    params ["_group","_category","_surface"];
    if (isNull _group || {isNil "ITW_CLASH_ServiceStability_fnc_HasLease"}) exitWith {false};
    if !([_group,vehicle leader _group] call ITW_CLASH_ServiceStability_fnc_HasLease) exitWith {false};

    _group setVariable ["Busy" + str _group,false];
    if (!isNil "ITW_CLASH_ServiceStability_fnc_EnsureQuarantine") then {
        [_group,"execution-" + toLowerANSI _category] call
            ITW_CLASH_ServiceStability_fnc_EnsureQuarantine;
    };
    ["rejected",[
        if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
            [_group] call ITW_CLASH_DualHAL_fnc_GroupId
        } else {str _group},
        _category,_surface,
        +(_group getVariable ["ITW_CLASH_ServiceLease",[]])
    ]] call ITW_CLASH_ServiceExecution_fnc_Log;
    true
};

[] spawn {
    scriptName "ITW_CLASH_ServiceExecutionGuardBinder";
    private _deadline = time + 240;
    waitUntil {
        sleep 0.25;
        time >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_ServiceStabilityReady",false]
            && {!isNil "HAL_GoAttInf"}
            && {!isNil "HAL_GoAttArmor"}
            && {!isNil "HAL_GoAttSniper"}
            && {!isNil "HAL_GoAttAir"}
            && {!isNil "HAL_GoAttAirCAP"}
            && {!isNil "HAL_GoAttNaval"}
            && {!isNil "HAL_GoDef"}
            && {!isNil "HAL_GoDefAir"}
            && {!isNil "HAL_GoDefNav"}
            && {!isNil "HAL_GoDefRes"}
        }
    };
    if (time >= _deadline) exitWith {
        ["bind-timeout",[
            !isNil "HAL_GoAttInf",!isNil "HAL_GoAttArmor",!isNil "HAL_GoAttSniper",
            !isNil "HAL_GoAttAir",!isNil "HAL_GoAttAirCAP",!isNil "HAL_GoAttNaval",
            !isNil "HAL_GoDef",!isNil "HAL_GoDefAir",!isNil "HAL_GoDefNav",!isNil "HAL_GoDefRes"
        ]] call ITW_CLASH_ServiceExecution_fnc_Log;
    };

    ITW_CLASH_ServiceExecution_fnc_GoAttInfBase = HAL_GoAttInf;
    ITW_CLASH_ServiceExecution_fnc_GoAttArmorBase = HAL_GoAttArmor;
    ITW_CLASH_ServiceExecution_fnc_GoAttSniperBase = HAL_GoAttSniper;
    ITW_CLASH_ServiceExecution_fnc_GoAttAirBase = HAL_GoAttAir;
    ITW_CLASH_ServiceExecution_fnc_GoAttAirCAPBase = HAL_GoAttAirCAP;
    ITW_CLASH_ServiceExecution_fnc_GoAttNavalBase = HAL_GoAttNaval;
    ITW_CLASH_ServiceExecution_fnc_GoDefBase = HAL_GoDef;
    ITW_CLASH_ServiceExecution_fnc_GoDefAirBase = HAL_GoDefAir;
    ITW_CLASH_ServiceExecution_fnc_GoDefNavBase = HAL_GoDefNav;
    ITW_CLASH_ServiceExecution_fnc_GoDefResBase = HAL_GoDefRes;

    HAL_GoAttInf = {
        private _group = _this param [0,grpNull];
        if ([_group,"ATTACK","GoAttInf"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoAttInfBase
    };
    HAL_GoAttArmor = {
        private _group = _this param [0,grpNull];
        if ([_group,"ATTACK","GoAttArmor"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoAttArmorBase
    };
    HAL_GoAttSniper = {
        private _group = _this param [0,grpNull];
        if ([_group,"ATTACK","GoAttSniper"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoAttSniperBase
    };
    HAL_GoAttAir = {
        private _group = _this param [0,grpNull];
        if ([_group,"ATTACK","GoAttAir"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoAttAirBase
    };
    HAL_GoAttAirCAP = {
        private _group = _this param [0,grpNull];
        if ([_group,"ATTACK","GoAttAirCAP"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoAttAirCAPBase
    };
    HAL_GoAttNaval = {
        private _group = _this param [0,grpNull];
        if ([_group,"ATTACK","GoAttNaval"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoAttNavalBase
    };

    HAL_GoDef = {
        private _group = _this param [0,grpNull];
        if ([_group,"DEFENSE","GoDef"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoDefBase
    };
    HAL_GoDefAir = {
        private _group = _this param [0,grpNull];
        if ([_group,"DEFENSE","GoDefAir"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoDefAirBase
    };
    HAL_GoDefNav = {
        private _group = _this param [0,grpNull];
        if ([_group,"DEFENSE","GoDefNav"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoDefNavBase
    };
    HAL_GoDefRes = {
        private _group = _this param [0,grpNull];
        if ([_group,"DEFENSE","GoDefRes"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
        _this call ITW_CLASH_ServiceExecution_fnc_GoDefResBase
    };

    private _optionalAttack = [];
    if (!isNil "HAL_GoFlank") then {
        ITW_CLASH_ServiceExecution_fnc_GoFlankBase = HAL_GoFlank;
        HAL_GoFlank = {
            private _group = _this param [0,grpNull];
            if ([_group,"ATTACK","GoFlank"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
            _this call ITW_CLASH_ServiceExecution_fnc_GoFlankBase
        };
        _optionalAttack pushBack "GoFlank";
    };
    if (!isNil "HAL_GoSFAttack") then {
        ITW_CLASH_ServiceExecution_fnc_GoSFAttackBase = HAL_GoSFAttack;
        HAL_GoSFAttack = {
            private _group = _this param [0,grpNull];
            if ([_group,"ATTACK","GoSFAttack"] call ITW_CLASH_ServiceExecution_fnc_Reject) exitWith {false};
            _this call ITW_CLASH_ServiceExecution_fnc_GoSFAttackBase
        };
        _optionalAttack pushBack "GoSFAttack";
    };

    ITW_CLASH_ServiceExecutionGuardsReady = true;
    ["guard-ready",[
        "attack",["GoAttInf","GoAttArmor","GoAttSniper","GoAttAir","GoAttAirCAP","GoAttNaval"] + _optionalAttack,
        "defense",["GoDef","GoDefAir","GoDefNav","GoDefRes"],
        "recon","service-stability"
    ]] call ITW_CLASH_ServiceExecution_fnc_Log;
    diag_log format [
        "CLASH BOOT | service-execution-guards-ready | version=%1 attackGuard=true defenseGuard=true reconGuard=service-stability optionalAttack=%2",
        ITW_CLASH_ServiceExecutionGuardsVersion,_optionalAttack
    ];
};

true
