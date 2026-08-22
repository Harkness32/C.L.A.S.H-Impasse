if (!hasInterface || {isServer}) exitWith {true};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskClientStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskClientStarted = true;
ITW_CLASH_PlayerTaskClientReady = false;

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskClientBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.25;
        diag_tickTime >= _deadline || {
            !isNil "Action1ct" && {!isNil "Action2ct"} && {!isNil "Action3ct"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH PLAYER TASK CLIENT | native HAL action bind timeout";
    };

    ITW_CLASH_PlayerTaskClient_fnc_NativeAction1 = Action1ct;
    ITW_CLASH_PlayerTaskClient_fnc_NativeAction2 = Action2ct;
    ITW_CLASH_PlayerTaskClient_fnc_NativeAction3 = Action3ct;

    Action1ct = {
        private _result = _this call ITW_CLASH_PlayerTaskClient_fnc_NativeAction1;
        [player] remoteExecCall ["ITW_CLASH_PlayerTasks_fnc_CancelRemote",2];
        _result
    };
    Action2ct = {
        private _result = _this call ITW_CLASH_PlayerTaskClient_fnc_NativeAction2;
        [player,false] remoteExecCall ["ITW_CLASH_PlayerTasks_fnc_SetOptInRemote",2];
        _result
    };
    Action3ct = {
        private _result = _this call ITW_CLASH_PlayerTaskClient_fnc_NativeAction3;
        [player,true] remoteExecCall ["ITW_CLASH_PlayerTasks_fnc_SetOptInRemote",2];
        _result
    };

    ITW_CLASH_PlayerTaskClientReady = true;
    diag_log "CLASH PLAYER TASK CLIENT | ready | native HAL toggle bridged";
};

true
