#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ServiceAuthorityStarted",false]) exitWith {true};
ITW_CLASH_ServiceAuthorityStarted = true;
ITW_CLASH_ServiceAuthorityVersion = 1;
ITW_CLASH_ServiceAuthorityReady = false;

if (
    isNil "ITW_CLASH_Service_fnc_RegisterPhysical"
    || {isNil "ITW_CLASH_Service_fnc_StageFieldVehicleBase"}
    || {isNil "ITW_CLASH_Checkbook_fnc_RegisterTransport"}
    || {isNil "ITW_CLASH_Generation_fnc_RegisterAsset"}
) exitWith {
    diag_log "CLASH BOOT | WARNING | service-authority-source-missing";
    false
};

ITW_CLASH_ServiceAuthority_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["service-authority-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH SERVICE AUTHORITY | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_ServiceAuthority_fnc_SetLease = {
    params ["_veh",["_group",grpNull],"_capability",["_source","explicit"]];
    if (isNull _veh) exitWith {[]};
    _capability = toUpperANSI _capability;
    if (!isNil "ITW_CLASH_Service_fnc_IsCapability" && {
        !([_capability] call ITW_CLASH_Service_fnc_IsCapability)
    }) exitWith {[]};
    if (isNull _group) then {_group = group driver _veh};
    private _lease = [_capability,_source,time];
    _veh setVariable ["ITW_CLASH_ServiceLease",+_lease,true];
    if (!isNull _group) then {
        _group setVariable ["ITW_CLASH_ServiceLease",+_lease];
    };
    _lease
};

ITW_CLASH_ServiceAuthority_fnc_ClearLease = {
    params ["_veh",["_group",grpNull],["_reason","clear"]];
    if (isNull _group && {!isNull _veh}) then {_group = group driver _veh};
    if (!isNull _veh) then {_veh setVariable ["ITW_CLASH_ServiceLease",nil,true]};
    if (!isNull _group) then {_group setVariable ["ITW_CLASH_ServiceLease",nil]};
    true
};

ITW_CLASH_ServiceAuthority_fnc_GetLease = {
    params ["_subject"];
    if (_subject isEqualType objNull) exitWith {
        if (isNull _subject) then {[]} else {
            +(_subject getVariable ["ITW_CLASH_ServiceLease",[]])
        }
    };
    if (_subject isEqualType grpNull) exitWith {
        if (isNull _subject) then {[]} else {
            +(_subject getVariable ["ITW_CLASH_ServiceLease",[]])
        }
    };
    []
};

ITW_CLASH_ServiceAuthority_fnc_HasLease = {
    private _lease = [_this param [0,objNull]] call ITW_CLASH_ServiceAuthority_fnc_GetLease;
    _lease isEqualType [] && {count _lease >= 3} && {
        !isNil "ITW_CLASH_Service_fnc_IsCapability" && {
            [_lease#0] call ITW_CLASH_Service_fnc_IsCapability
        }
    }
};

// Explicit Checkbook transport demand creates the lease before lifecycle-v1's
// RegisterTransport wrapper calls RegisterPhysical.
ITW_CLASH_ServiceAuthority_fnc_RegisterTransportBase = ITW_CLASH_Checkbook_fnc_RegisterTransport;
ITW_CLASH_Checkbook_fnc_RegisterTransport = {
    _this params ["_veh","_crewGroup","_vehDef","_hq","_requestId",["_source","checkbook"]];
    if (!isNull _veh) then {
        [_veh,_crewGroup,"TRANSPORT","checkbook-transport"] call
            ITW_CLASH_ServiceAuthority_fnc_SetLease;
    };
    _this call ITW_CLASH_ServiceAuthority_fnc_RegisterTransportBase
};

// Logistics registration is also an explicit service request. Artillery never
// receives a service lease and remains persistent/combat-accounted.
ITW_CLASH_ServiceAuthority_fnc_RegisterGeneratedBase = ITW_CLASH_Generation_fnc_RegisterAsset;
ITW_CLASH_Generation_fnc_RegisterAsset = {
    _this params ["_veh","_group","_hq","_capability"];
    if (!isNull _veh && {
        (toUpperANSI _capability) in ["LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"]
    }) then {
        [_veh,_group,_capability,"checkbook-logistics"] call
            ITW_CLASH_ServiceAuthority_fnc_SetLease;
    };
    _this call ITW_CLASH_ServiceAuthority_fnc_RegisterGeneratedBase
};

// Lifecycle-v1 inferred service from role. Replace that field-handoff boundary:
// combat DUAL deployments bypass the lifecycle wrapper entirely; pure transport
// and explicitly DUAL-as-transport deployments carry an explicit lease first.
ITW_CLASH_ServiceAuthority_fnc_StageFieldVehicleLifecycleBase = ITW_CLASH_DualHAL_fnc_StageFieldVehicle;
ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {
    params ["_vehInfo",["_teleportToAttackPos",false],["_populateObjectives",false]];
    if !(_vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CARGO_GRPS}) exitWith {false};

    private _veh = _vehInfo#VEHINFO_VEH;
    private _group = _vehInfo#VEHINFO_CREW_GRP;
    private _role = _vehInfo#VEHINFO_ROLE;
    private _dualAsTransport = _vehInfo param [VEHINFO_IS_DUAL_AS_TRANSPORT,false];
    private _transportDeployment = _role == ITW_VEH_ROLE_TRANSPORT || {
        _role == ITW_VEH_ROLE_DUAL && {_dualAsTransport}
    };

    if (_transportDeployment && {!isNull _veh}) then {
        [_veh,_group,"TRANSPORT","impasse-handoff"] call
            ITW_CLASH_ServiceAuthority_fnc_SetLease;
    };

    private _result = if (_role == ITW_VEH_ROLE_DUAL && {!_dualAsTransport}) then {
        // Bypass ServiceLifecycle v1's broad DUAL enrollment. Its saved base is
        // the already-hardened DualHAL handoff. That older base also classified
        // all DUAL as cargo, so remove only those service-only memberships after
        // the handoff; HAL can then classify the asset normally as combat-capable.
        private _handled = _this call ITW_CLASH_Service_fnc_StageFieldVehicleBase;
        if (_handled && {!isNull _veh}) then {
            [_veh,_group,"dual-combat-handoff"] call ITW_CLASH_ServiceAuthority_fnc_ClearLease;
            if (!isNull _group) then {
                private _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
                if (!isNull _hq) then {
                    {
                        private _members = +(_hq getVariable [_x,[]]);
                        _hq setVariable [_x,_members - [_group]];
                    } forEach [
                        "RydHQ_CargoG","RydHQ_CargoOnly",
                        "RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"
                    ];
                };
                _group setVariable ["ITW_CLASH_CapExempt",nil];
                _group setVariable ["ITW_CLASH_ServiceAsset",nil];
                _group setVariable ["ITW_CLASH_ServiceCapability",nil];
            };
            _veh setVariable ["ITW_CLASH_ServiceAsset",nil,true];
            _veh setVariable ["ITW_CLASH_ServiceCapability",nil,true];
        };
        _handled
    } else {
        _this call ITW_CLASH_ServiceAuthority_fnc_StageFieldVehicleLifecycleBase
    };

    // The suppressed native Impasse writer disarms DUAL only when this exact
    // deployment is DUAL-as-transport. Reproduce that per-deployment policy.
    if (_result && {!isNull _veh} && {
        _role == ITW_VEH_ROLE_DUAL && {_dualAsTransport}
    }) then {
        [_veh,0] remoteExec ["setVehicleAmmo",_veh];
    };

    if (_result) then {
        ["handoff-classified",[
            if (isNull _group) then {"<null>"} else {
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId
            },
            if (isNull _veh) then {"<null>"} else {typeOf _veh},
            _role,_dualAsTransport,
            if (_transportDeployment) then {
                if (_role == ITW_VEH_ROLE_DUAL) then {"DUAL_TRANSPORT_LEASE"} else {"PURE_TRANSPORT"}
            } else {"COMBAT"}
        ]] call ITW_CLASH_ServiceAuthority_fnc_Log;
    };
    _result
};

ITW_CLASH_ServiceAuthorityReady = true;
diag_log format [
    "CLASH BOOT | service-authority-ready | version=%1 explicitLease=true sharedVehDefImmutable=true dualDeploymentAware=true",
    ITW_CLASH_ServiceAuthorityVersion
];
true
