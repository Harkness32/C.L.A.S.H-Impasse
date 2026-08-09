#include "defines.hpp"

ITW_CLASH_Mode = 0;
ITW_CLASH_ObserverEnabled = false;
ITW_CLASH_ObserverStarted = false;
ITW_CLASH_LiveEnabled = false;
ITW_CLASH_LiveStarted = false;
ITW_CLASH_HALReady = false;
ITW_CLASH_Transitioning = false;
ITW_CLASH_RegistrationFrozenUntil = 0;
ITW_CLASH_MaxManagedGroups = 12;
ITW_CLASH_MaxManagedPerObjective = 4;
ITW_CLASH_HALLeader = objNull;
ITW_CLASH_HALHQ = grpNull;
ITW_CLASH_HALObjectives = [];
ITW_CLASH_LastMirroredZone = -1;
ITW_CLASH_LastObjectiveSignature = "";
ITW_CLASH_ManagedGroups = [];
ITW_CLASH_ObserverNextId = 0;
ITW_CLASH_ObserverGroups = createHashMap;
ITW_CLASH_ObserverWriterLast = createHashMap;

ITW_CLASH_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isServer || {!ITW_CLASH_ObserverEnabled}) exitWith {};
    diag_log format ["CLASH OBS | %1 | %2",_event,_payload];
};

ITW_CLASH_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};

    private _id = _group getVariable ["ITW_CLASH_ObserverId",""];
    if (_id isEqualTo "") then {
        ITW_CLASH_ObserverNextId = ITW_CLASH_ObserverNextId + 1;
        _id = format ["G%1",ITW_CLASH_ObserverNextId];
        _group setVariable ["ITW_CLASH_ObserverId",_id];
    };
    _id
};

ITW_CLASH_fnc_ClassifyGroup = {
    params ["_group"];

    if (isNull _group) exitWith {[false,"null-group",[]]};
    if (isNil "ITW_EnemySide") exitWith {[false,"side-not-ready",[]]};
    if (side _group != ITW_EnemySide) exitWith {[false,"not-opfor",[side _group]]};

    private _members = units _group;
    private _aliveUnits = _members select {alive _x};
    if (_aliveUnits isEqualTo []) exitWith {[false,"dead-or-empty",[count _members]]};
    if (_aliveUnits findIf {isPlayer _x} >= 0) exitWith {[false,"player-group",[]]};
    if (!local _group) exitWith {[false,"headless-or-remote",[groupOwner _group]]};

    if (_group getVariable ["itwInitGrp",false]) exitWith {[false,"spawn-transition",[]]};
    if (_group getVariable ["itwDelivery",false]) exitWith {[false,"delivery",[]]};
    if (_group getVariable ["ITW_Garrison",false]) exitWith {[false,"garrison",[]]};
    if (_group getVariable ["VarWaitingTransport",false]) exitWith {[false,"awaiting-transport",[]]};

    private _getInState = _group getVariable ["ITW_getInState",-1];
    if (_getInState != -1) exitWith {[false,"transport-transition",[_getInState]]};
    if (_group getVariable ["ITW_OkayToReset",false]) exitWith {[false,"objective-reset",[]]};
    if (missionNamespace getVariable ["ITW_ObjZonesUpdating",false]) exitWith {[false,"zone-transition",[]]};
    if (ITW_CLASH_Transitioning || {time < ITW_CLASH_RegistrationFrozenUntil}) exitWith {
        [false,"bridge-frozen",[ITW_CLASH_RegistrationFrozenUntil - time]]
    };

    private _managedVehicleIndex = -1;
    if (!isNil "ITW_ManagedVehs") then {
        _managedVehicleIndex = ITW_ManagedVehs findIf {
            count _x > VEHINFO_CARGO_GRPS && {
                (_x#VEHINFO_CREW_GRP) isEqualTo _group || {
                    _group in (_x#VEHINFO_CARGO_GRPS)
                }
            }
        };
    };
    if (_managedVehicleIndex >= 0) exitWith {[false,"vehicle-managed",[_managedVehicleIndex]]};
    if (assignedVehicles _group isNotEqualTo []) exitWith {[false,"assigned-vehicle",[]]};
    if (_aliveUnits findIf {vehicle _x != _x} >= 0) exitWith {[false,"vehicle-or-cargo",[]]};
    if (_aliveUnits findIf {!(_x isKindOf "CAManBase")} >= 0) exitWith {[false,"not-infantry",[]]};

    private _supportIndex = _aliveUnits findIf {
        private _cfg = configFile >> "CfgVehicles" >> typeOf _x;
        getNumber (_cfg >> "attendant") > 0 || {
            getNumber (_cfg >> "engineer") > 0 || {
                getNumber (_cfg >> "uavHacker") > 0
            }
        }
    };
    if (_supportIndex >= 0) exitWith {
        [false,"support-specialist",[typeOf (_aliveUnits#_supportIndex)]]
    };

    private _objectiveIndex = VAR_GET_OBJ_IDX(_group);
    if (_objectiveIndex < 0) exitWith {[false,"unassigned-objective",[]]};

    [true,"eligible",[
        count _aliveUnits,
        _objectiveIndex,
        groupOwner _group
    ]]
};

ITW_CLASH_fnc_ClearGroupWaypoints = {
    params ["_group"];
    if (isNull _group) exitWith {false};

    if (!isNil "RYD_WPdel") then {
        [_group] call RYD_WPdel;
    } else {
        {deleteWaypoint _x} forEachReversed waypoints _group;
    };
    true
};

ITW_CLASH_fnc_SyncHALIncluded = {
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {[]};

    ITW_CLASH_ManagedGroups = ITW_CLASH_ManagedGroups select {
        !isNull _x && {
            count units _x > 0 && {
                _x getVariable ["ITW_CLASH_Managed",false]
            }
        }
    };

    RydHQ_Included = +ITW_CLASH_ManagedGroups;
    RydHQ_NoDef = +ITW_CLASH_ManagedGroups;
    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_Included",+ITW_CLASH_ManagedGroups];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoDef",+ITW_CLASH_ManagedGroups];
    };
    +ITW_CLASH_ManagedGroups
};

ITW_CLASH_fnc_MirrorObjectives = {
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {false};
    if (isNil "ITW_Zones" || {isNil "ITW_ZoneIndex"} || {isNil "ITW_Objectives"}) exitWith {
        ["objective-mirror-deferred",[]] call ITW_CLASH_fnc_Log;
        false
    };
    if (ITW_ZoneIndex < 0 || {ITW_ZoneIndex >= count ITW_Zones}) exitWith {
        ["objective-mirror-invalid-zone",[ITW_ZoneIndex,count ITW_Zones]] call ITW_CLASH_fnc_Log;
        false
    };

    {
        if (!isNull _x) then {
            _x setVariable ["SetTakenA",false];
            if (!isNull ITW_CLASH_HALHQ) then {
                _x setVariable [
                    format ["Capturing%1%2",str _x,str ITW_CLASH_HALHQ],
                    nil
                ];
            };
        };
    } forEach ITW_CLASH_HALObjectives;

    private _zoneChanged = ITW_CLASH_LastMirroredZone != ITW_ZoneIndex;
    private _mirrors = [];
    private _taken = [];
    {
        private _objectiveIndex = _x;
        if (_objectiveIndex >= 0 && {_objectiveIndex < count ITW_Objectives}) then {
            private _objective = ITW_Objectives#_objectiveIndex;
            if (count _objective > ITW_OBJ_FLAG) then {
                private _flag = _objective#ITW_OBJ_FLAG;
                if (!isNull _flag) then {
                    private _playerOwned = [_objectiveIndex] call ITW_ObjContestedOwnerIsFriendly;
                    _flag setVariable ["SetTakenA",!_playerOwned];
                    _mirrors pushBack _flag;
                    if (!_playerOwned) then {
                        _taken pushBack _flag;
                    };
                };
            };
        };
    } forEach (ITW_Zones#ITW_ZoneIndex);

    ITW_CLASH_HALObjectives = _mirrors;
    RydHQ_SimpleMode = true;
    RydHQ_SimpleObjs = +_mirrors;
    RydHQ_Taken = +_taken;
    if (_zoneChanged) then {
        RydHQ_NObj = 1;
    };

    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_SimpleMode",true];
        ITW_CLASH_HALHQ setVariable ["RydHQ_SimpleObjs",+_mirrors];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Objectives",+_mirrors];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Taken",+_taken];
        if (_zoneChanged) then {
            ITW_CLASH_HALHQ setVariable ["RydHQ_NObj",1];
        };
    };

    ITW_CLASH_LastMirroredZone = ITW_ZoneIndex;
    private _signature = str [
        ITW_ZoneIndex,
        _mirrors apply {str _x},
        _taken apply {str _x}
    ];
    if (_signature != ITW_CLASH_LastObjectiveSignature) then {
        ITW_CLASH_LastObjectiveSignature = _signature;
        ["objective-mirror",[ITW_ZoneIndex,count _mirrors,count _taken]] call ITW_CLASH_fnc_Log;
    };
    !(_mirrors isEqualTo [])
};

ITW_CLASH_fnc_RegisterGroup = {
    params ["_group",["_source","reconcile"],["_allowBeforeReady",false]];
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {false};
    if (!ITW_CLASH_HALReady && {!_allowBeforeReady}) exitWith {false};
    if (isNull _group || {!local _group}) exitWith {false};
    if (_group getVariable ["ITW_CLASH_Managed",false]) exitWith {true};

    private _result = [_group] call ITW_CLASH_fnc_ClassifyGroup;
    if !(_result#0) exitWith {false};

    private _objectiveIndex = VAR_GET_OBJ_IDX(_group);
    private _sameObjectiveCount = {
        !isNull _x && {
            (_x getVariable ["ITW_CLASH_Managed",false]) && {
                VAR_GET_OBJ_IDX(_x) == _objectiveIndex
            }
        }
    } count ITW_CLASH_ManagedGroups;

    if (count ITW_CLASH_ManagedGroups >= ITW_CLASH_MaxManagedGroups || {
        _sameObjectiveCount >= ITW_CLASH_MaxManagedPerObjective
    }) exitWith {
        if !(_group getVariable ["ITW_CLASH_CapacityLogged",false]) then {
            _group setVariable ["ITW_CLASH_CapacityLogged",true];
            ["pilot-capacity",[
                [_group] call ITW_CLASH_fnc_GroupId,
                _objectiveIndex,
                count ITW_CLASH_ManagedGroups,
                _sameObjectiveCount
            ]] call ITW_CLASH_fnc_Log;
        };
        false
    };

    _group setVariable ["ITW_CLASH_CapacityLogged",nil];
    _group setVariable ["RydHQ_MIA",nil];
    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group setVariable ["ITW_CLASH_Managed",true];
    ITW_CLASH_ManagedGroups pushBackUnique _group;
    call ITW_CLASH_fnc_SyncHALIncluded;

    ["register",[
        _source,
        [_group] call ITW_CLASH_fnc_GroupId,
        str _group,
        _objectiveIndex,
        count units _group
    ]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_BeginRelease = {
    params ["_group",["_reason","unspecified"]];
    if (!isServer || {!ITW_CLASH_LiveEnabled} || {isNull _group}) exitWith {false};

    private _managed = _group getVariable ["ITW_CLASH_Managed",false] || {
        _group in ITW_CLASH_ManagedGroups
    };
    if (!_managed || {_group getVariable ["ITW_CLASH_Releasing",false]}) exitWith {false};

    _group setVariable ["ITW_CLASH_ReleaseReason",_reason];
    _group setVariable ["ITW_CLASH_ReleaseStarted",diag_tickTime];
    _group setVariable ["ITW_CLASH_Releasing",true];
    _group setVariable ["RydHQ_MIA",true];
    ITW_CLASH_ManagedGroups = ITW_CLASH_ManagedGroups - [_group];
    call ITW_CLASH_fnc_SyncHALIncluded;

    if (!isNull ITW_CLASH_HALHQ) then {
        {
            private _varName = _x;
            if ((_varName select [0,6]) isEqualTo "RydHQ_") then {
                private _value = ITW_CLASH_HALHQ getVariable _varName;
                if (_value isEqualType [] && {_group in _value}) then {
                    ITW_CLASH_HALHQ setVariable [_varName,_value - [_group]];
                };
            };
        } forEach allVariables ITW_CLASH_HALHQ;
    };
    true
};

ITW_CLASH_fnc_ReleaseAcknowledged = {
    params ["_group"];
    if (isNull _group) exitWith {true};

    private _releaseStarted = _group getVariable ["ITW_CLASH_ReleaseStarted",diag_tickTime];
    if (diag_tickTime - _releaseStarted < 6.5) exitWith {false};

    private _busyName = "Busy" + str _group;
    !(_group getVariable [_busyName,false]) || {
        !(_group getVariable ["RydHQ_MIA",false])
    }
};

ITW_CLASH_fnc_FinishRelease = {
    params ["_group",["_timedOut",false]];
    if (isNull _group) exitWith {false};

    private _reason = _group getVariable ["ITW_CLASH_ReleaseReason","unspecified"];
    private _id = [_group] call ITW_CLASH_fnc_GroupId;
    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group setVariable ["ITW_CLASH_Managed",false];
    _group setVariable ["ITW_CLASH_Releasing",false];
    _group setVariable ["ITW_CLASH_ReleaseReason",nil];
    _group setVariable ["ITW_CLASH_ReleaseStarted",nil];

    if (_timedOut) then {
        ["release-timeout",[_reason,_id,str _group]] call ITW_CLASH_fnc_Log;
    };
    ["release",[_reason,_id,str _group,count units _group]] call ITW_CLASH_fnc_Log;
    true
};

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
            call ITW_CLASH_fnc_MirrorObjectives;
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
    RydHQ_CargoFind = 0;
    RydHQ_SecTasks = false;
    RydHQ_ResetOnDemand = false;
    RydHQ_ResetTime = 30;
    RydHQ_Order = "ATTACK";
    RydHQ_IdleDef = false;
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
    if (ITW_CLASH_HALObjectives isNotEqualTo []) then {
        _position = getPosATL (ITW_CLASH_HALObjectives#0);
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
        ["pilot-ready",[
            "opfor-dismounted-live",
            count ITW_CLASH_ManagedGroups,
            ITW_CLASH_MaxManagedGroups,
            ITW_CLASH_MaxManagedPerObjective
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
["ITW_CLASH_fnc_ClassifyGroup"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ClearGroupWaypoints"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_SyncHALIncluded"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_MirrorObjectives"] call SKL_fnc_CompileFinal;
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
