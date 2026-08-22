#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALLogisticsStarted",false]) exitWith {true};
ITW_CLASH_HALLogisticsStarted = true;
ITW_CLASH_HALLogisticsVersion = 1;
ITW_CLASH_HALLogisticsReady = false;

ITW_CLASH_HALLogistics_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-logistics-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL LOGISTICS | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_HALLogistics_fnc_UsableGroups = {
    params ["_groups"];
    _groups select {
        !isNull _x && {{alive _x} count units _x > 0} && {
            private _veh = vehicle leader _x;
            !isNull _veh && {alive _veh} && {canMove _veh}
        }
    }
};

ITW_CLASH_HALLogistics_fnc_Request = {
    params ["_hq","_capability","_mode"];
    if (isNull _hq || {isNil "ITW_CLASH_fnc_RequestCapability"}) exitWith {createHashMap};
    private _side = side _hq;
    private _requirements = createHashMapFromArray [
        ["hq",_hq],
        ["side",_side],
        ["mode",_mode],
        ["profile",if (_mode == "AIR") then {"REAR_AIR"} else {"REAR"}],
        ["reference",getPosATL leader _hq]
    ];
    private _reply = [
        _capability,_hq,_requirements,"HIGH"
    ] call ITW_CLASH_fnc_RequestCapability;
    ["request-result",[
        _hq getVariable ["RydHQ_CodeSign","?"],
        _capability,
        _mode,
        _reply getOrDefault ["status","INVALID"],
        _reply getOrDefault ["reason","invalid-result"],
        _reply getOrDefault ["requestId",""]
    ]] call ITW_CLASH_HALLogistics_fnc_Log;
    _reply
};

ITW_CLASH_HALLogistics_fnc_Evaluate = {
    params ["_hq","_kind"];
    if (isNull _hq || {
        !(missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false])
    }) exitWith {false};

    private _cooldownKey = "ITW_CLASH_LogisticsRetryAt_" + _kind;
    if (time < (_hq getVariable [_cooldownKey,0])) exitWith {false};
    _hq setVariable [_cooldownKey,time + 45];

    switch (_kind) do {
        case "AMMO": {
            private _demand = +(_hq getVariable ["RydHQ_Hollow",[]]);
            if (_demand isEqualTo []) exitWith {false};

            private _allAmmo = [
                +(_hq getVariable ["RydHQ_AmmoSupportG",[]])
            ] call ITW_CLASH_HALLogistics_fnc_UsableGroups;
            private _airAmmo = [
                +(_hq getVariable ["RydHQ_AmmoDrop",[]])
            ] call ITW_CLASH_HALLogistics_fnc_UsableGroups;
            private _groundAmmo = _allAmmo - _airAmmo;
            private _ammoBoxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
            _ammoBoxes = _ammoBoxes select {!isNull _x && {alive _x}};
            _hq setVariable ["RydHQ_AmmoBoxes",_ammoBoxes];

            if (_groundAmmo isEqualTo []) then {
                [_hq,"LOGISTICS_AMMO","GROUND"] call ITW_CLASH_HALLogistics_fnc_Request;
            };
            if (_airAmmo isEqualTo []) then {
                [_hq,"LOGISTICS_AMMO","AIR"] call ITW_CLASH_HALLogistics_fnc_Request;
            };
            if (_ammoBoxes isEqualTo []) then {
                [_hq,"LOGISTICS_PACKAGE_AMMO","AIR"] call
                    ITW_CLASH_HALLogistics_fnc_Request;
            };
            true
        };
        case "FUEL": {
            private _demand = +(_hq getVariable ["RydHQ_Dried",[]]);
            if (_demand isEqualTo []) exitWith {false};
            private _providers = [
                +(_hq getVariable ["RydHQ_FuelSupportG",[]])
            ] call ITW_CLASH_HALLogistics_fnc_UsableGroups;
            if (_providers isEqualTo []) then {
                [_hq,"LOGISTICS_FUEL","GROUND"] call ITW_CLASH_HALLogistics_fnc_Request;
            };
            true
        };
        case "REPAIR": {
            private _demand = +(_hq getVariable ["RydHQ_damaged",[]]);
            if (_demand isEqualTo []) exitWith {false};
            private _providers = [
                +(_hq getVariable ["RydHQ_RepSupportG",[]])
            ] call ITW_CLASH_HALLogistics_fnc_UsableGroups;
            if (_providers isEqualTo []) then {
                [_hq,"LOGISTICS_REPAIR","GROUND"] call ITW_CLASH_HALLogistics_fnc_Request;
            };
            true
        };
        default {false};
    }
};

[] spawn {
    scriptName "ITW_CLASH_HALLogisticsBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.25;
        diag_tickTime >= _deadline || {
            !isNil "HAL_SuppAmmo" && {
                !isNil "HAL_SuppFuel" && {!isNil "HAL_SuppRep"}
            }
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        ["bind-timeout",[]] call ITW_CLASH_HALLogistics_fnc_Log;
    };

    ITW_CLASH_HALLogistics_fnc_NativeSuppAmmo = HAL_SuppAmmo;
    ITW_CLASH_HALLogistics_fnc_NativeSuppFuel = HAL_SuppFuel;
    ITW_CLASH_HALLogistics_fnc_NativeSuppRep = HAL_SuppRep;

    HAL_SuppAmmo = {
        private _hq = _this param [0,grpNull];
        private _result = _this call ITW_CLASH_HALLogistics_fnc_NativeSuppAmmo;
        if (!isNull _hq) then {[_hq,"AMMO"] spawn ITW_CLASH_HALLogistics_fnc_Evaluate};
        _result
    };
    HAL_SuppFuel = {
        private _hq = _this param [0,grpNull];
        private _result = _this call ITW_CLASH_HALLogistics_fnc_NativeSuppFuel;
        if (!isNull _hq) then {[_hq,"FUEL"] spawn ITW_CLASH_HALLogistics_fnc_Evaluate};
        _result
    };
    HAL_SuppRep = {
        private _hq = _this param [0,grpNull];
        private _result = _this call ITW_CLASH_HALLogistics_fnc_NativeSuppRep;
        if (!isNull _hq) then {[_hq,"REPAIR"] spawn ITW_CLASH_HALLogistics_fnc_Evaluate};
        _result
    };

    ITW_CLASH_HALLogisticsReady = true;
    diag_log format [
        "CLASH BOOT | hal-logistics-ready | version=%1 nativeDemand=true groundAmmo=true ammoHelo=true physicalAmmoPackage=true groundFuel=true groundRepair=true halRecipientAndRouteAuthority=true",
        ITW_CLASH_HALLogisticsVersion
    ];
};

true
