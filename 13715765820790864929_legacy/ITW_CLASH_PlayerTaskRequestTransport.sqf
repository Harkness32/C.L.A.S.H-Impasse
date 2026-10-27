#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestTransportStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestTransportStarted = true;
ITW_CLASH_PlayerTaskRequestTransportReady = false;
ITW_CLASH_PlayerTaskRequestTransportVersion = 3;
ITW_CLASH_PlayerTaskRequestTransportSerial = 0;

/*
    A transport pilot asks for work: lift a real squad to the front.

    Hark, 2026-10-27. Strike players make their own work; a transport pilot
    could only wait for HAL to want a lift. Spawning a squad to carry would be
    free reinforcements outside Impasse's manpower cap and tickets, so the
    request finds a squad that already exists and is already going: one of our
    AI infantry squads on foot at or near a friendly base, with a long walk to
    its destination. Nothing is created; the commander's own push simply
    arrives sooner.

    The squad's destination is where its orders already send it (its last
    waypoint, not yet reached). A squad with no orders is HAL's reserve and is
    left alone (v2, Hark: "are we just snatching up a team held in reserve?");
    v1 guessed COLOSSUS's plan objective for one. The task says where the
    orders lead, and the drop zone is on the map from the moment of assignment.

    HAL is kept out of the way rather than fought. HAL's own attack, capture
    and recon scripts watch a squad leader's assigned vehicle and run their
    own get-in and unload flow the moment one appears, which would steer the
    same squad as this job. So for the length of the ride the squad carries
    ITW_CLASH_PlayerLift: it reads as lifecycle-reserved, the BLUFOR layer
    drops it from HAL's Included list exactly as it drops a boarded CASEVAC
    squad, and HAL's running task ends through HAL's own Break flag. On the
    drop the mark clears and HAL takes the squad back and tasks it from where
    it now stands; until then it keeps moving toward its destination.

    Skipped: a squad HAL already queued for a lift (CargoCheckPending,
    CargoChosen, AssignedCargo), an anchor, a withdrawal, special forces, any
    other recovery, and a squad that would not fit in the pilot's seats.

    The job: land within GatherRadius of them; they walk to you and climb
    in, as AI CASEVAC's survivors do; drop them on the ground within
    DropRadius of their destination. A pickup nobody makes in PickupTimeout hands the squad
    back to HAL.
*/

ITW_CLASH_PlayerLiftBaseRadius = missionNamespace getVariable ["ITW_CLASH_PlayerLiftBaseRadius",600];
ITW_CLASH_PlayerLiftMinDistance = missionNamespace getVariable ["ITW_CLASH_PlayerLiftMinDistance",2000];
ITW_CLASH_PlayerLiftDropRadius = missionNamespace getVariable ["ITW_CLASH_PlayerLiftDropRadius",1500];
ITW_CLASH_PlayerLiftGatherRadius = missionNamespace getVariable ["ITW_CLASH_PlayerLiftGatherRadius",300];
ITW_CLASH_PlayerLiftPickupTimeout = missionNamespace getVariable ["ITW_CLASH_PlayerLiftPickupTimeout",600];
ITW_CLASH_PlayerLiftPoll = 1;

ITW_CLASH_PlayerTaskRequestTransport_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTaskRequests_fnc_Log") then {
        ["transport-" + _event,_payload] call ITW_CLASH_PlayerTaskRequests_fnc_Log;
    } else {
        diag_log format ["CLASH TASK REQUEST TRANSPORT | %1 | %2",_event,_payload];
    };
};

// Where the squad's orders send it: [position, source] or [[],""] when it has
// no order it has not finished yet.
ITW_CLASH_PlayerTaskRequestTransport_fnc_Destination = {
    params ["_squad"];
    private _count = count waypoints _squad;
    if (_count == 0 || {currentWaypoint _squad >= _count}) exitWith {[[],""]};
    private _wp = waypointPosition [_squad,_count - 1];
    if (_wp isEqualTo [] || {_wp isEqualTo [0,0,0]}) exitWith {[[],""]};
    if ((_squad getVariable ["ITW_CLASH_FOBAirDefence",""]) isNotEqualTo "") exitWith {[+_wp,"fob-air-defence"]};
    [+_wp,"orders"]
};

// What the pilot is told about the destination.
ITW_CLASH_PlayerTaskRequestTransport_fnc_DestinationText = {
    params ["_destination","_source"];
    private _grid = mapGridPosition _destination;
    if (_source == "fob-air-defence") exitWith {
        format ["Command has posted them to the FOB at grid %1 for air defence",_grid]
    };
    private _objective = [];
    private _best = 1e10;
    if (!isNil "ITW_Objectives") then {
        {
            if (_x#ITW_OBJ_HIDDEN) then {continue};
            private _d = _destination distance2D (_x#ITW_OBJ_POS);
            if (_d < _best && {_d <= (_x#ITW_OBJ_SIZE) + 500}) then {_best = _d; _objective = _x};
        } forEach ITW_Objectives;
    };
    if (_objective isEqualTo []) exitWith {format ["Their orders take them to grid %1",_grid]};
    if ((_objective#ITW_OBJ_OWNER) == ITW_OWNER_FRIENDLY) exitWith {
        format ["Their orders take them to reinforce %1 (grid %2)",_objective#ITW_OBJ_NAME,_grid]
    };
    format ["Their orders take them into the fight for %1 (grid %2)",_objective#ITW_OBJ_NAME,_grid]
};

/*
    Squads that could be lifted now, nearest to the pilot first, as
    [squad, destination, source, distance to destination].
*/
ITW_CLASH_PlayerTaskRequestTransport_fnc_Candidates = {
    params ["_hq","_seats","_from"];
    if (isNil "ITW_CLASH_DualHALBLUFORGroups") exitWith {[]};
    private _specFor = _hq getVariable ["RydHQ_SpecForG",[]];
    private _result = [];
    {
        private _squad = _x;
        if (isNull _squad || {side _squad != ITW_PlayerSide}) then {continue};
        if ([_squad] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup) then {continue};
        if (_squad in _specFor) then {continue};
        private _alive = units _squad select {alive _x};
        if (_alive isEqualTo [] || {count _alive > _seats}) then {continue};
        if ((_alive findIf {vehicle _x != _x || {!(_x isKindOf "CAManBase")}}) >= 0) then {continue};
        if (_squad getVariable ["ITW_CLASH_Withdrawing",false]) then {continue};
        if ((_squad getVariable ["ITW_CLASH_AnchorObjective",-1]) >= 0) then {continue};
        if ((_squad getVariable ["ITW_CLASH_PlayerLift",""]) isNotEqualTo "") then {continue};
        if ([_squad] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved) then {continue};
        // HAL already queued it for a lift of its own.
        if (_squad getVariable ["CargoCheckPending" + str _squad,false]) then {continue};
        if (_squad getVariable ["CargoChosen",false]) then {continue};
        if (!isNull (_squad getVariable ["AssignedCargo" + str _squad,objNull])) then {continue};

        private _leader = leader _squad;
        private _base = [getPosATL _leader] call ITW_BaseNearest;
        if !(_base isEqualType [] && {count _base > ITW_BASE_POS}) then {continue};
        if ((_leader distance2D (_base#ITW_BASE_POS)) > ITW_CLASH_PlayerLiftBaseRadius) then {continue};

        ([_squad] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Destination) params ["_destination","_source"];
        if (_destination isEqualTo []) then {continue};
        private _far = _leader distance2D _destination;
        if (_far < ITW_CLASH_PlayerLiftMinDistance) then {continue};
        _result pushBack [_squad,_destination,_source,_far,_leader distance2D _from];
    } forEach +ITW_CLASH_DualHALBLUFORGroups;
    ([_result,[],{_x#4},"ASCEND"] call BIS_fnc_sortBy) apply {_x select [0,4]}
};

/*
    Hand the squad back to HAL: the mark clears, the BLUFOR layer puts it back
    in Included, and it keeps moving toward its destination until HAL's next
    cycle tasks it from where it stands.
*/
ITW_CLASH_PlayerTaskRequestTransport_fnc_ReleaseSquad = {
    params ["_squad","_jobId","_destination",["_reason","release"]];
    if (isNull _squad) exitWith {false};
    if ((_squad getVariable ["ITW_CLASH_PlayerLift",""]) != _jobId) exitWith {false};
    _squad setVariable ["ITW_CLASH_PlayerLift",nil];
    if (!(_squad getVariable ["ITW_CLASH_Withdrawing",false])) then {
        _squad setVariable ["Break",nil];
    };
    if (({alive _x} count units _squad) > 0 && {_destination isNotEqualTo []}) then {
        [_squad] call ITW_CLASH_fnc_ClearGroupWaypoints;
        private _wp = _squad addWaypoint [_destination,50];
        _wp setWaypointType "MOVE";
        _wp setWaypointBehaviour "AWARE";
        _wp setWaypointCombatMode "YELLOW";
        _wp setWaypointSpeed "NORMAL";
    };
    if (!isNil "ITW_CLASH_DualHAL_fnc_SyncIncluded") then {call ITW_CLASH_DualHAL_fnc_SyncIncluded};
    ["squad-released",[_jobId,groupId _squad,_reason]] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequestTransport_fnc_Unload = {
    params ["_vehicle","_men"];
    {
        if (!isNull _x && {alive _x} && {vehicle _x == _vehicle}) then {
            unassignVehicle _x;
            moveOut _x;
        };
    } forEach _men;
};

ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish = {
    params ["_jobId","_state","_outcome"];
    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    if (count _job == 0) exitWith {false};
    if ((_job getOrDefault ["state",""]) in ["COMPLETED","FAILED","CANCELED"]) exitWith {false};

    private _group = _job getOrDefault ["group",grpNull];
    private _squad = _job getOrDefault ["targetGroup",grpNull];
    private _taskId = _job getOrDefault ["taskId",""];
    [_jobId,_state,_outcome] call ITW_CLASH_PlayerTasks_fnc_SetJobState;
    {deleteMarker _x} forEach (_job getOrDefault ["markers",[]]);

    [_squad,_jobId,_job getOrDefault ["destination",[]],"terminal-" + _state] call
        ITW_CLASH_PlayerTaskRequestTransport_fnc_ReleaseSquad;
    if (!isNull _group) then {
        if ((_group getVariable ["ITW_CLASH_PlayerLiftJobId",""]) == _jobId) then {
            _group setVariable ["ITW_CLASH_PlayerLiftJobId",nil,true];
            _group setVariable ["ITW_CLASH_PlayerLiftJobCancel",nil,true];
            _group setVariable ["Busy" + str _group,false];
        };
        if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
            [_group,"requested-transport-ended"] call
                ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
        };
    };
    if (_taskId isNotEqualTo "") then {
        [_taskId,switch (_state) do {
            case "COMPLETED": {"SUCCEEDED"};
            case "CANCELED": {"CANCELED"};
            default {"FAILED"};
        },true] call BIS_fnc_taskSetState;
    };
    if (_state == "COMPLETED") then {
        ["PLAYER_TASK_REWARD_AUTHORIZED",createHashMapFromArray [
            ["jobId",_jobId],
            ["origin","PLAYER_REQUEST"],
            ["rewardClass","TRANSPORT"],
            ["participants",_job getOrDefault ["participants",[]]],
            ["outcome",_outcome]
        ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    };
    ["finished",[_jobId,_state,_outcome]] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Log;
    true
};

/*
    PICKUP: the squad holds where it is. A carrier grounded within
    GatherRadius brings them walking to it and they climb in. Returns true
    once they are aboard.
*/
ITW_CLASH_PlayerTaskRequestTransport_fnc_Pickup = {
    params ["_jobId","_job","_group","_squad"];
    // Hold: whatever HAL was still doing ends, and no new route is walked.
    if (_squad getVariable ["Busy" + str _squad,false]) then {_squad setVariable ["Break",true]};
    if ((count waypoints _squad) > 0 && {!(_job getOrDefault ["gathering",false])}) then {
        [_squad] call ITW_CLASH_fnc_ClearGroupWaypoints;
    };

    private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
    private _leader = leader _squad;
    private _ready = !isNull _vehicle
        && {[_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity}
        && {[_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer}
        && {(_vehicle distance2D _leader) <= ITW_CLASH_PlayerLiftGatherRadius};
    if (!_ready) exitWith {
        if (_job getOrDefault ["gathering",false]) then {
            _job set ["gathering",false];
            [units _squad,_job getOrDefault ["boardingVehicle",objNull],_job] call
                ITW_CLASH_PlayerDemand_fnc_CancelBoarding;
        };
        false
    };
    _job set ["gathering",true];

    private _men = units _squad select {alive _x};
    private _outside = _men select {vehicle _x != _vehicle};
    if ((_vehicle emptyPositions "cargo") < count _outside) exitWith {
        if !(_job getOrDefault ["seatsSaid",false]) then {
            _job set ["seatsSaid",true];
            ["too-few-seats",[_jobId,typeOf _vehicle,_vehicle emptyPositions "cargo",count _outside]] call
                ITW_CLASH_PlayerTaskRequestTransport_fnc_Log;
        };
        false
    };

    // v3 (Hark, 2026-10-27): they walk over and climb in, as for AI CASEVAC.
    _job set ["boardingVehicle",_vehicle];
    if !([_men,_vehicle,_job] call ITW_CLASH_PlayerDemand_fnc_BoardOnFoot) exitWith {false};

    _job set ["phase","CARRY"];
    _job set ["carrier",_vehicle];
    _job set ["passengers",+_men];
    _job set ["loadedAt",time];
    private _taskId = _job getOrDefault ["taskId",""];
    if (_taskId isNotEqualTo "") then {
        [_taskId,_job getOrDefault ["destination",[]]] call BIS_fnc_taskSetDestination;
    };
    ["loaded",[_jobId,groupId _squad,typeOf _vehicle,count _men]] call
        ITW_CLASH_PlayerTaskRequestTransport_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequestTransport_fnc_Monitor = {
    params ["_jobId"];
    private _done = false;
    while {!_done} do {
        sleep ITW_CLASH_PlayerLiftPoll;
        private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
        if (count _job == 0) exitWith {};
        if ((_job getOrDefault ["state",""]) in ["COMPLETED","FAILED","CANCELED"]) exitWith {};

        private _group = _job getOrDefault ["group",grpNull];
        private _squad = _job getOrDefault ["targetGroup",grpNull];
        private _phase = _job getOrDefault ["phase","PICKUP"];
        private _carrier = _job getOrDefault ["carrier",objNull];
        private _men = +(_job getOrDefault ["passengers",[]]);
        private _destination = _job getOrDefault ["destination",[]];

        if (isNull _group || {{alive _x && {isPlayer _x}} count units _group == 0}) exitWith {
            [_jobId,"FAILED","player-group-unavailable"] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish;
        };
        if (isNull _squad || {{alive _x} count units _squad == 0}) exitWith {
            [_jobId,if (_phase == "CARRY") then {"FAILED"} else {"CANCELED"},"squad-lost"] call
                ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish;
        };

        if (_phase == "PICKUP") then {
            switch (true) do {
                case (_group getVariable ["ITW_CLASH_PlayerLiftJobCancel",false]): {
                    [_jobId,"CANCELED","player-cancel"] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish;
                    _done = true;
                };
                case (_squad getVariable ["ITW_CLASH_Withdrawing",false]): {
                    [_jobId,"CANCELED","squad-withdrawing"] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish;
                    _done = true;
                };
                case (time - (_job getOrDefault ["assignedAt",time]) > ITW_CLASH_PlayerLiftPickupTimeout): {
                    [_jobId,"CANCELED","pickup-timeout"] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish;
                    _done = true;
                };
                default {
                    [_jobId,_job,_group,_squad] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Pickup;
                };
            };
        } else {
            private _grounded = [_carrier] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer;
            switch (true) do {
                case (isNull _carrier || {!alive _carrier}): {
                    [_jobId,"FAILED","carrier-lost"] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish;
                    _done = true;
                };
                case (_group getVariable ["ITW_CLASH_PlayerLiftJobCancel",false]): {
                    if (_grounded) then {
                        [_carrier,_men] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Unload;
                        [_jobId,"CANCELED","player-cancel"] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish;
                        _done = true;
                    };
                };
                case (_grounded && {(_carrier distance2D _destination) <= ITW_CLASH_PlayerLiftDropRadius}): {
                    [_carrier,_men] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Unload;
                    ["delivered",[
                        _jobId,groupId _squad,round (_carrier distance2D _destination),
                        round (time - (_job getOrDefault ["loadedAt",time]))
                    ]] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Log;
                    [_jobId,"COMPLETED","squad-delivered"] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish;
                    _done = true;
                };
            };
        };
    };
};

ITW_CLASH_PlayerTaskRequestTransport_fnc_Request = {
    params ["_group","_hq","_requestType"];
    private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
    if (isNull _vehicle || {!([_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity)}) exitWith {
        ["NO_CAPABILITY","Get in a vehicle with passenger seats, then request a transport task."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };
    private _seats = _vehicle emptyPositions "cargo";
    private _candidates = [_hq,_seats,getPosATL _vehicle] call ITW_CLASH_PlayerTaskRequestTransport_fnc_Candidates;
    if (_candidates isEqualTo []) exitWith {
        ["NO_TASK",format ["No squad with orders is at a base needing a lift that fits your %1 seats.",_seats]] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };
    (_candidates#0) params ["_squad","_destination","_source","_far"];

    ITW_CLASH_PlayerTaskRequestTransportSerial = ITW_CLASH_PlayerTaskRequestTransportSerial + 1;
    private _jobId = format [
        "CLASH-LIFT-%1-%2",round (diag_tickTime * 1000),ITW_CLASH_PlayerTaskRequestTransportSerial
    ];
    if ((_squad getVariable ["ITW_CLASH_PlayerLift",""]) isNotEqualTo "") exitWith {
        ["NO_TASK","That squad was just taken by another pilot. Request again."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };
    // Off HAL for the ride: reserved, out of Included, its running task ended.
    _squad setVariable ["ITW_CLASH_PlayerLift",_jobId];
    if (_squad getVariable ["Busy" + str _squad,false]) then {_squad setVariable ["Break",true]};
    [_squad] call ITW_CLASH_fnc_ClearGroupWaypoints;
    {doStop _x} forEach (units _squad select {alive _x});
    if (!isNil "ITW_CLASH_DualHAL_fnc_SyncIncluded") then {call ITW_CLASH_DualHAL_fnc_SyncIncluded};

    private _pickup = getPosATL leader _squad;
    private _count = {alive _x} count units _squad;
    private _taskId = "ITW_" + _jobId;
    private _roster = [_group] call ITW_CLASH_PlayerTasks_fnc_HumanRoster;
    private _job = createHashMapFromArray [
        ["id",_jobId],
        ["type","TRANSPORT_LIFT"],
        ["state","ACTIVE"],
        ["origin","PLAYER_REQUEST"],
        ["requestType","TRANSPORT"],
        ["group",_group],
        ["hq",_hq],
        ["targetGroup",_squad],
        ["pickup",+_pickup],
        ["destination",+_destination],
        ["destinationSource",_source],
        ["phase","PICKUP"],
        ["participants",_roster],
        ["assignedAt",time],
        ["activeAt",time],
        ["completedAt",-1],
        ["outcome",""],
        ["taskId",_taskId],
        ["sourceKey","LIFT|" + str _squad],
        ["rewardClass","TRANSPORT"]
    ];
    ITW_CLASH_PlayerJobs set [_jobId,_job];
    ["JOB_ASSIGNED",_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    ["JOB_ACTIVE",_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;

    _group setVariable ["ITW_CLASH_PlayerLiftJobId",_jobId,true];
    _group setVariable ["ITW_CLASH_PlayerLiftJobCancel",false,true];
    _group setVariable ["Busy" + str _group,true];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
        [_group,"requested-transport-assigned"] call ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
    };

    // The drop zone is on the map from the start; the task marker moves to it
    // once they are aboard.
    private _zone = "ITW_CLASH_LiftZone_" + _jobId;
    createMarker [_zone,_destination];
    _zone setMarkerShape "ELLIPSE";
    _zone setMarkerSize [ITW_CLASH_PlayerLiftDropRadius,ITW_CLASH_PlayerLiftDropRadius];
    _zone setMarkerBrush "Border";
    _zone setMarkerColor "ColorWEST";
    private _drop = "ITW_CLASH_LiftDrop_" + _jobId;
    createMarker [_drop,_destination];
    _drop setMarkerType "hd_end";
    _drop setMarkerColor "ColorWEST";
    _drop setMarkerText format ["%1 drop zone",groupId _squad];
    _job set ["markers",[_zone,_drop]];

    [
        units _group select {isPlayer _x},
        _taskId,
        [
            format [
                "%1 (%2 men) is at grid %3. %4, %5 km away. Land within %6 m of them; they board when you are down. Put them on the ground inside the circled drop zone, %7 km around where they are going.",
                groupId _squad,_count,mapGridPosition _pickup,
                [_destination,_source] call ITW_CLASH_PlayerTaskRequestTransport_fnc_DestinationText,
                (round (_far / 100)) / 10,ITW_CLASH_PlayerLiftGatherRadius,
                (round (ITW_CLASH_PlayerLiftDropRadius / 100)) / 10
            ],
            format ["Lift %1",groupId _squad],
            ""
        ],
        _pickup,
        "ASSIGNED",
        1,
        true,
        "heli",
        true
    ] call BIS_fnc_taskCreate;

    ["assigned",[_jobId,groupId _group,groupId _squad,_count,round _far,_source,typeOf _vehicle]] call
        ITW_CLASH_PlayerTaskRequestTransport_fnc_Log;
    [_jobId] spawn ITW_CLASH_PlayerTaskRequestTransport_fnc_Monitor;
    ["MATCHED",format ["Transport task assigned: lift %1. The drop zone is marked on your map.",groupId _squad],_jobId] call
        ITW_CLASH_PlayerTaskRequests_fnc_Result
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskRequestTransportBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestsReady",false]
            && {missionNamespace getVariable ["ITW_CLASH_PlayerTaskSupportReady",false]}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_SetJobState"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_CancelGroupJob"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer"}
            && {!isNil "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved"}
            && {!isNil "ITW_CLASH_fnc_ClearGroupWaypoints"}
            && {!isNil "ITW_BaseNearest"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-task-request-transport-bind-timeout | TRANSPORT request remains unavailable";
    };

    // A squad under a player's lift is reserved like a boarded CASEVAC squad,
    // so the BLUFOR layer keeps it out of HAL's Included list for the ride.
    ITW_CLASH_PlayerTaskRequestTransport_fnc_IsLifecycleReservedBase =
        ITW_CLASH_DualHAL_fnc_IsLifecycleReserved;
    ITW_CLASH_DualHAL_fnc_IsLifecycleReserved = {
        params ["_group"];
        if (!isNull _group && {(_group getVariable ["ITW_CLASH_PlayerLift",""]) isNotEqualTo ""}) exitWith {true};
        _this call ITW_CLASH_PlayerTaskRequestTransport_fnc_IsLifecycleReservedBase
    };

    ITW_CLASH_PlayerTaskRequestTransport_fnc_CancelGroupJobBase =
        ITW_CLASH_PlayerTasks_fnc_CancelGroupJob;
    ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {false};
        private _liftJob = _group getVariable ["ITW_CLASH_PlayerLiftJobId",""];
        if (_liftJob isNotEqualTo "") exitWith {
            _group setVariable ["ITW_CLASH_PlayerLiftJobCancel",true,true];
            ["cancel-requested",[_liftJob,groupId _group]] call
                ITW_CLASH_PlayerTaskRequestTransport_fnc_Log;
            true
        };
        _this call ITW_CLASH_PlayerTaskRequestTransport_fnc_CancelGroupJobBase
    };

    ["TRANSPORT",ITW_CLASH_PlayerTaskRequestTransport_fnc_Request] call
        ITW_CLASH_PlayerTaskRequests_fnc_RegisterAdapter;
    ITW_CLASH_PlayerTaskRequestTransportReady = true;

    diag_log format [
        "CLASH BOOT | player-task-request-transport-ready | version=%1 realSquadsOnly=true spawnsNothing=true baseRadius=%2 minDistance=%3 dropRadius=%4 gather=%5 boardTimeout=%6 pickupTimeout=%7 halQueuedLiftsSkipped=true offHALForRide=true orderedSquadsOnly=true dropZoneMarked=true",
        ITW_CLASH_PlayerTaskRequestTransportVersion,
        ITW_CLASH_PlayerLiftBaseRadius,
        ITW_CLASH_PlayerLiftMinDistance,
        ITW_CLASH_PlayerLiftDropRadius,
        ITW_CLASH_PlayerLiftGatherRadius,
        ITW_CLASH_PlayerBoardTimeout,
        ITW_CLASH_PlayerLiftPickupTimeout
    ];
};

true
