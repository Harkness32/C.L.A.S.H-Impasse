#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestReconStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestReconStarted = true;
ITW_CLASH_PlayerTaskRequestReconReady = false;
ITW_CLASH_PlayerTaskRequestReconVersion = 1;
ITW_CLASH_PlayerTaskRequestReconSerial = 0;
ITW_CLASH_PlayerReconContactHistory = createHashMap;
ITW_CLASH_PlayerReconHistoryPoll = missionNamespace getVariable [
    "ITW_CLASH_PlayerReconHistoryPoll",2
];
ITW_CLASH_PlayerReconStaleSeconds = missionNamespace getVariable [
    "ITW_CLASH_PlayerReconStaleSeconds",60
];
ITW_CLASH_PlayerReconKnowledgeThreshold = missionNamespace getVariable [
    "ITW_CLASH_PlayerReconKnowledgeThreshold",0.05
];

ITW_CLASH_PlayerTaskRequestRecon_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTaskRequests_fnc_Log") then {
        ["recon-" + _event,_payload] call ITW_CLASH_PlayerTaskRequests_fnc_Log;
    } else {
        diag_log format ["CLASH TASK REQUEST RECON | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_Key = {
    params ["_hq","_targetGroup"];
    if (isNull _hq || {isNull _targetGroup}) exitWith {""};
    str _hq + "|" + str _targetGroup
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_KnownGroups = {
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
    _known select {!isNull _x && {{alive _x} count units _x > 0}}
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_RecordKnown = {
    params ["_hq","_targetGroup"];
    if (isNull _hq || {isNull _targetGroup}) exitWith {false};
    private _leader = leader _targetGroup;
    if (isNull _leader) exitWith {false};
    private _key = [_hq,_targetGroup] call ITW_CLASH_PlayerTaskRequestRecon_fnc_Key;
    if (_key isEqualTo "") exitWith {false};

    private _record = ITW_CLASH_PlayerReconContactHistory getOrDefault [
        _key,createHashMap
    ];
    private _wasLost = (_record getOrDefault ["lostAt",-1]) >= 0;
    _record set ["key",_key];
    _record set ["hq",_hq];
    _record set ["targetGroup",_targetGroup];
    _record set ["lastKnownAt",time];
    _record set ["lastKnownPos",getPosATL (vehicle _leader)];
    _record set ["lastKnownType",typeOf (vehicle _leader)];
    _record set ["lostAt",-1];
    ITW_CLASH_PlayerReconContactHistory set [_key,_record];

    if (_wasLost) then {
        ["contact-returned-to-hal",[
            groupId _targetGroup,_key,_record get "lastKnownPos"
        ]] call ITW_CLASH_PlayerTaskRequestRecon_fnc_Log;
    };
    true
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_UpdateHistory = {
    params ["_hq"];
    if (isNull _hq) exitWith {false};
    private _known = [_hq] call ITW_CLASH_PlayerTaskRequestRecon_fnc_KnownGroups;

    {
        [_hq,_x] call ITW_CLASH_PlayerTaskRequestRecon_fnc_RecordKnown;
    } forEach _known;

    {
        private _key = _x;
        private _record = ITW_CLASH_PlayerReconContactHistory getOrDefault [
            _key,createHashMap
        ];
        if (count _record == 0) then {continue};
        if ((_record getOrDefault ["hq",grpNull]) != _hq) then {continue};
        private _targetGroup = _record getOrDefault ["targetGroup",grpNull];
        if (isNull _targetGroup || {{alive _x} count units _targetGroup == 0}) then {
            ITW_CLASH_PlayerReconContactHistory deleteAt _key;
            continue;
        };
        if (_targetGroup in _known) then {continue};
        if ((_record getOrDefault ["lostAt",-1]) < 0) then {
            _record set ["lostAt",time];
            ITW_CLASH_PlayerReconContactHistory set [_key,_record];
            ["contact-lost-by-hal",[
                groupId _targetGroup,_key,
                _record getOrDefault ["lastKnownPos",[]]
            ]] call ITW_CLASH_PlayerTaskRequestRecon_fnc_Log;
        };
    } forEach (keys ITW_CLASH_PlayerReconContactHistory);
    true
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_PlayerKnowledge = {
    params ["_playerGroup","_targetGroup"];
    if (isNull _playerGroup || {isNull _targetGroup}) exitWith {0};
    private _targets = [];
    {
        if (alive _x) then {
            _targets pushBackUnique (vehicle _x);
        };
    } forEach units _targetGroup;
    if (_targets isEqualTo []) exitWith {0};

    private _knowledge = 0;
    {
        private _observer = _x;
        if (!alive _observer) then {continue};
        {
            _knowledge = _knowledge max (_observer knowsAbout _x);
        } forEach _targets;
    } forEach units _playerGroup;
    _knowledge
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_HALKnows = {
    params ["_hq","_targetGroup"];
    if (isNull _hq || {isNull _targetGroup}) exitWith {false};
    private _knownGroups = [_hq] call
        ITW_CLASH_PlayerTaskRequestRecon_fnc_KnownGroups;
    _targetGroup in _knownGroups
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_ReleaseReservation = {
    params ["_targetGroup","_jobId",["_reason","release"]];
    if (isNull _targetGroup) exitWith {false};
    private _current = _targetGroup getVariable [
        "ITW_CLASH_PlayerReconReservation",""
    ];
    if (_current != _jobId) exitWith {false};
    _targetGroup setVariable ["ITW_CLASH_PlayerReconReservation",nil];
    ["reservation-released",[groupId _targetGroup,_jobId,_reason]] call
        ITW_CLASH_PlayerTaskRequestRecon_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish = {
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
            ITW_CLASH_PlayerTaskRequestRecon_fnc_ReleaseReservation;
    };
    if (!isNull _group) then {
        if ((_group getVariable ["ITW_CLASH_PlayerReconJobId",""]) == _jobId) then {
            _group setVariable ["ITW_CLASH_PlayerReconJobId",nil,true];
            _group setVariable ["ITW_CLASH_PlayerReconJobCancel",nil,true];
            _group setVariable ["Busy" + str _group,false];
        };
        if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
            [_group,"requested-recon-ended"] call
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
            ["rewardClass","RECON"],
            ["participants",_job getOrDefault ["participants",[]]],
            ["outcome",_outcome]
        ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    };
    ["finished",[_jobId,_state,_outcome]] call
        ITW_CLASH_PlayerTaskRequestRecon_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_Monitor = {
    params ["_jobId"];
    while {true} do {
        sleep ITW_CLASH_PlayerReconHistoryPoll;
        private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
        if (count _job == 0) exitWith {};
        if ((_job getOrDefault ["state",""]) in ["COMPLETED","FAILED","CANCELED"]) exitWith {};

        private _group = _job getOrDefault ["group",grpNull];
        private _hq = _job getOrDefault ["hq",grpNull];
        private _targetGroup = _job getOrDefault ["targetGroup",grpNull];
        if (isNull _group || {{alive _x && {isPlayer _x}} count units _group == 0}) exitWith {
            [_jobId,"FAILED","player-group-unavailable"] call
                ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish;
        };
        if (_group getVariable ["ITW_CLASH_PlayerReconJobCancel",false]) exitWith {
            [_jobId,"CANCELED","player-cancel"] call
                ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish;
        };
        if (isNull _targetGroup || {{alive _x} count units _targetGroup == 0}) exitWith {
            [_jobId,"CANCELED","contact-destroyed-before-reacquisition"] call
                ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish;
        };

        private _playerKnowledge = [_group,_targetGroup] call
            ITW_CLASH_PlayerTaskRequestRecon_fnc_PlayerKnowledge;
        private _halKnows = [_hq,_targetGroup] call
            ITW_CLASH_PlayerTaskRequestRecon_fnc_HALKnows;
        if (
            _playerKnowledge >= ITW_CLASH_PlayerReconKnowledgeThreshold
            && {_halKnows}
        ) exitWith {
            ["intel-reacquired",[
                _jobId,groupId _group,groupId _targetGroup,_playerKnowledge
            ]] call ITW_CLASH_PlayerTaskRequestRecon_fnc_Log;
            [_jobId,"COMPLETED","hal-intel-reacquired"] call
                ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish;
        };
        if (_halKnows && {
            _playerKnowledge < ITW_CLASH_PlayerReconKnowledgeThreshold
        }) exitWith {
            [_jobId,"CANCELED","contact-reacquired-by-other-friendly"] call
                ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish;
        };
    };
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_SelectRecord = {
    params ["_hq"];
    if (isNull _hq) exitWith {createHashMap};
    [_hq] call ITW_CLASH_PlayerTaskRequestRecon_fnc_UpdateHistory;

    private _best = createHashMap;
    private _bestLostAt = -1;
    {
        private _record = ITW_CLASH_PlayerReconContactHistory getOrDefault [
            _x,createHashMap
        ];
        if (count _record == 0 || {(_record getOrDefault ["hq",grpNull]) != _hq}) then {continue};
        private _targetGroup = _record getOrDefault ["targetGroup",grpNull];
        private _lostAt = _record getOrDefault ["lostAt",-1];
        if (
            isNull _targetGroup
            || {{alive _x} count units _targetGroup == 0}
            || {_lostAt < 0}
            || {time - _lostAt < ITW_CLASH_PlayerReconStaleSeconds}
            || {(_targetGroup getVariable ["ITW_CLASH_PlayerReconReservation",""]) isNotEqualTo ""}
        ) then {continue};

        // Prefer the most recently lost mature contact: recover fresh tactical
        // uncertainty first, while never inventing a contact HAL did not know.
        if (_lostAt > _bestLostAt) then {
            _best = _record;
            _bestLostAt = _lostAt;
        };
    } forEach (keys ITW_CLASH_PlayerReconContactHistory);
    _best
};

ITW_CLASH_PlayerTaskRequestRecon_fnc_Request = {
    params ["_group","_hq","_requestType"];
    private _record = [_hq] call ITW_CLASH_PlayerTaskRequestRecon_fnc_SelectRecord;
    if (count _record == 0) exitWith {
        ["NO_TASK","HAL has no mature lost contact requiring reacquisition."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    private _targetGroup = _record getOrDefault ["targetGroup",grpNull];
    if (isNull _targetGroup) exitWith {
        ["NO_TASK","HAL lost-contact record became invalid."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    ITW_CLASH_PlayerTaskRequestReconSerial = ITW_CLASH_PlayerTaskRequestReconSerial + 1;
    private _jobId = format [
        "CLASH-RECON-%1-%2",
        round (diag_tickTime * 1000),
        ITW_CLASH_PlayerTaskRequestReconSerial
    ];
    if ((_targetGroup getVariable ["ITW_CLASH_PlayerReconReservation",""]) isNotEqualTo "") exitWith {
        ["NO_TASK","HAL lost contact was assigned to another recon element."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };
    _targetGroup setVariable ["ITW_CLASH_PlayerReconReservation",_jobId];

    private _lastKnownPos = +(_record getOrDefault ["lastKnownPos",[]]);
    if (count _lastKnownPos < 2) exitWith {
        [_targetGroup,_jobId,"missing-last-known-position"] call
            ITW_CLASH_PlayerTaskRequestRecon_fnc_ReleaseReservation;
        ["NO_TASK","HAL has no usable last-known position for that contact."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };
    private _taskId = "ITW_" + _jobId;
    private _roster = [_group] call ITW_CLASH_PlayerTasks_fnc_HumanRoster;
    private _job = createHashMapFromArray [
        ["id",_jobId],
        ["type","RECON_REACQUIRE_CONTACT"],
        ["state","ACTIVE"],
        ["origin","PLAYER_REQUEST"],
        ["requestType","RECON"],
        ["group",_group],
        ["hq",_hq],
        ["targetGroup",_targetGroup],
        ["lastKnownPosition",+_lastKnownPos],
        ["lastKnownAt",_record getOrDefault ["lastKnownAt",-1]],
        ["lostAt",_record getOrDefault ["lostAt",-1]],
        ["lastKnownType",_record getOrDefault ["lastKnownType","unknown"]],
        ["participants",_roster],
        ["assignedAt",time],
        ["activeAt",time],
        ["completedAt",-1],
        ["outcome",""],
        ["taskId",_taskId],
        ["sourceKey","RECON_LOST|" + str _targetGroup],
        ["rewardClass","RECON"]
    ];
    ITW_CLASH_PlayerJobs set [_jobId,_job];
    ["JOB_ASSIGNED",_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    ["JOB_ACTIVE",_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;

    _group setVariable ["ITW_CLASH_PlayerReconJobId",_jobId,true];
    _group setVariable ["ITW_CLASH_PlayerReconJobCancel",false,true];
    _group setVariable ["Busy" + str _group,true];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
        [_group,"requested-recon-assigned"] call
            ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
    };

    private _players = units _group select {isPlayer _x};
    [
        _players,
        _taskId,
        [
            format [
                "HAL lost contact with %1. Search the marked last-known area and positively reacquire the formation. Destruction is not required. The marker is the last legitimate HAL position and will not track the target.",
                _record getOrDefault ["lastKnownType","enemy contact"]
            ],
            "HAL Recon: Reacquire Contact",
            ""
        ],
        _lastKnownPos,
        "ASSIGNED",
        1,
        true,
        "scout",
        true
    ] call BIS_fnc_taskCreate;

    ["assigned",[
        _jobId,groupId _group,groupId _targetGroup,_lastKnownPos,
        _record getOrDefault ["lostAt",-1]
    ]] call ITW_CLASH_PlayerTaskRequestRecon_fnc_Log;
    [_jobId] spawn ITW_CLASH_PlayerTaskRequestRecon_fnc_Monitor;
    ["MATCHED","HAL recon task assigned: reacquire the lost contact.",_jobId] call
        ITW_CLASH_PlayerTaskRequests_fnc_Result
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskRequestReconBinder";
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
        diag_log "CLASH BOOT | player-task-request-recon-bind-timeout | RECON request remains unavailable";
    };

    ITW_CLASH_PlayerTaskRequestRecon_fnc_CancelGroupJobBase =
        ITW_CLASH_PlayerTasks_fnc_CancelGroupJob;
    ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {false};
        private _reconJob = _group getVariable ["ITW_CLASH_PlayerReconJobId",""];
        if (_reconJob isNotEqualTo "") exitWith {
            _group setVariable ["ITW_CLASH_PlayerReconJobCancel",true,true];
            ["cancel-requested",[_reconJob,groupId _group]] call
                ITW_CLASH_PlayerTaskRequestRecon_fnc_Log;
            true
        };
        _this call ITW_CLASH_PlayerTaskRequestRecon_fnc_CancelGroupJobBase
    };

    ["RECON",ITW_CLASH_PlayerTaskRequestRecon_fnc_Request] call
        ITW_CLASH_PlayerTaskRequests_fnc_RegisterAdapter;
    ITW_CLASH_PlayerTaskRequestReconReady = true;

    [] spawn {
        scriptName "ITW_CLASH_PlayerReconContactHistoryObserver";
        while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
            sleep ITW_CLASH_PlayerReconHistoryPoll;
            if (!missionNamespace getVariable ["ITW_CLASH_HALReady",false]) then {continue};
            private _hq = missionNamespace getVariable ["ITW_CLASH_BLUFORHQ",grpNull];
            if (isNull _hq) then {continue};
            [_hq] call ITW_CLASH_PlayerTaskRequestRecon_fnc_UpdateHistory;
        };
    };

    diag_log format [
        "CLASH BOOT | player-task-request-recon-ready | version=%1 vehicleAgnostic=true halKnownHistoryOnly=true revealsEnemies=false staleSeconds=%2 knowledgeThreshold=%3 lastKnownMarkerOnly=true rewardAuthorizationOnly=true",
        ITW_CLASH_PlayerTaskRequestReconVersion,
        ITW_CLASH_PlayerReconStaleSeconds,
        ITW_CLASH_PlayerReconKnowledgeThreshold
    ];
};

true
