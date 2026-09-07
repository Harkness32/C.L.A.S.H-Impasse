#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALLogisticsStarted",false]) exitWith {true};
ITW_CLASH_HALLogisticsStarted = true;
ITW_CLASH_HALLogisticsVersion = 10;
ITW_CLASH_HALLogisticsReady = false;

// NR6 HAL ships explicit ACE logistics workarounds but leaves them disabled by
// default. Enable them only when ACE itself is present. This preserves native
// HAL/vanilla support behavior on non-ACE missions while making ACE-managed
// repair/rearm/refuel complete when the support vehicle reaches its recipient.
// Keep MagicHeal off even under ACE: C.L.A.S.H. owns casualty extraction and
// reconstitution, and automatic healing would erase medical demand.
ITW_CLASH_ACEActive = isClass (configFile >> "CfgPatches" >> "ace_main");
missionNamespace setVariable ["ITW_CLASH_ACEActive",ITW_CLASH_ACEActive,true];
missionNamespace setVariable ["RydxHQ_MagicRepair",ITW_CLASH_ACEActive,true];
missionNamespace setVariable ["RydxHQ_MagicRearm",ITW_CLASH_ACEActive,true];
missionNamespace setVariable ["RydxHQ_MagicRefuel",ITW_CLASH_ACEActive,true];
missionNamespace setVariable ["RydxHQ_MagicHeal",false,true];
diag_log format [
    "CLASH BOOT | ace-logistics-workaround | ace=%1 repair=%1 rearm=%1 refuel=%1 heal=false",
    ITW_CLASH_ACEActive
];
ITW_CLASH_LogisticsBootstrapInterval = missionNamespace getVariable [
    "ITW_CLASH_LogisticsBootstrapInterval",25
];

ITW_CLASH_HALLogistics_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-logistics-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL LOGISTICS | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_HALLogistics_fnc_ProviderVehicle = {
    params ["_subject"];

    // HAL normally discovers support providers through assignedVehicle. Impasse
    // physically seats generated crews with moveInAny, and players may manually
    // enter a valid provider, so assignedVehicle can be null/stale while the
    // actual service platform is occupied. Preserve native HAL semantics for
    // ordinary AI and promote the physical vehicle only for humans or explicit
    // C.L.A.S.H. service / Checkbook groups.
    private _group = grpNull;
    private _unit = objNull;
    if (typeName _subject == "GROUP") then {
        _group = _subject;
        if (!isNull _group) then {_unit = leader _group};
    } else {
        if (typeName _subject == "OBJECT") then {
            _unit = _subject;
            if (!isNull _unit) then {_group = group _unit};
        };
    };
    if (isNull _unit) exitWith {objNull};

    private _assigned = assignedVehicle _unit;
    private _physical = vehicle _unit;
    private _veh = _assigned;
    private _human = !isNull _group && {
        (units _group findIf {isPlayer _x}) >= 0
    };
    private _clashOwned = !isNull _group && {
        _group getVariable ["ITW_CLASH_ServiceAsset",false]
        || {_group getVariable ["ITW_CLASH_CheckbookAsset",false]}
    };

    if ((_human || {_clashOwned}) && {
        _physical != _unit
    } && {
        isNull _assigned || {_assigned != _physical}
    }) then {
        _veh = _physical;
        if (!isNull _group) then {
            private _nextLog = _group getVariable [
                "ITW_CLASH_LogisticsProviderFallbackLogAt",0
            ];
            if (time >= _nextLog) then {
                _group setVariable [
                    "ITW_CLASH_LogisticsProviderFallbackLogAt",time + 30
                ];
                ["provider-physical-vehicle-fallback",[
                    if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                        [_group] call ITW_CLASH_DualHAL_fnc_GroupId
                    } else {
                        groupId _group
                    },
                    typeOf _physical,
                    if (isNull _assigned) then {"<none>"} else {typeOf _assigned},
                    _clashOwned,_human
                ]] call ITW_CLASH_HALLogistics_fnc_Log;
            };
        };
    };
    _veh
};

ITW_CLASH_HALLogistics_fnc_UsableGroups = {
    params ["_groups"];
    _groups select {
        private _group = _x;
        if (isNull _group || {{alive _x} count units _group <= 0}) then {
            false
        } else {
            private _veh = [_group] call
                ITW_CLASH_HALLogistics_fnc_ProviderVehicle;
            !isNull _veh
            && {alive _veh}
            && {canMove _veh}
            && {fuel _veh > 0.2}
            && {!(_group getVariable ["Busy" + str _group,false])}
            && {!(_group getVariable ["Unable",false])}
        }
    }
};

ITW_CLASH_HALLogistics_fnc_PrimeAmmoSling = {
    params ["_hq",["_preferred",objNull]];
    if (isNull _hq) exitWith {false};

    private _boxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
    _boxes = _boxes select {
        !isNull _x
        && {alive _x}
        && {isNull (_x getVariable ["ITW_CLASH_PreloadedSlingCarrier",objNull])}
    };
    if (_boxes isEqualTo []) exitWith {false};

    private _groups = +(_hq getVariable ["RydHQ_AmmoDrop",[]]);
    private _vehicles = [];
    {
        private _veh = [_x] call ITW_CLASH_HALLogistics_fnc_ProviderVehicle;
        if (
            !isNull _veh
            && {_veh isKindOf "Helicopter"}
            && {alive _veh}
            && {canMove _veh}
            && {isNull getSlingLoad _veh}
            && {!(_x getVariable ["Busy" + str _x,false])}
            && {!(_x getVariable ["Unable",false])}
        ) then {
            _vehicles pushBackUnique _veh;
        };
    } forEach _groups;

    if (!isNull _preferred && {
        _preferred isKindOf "Helicopter"
        && {alive _preferred}
        && {canMove _preferred}
        && {isNull getSlingLoad _preferred}
    }) then {
        _vehicles = [_preferred] + (_vehicles - [_preferred]);
    };
    if (_vehicles isEqualTo []) exitWith {false};

    private _paired = false;
    {
        private _veh = _x;
        private _boxIndex = _boxes findIf {_veh canSlingLoad _x};
        if (_boxIndex < 0) then {continue};
        private _box = _boxes#_boxIndex;

        if (_veh setSlingLoad _box) then {
            _veh setVariable ["ITW_CLASH_PreloadedAmmoBox",_box,true];
            _box setVariable ["ITW_CLASH_PreloadedSlingCarrier",_veh,true];
            _box setVariable ["ITW_CLASH_LogisticsPackageState","RESERVED",true];
            _box setVariable ["ITW_CLASH_LogisticsPackageReason","preloaded-ai-sling",true];
            ["ammo-sling-preloaded",[
                _hq getVariable ["RydHQ_CodeSign","?"],
                typeOf _veh,typeOf _box,getPosATL _veh
            ]] call ITW_CLASH_HALLogistics_fnc_Log;
            _paired = true;
            break;
        };
    } forEach _vehicles;
    _paired
};

ITW_CLASH_HALLogistics_fnc_PrimeExactAmmoSling = {
    params ["_hq","_veh","_box"];
    if (isNull _hq || {isNull _veh} || {isNull _box}) exitWith {false};
    if !(_veh isKindOf "Helicopter") exitWith {false};
    if (!alive _veh || {!canMove _veh} || {!alive _box}) exitWith {false};

    private _current = getSlingLoad _veh;
    if (!isNull _current) exitWith {_current isEqualTo _box};
    if !(_veh canSlingLoad _box) exitWith {
        ["ammo-exact-sling-unavailable",[
            _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,typeOf _box
        ]] call ITW_CLASH_HALLogistics_fnc_Log;
        false
    };

    if !(_veh setSlingLoad _box) exitWith {
        ["ammo-exact-sling-failed",[
            _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,typeOf _box
        ]] call ITW_CLASH_HALLogistics_fnc_Log;
        false
    };

    _veh setVariable ["ITW_CLASH_PreloadedAmmoBox",_box,true];
    _box setVariable ["ITW_CLASH_PreloadedSlingCarrier",_veh,true];
    _box setVariable ["ITW_CLASH_LogisticsPackageState","RESERVED",true];
    _box setVariable ["ITW_CLASH_LogisticsPackageReason","exact-dispatch-ai-sling",true];
    ["ammo-exact-sling-preloaded",[
        _hq getVariable ["RydHQ_CodeSign","?"],
        typeOf _veh,typeOf _box,getPosATL _veh
    ]] call ITW_CLASH_HALLogistics_fnc_Log;
    true
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

    if ((_reply getOrDefault ["status",""]) == "APPROVED") then {
        private _kind = switch (toUpperANSI _capability) do {
            case "LOGISTICS_AMMO";
            case "LOGISTICS_PACKAGE_AMMO": {"AMMO"};
            case "LOGISTICS_FUEL": {"FUEL"};
            case "LOGISTICS_REPAIR": {"REPAIR"};
            default {""};
        };
        if (_kind isNotEqualTo "") then {
            [_hq,_kind,format [
                "%1/%2",_capability,_reply getOrDefault ["reason","provided"]
            ]] call ITW_CLASH_HALLogistics_fnc_KickNative;
        };
    };
    _reply
};

ITW_CLASH_HALLogistics_fnc_KickNative = {
    params ["_hq","_kind",["_reason","capability-provided"]];
    if (isNull _hq) exitWith {false};
    _kind = toUpperANSI _kind;
    if !(_kind in ["AMMO","FUEL","REPAIR"]) exitWith {false};

    private _pendingKey = "ITW_CLASH_LogisticsNativeRecheckPending_" + _kind;
    if (_hq getVariable [_pendingKey,false]) exitWith {false};
    _hq setVariable [_pendingKey,true];

    [_hq,_kind,_reason,_pendingKey] spawn {
        params ["_hq","_kind","_reason","_pendingKey"];
        sleep 0.25;
        if (isNull _hq) exitWith {};

        ["native-recheck",[
            _hq getVariable ["RydHQ_CodeSign","?"],
            _kind,_reason,
            count (_hq getVariable ["RydHQ_Hollow",[]]),
            count (_hq getVariable ["RydHQ_Dried",[]]),
            count (_hq getVariable ["RydHQ_damaged",[]])
        ]] call ITW_CLASH_HALLogistics_fnc_Log;

        switch (_kind) do {
            case "AMMO": {[_hq] call HAL_SuppAmmo};
            case "FUEL": {[_hq] call HAL_SuppFuel};
            case "REPAIR": {[_hq] call HAL_SuppRep};
        };
        if (!isNull _hq) then {
            _hq setVariable [_pendingKey,false];
        };
    };
    true
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

            // Busy/committed support is unavailable for a second task, but it
            // is not missing inventory. Provision only while at least one HAL
            // ammo demand remains outside ASupportedG/Boxed.
            private _blocked = (
                +(_hq getVariable ["RydHQ_ASupportedG",[]])
                + (_hq getVariable ["RydHQ_Boxed",[]])
            );
            private _openDemandCount = 0;
            {
                private _targetGroup = if (_x isKindOf "Man") then {
                    group _x
                } else {
                    private _commander = effectiveCommander _x;
                    if (isNull _commander) then {grpNull} else {group _commander}
                };
                if (
                    isNull _targetGroup
                    || {!(_targetGroup in _blocked)}
                ) then {
                    _openDemandCount = _openDemandCount + 1
                };
            } forEach _demand;

            if (_openDemandCount <= 0) exitWith {true};

            if (_groundAmmo isEqualTo []) then {
                [_hq,"LOGISTICS_AMMO","GROUND"] call
                    ITW_CLASH_HALLogistics_fnc_Request;
            };

            // Build a package only for an actually open demand. The box is a
            // reservation, not a conserved stock item, but speculative package
            // purchases while all recipients are already committed are waste.
            if (_ammoBoxes isEqualTo []) then {
                [_hq,"LOGISTICS_PACKAGE_AMMO","AIR"] call
                    ITW_CLASH_HALLogistics_fnc_Request;
                _ammoBoxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
                _ammoBoxes = _ammoBoxes select {!isNull _x && {alive _x}};
            };

            // Provision air capacity here, but do not physically bind a box to
            // an aircraft yet. Exact pre-sling happens only after HAL selects the
            // provider, target and exact reserved box.
            private _availableAir = count _airAmmo;
            private _committedSoon = if (
                missionNamespace getVariable ["ITW_CLASH_ThunderRunReady",false]
                && {!isNil "ITW_CLASH_ThunderRun_fnc_CommittedCapacity"}
            ) then {
                [_hq,missionNamespace getVariable [
                    "ITW_CLASH_ThunderRunDemandPatience",420
                ]] call ITW_CLASH_ThunderRun_fnc_CommittedCapacity
            } else {
                0
            };
            private _effectiveAirCapacity = _availableAir + _committedSoon;

            if (_effectiveAirCapacity < _openDemandCount) then {
                [_hq,"LOGISTICS_AMMO","AIR"] call
                    ITW_CLASH_HALLogistics_fnc_Request;
            };
            ["ammo-air-capacity",[
                _hq getVariable ["RydHQ_CodeSign","?"],
                _openDemandCount,_availableAir,_committedSoon,
                _effectiveAirCapacity
            ]] call ITW_CLASH_HALLogistics_fnc_Log;
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
        private _result = true;
        private _nativeResult = _this call ITW_CLASH_HALLogistics_fnc_NativeSuppAmmo;
        if !(isNil "_nativeResult") then {_result = _nativeResult};
        if (!isNull _hq) then {[_hq,"AMMO"] spawn ITW_CLASH_HALLogistics_fnc_Evaluate};
        _result
    };
    HAL_SuppFuel = {
        private _hq = _this param [0,grpNull];
        private _result = true;
        private _nativeResult = _this call ITW_CLASH_HALLogistics_fnc_NativeSuppFuel;
        if !(isNil "_nativeResult") then {_result = _nativeResult};
        if (!isNull _hq) then {[_hq,"FUEL"] spawn ITW_CLASH_HALLogistics_fnc_Evaluate};
        _result
    };
    HAL_SuppRep = {
        private _hq = _this param [0,grpNull];
        private _result = true;
        private _nativeResult = _this call ITW_CLASH_HALLogistics_fnc_NativeSuppRep;
        if !(isNil "_nativeResult") then {_result = _nativeResult};
        if (!isNull _hq) then {[_hq,"REPAIR"] spawn ITW_CLASH_HALLogistics_fnc_Evaluate};
        _result
    };

    ITW_CLASH_HALLogisticsReady = true;
    diag_log format [
        "CLASH BOOT | hal-logistics-ready | version=%1 nativeDemand=true groundAmmo=true ammoHelo=true physicalAmmoPackage=true preloadedAmmoSling=true groundFuel=true groundRepair=true halRecipientAndRouteAuthority=true nativeNilReturnSafe=true nativeEligibilityParity=true postProvisionRecheck=true zeroProviderBootstrap=true physicalServiceProviderFallback=true declaredCapabilityAdmission=true aceConditionalMagic=true aceMagicHeal=false",
        ITW_CLASH_HALLogisticsVersion
    ];
};

[] spawn {
    scriptName "ITW_CLASH_HALLogisticsZeroProviderBootstrap";
    waitUntil {
        sleep 1;
        missionNamespace getVariable ["ITW_CLASH_HALLogisticsReady",false]
        && {missionNamespace getVariable ["ITW_CLASH_HALReady",false]}
        && {!isNil "ITW_CLASH_fnc_GetCommanderForSide"}
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        private _sides = [];
        if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
        if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};

        {
            private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
            if (isNull _hq) then {continue};

            private _support = +(_hq getVariable ["RydHQ_Support",[]]);
            private _drops = +(_hq getVariable ["RydHQ_AmmoDrop",[]]);

            if (_support isEqualTo []) then {
                ["bootstrap-pulse",[
                    _hq getVariable ["RydHQ_CodeSign","?"],
                    "GROUND",count _support,count _drops
                ]] call ITW_CLASH_HALLogistics_fnc_Log;
                [_hq] call HAL_SuppFuel;
                [_hq] call HAL_SuppRep;
            };

            if ((_support + _drops) isEqualTo []) then {
                ["bootstrap-pulse",[
                    _hq getVariable ["RydHQ_CodeSign","?"],
                    "AMMO",count _support,count _drops
                ]] call ITW_CLASH_HALLogistics_fnc_Log;
                [_hq] call HAL_SuppAmmo;
            };
        } forEach _sides;

        sleep ITW_CLASH_LogisticsBootstrapInterval;
    };
};

// Shared lifecycle is loaded here because Checkbook API and ForceGeneration are
// already live, while HAL logistics is the first common service layer for both
// persistent Impasse transports and newly purchased support assets.
if (fileExists "ITW_CLASH_ServiceLifecycle.sqf") then {
    private _serviceLifecycleLoaded = call compile preprocessFileLineNumbers
        "ITW_CLASH_ServiceLifecycle.sqf";
    if !(_serviceLifecycleLoaded isEqualTo true) then {
        diag_log "CLASH BOOT | WARNING | service-lifecycle-load-failed | persistent support behavior retained";
    };
} else {
    diag_log "CLASH BOOT | WARNING | service-lifecycle-missing | persistent support behavior retained";
};

// Load after the service wrappers so the sea guard is the outermost staging
// boundary. Boats may be handed to HAL, but a successful handoff may never
// leave a Ship on a land/FOB fallback position.
if (fileExists "ITW_CLASH_SeaGenerationGuard.sqf") then {
    private _seaGuardLoaded = call compile preprocessFileLineNumbers
        "ITW_CLASH_SeaGenerationGuard.sqf";
    if !(_seaGuardLoaded isEqualTo true) then {
        diag_log "CLASH BOOT | WARNING | sea-generation-guard-load-failed | native sea staging retained";
    };
} else {
    diag_log "CLASH BOOT | WARNING | sea-generation-guard-missing | native sea staging retained";
};

// HAL SCargo owns physical transport execution. This observer restores the
// native Impasse boarding audio cues from HAL's real seat-assignment/embark
// state without issuing movement, waypoint, or GET IN/GET OUT commands.
if (fileExists "ITW_CLASH_HALTransportAudio.sqf") then {
    [] execVM "ITW_CLASH_HALTransportAudio.sqf";
} else {
    diag_log "CLASH BOOT | WARNING | hal-transport-audio-missing | HAL transport remains functional but boarding cues are unavailable";
};

// Native SCargo deliberately creates a terminal "Return To Base" task for the
// carrier after troop delivery, but its original arrival/task-success block is
// commented out. Keep the useful RTB guidance for player-flown aircraft and
// passively complete only that task once the player actually lands back home.
if (fileExists "ITW_CLASH_PlayerTransportRTB.sqf") then {
    [] execVM "ITW_CLASH_PlayerTransportRTB.sqf";
} else {
    diag_log "CLASH BOOT | WARNING | player-transport-rtb-missing | native HAL RTB task may remain assigned";
};

true
