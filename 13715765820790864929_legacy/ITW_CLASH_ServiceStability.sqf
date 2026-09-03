#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ServiceStabilityStarted",false]) exitWith {true};
ITW_CLASH_ServiceStabilityStarted = true;
ITW_CLASH_ServiceStabilityVersion = 4;
ITW_CLASH_ServiceStabilityReady = false;
ITW_CLASH_ServiceReactivationBusy = false;

if (
    !(missionNamespace getVariable ["ITW_CLASH_ServiceAuthorityReady",false])
    || {isNil "ITW_CLASH_Service_fnc_Retire"}
    || {isNil "ITW_CLASH_Service_fnc_TryReactivate"}
) exitWith {
    diag_log "CLASH BOOT | WARNING | service-stability-source-missing";
    false
};

ITW_CLASH_ServiceStability_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["service-stability-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH SERVICE STABILITY | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_ServiceStability_fnc_HasLease = {
    params ["_group",["_veh",objNull]];
    if (!isNull _veh && {[_veh] call ITW_CLASH_ServiceAuthority_fnc_HasLease}) exitWith {true};
    !isNull _group && {[_group] call ITW_CLASH_ServiceAuthority_fnc_HasLease}
};

/*
    Compatibility shim for callers from older service-authority revisions.
    A live lease is identity/accounting metadata only. We deliberately do not
    rewrite HAL planning arrays here: HAL owns live disposition and SitRep.
*/
ITW_CLASH_ServiceStability_fnc_EnsureQuarantine = {
    params ["_group",["_source","compat"]];
    !isNull _group
};

/*
    Virtualization occurs only after ServiceLifecycle has observed HAL's own RTB
    and home-idle settle. At this storage boundary it is safe to remove the live
    group from HAL, clear the lease, delete the physical object, and retain the
    already-paid virtual entitlement. Impasse's live count remains authoritative.
*/
ITW_CLASH_ServiceStability_fnc_RetireBase = ITW_CLASH_Service_fnc_Retire;
ITW_CLASH_Service_fnc_Retire = {
    params ["_index",["_reason","hal-returned-home"]];
    if (_index < 0 || {_index >= count ITW_CLASH_ServicePool}) exitWith {false};
    private _entry = ITW_CLASH_ServicePool#_index;
    private _veh = _entry getOrDefault ["vehicle",objNull];
    private _group = _entry getOrDefault ["group",grpNull];
    if (isNull _veh) exitWith {false};

    private _players = allPlayers select {!(_x isKindOf "HeadlessClient_F")};
    private _capability = toUpperANSI (_entry getOrDefault ["capability",""]);
    private _retirePlayerRadius = if (_capability == "TRANSPORT") then {
        missionNamespace getVariable [
            "ITW_CLASH_ServiceTransportRetirePlayerRadius",
            ITW_CLASH_ServiceRetirePlayerRadius
        ]
    } else {
        ITW_CLASH_ServiceRetirePlayerRadius
    };
    if ((_players findIf {_x distance2D _veh < _retirePlayerRadius}) >= 0) exitWith {false};

    private _vehDef = _entry getOrDefault ["vehDef",[]];
    if (_vehDef isEqualTo []) then {_vehDef = _veh getVariable ["ITW_VehDef",[]]};
    if (_vehDef isEqualTo []) exitWith {false};

    if (!isNull _group) then {
        [_group] call ITW_CLASH_Service_fnc_RemoveHALOwnership
    };

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
    [_veh,_group,"virtualized-after-hal-rtb"] call ITW_CLASH_ServiceAuthority_fnc_ClearLease;

    deleteVehicleCrew _veh;
    deleteVehicle _veh;
    if (!isNull _group && {units _group isEqualTo []}) then {deleteGroup _group};

    ["virtualized",[
        _poolId,_capability,_class,_reason,
        _vehDef#ITW_VEH_COUNT,"physical-recount-authoritative"
    ]] call ITW_CLASH_Service_fnc_Log;
    true
};

/*
    A virtual entitlement rematerializes only when native Impasse capacity is
    available. It does not spend tickets again. Once registered, the live asset
    belongs to HAL until HAL later returns it home.
*/
ITW_CLASH_ServiceStability_fnc_TryReactivateBase = ITW_CLASH_Service_fnc_TryReactivate;
ITW_CLASH_Service_fnc_TryReactivate = {
    private _request = _this;
    private _capability = toUpperANSI (_request getOrDefault ["capability",""]);
    if !([_capability] call ITW_CLASH_Service_fnc_IsCapability) exitWith {createHashMap};

    private _requirements = _request getOrDefault ["requirements",createHashMap];
    private _side = _request getOrDefault ["side",sideUnknown];
    private _mode = toUpperANSI (_requirements getOrDefault ["mode","GROUND"]);
    private _seats = round (_requirements getOrDefault ["seats",1]);
    private _eligibleIndices = [];
    for "_i" from 0 to ((count ITW_CLASH_ServicePool) - 1) do {
        private _candidate = ITW_CLASH_ServicePool#_i;
        if (
            (_candidate getOrDefault ["state",""]) isEqualTo "AVAILABLE"
            && {(_candidate getOrDefault ["side",sideUnknown]) == _side}
            && {(_candidate getOrDefault ["capability",""]) isEqualTo _capability}
            && {(_candidate getOrDefault ["mode",""]) isEqualTo _mode}
            && {time >= (_candidate getOrDefault ["availableAt",0])}
            && {(_candidate getOrDefault ["vehDef",[]]) isNotEqualTo []}
        ) then {
            _eligibleIndices pushBack _i;
        };
    };

    private _index = if (
        _capability == "TRANSPORT"
        && {missionNamespace getVariable ["ITW_CLASH_ServiceCapacityPolicyReady",false]}
        && {!isNil "ITW_CLASH_ServiceCapacity_fnc_ScoreClass"}
    ) then {
        private _best = -1;
        private _bestScore = 1e12;
        {
            private _candidate = ITW_CLASH_ServicePool#_x;
            private _class = _candidate getOrDefault ["class",""];
            private _vehDef = _candidate getOrDefault ["vehDef",[]];
            private _scoreInfo = [
                _class,_vehDef,_seats,"TRANSPORT_POOL"
            ] call ITW_CLASH_ServiceCapacity_fnc_ScoreClass;
            private _score = _scoreInfo#0;
            if (_score < _bestScore) then {
                _best = _x;
                _bestScore = _score;
            };
        } forEach _eligibleIndices;
        _best
    } else {
        if (_eligibleIndices isEqualTo []) then {-1} else {_eligibleIndices#0}
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
        "reference",if (isNull _requester) then {[0,0,0]} else {getPosATL leader _requester}
    ]);
    private _generation = [
        _side,_capability,_profile,_reference
    ] call ITW_CLASH_Generation_fnc_Resolve;
    if ((_generation getOrDefault ["status",""]) != "RESOLVED") exitWith {createHashMap};

    private _crewInfo = [_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes;
    _crewInfo params ["_crewTypes","_unitTypes"];
    if (_crewTypes isEqualTo [] || {_unitTypes isEqualTo []}) exitWith {createHashMap};

    SEM_LOCK_LONG(ITW_CLASH_ServiceReactivationBusy);
    ITW_TICKET_SEM_CHECK;
    if ((_vehDef#ITW_VEH_COUNT) >= (_vehDef#ITW_VEH_MAX)) exitWith {
        SEM_UNLOCK(ITW_CLASH_ServiceReactivationBusy);
        ["reactivation-deferred",[
            _entry get "id",_capability,_class,
            _vehDef#ITW_VEH_COUNT,_vehDef#ITW_VEH_MAX,"native-capacity-full"
        ]] call ITW_CLASH_ServiceStability_fnc_Log;
        createHashMap
    };

    private _origin = +(_generation get "origin");
    private _veh = [[_class],_crewTypes,_unitTypes,_side,_origin,-1] call ITW_AtkSpawnVeh;
    if (isNull _veh) exitWith {
        SEM_UNLOCK(ITW_CLASH_ServiceReactivationBusy);
        createHashMap
    };
    private _crewGroup = group driver _veh;

    if (_capability == "TRANSPORT" && {_veh emptyPositions "" < _seats}) exitWith {
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        SEM_UNLOCK(ITW_CLASH_ServiceReactivationBusy);
        createHashMap
    };

    _veh setVariable ["ITW_CLASH_ServicePoolId",_entry get "id",true];
    [_veh,_crewGroup,_capability,"virtual-reactivation"] call
        ITW_CLASH_ServiceAuthority_fnc_SetLease;

    private _hq = _requirements getOrDefault ["hq",grpNull];
    if (isNull _hq && {!isNil "ITW_CLASH_fnc_GetCommanderForSide"}) then {
        _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide
    };
    if (isNull _hq) exitWith {
        [_veh,_crewGroup,"reactivation-no-hq"] call ITW_CLASH_ServiceAuthority_fnc_ClearLease;
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        SEM_UNLOCK(ITW_CLASH_ServiceReactivationBusy);
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
        [_veh,_crewGroup,"reactivation-register-failed"] call ITW_CLASH_ServiceAuthority_fnc_ClearLease;
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        SEM_UNLOCK(ITW_CLASH_ServiceReactivationBusy);
        createHashMap
    };

    ITW_VEH_COUNT_INCR(_vehDef);
    SEM_UNLOCK(ITW_CLASH_ServiceReactivationBusy);

    _veh setDir (_generation getOrDefault ["direction",direction _veh]);
    {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;
    [_veh,_capability,_mode,"virtual-reactivation"] call
        ITW_CLASH_Service_fnc_RegisterPhysical;

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
        ["poolId",_entry get "id"],
        ["halOwnsLiveDisposition",true]
    ];

    ["reactivated",[
        _entry get "id",_capability,_side,_mode,_class,
        _vehDef#ITW_VEH_COUNT,_vehDef#ITW_VEH_MAX
    ]] call ITW_CLASH_Service_fnc_Log;

    [_request,"APPROVED",[_veh],"virtual-asset-reactivated",
        "service-stability-v3",_billing,_generation,_metadata
    ] call ITW_CLASH_Checkbook_fnc_Response
};

/*
    Service identity is still a role-safety boundary: a truck/transport that HAL
    accidentally presents to recon execution is rejected. This does not author
    routes or maintain tactical availability arrays.
*/
[] spawn {
    scriptName "ITW_CLASH_ServiceReconExecutionGuard";
    private _deadline = time + 240;
    waitUntil {
        sleep 0.25;
        time >= _deadline || {
            !isNil "ITW_CLASH_Recon_fnc_NativeGoRecon"
            && {!isNil "HAL_GoRecon"} && {!isNil "HAL_GoDefRecon"}
        }
    };
    if (time >= _deadline) exitWith {
        ["recon-guard-timeout",[]] call ITW_CLASH_ServiceStability_fnc_Log;
    };

    ITW_CLASH_ServiceStability_fnc_GoReconBase = HAL_GoRecon;
    ITW_CLASH_ServiceStability_fnc_GoDefReconBase = HAL_GoDefRecon;

    HAL_GoRecon = {
        private _group = _this param [0,grpNull];
        if (!isNull _group && {
            [_group,vehicle leader _group] call ITW_CLASH_ServiceStability_fnc_HasLease
        }) exitWith {
            _group setVariable ["Busy" + str _group,false];
            ["execution-rejected",[
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId,"RECON","offensive"
            ]] call ITW_CLASH_ServiceStability_fnc_Log;
            false
        };
        _this call ITW_CLASH_ServiceStability_fnc_GoReconBase
    };

    HAL_GoDefRecon = {
        private _group = _this param [0,grpNull];
        if (!isNull _group && {
            [_group,vehicle leader _group] call ITW_CLASH_ServiceStability_fnc_HasLease
        }) exitWith {
            _group setVariable ["Busy" + str _group,false];
            ["execution-rejected",[
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId,"RECON","defensive"
            ]] call ITW_CLASH_ServiceStability_fnc_Log;
            false
        };
        _this call ITW_CLASH_ServiceStability_fnc_GoDefReconBase
    };

    ["recon-execution-guard-ready",[]] call ITW_CLASH_ServiceStability_fnc_Log;
};

ITW_CLASH_ServiceStabilityReady = true;
diag_log format [
    "CLASH BOOT | service-stability-ready | version=%1 passiveLifecycle=true tacticalQuarantine=false halOwnsLiveDisposition=true reconRoleGuard=true virtualEntitlement=true transportReuse=true transportBestFit=true nativeCountAuthority=true",
    ITW_CLASH_ServiceStabilityVersion
];
true