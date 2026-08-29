#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AusterityStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_PlayerTasks_fnc_RecordEvent") exitWith {
    diag_log "CLASH AUSTERITY | load rejected | PlayerTaskSupport unavailable";
    false
};

ITW_CLASH_AusterityStarted = true;
ITW_CLASH_AusterityVersion = 1;
ITW_CLASH_AusterityTaskReward = 1000;
ITW_CLASH_AusterityCash = createHashMap;
ITW_CLASH_AusterityRewardedJobs = createHashMap;

ITW_CLASH_Austerity_fnc_Log = {
    params ["_event",["_payload",[]]];
    diag_log format ["CLASH AUSTERITY | %1 | %2",_event,_payload];
};

ITW_CLASH_Austerity_fnc_GetCash = {
    params [["_uid",""]];
    if (_uid isEqualTo "") exitWith {0};
    ITW_CLASH_AusterityCash getOrDefault [_uid,0]
};

ITW_CLASH_Austerity_fnc_PublishCash = {
    params [["_uid",""],["_delta",0],["_reason","sync"]];
    if (_uid isEqualTo "") exitWith {false};

    private _cash = [_uid] call ITW_CLASH_Austerity_fnc_GetCash;
    private _player = (allPlayers select {
        isPlayer _x && {getPlayerUID _x == _uid}
    }) param [0,objNull];

    if (isNull _player) exitWith {false};
    [_cash,_delta,_reason] remoteExecCall [
        "ITW_CLASH_AusterityClient_fnc_ReceiveCash",
        owner _player
    ];
    true
};

ITW_CLASH_Austerity_fnc_Award = {
    params [["_uid",""],["_amount",0],["_reason","hal-task"]];
    if (_uid isEqualTo "" || {_amount <= 0}) exitWith {false};

    private _old = [_uid] call ITW_CLASH_Austerity_fnc_GetCash;
    private _new = _old + _amount;
    ITW_CLASH_AusterityCash set [_uid,_new];

    [_uid,_amount,_reason] call ITW_CLASH_Austerity_fnc_PublishCash;
    ["cash-awarded",[_uid,_amount,_new,_reason]] call ITW_CLASH_Austerity_fnc_Log;
    true
};

ITW_CLASH_Austerity_fnc_HandleCompletedJob = {
    params [["_job",createHashMap]];
    if !(_job isEqualType createHashMap) exitWith {false};

    private _jobId = _job getOrDefault ["id",""];
    if (_jobId isEqualTo "") exitWith {false};
    if (ITW_CLASH_AusterityRewardedJobs getOrDefault [_jobId,false]) exitWith {
        false
    };

    private _participants = _job getOrDefault ["participants",[]];
    if !(_participants isEqualType [] && {_participants isNotEqualTo []}) exitWith {
        false
    };

    ITW_CLASH_AusterityRewardedJobs set [_jobId,true];
    private _paid = 0;
    {
        private _uid = _x param [0,""];
        if (_uid isNotEqualTo "") then {
            if ([
                _uid,
                ITW_CLASH_AusterityTaskReward,
                "hal-task-completed:" + _jobId
            ] call ITW_CLASH_Austerity_fnc_Award) then {
                _paid = _paid + 1;
            };
        };
    } forEach _participants;

    ["job-paid",[
        _jobId,
        _job getOrDefault ["type",""],
        _job getOrDefault ["requestType",""],
        _paid,
        ITW_CLASH_AusterityTaskReward
    ]] call ITW_CLASH_Austerity_fnc_Log;
    _paid > 0
};

[] spawn {
    scriptName "ITW_CLASH_AusterityRewardObserver";

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        {
            private _jobId = _x;
            private _job = _y;

            if (
                (_job getOrDefault ["state",""]) == "COMPLETED"
                && {
                    !(ITW_CLASH_AusterityRewardedJobs getOrDefault [
                        _jobId,false
                    ])
                }
            ) then {
                [_job] call ITW_CLASH_Austerity_fnc_HandleCompletedJob;
            };
        } forEach ITW_CLASH_PlayerJobs;

        sleep 0.5;
    };
};

ITW_CLASH_Austerity_fnc_RequestSync = {
    params [["_player",objNull]];
    if (isNull _player || {!isPlayer _player}) exitWith {false};
    if (isRemoteExecuted && {remoteExecutedOwner != owner _player}) exitWith {
        false
    };

    private _uid = getPlayerUID _player;
    if (_uid isEqualTo "") exitWith {false};
    [_uid,0,"sync"] call ITW_CLASH_Austerity_fnc_PublishCash
};

diag_log format [
    "CLASH AUSTERITY | ready | version=%1 rewardPerCompletedHalJob=$%2 startingCash=$0 persistence=session-only",
    ITW_CLASH_AusterityVersion,
    ITW_CLASH_AusterityTaskReward
];

true
