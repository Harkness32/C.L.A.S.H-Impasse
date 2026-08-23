#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateHardeningStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskStateHardeningStarted = true;
ITW_CLASH_PlayerTaskStateHardeningReady = false;
ITW_CLASH_PlayerTaskStateHardeningVersion = 1;

ITW_CLASH_PlayerTaskState_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_Log") then {
        ["state-" + _event,_payload] call ITW_CLASH_PlayerTasks_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER TASK STATE | %1 | %2",_event,_payload];
    };
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskStateHardening";
    private _deadline = diag_tickTime + 120;
    waitUntil {
        sleep 0.25;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskSupportReady",false]
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_NativeAction1"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_GetSubscriptions"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_IsSubscribed"}
        }
    };

    if (diag_tickTime >= _deadline) exitWith {
        ["bind-timeout",[]] call ITW_CLASH_PlayerTaskState_fnc_Log;
    };
    if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskStateHardeningReady",false]) exitWith {};

    ITW_CLASH_PlayerTasks_fnc_HasActiveJob = {
        params ["_subject"];
        private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {false};

        (_group getVariable ["Busy" + str _group,false])
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

        ["cancel-request",[
            if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId
            } else {str _group},
            _ammoJob,_artilleryJob,_nativeJob,_nativeActive
        ]] call ITW_CLASH_PlayerTaskState_fnc_Log;

        private _specialResult = _this call
            ITW_CLASH_PlayerTaskState_fnc_CancelGroupJobBase;
        private _nativeResult = false;

        if (_nativeActive && {!isNil "ITW_CLASH_PlayerTasks_fnc_NativeAction1"}) then {
            private _leader = leader _group;
            if (!isNull _leader) then {
                _group setVariable [
                    "ITW_CLASH_PlayerNativeJobCancelRequested",true,true
                ];
                [_leader] call ITW_CLASH_PlayerTasks_fnc_NativeAction1;
                _nativeResult = true;
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

    // The client menu already requires group leadership. Enforce the same
    // authority on the server instead of trusting the UI boundary.
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

    if (!isNil "ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle") then {
        ITW_CLASH_PlayerTaskState_fnc_ArtilleryEligibleBase =
            ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle;
        ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle = {
            params ["_group"];
            if !([_group,"ARTILLERY"] call
                ITW_CLASH_PlayerTasks_fnc_CanAcceptJob
            ) exitWith {objNull};
            _this call ITW_CLASH_PlayerTaskState_fnc_ArtilleryEligibleBase
        };
    };

    {
        private _group = group _x;
        if (!isNull _group && {side _group == ITW_PlayerSide}) then {
            [_group,"hardening-install"] call
                ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
        };
    } forEach allPlayers;

    ITW_CLASH_PlayerTaskStateHardeningReady = true;
    diag_log format [
        "CLASH BOOT | player-task-state-hardening-ready | version=%1 authoritativeAdmission=true busyAwareAvailability=true combatGate=true nativeCancelBridge=true leaderCancelAuthority=true",
        ITW_CLASH_PlayerTaskStateHardeningVersion
    ];
};

true
