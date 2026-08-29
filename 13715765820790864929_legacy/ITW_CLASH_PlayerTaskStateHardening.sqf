#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateHardeningStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskStateHardeningStarted = true;
ITW_CLASH_PlayerTaskStateHardeningReady = false;
ITW_CLASH_PlayerTaskStateLeaderGateReady = false;
ITW_CLASH_PlayerTaskStateCancelReady = false;
ITW_CLASH_PlayerTaskStateArtilleryGuardReady = false;
ITW_CLASH_PlayerTaskStateHardeningVersion = 3;

ITW_CLASH_PlayerTaskState_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_Log") then {
        ["state-" + _event,_payload] call ITW_CLASH_PlayerTasks_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER TASK STATE | %1 | %2",_event,_payload];
    };
};

// Leader authority is independent of native HAL cancellation. Install this gate
// as soon as the generic remote surface exists so observer mode, HAL load
// failure, or an Action1ct binder timeout can never fall back to the permissive
// v1 CancelRemote path.
ITW_CLASH_PlayerTaskState_fnc_InstallLeaderCancelGate = {
    if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateLeaderGateReady",false]) exitWith {true};
    if (
        isNil "ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid"
        || {isNil "ITW_CLASH_PlayerTasks_fnc_SendEmploymentState"}
        || {isNil "ITW_CLASH_PlayerTasks_fnc_CancelGroupJob"}
    ) exitWith {false};

    ITW_CLASH_PlayerTasks_fnc_CancelRemote = {
        params ["_player"];
        if !([_player,true] call
            ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid
        ) exitWith {
            if ([_player,false] call
                ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid
            ) then {
                [_player,false,"Only the group leader can cancel HAL employment."] call
                    ITW_CLASH_PlayerTasks_fnc_SendEmploymentState;
            };
            false
        };

        private _success = [_player] call
            ITW_CLASH_PlayerTasks_fnc_CancelGroupJob;
        [_player,_success,if (_success) then {
            "HAL job cancellation requested."
        } else {
            "No active HAL job to cancel."
        }] call ITW_CLASH_PlayerTasks_fnc_SendEmploymentState;
        _success
    };

    ITW_CLASH_PlayerTaskStateLeaderGateReady = true;
    ["leader-cancel-gate-ready",[
        "native-action-independent",true
    ]] call ITW_CLASH_PlayerTaskState_fnc_Log;
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskStateLeaderGate";
    private _deadline = diag_tickTime + 120;
    waitUntil {
        sleep 0.05;
        diag_tickTime >= _deadline || {
            !isNil "ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid"
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_SendEmploymentState"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_CancelGroupJob"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        ["leader-cancel-gate-bind-timeout",[]] call ITW_CLASH_PlayerTaskState_fnc_Log;
    };
    call ITW_CLASH_PlayerTaskState_fnc_InstallLeaderCancelGate;
};

// Phase 1: install admission as soon as PlayerTaskSupport has defined its
// primitives. This intentionally does not wait for HAL's Action1ct binder, so
// COMBAT exclusions are present before HAL gets its first useful planning pass.
[] spawn {
    scriptName "ITW_CLASH_PlayerTaskStateAdmission";
    private _deadline = diag_tickTime + 120;
    waitUntil {
        sleep 0.05;
        diag_tickTime >= _deadline || {
            !isNil "ITW_CLASH_PlayerTasks_fnc_GroupFromSubject"
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_GetSubscriptions"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_IsSubscribed"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_HasArtilleryCapability"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle"}
        }
    };

    if (diag_tickTime >= _deadline) exitWith {
        ["admission-bind-timeout",[]] call ITW_CLASH_PlayerTaskState_fnc_Log;
    };
    if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateHardeningReady",false]) exitWith {};

    ITW_CLASH_PlayerTasks_fnc_HasActiveJob = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {false};

        (_group getVariable ["Busy" + str _group,false])
        || {(_group getVariable ["ITW_CLASH_PlayerTaskRequestActiveJobId",""]) isNotEqualTo ""}
        || {(_group getVariable ["ITW_CLASH_PlayerStrikeJobId",""]) isNotEqualTo ""}
        || {(_group getVariable ["ITW_CLASH_PlayerReconJobId",""]) isNotEqualTo ""}
        || {(_group getVariable ["ITW_CLASH_PlayerAmmoJobId",""]) isNotEqualTo ""}
        || {(_group getVariable ["ITW_CLASH_PlayerArtilleryJobId",""]) isNotEqualTo ""}
        || {(_group getVariable ["ITW_CLASH_PlayerNativeJobId",""]) isNotEqualTo ""}
        || {_group getVariable ["RydHQ_BatteryBusy",false]}
    };

    ITW_CLASH_PlayerTasks_fnc_CanAcceptJob = {
        params ["_subject","_jobType",["_ignoreOccupied",false]];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group || {!(_jobType isEqualType "")}) exitWith {false};
        _jobType = toUpperANSI _jobType;
        if !(_jobType in ITW_CLASH_PlayerJobTypes) exitWith {false};
        if (isNil "ITW_PlayerSide" || {side _group != ITW_PlayerSide}) exitWith {false};
        if ((units _group findIf {alive _x && {isPlayer _x}}) < 0) exitWith {false};
        if !([_group,_jobType] call ITW_CLASH_PlayerTasks_fnc_IsSubscribed) exitWith {false};
        if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {false};
        if (!_ignoreOccupied && {[_group] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob}) exitWith {false};

        switch (_jobType) do {
            case "COMBAT": {true};
            case "TRANSPORT": {
                private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
                [_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity
            };
            case "MEDEVAC": {
                private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
                [_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity
            };
            case "LOGISTICS": {
                !isNull ([_group] call ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle)
            };
            case "ARTILLERY": {
                private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
                [_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasArtilleryCapability
            };
            default {false};
        }
    };

    // Capability is channel-specific. Occupancy is applied separately by the
    // employment-state synchronizer so willingness/capability survive a job.
    ITW_CLASH_PlayerTasks_fnc_HasExecutableSubscription = {
        params ["_group"];
        if (isNull _group) exitWith {false};
        private _subscriptions = [_group] call
            ITW_CLASH_PlayerTasks_fnc_GetSubscriptions;
        (_subscriptions findIf {
            [_group,_x,true] call ITW_CLASH_PlayerTasks_fnc_CanAcceptJob
        }) >= 0
    };

    ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group || {isNil "ITW_CLASH_fnc_GetCommanderForGroup"}) exitWith {false};
        private _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
        if (isNull _hq) exitWith {false};

        private _combat = [_group,"COMBAT"] call
            ITW_CLASH_PlayerTasks_fnc_IsSubscribed;

        private _noRecon = +(_hq getVariable ["RydHQ_NoRecon",[]]);
        private _cargoOnly = +(_hq getVariable ["RydHQ_CargoOnly",[]]);
        private _ownedNoRecon = _group getVariable [
            "ITW_CLASH_PlayerCombatGateOwnsNoRecon",false
        ];
        private _ownedCargoOnly = _group getVariable [
            "ITW_CLASH_PlayerCombatGateOwnsCargoOnly",false
        ];

        if (_combat) then {
            if (_ownedNoRecon) then {
                _noRecon = _noRecon - [_group];
                _group setVariable ["ITW_CLASH_PlayerCombatGateOwnsNoRecon",nil];
            };
            if (_ownedCargoOnly) then {
                _cargoOnly = _cargoOnly - [_group];
                _group setVariable ["ITW_CLASH_PlayerCombatGateOwnsCargoOnly",nil];
            };
        } else {
            if !(_group in _noRecon) then {
                _noRecon pushBack _group;
                _group setVariable ["ITW_CLASH_PlayerCombatGateOwnsNoRecon",true];
            };
            if !(_group in _cargoOnly) then {
                _cargoOnly pushBack _group;
                _group setVariable ["ITW_CLASH_PlayerCombatGateOwnsCargoOnly",true];
            };
        };

        _hq setVariable ["RydHQ_NoRecon",_noRecon];
        _hq setVariable ["RydHQ_CargoOnly",_cargoOnly];
        true
    };

    // Replace the v2 synchronizer rather than post-correcting it. HAL's Busy
    // reservation and the custom job IDs are part of availability, not merely
    // current physical capability.
    ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState = {
        params ["_subject",["_source","sync"]];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group || {isNil "ITW_PlayerSide"} || {
            side _group != ITW_PlayerSide
        }) exitWith {false};

        private _subscriptions = [_group] call
            ITW_CLASH_PlayerTasks_fnc_GetSubscriptions;
        private _willing = _subscriptions isNotEqualTo [];
        private _capable = _willing && {
            [_group] call ITW_CLASH_PlayerTasks_fnc_HasExecutableSubscription
        };
        private _occupied = [_group] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob;
        private _available = _capable && {!_occupied};
        private _previous = _group getVariable [
            "ITW_CLASH_PlayerTaskAvailable",-1
        ];

        _group setVariable ["EnableHALActions",true,true];
        _group setVariable ["ITW_CLASH_PlayerTaskInitialized",true,true];
        _group setVariable ["ITW_CLASH_PlayerTaskOptIn",_willing,true];
        _group setVariable ["ITW_CLASH_PlayerTaskAvailable",_available,true];
        _group setVariable ["ITW_CLASH_PlayerHasActiveHALJob",_occupied,true];
        _group setVariable ["Unable",!_available,true];
        _group setVariable ["BUnable",!_available,true];

        if (_willing) then {
            ITW_CLASH_PlayerTaskGroups pushBackUnique _group;
        } else {
            ITW_CLASH_PlayerTaskGroups = ITW_CLASH_PlayerTaskGroups - [_group];
        };

        [_group] call ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission;

        if !(_previous isEqualTo _available) then {
            ["availability-changed",[
                if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                    [_group] call ITW_CLASH_DualHAL_fnc_GroupId
                } else {str _group},
                _available,
                _subscriptions,
                _source,
                _occupied
            ]] call ITW_CLASH_PlayerTasks_fnc_Log;
        };
        true
    };

    {
        private _group = group _x;
        if (!isNull _group && {!isNil "ITW_PlayerSide"} && {
            side _group == ITW_PlayerSide
        }) then {
            [_group,"hardening-install"] call
                ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
        };
    } forEach allPlayers;

    ITW_CLASH_PlayerTaskStateHardeningReady = true;
    diag_log format [
        "CLASH BOOT | player-task-state-admission-ready | version=%1 authoritativeAdmission=true busyAwareAvailability=true combatGate=true preHALBinder=true leaderCancelGate=%2",
        ITW_CLASH_PlayerTaskStateHardeningVersion,
        missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateLeaderGateReady",false]
    ];
};

// Phase 2: HAL's native deny function is only captured by PlayerTaskSupport's
// binder. Native cancellation waits for that exact function, but leader
// authority above does not.
[] spawn {
    scriptName "ITW_CLASH_PlayerTaskStateCancelBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateHardeningReady",false]
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_NativeAction1"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_CancelGroupJob"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_SendEmploymentState"}
            && {!isNil "Action1ct"}
        }
    };

    if (diag_tickTime >= _deadline) exitWith {
        ["cancel-bind-timeout",[
            "leaderGateRetained",
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateLeaderGateReady",false]
        ]] call ITW_CLASH_PlayerTaskState_fnc_Log;
    };
    if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateCancelReady",false]) exitWith {};

    // Preserve whichever specialist cancel layers are already installed. If
    // artillery binds later, it will in turn preserve this function as its base.
    ITW_CLASH_PlayerTaskState_fnc_CancelGroupJobBase =
        ITW_CLASH_PlayerTasks_fnc_CancelGroupJob;
    ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {false};

        private _ammoJob = _group getVariable ["ITW_CLASH_PlayerAmmoJobId",""];
        private _artilleryJob = _group getVariable [
            "ITW_CLASH_PlayerArtilleryJobId",""
        ];
        private _nativeJob = _group getVariable ["ITW_CLASH_PlayerNativeJobId",""];
        private _customActive = _ammoJob isNotEqualTo "" || {
            _artilleryJob isNotEqualTo ""
        };
        private _nativeActive = !_customActive && {
            _nativeJob isNotEqualTo "" || {
                _group getVariable ["Busy" + str _group,false]
            }
        };
        private _nativeDenyInFlight = _group getVariable [
            "ITW_CLASH_PlayerNativeJobCancelRequested",false
        ];

        ["cancel-request",[
            if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId
            } else {str _group},
            _ammoJob,_artilleryJob,_nativeJob,_nativeActive,_nativeDenyInFlight
        ]] call ITW_CLASH_PlayerTaskState_fnc_Log;

        private _specialResult = _this call
            ITW_CLASH_PlayerTaskState_fnc_CancelGroupJobBase;
        private _nativeResult = false;

        if (_nativeActive && {_nativeDenyInFlight}) then {
            // Hosted-server Action1ct already issued the native HAL deny before
            // entering this wrapper. Count it as accepted; never invoke it twice.
            _nativeResult = true;
            ["cancel-native-deny-already-in-flight",[
                if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                    [_group] call ITW_CLASH_DualHAL_fnc_GroupId
                } else {str _group}
            ]] call ITW_CLASH_PlayerTaskState_fnc_Log;
        } else {
            if (_nativeActive && {!isNil "ITW_CLASH_PlayerTasks_fnc_NativeAction1"}) then {
                private _leader = leader _group;
                if (!isNull _leader) then {
                    _group setVariable [
                        "ITW_CLASH_PlayerNativeJobCancelRequested",true
                    ];
                    [_leader] call ITW_CLASH_PlayerTasks_fnc_NativeAction1;
                    _group setVariable [
                        "ITW_CLASH_PlayerNativeJobCancelRequested",nil
                    ];
                    _nativeResult = true;
                };
            };
        };

        private _accepted = _specialResult || _nativeResult;
        [if (_accepted) then {"cancel-accepted"} else {"cancel-no-active-job"},[
            if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId
            } else {str _group},
            _specialResult,_nativeResult
        ]] call ITW_CLASH_PlayerTaskState_fnc_Log;

        if (_accepted) then {
            [_group] spawn {
                params ["_group"];
                private _deadline = time + 10;
                waitUntil {
                    sleep 0.25;
                    isNull _group
                    || {time >= _deadline}
                    || {!([_group] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob)}
                };
                if (isNull _group) exitWith {};
                [_group,"cancel-settle"] call
                    ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
                private _stillActive = [_group] call
                    ITW_CLASH_PlayerTasks_fnc_HasActiveJob;
                [if (_stillActive) then {"cancel-pending"} else {"cancel-settled"},[
                    if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                        [_group] call ITW_CLASH_DualHAL_fnc_GroupId
                    } else {str _group},
                    _group getVariable ["ITW_CLASH_PlayerTaskAvailable",false]
                ]] call ITW_CLASH_PlayerTaskState_fnc_Log;
            };
        };
        _accepted
    };

    // On a hosted server the action menu invokes PlayerTaskSupport's Action1ct
    // wrapper in the same namespace. That wrapper performs NativeAction1 first
    // and then calls the now-hardened CancelGroupJob. Scope the existing flag
    // around that wrapper so the inner cancellation path observes that native
    // deny is already in flight and cannot issue a second deny.
    ITW_CLASH_PlayerTaskState_fnc_Action1CancelBase = Action1ct;
    Action1ct = {
        private _unit = _this param [0,objNull];
        if (isNull _unit && {hasInterface}) then {_unit = player};
        private _group = if (isNull _unit) then {grpNull} else {group _unit};
        if (!isNull _group) then {
            _group setVariable [
                "ITW_CLASH_PlayerNativeJobCancelRequested",true
            ];
        };
        private _result = _this call ITW_CLASH_PlayerTaskState_fnc_Action1CancelBase;
        if (!isNull _group) then {
            _group setVariable [
                "ITW_CLASH_PlayerNativeJobCancelRequested",nil
            ];
        };
        _result
    };

    // Reassert the leader gate after native cancellation binds. The gate calls
    // CancelGroupJob by global name, so it automatically reaches the hardened
    // specialist/native composite above.
    call ITW_CLASH_PlayerTaskState_fnc_InstallLeaderCancelGate;

    ITW_CLASH_PlayerTaskStateCancelReady = true;
    diag_log format [
        "CLASH BOOT | player-task-state-cancel-ready | version=%1 nativeCancelBridge=true leaderCancelAuthority=true degradedLeaderGate=true hostedDoubleDenyGuard=true",
        ITW_CLASH_PlayerTaskStateHardeningVersion
    ];
};

// Phase 3: apply the same central admission gate to the dedicated artillery
// selector once that subsystem has defined its eligibility function.
[] spawn {
    scriptName "ITW_CLASH_PlayerTaskStateArtilleryBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateHardeningReady",false]
            && {!isNil "ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle"}
        }
    };

    if (diag_tickTime >= _deadline) exitWith {
        ["artillery-bind-timeout",[]] call ITW_CLASH_PlayerTaskState_fnc_Log;
    };
    if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateArtilleryGuardReady",false]) exitWith {};

    ITW_CLASH_PlayerTaskState_fnc_ArtilleryEligibleBase =
        ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle;
    ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle = {
        params ["_group"];
        if !([_group,"ARTILLERY"] call
            ITW_CLASH_PlayerTasks_fnc_CanAcceptJob
        ) exitWith {objNull};
        _this call ITW_CLASH_PlayerTaskState_fnc_ArtilleryEligibleBase
    };

    ITW_CLASH_PlayerTaskStateArtilleryGuardReady = true;
    diag_log format [
        "CLASH BOOT | player-task-state-artillery-guard-ready | version=%1 centralAdmission=true",
        ITW_CLASH_PlayerTaskStateHardeningVersion
    ];
};

true