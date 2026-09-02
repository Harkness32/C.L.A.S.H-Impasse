#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerDemandDispatchStarted",false]) exitWith {true};

ITW_CLASH_PlayerDemandDispatchStarted = true;
ITW_CLASH_PlayerDemandDispatchReady = false;
ITW_CLASH_PlayerDemandDispatchVersion = 1;
ITW_CLASH_PlayerDemands = createHashMap;
ITW_CLASH_PlayerDemandNextId = 0;
ITW_CLASH_PlayerDemandPoll = 1;
ITW_CLASH_PlayerDemandMedevacPickupRadius = 35;
ITW_CLASH_PlayerDemandMedevacHomeRadius = 125;
ITW_CLASH_PlayerDemandMedevacDeliveredCooldown = 900;

ITW_CLASH_PlayerDemand_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_Log") then {
        ["demand-" + _event,_payload] call ITW_CLASH_PlayerTasks_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER DEMAND | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerDemand_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_DualHAL_fnc_GroupId
    };
    private _id = groupId _group;
    if (_id isEqualTo "") then {str _group} else {_id}
};

ITW_CLASH_PlayerDemand_fnc_TargetGroup = {
    params ["_target"];
    if (isNull _target) exitWith {grpNull};
    if (_target isKindOf "Man") exitWith {group _target};
    private _commander = effectiveCommander _target;
    if (isNull _commander) exitWith {grpNull};
    group _commander
};

ITW_CLASH_PlayerDemand_fnc_HumanGroupAlive = {
    params ["_group"];
    !isNull _group && {
        (units _group findIf {alive _x && {isPlayer _x}}) >= 0
    }
};

ITW_CLASH_PlayerDemand_fnc_Get = {
    params ["_demandId"];
    ITW_CLASH_PlayerDemands getOrDefault [_demandId,createHashMap]
};

ITW_CLASH_PlayerDemand_fnc_FindBySourceKey = {
    params ["_sourceKey"];
    private _found = "";
    {
        private _demand = ITW_CLASH_PlayerDemands getOrDefault [_x,createHashMap];
        if (count _demand == 0) then {continue};
        if ((_demand getOrDefault ["sourceKey",""]) != _sourceKey) then {continue};
        if ((_demand getOrDefault ["state",""]) in ["COMPLETED","INVALID","FAILED"]) then {continue};
        _found = _x;
        break;
    } forEach (keys ITW_CLASH_PlayerDemands);
    _found
};

ITW_CLASH_PlayerDemand_fnc_Publish = {
    params [
        "_channel","_kind","_sourceKey","_hq","_target","_title",
        "_description","_requirement",["_destination",[]]
    ];
    if (isNull _hq || {isNull _target} || {_sourceKey isEqualTo ""}) exitWith {""};

    private _existingId = [_sourceKey] call ITW_CLASH_PlayerDemand_fnc_FindBySourceKey;
    if (_existingId isNotEqualTo "") exitWith {
        private _existing = [_existingId] call ITW_CLASH_PlayerDemand_fnc_Get;
        _existing set ["target",_target];
        _existing set ["targetGroup",[_target] call ITW_CLASH_PlayerDemand_fnc_TargetGroup];
        _existing set ["description",_description];
        _existing set ["requirement",_requirement];
        _existing set ["destination",+_destination];
        _existing set ["lastSeenAt",time];
        ITW_CLASH_PlayerDemands set [_existingId,_existing];
        _existingId
    };

    ITW_CLASH_PlayerDemandNextId = ITW_CLASH_PlayerDemandNextId + 1;
    private _demandId = format [
        "CLASH-DEMAND-%1-%2-%3",
        _channel,ITW_CLASH_PlayerDemandNextId,round (diag_tickTime * 1000)
    ];
    private _demand = createHashMapFromArray [
        ["id",_demandId],
        ["channel",toUpperANSI _channel],
        ["kind",_kind],
        ["sourceKey",_sourceKey],
        ["hq",_hq],
        ["target",_target],
        ["targetGroup",[_target] call ITW_CLASH_PlayerDemand_fnc_TargetGroup],
        ["title",_title],
        ["description",_description],
        ["requirement",_requirement],
        ["destination",+_destination],
        ["state","OPEN"],
        ["createdAt",time],
        ["lastSeenAt",time],
        ["reservedGroup",grpNull],
        ["reservedAt",-1],
        ["executionJobId",""],
        ["taskId",""],
        ["declinedGroups",[]],
        ["suppressionArray",""],
        ["suppressionOwned",false],
        ["lastPreparingLogAt",0],
        ["lastHomeResolveAt",0]
    ];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    ["player-demand-published",[
        _demandId,_channel,_kind,
        [(_demand get "targetGroup")] call ITW_CLASH_PlayerDemand_fnc_GroupId,
        _requirement
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    _demandId
};

ITW_CLASH_PlayerDemand_fnc_SetState = {
    params ["_demandId","_state",["_reason",""]];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {false};
    _demand set ["state",_state];
    _demand set ["stateAt",time];
    _demand set ["stateReason",_reason];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    true
};

ITW_CLASH_PlayerDemand_fnc_ApplySuppression = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {false};
    private _hq = _demand getOrDefault ["hq",grpNull];
    private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _hq || {isNull _targetGroup}) exitWith {false};

    private _kind = _demand getOrDefault ["kind",""];
    private _arrayName = switch (_kind) do {
        case "LOGISTICS_AMMO": {"RydHQ_ASupportedG"};
        case "MEDEVAC_SEVERE": {"RydHQ_SupportedG"};
        default {""};
    };
    if (_arrayName isEqualTo "") exitWith {true};

    private _entries = +(_hq getVariable [_arrayName,[]]);
    private _owned = !(_targetGroup in _entries);
    if (_owned) then {
        _entries pushBack _targetGroup;
        _hq setVariable [_arrayName,_entries];
    };
    _demand set ["suppressionArray",_arrayName];
    _demand set ["suppressionOwned",_owned];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    ["player-demand-native-suppressed",[
        _demandId,_arrayName,
        [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId,
        _owned
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    true
};

ITW_CLASH_PlayerDemand_fnc_RestoreSuppression = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {false};
    private _hq = _demand getOrDefault ["hq",grpNull];
    private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
    private _arrayName = _demand getOrDefault ["suppressionArray",""];
    private _owned = _demand getOrDefault ["suppressionOwned",false];

    if (_owned && {_arrayName isNotEqualTo ""} && {!isNull _hq} && {!isNull _targetGroup}) then {
        private _entries = +(_hq getVariable [_arrayName,[]]);
        _hq setVariable [_arrayName,_entries - [_targetGroup]];
    };
    if (_arrayName isNotEqualTo "") then {
        ["player-demand-native-restored",[
            _demandId,_arrayName,
            if (isNull _targetGroup) then {"<null>"} else {
                [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
            },_owned
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    };
    _demand set ["suppressionArray",""];
    _demand set ["suppressionOwned",false];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    true
};

ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty = {
    params ["_unit"];
    !isNull _unit && {alive _unit} && {
        (damage _unit) > 0.75 || {!canStand _unit}
    }
};

ITW_CLASH_PlayerDemand_fnc_StillValid = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {false};
    private _state = _demand getOrDefault ["state",""];
    if (_state in ["COMPLETED","INVALID","FAILED"]) exitWith {false};

    private _hq = _demand getOrDefault ["hq",grpNull];
    private _target = _demand getOrDefault ["target",objNull];
    private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _hq || {isNull _target} || {isNull _targetGroup}) exitWith {false};

    private _kind = _demand getOrDefault ["kind",""];
    switch (_kind) do {
        case "LOGISTICS_AMMO": {
            if (!alive _target) exitWith {false};
            private _hollow = +(_hq getVariable ["RydHQ_Hollow",[]]);
            private _needed = (_hollow findIf {
                !isNull _x && {([_x] call ITW_CLASH_PlayerDemand_fnc_TargetGroup) == _targetGroup}
            }) >= 0;
            if (!_needed) exitWith {false};
            if (_state == "OPEN" && {
                _targetGroup in (_hq getVariable ["RydHQ_ASupportedG",[]])
            }) exitWith {false};
            true
        };
        case "MEDEVAC_SEVERE": {
            private _severe = (units _targetGroup findIf {
                [_x] call ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty
            }) >= 0;
            if (!_severe) exitWith {false};
            private _deliveredAt = _targetGroup getVariable [
                "ITW_CLASH_PlayerMedevacDeliveredAt",-1
            ];
            if (_deliveredAt >= 0 && {
                time - _deliveredAt < ITW_CLASH_PlayerDemandMedevacDeliveredCooldown
            }) exitWith {false};
            if (_state == "OPEN" && {
                _targetGroup in (_hq getVariable ["RydHQ_SupportedG",[]])
            }) exitWith {false};
            true
        };
        default {true};
    }
};

ITW_CLASH_PlayerDemand_fnc_TaskPlayers = {
    params ["_group"];
    if (isNull _group) exitWith {[]};
    units _group select {alive _x && {isPlayer _x}}
};

ITW_CLASH_PlayerDemand_fnc_CreateTask = {
    params ["_demandId","_group"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0 || {isNull _group}) exitWith {""};
    private _players = [_group] call ITW_CLASH_PlayerDemand_fnc_TaskPlayers;
    if (_players isEqualTo []) exitWith {""};

    private _taskId = format ["ITW_%1",_demandId];
    private _title = _demand getOrDefault ["title","HAL Employment"];
    private _requirement = _demand getOrDefault ["requirement",""];
    private _description = _demand getOrDefault ["description",""];
    private _full = if (_requirement isEqualTo "") then {_description} else {
        _description + "\n\nPREPARATION: " + _requirement +
        "\n\nAcquire what you need to execute the mission, or use Cancel Current HAL Job to release it."
    };
    private _destination = +(_demand getOrDefault ["destination",[]]);
    private _target = _demand getOrDefault ["target",objNull];
    private _taskDestination = if (_destination isNotEqualTo []) then {_destination} else {_target};

    [
        _players,_taskId,[_full,_title,""],_taskDestination,
        "ASSIGNED",1,true,"move",true
    ] call BIS_fnc_taskCreate;
    _taskId
};

ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {grpNull};
    private _channel = _demand getOrDefault ["channel",""];
    private _declined = +(_demand getOrDefault ["declinedGroups",[]]);
    private _found = grpNull;
    {
        if (isNull _x || {_x in _declined}) then {continue};
        if ([_x,_channel] call ITW_CLASH_PlayerTasks_fnc_CanAcceptJob) exitWith {
            _found = _x;
        };
    } forEach +ITW_CLASH_PlayerTaskGroups;
    _found
};

ITW_CLASH_PlayerDemand_fnc_Reserve = {
    params ["_demandId","_group"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0 || {isNull _group}) exitWith {false};
    if ((_demand getOrDefault ["state",""]) != "OPEN") exitWith {false};
    if !([_demandId] call ITW_CLASH_PlayerDemand_fnc_StillValid) exitWith {false};
    private _channel = _demand getOrDefault ["channel",""];
    if !([_group,_channel] call ITW_CLASH_PlayerTasks_fnc_CanAcceptJob) exitWith {false};

    private _taskId = [_demandId,_group] call ITW_CLASH_PlayerDemand_fnc_CreateTask;
    if (_taskId isEqualTo "") exitWith {false};

    _demand set ["state","RESERVED"];
    _demand set ["reservedGroup",_group];
    _demand set ["reservedAt",time];
    _demand set ["taskId",_taskId];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    [_demandId] call ITW_CLASH_PlayerDemand_fnc_ApplySuppression;

    private _busyName = "Busy" + str _group;
    private _alreadyBusy = _group getVariable [_busyName,false];
    _group setVariable ["ITW_CLASH_PlayerDemandOwnsBusy",!_alreadyBusy];
    _group setVariable [_busyName,true];
    _group setVariable ["ITW_CLASH_PlayerDemandJobId",_demandId,true];
    _group setVariable ["ITW_CLASH_PlayerDemandCancel",false,true];
    [_group,"demand-reserved"] call ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;

    ["player-demand-reserved",[
        _demandId,_channel,_demand getOrDefault ["kind",""],
        [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId,
        _demand getOrDefault ["requirement",""]
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    true
};

ITW_CLASH_PlayerDemand_fnc_ClearGroupReservation = {
    params ["_group","_demandId"];
    if (isNull _group) exitWith {false};
    if ((_group getVariable ["ITW_CLASH_PlayerDemandJobId",""]) == _demandId) then {
        _group setVariable ["ITW_CLASH_PlayerDemandJobId",nil,true];
        _group setVariable ["ITW_CLASH_PlayerDemandCancel",nil,true];
    };
    if (_group getVariable ["ITW_CLASH_PlayerDemandOwnsBusy",false]) then {
        _group setVariable ["Busy" + str _group,false];
    };
    _group setVariable ["ITW_CLASH_PlayerDemandOwnsBusy",nil];
    [_group,"demand-released"] call ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
    true
};

ITW_CLASH_PlayerDemand_fnc_Release = {
    params ["_demandId",["_reason","released"],["_declined",false]];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {false};
    private _group = _demand getOrDefault ["reservedGroup",grpNull];
    private _taskId = _demand getOrDefault ["taskId",""];
    if (_taskId isNotEqualTo "") then {
        [_taskId,"CANCELED",false] call BIS_fnc_taskSetState;
    };

    if (_declined && {!isNull _group}) then {
        private _declinedGroups = +(_demand getOrDefault ["declinedGroups",[]]);
        _declinedGroups pushBackUnique _group;
        _demand set ["declinedGroups",_declinedGroups];
        ITW_CLASH_PlayerDemands set [_demandId,_demand];
    };

    [_demandId] call ITW_CLASH_PlayerDemand_fnc_RestoreSuppression;
    if (!isNull _group) then {
        [_group,_demandId] call ITW_CLASH_PlayerDemand_fnc_ClearGroupReservation;
    };

    private _valid = [_demandId] call ITW_CLASH_PlayerDemand_fnc_StillValid;
    _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    _demand set ["reservedGroup",grpNull];
    _demand set ["reservedAt",-1];
    _demand set ["executionJobId",""];
    _demand set ["taskId",""];
    _demand set ["state",if (_valid) then {"OPEN"} else {"INVALID"}];
    _demand set ["stateReason",_reason];
    _demand set ["stateAt",time];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];

    [if (_valid) then {"player-demand-released"} else {"player-demand-invalidated"},[
        _demandId,_reason,
        if (isNull _group) then {"<null>"} else {
            [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId
        },_declined
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    true
};

ITW_CLASH_PlayerDemand_fnc_Complete = {
    params ["_demandId",["_reason","completed"]];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {false};
    private _group = _demand getOrDefault ["reservedGroup",grpNull];
    private _taskId = _demand getOrDefault ["taskId",""];
    if (_taskId isNotEqualTo "") then {
        [_taskId,"SUCCEEDED",false] call BIS_fnc_taskSetState;
    };
    [_demandId] call ITW_CLASH_PlayerDemand_fnc_RestoreSuppression;
    if (!isNull _group) then {
        [_group,_demandId] call ITW_CLASH_PlayerDemand_fnc_ClearGroupReservation;
    };
    _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    _demand set ["state","COMPLETED"];
    _demand set ["stateReason",_reason];
    _demand set ["stateAt",time];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    ["player-demand-completed",[_demandId,_reason]] call ITW_CLASH_PlayerDemand_fnc_Log;
    true
};

ITW_CLASH_PlayerDemand_fnc_DispatchOpen = {
    {
        private _demandId = _x;
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if ((_demand getOrDefault ["state",""]) != "OPEN") then {continue};
        if !([_demandId] call ITW_CLASH_PlayerDemand_fnc_StillValid) then {
            [_demandId,"open-demand-no-longer-valid",false] call
                ITW_CLASH_PlayerDemand_fnc_Release;
            continue;
        };
        private _group = [_demandId] call ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup;
        if (!isNull _group) then {
            [_demandId,_group] call ITW_CLASH_PlayerDemand_fnc_Reserve;
        };
    } forEach (keys ITW_CLASH_PlayerDemands);
};

ITW_CLASH_PlayerDemand_fnc_FindAmmoPackage = {
    params ["_hq","_vehicle"];
    if (isNull _hq || {isNull _vehicle}) exitWith {objNull};
    private _packages = if (!isNil "ITW_CLASH_PlayerTasks_fnc_OutstandingPackages") then {
        [_hq] call ITW_CLASH_PlayerTasks_fnc_OutstandingPackages
    } else {
        +(_hq getVariable ["RydHQ_AmmoBoxes",[]])
    };
    private _box = objNull;
    {
        if (isNull _x || {!alive _x}) then {continue};
        if ((_x getVariable ["ITW_CLASH_LogisticsPackageState","AVAILABLE_AT_REAR"]) != "AVAILABLE_AT_REAR") then {continue};
        if (_vehicle canSlingLoad _x) exitWith {_box = _x};
    } forEach _packages;
    _box
};

ITW_CLASH_PlayerDemand_fnc_StartAmmoExecution = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0 || {(_demand getOrDefault ["state",""]) != "RESERVED"}) exitWith {false};
    private _group = _demand getOrDefault ["reservedGroup",grpNull];
    private _hq = _demand getOrDefault ["hq",grpNull];
    private _target = _demand getOrDefault ["target",objNull];
    if (isNull _group || {isNull _hq} || {isNull _target}) exitWith {false};

    private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle;
    if (isNull _vehicle) exitWith {false};
    private _box = [_hq,_vehicle] call ITW_CLASH_PlayerDemand_fnc_FindAmmoPackage;
    if (isNull _box) exitWith {false};

    private _taskId = _demand getOrDefault ["taskId",""];
    if (_taskId isNotEqualTo "") then {
        [_taskId,"CANCELED",false] call BIS_fnc_taskSetState;
    };
    _demand set ["taskId",""];
    _demand set ["state","EXECUTING"];
    _demand set ["stateAt",time];
    _demand set ["executionVehicle",_vehicle];
    _demand set ["executionPackage",_box];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];

    ["player-demand-execution-ready",[
        _demandId,"LOGISTICS_AMMO",typeOf _vehicle,typeOf _box
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    ["player-demand-executing",[_demandId,"LOGISTICS_AMMO"]] call
        ITW_CLASH_PlayerDemand_fnc_Log;

    [_vehicle,_target,[],[],true,_box,_hq] spawn
        ITW_CLASH_PlayerTasks_fnc_PlayerAmmoJob;

    [_demandId,_group,_box] spawn {
        params ["_demandId","_group","_box"];
        private _seenJob = false;
        private _deadline = time + 15;
        waitUntil {
            sleep 0.25;
            isNull _group || {
                (_group getVariable ["ITW_CLASH_PlayerAmmoJobId",""]) isNotEqualTo ""
                || {time >= _deadline}
            }
        };
        if (isNull _group) exitWith {};
        private _jobId = _group getVariable ["ITW_CLASH_PlayerAmmoJobId",""];
        if (_jobId isEqualTo "") exitWith {
            [_demandId,"ammo-executor-did-not-arm",false] call
                ITW_CLASH_PlayerDemand_fnc_Release;
        };
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        _demand set ["executionJobId",_jobId];
        ITW_CLASH_PlayerDemands set [_demandId,_demand];
        waitUntil {
            sleep 0.5;
            isNull _group || {
                (_group getVariable ["ITW_CLASH_PlayerAmmoJobId",""]) isEqualTo ""
            }
        };
        if (isNull _group) exitWith {};
        private _state = if (isNull _box) then {""} else {
            _box getVariable ["ITW_CLASH_LogisticsPackageState",""]
        };
        if (_state == "DELIVERED") then {
            [_demandId,"ammo-delivered"] call ITW_CLASH_PlayerDemand_fnc_Complete;
        } else {
            private _cancelled = _group getVariable ["ITW_CLASH_PlayerDemandCancel",false];
            [_demandId,if (_cancelled) then {"player-canceled-ammo"} else {"ammo-execution-ended"},_cancelled] call
                ITW_CLASH_PlayerDemand_fnc_Release;
        };
    };
    true
};

ITW_CLASH_PlayerDemand_fnc_MedevacEvacuees = {
    params ["_demand"];
    private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _targetGroup) exitWith {[]};
    units _targetGroup select {
        [_x] call ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty
    }
};

ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer = {
    params ["_vehicle"];
    if (isNull _vehicle || {!alive _vehicle} || {!canMove _vehicle}) exitWith {false};
    if (abs speed _vehicle >= 3) exitWith {false};
    if (_vehicle isKindOf "Air") exitWith {
        isTouchingGround _vehicle || {(getPosATL _vehicle)#2 < 2.5}
    };
    true
};

ITW_CLASH_PlayerDemand_fnc_StartMedevacExecution = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0 || {(_demand getOrDefault ["state",""]) != "RESERVED"}) exitWith {false};
    private _group = _demand getOrDefault ["reservedGroup",grpNull];
    private _target = _demand getOrDefault ["target",objNull];
    if (isNull _group || {isNull _target}) exitWith {false};

    private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
    if (isNull _vehicle || {!([_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity)}) exitWith {false};
    if !([_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer) exitWith {false};
    if (_vehicle distance2D _target > ITW_CLASH_PlayerDemandMedevacPickupRadius) exitWith {false};

    private _evacuees = [_demand] call ITW_CLASH_PlayerDemand_fnc_MedevacEvacuees;
    if (_evacuees isEqualTo []) exitWith {false};
    if ((_vehicle emptyPositions "cargo") < count _evacuees) exitWith {false};
    if ((_evacuees findIf {_x distance2D _vehicle > ITW_CLASH_PlayerDemandMedevacPickupRadius}) >= 0) exitWith {false};

    {
        unassignVehicle _x;
        _x assignAsCargo _vehicle;
        _x moveInCargo _vehicle;
    } forEach _evacuees;

    private _allLoaded = (_evacuees findIf {vehicle _x != _vehicle}) < 0;
    if (!_allLoaded) exitWith {false};

    private _taskId = _demand getOrDefault ["taskId",""];
    _demand set ["state","EXECUTING"];
    _demand set ["stateAt",time];
    _demand set ["executionVehicle",_vehicle];
    _demand set ["evacuees",+_evacuees];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    ["player-demand-execution-ready",[
        _demandId,"MEDEVAC_SEVERE",typeOf _vehicle,count _evacuees
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    ["medevac-assisted-load",[
        _demandId,typeOf _vehicle,_evacuees apply {name _x}
    ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    ["player-demand-executing",[_demandId,"MEDEVAC_SEVERE"]] call
        ITW_CLASH_PlayerDemand_fnc_Log;

    [_demandId] spawn {
        params ["_demandId"];
        while {true} do {
            sleep 1;
            private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
            if (count _demand == 0 || {(_demand getOrDefault ["state",""]) != "EXECUTING"}) exitWith {};
            private _group = _demand getOrDefault ["reservedGroup",grpNull];
            private _vehicle = _demand getOrDefault ["executionVehicle",objNull];
            private _evacuees = +(_demand getOrDefault ["evacuees",[]]);
            private _taskId = _demand getOrDefault ["taskId",""];
            if (isNull _group || {isNull _vehicle} || {!alive _vehicle}) exitWith {
                [_demandId,"medevac-carrier-lost",false] call ITW_CLASH_PlayerDemand_fnc_Release;
            };

            if (_group getVariable ["ITW_CLASH_PlayerDemandCancel",false]) then {
                if ([_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer) exitWith {
                    {
                        if (!isNull _x && {alive _x} && {vehicle _x == _vehicle}) then {
                            unassignVehicle _x;
                            moveOut _x;
                        };
                    } forEach _evacuees;
                    [_demandId,"player-canceled-medevac",true] call ITW_CLASH_PlayerDemand_fnc_Release;
                };
                continue;
            };

            private _resolved = createHashMap;
            if (!isNil "ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup") then {
                _resolved = [_group,_vehicle,"player-medevac"] call
                    ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup;
            };
            if ((_resolved getOrDefault ["status",""]) != "RESOLVED") then {continue};
            private _home = +(_resolved get "position");
            if (_taskId isNotEqualTo "") then {
                [_taskId,[_home,true]] call BIS_fnc_taskSetDestination;
            };
            if (_vehicle distance2D _home > ITW_CLASH_PlayerDemandMedevacHomeRadius) then {continue};
            if !([_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer) then {continue};

            {
                if (!isNull _x && {alive _x} && {vehicle _x == _vehicle}) then {
                    unassignVehicle _x;
                    moveOut _x;
                };
            } forEach _evacuees;
            sleep 0.5;
            private _remaining = _evacuees select {
                !isNull _x && {alive _x} && {vehicle _x == _vehicle}
            };
            if (_remaining isNotEqualTo []) then {continue};

            private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
            if (!isNull _targetGroup) then {
                _targetGroup setVariable ["ITW_CLASH_PlayerMedevacDeliveredAt",time];
            };
            [_demandId,"casualties-delivered-to-friendly-home"] call
                ITW_CLASH_PlayerDemand_fnc_Complete;
            break;
        };
    };
    true
};

ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {};
    private _state = _demand getOrDefault ["state",""];
    if !(_state in ["RESERVED","EXECUTING"]) exitWith {};

    if !([_demandId] call ITW_CLASH_PlayerDemand_fnc_StillValid) exitWith {
        [_demandId,"underlying-demand-invalidated",false] call
            ITW_CLASH_PlayerDemand_fnc_Release;
    };

    private _group = _demand getOrDefault ["reservedGroup",grpNull];
    if !([_group] call ITW_CLASH_PlayerDemand_fnc_HumanGroupAlive) exitWith {
        [_demandId,"player-group-unavailable",false] call
            ITW_CLASH_PlayerDemand_fnc_Release;
    };

    if (_state == "RESERVED") then {
        private _nextLog = _demand getOrDefault ["lastPreparingLogAt",0];
        if (time >= _nextLog) then {
            _demand set ["lastPreparingLogAt",time + 30];
            ITW_CLASH_PlayerDemands set [_demandId,_demand];
            ["player-demand-preparing",[
                _demandId,
                [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId,
                _demand getOrDefault ["requirement",""]
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        };
        switch (_demand getOrDefault ["kind",""]) do {
            case "LOGISTICS_AMMO": {
                [_demandId] call ITW_CLASH_PlayerDemand_fnc_StartAmmoExecution;
            };
            case "MEDEVAC_SEVERE": {
                [_demandId] call ITW_CLASH_PlayerDemand_fnc_StartMedevacExecution;
            };
        };
    };
};

ITW_CLASH_PlayerDemand_fnc_OnAmmoDemand = {
    params ["_hq",["_targets",[]]];
    if (!ITW_CLASH_PlayerDemandDispatchReady || {isNull _hq}) exitWith {false};
    private _seenGroups = [];
    {
        private _target = _x;
        if (isNull _target || {!alive _target}) then {continue};
        private _targetGroup = [_target] call ITW_CLASH_PlayerDemand_fnc_TargetGroup;
        if (isNull _targetGroup || {_targetGroup in _seenGroups}) then {continue};
        _seenGroups pushBack _targetGroup;
        if ((_targetGroup getVariable [
            "ITW_CLASH_NativeAmmoExecution",""
        ]) isNotEqualTo "") then {continue};
        private _key = "LOGISTICS_AMMO|" + str _targetGroup;
        private _existing = [_key] call ITW_CLASH_PlayerDemand_fnc_FindBySourceKey;
        if (_existing isEqualTo "" && {
            _targetGroup in (_hq getVariable ["RydHQ_ASupportedG",[]])
        }) then {continue};
        private _name = [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId;
        [
            "LOGISTICS","LOGISTICS_AMMO",_key,_hq,_target,
            "HAL Logistics: Ammunition Delivery",
            format ["HAL reports %1 requires ammunition support. Deliver an ammunition package to the marked recipient.",_name],
            "Acquire a sling-capable helicopter that can lift the ammunition package.",
            getPosATL _target
        ] call ITW_CLASH_PlayerDemand_fnc_Publish;
    } forEach _targets;
    call ITW_CLASH_PlayerDemand_fnc_DispatchOpen;
    true
};

ITW_CLASH_PlayerDemand_fnc_OnMedicalDemand = {
    params ["_hq",["_severe",[]]];
    if (!ITW_CLASH_PlayerDemandDispatchReady || {isNull _hq}) exitWith {false};
    private _seenGroups = [];
    {
        private _casualty = _x;
        if !([_casualty] call ITW_CLASH_PlayerDemand_fnc_IsSevereCasualty) then {continue};
        private _targetGroup = group _casualty;
        if (isNull _targetGroup || {_targetGroup in _seenGroups}) then {continue};
        _seenGroups pushBack _targetGroup;
        private _deliveredAt = _targetGroup getVariable ["ITW_CLASH_PlayerMedevacDeliveredAt",-1];
        if (_deliveredAt >= 0 && {
            time - _deliveredAt < ITW_CLASH_PlayerDemandMedevacDeliveredCooldown
        }) then {continue};
        private _key = "MEDEVAC_SEVERE|" + str _targetGroup;
        private _existing = [_key] call ITW_CLASH_PlayerDemand_fnc_FindBySourceKey;
        if (_existing isEqualTo "" && {
            _targetGroup in (_hq getVariable ["RydHQ_SupportedG",[]])
        }) then {continue};
        private _name = [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId;
        [
            "MEDEVAC","MEDEVAC_SEVERE",_key,_hq,_casualty,
            "HAL MEDEVAC: Casualty Extraction",
            format ["HAL reports severe casualties in %1. Reach the casualty position, evacuate the surviving severe casualties, and return them to a live friendly base.",_name],
            "Acquire any living movable vehicle with sufficient passenger capacity for the evacuees.",
            getPosATL _casualty
        ] call ITW_CLASH_PlayerDemand_fnc_Publish;
    } forEach _severe;
    call ITW_CLASH_PlayerDemand_fnc_DispatchOpen;
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerDemandDispatchBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateHardeningReady",false]
            && {missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateCancelReady",false]}
            && {missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateArtilleryGuardReady",false]}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_HasActiveJob"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_CanAcceptJob"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_CancelGroupJob"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-demand-dispatch-bind-timeout | legacy capability-gated employment retained";
    };

    ITW_CLASH_PlayerDemand_fnc_HasActiveJobBase = ITW_CLASH_PlayerTasks_fnc_HasActiveJob;
    ITW_CLASH_PlayerDemand_fnc_CancelGroupJobBase = ITW_CLASH_PlayerTasks_fnc_CancelGroupJob;

    ITW_CLASH_PlayerTasks_fnc_HasActiveJob = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {false};
        ((_group getVariable ["ITW_CLASH_PlayerDemandJobId",""]) isNotEqualTo "")
        || {_this call ITW_CLASH_PlayerDemand_fnc_HasActiveJobBase}
    };

    // Subscription/willingness only. Current vehicle is deliberately absent.
    ITW_CLASH_PlayerTasks_fnc_CanAcceptJob = {
        params ["_subject","_jobType",["_ignoreOccupied",false]];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group || {!(_jobType isEqualType "")}) exitWith {false};
        _jobType = toUpperANSI _jobType;
        if !(_jobType in ITW_CLASH_PlayerJobTypes) exitWith {false};
        if (isNil "ITW_PlayerSide" || {side _group != ITW_PlayerSide}) exitWith {false};
        if ((units _group findIf {alive _x && {isPlayer _x}}) < 0) exitWith {false};
        if !([_group,_jobType] call ITW_CLASH_PlayerTasks_fnc_IsSubscribed) exitWith {false};
        if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {false};
        if (!_ignoreOccupied && {[_group] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob}) exitWith {false};
        true
    };

    ITW_CLASH_PlayerTasks_fnc_HasNativeExecutableSubscription = {
        params ["_group"];
        if (isNull _group) exitWith {false};
        private _subscriptions = [_group] call ITW_CLASH_PlayerTasks_fnc_GetSubscriptions;
        if (_subscriptions isEqualTo []) exitWith {false};
        if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {false};
        if ("COMBAT" in _subscriptions) exitWith {true};

        private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
        if (("TRANSPORT" in _subscriptions || {"MEDEVAC" in _subscriptions}) && {
            [_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity
        }) exitWith {true};
        if ("LOGISTICS" in _subscriptions && {
            !isNull ([_group] call ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle)
        }) exitWith {true};
        if ("ARTILLERY" in _subscriptions && {
            [_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasArtilleryCapability
        }) exitWith {true};
        false
    };

    // Preserve the legacy executable helper for callers that truly mean native
    // physical execution. It is no longer used to decide player dispatch.
    ITW_CLASH_PlayerTasks_fnc_HasExecutableSubscription = {
        params ["_group"];
        [_group] call ITW_CLASH_PlayerTasks_fnc_HasNativeExecutableSubscription
    };

    ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState = {
        params ["_subject",["_source","sync"]];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group || {isNil "ITW_PlayerSide"} || {side _group != ITW_PlayerSide}) exitWith {false};

        private _subscriptions = [_group] call ITW_CLASH_PlayerTasks_fnc_GetSubscriptions;
        private _willing = _subscriptions isNotEqualTo [];
        private _occupied = [_group] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob;
        private _dispatchable = _willing && {!_occupied} && {
            !(_group getVariable ["ITW_CLASH_AuthorityHold",false])
        };
        private _nativeExecutable = _willing && {!_occupied} && {
            [_group] call ITW_CLASH_PlayerTasks_fnc_HasNativeExecutableSubscription
        };
        private _signature = [
            _dispatchable,_nativeExecutable,_occupied,+_subscriptions
        ];
        private _previous = _group getVariable ["ITW_CLASH_PlayerEmploymentSignature",[]];

        _group setVariable ["EnableHALActions",true,true];
        _group setVariable ["ITW_CLASH_PlayerTaskInitialized",true,true];
        _group setVariable ["ITW_CLASH_PlayerTaskOptIn",_willing,true];
        _group setVariable ["ITW_CLASH_PlayerTaskAvailable",_dispatchable,true];
        _group setVariable ["ITW_CLASH_PlayerTaskDispatchable",_dispatchable,true];
        _group setVariable ["ITW_CLASH_PlayerNativeExecutable",_nativeExecutable,true];
        _group setVariable ["ITW_CLASH_PlayerHasActiveHALJob",_occupied,true];
        _group setVariable ["Unable",!_nativeExecutable,true];
        _group setVariable ["BUnable",!_nativeExecutable,true];
        _group setVariable ["ITW_CLASH_PlayerEmploymentSignature",_signature];

        if (_willing) then {
            ITW_CLASH_PlayerTaskGroups pushBackUnique _group;
        } else {
            ITW_CLASH_PlayerTaskGroups = ITW_CLASH_PlayerTaskGroups - [_group];
        };
        [_group] call ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission;

        if !(_previous isEqualTo _signature) then {
            ["employment-state",[
                [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId,
                "dispatchable=" + str _dispatchable,
                "nativeExecutable=" + str _nativeExecutable,
                "occupied=" + str _occupied,
                +_subscriptions,_source
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        };
        true
    };

    ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {false};
        private _demandId = _group getVariable ["ITW_CLASH_PlayerDemandJobId",""];
        if (_demandId isEqualTo "") exitWith {
            _this call ITW_CLASH_PlayerDemand_fnc_CancelGroupJobBase
        };

        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {
            _group setVariable ["ITW_CLASH_PlayerDemandJobId",nil,true];
            _this call ITW_CLASH_PlayerDemand_fnc_CancelGroupJobBase
        };
        _group setVariable ["ITW_CLASH_PlayerDemandCancel",true,true];
        private _state = _demand getOrDefault ["state",""];
        if (_state == "EXECUTING") then {
            private _kind = _demand getOrDefault ["kind",""];
            if (_kind == "LOGISTICS_AMMO") then {
                _this call ITW_CLASH_PlayerDemand_fnc_CancelGroupJobBase;
            };
            ["player-demand-cancel-pending",[_demandId,_kind]] call
                ITW_CLASH_PlayerDemand_fnc_Log;
            true
        } else {
            [_demandId,"player-canceled-before-execution",true] call
                ITW_CLASH_PlayerDemand_fnc_Release;
            true
        }
    };

    ITW_CLASH_PlayerDemandDispatchReady = true;
    {
        private _group = group _x;
        if (!isNull _group && {!isNil "ITW_PlayerSide"} && {side _group == ITW_PlayerSide}) then {
            [_group,"demand-policy-install"] call ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
        };
    } forEach allPlayers;

    diag_log format [
        "CLASH BOOT | player-demand-dispatch-ready | version=%1 subscriptionGatesDispatch=true capabilityGatesExecution=true vehicleIndependentAssignment=true nativeUnableSeparated=true ammoDemandHook=true medevacDemandHook=true",
        ITW_CLASH_PlayerDemandDispatchVersion
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_PlayerDemandPoll;
        if (!(missionNamespace getVariable ["ITW_CLASH_HALReady",false])) then {continue};

        {
            private _demandId = _x;
            private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
            private _state = _demand getOrDefault ["state",""];
            if (_state in ["RESERVED","EXECUTING"]) then {
                [_demandId] call ITW_CLASH_PlayerDemand_fnc_UpdateReserved;
            } else {
                if (_state == "OPEN" && {!([_demandId] call ITW_CLASH_PlayerDemand_fnc_StillValid)}) then {
                    _demand set ["state","INVALID"];
                    _demand set ["stateReason","open-demand-invalidated"];
                    _demand set ["stateAt",time];
                    ITW_CLASH_PlayerDemands set [_demandId,_demand];
                    ["player-demand-invalidated",[_demandId,"open-demand-invalidated"]] call
                        ITW_CLASH_PlayerDemand_fnc_Log;
                };
            };
        } forEach (keys ITW_CLASH_PlayerDemands);

        call ITW_CLASH_PlayerDemand_fnc_DispatchOpen;
    };
};

true