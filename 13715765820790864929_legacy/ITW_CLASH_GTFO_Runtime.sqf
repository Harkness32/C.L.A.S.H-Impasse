#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_GTFORuntimeStarted",false]) exitWith {};
ITW_CLASH_GTFORuntimeStarted = true;
ITW_CLASH_GTFORuntimeVersion = 3;
ITW_CLASH_GTFO_ArrivalRadius = 160;
ITW_CLASH_GTFO_RestRestartGrace = 90;
ITW_CLASH_GTFO_RestRestartProgress = 25;
ITW_CLASH_GTFO_RestRestartBreakWait = 45;
ITW_CLASH_GTFORuntimeProgress = createHashMap;

// Native GoRest deliberately randomizes a RestDecoy rally by up to +/-100 m on
// each horizontal axis. Its farthest valid rally is therefore ~141 m from the
// Impasse corridor center. Keep rear absorption outside that entire native HAL
// jitter envelope so a successful HAL withdrawal cannot stop 10-20 m short of
// the old 125 m C.L.A.S.H. bubble and wait forever.
if (!isNil "ITW_CLASH_WithdrawalArrivalRadius") then {
    ITW_CLASH_WithdrawalArrivalRadius = ITW_CLASH_WithdrawalArrivalRadius max ITW_CLASH_GTFO_ArrivalRadius;
};

/*
    Late-bound GTFO adapters.

    The synchronous GTFO controller bridge loads before Recon and recovery
    modules exist. These adapters enforce only cross-system authority boundaries:
      - GTFO groups cannot be assigned recon.
      - Recovery becomes exclusive only after physical boarding completes.
      - A pre-boarding recovery abort explicitly restarts HAL's native GoRest
        after the abandoned rendezvous order has unwound.
      - Stale HAL garrison/defense memberships are removed while a group is GTFO.
      - A real Busy=true / Resting=false / no-progress stall uses HAL's native
        Break mechanism and then relaunches HAL_GoRest; C.L.A.S.H. never invents
        a withdrawal MOVE waypoint or blindly clears Busy.
*/

ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal = {
    params ["_group"];
    if (isNull _group || {!(_group getVariable ["ITW_CLASH_GTFO",false])}) exitWith {
        false
    };
    (_group getVariable ["ITW_CLASH_Managed",false])
    || {
        !isNil "ITW_PlayerSide"
        && {side _group == ITW_PlayerSide}
        && {_group getVariable ["ITW_CLASH_DualHALManaged",false]}
    }
};

ITW_CLASH_GTFO_fnc_GetCommander = {
    params ["_group"];
    if (isNull _group) exitWith {grpNull};
    private _hq = grpNull;
    if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
    };
    if (isNull _hq && {
        !isNil "ITW_EnemySide" && {side _group == ITW_EnemySide}
    }) then {
        _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
    };
    _hq
};

ITW_CLASH_GTFO_fnc_ClearStaleHALRoles = {
    params ["_group",["_source","watch"]];
    if !([_group] call ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal) exitWith {[]};
    private _hq = [_group] call ITW_CLASH_GTFO_fnc_GetCommander;
    if (isNull _hq) exitWith {[]};

    private _removed = [];
    {
        private _name = _x;
        private _members = +(_hq getVariable [_name,[]]);
        if (_group in _members) then {
            _hq setVariable [_name,_members - [_group]];
            _removed pushBack _name;
        };
    } forEach [
        "RydHQ_Garrison",
        "RydHQ_DefSpot",
        "RydHQ_Def",
        "RydHQ_DefRes",
        "RydHQ_RecDefSpot"
    ];

    if (_group getVariable ["Defending",false]) then {
        _group setVariable ["Defending",false];
        _removed pushBackUnique "Defending";
    };

    if (_removed isNotEqualTo []) then {
        ["hal-role-cleanup",[
            [_group] call ITW_CLASH_fnc_GroupId,
            _source,
            _removed,
            _group getVariable ["ITW_CLASH_GTFO_State",""]
        ]] call ITW_CLASH_GTFO_fnc_Log;
    };
    _removed
};

ITW_CLASH_GTFO_fnc_RequestNativeRestRestart = {
    params ["_mode","_group","_reason"];
    if !([_group] call ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal) exitWith {false};
    if (_group getVariable ["ITW_CLASH_GTFO_RestRestartPending",false]) exitWith {false};

    _group setVariable ["ITW_CLASH_GTFO_RestRestartPending",true];
    [_mode,_group,_reason] spawn {
        params ["_mode","_group","_reason"];
        if (isNull _group) exitWith {};

        private _unitVar = str _group;
        private _wasBusy = _group getVariable ["Busy" + _unitVar,false];
        private _wasResting = _group getVariable ["Resting" + _unitVar,false];

        [_group,"rest-restart"] call ITW_CLASH_GTFO_fnc_ClearStaleHALRoles;

        // Break is HAL's native cancellation surface. Do not clear Busy by hand:
        // the order that owns Busy must unwind and release it itself.
        if (_wasBusy || {_wasResting}) then {
            _group setVariable ["Break",true];
        };

        ["rest-restart-requested",[
            [_group] call ITW_CLASH_fnc_GroupId,
            _mode,
            _reason,
            _wasBusy,
            _wasResting
        ]] call ITW_CLASH_GTFO_fnc_Log;

        private _deadline = time + ITW_CLASH_GTFO_RestRestartBreakWait;
        waitUntil {
            sleep 1;
            isNull _group || {
                !(_group getVariable ["ITW_CLASH_GTFO",false]) || {
                    !([_group] call ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal) || {
                        (
                            !(_group getVariable ["Busy" + str _group,false]) &&
                            {!(_group getVariable ["Resting" + str _group,false])} &&
                            {!(_group getVariable ["Break",false])}
                        ) || {time >= _deadline}
                    }
                }
            }
        };

        if (isNull _group) exitWith {};
        if !(_group getVariable ["ITW_CLASH_GTFO",false]) exitWith {
            _group setVariable ["ITW_CLASH_GTFO_RestRestartPending",nil];
        };
        if !([_group] call ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal) exitWith {
            _group setVariable ["ITW_CLASH_GTFO_RestRestartPending",nil];
        };
        if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "" ||
            {(_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo ""}) exitWith {
            _group setVariable ["ITW_CLASH_GTFO_RestRestartPending",nil];
        };

        private _busy = _group getVariable ["Busy" + str _group,false];
        private _resting = _group getVariable ["Resting" + str _group,false];
        if (_busy || {_resting}) exitWith {
            ["rest-restart-deferred",[
                [_group] call ITW_CLASH_fnc_GroupId,
                _mode,
                _reason,
                _busy,
                _resting,
                _group getVariable ["Break",false],
                round ITW_CLASH_GTFO_RestRestartBreakWait
            ]] call ITW_CLASH_GTFO_fnc_Log;
            _group setVariable ["ITW_CLASH_GTFO_RestRestartPending",nil];
        };

        [_group,"pre-dispatch"] call ITW_CLASH_GTFO_fnc_ClearStaleHALRoles;
        if (!isNil "ITW_CLASH_GTFO_fnc_SetPersistentConstraints") then {
            [_group,true] call ITW_CLASH_GTFO_fnc_SetPersistentConstraints;
        };
        private _hq = [_group] call ITW_CLASH_GTFO_fnc_GetCommander;

        if (isNil "HAL_GoRest" || {isNil "RYD_Spawn"} || {isNull _hq}) exitWith {
            ["rest-restart-unavailable",[
                [_group] call ITW_CLASH_fnc_GroupId,
                _mode,
                _reason,
                isNil "HAL_GoRest",
                isNil "RYD_Spawn",
                isNull _hq
            ]] call ITW_CLASH_GTFO_fnc_Log;
            _group setVariable ["ITW_CLASH_GTFO_RestRestartPending",nil];
        };

        [[_group,_hq,true],HAL_GoRest] call RYD_Spawn;
        _group setVariable ["ITW_CLASH_GTFO_RestRestartPending",nil];
        _group setVariable ["ITW_CLASH_GTFO_NativeRestLogged",nil];
        ["rest-restart-dispatched",[
            [_group] call ITW_CLASH_fnc_GroupId,
            _mode,
            _reason,
            _group getVariable ["ITW_CLASH_GTFO_EgressObjective",-1],
            _group getVariable ["ITW_CLASH_GTFO_Source",""]
        ]] call ITW_CLASH_GTFO_fnc_Log;
    };
    true
};

[] spawn {
    scriptName "ITW_CLASH_GTFO_ReconGuard";
    private _deadline = time + 180;
    waitUntil {
        sleep 0.25;
        (
            !isNil "ITW_CLASH_Recon_fnc_NativeGoRecon" &&
            {!isNil "ITW_CLASH_Recon_fnc_NativeGoDefRecon"} &&
            {!isNil "HAL_GoRecon"} &&
            {!isNil "HAL_GoDefRecon"}
        ) || {time > _deadline}
    };

    if (time > _deadline || {
        isNil "HAL_GoRecon" || {isNil "HAL_GoDefRecon"}
    }) exitWith {
        diag_log "CLASH BOOT | gtfo-recon-guard-deferred | recon surface unavailable";
    };

    sleep 0.25;
    ITW_CLASH_GTFO_fnc_ReconBase = HAL_GoRecon;
    ITW_CLASH_GTFO_fnc_DefReconBase = HAL_GoDefRecon;

    ITW_CLASH_GTFO_fnc_BlockRecon = {
        params ["_mode","_group","_hq"];
        if (!isNull _group) then {
            _group setVariable ["Busy" + str _group,false];
            _group setVariable ["ITW_CLASH_ReconPhase0Active",nil];
            _group setVariable ["ITW_CLASH_ReconPhase0Mode",nil];
        };

        if (!isNull _hq && {_mode isEqualTo "defensive"}) then {
            [_group,_hq] spawn {
                params ["_group","_hq"];
                sleep 0.25;
                if (!isNull _hq) then {
                    _hq setVariable [
                        "RydHQ_RecDefSpot",
                        (_hq getVariable ["RydHQ_RecDefSpot",[]]) - [_group]
                    ];
                };
            };
        };

        if (!isNil "ITW_CLASH_fnc_Log") then {
            ["recon-blocked-gtfo",[
                if (isNull _group) then {"<null>"} else {
                    [_group] call ITW_CLASH_fnc_GroupId
                },
                _mode,
                if (isNull _group) then {""} else {
                    _group getVariable ["ITW_CLASH_GTFO_State",""]
                }
            ]] call ITW_CLASH_fnc_Log;
        };
        false
    };

    HAL_GoRecon = {
        private _group = _this param [0,grpNull];
        private _hq = _this param [3,grpNull];
        if (!isNull _group && {
            _group getVariable ["ITW_CLASH_GTFO",false]
        }) exitWith {
            ["offensive",_group,_hq] call ITW_CLASH_GTFO_fnc_BlockRecon
        };
        _this call ITW_CLASH_GTFO_fnc_ReconBase
    };

    HAL_GoDefRecon = {
        private _group = _this param [0,grpNull];
        private _hq = _this param [3,grpNull];
        if (!isNull _group && {
            _group getVariable ["ITW_CLASH_GTFO",false]
        }) exitWith {
            ["defensive",_group,_hq] call ITW_CLASH_GTFO_fnc_BlockRecon
        };
        _this call ITW_CLASH_GTFO_fnc_DefReconBase
    };

    diag_log "CLASH BOOT | gtfo-recon-guard-ready | version=2 bridgeOnly=true";
};

[] spawn {
    scriptName "ITW_CLASH_GTFO_RecoveryHandoff";
    private _deadline = time + 180;
    waitUntil {
        sleep 0.25;
        !isNil "ITW_CLASH_EvacBoarding_fnc_Board" || {time > _deadline}
    };

    if (time > _deadline || {isNil "ITW_CLASH_EvacBoarding_fnc_Board"}) exitWith {
        diag_log "CLASH BOOT | gtfo-recovery-handoff-deferred | boarding surface unavailable";
    };

    ITW_CLASH_GTFO_fnc_BoardBase = ITW_CLASH_EvacBoarding_fnc_Board;
    ITW_CLASH_EvacBoarding_fnc_Board = {
        private _mode = _this param [0,"recovery"];
        private _group = _this param [3,grpNull];
        private _result = _this call ITW_CLASH_GTFO_fnc_BoardBase;

        if (
            _result isEqualType [] && {
                count _result > 0 && {
                    _result#0 && {
                        !isNull _group && {
                            _group getVariable ["ITW_CLASH_GTFO",false]
                        }
                    }
                }
            }
        ) then {
            [_group,_mode] call ITW_CLASH_GTFO_fnc_RecoveryOwned;
        };
        _result
    };

    diag_log "CLASH BOOT | gtfo-recovery-handoff-ready | version=2 ownership=postBoarding";
};

[] spawn {
    scriptName "ITW_CLASH_GTFO_RecoveryFailureHandback";
    private _deadline = time + 180;
    waitUntil {
        sleep 0.25;
        (
            !isNil "ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal" &&
            {!isNil "ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal"}
        ) || {time > _deadline}
    };

    if (time > _deadline || {
        isNil "ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal" || {
            isNil "ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal"
        }
    }) exitWith {
        diag_log "CLASH BOOT | gtfo-recovery-failure-handback-deferred | recovery resume surface unavailable";
    };

    ITW_CLASH_GTFO_fnc_CASEVACResumeBase = ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
    ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal = {
        private _group = _this param [1,grpNull];
        private _reason = _this param [2,"unknown"];
        ["air",_group,_reason] call ITW_CLASH_GTFO_fnc_RequestNativeRestRestart;
        _this call ITW_CLASH_GTFO_fnc_CASEVACResumeBase
    };

    ITW_CLASH_GTFO_fnc_GroundResumeBase = ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
    ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal = {
        private _group = _this param [1,grpNull];
        private _reason = _this param [2,"unknown"];
        ["ground",_group,_reason] call ITW_CLASH_GTFO_fnc_RequestNativeRestRestart;
        _this call ITW_CLASH_GTFO_fnc_GroundResumeBase
    };

    diag_log "CLASH BOOT | gtfo-recovery-failure-handback-ready | version=2 explicitGoRestRestart=true";
};

[] spawn {
    scriptName "ITW_CLASH_GTFO_ConstraintWatch";
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 2;
        if !(
            missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false] && {
                missionNamespace getVariable ["ITW_CLASH_HALReady",false] && {
                    !isNil "ITW_CLASH_GTFO_fnc_ApplyConstraints"
                }
            }
        ) then {continue};

        private _activeKeys = [];
        private _watchGroups = [];
        if (!isNil "ITW_CLASH_Withdrawals") then {
            {
                private _entry = ITW_CLASH_Withdrawals getOrDefault [_x,[]];
                if (_entry isNotEqualTo []) then {
                    private _candidate = _entry#0;
                    if (!isNull _candidate) then {
                        _watchGroups pushBackUnique _candidate;
                    };
                };
            } forEach +(keys ITW_CLASH_Withdrawals);
        };
        {
            private _group = _x;
            if !([_group] call ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal) then {continue};
            private _id = [_group] call ITW_CLASH_fnc_GroupId;
            _activeKeys pushBack _id;

            [_group,"constraint-watch"] call ITW_CLASH_GTFO_fnc_ClearStaleHALRoles;
            if (!isNil "ITW_CLASH_GTFO_fnc_SetPersistentConstraints") then {
                [_group,true] call ITW_CLASH_GTFO_fnc_SetPersistentConstraints;
            };

            // One-shot field proof that HAL's native GoRest owns the formation.
            if !(_group getVariable ["ITW_CLASH_GTFO_NativeRestLogged",false]) then {
                if (_group getVariable ["Resting" + str _group,false]) then {
                    private _waypoints = waypoints _group;
                    private _wpIndex = currentWaypoint _group;
                    if (_waypoints isNotEqualTo [] && {
                        _wpIndex >= 0 && {_wpIndex < count _waypoints}
                    }) then {
                        _group setVariable ["ITW_CLASH_GTFO_NativeRestLogged",true];
                        ["native-rest-active",[
                            _id,
                            waypointType [_group,_wpIndex],
                            waypointPosition [_group,_wpIndex],
                            attackEnabled _group,
                            combatMode _group,
                            behaviour leader _group,
                            _group getVariable ["ITW_CLASH_GTFO_Destination",[]]
                        ]] call ITW_CLASH_GTFO_fnc_Log;
                    };
                };
            };

            if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "" ||
                {(_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo ""}) then {
                ITW_CLASH_GTFORuntimeProgress deleteAt _id;
                continue;
            };

            private _destination = _group getVariable ["ITW_CLASH_GTFO_Destination",[]];
            private _leader = leader _group;
            if (_destination isEqualTo [] || {isNull _leader}) then {
                ITW_CLASH_GTFORuntimeProgress deleteAt _id;
                continue;
            };

            private _distance = _leader distance2D _destination;
            private _sample = ITW_CLASH_GTFORuntimeProgress getOrDefault [_id,[]];
            if (_sample isEqualTo []) then {
                // Explicitly seed the hashmap. getOrDefault's fallback alone is
                // not persistent and was the reason the old observer could fail
                // to accumulate a stall duration from its first sample.
                ITW_CLASH_GTFORuntimeProgress set [_id,[time,_distance]];
                continue;
            };
            _sample params ["_sampleAt","_sampleDistance"];

            private _busy = _group getVariable ["Busy" + str _group,false];
            private _resting = _group getVariable ["Resting" + str _group,false];
            if (!_busy || {_resting} || {
                abs (_sampleDistance - _distance) >= ITW_CLASH_GTFO_RestRestartProgress
            }) then {
                ITW_CLASH_GTFORuntimeProgress set [_id,[time,_distance]];
                continue;
            };

            private _stalledFor = time - _sampleAt;
            if (_stalledFor < ITW_CLASH_GTFO_RestRestartGrace) then {continue};
            ITW_CLASH_GTFORuntimeProgress set [_id,[time,_distance]];
            ["stall-restart",_group,format ["busy-no-rest-%1s",round _stalledFor]] call
                ITW_CLASH_GTFO_fnc_RequestNativeRestRestart;
        } forEach _watchGroups;

        {
            if !(_x in _activeKeys) then {
                ITW_CLASH_GTFORuntimeProgress deleteAt _x;
            };
        } forEach +(keys ITW_CLASH_GTFORuntimeProgress);

        call ITW_CLASH_GTFO_fnc_ApplyConstraints;
    };
};

diag_log format [
    "CLASH BOOT | gtfo-runtime-started | version=%1 reconGuard=true recoveryPostBoard=true explicitGoRestRestart=true commanderAware=true bluforTracked=true staleHALRoles=true busyStallGrace=%2 busyProgress=%3 constraintPoll=2 arrivalRadius=%4 nativeRestTelemetry=true",
    ITW_CLASH_GTFORuntimeVersion,
    ITW_CLASH_GTFO_RestRestartGrace,
    ITW_CLASH_GTFO_RestRestartProgress,
    ITW_CLASH_GTFO_ArrivalRadius
];
