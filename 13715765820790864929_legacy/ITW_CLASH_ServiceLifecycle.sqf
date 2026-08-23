#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ServiceLifecycleStarted",false]) exitWith {true};
ITW_CLASH_ServiceLifecycleStarted = true;
ITW_CLASH_ServiceLifecycleVersion = 1;
ITW_CLASH_ServiceLifecycleReady = false;
ITW_CLASH_ServicePool = [];
ITW_CLASH_ServiceSerial = 0;
ITW_CLASH_ServiceRTBLandRadius = 125;
ITW_CLASH_ServiceRTBAirRadius = 350;
ITW_CLASH_ServiceIdleGrace = 25;
ITW_CLASH_ServiceUnclaimedTimeout = 180;
ITW_CLASH_ServiceProgressTimeout = 75;
ITW_CLASH_ServiceHardStuckTimeout = 210;
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
        "TRANSPORT",
        "LOGISTICS_AMMO",
        "LOGISTICS_FUEL",
        "LOGISTICS_REPAIR"
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
    ITW_CLASH_ServicePool findIf {
        (_x getOrDefault ["id",""]) isEqualTo _poolId
    }
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

ITW_CLASH_Service_fnc_RemoveHALOwnership = {
    params ["_group"];
    if (isNull _group) exitWith {false};

    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {grpNull};
    if (!isNull _hq) then {
        {
            private _arr = +(_hq getVariable [_x,[]]);
            _arr = _arr - [_group];
            _hq setVariable [_x,_arr];
        } forEach [
            "RydHQ_Friends",
            "RydHQ_Included",
            "RydHQ_AttackAv",
            "RydHQ_FlankAv",
            "RydHQ_CombatAv",
            "RydHQ_ReconAv",
            "RydHQ_ReconG",
            "RydHQ_CargoG",
            "RydHQ_CargoOnly",
            "RydHQ_NoAttack",
            "RydHQ_NoRecon",
            "RydHQ_NoDef",
            "RydHQ_AirG",
            "RydHQ_DefRes",
            "RydHQ_AmmoSupportG",
            "RydHQ_AmmoDrop",
            "RydHQ_FuelSupportG",
            "RydHQ_RepSupportG"
        ];
        private _support = +(_hq getVariable ["RydHQ_Support",[]]);
        _support = _support - (units _group);
        _hq setVariable ["RydHQ_Support",_support];
    };

    if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
        ITW_CLASH_DualHALBLUFORGroups = ITW_CLASH_DualHALBLUFORGroups - [_group];
    };
    if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
        ITW_CLASH_DualHALOPFORExtraGroups = ITW_CLASH_DualHALOPFORExtraGroups - [_group];
    };

    _group setVariable ["ITW_CLASH_ExcludeHAL",true];
    _group setVariable ["ITW_CLASH_ServiceRTB",true];
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
    _group setVariable ["ITW_CLASH_ServiceRTB",nil];
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
    private _vehDef = _veh getVariable ["ITW_VehDef",[]];
    private _entry = ITW_CLASH_ServicePool#_index;
    _entry set ["id",_poolId];
    _entry set ["side",side _group];
    _entry set ["capability",_capability];
    _entry set ["mode",_mode];
    _entry set ["class",typeOf _veh];
    _entry set ["vehDef",_vehDef];
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
    _entry set ["lastDistance",_veh distance2D _home];
    _entry set ["lastProgressAt",time];
    ITW_CLASH_ServicePool set [_index,_entry];

    _veh setVariable ["ITW_CLASH_ServicePoolId",_poolId,true];
    _group setVariable ["ITW_CLASH_ServicePoolId",_poolId];
    _group setVariable ["ITW_CLASH_ServiceHome",+_home];

    ["physical-registered",[
        _poolId,_capability,side _group,_mode,typeOf _veh,_source,+_home
    ]] call ITW_CLASH_Service_fnc_Log;
    _poolId
};

ITW_CLASH_Service_fnc_OrderRTB = {
    params ["_index",["_reason","task-complete"]];
    if (_index < 0 || {_index >= count ITW_CLASH_ServicePool}) exitWith {false};
    private _entry = ITW_CLASH_ServicePool#_index;
    if ((_entry getOrDefault ["state",""]) isNotEqualTo "DEPLOYED") exitWith {false};

    private _veh = _entry getOrDefault ["vehicle",objNull];
    private _group = _entry getOrDefault ["group",grpNull];
    private _home = +(_entry getOrDefault ["home",[]]);
    if (isNull _veh || {isNull _group} || {_home isEqualTo []}) exitWith {false};

    [_group] call ITW_CLASH_Service_fnc_RemoveHALOwnership;
    if (!isNil "RYD_WPdel") then {[_group] call RYD_WPdel} else {
        {deleteWaypoint _x} forEachReversed waypoints _group
    };
    _group enableAttack false;
    _group setCombatMode "BLUE";
    _group setBehaviourStrong "CARELESS";
    _group setSpeedMode "FULL";
    if (_veh isKindOf "Air") then {_veh flyInHeight 80};

    private _wp = _group addWaypoint [_home,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius (if (_veh isKindOf "Air") then {150} else {35});

    private _distance = _veh distance2D _home;
    _entry set ["state","RTB"];
    _entry set ["rtbReason",_reason];
    _entry set ["rtbStarted",time];
    _entry set ["lastDistance",_distance];
    _entry set ["lastProgressAt",time];
    _entry set ["lastOrderAt",time];
    ITW_CLASH_ServicePool set [_index,_entry];

    ["rtb-start",[
        _entry get "id",_entry get "capability",side _group,typeOf _veh,
        _reason,round _distance
    ]] call ITW_CLASH_Service_fnc_Log;
    true
};

ITW_CLASH_Service_fnc_Retire = {
    params ["_index",["_reason","home"]];
    if (_index < 0 || {_index >= count ITW_CLASH_ServicePool}) exitWith {false};
    private _entry = ITW_CLASH_ServicePool#_index;
    private _veh = _entry getOrDefault ["vehicle",objNull];
    private _group = _entry getOrDefault ["group",grpNull];
    if (isNull _veh) exitWith {false};

    private _players = allPlayers select {!(_x isKindOf "HeadlessClient_F")};
    private _nearPlayer = (_players findIf {_x distance2D _veh < ITW_CLASH_ServiceRetirePlayerRadius}) >= 0;
    if (_nearPlayer) exitWith {false};

    private _vehDef = _entry getOrDefault ["vehDef",[]];
    if (_vehDef isEqualTo []) then {_vehDef = _veh getVariable ["ITW_VehDef",[]]};
    if (_vehDef isEqualTo []) exitWith {false};

    // Mark the physical tracker released before deletion so a successful RTB
    // does not free the already-paid Impasse vehicle slot. Destruction still
    // follows the normal tracker path and decrements the slot.
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

    ["virtualized",[
        _poolId,_capability,_class,_reason,_vehDef#ITW_VEH_COUNT
    ]] call ITW_CLASH_Service_fnc_Log;
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

ITW_CLASH_Service_fnc_ReissueRTB = {
    params ["_index"];
    if (_index < 0 || {_index >= count ITW_CLASH_ServicePool}) exitWith {false};
    private _entry = ITW_CLASH_ServicePool#_index;
    private _veh = _entry getOrDefault ["vehicle",objNull];
    private _group = _entry getOrDefault ["group",grpNull];
    private _home = +(_entry getOrDefault ["home",[]]);
    if (isNull _veh || {isNull _group} || {_home isEqualTo []}) exitWith {false};

    if (!isNil "RYD_WPdel") then {[_group] call RYD_WPdel} else {
        {deleteWaypoint _x} forEachReversed waypoints _group
    };
    private _wp = _group addWaypoint [_home,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius (if (_veh isKindOf "Air") then {150} else {35});
    if (_veh isKindOf "Air") then {_veh flyInHeight 80};
    _entry set ["lastOrderAt",time];
    ITW_CLASH_ServicePool set [_index,_entry];
    true
};

ITW_CLASH_Service_fnc_TryReactivate = {
    private _request = _this;
    private _capability = toUpperANSI (_request getOrDefault ["capability",""]);
    if !([_capability] call ITW_CLASH_Service_fnc_IsCapability) exitWith {createHashMap};

    private _requirements = _request getOrDefault ["requirements",createHashMap];
    private _side = _request getOrDefault ["side",sideUnknown];
    private _mode = toUpperANSI (_requirements getOrDefault ["mode","GROUND"]);
    private _seats = round (_requirements getOrDefault ["seats",1]);
    private _index = ITW_CLASH_ServicePool findIf {
        (_x getOrDefault ["state",""]) isEqualTo "AVAILABLE" && {
            (_x getOrDefault ["side",sideUnknown]) == _side && {
                (_x getOrDefault ["capability",""]) isEqualTo _capability && {
                    (_x getOrDefault ["mode",""]) isEqualTo _mode && {
                        time >= (_x getOrDefault ["availableAt",0]) && {
                            (_x getOrDefault ["vehDef",[]]) isNotEqualTo []
                        }
                    }
                }
            }
        }
    };
    if (_index < 0) exitWith {createHashMap};

    private _entry = ITW_CLASH_ServicePool#_index;
    private _class = _entry getOrDefault ["class",""];
    private _vehDef = _entry getOrDefault ["vehDef",[]];
    if (_class isEqualTo "" || {_vehDef isEqualTo []}) exitWith {createHashMap};

    private _profile = toUpperANSI (_requirements getOrDefault [
        "profile",
        if (_capability == "TRANSPORT") then {
            if (_mode == "AIR") then {"FORWARD_AIR"} else {"FORWARD"}
        } else {
            if (_mode == "AIR") then {"REAR_AIR"} else {"REAR"}
        }
    ]);
    private _requester = _request getOrDefault ["requester",grpNull];
    private _reference = +(_requirements getOrDefault [
        "reference",
        if (isNull _requester) then {[0,0,0]} else {getPosATL leader _requester}
    ]);
    private _generation = [
        _side,_capability,_profile,_reference
    ] call ITW_CLASH_Generation_fnc_Resolve;
    if ((_generation getOrDefault ["status",""]) != "RESOLVED") exitWith {createHashMap};

    private _crewInfo = [_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes;
    _crewInfo params ["_crewTypes","_unitTypes"];
    if (_crewTypes isEqualTo [] || {_unitTypes isEqualTo []}) exitWith {createHashMap};

    private _origin = +(_generation get "origin");
    private _veh = [[_class],_crewTypes,_unitTypes,_side,_origin,-1] call ITW_AtkSpawnVeh;
    if (isNull _veh) exitWith {createHashMap};
    private _crewGroup = group driver _veh;
    if (_capability == "TRANSPORT" && {_veh emptyPositions "" < _seats}) exitWith {
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        createHashMap
    };

    _veh setVariable ["ITW_CLASH_ServicePoolId",_entry get "id",true];
    private _hq = _requirements getOrDefault ["hq",grpNull];
    if (isNull _hq && {!isNil "ITW_CLASH_fnc_GetCommanderForSide"}) then {
        _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide
    };
    if (isNull _hq) exitWith {
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        createHashMap
    };

    private _registered = if (_capability == "TRANSPORT") then {
        [_veh,_crewGroup,_vehDef,_hq,_request get "id","service-pool"] call
            ITW_CLASH_Checkbook_fnc_RegisterTransport
    } else {
        [_veh,_crewGroup,_hq,_capability,_mode,_request get "id",_vehDef] call
            ITW_CLASH_Generation_fnc_RegisterAsset
    };
    if (!_registered) exitWith {
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        createHashMap
    };

    _veh setDir (_generation getOrDefault ["direction",direction _veh]);
    {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;
    [_veh,_capability,_mode,"virtual-reactivation"] call ITW_CLASH_Service_fnc_RegisterPhysical;

    private _billing = createHashMapFromArray [
        ["class",_class],
        ["ticketCost",0],
        ["reused",true],
        ["count",_vehDef#ITW_VEH_COUNT],
        ["max",_vehDef#ITW_VEH_MAX]
    ];
    private _metadata = createHashMapFromArray [
        ["mode",_mode],
        ["virtualPool",true],
        ["poolId",_entry get "id"]
    ];
    ["reactivated",[
        _entry get "id",_capability,_side,_mode,_class,_vehDef#ITW_VEH_COUNT
    ]] call ITW_CLASH_Service_fnc_Log;

    [_request,"APPROVED",[_veh],"virtual-asset-reactivated","service-lifecycle-v1",_billing,_generation,_metadata] call
        ITW_CLASH_Checkbook_fnc_Response
};

ITW_CLASH_ServiceNativeProviders = createHashMap;
ITW_CLASH_Service_fnc_Provider = {
    private _request = _this;
    private _capability = toUpperANSI (_request getOrDefault ["capability",""]);
    private _reused = _request call ITW_CLASH_Service_fnc_TryReactivate;
    if (_reused isEqualType createHashMap && {count _reused > 0}) exitWith {_reused};

    private _native = ITW_CLASH_ServiceNativeProviders getOrDefault [_capability,objNull];
    if !(_native isEqualType {}) exitWith {
        [_request,"DENIED",[],"service-native-provider-missing","service-lifecycle-v1"] call
            ITW_CLASH_Checkbook_fnc_Response
    };
    private _reply = _request call _native;
    if (_reply isEqualType createHashMap && {
        (_reply getOrDefault ["status",""]) == "APPROVED"
    }) then {
        private _veh = _reply getOrDefault ["asset",objNull];
        if (!isNull _veh) then {
            private _requirements = _request getOrDefault ["requirements",createHashMap];
            private _mode = toUpperANSI (_requirements getOrDefault [
                "mode",[_veh] call ITW_CLASH_Service_fnc_ModeForVehicle
            ]);
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
    } forEach ["TRANSPORT","LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"];
    true
};

// Mark every transport created by the direct Checkbook path as support manpower.
if (!isNil "ITW_CLASH_Checkbook_fnc_RegisterTransport") then {
    ITW_CLASH_Service_fnc_RegisterTransportBase = ITW_CLASH_Checkbook_fnc_RegisterTransport;
    ITW_CLASH_Checkbook_fnc_RegisterTransport = {
        private _result = _this call ITW_CLASH_Service_fnc_RegisterTransportBase;
        if (_result) then {
            _this params ["_veh","_crewGroup"];
            if (!isNull _crewGroup) then {_crewGroup setVariable ["ITW_CLASH_CapExempt",true]};
            if (!isNull _veh) then {
                [_veh,"TRANSPORT",[_veh] call ITW_CLASH_Service_fnc_ModeForVehicle,"checkbook-register"] call
                    ITW_CLASH_Service_fnc_RegisterPhysical;
            };
        };
        _result
    };
};

// Logistics assets are services; artillery deliberately remains persistent and
// combat-accounted.
if (!isNil "ITW_CLASH_Generation_fnc_RegisterAsset") then {
    ITW_CLASH_Service_fnc_RegisterGeneratedBase = ITW_CLASH_Generation_fnc_RegisterAsset;
    ITW_CLASH_Generation_fnc_RegisterAsset = {
        private _result = _this call ITW_CLASH_Service_fnc_RegisterGeneratedBase;
        if (_result) then {
            _this params ["_veh","_group","_hq","_capability","_mode"];
            if ((toUpperANSI _capability) in ["LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"]) then {
                if (!isNull _group) then {_group setVariable ["ITW_CLASH_CapExempt",true]};
                if (!isNull _veh) then {
                    [_veh,_capability,_mode,"generation-register"] call
                        ITW_CLASH_Service_fnc_RegisterPhysical;
                };
            };
        };
        _result
    };
};

// Existing Impasse transports can enter HAL with stale SAD/COMBAT waypoints.
// Sanitize that inherited task immediately after handoff and put the asset into
// the same on-demand lifecycle as Checkbook transports.
if (!isNil "ITW_CLASH_DualHAL_fnc_StageFieldVehicle") then {
    ITW_CLASH_Service_fnc_StageFieldVehicleBase = ITW_CLASH_DualHAL_fnc_StageFieldVehicle;
    ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {
        private _result = _this call ITW_CLASH_Service_fnc_StageFieldVehicleBase;
        if (_result) then {
            private _vehInfo = _this param [0,[]];
            if (_vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CARGO_GRPS}) then {
                private _role = _vehInfo#VEHINFO_ROLE;
                if (_role in [ITW_VEH_ROLE_TRANSPORT,ITW_VEH_ROLE_DUAL]) then {
                    private _veh = _vehInfo#VEHINFO_VEH;
                    private _group = _vehInfo#VEHINFO_CREW_GRP;
                    if (!isNull _group) then {
                        if (!isNil "RYD_WPdel") then {[_group] call RYD_WPdel} else {
                            {deleteWaypoint _x} forEachReversed waypoints _group
                        };
                        _group setVariable ["ITW_CLASH_CapExempt",true];
                    };
                    if (!isNull _veh) then {
                        [_veh,"TRANSPORT",[_veh] call ITW_CLASH_Service_fnc_ModeForVehicle,"impasse-handoff"] call
                            ITW_CLASH_Service_fnc_RegisterPhysical;
                    };
                };
            };
        };
        _result
    };
};

call ITW_CLASH_Service_fnc_InstallProviderWrappers;

[] spawn {
    scriptName "ITW_CLASH_ServiceLifecycleMonitor";
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
            private _state = _entry getOrDefault ["state",""];
            if (_state isEqualTo "AVAILABLE") then {continue};
            private _externalMutation = false;

            private _veh = _entry getOrDefault ["vehicle",objNull];
            if (isNull _veh || {!alive _veh}) then {
                ["lost",[
                    _entry getOrDefault ["id","?"],
                    _entry getOrDefault ["capability","?"],
                    _entry getOrDefault ["class","?"]
                ]] call ITW_CLASH_Service_fnc_Log;
                ITW_CLASH_ServicePool deleteAt _i;
                continue;
            };

            private _group = _entry getOrDefault ["group",grpNull];
            if (isNull _group) then {_group = group driver _veh; _entry set ["group",_group]};
            private _vehDef = _entry getOrDefault ["vehDef",[]];
            if (_vehDef isEqualTo []) then {
                _vehDef = _veh getVariable ["ITW_VehDef",[]];
                if (_vehDef isNotEqualTo []) then {_entry set ["vehDef",_vehDef]};
            };

            private _home = +(_entry getOrDefault ["home",getPosATL _veh]);
            private _distance = _veh distance2D _home;
            if (_state isEqualTo "DEPLOYED") then {
                private _busy = if (isNull _group) then {false} else {
                    _group getVariable ["Busy" + str _group,false]
                };
                private _cargo = (assignedCargo _veh) isNotEqualTo [] || {
                    (crew _veh findIf {alive _x && {!isNull _group && {group _x != _group}}}) >= 0
                };
                if (_busy || {_cargo}) then {
                    _entry set ["everBusy",true];
                    _entry set ["taskSeen",true];
                    _entry set ["idleSince",-1];
                };
                if (_distance > 175) then {_entry set ["taskSeen",true]};

                private _wpInfo = if (isNull _group) then {["NONE",[]]} else {
                    [_group] call ITW_CLASH_Service_fnc_CurrentWaypoint
                };
                _wpInfo params ["_wpType","_wpPos"];
                private _halReturn = _wpPos isNotEqualTo [] && {
                    _wpPos distance2D _home <= 350
                };
                private _taskSeen = _entry getOrDefault ["taskSeen",false];
                private _everBusy = _entry getOrDefault ["everBusy",false];
                private _idle = !_busy && {!_cargo};

                if (_idle && {_everBusy}) then {
                    private _idleSince = _entry getOrDefault ["idleSince",-1];
                    if (_idleSince < 0) then {
                        _idleSince = time;
                        _entry set ["idleSince",_idleSince];
                    };
                    if (time - _idleSince >= ITW_CLASH_ServiceIdleGrace) then {
                        ITW_CLASH_ServicePool set [_i,_entry];
                        _externalMutation = [_i,"hal-task-complete"] call ITW_CLASH_Service_fnc_OrderRTB;
                    };
                } else {
                    if (_idle && {_taskSeen && {_halReturn}}) then {
                        ITW_CLASH_ServicePool set [_i,_entry];
                        _externalMutation = [_i,"hal-rtb-takeover"] call ITW_CLASH_Service_fnc_OrderRTB;
                    } else {
                        if (_idle && {_taskSeen && {_wpType isEqualTo "NONE" && {_distance > 175}}}) then {
                            private _idleSince = _entry getOrDefault ["idleSince",-1];
                            if (_idleSince < 0) then {
                                _idleSince = time;
                                _entry set ["idleSince",_idleSince];
                            };
                            if (time - _idleSince >= ITW_CLASH_ServiceIdleGrace) then {
                                ITW_CLASH_ServicePool set [_i,_entry];
                                _externalMutation = [_i,"idle-after-task"] call ITW_CLASH_Service_fnc_OrderRTB;
                            };
                        } else {
                            if (!_taskSeen && {
                                _distance < 175 && {
                                    time - (_entry getOrDefault ["spawnedAt",time]) >= ITW_CLASH_ServiceUnclaimedTimeout
                                }
                            }) then {
                                ITW_CLASH_ServicePool set [_i,_entry];
                                _externalMutation = [_i,"unclaimed-timeout"] call ITW_CLASH_Service_fnc_OrderRTB;
                            };
                        };
                    };
                };
            } else {
                if (_state isEqualTo "RTB") then {
                    private _radius = if (_veh isKindOf "Air") then {
                        ITW_CLASH_ServiceRTBAirRadius
                    } else {
                        ITW_CLASH_ServiceRTBLandRadius
                    };
                    if (_distance <= _radius) then {
                        ITW_CLASH_ServicePool set [_i,_entry];
                        _externalMutation = [_i,"home-radius"] call ITW_CLASH_Service_fnc_Retire;
                    } else {
                        private _lastDistance = _entry getOrDefault ["lastDistance",_distance];
                        if (_distance < (_lastDistance - 25)) then {
                            _entry set ["lastDistance",_distance];
                            _entry set ["lastProgressAt",time];
                        };
                        private _lastProgress = _entry getOrDefault ["lastProgressAt",time];
                        private _lastOrder = _entry getOrDefault ["lastOrderAt",0];
                        if (time - _lastProgress >= ITW_CLASH_ServiceProgressTimeout && {
                            time - _lastOrder >= 45
                        }) then {
                            ITW_CLASH_ServicePool set [_i,_entry];
                            _externalMutation = [_i] call ITW_CLASH_Service_fnc_ReissueRTB;
                            ["rtb-reissued",[
                                _entry get "id",typeOf _veh,round _distance,
                                round (time - _lastProgress)
                            ]] call ITW_CLASH_Service_fnc_Log;
                        };
                        if (!_externalMutation && {
                            time - _lastProgress >= ITW_CLASH_ServiceHardStuckTimeout
                        }) then {
                            private _players = allPlayers select {!(_x isKindOf "HeadlessClient_F")};
                            private _visible = (_players findIf {_x distance2D _veh < 1000}) >= 0;
                            if (!_visible) then {
                                ITW_CLASH_ServicePool set [_i,_entry];
                                _externalMutation = [_i,"stuck-safe-retire"] call ITW_CLASH_Service_fnc_Retire;
                            };
                        };
                    };
                };
            };
            if (!_externalMutation && {_i < count ITW_CLASH_ServicePool}) then {
                if ((ITW_CLASH_ServicePool#_i getOrDefault ["id",""]) isEqualTo (_entry getOrDefault ["id","-changed-"])) then {
                    ITW_CLASH_ServicePool set [_i,_entry];
                };
            };
        };
    };
};

ITW_CLASH_ServiceLifecycleReady = true;
diag_log format [
    "CLASH BOOT | service-lifecycle-ready | version=%1 capExempt=true virtualPool=true deterministicRTB=true staleHandoffSanitized=true artilleryPersistent=true",
    ITW_CLASH_ServiceLifecycleVersion
];
true