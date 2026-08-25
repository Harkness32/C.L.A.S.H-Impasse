#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ReconstitutionTransitFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_ReconstitutionTransitFixReady",false]
};
ITW_CLASH_ReconstitutionTransitFixStarted = true;
ITW_CLASH_ReconstitutionTransitFixVersion = 4;
ITW_CLASH_ReconstitutionTransitFixReady = false;
ITW_CLASH_ReconstitutionHandoffBuffer = 250;

// Once replacement infantry is physically out of its dedicated transit
// vehicle, release the lifecycle reservation. Impasse can finish removing the
// cargo bookkeeping, after which the normal Dual-HAL handoff/service lifecycle
// may adopt the now-empty transport and return/virtualize it.
ITW_CLASH_Reconstitution_fnc_ReleaseTransportReservation = {
    params ["_group",["_reason","dismounted"]];
    if (isNull _group) exitWith {false};
    private _veh = _group getVariable ["ITW_CLASH_TransitVehicle",objNull];
    if (isNull _veh || {
        !(_veh getVariable ["ITW_CLASH_ReconstitutionTransport",false])
    }) exitWith {false};

    _veh setVariable ["ITW_CLASH_ReconstitutionTransport",nil,true];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["reconstitution-transport-released",[
            _group getVariable ["ITW_CLASH_ReconstitutionRequest",""],
            _group getVariable ["ITW_CLASH_Lineage",""],
            typeOf _veh,_reason,getPosATL _veh
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

// This file is compiled synchronously from preInit immediately after
// ITW_Attack.sqf. preInit defers this one finalizer so the canonical function is
// still mutable. The corrected manager is therefore the function that becomes
// final before gameplay starts, instead of racing a final function from init.
if (isNil "ITW_AtkReconstitutionTransitManager") exitWith {
    diag_log "CLASH BOOT | FAILED | reconstitution-transit-fix-source-missing";
    false
};

if (missionNamespace getVariable ["ITW_AtkReconstitutionTransitManagerStarted",false]) exitWith {
    diag_log "CLASH BOOT | FAILED | reconstitution-transit-fix-manager-already-running";
    false
};

ITW_AtkReconstitutionTransitManager = {
    scriptName "ITW_AtkReconstitutionTransitManager";
    while {!ITW_GameOver} do {
        sleep 10;
        while {LV_PAUSE} do {sleep 5};
        while {ITW_ObjZonesUpdating} do {sleep 0.5};

        for "_i" from ((count ITW_AtkReconstitutionTransits) - 1) to 0 step -1 do {
            private _entry = ITW_AtkReconstitutionTransits#_i;
            _entry params [
                "_group","_requestId","_objectiveIndex","_archetype","_lineage",
                "_queuedAt","_createdAt","_lastAttempt","_state"
            ];

            if (isNull _group || {{alive _x} count units _group == 0}) then {
                if (!isNull _group) then {
                    [_group,"group-lost"] call ITW_CLASH_Reconstitution_fnc_ReleaseTransportReservation;
                };
                ITW_AtkReconstitutionTransits deleteAt _i;
                if (!isNil "ITW_CLASH_fnc_Log") then {
                    ["reconstitution-transit-failed",[
                        _requestId,_lineage,_objectiveIndex,"group-lost-in-transit",
                        round (time - _createdAt)
                    ]] call ITW_CLASH_fnc_Log;
                };
                continue;
            };

            _objectiveIndex = _group getVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];
            if (_objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}) then {continue};

            private _aliveUnits = units _group select {alive _x};
            private _inVehicle = _aliveUnits findIf {vehicle _x != _x} >= 0;
            private _obj = ITW_Objectives#_objectiveIndex;
            private _objPos = _obj#ITW_OBJ_POS;
            private _handoffRadius = (
                (_obj#ITW_OBJ_SIZE) +
                ITW_ParamTransportUnloadDist +
                ITW_CLASH_ReconstitutionHandoffBuffer
            );
            private _distance = leader _group distance2D _objPos;
            private _nearHandoff = !_inVehicle && {
                _state in ["transport","walking"] && {
                    _distance <= _handoffRadius
                }
            };

            // The dedicated vehicle has finished its only protected purpose as
            // soon as every replacement soldier is physically on foot. Do this
            // before waiting on Impasse cargo/assignedVehicle cleanup, so the
            // empty vehicle can enter the shared service lifecycle immediately
            // after those ownership references clear.
            if (_state isEqualTo "transport" && {!_inVehicle}) then {
                [_group,"physical-dismount"] call
                    ITW_CLASH_Reconstitution_fnc_ReleaseTransportReservation;
            };

            // Physical dismount alone is not enough for HAL handoff. Impasse's
            // vehicle manager can retain this group as cargo for another manager
            // tick, and Arma can retain assignedVehicles even after every soldier
            // is physically on foot. Preserve the original objective affinity and
            // wait until both ownership layers are clear before registration.
            private _assigned = assignedVehicles _group;
            if (_nearHandoff && {_assigned isNotEqualTo []}) then {
                {unassignVehicle _x} forEach _aliveUnits;
                _assigned = assignedVehicles _group;
            };

            private _managedVehicleIndex = -1;
            if (!isNil "ITW_ManagedVehs") then {
                _managedVehicleIndex = ITW_ManagedVehs findIf {
                    count _x > VEHINFO_CARGO_GRPS && {
                        (_x#VEHINFO_CREW_GRP) isEqualTo _group || {
                            _group in (_x#VEHINFO_CARGO_GRPS)
                        }
                    }
                };
            };
            private _handoffBlocked = _managedVehicleIndex >= 0 || {
                _assigned isNotEqualTo []
            };

            if (_nearHandoff && {_handoffBlocked}) then {
                VAR_SET_OBJ_IDX(_group,_objectiveIndex);
                private _nextWaitLog = _group getVariable [
                    "ITW_CLASH_ReconstitutionHandoffWaitLogAt",0
                ];
                if (time >= _nextWaitLog && {!isNil "ITW_CLASH_fnc_Log"}) then {
                    _group setVariable [
                        "ITW_CLASH_ReconstitutionHandoffWaitLogAt",time + 30
                    ];
                    ["reconstitution-handoff-wait",[
                        _requestId,_lineage,_objectiveIndex,_managedVehicleIndex,
                        count _assigned,round _distance
                    ]] call ITW_CLASH_fnc_Log;
                };
                continue;
            };

            if (_nearHandoff) then {
                [_group,"ao-handoff"] call ITW_CLASH_Reconstitution_fnc_ReleaseTransportReservation;
                _group setVariable ["ITW_CLASH_ReconstitutionTransit",nil];
                _group setVariable ["ITW_CLASH_TransitState",nil];
                _group setVariable ["ITW_CLASH_TransitVehicle",nil];
                _group setVariable ["ITW_CLASH_TransitObjective",nil];
                _group setVariable ["ITW_CLASH_ReconstitutionHandoffWaitLogAt",nil];
                _group setVariable ["itwInitGrp",nil,true];
                VAR_SET_OBJ_IDX(_group,_objectiveIndex);

                private _accepted = false;
                if (!isNil "ITW_CLASH_fnc_AcknowledgeReconstitution") then {
                    _accepted = [
                        _group,_requestId,_objectiveIndex,_archetype,_lineage,_queuedAt
                    ] call ITW_CLASH_fnc_AcknowledgeReconstitution;
                };
                if (!isNil "ITW_EnemyGroupCallback") then {[_group] call ITW_EnemyGroupCallback};
                if (!_accepted) then {[_group,false] spawn ITW_AtkEngageInfantry};

                if (!isNil "ITW_CLASH_fnc_Log") then {
                    ["reconstitution-transit-arrived",[
                        _requestId,_lineage,_objectiveIndex,_state,
                        count _aliveUnits,round _distance,round (time - _createdAt),_accepted,
                        round _handoffRadius
                    ]] call ITW_CLASH_fnc_Log;
                };
                ITW_AtkReconstitutionTransits deleteAt _i;
                continue;
            };

            if (_state isEqualTo "transport" && {!_inVehicle}) then {
                _state = "walking";
                _group setVariable ["ITW_CLASH_TransitState",_state];
                [_group,false] spawn ITW_AtkEngageInfantry;
                if (!isNil "ITW_CLASH_fnc_Log") then {
                    ["reconstitution-transport-interrupted",[
                        _requestId,_lineage,_objectiveIndex,round _distance
                    ]] call ITW_CLASH_fnc_Log;
                };
            };

            if (_state isEqualTo "waiting-transport" && {time - _lastAttempt >= 15}) then {
                _lastAttempt = time;

                // Dispatcher side effects are authoritative. Derive success from
                // live state instead of trusting any legacy return path.
                [
                    _group,_requestId,_objectiveIndex,_lineage
                ] call ITW_AtkDispatchReconstitutionTransport;

                private _liveState = _group getVariable ["ITW_CLASH_TransitState",""];
                private _liveVehicle = _group getVariable ["ITW_CLASH_TransitVehicle",objNull];
                private _dispatchSucceeded = _liveState isEqualTo "transport" && {
                    !isNull _liveVehicle && {alive _liveVehicle}
                };

                if (!isNil "ITW_CLASH_fnc_Log") then {
                    ["reconstitution-dispatch-state",[
                        _requestId,_lineage,_objectiveIndex,_dispatchSucceeded,
                        _liveState,
                        if (isNull _liveVehicle) then {""} else {typeOf _liveVehicle}
                    ]] call ITW_CLASH_fnc_Log;
                };

                if (_dispatchSucceeded) then {
                    _state = "transport";
                } else {
                    // Replacement infantry now starts at the forward FOB. If
                    // transport cannot be funded/created, the squad may simply
                    // walk forward after the existing grace period; there is no
                    // longer a support-corridor air-only exception to preserve.
                    if (time - _createdAt >= ITW_AtkReconstitutionTransportWait) then {
                        _state = "walking";
                        _group setVariable ["ITW_CLASH_TransitState",_state];
                        [_group,false] spawn ITW_AtkEngageInfantry;
                        if (!isNil "ITW_CLASH_fnc_Log") then {
                            ["reconstitution-transport-fallback-walk",[
                                _requestId,_lineage,_objectiveIndex,
                                round (time - _createdAt),round _distance,
                                "forward-fob"
                            ]] call ITW_CLASH_fnc_Log;
                        };
                    };
                };
            };

            _entry set [2,_objectiveIndex];
            _entry set [7,_lastAttempt];
            _entry set [8,_state];
            ITW_AtkReconstitutionTransits set [_i,_entry];
        };
    };
    ITW_AtkReconstitutionTransitManagerStarted = false;
};

isNil {
    private _deferred = missionNamespace getVariable ["ITW_CLASH_DeferredFinalizers",[]];
    _deferred = _deferred - ["ITW_AtkReconstitutionTransitManager"];
    missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];
};

private _finalized = ["ITW_AtkReconstitutionTransitManager"] call SKL_fnc_CompileFinal;
ITW_CLASH_ReconstitutionTransitFixReady = _finalized;
if (_finalized) then {
    diag_log format [
        "CLASH BOOT | reconstitution-transit-fix-ready | version=%1 handoffBuffer=%2 authoritativeState=true preInit=true vehicleOwnershipGate=true lifecycleRelease=true forwardFOBFallback=true",
        ITW_CLASH_ReconstitutionTransitFixVersion,
        ITW_CLASH_ReconstitutionHandoffBuffer
    ];
} else {
    diag_log "CLASH BOOT | FAILED | reconstitution-transit-fix-finalization";
};
_finalized