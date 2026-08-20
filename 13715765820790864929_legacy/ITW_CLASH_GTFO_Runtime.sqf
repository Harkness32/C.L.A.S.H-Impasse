#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_GTFORuntimeStarted",false]) exitWith {};
ITW_CLASH_GTFORuntimeStarted = true;
ITW_CLASH_GTFORuntimeVersion = 1;

/*
    Late-bound GTFO adapters.

    The synchronous GTFO controller bridge loads before Recon Phase 0 and the
    shared evacuation boarding helper exist. These adapters wait for those
    modules and then enforce only authority boundaries:
      - GTFO groups cannot be assigned recon.
      - Recovery becomes exclusive only after physical boarding completes.
      - Ongoing GTFO constraints are reasserted without writing tactical waypoints.
*/

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

    // Let Recon Phase 0 finish assigning its own wrappers in the same scheduler
    // turn, then wrap that public surface rather than the vendored native code.
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

    diag_log "CLASH BOOT | gtfo-recon-guard-ready | version=1 bridgeOnly=true";
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

    diag_log "CLASH BOOT | gtfo-recovery-handoff-ready | version=1 ownership=postBoarding";
};

[] spawn {
    scriptName "ITW_CLASH_GTFO_ConstraintWatch";
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 2;
        if (
            missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false] && {
                missionNamespace getVariable ["ITW_CLASH_HALReady",false] && {
                    !isNil "ITW_CLASH_GTFO_fnc_ApplyConstraints"
                }
            }
        ) then {
            call ITW_CLASH_GTFO_fnc_ApplyConstraints;
        };
    };
};

diag_log format [
    "CLASH BOOT | gtfo-runtime-started | version=%1 reconGuard=true recoveryPostBoard=true constraintPoll=2",
    ITW_CLASH_GTFORuntimeVersion
];
