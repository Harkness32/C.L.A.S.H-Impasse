#include "defines.hpp"

// C.L.A.S.H. V6 preprocessor bisect chunk 8/8.
// Original ITW_CLASH.sqf lines 2311-2639. Diagnostic only; never executed.

ITW_CLASH_fnc_CreateCommander = {
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {false};
    if (isNil "NR6_fnc_HALcore") exitWith {
        ["pilot-failed",["NR6_fnc_HALcore missing; load untouched NR6 Pack 4.11"]] call ITW_CLASH_fnc_Log;
        false
    };
    if (!isNil "RydxHQ_AllHQ" && {count RydxHQ_AllHQ > 0}) exitWith {
        ["pilot-failed",["existing HAL commander detected"]] call ITW_CLASH_fnc_Log;
        false
    };
    if (!isNil "leaderHQ" && {!isNull leaderHQ}) exitWith {
        ["pilot-failed",["existing LeaderHQ detected"]] call ITW_CLASH_fnc_Log;
        false
    };

    private _class = switch (ITW_EnemySide) do {
        case east: {"O_officer_F"};
        case independent: {"I_officer_F"};
        default {""};
    };
    if (_class isEqualTo "") exitWith {
        ["pilot-failed",["unsupported enemy side",ITW_EnemySide]] call ITW_CLASH_fnc_Log;
        false
    };

    private _position = [0,0,0];
    private _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    if (_heldObjectives isNotEqualTo []) then {
        _position = [
            _heldObjectives#0#0,
            _heldObjectives#0#1
        ] call ITW_CLASH_fnc_GetCommanderPosition;
    } else {
        if (ITW_CLASH_HALObjectives isNotEqualTo []) then {
            _position = getPosATL (ITW_CLASH_HALObjectives#0);
        };
    };

    ITW_CLASH_HALHQ = createGroup ITW_EnemySide;
    ITW_CLASH_HALLeader = ITW_CLASH_HALHQ createUnit [_class,_position,[],0,"NONE"];
    if (isNull ITW_CLASH_HALLeader) exitWith {
        ["pilot-failed",["unable to create HAL commander"]] call ITW_CLASH_fnc_Log;
        false
    };

    ITW_CLASH_HALHQ setGroupIdGlobal ["CLASH HAL OPFOR"];
    ITW_CLASH_HALHQ setVariable ["zbe_cacheDisabled",true];
    ITW_CLASH_HALHQ setVariable ["ITW_CLASH_Commander",true];
    ITW_CLASH_HALLeader setVariable ["itw_dmgBlocked",true];
    ITW_CLASH_HALLeader hideObjectGlobal true;
    ITW_CLASH_HALLeader enableSimulationGlobal false;
    ITW_CLASH_HALLeader allowDamage false;

    leaderHQ = ITW_CLASH_HALLeader;
    publicVariable "leaderHQ";
    call ITW_CLASH_fnc_ApplyObjectiveDoctrine;
    [_heldObjectives] call ITW_CLASH_fnc_SyncCommanderObjective;
    true
};

ITW_CLASH_fnc_CommanderHealthy = {
    if (!isServer || {!ITW_CLASH_LiveEnabled} || {!ITW_CLASH_HALReady}) exitWith {false};

    !isNull ITW_CLASH_HALHQ && {
        !isNull ITW_CLASH_HALLeader && {
            alive ITW_CLASH_HALLeader && {
                group ITW_CLASH_HALLeader isEqualTo ITW_CLASH_HALHQ && {
                    leader ITW_CLASH_HALHQ isEqualTo ITW_CLASH_HALLeader && {
                        ITW_CLASH_HALHQ getVariable ["ITW_CLASH_Commander",false] && {
                            ITW_CLASH_HALHQ in (missionNamespace getVariable ["RydxHQ_AllHQ",[]])
                        }
                    }
                }
            }
        }
    }
};

ITW_CLASH_fnc_FailPilot = {
    params [["_reason","commander-invalid"],["_details",[]]];
    if (!isServer || {ITW_CLASH_PilotFailed}) exitWith {false};

    ITW_CLASH_PilotFailed = true;
    ITW_CLASH_HALReady = false;
    ITW_CLASH_Transitioning = true;
    ITW_CLASH_RegistrationFrozenUntil = 1e10;
    ["pilot-failing",[_reason,_details,count ITW_CLASH_ManagedGroups]] call ITW_CLASH_fnc_Log;

    private _released = [format ["pilot-failed:%1",_reason]] call ITW_CLASH_fnc_ReleaseAll;
    [format ["pilot-failed:%1",_reason]] call ITW_CLASH_fnc_ResetAnchors;
    private _withdrawalsCancelled = [
        format ["pilot-failed:%1",_reason]
    ] call ITW_CLASH_fnc_CancelWithdrawals;
    ITW_CLASH_ManagedGroups = [];
    RydHQ_Included = [];
    RydHQ_NoDef = [];
    RydHQ_NoAttack = [];
    RydHQ_NoRecon = [];
    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_Included",[]];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoDef",[]];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoAttack",[]];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoRecon",[]];
    };

    ITW_CLASH_LiveEnabled = false;
    ["pilot-failed",[
        _reason,
        _details,
        _released,
        _withdrawalsCancelled
    ]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_StartCommanderWatchdog = {
    if (!isServer || {!ITW_CLASH_LiveEnabled} || {!ITW_CLASH_HALReady}) exitWith {false};
    if (ITW_CLASH_CommanderWatchdogStarted) exitWith {true};

    ITW_CLASH_CommanderWatchdogStarted = true;
    [] spawn {
        scriptName "ITW_CLASH_CommanderWatchdog";
        while {ITW_CLASH_LiveEnabled && {
            !ITW_CLASH_PilotFailed && {
                !(missionNamespace getVariable ["ITW_GameOver",false])
            }
        }} do {
            sleep 1;
            if !(call ITW_CLASH_fnc_CommanderHealthy) exitWith {
                private _details = [
                    isNull ITW_CLASH_HALHQ,
                    isNull ITW_CLASH_HALLeader,
                    if (isNull ITW_CLASH_HALLeader) then {false} else {alive ITW_CLASH_HALLeader},
                    if (isNull ITW_CLASH_HALLeader) then {"<null>"} else {str (group ITW_CLASH_HALLeader)},
                    if (isNull ITW_CLASH_HALHQ) then {"<null>"} else {str (leader ITW_CLASH_HALHQ)},
                    ITW_CLASH_HALHQ in (missionNamespace getVariable ["RydxHQ_AllHQ",[]])
                ];
                ["commander-invalid",_details] call ITW_CLASH_fnc_FailPilot;
            };
            while {missionNamespace getVariable ["LV_PAUSE",false]} do {sleep 5};
        };
    };
    true
};

ITW_CLASH_fnc_StartLivePilot = {
    if (!isServer) exitWith {false};
    if (ITW_CLASH_LiveStarted) exitWith {true};

    ITW_CLASH_LiveStarted = true;
    ITW_CLASH_LiveEnabled = true;

    [] spawn {
        scriptName "ITW_CLASH_LivePilot";
        waitUntil {
            sleep 1;
            missionNamespace getVariable ["ITW_GameReady",false]
        };

        if !(call ITW_CLASH_fnc_ConfigureHAL) exitWith {
            ITW_CLASH_LiveEnabled = false;
        };

        if !(call ITW_CLASH_fnc_MirrorObjectives) exitWith {
            ITW_CLASH_LiveEnabled = false;
            ["pilot-failed",["no current objective mirrors"]] call ITW_CLASH_fnc_Log;
        };

        if !(call ITW_CLASH_fnc_CreateCommander) exitWith {
            ITW_CLASH_LiveEnabled = false;
        };
        call ITW_CLASH_fnc_MirrorObjectives;

        {
            private _result = [_x] call ITW_CLASH_fnc_ClassifyGroup;
            if (_result#0) then {
                [_x,"pilot-seed",true] call ITW_CLASH_fnc_RegisterGroup;
            };
        } forEach allGroups;

        [] spawn NR6_fnc_HALcore;

        private _timeout = diag_tickTime + 120;
        waitUntil {
            sleep 1;
            diag_tickTime >= _timeout || {
                !isNull ITW_CLASH_HALHQ && {
                    !isNil "RydxHQ_AllHQ" && {
                        ITW_CLASH_HALHQ in RydxHQ_AllHQ && {
                            !(ITW_CLASH_HALHQ getVariable ["RydHQ_Init",true])
                        }
                    }
                }
            }
        };

        ITW_CLASH_HALReady = diag_tickTime < _timeout && {
            !isNull ITW_CLASH_HALHQ && {
                ITW_CLASH_HALHQ in (missionNamespace getVariable ["RydxHQ_AllHQ",[]])
            }
        };

        if (!ITW_CLASH_HALReady) exitWith {
            ["pilot-init-timeout"] call ITW_CLASH_fnc_ReleaseAll;
            ITW_CLASH_LiveEnabled = false;
            ["pilot-failed",["HAL initialization timeout"]] call ITW_CLASH_fnc_Log;
        };

        call ITW_CLASH_fnc_MirrorObjectives;
        call ITW_CLASH_fnc_SyncHALIncluded;
        ITW_CLASH_AnchorAuditReadyAt = time + 45;
        if !(call ITW_CLASH_fnc_StartCommanderWatchdog) exitWith {
            ["watchdog-start-failed",[]] call ITW_CLASH_fnc_FailPilot;
        };
        ["pilot-ready",[
            ["version",ITW_CLASH_Version],
            "opfor-dismounted-live",
            count ITW_CLASH_ManagedGroups,
            ITW_CLASH_MaxManagedGroups,
            ITW_CLASH_MaxManagedPerObjective,
            ITW_CLASH_MinAnchorSoldiers,
            ITW_CLASH_ReserveRatio,
            ITW_CLASH_ExhaustionConfirmGrace,
            ITW_CLASH_WithdrawalArrivalRadius
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_StartObserver = {
    if (!isServer) exitWith {false};
    if (ITW_CLASH_ObserverStarted) exitWith {true};

    ITW_CLASH_ObserverEnabled = true;
    ITW_CLASH_ObserverStarted = true;
    ["observer-start",["mode",ITW_CLASH_Mode]] call ITW_CLASH_fnc_Log;

    [] spawn {
        scriptName "ITW_CLASH_Observer";
        waitUntil {
            sleep 1;
            missionNamespace getVariable ["ITW_GameReady",false]
        };

        while {ITW_CLASH_ObserverEnabled && {
            !(missionNamespace getVariable ["ITW_GameOver",false])
        }} do {
            call ITW_CLASH_fnc_Reconcile;
            sleep 10;
            while {missionNamespace getVariable ["LV_PAUSE",false]} do {sleep 5};
        };
    };
    true
};

["ITW_CLASH_fnc_Log"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GroupId"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_IsCommanderGroup"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_IsConscious"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_CountConscious"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_IsHALExhausted"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GetArchetype"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_AnchorKey"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GetObjectiveRadius"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GetObjectiveCenter"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GetObjectiveFlag"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GetActiveObjectives"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GetHeldObjectives"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GetCommanderPosition"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_SyncCommanderObjective"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ClassifyGroup"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ClearGroupWaypoints"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ApplyObjectiveDoctrine"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_SyncHALIncluded"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_MirrorObjectives"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ClearAnchorSlot"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ResetAnchors"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_SelectAnchorGroup"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_OrderAnchor"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_RequestAnchorRefill"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_NextAnchorRefill"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_AcknowledgeAnchorRefill"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_GetEgressPoint"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_OrderWithdrawal"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_StartWithdrawal"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_AcknowledgeReconstitution"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_AuditWithdrawals"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_CancelWithdrawals"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_AuditAnchors"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_AuditAllocations"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_RegisterGroup"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_BeginRelease"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ReleaseAcknowledged"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_FinishRelease"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ReleaseGroup"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ReleaseAll"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ObserveGroup"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ObserveWriter"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_WouldReleaseAll"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ObserveLifecycle"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_Reconcile"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_DiagnosticSnapshot"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ConfigureHAL"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_CreateCommander"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_CommanderHealthy"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_FailPilot"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_StartCommanderWatchdog"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_StartLivePilot"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_StartObserver"] call SKL_fnc_CompileFinal;

if (isServer) then {
    [] spawn {
        waitUntil {sleep 0.1; !isNil "ITW_Params_complete"};
        ITW_CLASH_Mode = missionNamespace getVariable ["ITW_ParamCLASHObserver",0];

        switch (ITW_CLASH_Mode) do {
            case 1: {
                call ITW_CLASH_fnc_StartObserver;
            };
            case 2: {
                call ITW_CLASH_fnc_StartObserver;
                call ITW_CLASH_fnc_StartLivePilot;
            };
            default {
                diag_log "CLASH OBS | disabled | lobby parameter is Off";
            };
        };
    };
};
