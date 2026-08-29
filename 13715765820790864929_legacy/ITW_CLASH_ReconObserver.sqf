#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_ReconPhase0Started",false]) exitWith {};

ITW_CLASH_ReconPhase0Started = true;
ITW_CLASH_ReconPhase0Version = 4;
ITW_CLASH_ReconPollInterval = 2;
ITW_CLASH_ReconActiveGroups = createHashMap;

/*
    C.L.A.S.H. reconnaissance doctrine

    HAL owns reconnaissance selection and execution. Recon is a COMBAT-channel
    job for player groups; it is not a sixth employment subscription. AI groups
    retain HAL's native broad reconnaissance behavior.

    C.L.A.S.H. observes native GoRecon/GoDefRecon and adds only the player
    employment admission boundary. It does not spawn reconnaissance units,
    spend tickets, reveal targets, or create a second recon implementation.
*/

if (fileExists "ITW_CLASH_PlayerTaskStateHardening.sqf") then {
    private _stateHardening = call compile preprocessFileLineNumbers
        "ITW_CLASH_PlayerTaskStateHardening.sqf";
    if !(_stateHardening isEqualTo true) then {
        diag_log "CLASH BOOT | WARNING | player-task-state-hardening-load-failed | recon execution guard remains fail-closed for unsubscribed players";
    };
} else {
    diag_log "CLASH BOOT | WARNING | player-task-state-hardening-missing | recon execution guard remains fail-closed for unsubscribed players";
};

ITW_CLASH_Recon_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["recon-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_Recon_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_fnc_GroupId
    };
    str _group
};

ITW_CLASH_Recon_fnc_IsPlayerGroup = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsPlayerGroup") exitWith {
        [_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup
    };
    (units _group findIf {isPlayer _x}) >= 0
};

ITW_CLASH_Recon_fnc_PlayerCombatAllowed = {
    params ["_group"];
    if (isNull _group) exitWith {[false,"null-group"]};
    if !([_group] call ITW_CLASH_Recon_fnc_IsPlayerGroup) exitWith {
        [true,"ai-native"]
    };

    if (!isNil "ITW_CLASH_PlayerTasks_fnc_CanAcceptJob") exitWith {
        if ([_group,"COMBAT",true] call
            ITW_CLASH_PlayerTasks_fnc_CanAcceptJob
        ) then {
            [true,"combat-subscribed"]
        } else {
            [false,"combat-channel-disabled-or-held"]
        }
    };

    if (!isNil "ITW_CLASH_PlayerTasks_fnc_IsSubscribed") exitWith {
        if ([_group,"COMBAT"] call
            ITW_CLASH_PlayerTasks_fnc_IsSubscribed
        ) then {
            [true,"combat-subscribed-fallback"]
        } else {
            [false,"combat-channel-disabled"]
        }
    };

    // Player employment support exists on the tested branch. If its admission
    // API is unavailable, do not silently hand a player an unsolicited recon.
    [false,"player-employment-admission-unavailable"]
};

ITW_CLASH_Recon_fnc_RejectPlayerMission = {
    params ["_mode","_group","_hq","_destination","_reason"];
    if (isNull _group) exitWith {false};

    _group setVariable ["Busy" + str _group,false];
    _group setVariable ["ITW_CLASH_PlayerNativeJobId",nil,true];
    _group setVariable ["ITW_CLASH_PlayerNativeJobType",nil,true];
    _group setVariable ["ITW_CLASH_PlayerNativeJobCancelRequested",nil,true];
    _group setVariable ["ITW_CLASH_PlayerHasActiveHALJob",false,true];

    if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission") then {
        [_group] call ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission;
    };
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
        [_group,"recon-execution-rejected"] call
            ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
    };

    ["tasking-rejected",[
        [_group] call ITW_CLASH_Recon_fnc_GroupId,
        _mode,
        _reason,
        if (isNull _hq) then {"<null>"} else {
            _hq getVariable ["RydHQ_CodeSign","?"]
        },
        round (leader _group distance2D _destination),
        if (!isNil "ITW_CLASH_PlayerTasks_fnc_GetSubscriptions") then {
            [_group] call ITW_CLASH_PlayerTasks_fnc_GetSubscriptions
        } else {[]}
    ]] call ITW_CLASH_Recon_fnc_Log;
    true
};

ITW_CLASH_Recon_fnc_Classify = {
    params ["_group"];
    if (isNull _group) exitWith {[false,"null-group",0,0,[]]};
    if (!isNil "ITW_CLASH_SOF_fnc_Classify") exitWith {
        [_group] call ITW_CLASH_SOF_fnc_Classify
    };
    [false,"unclassified",0,{alive _x} count units _group,(units _group) apply {typeOf _x}]
};

ITW_CLASH_Recon_fnc_MonitorMission = {
    params ["_mode","_group","_hq"];
    if (isNull _group || {isNull _hq}) exitWith {};

    private _seen = [];
    private _knownAtStart = +(_hq getVariable ["RydHQ_KnEnemies",[]]);
    while {
        !isNull _group && {
            !isNull _hq && {
                (_group getVariable ["ITW_CLASH_ReconPhase0Active",false]) && {
                    {alive _x} count units _group > 0
                }
            }
        }
    } do {
        sleep ITW_CLASH_ReconPollInterval;
        if (isNull _group || {isNull _hq}) then {continue};

        private _targets = [];
        {
            if (isNull _x) then {continue};
            {
                if (alive _x) then {
                    _targets pushBackUnique (vehicle _x);
                };
            } forEach units _x;
        } forEach (_hq getVariable ["RydHQ_Enemies",[]]);

        {
            private _target = _x;
            if (isNull _target || {!alive _target} || {_target in _seen}) then {continue};

            private _knowledge = 0;
            {
                if (alive _x) then {
                    _knowledge = _knowledge max (_x knowsAbout _target);
                };
            } forEach units _group;
            if (_knowledge < 0.05) then {continue};

            _seen pushBack _target;
            private _globallyKnown = _target in (_hq getVariable ["RydHQ_KnEnemies",[]]);
            ["contact",[
                [_group] call ITW_CLASH_Recon_fnc_GroupId,
                _mode,
                typeOf _target,
                round (leader _group distance2D _target),
                _knowledge,
                _globallyKnown
            ]] call ITW_CLASH_Recon_fnc_Log;

            if (_globallyKnown && {!(_target in _knownAtStart)}) then {
                ["intel-gained",[
                    [_group] call ITW_CLASH_Recon_fnc_GroupId,
                    _mode,
                    typeOf _target,
                    round (leader _group distance2D _target),
                    _knowledge
                ]] call ITW_CLASH_Recon_fnc_Log;
                _knownAtStart pushBack _target;
            };
        } forEach _targets;
    };
};

ITW_CLASH_Recon_fnc_BeginMission = {
    params ["_mode","_group","_hq","_destination"];
    if (isNull _group || {isNull _hq}) exitWith {};

    private _classification = [_group] call ITW_CLASH_Recon_fnc_Classify;
    private _isSOF = _classification#0;
    private _jobId = "";

    if ([_group] call ITW_CLASH_Recon_fnc_IsPlayerGroup) then {
        _jobId = format [
            "HAL-COMBAT-RECON-%1-%2",
            round (diag_tickTime * 1000),
            [_group] call ITW_CLASH_Recon_fnc_GroupId
        ];
        _group setVariable ["ITW_CLASH_PlayerNativeJobId",_jobId,true];
        _group setVariable ["ITW_CLASH_PlayerNativeJobType","COMBAT",true];
        _group setVariable ["ITW_CLASH_PlayerNativeJobCancelRequested",false,true];
        _group setVariable ["ITW_CLASH_PlayerHasActiveHALJob",true,true];

        if (!isNil "ITW_CLASH_PlayerTasks_fnc_RecordEvent") then {
            ["NATIVE_COMBAT_ASSIGNED",createHashMapFromArray [
                ["jobId",_jobId],
                ["group",_group],
                ["mode",_mode],
                ["kind","RECON"],
                ["destination",+_destination],
                ["assignedAt",time]
            ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
        };
    };

    _group setVariable ["ITW_CLASH_ReconPhase0Active",true];
    _group setVariable ["ITW_CLASH_ReconPhase0Mode",_mode];
    ITW_CLASH_ReconActiveGroups set [str _group,[_group,_mode,time,_jobId]];

    ["assigned",[
        [_group] call ITW_CLASH_Recon_fnc_GroupId,
        _mode,
        _classification#1,
        _isSOF,
        {alive _x} count units _group,
        round (leader _group distance2D _destination),
        _destination,
        _jobId
    ]] call ITW_CLASH_Recon_fnc_Log;

    if (_isSOF) then {
        ["unexpected-specfor-assignment",[
            [_group] call ITW_CLASH_Recon_fnc_GroupId,
            _mode,
            _classification#1,
            _group in (_hq getVariable ["RydHQ_SpecForG",[]])
        ]] call ITW_CLASH_Recon_fnc_Log;
    };

    [_mode,_group,_hq] spawn ITW_CLASH_Recon_fnc_MonitorMission;
};

ITW_CLASH_Recon_fnc_EndMission = {
    params ["_mode","_group","_startedAt"];
    if (isNull _group) exitWith {};

    private _jobId = _group getVariable ["ITW_CLASH_PlayerNativeJobId",""];
    private _cancelRequested = _group getVariable [
        "ITW_CLASH_PlayerNativeJobCancelRequested",false
    ];

    _group setVariable ["ITW_CLASH_ReconPhase0Active",nil];
    _group setVariable ["ITW_CLASH_ReconPhase0Mode",nil];
    ITW_CLASH_ReconActiveGroups deleteAt (str _group);

    private _alive = {alive _x} count units _group;
    private _event = if (_alive == 0) then {"wiped"} else {
        if (_cancelRequested || {
            _group getVariable ["ITW_CLASH_Withdrawing",false]
        }) then {"aborted"} else {"complete"}
    };
    [_event,[
        [_group] call ITW_CLASH_Recon_fnc_GroupId,
        _mode,
        _alive,
        round (time - _startedAt),
        _jobId
    ]] call ITW_CLASH_Recon_fnc_Log;

    if (_jobId isNotEqualTo "" && {
        !isNil "ITW_CLASH_PlayerTasks_fnc_RecordEvent"
    }) then {
        private _recordType = if (_alive == 0) then {
            "NATIVE_COMBAT_FAILED"
        } else {
            if (_cancelRequested) then {
                "NATIVE_COMBAT_CANCELED"
            } else {
                "NATIVE_COMBAT_COMPLETED"
            }
        };
        [_recordType,createHashMapFromArray [
            ["jobId",_jobId],
            ["group",_group],
            ["mode",_mode],
            ["kind","RECON"],
            ["alive",_alive],
            ["duration",round (time - _startedAt)]
        ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    };

    _group setVariable ["ITW_CLASH_PlayerNativeJobId",nil,true];
    _group setVariable ["ITW_CLASH_PlayerNativeJobType",nil,true];
    _group setVariable ["ITW_CLASH_PlayerNativeJobCancelRequested",nil,true];

    if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState") then {
        [_group,"native-recon-ended"] call
            ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
    };
};

[] spawn {
    scriptName "ITW_CLASH_ReconObserver";

    private _deadline = time + 120;
    waitUntil {
        sleep 0.25;
        (
            missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]
            && {missionNamespace getVariable ["ITW_CLASH_HALReady",false]}
            && {!isNil "HAL_GoRecon"}
            && {!isNil "HAL_GoDefRecon"}
        ) || {time > _deadline}
    };

    if !(missionNamespace getVariable ["ITW_CLASH_HALReady",false]) exitWith {
        ITW_CLASH_ReconPhase0Started = false;
        diag_log "CLASH BOOT | recon-observer-deferred | HAL not ready; native HAL recon retained";
    };
    if (isNil "HAL_GoRecon" || {isNil "HAL_GoDefRecon"}) exitWith {
        ITW_CLASH_ReconPhase0Started = false;
        diag_log "CLASH BOOT | recon-observer-fail-open | native HAL recon functions unavailable";
    };

    ITW_CLASH_Recon_fnc_NativeGoRecon = HAL_GoRecon;
    ITW_CLASH_Recon_fnc_NativeGoDefRecon = HAL_GoDefRecon;

    HAL_GoRecon = {
        private _group = _this param [0,grpNull];
        private _destination = _this param [1,[]];
        private _hq = _this param [3,grpNull];
        if (isNull _hq && {!isNil "ITW_CLASH_fnc_GetCommanderForGroup"}) then {
            _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
        };
        if (isNull _hq && {!isNil "ITW_CLASH_fnc_GetCommanderForSide"}) then {
            _hq = [side _group] call ITW_CLASH_fnc_GetCommanderForSide;
        };
        if (isNull _hq && {
            !isNil "ITW_EnemySide" && {side _group == ITW_EnemySide}
        }) then {
            _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
        };

        private _admission = [_group] call
            ITW_CLASH_Recon_fnc_PlayerCombatAllowed;
        if !(_admission#0) exitWith {
            [
                "offensive",_group,_hq,_destination,_admission#1
            ] call ITW_CLASH_Recon_fnc_RejectPlayerMission;
            false
        };

        private _startedAt = time;
        ["offensive",_group,_hq,_destination] call ITW_CLASH_Recon_fnc_BeginMission;
        _this call ITW_CLASH_Recon_fnc_NativeGoRecon;
        ["offensive",_group,_startedAt] call ITW_CLASH_Recon_fnc_EndMission;
        true
    };

    HAL_GoDefRecon = {
        private _group = _this param [0,grpNull];
        private _destination = _this param [1,[]];
        private _hq = _this param [3,grpNull];
        if (isNull _hq && {!isNil "ITW_CLASH_fnc_GetCommanderForGroup"}) then {
            _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
        };
        if (isNull _hq && {!isNil "ITW_CLASH_fnc_GetCommanderForSide"}) then {
            _hq = [side _group] call ITW_CLASH_fnc_GetCommanderForSide;
        };
        if (isNull _hq && {
            !isNil "ITW_EnemySide" && {side _group == ITW_EnemySide}
        }) then {
            _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
        };

        private _admission = [_group] call
            ITW_CLASH_Recon_fnc_PlayerCombatAllowed;
        if !(_admission#0) exitWith {
            [
                "defensive",_group,_hq,_destination,_admission#1
            ] call ITW_CLASH_Recon_fnc_RejectPlayerMission;
            false
        };

        private _startedAt = time;
        ["defensive",_group,_hq,_destination] call ITW_CLASH_Recon_fnc_BeginMission;
        _this call ITW_CLASH_Recon_fnc_NativeGoDefRecon;
        ["defensive",_group,_startedAt] call ITW_CLASH_Recon_fnc_EndMission;
        true
    };

    diag_log format [
        "CLASH BOOT | recon-observer-ready | version=%1 nativeBroadRecon=true playerCombatAdmission=true observerOnlyAI=true commanderAware=true spawning=false requisition=false reveal=false",
        ITW_CLASH_ReconPhase0Version
    ];
};
