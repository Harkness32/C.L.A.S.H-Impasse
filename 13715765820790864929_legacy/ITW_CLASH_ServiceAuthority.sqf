#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ServiceAuthorityStarted",false]) exitWith {true};
ITW_CLASH_ServiceAuthorityStarted = true;
ITW_CLASH_ServiceAuthorityVersion = 4;
ITW_CLASH_ServiceAuthorityReady = false;

if (
    isNil "ITW_CLASH_Service_fnc_RegisterPhysical"
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

// RegisterPhysical v1 rewrote state/timers every time the same vehicle crossed
// a registration wrapper. Make registration idempotent. A true rematerialization
// (AVAILABLE entry with no live physical vehicle) starts a new deployment; a
// duplicate registration of the same live vehicle only refreshes safe metadata.
ITW_CLASH_ServiceAuthority_fnc_RegisterPhysicalBase = ITW_CLASH_Service_fnc_RegisterPhysical;
ITW_CLASH_Service_fnc_RegisterPhysical = {
    params ["_veh","_capability",["_mode",""],["_source","service"]];
    if (isNull _veh || {!([_capability] call ITW_CLASH_Service_fnc_IsCapability)}) exitWith {""};

    private _group = group driver _veh;
    if (isNull _group) exitWith {""};
    private _lease = [_veh] call ITW_CLASH_ServiceAuthority_fnc_GetLease;
    if (_lease isEqualTo []) then {_lease = [_group] call ITW_CLASH_ServiceAuthority_fnc_GetLease};
    if (_lease isEqualTo []) exitWith {
        ["registration-rejected",[
            typeOf _veh,side _group,toUpperANSI _capability,_source,"no-explicit-service-lease"
        ]] call ITW_CLASH_ServiceAuthority_fnc_Log;
        ""
    };

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
    private _newEntry = _index < 0;
    if (_newEntry) then {
        ITW_CLASH_ServiceSerial = ITW_CLASH_ServiceSerial + 1;
        _poolId = format ["SVC-%1-%2",round (diag_tickTime * 1000),ITW_CLASH_ServiceSerial];
        _index = count ITW_CLASH_ServicePool;
        ITW_CLASH_ServicePool pushBack createHashMap;
    };

    private _entry = ITW_CLASH_ServicePool#_index;
    private _oldVeh = _entry getOrDefault ["vehicle",objNull];
    private _sameLivePhysical = !_newEntry && {!isNull _oldVeh} && {
        _oldVeh isEqualTo _veh && {alive _oldVeh}
    };
    private _newDeployment = _newEntry || {!_sameLivePhysical};

    // Home is deployment metadata. Do not overwrite a live entry's home on a
    // duplicate registration: SeaGuard may already have corrected a ship home.
    private _home = +(_entry getOrDefault ["home",[]]);
    if (_newDeployment || {_home isEqualTo []}) then {
        _home = _group getVariable ["START" + str _group,getPosATL _veh];
        if (_home isEqualTo []) then {_home = getPosATL _veh};
        if (count _home < 3) then {_home pushBack 0};
    };

    private _vehDef = _veh getVariable ["ITW_VehDef",[]];
    _entry set ["id",_poolId];
    _entry set ["side",side _group];
    _entry set ["capability",_capability];
    _entry set ["mode",_mode];
    _entry set ["class",typeOf _veh];
    if (_vehDef isNotEqualTo []) then {_entry set ["vehDef",_vehDef]};
    _entry set ["vehicle",_veh];
    _entry set ["group",_group];
    _entry set ["source",_source];

    if (_newDeployment) then {
        _entry set ["home",+_home];
        _entry set ["state","DEPLOYED"];
        _entry set ["spawnedAt",time];
        _entry set ["everBusy",false];
        _entry set ["taskSeen",false];
        _entry set ["idleSince",-1];
        _entry set ["availableAt",0];
        _entry set ["lastDistance",_veh distance2D _home];
        _entry set ["lastProgressAt",time];
    };
    ITW_CLASH_ServicePool set [_index,_entry];

    _veh setVariable ["ITW_CLASH_ServicePoolId",_poolId,true];
    _group setVariable ["ITW_CLASH_ServicePoolId",_poolId];
    _group setVariable ["ITW_CLASH_ServiceHome",+_home];

    [if (_sameLivePhysical) then {"physical-registration-refreshed"} else {"physical-registered"},[
        _poolId,_capability,side _group,_mode,typeOf _veh,_source,+_home,
        _entry getOrDefault ["state",""],
        _entry getOrDefault ["everBusy",false],
        _entry getOrDefault ["taskSeen",false]
    ]] call ITW_CLASH_Service_fnc_Log;
    _poolId
};

// A transport lease is identity/accounting only. HAL still owns all live
// transport movement. The lease lets ServiceLifecycle virtualize the asset only
// after HAL has returned it home and it has settled idle.
ITW_CLASH_ServiceAuthority_fnc_RegisterTransportBase = ITW_CLASH_Checkbook_fnc_RegisterTransport;
ITW_CLASH_Checkbook_fnc_RegisterTransport = {
    _this params ["_veh","_crewGroup","_vehDef","_hq","_requestId",["_source","checkbook"]];
    if (!isNull _veh) then {
        [_veh,_crewGroup,"TRANSPORT","checkbook-transport"] call
            ITW_CLASH_ServiceAuthority_fnc_SetLease;
    };
    private _result = _this call ITW_CLASH_ServiceAuthority_fnc_RegisterTransportBase;
    if (!_result && {!isNull _veh}) then {
        [_veh,_crewGroup,"transport-register-failed"] call
            ITW_CLASH_ServiceAuthority_fnc_ClearLease;
    };
    _result
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

/*
    v4: a helicopter HAL calls non-combat gets the transport lease.

    Hark, 2026-10-11: "tons of helicopters hanging". Run of 20:23, mission 2:
    sixteen dual-role helicopters were handed from Impasse to HAL, and the rule
    below leased none of them, because a combat DUAL deployment bypasses the
    lifecycle. HAL gave attack orders to the ones it counts as combat aircraft.
    The unarmed Ghost Hawks it could only ever use as cargo, and nothing stored
    them, landed them or sent them anywhere:

        G242  enemy   handed over 21:24   no waypoint to the end of the log
        G304  BLUFOR  handed over 21:45   no waypoint to the end of the log
        G366  BLUFOR  handed over 22:03   shot down at 48 m at 22:32
        G504  BLUFOR  handed over 22:58   shot down at 48 m at 23:00
        G121  enemy   handed over 20:53   shot down at 48 m at 20:55

    The pure transports handed over in the same run were stored about four
    minutes after they arrived, as this lease intends (SVC-603477-2, 20:38:01).

    So the question "is this a transport" is put to HAL. HAL files every
    aircraft class it knows as armed or not: RHQ_NCAir is the unarmed subset of
    RHQ_Air (HAC_fnc2.sqf, the class autofill: armed means any magazine other
    than flares), and its situation report puts a group on RydHQ_NCAirG, the
    non-combat air list its attack and defence pools leave out, when the driver's
    vehicle class is on that list (HQSitRep.sqf:149, HAC_fnc2.sqf:470). This
    reads the same lists with the same expression. Non-combat: the helicopter
    gets exactly what a transport deployment gets here, the transport doctrine
    and the lease, and the lifecycle takes it from there. Combat: nothing
    changes. Not yet known to HAL: asked again every few seconds until it is.

    HAL's per-cycle combat lists (RydHQ_CombatAv, RydHQ_AttackAv) were not used.
    They say who is free this cycle, not what the aircraft is. In the same run
    attack helicopters first appeared on them 11 and 23 minutes after the
    handover (G119, G460); a rule built on them would have leased those.
*/
ITW_CLASH_ServiceNonCombatAirLease = missionNamespace getVariable [
    "ITW_CLASH_ServiceNonCombatAirLease",true
];
ITW_CLASH_ServiceAirVerdictWait = missionNamespace getVariable [
    "ITW_CLASH_ServiceAirVerdictWait",600
];

// "non-combat", "combat", or "" when HAL's lists do not know the class yet.
ITW_CLASH_ServiceAuthority_fnc_HALAirVerdict = {
    params ["_veh"];
    if (isNull _veh) exitWith {""};
    if (isNil "RHQ_Air" || {isNil "RHQ_NCAir"}) exitWith {""};
    private _class = toLower (typeOf _veh);
    private _ncAir = RHQ_NCAir
        + (missionNamespace getVariable ["RYD_WS_NCAir_class",[]])
        - (missionNamespace getVariable ["RHQs_NCAir",[]]);
    if (_class in _ncAir) exitWith {"non-combat"};
    private _air = RHQ_Air
        + (missionNamespace getVariable ["RYD_WS_Air_class",[]])
        - (missionNamespace getVariable ["RHQs_Air",[]]);
    if (_class in _air) exitWith {"combat"};
    ""
};

ITW_CLASH_ServiceAuthority_fnc_AwaitAirVerdict = {
    params ["_veh","_group"];
    scriptName "ITW_CLASH_ServiceAuthority_AirVerdict";
    private _startedAt = time;
    private _verdict = "";
    private _lost = false;
    while {_verdict isEqualTo "" && {time < _startedAt + ITW_CLASH_ServiceAirVerdictWait}} do {
        if (isNull _veh || {!alive _veh} || {isNull _group} || {
            ({alive _x} count units _group) == 0
        }) exitWith {_lost = true};
        _verdict = [_veh] call ITW_CLASH_ServiceAuthority_fnc_HALAirVerdict;
        if (_verdict isEqualTo "") then {sleep 5};
    };
    if (_lost) exitWith {false};

    private _id = if (isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {str _group} else {
        [_group] call ITW_CLASH_DualHAL_fnc_GroupId
    };
    private _waited = round (time - _startedAt);
    if (_verdict isEqualTo "") exitWith {
        ["air-verdict-timeout",[_id,typeOf _veh,side _group,_waited]]
            call ITW_CLASH_ServiceAuthority_fnc_Log;
        false
    };
    if (_verdict isEqualTo "combat") exitWith {
        ["air-verdict-combat",[_id,typeOf _veh,side _group,_waited]]
            call ITW_CLASH_ServiceAuthority_fnc_Log;
        false
    };
    if ([_veh] call ITW_CLASH_ServiceAuthority_fnc_HasLease) exitWith {false};

    // What StageFieldVehicle and the wrapper below give a transport
    // deployment, in the same order.
    if (!isNil "ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine") then {
        [_group,true,"hal-noncombat-air"] call
            ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine;
    };
    [_veh,_group,"TRANSPORT","hal-noncombat-air"] call
        ITW_CLASH_ServiceAuthority_fnc_SetLease;
    private _poolId = [
        _veh,"TRANSPORT",[_veh] call ITW_CLASH_Service_fnc_ModeForVehicle,"hal-noncombat-air"
    ] call ITW_CLASH_Service_fnc_RegisterPhysical;
    ["air-verdict-noncombat-leased",[_id,typeOf _veh,side _group,_waited,_poolId]]
        call ITW_CLASH_ServiceAuthority_fnc_Log;
    true
};

// Lifecycle-v1 inferred service from role. Replace that field-handoff boundary:
// combat DUAL deployments bypass the lifecycle wrapper entirely; pure transport
// and explicitly DUAL-as-transport deployments carry an explicit lease first.
ITW_CLASH_ServiceAuthority_fnc_StageFieldVehicleLifecycleBase = ITW_CLASH_DualHAL_fnc_StageFieldVehicle;
ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {
    params ["_vehInfo",["_teleportToAttackPos",false],["_populateObjectives",false]];
    private _result = _this call ITW_CLASH_ServiceAuthority_fnc_StageFieldVehicleLifecycleBase;

    if (_result && {_vehInfo isEqualType []} && {count _vehInfo > VEHINFO_IS_DUAL_AS_TRANSPORT}) then {
        private _veh = _vehInfo#VEHINFO_VEH;
        private _group = _vehInfo#VEHINFO_CREW_GRP;
        private _role = _vehInfo#VEHINFO_ROLE;
        private _dualAsTransport = _vehInfo param [VEHINFO_IS_DUAL_AS_TRANSPORT,false];
        private _transportDeployment = _role == ITW_VEH_ROLE_TRANSPORT || {
            _role == ITW_VEH_ROLE_DUAL && {_dualAsTransport}
        };

        // Preserve native Impasse's per-deployment DUAL transport disarm rule.
        if (!isNull _veh && {_role == ITW_VEH_ROLE_DUAL} && {_dualAsTransport}) then {
            [_veh,0] remoteExec ["setVehicleAmmo",_veh];
        };

        // Enroll the already-completed HAL handoff in the passive pool. This
        // does not clear or author any waypoint and therefore cannot race SCargo.
        if (_transportDeployment && {!isNull _veh} && {!isNull _group}) then {
            [_veh,_group,"TRANSPORT","impasse-handoff"] call
                ITW_CLASH_ServiceAuthority_fnc_SetLease;
            [_veh,"TRANSPORT",[_veh] call ITW_CLASH_Service_fnc_ModeForVehicle,"impasse-handoff"] call
                ITW_CLASH_Service_fnc_RegisterPhysical;
        };

        // v4: any other helicopter is a transport if HAL says it cannot fight.
        if (
            ITW_CLASH_ServiceNonCombatAirLease
            && {!_transportDeployment}
            && {!isNull _veh} && {!isNull _group}
            && {_veh isKindOf "Helicopter"}
        ) then {
            [_veh,_group] spawn ITW_CLASH_ServiceAuthority_fnc_AwaitAirVerdict;
        };
    };
    _result
};

ITW_CLASH_ServiceAuthorityReady = true;
diag_log format [
    "CLASH BOOT | service-authority-ready | version=%1 explicitLease=true transportVirtualization=true logisticsVirtualization=true sharedVehDefImmutable=true idempotentRegistration=true staleStagePrerequisiteRemoved=true nonCombatAirLease=%2 airVerdictWait=%3s airVerdictFrom=RHQ_NCAir",
    ITW_CLASH_ServiceAuthorityVersion,
    ITW_CLASH_ServiceNonCombatAirLease,
    ITW_CLASH_ServiceAirVerdictWait
];
true