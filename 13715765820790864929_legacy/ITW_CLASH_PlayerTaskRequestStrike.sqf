#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestStrikeStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestStrikeStarted = true;
ITW_CLASH_PlayerTaskRequestStrikeReady = false;
ITW_CLASH_PlayerTaskRequestStrikeVersion = 3;
ITW_CLASH_PlayerTaskRequestStrikeSerial = 0;
ITW_CLASH_PlayerStrikePollInterval = missionNamespace getVariable [
    "ITW_CLASH_PlayerStrikePollInterval",2
];

ITW_CLASH_PlayerTaskRequestStrike_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTaskRequests_fnc_Log") then {
        ["strike-" + _event,_payload] call ITW_CLASH_PlayerTaskRequests_fnc_Log;
    } else {
        diag_log format ["CLASH TASK REQUEST STRIKE | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_KnownGroups = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};

    private _known = +(_hq getVariable ["RydHQ_KnEnemiesG",[]]);
    if (_known isEqualTo []) then {
        {
            if (!isNull _x) then {
                private _g = group _x;
                if (!isNull _g) then {_known pushBackUnique _g};
            };
        } forEach +(_hq getVariable ["RydHQ_KnEnemies",[]]);
    };
    _known select {
        !isNull _x && {{alive _x} count units _x > 0}
    }
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_ClassGroups = {
    params ["_hq","_requestType"];
    if (isNull _hq) exitWith {[]};

    private _heavy = +(_hq getVariable ["RydHQ_EnHArmorG",[]]);
    private _light = [];
    _light append +(_hq getVariable ["RydHQ_EnMArmorG",[]]);
    _light append +(_hq getVariable ["RydHQ_EnLArmorG",[]]);
    _light append +(_hq getVariable ["RydHQ_EnLArmorATG",[]]);
    _light = _light arrayIntersect _light;

    private _soft = [];
    {
        _soft append +(_hq getVariable [_x,[]]);
    } forEach [
        "RydHQ_EnInfG","RydHQ_EnStaticG","RydHQ_EnCarsG",
        "RydHQ_EnArtG","RydHQ_EnSupportG","RydHQ_EnCargoG",
        "RydHQ_EnNCCargoG"
    ];
    _soft = (_soft arrayIntersect _soft) - _heavy - _light;

    switch (_requestType) do {
        case "STRIKE_HEAVY_ARMOR": {_heavy};
        case "STRIKE_LIGHT_ARMOR": {_light};
        case "STRIKE_SOFT": {_soft};
        default {[]};
    }
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_ThreatCount = {
    params ["_targetGroup","_requestType"];
    if (isNull _targetGroup) exitWith {0};

    if (_requestType in ["STRIKE_LIGHT_ARMOR","STRIKE_HEAVY_ARMOR"]) then {
        private _vehicles = [];
        {
            if (!alive _x) then {continue};
            private _vehicle = vehicle _x;
            if (_vehicle != _x && {alive _vehicle} && {canFire _vehicle}) then {
                _vehicles pushBackUnique _vehicle;
            };
        } forEach units _targetGroup;

        // Armor STRIKE is against the fighting vehicles, not their dismounted
        // crews. Once no living, combat-capable armored vehicle remains, the
        // armored objective is complete even if surviving crew escape on foot.
        // Do not fall through to the infantry count for LIGHT/HEAVY requests.
        count _vehicles
    } else {
        {alive _x} count units _targetGroup
    }
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_CombatIneffective = {
    params ["_job"];
    private _targetGroup = _job getOrDefault ["targetGroup",grpNull];
    if (isNull _targetGroup) exitWith {true};

    private _requestType = _job getOrDefault ["requestType","STRIKE_SOFT"];
    private _current = [_targetGroup,_requestType] call
        ITW_CLASH_PlayerTaskRequestStrike_fnc_ThreatCount;
    private _nominal = _job getOrDefault ["targetNominalThreat",1];
    if (_current <= 0) exitWith {true};
    _nominal >= 4 && {_current <= floor (_nominal * 0.25)}
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_TrackingObject = {
    params ["_targetGroup","_requestType"];
    if (isNull _targetGroup) exitWith {objNull};

    if (_requestType in ["STRIKE_LIGHT_ARMOR","STRIKE_HEAVY_ARMOR"]) then {
        private _vehicles = [];
        {
            if (!alive _x) then {continue};
            private _vehicle = vehicle _x;
            if (_vehicle != _x && {alive _vehicle} && {canFire _vehicle}) then {
                _vehicles pushBackUnique _vehicle;
            };
        } forEach units _targetGroup;
        if (_vehicles isEqualTo []) exitWith {objNull};

        private _leaderVehicle = vehicle leader _targetGroup;
        if (_leaderVehicle in _vehicles) exitWith {_leaderVehicle};
        _vehicles#0
    } else {
        private _leader = leader _targetGroup;
        if (!isNull _leader && {alive _leader}) exitWith {vehicle _leader};

        private _alive = units _targetGroup select {alive _x};
        if (_alive isEqualTo []) exitWith {objNull};
        vehicle (_alive#0)
    }
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_TaskPresentation = {
    params ["_targetGroup","_requestType"];

    switch (_requestType) do {
        case "STRIKE_HEAVY_ARMOR": {
            [
                "Destroy Heavy Armor",
                "HAL has designated a heavy armor target. The task marker follows HAL's latest known position. Destroy or render the assigned combat vehicles ineffective. Dismounted surviving crews are not part of the armor STRIKE objective."
            ]
        };
        case "STRIKE_LIGHT_ARMOR": {
            [
                "Destroy Light Armor",
                "HAL has designated a light armor target. The task marker follows HAL's latest known position. Destroy or render the assigned combat vehicles ineffective. Dismounted surviving crews are not part of the armor STRIKE objective."
            ]
        };
        default {
            private _hasMountedVehicle = (units _targetGroup findIf {
                alive _x && {vehicle _x != _x}
            }) >= 0;
            if (_hasMountedVehicle) then {
                [
                    "Destroy Soft Target",
                    "HAL has designated a soft target formation. The task marker follows HAL's latest known position. Destroy the assigned formation or reduce it below meaningful combat effectiveness."
                ]
            } else {
                [
                    "Destroy Squad",
                    "HAL has designated an enemy squad. The task marker follows HAL's latest known position. Destroy the squad or reduce it below meaningful combat effectiveness."
                ]
            }
        };
    }
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_ReleaseReservation = {
    params ["_targetGroup","_jobId",["_reason","release"]];
    if (isNull _targetGroup) exitWith {false};
    private _current = _targetGroup getVariable [
        "ITW_CLASH_PlayerStrikeReservation",""
    ];
    if (_current != _jobId) exitWith {false};
    _targetGroup setVariable ["ITW_CLASH_PlayerStrikeReservation",nil];
    ["reservation-released",[groupId _targetGroup,_jobId,_reason]] call
        ITW_CLASH_PlayerTaskRequestStrike_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_Finish = {
    params ["_jobId","_state","_outcome"];
    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    if (count _job == 0) exitWith {false};
    if ((_job getOrDefault ["state",""]) in ["COMPLETED","FAILED","CANCELED"]) exitWith {false};

    private _group = _job getOrDefault ["group",grpNull];
    private _targetGroup = _job getOrDefault ["targetGroup",grpNull];
    private _taskId = _job getOrDefault ["taskId",""];

    [_jobId,_state,_outcome] call ITW_CLASH_PlayerTasks_fnc_SetJobState;
    if (!isNull _targetGroup) then {
        [_targetGroup,_jobId,"terminal-" + _state] call
            ITW_CLASH_PlayerTaskRequestStrike_fnc_ReleaseReservation;
    };

    if (!isNull _group) then {
        if ((_group getVariable ["ITW_CLASH_PlayerStrikeJobId",""]) == _jobId) then {
            _group setVariable ["ITW_CLASH_PlayerStrikeJobId",nil,true];
            _group setVariable ["ITW_CLASH_PlayerStrikeJobCancel",nil,true];
            _group setVariable ["Busy" + str _group,false];
        };
        if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
            [_group,"requested-strike-ended"] call
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
            ["rewardClass","STRIKE"],
            ["participants",_job getOrDefault ["participants",[]]],
            ["outcome",_outcome]
        ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    };

    ["finished",[_jobId,_state,_outcome]] call
        ITW_CLASH_PlayerTaskRequestStrike_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_Monitor = {
    params ["_jobId"];
    while {true} do {
        sleep ITW_CLASH_PlayerStrikePollInterval;
        private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
        if (count _job == 0) exitWith {};
        if ((_job getOrDefault ["state",""]) in ["COMPLETED","FAILED","CANCELED"]) exitWith {};

        private _group = _job getOrDefault ["group",grpNull];
        private _targetGroup = _job getOrDefault ["targetGroup",grpNull];
        if (isNull _group || {{alive _x && {isPlayer _x}} count units _group == 0}) exitWith {
            [_jobId,"FAILED","player-group-unavailable"] call
                ITW_CLASH_PlayerTaskRequestStrike_fnc_Finish;
        };
        if (_group getVariable ["ITW_CLASH_PlayerStrikeJobCancel",false]) exitWith {
            [_jobId,"CANCELED","player-cancel"] call
                ITW_CLASH_PlayerTaskRequestStrike_fnc_Finish;
        };
        if (isNull _targetGroup || {
            [_job] call ITW_CLASH_PlayerTaskRequestStrike_fnc_CombatIneffective
        }) exitWith {
            [_jobId,"COMPLETED","target-combat-ineffective"] call
                ITW_CLASH_PlayerTaskRequestStrike_fnc_Finish;
        };

        // Update only from HAL-owned knowledge. If HAL loses this contact,
        // leave the task at the last legitimate known position rather than
        // leaking the target's real position through the task framework.
        private _hq = _job getOrDefault ["hq",grpNull];
        private _taskId = _job getOrDefault ["taskId",""];
        private _requestType = _job getOrDefault ["requestType","STRIKE_SOFT"];
        private _halKnows = !isNull _hq && {
            _targetGroup in ([_hq] call ITW_CLASH_PlayerTaskRequestStrike_fnc_KnownGroups)
        };
        if (_halKnows && {_taskId isNotEqualTo ""}) then {
            private _trackingTarget = [
                _targetGroup,_requestType
            ] call ITW_CLASH_PlayerTaskRequestStrike_fnc_TrackingObject;
            if (!isNull _trackingTarget && {alive _trackingTarget}) then {
                private _newPosition = getPosATL _trackingTarget;
                private _oldPosition = _job getOrDefault ["targetPosition",[]];
                if (_oldPosition isEqualTo [] || {
                    _newPosition distance2D _oldPosition >= 5
                }) then {
                    [_taskId,_newPosition] call BIS_fnc_taskSetDestination;
                    _job set ["target",_trackingTarget];
                    _job set ["targetPosition",+_newPosition];
                    _job set ["lastTrackedAt",time];
                    ITW_CLASH_PlayerJobs set [_jobId,_job];
                    ["target-tracked",[
                        _jobId,groupId _targetGroup,_requestType,_newPosition
                    ]] call ITW_CLASH_PlayerTaskRequestStrike_fnc_Log;
                };
            };
        };
    };
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_SelectTarget = {
    params ["_hq","_requestType"];
    if (isNull _hq) exitWith {grpNull};

    private _known = [_hq] call ITW_CLASH_PlayerTaskRequestStrike_fnc_KnownGroups;
    private _class = [_hq,_requestType] call
        ITW_CLASH_PlayerTaskRequestStrike_fnc_ClassGroups;
    private _candidates = _known select {
        _x in _class
        && {(_x getVariable ["ITW_CLASH_PlayerStrikeReservation",""]) isEqualTo ""}
        && {{alive _x} count units _x > 0}
    };
    if (_candidates isEqualTo []) exitWith {grpNull};

    // Native HQOrders chooses RydHQ_NearestE by distance from the HAL HQ.
    // Preserve that same immediate-threat heuristic after the requested class
    // filter instead of inventing a C.L.A.S.H. target score.
    private _hqVehicle = vehicle leader _hq;
    private _best = _candidates#0;
    private _bestDistance = (vehicle leader _best) distance2D _hqVehicle;
    {
        private _distance = (vehicle leader _x) distance2D _hqVehicle;
        if (_distance < _bestDistance) then {
            _best = _x;
            _bestDistance = _distance;
        };
    } forEach _candidates;
    _best
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_Request = {
    params ["_group","_hq","_requestType"];

    private _targetGroup = [_hq,_requestType] call
        ITW_CLASH_PlayerTaskRequestStrike_fnc_SelectTarget;
    if (isNull _targetGroup) exitWith {
        ["NO_TASK","No suitable HAL-known target is available in that strike class."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    ITW_CLASH_PlayerTaskRequestStrikeSerial =
        ITW_CLASH_PlayerTaskRequestStrikeSerial + 1;
    private _jobId = format [
        "CLASH-STRIKE-%1-%2",
        round (diag_tickTime * 1000),
        ITW_CLASH_PlayerTaskRequestStrikeSerial
    ];

    if ((_targetGroup getVariable ["ITW_CLASH_PlayerStrikeReservation",""]) isNotEqualTo "") exitWith {
        ["NO_TASK","HAL target was taken by another player strike assignment."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };
    _targetGroup setVariable ["ITW_CLASH_PlayerStrikeReservation",_jobId];

    private _target = vehicle leader _targetGroup;
    if (isNull _target || {!alive _target}) exitWith {
        [_targetGroup,_jobId,"target-invalid-before-assignment"] call
            ITW_CLASH_PlayerTaskRequestStrike_fnc_ReleaseReservation;
        ["NO_TASK","HAL target became invalid before assignment."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    private _targetPosition = getPosATL _target;
    private _label = switch (_requestType) do {
        case "STRIKE_HEAVY_ARMOR": {"Heavy Armor"};
        case "STRIKE_LIGHT_ARMOR": {"Light Armor"};
        default {"Soft Targets"};
    };
    private _presentation = [_targetGroup,_requestType] call
        ITW_CLASH_PlayerTaskRequestStrike_fnc_TaskPresentation;
    _presentation params ["_taskTitle","_taskDescription"];
    private _taskId = "ITW_" + _jobId;
    private _roster = [_group] call ITW_CLASH_PlayerTasks_fnc_HumanRoster;
    private _nominalThreat = [_targetGroup,_requestType] call
        ITW_CLASH_PlayerTaskRequestStrike_fnc_ThreatCount;
    _nominalThreat = _nominalThreat max 1;

    private _job = createHashMapFromArray [
        ["id",_jobId],
        ["type","STRIKE_TARGET"],
        ["state","ACTIVE"],
        ["origin","PLAYER_REQUEST"],
        ["requestType",_requestType],
        ["group",_group],
        ["hq",_hq],
        ["target",_target],
        ["targetGroup",_targetGroup],
        ["targetPosition",+_targetPosition],
        ["targetNominalThreat",_nominalThreat],
        ["participants",_roster],
        ["assignedAt",time],
        ["activeAt",time],
        ["completedAt",-1],
        ["outcome",""],
        ["taskId",_taskId],
        ["sourceKey","STRIKE|" + str _targetGroup],
        ["rewardClass","STRIKE"]
    ];
    ITW_CLASH_PlayerJobs set [_jobId,_job];
    ["JOB_ASSIGNED",_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    ["JOB_ACTIVE",_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;

    _group setVariable ["ITW_CLASH_PlayerStrikeJobId",_jobId,true];
    _group setVariable ["ITW_CLASH_PlayerStrikeJobCancel",false,true];
    _group setVariable ["Busy" + str _group,true];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
        [_group,"requested-strike-assigned"] call
            ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
    };

    private _players = units _group select {isPlayer _x};
    [
        _players,
        _taskId,
        [
            _taskDescription + " HAL retains normal battlefield authority; other friendly forces may engage the same enemy.",
            _taskTitle,
            _taskTitle
        ],
        _targetPosition,
        "ASSIGNED",
        1,
        true,
        "destroy",
        true
    ] call BIS_fnc_taskCreate;

    ["target-selected",[
        _jobId,groupId _group,groupId _targetGroup,_requestType,
        typeOf _target,_targetPosition,_nominalThreat
    ]] call ITW_CLASH_PlayerTaskRequestStrike_fnc_Log;

    [_jobId] spawn ITW_CLASH_PlayerTaskRequestStrike_fnc_Monitor;
    ["MATCHED",format ["HAL strike assigned: %1.",_label],_jobId] call
        ITW_CLASH_PlayerTaskRequests_fnc_Result
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskRequestStrikeBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestsReady",false]
            && {missionNamespace getVariable ["ITW_CLASH_PlayerTaskSupportReady",false]}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_SetJobState"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_CancelGroupJob"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-task-request-strike-bind-timeout | STRIKE request remains unavailable";
    };

    ITW_CLASH_PlayerTaskRequestStrike_fnc_CancelGroupJobBase =
        ITW_CLASH_PlayerTasks_fnc_CancelGroupJob;
    ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {false};
        private _strikeJob = _group getVariable ["ITW_CLASH_PlayerStrikeJobId",""];
        if (_strikeJob isNotEqualTo "") exitWith {
            _group setVariable ["ITW_CLASH_PlayerStrikeJobCancel",true,true];
            ["cancel-requested",[_strikeJob,groupId _group]] call
                ITW_CLASH_PlayerTaskRequestStrike_fnc_Log;
            true
        };
        _this call ITW_CLASH_PlayerTaskRequestStrike_fnc_CancelGroupJobBase
    };

    {
        [_x,ITW_CLASH_PlayerTaskRequestStrike_fnc_Request] call
            ITW_CLASH_PlayerTaskRequests_fnc_RegisterAdapter;
    } forEach ["STRIKE_SOFT","STRIKE_LIGHT_ARMOR","STRIKE_HEAVY_ARMOR"];

    ITW_CLASH_PlayerTaskRequestStrikeReady = true;
    diag_log format [
        "CLASH BOOT | player-task-request-strike-ready | version=%1 halKnownGroups=true halEnemyTaxonomy=true nativeNearestThreatHeuristic=true duplicatePlayerReservation=true aiCombatUnblocked=true halKnowledgeTracking=true lastKnownFreeze=true rewardAuthorizationOnly=true",
        ITW_CLASH_PlayerTaskRequestStrikeVersion
    ];
};

true
