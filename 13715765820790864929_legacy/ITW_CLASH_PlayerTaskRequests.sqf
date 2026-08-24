#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestsStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestsStarted = true;
ITW_CLASH_PlayerTaskRequestsReady = false;
ITW_CLASH_PlayerTaskRequestsVersion = 1;
ITW_CLASH_PlayerTaskRequestCooldown = missionNamespace getVariable [
    "ITW_CLASH_PlayerTaskRequestCooldown",15
];
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
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_HasActiveJob") exitWith {
        [_group] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob
    };
    ((_group getVariable ["ITW_CLASH_PlayerDemandJobId",""]) isNotEqualTo "")
    || {(_group getVariable ["ITW_CLASH_PlayerArtilleryJobId",""]) isNotEqualTo ""}
    || {(_group getVariable ["ITW_CLASH_PlayerAmmoJobId",""]) isNotEqualTo ""}
    || {(_group getVariable ["ITW_CLASH_PlayerNativeJobId",""]) isNotEqualTo ""}
    || {_group getVariable ["ITW_CLASH_PlayerHasActiveHALJob",false]}
};

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

    if ([_group] call ITW_CLASH_PlayerTaskRequests_fnc_HasActiveJob) exitWith {
        _result = ["BUSY","Unable. Your group already has an active HAL task."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
        [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
        ["response",[_requestType,"BUSY",groupId _group]] call
            ITW_CLASH_PlayerTaskRequests_fnc_Log;
        false
    };

    private _nextAllowed = _group getVariable ["ITW_CLASH_PlayerTaskRequestNextAt",0];
    if (time < _nextAllowed) exitWith {
        _result = ["COOLDOWN","HAL is still processing your last task query."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
        [_player,_result] call ITW_CLASH_PlayerTaskRequests_fnc_SendResponse;
        false
    };
    _group setVariable [
        "ITW_CLASH_PlayerTaskRequestNextAt",
        time + ITW_CLASH_PlayerTaskRequestCooldown
    ];

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
    _result = [_group,_hq,_requestType] call _adapter;
    if !(_result isEqualType createHashMap) then {
        _result = ["REJECTED","HAL task adapter returned an invalid response."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result;
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
        "CLASH BOOT | player-task-request-router-ready | version=%1 ephemeralRequests=true leaderAuthority=true subscriptionsRequired=false oneActiveJob=true cooldown=%2",
        ITW_CLASH_PlayerTaskRequestsVersion,
        ITW_CLASH_PlayerTaskRequestCooldown
    ];
};

// NativeInterceptors still boots the router directly on this stacked branch.
// From here, hand adapter loading to one bootstrap so later STRIKE/RECON/
// TRANSPORT phases do not require repeatedly editing that high-risk file.
if (
    fileExists "ITW_CLASH_PlayerTaskRequestBootstrap.sqf"
    && {!missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestBootstrapStarted",false]}
) then {
    call compile preprocessFileLineNumbers "ITW_CLASH_PlayerTaskRequestBootstrap.sqf";
};

true
