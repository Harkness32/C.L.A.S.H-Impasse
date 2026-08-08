#include "defines.hpp"

ITW_CLASH_ObserverEnabled = false;
ITW_CLASH_ObserverStarted = false;
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
    true
};

ITW_CLASH_fnc_WouldReleaseAll = {
    params ["_reason"];
    if (!isServer || {!ITW_CLASH_ObserverEnabled}) exitWith {0};

    private _count = 0;
    {
        private _group = _x;
        if (!isNil "ITW_EnemySide" && {side _group == ITW_EnemySide}) then {
            private _result = [_group] call ITW_CLASH_fnc_ClassifyGroup;
            if (_result#0) then {
                _count = _count + 1;
                private _id = [_group] call ITW_CLASH_fnc_GroupId;
                ["would-release",[_reason,_id,str _group,_result#2]] call ITW_CLASH_fnc_Log;
            };
        };
    } forEach allGroups;

    ["release-scan",[_reason,_count]] call ITW_CLASH_fnc_Log;
    _count
};

ITW_CLASH_fnc_ObserveLifecycle = {
    params ["_event",["_details",[]]];
    if (!isServer || {!ITW_CLASH_ObserverEnabled}) exitWith {false};

    if (_event in ["before-atk-next","defend-start","defend-done"]) then {
        [_event] call ITW_CLASH_fnc_WouldReleaseAll;
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
        ["enabled",ITW_CLASH_ObserverEnabled],
        ["tracked",count ITW_CLASH_ObserverGroups],
        ["eligible",_eligible],
        ["rejected",_rejected],
        ["zone",missionNamespace getVariable ["ITW_ZoneIndex",-1]],
        ["transition",missionNamespace getVariable ["ITW_ObjZonesUpdating",false]]
    ];
    diag_log format ["CLASH OBS | snapshot | %1",_snapshot];
    _snapshot
};

ITW_CLASH_fnc_StartObserver = {
    if (!isServer) exitWith {false};
    if (ITW_CLASH_ObserverStarted) exitWith {true};

    ITW_CLASH_ObserverEnabled = true;
    ITW_CLASH_ObserverStarted = true;
    ["observer-start",["mode","opfor-dismounted-observe-only"]] call ITW_CLASH_fnc_Log;

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
["ITW_CLASH_fnc_ObserveGroup"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ObserveWriter"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_WouldReleaseAll"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_ObserveLifecycle"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_Reconcile"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_DiagnosticSnapshot"] call SKL_fnc_CompileFinal;
["ITW_CLASH_fnc_StartObserver"] call SKL_fnc_CompileFinal;

if (isServer) then {
    [] spawn {
        waitUntil {sleep 0.1; !isNil "ITW_Params_complete"};
        if ((missionNamespace getVariable ["ITW_ParamCLASHObserver",0]) == 1) then {
            call ITW_CLASH_fnc_StartObserver;
        } else {
            diag_log "CLASH OBS | disabled | lobby parameter is Off";
        };
    };
};
