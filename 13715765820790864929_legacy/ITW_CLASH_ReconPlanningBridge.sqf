#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_ReconPlanningBridgeStarted",false]) exitWith {};
ITW_CLASH_ReconPlanningBridgeStarted = true;
ITW_CLASH_ReconPlanningBridgeVersion = 1;
ITW_CLASH_ReconPlanningRecoveryTimeout = 5;

/*
    HAL recon planning bridge

    HAL's native planner paradoxically subtracts RydHQ_SpecForG from both
    offensive and defensive reconnaissance candidate pools. C.L.A.S.H. does not
    assign a recon mission here. It opens a synchronous planning-only view in
    which recognized SOF can be considered by HAL's untouched HQOrders logic,
    then restores HAL's original semantic lists before returning.

    Offensive planning:
      - eligible SOF temporarily leaves SpecForG
      - eligible SOF temporarily enters ReconG
      - NoRecon is opened for those groups
      - ReconG already keeps them out of native ordinary AttackAv
      - this window opens only while RydHQ_ReconDone is false

    Defensive planning:
      - eligible SOF temporarily leaves SpecForG and enters ReconG
      - eligible SOF is temporarily removed from Friends so it cannot enter
        ordinary _LMCU defense while remaining explicitly available in _recDef
      - NoDef/NoRecon are opened only inside the planning call

    After the native planner returns every modified HAL list is restored exactly.
    A watchdog also owns a copy of the pre-window snapshot. If the native planner
    script faults before normal restoration, the watchdog closes the temporary
    semantic window instead of leaving HAL permanently reclassified.

    The bridge arms only after Recon Phase 0 has published its saved native
    GoRecon/GoDefRecon handles. That guarantees the SOF-only execution gate is
    already installed before C.L.A.S.H. exposes additional recon candidates.

    SOF therefore remains SpecFor for normal HAL direct-action behavior.
*/

ITW_CLASH_ReconPlanning_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["recon-bridge-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_ReconPlanning_fnc_EligibleSOF = {
    params ["_hq"];
    if (isNull _hq || {isNil "ITW_CLASH_SOF_fnc_Classify"}) exitWith {[]};

    private _exhausted = _hq getVariable ["RydHQ_Exhausted",[]];
    ITW_CLASH_ManagedGroups select {
        private _group = _x;
        !isNull _group && {
            {alive _x} count units _group > 0 && {
                _group getVariable ["ITW_CLASH_Managed",false] && {
                    !(_group getVariable ["ITW_CLASH_Releasing",false]) && {
                        !(_group getVariable ["ITW_CLASH_GTFO",false]) && {
                            !(_group getVariable ["ITW_CLASH_Withdrawing",false]) && {
                                (_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isEqualTo "" && {
                                    (_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isEqualTo "" && {
                                        !(_group in _exhausted) && {
                                            !(_group getVariable ["Busy" + str _group,false]) && {
                                                ([_group] call ITW_CLASH_SOF_fnc_Classify)#0
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
};

ITW_CLASH_ReconPlanning_fnc_RestoreSnapshot = {
    params ["_hq",["_source","normal"]];
    if (isNull _hq) exitWith {false};

    private _snapshot = _hq getVariable ["ITW_CLASH_ReconPlanningSnapshot",[]];
    if (_snapshot isEqualTo [] || {count _snapshot < 7}) exitWith {
        _hq setVariable ["ITW_CLASH_ReconPlanningDepth",0];
        false
    };

    _snapshot params [
        "_openedAt",
        "_mode",
        "_specFor0",
        "_recon0",
        "_noRecon0",
        "_friends0",
        "_noDef0"
    ];

    _hq setVariable ["RydHQ_SpecForG",+_specFor0];
    _hq setVariable ["RydHQ_ReconG",+_recon0];
    _hq setVariable ["RydHQ_NoRecon",+_noRecon0];
    _hq setVariable ["RydHQ_Friends",+_friends0];
    _hq setVariable ["RydHQ_NoDef",+_noDef0];
    _hq setVariable ["ITW_CLASH_ReconPlanningDepth",0];
    _hq setVariable ["ITW_CLASH_ReconPlanningSnapshot",nil];

    if !(_source isEqualTo "normal") then {
        ["window-recovered",[
            _source,
            _mode,
            round ((diag_tickTime - _openedAt) * 100) / 100,
            count _specFor0,
            count _recon0,
            count _friends0
        ]] call ITW_CLASH_ReconPlanning_fnc_Log;
    };
    true
};

ITW_CLASH_ReconPlanning_fnc_CallNative = {
    params ["_mode","_args","_native"];
    private _hq = _args param [0,grpNull];
    if (isNull _hq) exitWith {_args call _native};

    // Guard accidental nested planning calls. The outer window already exposes
    // the intended temporary HAL view.
    private _depth = _hq getVariable ["ITW_CLASH_ReconPlanningDepth",0];
    if (_depth > 0) exitWith {_args call _native};

    private _eligible = [_hq] call ITW_CLASH_ReconPlanning_fnc_EligibleSOF;
    if (_eligible isEqualTo []) exitWith {_args call _native};

    private _reconDemand = if (_mode isEqualTo "offensive") then {
        !(_hq getVariable ["RydHQ_ReconDone",false])
    } else {
        true
    };
    if (!_reconDemand) exitWith {_args call _native};

    private _specFor0 = +(_hq getVariable ["RydHQ_SpecForG",[]]);
    private _recon0 = +(_hq getVariable ["RydHQ_ReconG",[]]);
    private _noRecon0 = +(_hq getVariable ["RydHQ_NoRecon",[]]);
    private _friends0 = +(_hq getVariable ["RydHQ_Friends",[]]);
    private _noDef0 = +(_hq getVariable ["RydHQ_NoDef",[]]);

    private _specForWindow = _specFor0 - _eligible;
    private _reconWindow = +_recon0;
    {_reconWindow pushBackUnique _x} forEach _eligible;
    private _noReconWindow = _noRecon0 - _eligible;

    // Store a non-local dead-man copy before mutating HAL. Normal completion
    // clears it; the watchdog can recover it if execution faults in native code.
    _hq setVariable ["ITW_CLASH_ReconPlanningSnapshot",[
        diag_tickTime,
        _mode,
        +_specFor0,
        +_recon0,
        +_noRecon0,
        +_friends0,
        +_noDef0
    ]];
    _hq setVariable ["ITW_CLASH_ReconPlanningDepth",1];
    _hq setVariable ["RydHQ_SpecForG",_specForWindow];
    _hq setVariable ["RydHQ_ReconG",_reconWindow];
    _hq setVariable ["RydHQ_NoRecon",_noReconWindow];

    if (_mode isEqualTo "defensive") then {
        // _recDef comes from ReconG and does not require Friends membership.
        // Removing SOF from Friends keeps it out of ordinary _LMCU defense while
        // opening NoDef allows the same group to remain in native _recDef.
        _hq setVariable ["RydHQ_Friends",_friends0 - _eligible];
        _hq setVariable ["RydHQ_NoDef",_noDef0 - _eligible];
    };

    ["window-open",[
        _mode,
        _eligible apply {[
            [_x] call ITW_CLASH_fnc_GroupId,
            _x getVariable ["ITW_CLASH_ReconSOFFamily","sof"]
        ]},
        count _specFor0,
        count _recon0,
        _hq getVariable ["RydHQ_ReconStage",-1],
        _hq getVariable ["RydHQ_ReconStage2",-1],
        _hq getVariable ["RydHQ_ReconDone",false]
    ]] call ITW_CLASH_ReconPlanning_fnc_Log;

    private _result = _args call _native;

    // Restore HAL semantic identity immediately. Nothing about this bridge is a
    // persistent reclassification of SOF.
    [_hq,"normal"] call ITW_CLASH_ReconPlanning_fnc_RestoreSnapshot;

    ["window-close",[
        _mode,
        _eligible apply {[
            [_x] call ITW_CLASH_fnc_GroupId,
            _x getVariable ["Busy" + str _x,false],
            _x getVariable ["ITW_CLASH_ReconPhase0Active",false],
            _x getVariable ["ITW_CLASH_ReconPhase0Mode",""]
        ]},
        (_hq getVariable ["RydHQ_ReconAv",[]]) apply {[_x] call ITW_CLASH_fnc_GroupId},
        _hq getVariable ["RydHQ_ReconStage",-1],
        _hq getVariable ["RydHQ_ReconStage2",-1],
        _hq getVariable ["RydHQ_ReconDone",false]
    ]] call ITW_CLASH_ReconPlanning_fnc_Log;

    // The native recon function is usually spawned. Give its wrapper one
    // scheduler turn to report whether HAL actually selected one of the exposed
    // SOF candidates; this is telemetry only.
    [_mode,_eligible] spawn {
        params ["_mode","_eligible"];
        sleep 0.5;
        private _assigned = _eligible select {
            !isNull _x && {_x getVariable ["ITW_CLASH_ReconPhase0Active",false]}
        };
        ["result",[
            _mode,
            _assigned apply {[
                [_x] call ITW_CLASH_fnc_GroupId,
                _x getVariable ["ITW_CLASH_ReconPhase0Mode",""]
            ]},
            count _eligible
        ]] call ITW_CLASH_ReconPlanning_fnc_Log;
    };

    _result
};

[] spawn {
    scriptName "ITW_CLASH_ReconPlanningBridge";
    private _deadline = time + 180;
    waitUntil {
        sleep 0.25;
        (
            missionNamespace getVariable ["ITW_CLASH_HALReady",false] &&
            {!isNil "ITW_CLASH_SOF_fnc_Classify"} &&
            {!isNil "HAL_HQOrders"} &&
            {!isNil "HAL_HQOrdersDef"} &&
            {!isNil "ITW_CLASH_Recon_fnc_NativeGoRecon"} &&
            {!isNil "ITW_CLASH_Recon_fnc_NativeGoDefRecon"}
        ) || {time > _deadline}
    };

    if (time > _deadline || {
        isNil "HAL_HQOrders" || {
            isNil "HAL_HQOrdersDef" || {
                isNil "ITW_CLASH_Recon_fnc_NativeGoRecon" || {
                    isNil "ITW_CLASH_Recon_fnc_NativeGoDefRecon"
                }
            }
        }
    }) exitWith {
        ITW_CLASH_ReconPlanningBridgeStarted = false;
        diag_log "CLASH BOOT | recon-planning-bridge-deferred | HAL planner or Recon Phase 0 gate unavailable";
    };

    // Recon Phase 0 sets its saved native handles immediately before replacing
    // HAL_GoRecon/HAL_GoDefRecon. Yield once so those public gate assignments and
    // the phase boot record finish before a planning window can ever open.
    sleep 0.25;

    ITW_CLASH_ReconPlanning_fnc_NativeHQOrders = HAL_HQOrders;
    ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef = HAL_HQOrdersDef;

    HAL_HQOrders = {
        [
            "offensive",
            _this,
            ITW_CLASH_ReconPlanning_fnc_NativeHQOrders
        ] call ITW_CLASH_ReconPlanning_fnc_CallNative
    };

    HAL_HQOrdersDef = {
        [
            "defensive",
            _this,
            ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef
        ] call ITW_CLASH_ReconPlanning_fnc_CallNative
    };

    // Dead-man restoration for a script error/abnormal escape inside a native
    // planner call. In the normal synchronous path Depth returns to zero before
    // this watcher gets another scheduler turn.
    [] spawn {
        scriptName "ITW_CLASH_ReconPlanningRecoveryWatch";
        while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
            sleep 1;
            private _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
            if (isNull _hq) then {continue};
            if ((_hq getVariable ["ITW_CLASH_ReconPlanningDepth",0]) <= 0) then {continue};

            private _snapshot = _hq getVariable ["ITW_CLASH_ReconPlanningSnapshot",[]];
            if (_snapshot isEqualTo [] || {count _snapshot < 1}) then {
                _hq setVariable ["ITW_CLASH_ReconPlanningDepth",0];
                continue;
            };
            private _openedAt = _snapshot#0;
            if (diag_tickTime - _openedAt >= ITW_CLASH_ReconPlanningRecoveryTimeout) then {
                [_hq,"watchdog-timeout"] call ITW_CLASH_ReconPlanning_fnc_RestoreSnapshot;
            };
        };
    };

    diag_log format [
        "CLASH BOOT | recon-planning-bridge-ready | version=%1 halChooses=true specForPersistent=true planningWindow=true phase0Gate=true anchorsSeparate=true recoveryWatch=%2",
        ITW_CLASH_ReconPlanningBridgeVersion,
        ITW_CLASH_ReconPlanningRecoveryTimeout
    ];
};
