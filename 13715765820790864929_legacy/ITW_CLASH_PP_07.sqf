#include "defines.hpp"

// C.L.A.S.H. V6 preprocessor bisect chunk 7/8.
// Original ITW_CLASH.sqf lines 1981-2310. Diagnostic only; never executed.

ITW_CLASH_fnc_ReleaseGroup = {
    params ["_group",["_reason","unspecified"]];
    if !([_group,_reason] call ITW_CLASH_fnc_BeginRelease) exitWith {false};

    private _timedOut = false;
    if (canSuspend) then {
        private _deadline = diag_tickTime + 15;
        waitUntil {
            sleep 0.1;
            [_group] call ITW_CLASH_fnc_ReleaseAcknowledged || {
                diag_tickTime >= _deadline
            }
        };
        _timedOut = diag_tickTime >= _deadline && {
            !([_group] call ITW_CLASH_fnc_ReleaseAcknowledged)
        };
    } else {
        _timedOut = !([_group] call ITW_CLASH_fnc_ReleaseAcknowledged);
    };

    [_group,_timedOut] call ITW_CLASH_fnc_FinishRelease
};

ITW_CLASH_fnc_ReleaseAll = {
    params [["_reason","unspecified"]];
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {0};

    private _groups = +ITW_CLASH_ManagedGroups;
    private _releasing = [];
    {
        if ([_x,_reason] call ITW_CLASH_fnc_BeginRelease) then {
            _releasing pushBack _x;
        };
    } forEach _groups;

    private _timedOut = false;
    if (canSuspend && {_releasing isNotEqualTo []}) then {
        private _deadline = diag_tickTime + 15;
        waitUntil {
            sleep 0.1;
            _releasing findIf {
                !([_x] call ITW_CLASH_fnc_ReleaseAcknowledged)
            } < 0 || {
                diag_tickTime >= _deadline
            }
        };
        _timedOut = diag_tickTime >= _deadline;
    };

    {
        private _groupTimedOut = _timedOut && {
            !([_x] call ITW_CLASH_fnc_ReleaseAcknowledged)
        };
        [_x,_groupTimedOut] call ITW_CLASH_fnc_FinishRelease;
    } forEach _releasing;

    ["actual-release-scan",[_reason,count _releasing]] call ITW_CLASH_fnc_Log;
    count _releasing
};

ITW_CLASH_fnc_ObserveGroup = {
    params ["_source","_group"];
    if (!isServer || {!ITW_CLASH_ObserverEnabled}) exitWith {false};
    if (isNull _group) exitWith {
        ["classified",[_source,"<null>","null-group"]] call ITW_CLASH_fnc_Log;
        false
    };

    private _id = [_group] call ITW_CLASH_fnc_GroupId;
    private _result = [_group] call ITW_CLASH_fnc_ClassifyGroup;
    _result params ["_eligible","_reason","_details"];
    private _state = if (_eligible) then {"ELIGIBLE"} else {"REJECTED"};

    private _previous = ITW_CLASH_ObserverGroups getOrDefault [_id,[]];
    private _previousState = if (_previous isEqualTo []) then {""} else {_previous#1};
    private _previousReason = if (_previous isEqualTo []) then {""} else {_previous#2};

    if (_previousState != _state || {_previousReason != _reason}) then {
        if (_eligible) then {
            ["would-register",[_source,_id,str _group,_details]] call ITW_CLASH_fnc_Log;
        } else {
            if (_previousState isEqualTo "ELIGIBLE") then {
                ["would-release",[_source,_id,str _group,_reason,_details]] call ITW_CLASH_fnc_Log;
            } else {
                ["classified",[_source,_id,str _group,_reason,_details]] call ITW_CLASH_fnc_Log;
            };
        };
    };

    ITW_CLASH_ObserverGroups set [_id,[_group,_state,_reason,time,_details]];

    if (ITW_CLASH_LiveEnabled && {ITW_CLASH_HALReady}) then {
        if (_eligible) then {
            [_group,_source] call ITW_CLASH_fnc_RegisterGroup;
        } else {
            if (_group getVariable ["ITW_CLASH_Managed",false]) then {
                [_group,format ["classification:%1",_reason]] call ITW_CLASH_fnc_ReleaseGroup;
            };
        };
    };
    _eligible
};

ITW_CLASH_fnc_ObserveWriter = {
    params ["_writer","_group"];
    if (!isServer || {!ITW_CLASH_ObserverEnabled} || {isNull _group}) exitWith {false};

    if ([_group] call ITW_CLASH_fnc_IsCommanderGroup) exitWith {
        private _id = [_group] call ITW_CLASH_fnc_GroupId;
        private _key = format ["%1|commander|%2",_id,_writer];
        private _last = ITW_CLASH_ObserverWriterLast getOrDefault [_key,-1000];
        if (time - _last >= 10) then {
            ITW_CLASH_ObserverWriterLast set [_key,time];
            ["commander-writer-suppressed",[_writer,_id,str _group]] call ITW_CLASH_fnc_Log;
        };
        true
    };

    private _eligible = ["writer-scan",_group] call ITW_CLASH_fnc_ObserveGroup;
    if (!_eligible) exitWith {false};

    private _id = [_group] call ITW_CLASH_fnc_GroupId;
    private _key = format ["%1|%2",_id,_writer];
    private _last = ITW_CLASH_ObserverWriterLast getOrDefault [_key,-1000];
    if (time - _last >= 10) then {
        ITW_CLASH_ObserverWriterLast set [_key,time];
        ["candidate-waypoint-writer",[
            _writer,
            _id,
            str _group,
            currentWaypoint _group,
            count waypoints _group
        ]] call ITW_CLASH_fnc_Log;
    };

    if (!ITW_CLASH_LiveEnabled || {
        !(_group getVariable ["ITW_CLASH_Managed",false])
    }) exitWith {false};
    if (_group getVariable ["ITW_CLASH_Releasing",false]) exitWith {true};

    if (_writer in ["stuck-handler","infantry-manager-garrison","infantry-manager-merge"]) exitWith {
        [_group,format ["impasse-writer:%1",_writer]] call ITW_CLASH_fnc_ReleaseGroup;
        false
    };

    if (time - _last >= 10) then {
        ["impasse-writer-suppressed",[_writer,_id,str _group]] call ITW_CLASH_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_WouldReleaseAll = {
    params ["_reason"];
    if (!isServer || {!ITW_CLASH_ObserverEnabled}) exitWith {0};

    private _count = 0;
    {
        private _id = _x;
        private _entry = ITW_CLASH_ObserverGroups get _id;
        if ((_entry#1) isEqualTo "ELIGIBLE") then {
            private _group = _entry#0;
            _count = _count + 1;
            ["would-release",[_reason,_id,str _group,_entry#4]] call ITW_CLASH_fnc_Log;
            ITW_CLASH_ObserverGroups set [_id,[_group,"RELEASED",_reason,time,_entry#4]];
        };
    } forEach +(keys ITW_CLASH_ObserverGroups);

    ["release-scan",[_reason,_count]] call ITW_CLASH_fnc_Log;
    _count
};

ITW_CLASH_fnc_ObserveLifecycle = {
    params ["_event",["_details",[]]];
    if (!isServer || {!ITW_CLASH_ObserverEnabled}) exitWith {false};

    if (_event isEqualTo "zone-transition-begin") then {
        ITW_CLASH_Transitioning = true;
        ITW_CLASH_RegistrationFrozenUntil = 1e10;
    };

    if (_event in ["zone-transition-begin","before-atk-next","defend-start","defend-done"]) then {
        if (ITW_CLASH_LiveEnabled) then {
            [_event] call ITW_CLASH_fnc_ResetAnchors;
            [_event] call ITW_CLASH_fnc_ReleaseAll;
            if !(_event isEqualTo "zone-transition-begin") then {
                ITW_CLASH_RegistrationFrozenUntil = ITW_CLASH_RegistrationFrozenUntil max (time + 5);
            };
        };
        [_event] call ITW_CLASH_fnc_WouldReleaseAll;
    };

    if (_event isEqualTo "contested-state-published" && {
        ITW_CLASH_LiveEnabled && {ITW_CLASH_HALReady}
    }) then {
        call ITW_CLASH_fnc_MirrorObjectives;
    };

    if (_event isEqualTo "zone-transition-end") then {
        ITW_CLASH_Transitioning = false;
        if (ITW_CLASH_LiveEnabled) then {
            call ITW_CLASH_fnc_MirrorObjectives;
            ITW_CLASH_RegistrationFrozenUntil = time + 35;
            ITW_CLASH_AnchorAuditReadyAt = time + 45;
        } else {
            ITW_CLASH_RegistrationFrozenUntil = 0;
        };
    };

    ["lifecycle",[_event,_details]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_Reconcile = {
    if (!isServer || {!ITW_CLASH_ObserverEnabled}) exitWith {};

    {
        private _id = _x;
        private _entry = ITW_CLASH_ObserverGroups get _id;
        private _group = _entry#0;
        if (isNull _group) then {
            if ((_entry#1) isEqualTo "ELIGIBLE") then {
                ["would-release",["deleted-or-merged",_id,str _group]] call ITW_CLASH_fnc_Log;
            };
            ITW_CLASH_ObserverGroups deleteAt _id;
        } else {
            if (count units _group == 0 && {(_entry#1) isEqualTo "ELIGIBLE"}) then {
                ["reconcile",_group] call ITW_CLASH_fnc_ObserveGroup;
            };
        };
    } forEach +(keys ITW_CLASH_ObserverGroups);

    if (!isNil "ITW_EnemySide") then {
        {
            if (side _x == ITW_EnemySide) then {
                ["reconcile",_x] call ITW_CLASH_fnc_ObserveGroup;
            };
        } forEach allGroups;
    };

    if (ITW_CLASH_LiveEnabled) then {
        if (ITW_CLASH_HALReady && {!ITW_CLASH_Transitioning}) then {
            call ITW_CLASH_fnc_AuditWithdrawals;
            call ITW_CLASH_fnc_MirrorObjectives;
            call ITW_CLASH_fnc_AuditAnchors;
            call ITW_CLASH_fnc_AuditAllocations;
        };
        call ITW_CLASH_fnc_SyncHALIncluded;
    };
};

ITW_CLASH_fnc_DiagnosticSnapshot = {
    private _eligible = 0;
    private _rejected = createHashMap;

    {
        private _entry = _y;
        if ((_entry#1) isEqualTo "ELIGIBLE") then {
            _eligible = _eligible + 1;
        } else {
            private _reason = _entry#2;
            _rejected set [_reason,(_rejected getOrDefault [_reason,0]) + 1];
        };
    } forEach ITW_CLASH_ObserverGroups;

    private _snapshot = createHashMapFromArray [
        ["mode",ITW_CLASH_Mode],
        ["enabled",ITW_CLASH_ObserverEnabled],
        ["live",ITW_CLASH_LiveEnabled],
        ["halReady",ITW_CLASH_HALReady],
        ["tracked",count ITW_CLASH_ObserverGroups],
        ["eligible",_eligible],
        ["managed",count ITW_CLASH_ManagedGroups],
        ["anchorSlots",count (keys ITW_CLASH_AnchorGroups)],
        ["anchorRefills",count (keys ITW_CLASH_AnchorRefills)],
        ["anchorMinimum",ITW_CLASH_MinAnchorSoldiers],
        ["doctrine",missionNamespace getVariable ["RydHQ_Order","<unset>"]],
        ["heldObjectives",+ITW_CLASH_LastHeldObjectives],
        ["activeObjectives",count ITW_CLASH_HALObjectives],
        ["noAttack",count (missionNamespace getVariable ["RydHQ_NoAttack",[]])],
        ["noRecon",count (missionNamespace getVariable ["RydHQ_NoRecon",[]])],
        ["rejected",_rejected],
        ["zone",missionNamespace getVariable ["ITW_ZoneIndex",-1]],
        ["transition",missionNamespace getVariable ["ITW_ObjZonesUpdating",false]]
    ];
    diag_log format ["CLASH OBS | snapshot | %1",_snapshot];
    _snapshot
};

ITW_CLASH_fnc_ConfigureHAL = {
    if (!isServer) exitWith {false};

    RydHQ_Wait = 1;
    RydHQ_SubAll = false;
    RydHQ_Included = [];
    RydHQ_Excluded = [];
    RydHQ_NoDef = [];
    RydHQ_NoAttack = [];
    RydHQ_NoRecon = [];
    RydHQ_CargoFind = 0;
    RydHQ_SecTasks = false;
    RydHQ_ResetOnDemand = false;
    RydHQ_ResetTime = 30;
    RydHQ_Order = "DEFEND";
    RydHQ_Berserk = false;
    RydHQ_AttackAlways = false;
    RydHQ_IdleDef = true;
    RydHQ_DefendObjectives = 1;
    RydHQ_CRDefRes = ITW_CLASH_ReserveRatio;
    RydHQ_MAtt = true;
    RydHQ_Personality = "COMPETENT";
    RydHQ_Recklessness = 0.5;
    RydHQ_Consistency = 0.5;
    RydHQ_Activity = 0.5;
    RydHQ_Reflex = 0.5;
    RydHQ_Circumspection = 0.5;
    RydHQ_Fineness = 0.5;
    RydHQ_SimpleMode = true;
    RydHQ_SimpleObjs = [];
    RydHQ_GetHQInside = false;
    RydHQ_LRelocating = false;

    RydxHQ_Actions = false;
    RydxHQ_ActionsMenu = false;
    RydxHQ_TaskActions = false;
    RydxHQ_SupportActions = false;
    RydxHQ_NoRestPlayers = true;
    RydxHQ_NoCargoPlayers = true;
    true
};
