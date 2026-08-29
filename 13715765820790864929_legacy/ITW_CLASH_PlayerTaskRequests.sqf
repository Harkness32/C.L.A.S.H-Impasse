#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestsStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestsStarted = true;
ITW_CLASH_PlayerTaskRequestsReady = false;
ITW_CLASH_PlayerTaskRequestsVersion = 3;
ITW_CLASH_PlayerTaskRequestAdapters = createHashMap;
ITW_CLASH_PlayerTaskRequestTypes = [
    "STRIKE_SOFT","STRIKE_LIGHT_ARMOR","STRIKE_HEAVY_ARMOR",
    "RECON","ARTILLERY","TRANSPORT"
];

ITW_CLASH_PlayerTaskRequests_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_Log") then {
        ["task-request-" + _event,_payload] call ITW_CLASH_PlayerTasks_fnc_Log;
    } else {
        diag_log format ["CLASH TASK REQUEST | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerTaskRequests_fnc_Result = {
    params ["_status","_message",["_jobId",""]];
    createHashMapFromArray [
        ["status",_status],
        ["message",_message],
        ["jobId",_jobId]
    ]
};

ITW_CLASH_PlayerTaskRequests_fnc_SendResponse = {
    params ["_player","_result"];
    if (isNull _player || {!isPlayer _player}) exitWith {false};
    if !(_result isEqualType createHashMap) exitWith {false};

    [
        _result getOrDefault ["status","REJECTED"],
        _result getOrDefault ["message","HAL task request rejected."],
        _result getOrDefault ["jobId",""]
    ] remoteExecCall [
        "ITW_CLASH_PlayerTaskRequestMenu_fnc_ReceiveResponse",owner _player
    ];
    true
};

ITW_CLASH_PlayerTaskRequests_fnc_HasActiveJob = {
    params ["_group"];
    if (isNull _group) exitWith {false};

    if (
        (_group getVariable ["ITW_CLASH_PlayerTaskRequestActiveJobId",""])
        isNotEqualTo ""
    ) exitWith {true};
    if (
        (_group getVariable ["ITW_CLASH_PlayerStrikeJobId",""])
        isNotEqualTo ""
    ) exitWith {true};
    if (
        (_group getVariable ["ITW_CLASH_PlayerReconJobId",""])
        isNotEqualTo ""
    ) exitWith {true};

    if (!isNil "ITW_CLASH_PlayerTasks_fnc_HasActiveJob") exitWith {
        [_group] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob
    };
    ((_group getVariable ["ITW_CLASH_PlayerDemandJobId",""]) isNotEqualTo "")
    || {(_group getVariable ["ITW_CLASH_PlayerArtilleryJobId",""]) isNotEqualTo ""}
    || {(_group getVariable ["ITW_CLASH_PlayerAmmoJobId",""]) isNotEqualTo ""}
    || {(_group getVariable ["ITW_CLASH_PlayerNativeJobId",""]) isNotEqualTo ""}
    || {_group getVariable ["ITW_CLASH_PlayerHasActiveHALJob",false]}
};

ITW_CLASH_PlayerTaskRequests_fnc_ReleaseActiveLease = {
    params ["_group","_jobId",["_reason","terminal"]];
    if (isNull _group || {_jobId isEqualTo ""}) exitWith {false};
    if (
        (_group getVariable ["ITW_CLASH_PlayerTaskRequestActiveJobId",""])
        != _jobId
    ) exitWith {false};

    _group setVariable ["ITW_CLASH_PlayerTaskRequestActiveJobId",nil,true];
    ["active-lease-released",[_jobId,groupId _group,_reason]] call
        ITW_CLASH_PlayerTaskRequests_fnc_Log;

    if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
        [_group,"request-lease-released"] call
            ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
    };
    true
};

ITW_CLASH_PlayerTaskRequests_fnc_WatchActiveLease = {
    params ["_group","_jobId"];
    if (isNull _group || {_jobId isEqualTo ""}) exitWith {};

    while {
        !isNull _group
        && {
            (_group getVariable ["ITW_CLASH_PlayerTaskRequestActiveJobId",""])
            == _jobId
        }
    } do {
        sleep 0.25;

        private _job = ITW_CLASH_PlayerJobs getOrDefault [
            _jobId,createHashMap
        ];
        if (count _job == 0) exitWith {
            [_group,_jobId,"job-missing"] call
                ITW_CLASH_PlayerTaskRequests_fnc_ReleaseActiveLease;
        };

        private _state = _job getOrDefault ["state",""];
        if (_state in ["COMPLETED","FAILED","CANCELED"]) exitWith {
            // Reconcile the visible BIS task as a final safety net. Specialist
            // finishers remain authoritative; this only prevents a stale task
            // from surviving a terminal backend state after an unrelated error.
            private _taskId = _job getOrDefault ["taskId",""];
            if (_taskId isNotEqualTo "") then {
                [
                    _taskId,
                    switch (_state) do {
                        case "COMPLETED": {"SUCCEEDED"};
                        case "CANCELED": {"CANCELED"};
                        default {"FAILED"};
                    },
                    true
                ] call BIS_fnc_taskSetState;
            };
            [_group,_jobId,"job-" + toLowerANSI _state] call
                ITW_CLASH_PlayerTaskRequests_fnc_ReleaseActiveLease;
        };
    };
};

ITW_CLASH_PlayerTaskRequests_fnc_FailMatchedJob = {
    params ["_jobId",["_reason","assigned-player-killed"]];
    if (_jobId isEqualTo "") exitWith {false};

    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    if (count _job == 0) exitWith {false};
    if ((_job getOrDefault ["origin",""]) != "PLAYER_REQUEST") exitWith {
        false
    };
    if ((_job getOrDefault ["state",""]) in [
        "COMPLETED","FAILED","CANCELED"
    ]) exitWith {false};

    private _requestType = _job getOrDefault ["requestType",""];
    if (((_requestType find "STRIKE_") == 0) && {
        !isNil "ITW_CLASH_PlayerTaskRequestStrike_fnc_Finish"
    }) exitWith {
        [_jobId,"FAILED",_reason] call
            ITW_CLASH_PlayerTaskRequestStrike_fnc_Finish
    };
    if (_requestType == "RECON" && {
        !isNil "ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish"
    }) exitWith {
        [_jobId,"FAILED",_reason] call
            ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish
    };
    if (_requestType == "ARTILLERY" && {
        !isNil "ITW_CLASH_PlayerArtillery_fnc_FinishJob"
    }) exitWith {
        [_jobId,"FAILED",_reason] call
            ITW_CLASH_PlayerArtillery_fnc_FinishJob
    };

    ["death-fail-unhandled",[_jobId,_requestType,_reason]] call
        ITW_CLASH_PlayerTaskRequests_fnc_Log;
    false
};

ITW_CLASH_PlayerTaskRequestDeathEH = addMissionEventHandler [
    "EntityKilled",
    {
        params ["_killed"];
        if (!isServer || {isNull _killed} || {!isPlayer _killed}) exitWith {};

        private _uid = getPlayerUID _killed;
        if (_uid isEqualTo "") exitWith {};

        private _jobsToFail = [];
        {
            private _jobId = _x;
            private _job = _y;
            if ((_job getOrDefault ["origin",""]) != "PLAYER_REQUEST") then {
                continue
            };
            if ((_job getOrDefault ["state",""]) in [
                "COMPLETED","FAILED","CANCELED"
            ]) then {continue};

            private _participants = _job getOrDefault ["participants",[]];
            if ((_participants findIf {
                (_x param [0,""]) == _uid
            }) >= 0) then {
                _jobsToFail pushBackUnique _jobId;
            };
        } forEach ITW_CLASH_PlayerJobs;

        {
            ["assigned-player-killed",[
                _x,_uid,name _killed
            ]] call ITW_CLASH_PlayerTaskRequests_fnc_Log;
            [_x,"assigned-player-killed"] call
                ITW_CLASH_PlayerTaskRequests_fnc_FailMatchedJob;
        } forEach _jobsToFail;
    }
];

ITW_CLASH_PlayerTaskRequests_fnc_RegisterAdapter = {
    params ["_requestType","_function"];
    if !(_requestType isEqualType "" && {_function isEqualType {}}) exitWith {false};
    _requestType = toUpperANSI _requestType;
    if !(_requestType in ITW_CLASH_PlayerTaskRequestTypes) exitWith {false};
    ITW_CLASH_PlayerTaskRequestAdapters set [_requestType,_function];
    ["adapter-registered",[_requestType]] call ITW_CLASH_PlayerTaskRequests_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequests_fnc_AdapterUnavailable = {
    params ["_group","_hq","_requestType"];
    [
        "UNAVAILABLE",
        format ["%1 task requests are not source-certified on this build yet.",_requestType]
    ] call ITW_CLASH_PlayerTaskRequests_fnc_Result
};

ITW_CLASH_PlayerTaskRequests_fnc_HandleRemote = {
    params ["_player","_requestType"];

    if !(_requestType isEqualType "") exitWith {false};
    _requestType = toUpperANSI _requestType;

    if (
        isNil "ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid"
        || {!([_player,true] call ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid)}
    ) exitWith {false};

    private _group = group _player;
    private _result = createHashMap;

    if !(_requestType in ITW_CLASH_PlayerTaskRequestTypes) exitWith {
        _result = ["REJECTED","Unknown HAL task request type."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
        [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
        false
    };

    ["requested",[
        getPlayerUID _player,
        groupId _group,
        _requestType,
        getPosATL _player
    ]] call ITW_CLASH_PlayerTaskRequests_fnc_Log;

    if (isNil "ITW_PlayerSide" || {side _group != ITW_PlayerSide}) exitWith {
        _result = ["REJECTED","Unable. Group is outside the player HAL command."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
        [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
        false
    };

    if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {
        _result = ["AUTHORITY_HOLD","Unable. Group is not available for HAL tasking."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
        [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
        ["response",[_requestType,"AUTHORITY_HOLD",groupId _group]] call
            ITW_CLASH_PlayerTaskRequests_fnc_Log;
        false
    };

    private _claimUntil = _group getVariable [
        "ITW_CLASH_PlayerTaskRequestClaimUntil",0
    ];
    if (_claimUntil > 0 && {diag_tickTime >= _claimUntil}) then {
        _group setVariable ["ITW_CLASH_PlayerTaskRequestClaimUntil",nil];
        _claimUntil = 0;
    };
    if (diag_tickTime < _claimUntil) exitWith {
        _result = [
            "BUSY",
            "Unable. HAL is already assigning a task to your group."
        ] call ITW_CLASH_PlayerTaskRequests_fnc_Result;
        [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
        ["response",[_requestType,"CLAIM_IN_FLIGHT",groupId _group]] call
            ITW_CLASH_PlayerTaskRequests_fnc_Log;
        false
    };

    if ([_group] call ITW_CLASH_PlayerTaskRequests_fnc_HasActiveJob) exitWith {
        _result = ["BUSY","Unable. Your group already has an active HAL task."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
        [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
        ["response",[_requestType,"BUSY",groupId _group]] call
            ITW_CLASH_PlayerTaskRequests_fnc_Log;
        false
    };

    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {grpNull};
    if (isNull _hq) exitWith {
        _result = ["NO_TASK","No HAL commander is currently available for your group."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
        [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
        false
    };

    private _adapter = ITW_CLASH_PlayerTaskRequestAdapters getOrDefault [
        _requestType,ITW_CLASH_PlayerTaskRequests_fnc_AdapterUnavailable
    ];

    // This is a concurrency claim, not a player-facing cooldown. It exists
    // only while one request is being resolved so two near-simultaneous menu
    // clicks cannot both pass the empty-job test.
    _group setVariable [
        "ITW_CLASH_PlayerTaskRequestClaimUntil",
        diag_tickTime + 5
    ];
    _result = [_group,_hq,_requestType] call _adapter;
    _group setVariable ["ITW_CLASH_PlayerTaskRequestClaimUntil",nil];

    if !(_result isEqualType createHashMap) then {
        _result = ["REJECTED","HAL task adapter returned an invalid response."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
    };

    private _status = _result getOrDefault ["status","REJECTED"];
    private _jobId = _result getOrDefault ["jobId",""];
    if (_status == "MATCHED" && {_jobId isEqualTo ""}) then {
        _result = [
            "REJECTED",
            "HAL task adapter matched work without a valid job identifier."
        ] call ITW_CLASH_PlayerTaskRequests_fnc_Result;
        _status = "REJECTED";
    };

    if (_status == "MATCHED") then {
        _group setVariable [
            "ITW_CLASH_PlayerTaskRequestActiveJobId",_jobId,true
        ];
        ["active-lease-acquired",[
            _jobId,groupId _group,_requestType
        ]] call ITW_CLASH_PlayerTaskRequests_fnc_Log;
        [_group,_jobId] spawn
            ITW_CLASH_PlayerTaskRequests_fnc_WatchActiveLease;
    };

    [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
    ["response",[
        _requestType,
        _result getOrDefault ["status","REJECTED"],
        _result getOrDefault ["jobId",""],
        groupId _group
    ]] call ITW_CLASH_PlayerTaskRequests_fnc_Log;

    (_result getOrDefault ["status",""]) == "MATCHED"
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskRequestRouterBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskSupportReady",false]
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_HasActiveJob"}
            && {!isNil "ITW_CLASH_fnc_GetCommanderForGroup"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-task-request-router-bind-timeout | request UI remains fail-closed";
    };

    ITW_CLASH_PlayerTaskRequestsReady = true;
    publicVariable "ITW_CLASH_PlayerTaskRequestsReady";
    diag_log format [
        "CLASH BOOT | player-task-request-router-ready | version=%1 ephemeralRequests=true leaderAuthority=true subscriptionsRequired=false oneActiveJob=true sharedActiveLease=true deathFailsTask=true queryCooldown=false",
        ITW_CLASH_PlayerTaskRequestsVersion
    ];
};

// NativeInterceptors still boots the router directly on this stacked branch.
// From here, hand adapter loading to one bootstrap so later STRIKE/RECON/
// TRANSPORT phases do not require repeatedly editing that high-risk file.
if (
    fileExists "ITW_CLASH_PlayerTaskRequestBootstrap.sqf"
    && {!(missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestBootstrapStarted",false])}
) then {
    call compile preprocessFileLineNumbers "ITW_CLASH_PlayerTaskRequestBootstrap.sqf";
};

true
