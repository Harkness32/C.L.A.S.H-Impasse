#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ThunderRunEnhancementsStarted",false]) exitWith {true};

private _coreLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_ThunderRun_Core.sqf";
if !(_coreLoaded isEqualTo true) exitWith {
    diag_log "CLASH BOOT | thunder-run-enhancements-core-failed";
    false
};
if !(missionNamespace getVariable ["ITW_CLASH_ThunderRunReady",false]) exitWith {
    diag_log "CLASH BOOT | thunder-run-enhancements-core-not-ready";
    false
};

ITW_CLASH_ThunderRunEnhancementsStarted = true;
ITW_CLASH_ThunderRunEnhancementsReady = false;
ITW_CLASH_ThunderRunVersion = 4;

/*
    Enhancement layer over the proven Thunder Run core.

    - Exact reserved package is visibly slingloaded for transit.
    - At TAKEOVER the same object is detached/staged for RYD_AmmoDrop.
    - Dry AI vehicles in RydHQ_Hollow can use the same air-ammo doctrine.
    - Crew sensors stay live; Busy remains the HAL retask lock.
    - Live-burn speed/flare/RTB/ACE tuning loads after this layer is ready.
*/

ITW_CLASH_ThunderRun_fnc_ApplyStagingCore = ITW_CLASH_ThunderRun_fnc_ApplyStaging;
ITW_CLASH_ThunderRun_fnc_SetPhaseCore = ITW_CLASH_ThunderRun_fnc_SetPhase;
ITW_CLASH_ThunderRun_fnc_DisposeCore = ITW_CLASH_ThunderRun_fnc_Dispose;
ITW_CLASH_ThunderRun_fnc_ClassifyCore = ITW_CLASH_ThunderRun_fnc_Classify;

ITW_CLASH_ThunderRun_fnc_BoxKey = {
    params ["_box"];
    if (isNull _box) exitWith {""};
    private _key = netId _box;
    if (_key isEqualTo "") then {_key = str _box};
    _key
};

ITW_CLASH_ThunderRun_fnc_RegisterStagedBox = {
    params ["_state"];
    private _box = _state getOrDefault ["box",objNull];
    if (isNull _box) exitWith {false};

    private _boxKey = [_box] call ITW_CLASH_ThunderRun_fnc_BoxKey;
    if (_boxKey isEqualTo "") exitWith {false};

    _state set ["stagedBoxKey",_boxKey];
    ITW_CLASH_ThunderRunStagedBoxes set [_boxKey,_state];
    _box setVariable ["ITW_CLASH_ThunderRunStaged",true];
    _box setVariable [
        "ITW_CLASH_ThunderRunOwner",
        _state getOrDefault ["poolId",""]
    ];
    _box setVariable ["ITW_CLASH_ThunderRunRecovery",[
        _state getOrDefault ["hq",grpNull],
        _state getOrDefault ["target",objNull],
        _state getOrDefault ["context",createHashMap],
        +(_state getOrDefault ["boxOrigin",[]])
    ]];
    true
};

ITW_CLASH_ThunderRun_fnc_ClearSlingMetadata = {
    params ["_veh","_box"];
    if (!isNull _veh) then {
        if ((_veh getVariable ["ITW_CLASH_PreloadedAmmoBox",objNull]) isEqualTo _box) then {
            _veh setVariable ["ITW_CLASH_PreloadedAmmoBox",nil,true]
        };
    };
    if (!isNull _box) then {
        if ((_box getVariable ["ITW_CLASH_PreloadedSlingCarrier",objNull]) isEqualTo _veh) then {
            _box setVariable ["ITW_CLASH_PreloadedSlingCarrier",nil,true]
        };
    };
    true
};

ITW_CLASH_ThunderRun_fnc_ApplyStaging = {
    params ["_state"];
    if (_state getOrDefault ["stagingApplied",false]) exitWith {true};

    private _veh = _state getOrDefault ["vehicle",objNull];
    private _target = _state getOrDefault ["target",objNull];
    private _box = _state getOrDefault ["box",objNull];
    private _hq = _state getOrDefault ["hq",grpNull];
    private _group = _state getOrDefault ["group",grpNull];
    if (
        isNull _veh || {isNull _target} || {isNull _box}
        || {isNull _hq} || {isNull _group}
    ) exitWith {false};

    private _points = +(_hq getVariable ["RydHQ_AmmoPoints",[]]);
    _points pushBackUnique _target;
    _hq setVariable ["RydHQ_AmmoPoints",_points];

    _group setVariable ["Deployed" + str _group,false];
    _group setVariable ["Busy" + str _group,true];
    _group setVariable ["ITW_CLASH_ThunderRunActive",true];
    _veh setVariable ["ITW_CLASH_ThunderRunActive",true,true];
    // Busy prevents retasking; leave TARGET/AUTOTARGET enabled so this crew
    // remains part of HAL's emerging battlefield picture.
    [_group] call RYD_WPdel;

    private _targetGroup = [_target] call ITW_CLASH_ThunderRun_fnc_TargetGroup;
    if (!isNull _targetGroup) then {
        _targetGroup setVariable ["ForBoxing",_target]
    };

    _box hideObjectGlobal false;
    _box enableSimulationGlobal true;
    _box allowDamage true;

    if !([_hq,_veh,_box] call ITW_CLASH_HALLogistics_fnc_PrimeExactAmmoSling) exitWith {
        ["visible-sling-failed",[
            _state getOrDefault ["poolId","?"],typeOf _veh,typeOf _box,
            _veh distance2D _box
        ]] call ITW_CLASH_ThunderRun_fnc_Log;
        false
    };

    if (
        _box getVariable ["ITW_CLASH_LogisticsPackage",false]
        && {!isNil "ITW_CLASH_PlayerTasks_fnc_SetPackageState"}
    ) then {
        [_box,"RESERVED","thunder-run-visible-sling-transit"] call
            ITW_CLASH_PlayerTasks_fnc_SetPackageState;
    };

    _state set ["slingTransit",true];
    _state set ["packageTransitioned",false];
    _state set ["stagingApplied",true];

    ["package-sling-departure",[
        _state getOrDefault ["poolId","?"],typeOf _veh,typeOf _box,
        [_box] call ITW_CLASH_ThunderRun_fnc_BoxKey,getPosATL _veh,getPosATL _box
    ]] call ITW_CLASH_ThunderRun_fnc_Log;
    diag_log format [
        "THUNDER RUN SLING LOADED | pool=%1 | vehicle=%2 | box=%3 | boxId=%4",
        _state getOrDefault ["poolId","?"],typeOf _veh,typeOf _box,
        [_box] call ITW_CLASH_ThunderRun_fnc_BoxKey
    ];
    true
};

ITW_CLASH_ThunderRun_fnc_TransitionPackage = {
    params ["_state"];
    if (_state getOrDefault ["packageTransitioned",false]) exitWith {true};
    if !(_state getOrDefault ["slingTransit",false]) exitWith {true};

    private _veh = _state getOrDefault ["vehicle",objNull];
    private _box = _state getOrDefault ["box",objNull];
    if (isNull _veh || {isNull _box} || {!alive _box}) exitWith {false};

    private _detachPos = getPosATL _veh;
    private _detachAlt = _detachPos#2;
    _box allowDamage false;

    if ((getSlingLoad _veh) isEqualTo _box) then {
        _veh setSlingLoad objNull;
        private _deadline = diag_tickTime + 3;
        waitUntil {
            sleep 0.05;
            isNull getSlingLoad _veh || {diag_tickTime >= _deadline}
        };
    };

    // Same exact object: visible sling -> hidden tactical staging -> native chute.
    _box hideObjectGlobal true;
    _box enableSimulationGlobal false;
    _box setPos [0,0,2000];
    _box allowDamage true;

    [_veh,_box] call ITW_CLASH_ThunderRun_fnc_ClearSlingMetadata;
    [_state] call ITW_CLASH_ThunderRun_fnc_RegisterStagedBox;

    if (
        _box getVariable ["ITW_CLASH_LogisticsPackage",false]
        && {!isNil "ITW_CLASH_PlayerTasks_fnc_SetPackageState"}
    ) then {
        [_box,"RESERVED","thunder-run-package-transition"] call
            ITW_CLASH_PlayerTasks_fnc_SetPackageState;
    };

    _state set ["slingTransit",false];
    _state set ["packageTransitioned",true];

    ["package-transition",[
        _state getOrDefault ["poolId","?"],typeOf _veh,typeOf _box,
        [_box] call ITW_CLASH_ThunderRun_fnc_BoxKey,_detachPos,_detachAlt,
        getSlingLoad _veh
    ]] call ITW_CLASH_ThunderRun_fnc_Log;
    diag_log format [
        "THUNDER RUN PACKAGE TRANSITION | pool=%1 | box=%2 | boxId=%3 | pos=%4 | alt=%5",
        _state getOrDefault ["poolId","?"],typeOf _box,
        [_box] call ITW_CLASH_ThunderRun_fnc_BoxKey,_detachPos,_detachAlt
    ];
    true
};

ITW_CLASH_ThunderRun_fnc_SetPhase = {
    params ["_state","_phase"];
    private _result = [_state,_phase] call ITW_CLASH_ThunderRun_fnc_SetPhaseCore;
    if (_phase == "TAKEOVER" && {
        _state getOrDefault ["slingTransit",false]
    }) then {
        private _transitioned = [_state] call
            ITW_CLASH_ThunderRun_fnc_TransitionPackage;
        if (!_transitioned) then {
            _state set ["packageTransitionFailed",true];
            ["package-transition-failed",[
                _state getOrDefault ["poolId","?"],
                _state getOrDefault ["phase","?"],
                _state getOrDefault ["vehicle",objNull],
                _state getOrDefault ["box",objNull]
            ]] call ITW_CLASH_ThunderRun_fnc_Log;
        };
    };
    _result
};

ITW_CLASH_ThunderRun_fnc_Dispose = {
    params ["_state","_outcome"];
    if !(_state getOrDefault ["released",false]) then {
        private _veh = _state getOrDefault ["vehicle",objNull];
        private _box = _state getOrDefault ["box",objNull];
        if (!isNull _veh && {!isNull _box}) then {
            if ((getSlingLoad _veh) isEqualTo _box) then {
                _box allowDamage false;
                _veh setSlingLoad objNull;
                [_veh,_box] call ITW_CLASH_ThunderRun_fnc_ClearSlingMetadata;
                _box allowDamage true;
            };
        };
    };
    [_state,_outcome] call ITW_CLASH_ThunderRun_fnc_DisposeCore
};

// Preserve a preclassified vehicle-bridge CONTESTED/HOT decision for the few
// seconds between claim and the common HAL_GoAmmoSupp wrapper. AIR_DENIED wins.
ITW_CLASH_ThunderRun_fnc_Classify = {
    params ["_veh","_target","_hq"];
    private _result = [_veh,_target,_hq] call ITW_CLASH_ThunderRun_fnc_ClassifyCore;
    if (isNull _target) exitWith {_result};

    private _locked = _target getVariable [
        "ITW_CLASH_ThunderRunVehicleBridgeDecision",[]
    ];
    if (_locked isEqualType [] && {count _locked >= 3}) then {
        _locked params ["_lockedState","_lockedReason","_expires"];
        if (time <= _expires && {
            _lockedState in ["CONTESTED","HOT"]
        } && {
            (_result getOrDefault ["state","NORMAL"]) in ["NORMAL","SAFE"]
        }) then {
            _result set ["state",_lockedState];
            _result set ["reason",_lockedReason + "-commit-window"];
        };
    };
    _result
};

ITW_CLASH_ThunderRun_fnc_VehicleAmmoTargets = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};

    private _blocked = (
        +(_hq getVariable ["RydHQ_ASupportedG",[]])
        + (_hq getVariable ["RydHQ_Boxed",[]])
    );
    private _result = [];
    {
        private _target = _x;
        if (
            isNull _target
            || {_target isKindOf "Man"}
            || {!alive _target}
            || {!canMove _target}
            || {someAmmo _target}
        ) then {continue};

        private _targetGroup = [_target] call ITW_CLASH_ThunderRun_fnc_TargetGroup;
        if (isNull _targetGroup || {_targetGroup in _blocked}) then {continue};
        if ((units _targetGroup findIf {isPlayer _x}) >= 0) then {continue};
        _result pushBackUnique _target;
    } forEach (_hq getVariable ["RydHQ_Hollow",[]]);
    _result
};

ITW_CLASH_ThunderRun_fnc_VehicleAmmoProviders = {
    params ["_hq"];
    if (isNull _hq || {isNil "ITW_CLASH_HALLogistics_fnc_ProviderVehicle"}) exitWith {[]};

    private _result = [];
    {
        private _group = _x;
        if (
            isNull _group
            || {{alive _x} count units _group <= 0}
            || {_group getVariable ["Busy" + str _group,false]}
            || {_group getVariable ["Unable",false]}
            || {(units _group findIf {isPlayer _x}) >= 0}
        ) then {continue};

        private _veh = [_group] call
            ITW_CLASH_HALLogistics_fnc_ProviderVehicle;
        if (
            isNull _veh
            || {!alive _veh}
            || {!canMove _veh}
            || {fuel _veh <= 0.2}
            || {!(_veh isKindOf "Helicopter")}
            || {!isNull getSlingLoad _veh}
            || {_veh getVariable ["ITW_CLASH_ThunderRunActive",false]}
        ) then {continue};
        _result pushBackUnique [_group,_veh];
    } forEach (_hq getVariable ["RydHQ_AmmoDrop",[]]);
    _result
};

ITW_CLASH_ThunderRun_fnc_TryVehicleAmmoDispatch = {
    params ["_hq"];
    if (
        isNull _hq
        || {!isNil "ITW_GameOver" && {ITW_GameOver}}
        || {isNil "HAL_GoAmmoSupp"}
    ) exitWith {false};

    private _targets = [_hq] call ITW_CLASH_ThunderRun_fnc_VehicleAmmoTargets;
    if (_targets isEqualTo []) exitWith {false};
    private _providers = [_hq] call ITW_CLASH_ThunderRun_fnc_VehicleAmmoProviders;
    if (_providers isEqualTo []) exitWith {false};

    private _boxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
    _boxes = _boxes select {!isNull _x && {alive _x}};
    if (_boxes isEqualTo []) exitWith {false};

    private _dispatched = false;
    private _radius = 500;
    for [{},{_radius <= 44000 && {!_dispatched}},{_radius = _radius + 500}] do {
        {
            _x params ["_providerGroup","_provider"];
            if (_dispatched) exitWith {};
            {
                private _target = _x;
                if (_provider distance2D _target > _radius) then {continue};

                private _targetGroup = [_target] call
                    ITW_CLASH_ThunderRun_fnc_TargetGroup;
                if (isNull _targetGroup) then {continue};
                private _blocked = (
                    +(_hq getVariable ["RydHQ_ASupportedG",[]])
                    + (_hq getVariable ["RydHQ_Boxed",[]])
                );
                if (_targetGroup in _blocked) then {continue};

                private _boxIndex = _boxes findIf {
                    !isNull _x && {alive _x} && {_provider canSlingLoad _x}
                };
                if (_boxIndex < 0) then {continue};
                private _box = _boxes#_boxIndex;

                if !([_provider,_target,_box,_hq,false] call
                    ITW_CLASH_ThunderRun_fnc_IsEligible) then {continue};

                private _classification = [_provider,_target,_hq] call
                    ITW_CLASH_ThunderRun_fnc_Classify;
                private _state = _classification getOrDefault ["state","NORMAL"];
                if !(_state in ["CONTESTED","HOT"]) then {continue};

                private _supported = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
                _supported pushBackUnique _targetGroup;
                _hq setVariable ["RydHQ_ASupportedG",_supported];

                private _pool = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
                _hq setVariable ["RydHQ_AmmoBoxes",_pool - [_box]];

                _target setVariable [
                    "ITW_CLASH_ThunderRunVehicleBridgeDecision",
                    [_state,_classification getOrDefault ["reason","vehicle-ammo"],time + 5]
                ];

                ["vehicle-ammo-bridge-dispatch",[
                    _hq getVariable ["RydHQ_CodeSign","?"],
                    typeOf _target,typeOf _provider,typeOf _box,
                    [_box] call ITW_CLASH_ThunderRun_fnc_BoxKey,
                    _provider distance2D _target,_state,
                    _classification getOrDefault ["reason","unknown"]
                ]] call ITW_CLASH_ThunderRun_fnc_Log;

                [[
                    _provider,_target,[],[],true,_box,_hq,false,
                    ["CLASH_VEHICLE_AMMO_AIR",true,true]
                ],HAL_GoAmmoSupp] call RYD_Spawn;
                _dispatched = true;
            } forEach _targets;
        } forEach _providers;
    };
    _dispatched
};

[] spawn {
    scriptName "ITW_CLASH_ThunderRunVehicleAmmoBridge";
    waitUntil {
        sleep 1;
        missionNamespace getVariable ["ITW_CLASH_ThunderRunReady",false]
        && {missionNamespace getVariable ["ITW_CLASH_HALLogisticsReady",false]}
        && {!isNil "ITW_CLASH_fnc_GetCommanderForSide"}
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        private _sides = [];
        if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
        if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
        {
            private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
            if (!isNull _hq) then {
                [_hq] call ITW_CLASH_ThunderRun_fnc_TryVehicleAmmoDispatch;
            };
        } forEach _sides;
        sleep 3;
    };
};

ITW_CLASH_ThunderRunEnhancementsReady = true;

private _tuningLoaded = false;
if (fileExists "ITW_CLASH_ThunderRun_Tuning.sqf") then {
    _tuningLoaded = call compile preprocessFileLineNumbers
        "ITW_CLASH_ThunderRun_Tuning.sqf";
};

diag_log format [
    "CLASH BOOT | thunder-run-enhancements-ready | version=%1 visibleSlingTransit=true exactBoxIdentity=true takeoverPackageTransition=true vehicleAmmoThunderRun=true vehicleDemandSource=RydHQ_Hollow halThreatAuthority=true sensorAwareCrew=true liveBurnTuning=%2",
    ITW_CLASH_ThunderRunVersion,_tuningLoaded
];

true
