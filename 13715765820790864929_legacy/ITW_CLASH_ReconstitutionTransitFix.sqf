#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ReconstitutionTransitFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_ReconstitutionTransitFixReady",false]
};
ITW_CLASH_ReconstitutionTransitFixStarted = true;
ITW_CLASH_ReconstitutionTransitFixVersion = 3;
ITW_CLASH_ReconstitutionTransitFixReady = false;
ITW_CLASH_ReconstitutionHandoffBuffer = 250;

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

            if (!_inVehicle && {
                _state in ["transport","walking"] && {
                    _distance <= _handoffRadius
                }
            }) then {
                _group setVariable ["ITW_CLASH_ReconstitutionTransit",nil];
                _group setVariable ["ITW_CLASH_TransitState",nil];
                _group setVariable ["ITW_CLASH_TransitVehicle",nil];
                _group setVariable ["ITW_CLASH_TransitObjective",nil];
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
                    private _corridor = [_objectiveIndex] call ITW_CLASH_fnc_GetSupportCorridorSpawn;
                    private _airOnly = _corridor isNotEqualTo [] && {
                        ((_corridor#2) find "support-corridor-air") == 0
                    };
                    if (!_airOnly && {
                        time - _createdAt >= ITW_AtkReconstitutionTransportWait
                    }) then {
                        _state = "walking";
                        _group setVariable ["ITW_CLASH_TransitState",_state];
                        [_group,false] spawn ITW_AtkEngageInfantry;
                        if (!isNil "ITW_CLASH_fnc_Log") then {
                            ["reconstitution-transport-fallback-walk",[
                                _requestId,_lineage,_objectiveIndex,
                                round (time - _createdAt),round _distance
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
        "CLASH BOOT | reconstitution-transit-fix-ready | version=%1 handoffBuffer=%2 authoritativeState=true preInit=true",
        ITW_CLASH_ReconstitutionTransitFixVersion,
        ITW_CLASH_ReconstitutionHandoffBuffer
    ];
} else {
    diag_log "CLASH BOOT | FAILED | reconstitution-transit-fix-finalization";
};
_finalized
