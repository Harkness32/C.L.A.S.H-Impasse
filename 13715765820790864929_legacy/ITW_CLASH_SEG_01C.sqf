#include "defines.hpp"

ITW_CLASH_fnc_CountConscious = {
    params ["_units",["_center",[]],["_radius",-1]];
    {
        [_x] call ITW_CLASH_fnc_IsConscious && {
            _radius < 0 || {
                _center isNotEqualTo [] && {
                    _x distance _center < _radius
                }
            }
        }
    } count _units
};

ITW_CLASH_fnc_IsHALExhausted = {
    params ["_group"];
    !isNull _group && {
        !isNull ITW_CLASH_HALHQ && {
            _group in (
                ITW_CLASH_HALHQ getVariable ["RydHQ_Exhausted",[]]
            )
        }
    }
};

ITW_CLASH_fnc_GetArchetype = {
    params ["_group"];
    if (isNull _group) exitWith {[]};

    private _archetype = +(
        _group getVariable ["ITW_CLASH_Archetype",[]]
    );
    if (_archetype isEqualTo []) then {
        _archetype = (units _group) apply {toLowerANSI typeOf _x};
        _group setVariable ["ITW_CLASH_Archetype",+_archetype];
    };
    _archetype
};

ITW_CLASH_fnc_AnchorKey = {
    params [["_objectiveIndex",-1]];
    str _objectiveIndex
};

ITW_CLASH_fnc_GetObjectiveRadius = {
    params [["_objectiveIndex",-1]];
    if (isNil "ITW_Objectives" || {
        _objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}
    }) exitWith {0};

    private _objective = ITW_Objectives#_objectiveIndex;
    if (count _objective <= ITW_OBJ_SIZE) exitWith {0};
    _objective#ITW_OBJ_SIZE
};

ITW_CLASH_fnc_GetObjectiveCenter = {
    params [["_objectiveIndex",-1],["_flag",objNull]];
    if (isNull _flag) then {
        _flag = [_objectiveIndex] call ITW_CLASH_fnc_GetObjectiveFlag;
    };
    if (isNull _flag) exitWith {[]};
    _flag getVariable ["ITW_FlagPos",getPosATL _flag]
};

ITW_CLASH_fnc_GetObjectiveFlag = {
    params [["_objectiveIndex",-1]];
    if (isNil "ITW_Objectives" || {
        _objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}
    }) exitWith {objNull};

    private _objective = ITW_Objectives#_objectiveIndex;
    if (count _objective <= ITW_OBJ_FLAG) exitWith {objNull};
    _objective#ITW_OBJ_FLAG
};

ITW_CLASH_fnc_GetActiveObjectives = {
    if (isNil "ITW_Zones" || {
        isNil "ITW_ZoneIndex" || {
            isNil "ITW_Objectives"
        }
    }) exitWith {[]};
    if (ITW_ZoneIndex < 0 || {ITW_ZoneIndex >= count ITW_Zones}) exitWith {[]};

    private _active = [];
    {
        private _objectiveIndex = _x;
        private _flag = [_objectiveIndex] call ITW_CLASH_fnc_GetObjectiveFlag;
        if (!isNull _flag) then {
            _active pushBack [_objectiveIndex,_flag];
        };
    } forEach (ITW_Zones#ITW_ZoneIndex);
    _active
};

ITW_CLASH_fnc_GetHeldObjectives = {
    if (isNil "ITW_ObjContestedOwnerIsFriendly") exitWith {[]};

    private _held = [];
    {
        _x params ["_objectiveIndex","_flag"];
        if !([_objectiveIndex] call ITW_ObjContestedOwnerIsFriendly) then {
            _held pushBack [_objectiveIndex,_flag];
        };
    } forEach (call ITW_CLASH_fnc_GetActiveObjectives);
    _held
};

ITW_CLASH_fnc_GetCommanderPosition = {
    params [["_objectiveIndex",-1],["_flag",objNull]];
    if (isNull _flag) exitWith {[0,0,0]};

    private _radius = [_objectiveIndex] call ITW_CLASH_fnc_GetObjectiveRadius;
    private _center = [_objectiveIndex,_flag] call ITW_CLASH_fnc_GetObjectiveCenter;
    private _distance = _radius + 75;
    private _position = _center getPos [_distance,0];
    private _found = false;
    {
        private _candidate = _center getPos [_distance,_x];
        if (!surfaceIsWater _candidate) exitWith {
            _position = _candidate;
            _found = true;
        };
    } forEach [0,90,180,270];

    if (!_found) then {
        _position = [
            _center,
            _radius + 50,
            _radius + 250,
            2,
            0,
            0.5,
            0,
            [],
            [_position,_position]
        ] call BIS_fnc_findSafePos;
    };
    _position set [2,0];
    _position
};

ITW_CLASH_fnc_SyncCommanderObjective = {
    params [["_heldObjectives",[]]];
    if (!isServer || {isNull ITW_CLASH_HALLeader}) exitWith {-1};
    if (_heldObjectives isEqualTo []) then {
        _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    };
    if (_heldObjectives isEqualTo []) exitWith {-1};

    private _objectiveIndex = _heldObjectives#0#0;
    private _flag = _heldObjectives#0#1;
    if (isNull _flag) exitWith {-1};

    private _position = [
        _objectiveIndex,
        _flag
    ] call ITW_CLASH_fnc_GetCommanderPosition;
    ITW_CLASH_HALLeader setPosATL _position;
    if (ITW_CLASH_CommanderObjective != _objectiveIndex) then {
        ITW_CLASH_CommanderObjective = _objectiveIndex;
        ["commander-objective",[
            _objectiveIndex,
            _position,
            round (_position distance2D _flag)
        ]] call ITW_CLASH_fnc_Log;
    };
    _objectiveIndex
};

ITW_CLASH_fnc_ClassifyGroup = {
    params ["_group"];

    if (isNull _group) exitWith {[false,"null-group",[]]};
    if ([_group] call ITW_CLASH_fnc_IsCommanderGroup) exitWith {[false,"clash-commander",[]]};
    if (_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {
        [false,"combat-ineffective-withdrawal",[]]
    };
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
    private _reeligibleAt = _group getVariable ["ITW_CLASH_ReeligibleAt",0];
    if (time < _reeligibleAt) exitWith {
        [false,"allocation-cooldown",[_reeligibleAt - time]]
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
    if (isNil "ITW_Zones" || {
        isNil "ITW_ZoneIndex" || {
            isNil "ITW_ObjContestedOwnerIsFriendly"
        }
    }) exitWith {[false,"objective-state-not-ready",[]]};
    if (ITW_ZoneIndex < 0 || {ITW_ZoneIndex >= count ITW_Zones}) exitWith {
        [false,"objective-zone-invalid",[ITW_ZoneIndex]]
    };
    if !(_objectiveIndex in (ITW_Zones#ITW_ZoneIndex)) exitWith {
        [false,"objective-outside-active-zone",[_objectiveIndex,ITW_ZoneIndex]]
    };
    private _assignedObjective = _group getVariable ["ITW_CLASH_AssignedObjective",-1];
    if (_group getVariable ["ITW_CLASH_Managed",false] && {
        _assignedObjective >= 0 && {_assignedObjective != _objectiveIndex}
    }) exitWith {
        [false,"objective-reassigned",[_assignedObjective,_objectiveIndex]]
    };

    [true,"eligible",[
        count _aliveUnits,
        _objectiveIndex,
        groupOwner _group
    ]]
};
