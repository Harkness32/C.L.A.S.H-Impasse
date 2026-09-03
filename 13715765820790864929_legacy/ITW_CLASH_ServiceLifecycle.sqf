#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ServiceLifecycleStarted",false]) exitWith {true};
ITW_CLASH_ServiceLifecycleStarted = true;
ITW_CLASH_ServiceLifecycleVersion = 2;
ITW_CLASH_ServiceLifecycleReady = false;
ITW_CLASH_ServicePool = [];
ITW_CLASH_ServiceSerial = 0;
ITW_CLASH_ServiceRTBLandRadius = 125;
ITW_CLASH_ServiceRTBAirRadius = 350;
ITW_CLASH_ServiceIdleGrace = 25;
ITW_CLASH_ServiceRetirePlayerRadius = 600;
ITW_CLASH_ServiceReuseCooldown = 30;

ITW_CLASH_Service_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["service-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH SERVICE | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_Service_fnc_IsCapability = {
    params ["_capability"];
    (toUpperANSI _capability) in [
        "TRANSPORT","LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"
    ]
};

ITW_CLASH_Service_fnc_ModeForVehicle = {
    params ["_veh"];
    if (isNull _veh) exitWith {"GROUND"};
    if (_veh isKindOf "Ship") exitWith {"SEA"};
    if (_veh isKindOf "Air") exitWith {"AIR"};
    "GROUND"
};

ITW_CLASH_Service_fnc_FindEntry = {
    params ["_poolId"];
    if (_poolId isEqualTo "") exitWith {-1};
    ITW_CLASH_ServicePool findIf {(_x getOrDefault ["id",""]) isEqualTo _poolId}
};

ITW_CLASH_Service_fnc_MarkTrackerReleased = {
    params ["_veh"];
    if (isNull _veh || {isNil "ITW_CLASH_CheckbookAssets"}) exitWith {false};
    private _found = false;
    for "_i" from ((count ITW_CLASH_CheckbookAssets) - 1) to 0 step -1 do {
        private _entry = ITW_CLASH_CheckbookAssets#_i;
        if ((_entry#0) isEqualTo _veh) exitWith {
            _entry set [3,true];
            ITW_CLASH_CheckbookAssets set [_i,_entry];
            _found = true;
        };
    };
    _found
};

/* Storage boundary only. Live service assets remain HAL-owned through HAL RTB. */
ITW_CLASH_Service_fnc_RemoveHALOwnership = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {grpNull};
    if (!isNull _hq) then {
        {
            private _arr = +(_hq getVariable [_x,[]]);
            _hq setVariable [_x,_arr - [_group]];
        } forEach [
            "RydHQ_Friends","RydHQ_Included","RydHQ_AttackAv","RydHQ_FlankAv",
            "RydHQ_CombatAv","RydHQ_ReconAv","RydHQ_ReconG","RydHQ_CargoG",
            "RydHQ_CargoOnly","RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef",
            "RydHQ_AirG","RydHQ_DefRes","RydHQ_AmmoSupportG","RydHQ_AmmoDrop",
            "RydHQ_FuelSupportG","RydHQ_RepSupportG"
        ];
        private _support = +(_hq getVariable ["RydHQ_Support",[]]);
        _hq setVariable ["RydHQ_Support",_support - (units _group)];
    };
    if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
        ITW_CLASH_DualHALBLUFORGroups = ITW_CLASH_DualHALBLUFORGroups - [_group];
    };
    if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
        ITW_CLASH_DualHALOPFORExtraGroups = ITW_CLASH_DualHALOPFORExtraGroups - [_group];
    };
    _group setVariable ["ITW_CLASH_ExcludeHAL",true];
    _group setVariable ["Busy" + str _group,false];
    true
};

ITW_CLASH_Service_fnc_RegisterPhysical = {
    params ["_veh","_capability",["_mode",""],["_source","service"]];
    if (isNull _veh || {!([_capability] call ITW_CLASH_Service_fnc_IsCapability)}) exitWith {""};
    private _group = group driver _veh;
    if (isNull _group) exitWith {""};
    if (_mode isEqualTo "") then {_mode = [_veh] call ITW_CLASH_Service_fnc_ModeForVehicle};
    _mode = toUpperANSI _mode;
    _capability = toUpperANSI _capability;
    _group setVariable ["ITW_CLASH_CapExempt",true];
    _group setVariable ["ITW_CLASH_ServiceAsset",true];
    _group setVariable ["ITW_CLASH_ServiceCapability",_capability];
    _group setVariable ["ITW_CLASH_ExcludeHAL",nil];
    _veh setVariable ["ITW_CLASH_ServiceAsset",true,true];
    _veh setVariable ["ITW_CLASH_ServiceCapability",_capability,true];

    private _poolId = _veh getVariable ["ITW_CLASH_ServicePoolId",""];
    private _index = [_poolId] call ITW_CLASH_Service_fnc_FindEntry;
    if (_index < 0) then {
        ITW_CLASH_ServiceSerial = ITW_CLASH_ServiceSerial + 1;
        _poolId = format ["SVC-%1-%2",round (diag_tickTime * 1000),ITW_CLASH_ServiceSerial];
        _index = count ITW_CLASH_ServicePool;
        ITW_CLASH_ServicePool pushBack createHashMap;
    };
    private _home = _group getVariable ["START" + str _group,getPosATL _veh];
    if (_home isEqualTo []) then {_home = getPosATL _veh};
    if (count _home < 3) then {_home pushBack 0};
    private _entry = ITW_CLASH_ServicePool#_index;
    _entry set ["id",_poolId];
    _entry set ["side",side _group];
    _entry set ["capability",_capability];
    _entry set ["mode",_mode];
    _entry set ["class",typeOf _veh];
    _entry set ["vehDef",_veh getVariable ["ITW_VehDef",[]]];
    _entry set ["state","DEPLOYED"];
    _entry set ["vehicle",_veh];
    _entry set ["group",_group];
    _entry set ["home",+_home];
    _entry set ["source",_source];
    _entry set ["spawnedAt",time];
    _entry set ["everBusy",false];
    _entry set ["taskSeen",false];
    _entry set ["idleSince",-1];
    _entry set ["availableAt",0];
    ITW_CLASH_ServicePool set [_index,_entry];
    _veh setVariable ["ITW_CLASH_ServicePoolId",_poolId,true];
    _group setVariable ["ITW_CLASH_ServicePoolId",_poolId];
    _group setVariable ["ITW_CLASH_ServiceHome",+_home];
    ["physical-registered",[_poolId,_capability,side _group,_mode,typeOf _veh,_source,+_home]] call ITW_CLASH_Service_fnc_Log;
    _poolId
};

/* Fail-safe base; ServiceStability replaces this with native-count authority. */
ITW_CLASH_Service_fnc_Retire = {
    params ["_index",["_reason","hal-returned-home"]];
    if (_index < 0 || {_index >= count ITW_CLASH_ServicePool}) exitWith {false};
    private _entry = ITW_CLASH_ServicePool#_index;
    private _veh = _entry getOrDefault ["vehicle",objNull];
    private _group = _entry getOrDefault ["group",grpNull];
    if (isNull _veh) exitWith {false};
    private _players = allPlayers select {!(_x isKindOf "HeadlessClient_F")};
    if ((_players findIf {_x distance2D _veh < ITW_CLASH_ServiceRetirePlayerRadius}) >= 0) exitWith {false};
    private _vehDef = _entry getOrDefault ["vehDef",[]];
    if (_vehDef isEqualTo []) then {_vehDef = _veh getVariable ["ITW_VehDef",[]]};
    if (_vehDef isEqualTo []) exitWith {false};
    if !([_veh] call ITW_CLASH_Service_fnc_MarkTrackerReleased) exitWith {false};
    if (!isNull _group) then {[_group] call ITW_CLASH_Service_fnc_RemoveHALOwnership};
    _entry set ["vehDef",_vehDef];
    _entry set ["class",typeOf _veh];
    _entry set ["state","AVAILABLE"];
    _entry set ["vehicle",objNull];
    _entry set ["group",grpNull];
    _entry set ["availableAt",time + ITW_CLASH_ServiceReuseCooldown];
    _entry set ["retiredAt",time];
    ITW_CLASH_ServicePool set [_index,_entry];
    private _poolId = _entry get "id";
    private _capability = _entry get "capability";
    private _class = typeOf _veh;
    deleteVehicleCrew _veh;
    deleteVehicle _veh;
    if (!isNull _group && {units _group isEqualTo []}) then {deleteGroup _group};
    ["virtualized",[_poolId,_capability,_class,_reason,_vehDef#ITW_VEH_COUNT]] call ITW_CLASH_Service_fnc_Log;
    true
};

ITW_CLASH_Service_fnc_CurrentWaypoint = {
    params ["_group"];
    if (isNull _group) exitWith {["NONE",[]]};
    private _idx = currentWaypoint _group;
    private _wps = waypoints _group;
    if (_idx < 0 || {_idx >= count _wps}) exitWith {["NONE",[]]};
    private _wp = [_group,_idx];
    [waypointType _wp,waypointPosition _wp]
};

/* Replaced by ServiceStability's capacity-safe implementation during init. */
ITW_CLASH_Service_fnc_TryReactivate = {createHashMap};

ITW_CLASH_ServiceNativeProviders = createHashMap;
ITW_CLASH_Service_fnc_Provider = {
    private _request = _this;
    private _capability = toUpperANSI (_request getOrDefault ["capability",""]);
    private _reused = _request call ITW_CLASH_Service_fnc_TryReactivate;
    if (_reused isEqualType createHashMap && {count _reused > 0}) exitWith {_reused};
    private _native = ITW_CLASH_ServiceNativeProviders getOrDefault [_capability,objNull];
    if !(_native isEqualType {}) exitWith {
        [_request,"DENIED",[],"service-native-provider-missing","service-lifecycle-v2"] call ITW_CLASH_Checkbook_fnc_Response
    };
    private _reply = _request call _native;
    if (_reply isEqualType createHashMap && {(_reply getOrDefault ["status",""]) == "APPROVED"}) then {
        private _veh = _reply getOrDefault ["asset",objNull];
        if (!isNull _veh) then {
            private _requirements = _request getOrDefault ["requirements",createHashMap];
            private _mode = toUpperANSI (_requirements getOrDefault ["mode",[_veh] call ITW_CLASH_Service_fnc_ModeForVehicle]);
            [_veh,_capability,_mode,"new-purchase"] call ITW_CLASH_Service_fnc_RegisterPhysical;
        };
    };
    _reply
};

ITW_CLASH_Service_fnc_InstallProviderWrappers = {
    if (isNil "ITW_CLASH_CheckbookProviders") exitWith {false};
    {
        private _native = ITW_CLASH_CheckbookProviders getOrDefault [_x,objNull];
        if (_native isEqualType {}) then {
            ITW_CLASH_ServiceNativeProviders set [_x,_native];
            ITW_CLASH_CheckbookProviders set [_x,ITW_CLASH_Service_fnc_Provider];
        };
    } forEach ["LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"];
    true
};

// AI transport remains outside the service/virtualization pool during the
// isolation pass. Checkbook provisions it; HAL owns the live asset directly.

if (!isNil "ITW_CLASH_Generation_fnc_RegisterAsset") then {
    ITW_CLASH_Service_fnc_RegisterGeneratedBase = ITW_CLASH_Generation_fnc_RegisterAsset;
    ITW_CLASH_Generation_fnc_RegisterAsset = {
        private _result = _this call ITW_CLASH_Service_fnc_RegisterGeneratedBase;
        if (_result) then {
            _this params ["_veh","_group","_hq","_capability","_mode"];
            if ((toUpperANSI _capability) in ["LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"]) then {
                if (!isNull _group) then {_group setVariable ["ITW_CLASH_CapExempt",true]};
                if (!isNull _veh) then {[_veh,_capability,_mode,"generation-register"] call ITW_CLASH_Service_fnc_RegisterPhysical};
            };
        };
        _result
    };
};

/* Transport staging is intentionally not wrapped by ServiceLifecycle during
   isolation. DualHAL performs the handoff; HAL owns every live order afterward. */

call ITW_CLASH_Service_fnc_InstallProviderWrappers;

/* HAL owns pickup, delivery and RTB. C.L.A.S.H. only virtualizes settled returns. */
[] spawn {
    scriptName "ITW_CLASH_ServicePassiveReturnMonitor";
    waitUntil {
        sleep 1;
        missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 5;
        for "_i" from ((count ITW_CLASH_ServicePool) - 1) to 0 step -1 do {
            private _entry = ITW_CLASH_ServicePool#_i;
            if ((_entry getOrDefault ["state",""]) isEqualTo "AVAILABLE") then {continue};
            private _veh = _entry getOrDefault ["vehicle",objNull];
            if (isNull _veh || {!alive _veh}) then {
                ["lost",[_entry getOrDefault ["id","?"],_entry getOrDefault ["capability","?"],_entry getOrDefault ["class","?"]]] call ITW_CLASH_Service_fnc_Log;
                ITW_CLASH_ServicePool deleteAt _i;
                continue;
            };
            private _group = _entry getOrDefault ["group",grpNull];
            if (isNull _group) then {_group = group driver _veh; _entry set ["group",_group]};
            if (isNull _group) then {ITW_CLASH_ServicePool set [_i,_entry]; continue};
            private _home = +(_entry getOrDefault ["home",getPosATL _veh]);
            private _radius = if (_veh isKindOf "Air") then {ITW_CLASH_ServiceRTBAirRadius} else {ITW_CLASH_ServiceRTBLandRadius};
            private _distance = _veh distance2D _home;
            private _busy = _group getVariable ["Busy" + str _group,false];
            private _cargo = (assignedCargo _veh) isNotEqualTo [] || {(crew _veh findIf {alive _x && {group _x != _group}}) >= 0};

            if (_busy || {_cargo} || {_distance > (_radius + 50)}) then {
                if (_busy || {_cargo} || {_distance > 175}) then {
                    _entry set ["taskSeen",true];
                    if (_busy || {_cargo}) then {_entry set ["everBusy",true]};
                };
                _entry set ["idleSince",-1];
                ITW_CLASH_ServicePool set [_i,_entry];
                continue;
            };
            if !(_entry getOrDefault ["taskSeen",false]) then {
                _entry set ["idleSince",-1];
                ITW_CLASH_ServicePool set [_i,_entry];
                continue;
            };

            private _wpInfo = [_group] call ITW_CLASH_Service_fnc_CurrentWaypoint;
            _wpInfo params ["_wpType","_wpPos"];
            private _halHomeIntent = _wpType isEqualTo "NONE" || {_wpPos isNotEqualTo [] && {_wpPos distance2D _home <= (_radius + 100)}};
            private _settled = !_busy && {!_cargo} && {_distance <= _radius && {abs speed _veh < 2} && {_halHomeIntent}};
            if (!_settled) then {
                _entry set ["idleSince",-1];
                ITW_CLASH_ServicePool set [_i,_entry];
                continue;
            };

            private _idleSince = _entry getOrDefault ["idleSince",-1];
            if (_idleSince < 0) then {
                _entry set ["idleSince",time];
                ITW_CLASH_ServicePool set [_i,_entry];
                ["hal-return-observed",[_entry getOrDefault ["id","?"],_entry getOrDefault ["capability","?"],typeOf _veh,round _distance,_wpType]] call ITW_CLASH_Service_fnc_Log;
                continue;
            };
            if (time - _idleSince >= ITW_CLASH_ServiceIdleGrace) then {
                ITW_CLASH_ServicePool set [_i,_entry];
                [_i,"hal-returned-home"] call ITW_CLASH_Service_fnc_Retire;
            } else {ITW_CLASH_ServicePool set [_i,_entry]};
        };
    };
};

ITW_CLASH_ServiceLifecycleReady = true;
diag_log format [
    "CLASH BOOT | service-lifecycle-ready | version=%1 capExempt=true virtualPool=true passiveHALReturn=true clashOrdersRTB=false halOwnsLiveDisposition=true staleHandoffSanitized=true artilleryPersistent=true",
    ITW_CLASH_ServiceLifecycleVersion
];
true