#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_VehicleEchelonPolicyStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_VehicleEchelonPolicyReady",false]
};

ITW_CLASH_VehicleEchelonPolicyStarted = true;
ITW_CLASH_VehicleEchelonPolicyReady = false;
ITW_CLASH_VehicleEchelonPolicyVersion = 2;

ITW_CLASH_VehicleEchelon_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["vehicle-echelon-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH VEHICLE ECHELON | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_VehicleEchelon_fnc_IsArmoredCombatGroup = {
    params ["_group"];
    if (isNull _group || {((units _group) findIf {isPlayer _x}) >= 0}) exitWith {
        [false,objNull]
    };

    private _vehicle = vehicle leader _group;
    if (isNull _vehicle || {_vehicle == leader _group} || {!alive _vehicle}) exitWith {
        [false,objNull]
    };

    private _vehDef = _vehicle getVariable ["ITW_VehDef",[]];
    private _vehType = if (
        _vehDef isEqualType [] && {count _vehDef > ITW_VEH_TYPE}
    ) then {
        _vehDef#ITW_VEH_TYPE
    } else {
        -1
    };

    private _armored = _vehType in [
        ITW_TYPE_VEH_TANK,
        ITW_TYPE_VEH_APC
    ];
    if (!_armored) then {
        _armored = _vehicle isKindOf "Tank";
    };
    if (!_armored) then {
        private _subcategory = toLowerANSI getText (
            configFile >> "CfgVehicles" >> typeOf _vehicle >> "editorSubcategory"
        );
        _armored = "apc" in _subcategory || {"ifv" in _subcategory};
    };

    [_armored,_vehicle]
};

ITW_CLASH_VehicleEchelon_fnc_Objective = {
    params ["_group","_vehicle"];
    private _objective = _group getVariable [
        "ITW_CLASH_DualHALObjectiveAffinity",
        _group getVariable [
            "ITW_CLASH_AssignedObjective",
            VAR_GET_OBJ_IDX(_group)
        ]
    ];

    private _active = if (!isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds") then {
        call ITW_CLASH_Generation_fnc_ActiveObjectiveIds
    } else {
        []
    };
    if (_objective in _active) exitWith {_objective};
    if (_active isEqualTo []) exitWith {_objective};

    private _reference = if (isNull _vehicle) then {
        getPosATL leader _group
    } else {
        getPosATL _vehicle
    };
    private _best = _active#0;
    private _bestDistance = _reference distance2D (
        ITW_Objectives#_best#ITW_OBJ_POS
    );
    {
        private _distance = _reference distance2D (
            ITW_Objectives#_x#ITW_OBJ_POS
        );
        if (_distance < _bestDistance) then {
            _best = _x;
            _bestDistance = _distance;
        };
    } forEach _active;
    _best
};

ITW_CLASH_VehicleEchelon_fnc_PrepareRecovery = {
    params ["_group"];
    private _classification = [
        _group
    ] call ITW_CLASH_VehicleEchelon_fnc_IsArmoredCombatGroup;
    _classification params ["_armored","_vehicle"];
    if (!_armored) exitWith {false};
    if (isNil "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn") exitWith {
        false
    };

    private _objective = [
        _group,_vehicle
    ] call ITW_CLASH_VehicleEchelon_fnc_Objective;
    private _forward = [
        _objective,side _group
    ] call ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn;
    if (_forward isEqualTo []) exitWith {
        ["recovery-node-unresolved",[
            groupId _group,typeOf _vehicle,side _group,_objective
        ]] call ITW_CLASH_VehicleEchelon_fnc_Log;
        false
    };

    _forward params ["_position","_resolvedObjective","_source","_baseIndex"];
    private _restDecoy = _group getVariable [
        "ITW_CLASH_GTFO_GroupRestDecoy",objNull
    ];
    if (isNull _restDecoy) then {
        _restDecoy = createVehicle [
            "Land_HelipadEmpty_F",_position,[],0,"CAN_COLLIDE"
        ];
        _restDecoy hideObjectGlobal true;
        _restDecoy enableSimulationGlobal false;
        _restDecoy allowDamage false;
        _group setVariable [
            "ITW_CLASH_GTFO_GroupRestDecoy",_restDecoy
        ];
    } else {
        _restDecoy setPosATL _position;
    };

    _group setVariable ["ITW_CLASH_VehicleRecoveryRallyOwned",true];
    _group setVariable [
        "ITW_CLASH_VehicleRecoveryForwardBase",_baseIndex
    ];
    _group setVariable [
        "ITW_CLASH_VehicleRecoveryObjective",_resolvedObjective
    ];

    ["recovery-rally",[
        groupId _group,
        typeOf _vehicle,
        side _group,
        _resolvedObjective,
        _baseIndex,
        _source,
        _position
    ]] call ITW_CLASH_VehicleEchelon_fnc_Log;
    true
};

ITW_CLASH_VehicleEchelon_fnc_CleanupRecovery = {
    params ["_group"];
    if (isNull _group || {
        !(_group getVariable ["ITW_CLASH_VehicleRecoveryRallyOwned",false])
    }) exitWith {false};

    private _restDecoy = _group getVariable [
        "ITW_CLASH_GTFO_GroupRestDecoy",objNull
    ];
    if (!isNull _restDecoy) then {deleteVehicle _restDecoy};

    _group setVariable ["ITW_CLASH_GTFO_GroupRestDecoy",nil];
    _group setVariable ["ITW_CLASH_VehicleRecoveryRallyOwned",nil];
    _group setVariable ["ITW_CLASH_VehicleRecoveryForwardBase",nil];
    _group setVariable ["ITW_CLASH_VehicleRecoveryObjective",nil];
    true
};

[] spawn {
    scriptName "ITW_CLASH_VehicleEchelonPolicyBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            !isNil "HAL_GoRest"
            && {
                missionNamespace getVariable [
                    "ITW_CLASH_ForceGenerationReady",false
                ]
            }
            && {!isNil "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | vehicle-echelon-policy-bind-timeout | native HAL recovery unchanged";
    };

    ITW_CLASH_VehicleEchelon_fnc_NativeGoRest = HAL_GoRest;
    HAL_GoRest = {
        private _group = _this param [0,grpNull];
        private _ownsRally = false;
        if (!isNull _group && {
            !(_group getVariable ["ITW_CLASH_GTFO",false])
        }) then {
            _ownsRally = [
                _group
            ] call ITW_CLASH_VehicleEchelon_fnc_PrepareRecovery;
        };

        private _result = _this call ITW_CLASH_VehicleEchelon_fnc_NativeGoRest;

        if (_ownsRally && {!isNull _group}) then {
            [_group] call ITW_CLASH_VehicleEchelon_fnc_CleanupRecovery;
        };
        if (isNil "_result") exitWith {};
        _result
    };

    ITW_CLASH_VehicleEchelonPolicyReady = true;
    diag_log format [
        "CLASH BOOT | vehicle-echelon-policy-ready | version=%1 armorSpawn=rear lightSpawn=forward artillerySpawn=interstitial armorRecovery=forward nativeGoRest=true bothSides=true",
        ITW_CLASH_VehicleEchelonPolicyVersion
    ];
};

true
