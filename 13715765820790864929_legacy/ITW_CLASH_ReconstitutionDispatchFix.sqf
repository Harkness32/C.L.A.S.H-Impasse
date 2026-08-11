#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_ReconstitutionDispatchFixStarted",false]) exitWith {};
ITW_CLASH_ReconstitutionDispatchFixStarted = true;

// ITW_Attack.sqf owns transport selection, spawn, loading, ticket charging and
// vehicle registration. Its V6 dispatcher used a named breakOut that could leave
// the trailing `_dispatched` expression outside the private variable's live scope,
// producing a nil return plus `Undefined variable ... _dispatched` after an
// otherwise successful dispatch. init.sqf defers only this function's finalizer
// while this source-equivalent correction is installed.
waitUntil {
    sleep 0.1;
    !isNil "ITW_AtkDispatchReconstitutionTransport" && {
        !isNil "ITW_AtkDeliveryCntChange"
    }
};
sleep 0.1;

ITW_AtkDispatchReconstitutionTransport = {
    params ["_group","_requestId","_objectiveIndex","_lineage"];
    if (!isServer || {isNull _group}) exitWith {false};
    if (ITW_AtkReconstitutionTransportContext isEqualTo []) exitWith {false};

    ITW_AtkReconstitutionTransportContext params [
        "_transport","_dualVeh","_crewTypes","_unitTypes","_side"
    ];
    if (side _group != _side) exitWith {false};

    private _corridor = [_objectiveIndex] call ITW_CLASH_fnc_GetSupportCorridorSpawn;
    if (_corridor isEqualTo []) exitWith {false};
    private _baseIndex = _corridor#3;
    private _spawnPt = +(_corridor#0);
    private _spawnSource = _corridor#2;

    if (_baseIndex >= 0 && {_baseIndex < count ITW_Objectives}) then {
        private _vehicleSpawn = +(ITW_Objectives#_baseIndex#ITW_OBJ_V_SPAWN);
        if (_vehicleSpawn isNotEqualTo []) then {
            _spawnPt = _vehicleSpawn;
            _spawnSource = _spawnSource + "-vehicle-staging";
        };
    };
    if (count _spawnPt < 3) then {_spawnPt pushBack 0};

    private _members = units _group select {alive _x};
    if (_members isEqualTo []) exitWith {false};
    private _requiredSeats = count _members;

    private _candidates = (_transport + _dualVeh) select {
        private _vehDef = _x;
        private _type = _vehDef#ITW_VEH_TYPE;
        _type != ITW_TYPE_VEH_SHIP && {
            (_vehDef#ITW_VEH_REQD_TICKETS) <= (_vehDef#ITW_VEH_CURR_TICKETS) && {
                (_vehDef#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT || {
                    (_vehDef#ITW_VEH_COUNT) < (_vehDef#ITW_VEH_MAX)
                }
            }
        }
    };
    if (_candidates isEqualTo []) exitWith {false};

    private _routeDistance = _spawnPt distance2D ((ITW_Objectives#_objectiveIndex)#ITW_OBJ_POS);
    private _airRoute = (_spawnSource find "support-corridor-air") == 0;
    private _preferAir = _airRoute || {_routeDistance > 2500};
    private _preferred = _candidates select {
        private _type = _x#ITW_VEH_TYPE;
        if (_preferAir) then {ITW_VEH_IS_AIR(_type)} else {ITW_VEH_IS_LAND(_type)}
    };
    private _ordered = if (_airRoute) then {
        +_preferred
    } else {
        _preferred + (_candidates - _preferred)
    };

    private _dispatched = false;
    for "_candidateIndex" from 0 to ((count _ordered) - 1) do {
        if (_dispatched) then {continue};

        private _vehDef = _ordered#_candidateIndex;
        private _veh = [_vehDef,_crewTypes,_unitTypes,_side,_spawnPt] call ITW_AtkSpawnVeh;
        if (isNull _veh) then {continue};

        private _crewGroup = group driver _veh;
        private _availableSeats = _veh emptyPositions "";
        if (_availableSeats < _requiredSeats) then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
            continue;
        };

        private _loaded = true;
        {
            if !(_x moveInAny _veh) then {_loaded = false};
        } forEach _members;
        if (!_loaded || {_members findIf {vehicle _x != _veh} >= 0}) then {
            {
                if (vehicle _x == _veh) then {
                    unassignVehicle _x;
                    moveOut _x;
                };
            } forEach _members;
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
            continue;
        };

        _group setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];
        _group setVariable ["ITW_CLASH_TransitVehicle",_veh];
        _group setVariable ["ITW_CLASH_TransitState","transport"];
        _group setVariable ["ITW_CLASH_ReconstitutionSupportBase",_baseIndex];
        _group setVariable ["ITW_CLASH_ReconstitutionSpawnSource",_spawnSource];
        _crewGroup setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];

        private _vehInfo = [
            _vehDef#ITW_VEH_TYPE,
            _vehDef#ITW_VEH_ROLE,
            _veh,
            _crewGroup,
            [_group],
            getPosATL _veh,
            _vehDef#ITW_VEH_IS_DUAL_AS_TRANSPORT
        ];
        [_vehInfo,false,false] call ITW_AtkAddVehicle;

        ITW_TICKET_SEM_CHECK;
        ITW_VEH_COUNT_INCR(_vehDef);
        _veh setVariable ["ITW_VehDef",_vehDef];
        ITW_TICKET_SEM_CHECK;
        ITW_TICKET_REDUCE(_vehDef);

        private _hcIDs = allPlayers select {_x isKindOf "HeadlessClient_F"} apply {owner _x};
        _hcIDs pushBack 2;
        [_veh] remoteExec ["ITW_AtkUnloadProtect",_hcIDs];
        {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;
        if (!isNil "ITW_EnemyGroupCallback") then {[_crewGroup] call ITW_EnemyGroupCallback};

        if (!isNil "ITW_CLASH_fnc_Log") then {
            ["reconstitution-transport-dispatched",[
                _requestId,_lineage,_objectiveIndex,_baseIndex,_spawnSource,
                typeOf _veh,_requiredSeats,_vehDef#ITW_VEH_TYPE,round _routeDistance,
                if (_preferAir) then {"air-preferred"} else {"land-preferred"}
            ]] call ITW_CLASH_fnc_Log;
        };
        _dispatched = true;
    };

    private _vehicle = _group getVariable ["ITW_CLASH_TransitVehicle",objNull];
    private _state = _group getVariable ["ITW_CLASH_TransitState",""];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["reconstitution-dispatch-return",[
            _requestId,_lineage,_objectiveIndex,_dispatched,_state,
            if (isNull _vehicle) then {""} else {typeOf _vehicle}
        ]] call ITW_CLASH_fnc_Log;
    };
    _dispatched
};

private _deferred = missionNamespace getVariable ["ITW_CLASH_DeferredFinalizers",[]];
_deferred = _deferred - ["ITW_AtkDispatchReconstitutionTransport"];
missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];

private _finalized = ["ITW_AtkDispatchReconstitutionTransport"] call SKL_fnc_CompileFinal;
if (_finalized) then {
    diag_log "CLASH BOOT | reconstitution-dispatch-fix-ready | version=2 source-corrected=true";
} else {
    diag_log "CLASH BOOT | FAILED | reconstitution-dispatch-fix-finalization";
};
