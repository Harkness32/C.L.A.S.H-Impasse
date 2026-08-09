#include "defines.hpp"

ITW_CLASH_Version = 5;
ITW_CLASH_Mode = 0;
ITW_CLASH_ObserverEnabled = false;
ITW_CLASH_ObserverStarted = false;
ITW_CLASH_LiveEnabled = false;
ITW_CLASH_LiveStarted = false;
ITW_CLASH_HALReady = false;
ITW_CLASH_PilotFailed = false;
ITW_CLASH_CommanderWatchdogStarted = false;
ITW_CLASH_Transitioning = false;
ITW_CLASH_RegistrationFrozenUntil = 0;
ITW_CLASH_MaxManagedGroups = 12;
ITW_CLASH_MaxManagedPerObjective = 4;
ITW_CLASH_HALLeader = objNull;
ITW_CLASH_HALHQ = grpNull;
ITW_CLASH_HALObjectives = [];
ITW_CLASH_LastMirroredZone = -1;
ITW_CLASH_LastHeldObjectives = [];
ITW_CLASH_LastObjectiveSignature = "";
ITW_CLASH_LastDoctrineSignature = "";
ITW_CLASH_LastAllocationSignature = "";
ITW_CLASH_LastAnchorSignature = "";
ITW_CLASH_AllocationDriftMargin = 150;
ITW_CLASH_AllocationDriftCooldown = 60;
ITW_CLASH_MinAnchorSoldiers = 6;
ITW_CLASH_AnchorAuditGrace = 75;
ITW_CLASH_AnchorOrderCooldown = 60;
ITW_CLASH_AnchorRefillGrace = 120;
ITW_CLASH_AnchorAuditReadyAt = 1e10;
ITW_CLASH_ReserveRatio = 0.20;
ITW_CLASH_CommanderObjective = -1;
ITW_CLASH_ManagedGroups = [];
ITW_CLASH_AnchorGroups = createHashMap;
ITW_CLASH_AnchorRefills = createHashMap;
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

ITW_CLASH_fnc_IsCommanderGroup = {
    params ["_group"];
    !isNull _group && {
        _group isEqualTo ITW_CLASH_HALHQ || {
            _group getVariable ["ITW_CLASH_Commander",false]
        }
    }
};

ITW_CLASH_fnc_IsConscious = {
    params ["_unit"];
    if (isNull _unit || {!alive _unit}) exitWith {false};
#if __has_include("\z\ace\addons\main\script_component.hpp")
    !(_unit getVariable ["ACE_isUnconscious",false])
#else
    lifeState _unit in ["HEALTHY","INJURED"]
#endif
};

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

ITW_CLASH_fnc_ApplyObjectiveDoctrine = {
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {false};

    private _activeCount = count ITW_CLASH_HALObjectives;
    private _heldCount = count (missionNamespace getVariable ["RydHQ_Taken",[]]);
    private _recovering = _activeCount > _heldCount;
    private _order = if (_recovering) then {"ATTACK"} else {"DEFEND"};
    private _previousOrder = missionNamespace getVariable ["RydHQ_Order",""];
    private _anchors = [];
    {
        private _entry = ITW_CLASH_AnchorGroups getOrDefault [_x,[]];
        if (_entry isNotEqualTo []) then {
            private _group = _entry#0;
            if (!isNull _group && {
                _group getVariable ["ITW_CLASH_Managed",false] && {
                    !(_group getVariable ["ITW_CLASH_Releasing",false])
                }
            }) then {
                _anchors pushBackUnique _group;
            };
        };
    } forEach +(keys ITW_CLASH_AnchorGroups);

    if (_order isEqualTo "ATTACK" && {_previousOrder isNotEqualTo "ATTACK"}) then {
        private _detached = [];
        {
            if (!isNull _x && {
                !(_x in _anchors) && {
                    _x getVariable ["Defending",false]
                }
            }) then {
                _x setVariable ["Defending",false];
                [_x] call ITW_CLASH_fnc_ClearGroupWaypoints;
                _detached pushBack ([_x] call ITW_CLASH_fnc_GroupId);
            };
        } forEach +ITW_CLASH_ManagedGroups;
        if (!isNull ITW_CLASH_HALHQ) then {
            {
                ITW_CLASH_HALHQ setVariable [
                    _x,
                    (ITW_CLASH_HALHQ getVariable [_x,[]]) select {_x in _anchors}
                ];
            } forEach ["RydHQ_DefSpot","RydHQ_Def","RydHQ_DefRes","RydHQ_RecDefSpot"];
        };
        ["recovery-start",[
            ITW_ZoneIndex,
            ITW_CLASH_LastHeldObjectives,
            _activeCount,
            _detached
        ]] call ITW_CLASH_fnc_Log;
    };

    RydHQ_Order = _order;
    RydHQ_Berserk = false;
    RydHQ_AttackAlways = false;
    RydHQ_IdleDef = true;
    RydHQ_DefendObjectives = 1;
    RydHQ_CRDefRes = ITW_CLASH_ReserveRatio;
    RydHQ_NoDef = [];
    RydHQ_NoAttack = +_anchors;
    RydHQ_NoRecon = +_anchors;
    RydHQ_MAtt = true;
    RydHQ_Personality = "COMPETENT";
    RydHQ_Recklessness = 0.5;
    RydHQ_Consistency = 0.5;
    RydHQ_Activity = 0.5;
    RydHQ_Reflex = 0.5;
    RydHQ_Circumspection = 0.5;
    RydHQ_Fineness = 0.5;

    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_Order",_order];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Berserk",false];
        ITW_CLASH_HALHQ setVariable ["RydHQ_AttackAlways",false];
        ITW_CLASH_HALHQ setVariable ["RydHQ_IdleDef",true];
        ITW_CLASH_HALHQ setVariable ["RydHQ_DefendObjectives",1];
        ITW_CLASH_HALHQ setVariable ["RydHQ_CRDefRes",ITW_CLASH_ReserveRatio];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoDef",[]];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoAttack",+_anchors];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoRecon",+_anchors];
        ITW_CLASH_HALHQ setVariable ["RydHQ_MAtt",true];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Personality","COMPETENT"];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Recklessness",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Consistency",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Activity",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Reflex",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Circumspection",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Fineness",0.5];
    };

    private _signature = str [
        RydHQ_Order,
        RydHQ_Berserk,
        RydHQ_IdleDef,
        RydHQ_DefendObjectives,
        count RydHQ_NoDef,
        count RydHQ_NoAttack,
        RydHQ_CRDefRes,
        RydHQ_Personality,
        _recovering,
        _heldCount,
        _activeCount
    ];
    if (_signature != ITW_CLASH_LastDoctrineSignature) then {
        ITW_CLASH_LastDoctrineSignature = _signature;
        ["doctrine",[
            _order,
            RydHQ_IdleDef,
            RydHQ_DefendObjectives,
            count RydHQ_NoDef,
            count RydHQ_NoAttack,
            RydHQ_CRDefRes,
            RydHQ_Personality,
            _recovering,
            _heldCount,
            _activeCount
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_SyncHALIncluded = {
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {[]};

    ITW_CLASH_ManagedGroups = ITW_CLASH_ManagedGroups select {
        !isNull _x && {
            !([_x] call ITW_CLASH_fnc_IsCommanderGroup) && {
                count units _x > 0 && {
                    _x getVariable ["ITW_CLASH_Managed",false]
                }
            }
        }
    };

    RydHQ_Included = +ITW_CLASH_ManagedGroups;
    RydHQ_NoDef = [];
    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_Included",+ITW_CLASH_ManagedGroups];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoDef",[]];
    };
    call ITW_CLASH_fnc_ApplyObjectiveDoctrine;
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
    private _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    private _heldIndices = _heldObjectives apply {_x#0};
    private _previousHeld = if (_zoneChanged) then {[]} else {
        +ITW_CLASH_LastHeldObjectives
    };
    private _lostObjectives = if (_zoneChanged) then {[]} else {
        _previousHeld - _heldIndices
    };
    private _recoveredObjectives = if (_zoneChanged) then {[]} else {
        _heldIndices - _previousHeld
    };

    {
        private _key = [_x] call ITW_CLASH_fnc_AnchorKey;
        [_x,"objective-lost"] call ITW_CLASH_fnc_ClearAnchorSlot;
        private _refill = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
        if (_refill isNotEqualTo []) then {
            ITW_CLASH_AnchorRefills deleteAt _key;
            ["anchor-refill-cancelled",[
                _x,
                _refill#0,
                "objective-lost"
            ]] call ITW_CLASH_fnc_Log;
        };
    } forEach _lostObjectives;
    ITW_CLASH_LastHeldObjectives = +_heldIndices;
    private _commanderObjective = [_heldObjectives] call ITW_CLASH_fnc_SyncCommanderObjective;

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
    call ITW_CLASH_fnc_ApplyObjectiveDoctrine;

    if (_lostObjectives isNotEqualTo [] || {
        _recoveredObjectives isNotEqualTo []
    }) then {
        ["objective-ownership",[
            ITW_ZoneIndex,
            _lostObjectives,
            _recoveredObjectives,
            _heldIndices
        ]] call ITW_CLASH_fnc_Log;
    };

    ITW_CLASH_LastMirroredZone = ITW_ZoneIndex;
    private _signature = str [
        ITW_ZoneIndex,
        _mirrors apply {str _x},
        _taken apply {str _x},
        _commanderObjective
    ];
    if (_signature != ITW_CLASH_LastObjectiveSignature) then {
        ITW_CLASH_LastObjectiveSignature = _signature;
        ["objective-mirror",[
            ITW_ZoneIndex,
            ITW_Zones#ITW_ZoneIndex,
            _heldObjectives apply {_x#0},
            _commanderObjective
        ]] call ITW_CLASH_fnc_Log;
    };
    !(_mirrors isEqualTo [])
};

ITW_CLASH_fnc_ClearAnchorSlot = {
    params [["_objectiveIndex",-1],["_reason","unspecified"]];
    private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
    private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
    if (_entry isEqualTo []) exitWith {false};

    private _group = _entry#0;
    private _id = _entry#1;
    if (!isNull _group) then {
        _group setVariable ["ITW_CLASH_AnchorObjective",nil];
        _group setVariable ["ITW_CLASH_AnchorAssignedAt",nil];
        _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
        if (!isNull ITW_CLASH_HALHQ) then {
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_DefSpot",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_DefSpot",[]]) - [_group]
            ];
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_Def",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_Def",[]]) - [_group]
            ];
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_DefRes",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_DefRes",[]]) - [_group]
            ];
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_RecDefSpot",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_RecDefSpot",[]]) - [_group]
            ];
        };
        if (_reason isEqualTo "promoted-replacement") then {
            _group setVariable ["Break",true];
            _group setVariable ["Defending",false];
        };
        if (_reason isEqualTo "objective-lost") then {
            _group setVariable ["Defending",false];
            [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
        };
    };
    ITW_CLASH_AnchorGroups deleteAt _key;
    ["anchor-vacant",[
        _objectiveIndex,
        _id,
        _reason,
        if (isNull _group) then {0} else {
            [units _group] call ITW_CLASH_fnc_CountConscious
        }
    ]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_ResetAnchors = {
    params [["_reason","reset"]];
    private _count = 0;
    {
        private _entry = ITW_CLASH_AnchorGroups get _x;
        if (_entry isNotEqualTo []) then {
            private _group = _entry#0;
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_AnchorObjective",nil];
                _group setVariable ["ITW_CLASH_AnchorAssignedAt",nil];
                _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
            };
            _count = _count + 1;
        };
    } forEach +(keys ITW_CLASH_AnchorGroups);

    ITW_CLASH_AnchorGroups = createHashMap;
    ITW_CLASH_AnchorRefills = createHashMap;
    RydHQ_NoAttack = [];
    RydHQ_NoRecon = [];
    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoAttack",[]];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoRecon",[]];
    };
    ITW_CLASH_LastAnchorSignature = "";
    ITW_CLASH_AnchorAuditReadyAt = time + 45;
    ["anchor-reset",[_reason,_count]] call ITW_CLASH_fnc_Log;
    _count
};

ITW_CLASH_fnc_SelectAnchorGroup = {
    params ["_objectiveIndex","_flag","_radius"];
    if (isNull _flag) exitWith {grpNull};

    private _center = [_objectiveIndex,_flag] call ITW_CLASH_fnc_GetObjectiveCenter;
    private _bestStrong = grpNull;
    private _bestStrongScore = 1e10;
    private _bestWeak = grpNull;
    private _bestWeakScore = 1e10;

    {
        private _group = _x;
        if (!isNull _group && {
            _group getVariable ["ITW_CLASH_Managed",false] && {
                !(_group getVariable ["ITW_CLASH_Releasing",false]) && {
                    (_group getVariable ["ITW_CLASH_AssignedObjective",-1]) == _objectiveIndex
                }
            }
        }) then {
            private _otherAnchor = _group getVariable ["ITW_CLASH_AnchorObjective",-1];
            if (_otherAnchor in [-1,_objectiveIndex]) then {
                private _aliveCount = [units _group] call ITW_CLASH_fnc_CountConscious;
                if (_aliveCount > 0) then {
                    private _insideCount = [
                        units _group,
                        _center,
                        _radius
                    ] call ITW_CLASH_fnc_CountConscious;
                    private _distance = leader _group distance2D _flag;

                    if (_aliveCount >= ITW_CLASH_MinAnchorSoldiers) then {
                        private _score = if (_insideCount >= ITW_CLASH_MinAnchorSoldiers) then {
                            _distance
                        } else {
                            100000 + _distance
                        };
                        if (_score < _bestStrongScore) then {
                            _bestStrongScore = _score;
                            _bestStrong = _group;
                        };
                    } else {
                        private _score = (
                            (ITW_CLASH_MinAnchorSoldiers - _aliveCount) * 100000
                        ) + _distance - (_insideCount * 1000);
                        if (_score < _bestWeakScore) then {
                            _bestWeakScore = _score;
                            _bestWeak = _group;
                        };
                    };
                };
            };
        };
    } forEach +ITW_CLASH_ManagedGroups;

    if (!isNull _bestStrong) exitWith {_bestStrong};
    _bestWeak
};

ITW_CLASH_fnc_OrderAnchor = {
    params ["_group","_objectiveIndex","_flag","_radius"];
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            !ITW_CLASH_HALReady || {
                isNull _group || {isNull _flag}
            }
        }
    }) exitWith {false};
    if (isNil "HAL_GoDef" || {isNil "RYD_Spawn"}) exitWith {
        ["anchor-order-unavailable",[
            _objectiveIndex,
            [_group] call ITW_CLASH_fnc_GroupId
        ]] call ITW_CLASH_fnc_Log;
        false
    };
    if (_group getVariable ["ITW_CLASH_AnchorOrderPending",false]) exitWith {false};

    private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
    private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
    if (_entry isEqualTo [] || {!((_entry#0) isEqualTo _group)}) exitWith {false};

    private _center = [_objectiveIndex,_flag] call ITW_CLASH_fnc_GetObjectiveCenter;
    private _safeRadius = 20 max (_radius - 35);
    private _target = [
        _center,
        10,
        _safeRadius,
        2,
        0,
        0.4,
        0,
        [],
        [_center,_center]
    ] call BIS_fnc_findSafePos;
    if (surfaceIsWater _target) then {
        _target = +_center;
    };

    _entry set [3,time];
    ITW_CLASH_AnchorGroups set [_key,_entry];
    _group setVariable ["ITW_CLASH_AnchorOrderPending",true];
    ["anchor-order-requested",[
        _objectiveIndex,
        _entry#1,
        round (leader _group distance2D _flag),
        _target
    ]] call ITW_CLASH_fnc_Log;

    [_group,_objectiveIndex,_target] spawn {
        params ["_group","_objectiveIndex","_target"];
        if (isNull _group) exitWith {};

        _group setVariable ["Break",true];
        _group setVariable ["Defending",false];
        if (!isNull ITW_CLASH_HALHQ) then {
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_DefSpot",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_DefSpot",[]]) - [_group]
            ];
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_Def",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_Def",[]]) - [_group]
            ];
        };

        sleep 6;
        if (isNull _group || {
            !ITW_CLASH_LiveEnabled || {
                !ITW_CLASH_HALReady || {
                    !(_group getVariable ["ITW_CLASH_Managed",false]) || {
                        (_group getVariable ["ITW_CLASH_AnchorObjective",-1]) != _objectiveIndex
                    }
                }
            }
        }) exitWith {
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
            };
        };

        _group setVariable ["Break",false];
        _group setVariable ["Defending",false];
        private _defSpot = ITW_CLASH_HALHQ getVariable ["RydHQ_DefSpot",[]];
        _defSpot pushBackUnique _group;
        ITW_CLASH_HALHQ setVariable ["RydHQ_DefSpot",_defSpot];

        private _angle = ITW_CLASH_HALHQ getVariable ["RydHQ_Angle",0];
        [[
            _group,
            _target,
            0,
            0,
            false,
            _angle,
            ITW_CLASH_HALHQ
        ],HAL_GoDef] call RYD_Spawn;

        _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
        ["anchor-order-issued",[
            _objectiveIndex,
            [_group] call ITW_CLASH_fnc_GroupId,
            _target
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_RequestAnchorRefill = {
    params ["_objectiveIndex",["_reason","anchor-deficit"],["_deficit",1]];
    if (!isServer || {!ITW_CLASH_LiveEnabled} || {!ITW_CLASH_HALReady}) exitWith {false};

    private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
    private _entry = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
    if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "assigned"}) then {
        private _group = _entry#1;
        if (!isNull _group && {
            ([units _group] call ITW_CLASH_fnc_CountConscious) > 0 && {
                time - (_entry#2) < ITW_CLASH_AnchorRefillGrace
            }
        }) exitWith {false};
        ["anchor-refill-retry",[
            _objectiveIndex,
            if (isNull _group) then {"<null>"} else {
                [_group] call ITW_CLASH_fnc_GroupId
            },
            time - (_entry#2)
        ]] call ITW_CLASH_fnc_Log;
        _entry = [];
    };
    if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "pending"}) exitWith {false};

    ITW_CLASH_AnchorRefills set [
        _key,
        ["pending",grpNull,time,_reason,_deficit]
    ];
    ["anchor-deficit",[
        _objectiveIndex,
        _reason,
        _deficit,
        ITW_CLASH_MinAnchorSoldiers
    ]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_NextAnchorRefill = {
    if (!isServer || {!ITW_CLASH_LiveEnabled} || {!ITW_CLASH_HALReady}) exitWith {-1};

    private _nextObjective = -1;
    {
        private _objectiveIndex = _x#0;
        private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
        private _entry = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
        if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "pending"}) exitWith {
            _nextObjective = _objectiveIndex;
        };
    } forEach (call ITW_CLASH_fnc_GetHeldObjectives);
    _nextObjective
};

ITW_CLASH_fnc_AcknowledgeAnchorRefill = {
    params ["_group","_objectiveIndex"];
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            isNull _group || {_objectiveIndex < 0}
        }
    }) exitWith {false};

    private _held = call ITW_CLASH_fnc_GetHeldObjectives;
    if ((_held findIf {(_x#0) == _objectiveIndex}) < 0) exitWith {false};

    private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
    private _entry = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
    if (_entry isEqualTo [] || {!((_entry#0) isEqualTo "pending")}) exitWith {false};

    _group setVariable ["ITW_CLASH_RefillObjective",_objectiveIndex];
    ITW_CLASH_AnchorRefills set [
        _key,
        ["assigned",_group,time,_entry#3,_entry#4]
    ];
    ["anchor-refill-assigned",[
        _objectiveIndex,
        [_group] call ITW_CLASH_fnc_GroupId,
        count units _group
    ]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_AuditAnchors = {
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            !ITW_CLASH_HALReady || {
                ITW_CLASH_Transitioning || {
                    time < ITW_CLASH_AnchorAuditReadyAt || {
                        time < ITW_CLASH_RegistrationFrozenUntil
                    }
                }
            }
        }
    }) exitWith {[]};

    private _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    private _heldKeys = _heldObjectives apply {
        [_x#0] call ITW_CLASH_fnc_AnchorKey
    };

    {
        if !(_x in _heldKeys) then {
            private _objectiveIndex = parseNumber _x;
            [_objectiveIndex,"objective-not-held"] call ITW_CLASH_fnc_ClearAnchorSlot;
        };
    } forEach +(keys ITW_CLASH_AnchorGroups);
    {
        if !(_x in _heldKeys) then {
            ITW_CLASH_AnchorRefills deleteAt _x;
        };
    } forEach +(keys ITW_CLASH_AnchorRefills);

    private _coverage = [];
    private _enemyCoverageUnits = (units ITW_EnemySide) select {
        !([group _x] call ITW_CLASH_fnc_IsCommanderGroup)
    };
    {
        _x params ["_objectiveIndex","_flag"];
        private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
        private _radius = [_objectiveIndex] call ITW_CLASH_fnc_GetObjectiveRadius;
        private _center = [_objectiveIndex,_flag] call ITW_CLASH_fnc_GetObjectiveCenter;
        private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
        private _anchor = if (_entry isEqualTo []) then {grpNull} else {_entry#0};

        private _anchorValid = !isNull _anchor && {
            _anchor getVariable ["ITW_CLASH_Managed",false] && {
                !(_anchor getVariable ["ITW_CLASH_Releasing",false]) && {
                    (_anchor getVariable ["ITW_CLASH_AssignedObjective",-1]) == _objectiveIndex && {
                        ([units _anchor] call ITW_CLASH_fnc_CountConscious) > 0
                    }
                }
            }
        };
        if (!_anchorValid && {_entry isNotEqualTo []}) then {
            [_objectiveIndex,"dead-or-ineligible"] call ITW_CLASH_fnc_ClearAnchorSlot;
            _entry = [];
            _anchor = grpNull;
        };

        private _anchorAlive = if (isNull _anchor) then {0} else {
            [units _anchor] call ITW_CLASH_fnc_CountConscious
        };
        private _anchorInside = if (isNull _anchor) then {0} else {
            [units _anchor,_center,_radius] call ITW_CLASH_fnc_CountConscious
        };

        if (isNull _anchor || {
            _anchorAlive < ITW_CLASH_MinAnchorSoldiers || {
                _anchorInside < ITW_CLASH_MinAnchorSoldiers
            }
        }) then {
            private _candidate = [
                _objectiveIndex,
                _flag,
                _radius
            ] call ITW_CLASH_fnc_SelectAnchorGroup;
            private _candidateAlive = if (isNull _candidate) then {0} else {
                [units _candidate] call ITW_CLASH_fnc_CountConscious
            };
            private _candidateInside = if (isNull _candidate) then {0} else {
                [units _candidate,_center,_radius] call ITW_CLASH_fnc_CountConscious
            };

            if (!isNull _candidate && {
                !(_candidate isEqualTo _anchor) && {
                    isNull _anchor || {
                        _candidateAlive >= ITW_CLASH_MinAnchorSoldiers && {
                            _anchorAlive < ITW_CLASH_MinAnchorSoldiers || {
                                _candidateInside >= ITW_CLASH_MinAnchorSoldiers && {
                                    _anchorInside < ITW_CLASH_MinAnchorSoldiers
                                }
                            }
                        }
                    }
                }
            }) then {
                if (!isNull _anchor) then {
                    [_objectiveIndex,"promoted-replacement"] call ITW_CLASH_fnc_ClearAnchorSlot;
                };

                private _id = [_candidate] call ITW_CLASH_fnc_GroupId;
                _candidate setVariable ["ITW_CLASH_AnchorObjective",_objectiveIndex];
                _candidate setVariable ["ITW_CLASH_AnchorAssignedAt",time];
                ITW_CLASH_AnchorGroups set [
                    _key,
                    [_candidate,_id,time,-1000]
                ];
                ["anchor-promoted",[
                    _objectiveIndex,
                    _id,
                    _candidateAlive,
                    _candidateInside,
                    round (leader _candidate distance2D _flag)
                ]] call ITW_CLASH_fnc_Log;

                _entry = ITW_CLASH_AnchorGroups get _key;
                _anchor = _candidate;
                _anchorAlive = _candidateAlive;
                _anchorInside = _candidateInside;
            };
        };

        if (!isNull _anchor && {
            _anchorInside < ITW_CLASH_MinAnchorSoldiers
        }) then {
            private _lastOrder = _entry#3;
            if (time - _lastOrder >= ITW_CLASH_AnchorOrderCooldown) then {
                [
                    _anchor,
                    _objectiveIndex,
                    _flag,
                    _radius
                ] call ITW_CLASH_fnc_OrderAnchor;
                _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,_entry];
            };
        };

        private _totalEnemyInside = [
            _enemyCoverageUnits,
            _center,
            _radius
        ] call ITW_CLASH_fnc_CountConscious;
        private _state = "UNCOVERED";

        if (_anchorInside >= ITW_CLASH_MinAnchorSoldiers) then {
            _state = "COVERED";
        } else {
            if (isNull _anchor) then {
                _state = "VACANT";
            } else {
                if (_anchorAlive < ITW_CLASH_MinAnchorSoldiers) then {
                    _state = "DEGRADED";
                } else {
                    _state = "MOVING";
                };
            };
        };

        if (_state isEqualTo "COVERED") then {
            private _refill = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
            if (_refill isNotEqualTo []) then {
                ITW_CLASH_AnchorRefills deleteAt _key;
                ["anchor-refill-satisfied",[
                    _objectiveIndex,
                    _state,
                    _anchorInside,
                    _totalEnemyInside
                ]] call ITW_CLASH_fnc_Log;
            };
        } else {
            private _assignedAt = if (_entry isEqualTo []) then {0} else {_entry#2};
            if (isNull _anchor || {
                _anchorAlive < ITW_CLASH_MinAnchorSoldiers || {
                    time - _assignedAt >= ITW_CLASH_AnchorAuditGrace
                }
            }) then {
                [
                    _objectiveIndex,
                    toLowerANSI _state,
                    ITW_CLASH_MinAnchorSoldiers - _anchorInside
                ] call ITW_CLASH_fnc_RequestAnchorRefill;
            };
        };

        private _refill = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
        private _refillState = if (_refill isEqualTo []) then {"none"} else {_refill#0};
        _coverage pushBack [
            _objectiveIndex,
            round _radius,
            if (_entry isEqualTo []) then {"<none>"} else {_entry#1},
            _anchorAlive,
            _anchorInside,
            _totalEnemyInside,
            _state,
            _refillState
        ];
    } forEach _heldObjectives;

    private _signature = str [
        ITW_ZoneIndex,
        _coverage apply {
            [_x#0,_x#2,_x#3,_x#4,_x#5,_x#6,_x#7]
        }
    ];
    if (_signature != ITW_CLASH_LastAnchorSignature) then {
        ITW_CLASH_LastAnchorSignature = _signature;
        ["anchor-coverage",[ITW_ZoneIndex,_coverage]] call ITW_CLASH_fnc_Log;
    };
    _coverage
};

ITW_CLASH_fnc_AuditAllocations = {
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            !ITW_CLASH_HALReady || {
                ITW_CLASH_Transitioning
            }
        }
    }) exitWith {[]};

    private _activeObjectives = call ITW_CLASH_fnc_GetActiveObjectives;
    private _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    private _heldIndices = _heldObjectives apply {_x#0};
    private _allocations = [];
    private _drifted = [];

    {
        private _group = _x;
        if (!isNull _group && {
            _group getVariable ["ITW_CLASH_Managed",false]
        }) then {
            private _id = [_group] call ITW_CLASH_fnc_GroupId;
            private _assignedObjective = _group getVariable [
                "ITW_CLASH_AssignedObjective",
                VAR_GET_OBJ_IDX(_group)
            ];
            private _assignedFlag = [_assignedObjective] call ITW_CLASH_fnc_GetObjectiveFlag;
            private _waypointIndex = currentWaypoint _group;
            private _waypointCount = count waypoints _group;
            private _hasWaypoint = _waypointCount > 0 && {
                _waypointIndex >= 0 && {_waypointIndex < _waypointCount}
            };
            private _waypointPosition = getPosATL (leader _group);
            private _waypointType = "";
            if (_hasWaypoint) then {
                _waypointPosition = waypointPosition [_group,_waypointIndex];
                _waypointType = waypointType [_group,_waypointIndex];
            };

            private _nearestObjective = -1;
            private _nearestDistance = 1e10;
            {
                _x params ["_objectiveIndex","_flag"];
                private _distance = _waypointPosition distance2D _flag;
                if (_distance < _nearestDistance) then {
                    _nearestObjective = _objectiveIndex;
                    _nearestDistance = _distance;
                };
            } forEach _activeObjectives;

            private _assignedDistance = if (isNull _assignedFlag) then {
                1e10
            } else {
                _waypointPosition distance2D _assignedFlag
            };
            private _state = if (_group getVariable ["Defending",false]) then {
                "defending"
            } else {
                if (_group getVariable ["Busy" + str _group,false]) then {
                    "busy"
                } else {
                    "awaiting-order"
                }
            };

            private _role = if (
                (_group getVariable ["ITW_CLASH_AnchorObjective",-1]) == _assignedObjective
            ) then {
                "anchor"
            } else {
                if (!isNull ITW_CLASH_HALHQ && {
                    _group in (ITW_CLASH_HALHQ getVariable ["RydHQ_DefRes",[]])
                }) then {
                    "reserve"
                } else {
                    "main"
                }
            };

            private _entry = [
                _id,
                _assignedObjective,
                _state,
                _nearestObjective,
                _waypointType,
                round _assignedDistance,
                round _nearestDistance,
                _role
            ];
            _allocations pushBack _entry;

            if (_state isEqualTo "defending" && {
                _hasWaypoint && {
                    _nearestObjective >= 0 && {
                        _nearestObjective != _assignedObjective && {
                            _nearestDistance + ITW_CLASH_AllocationDriftMargin < _assignedDistance
                        }
                    }
                }
            }) then {
                _drifted pushBack [_group,_entry];
            };
        };
    } forEach +ITW_CLASH_ManagedGroups;

    private _coverage = [];
    {
        private _objectiveIndex = _x#0;
        _coverage pushBack [
            _objectiveIndex,
            if (_objectiveIndex in _heldIndices) then {"held"} else {"recovery"},
            {
                !isNull _x && {
                    (_x getVariable ["ITW_CLASH_AssignedObjective",-1]) == _objectiveIndex
                }
            } count ITW_CLASH_ManagedGroups,
            {
                (_x#3) == _objectiveIndex
            } count _allocations
        ];
    } forEach _activeObjectives;

    private _signature = str [
        ITW_ZoneIndex,
        _coverage,
        _allocations apply {[_x#0,_x#1,_x#2,_x#3,_x#4,_x#7]}
    ];
    if (_signature != ITW_CLASH_LastAllocationSignature) then {
        ITW_CLASH_LastAllocationSignature = _signature;
        ["objective-allocation",[ITW_ZoneIndex,_coverage,_allocations]] call ITW_CLASH_fnc_Log;
    };

    {
        _x params ["_group","_entry"];
        _group setVariable [
            "ITW_CLASH_ReeligibleAt",
            time + ITW_CLASH_AllocationDriftCooldown
        ];
        ["allocation-drift",_entry] call ITW_CLASH_fnc_Log;
        [_group,"objective-allocation-drift"] call ITW_CLASH_fnc_ReleaseGroup;
    } forEach _drifted;

    _allocations
};

ITW_CLASH_fnc_RegisterGroup = {
    params ["_group",["_source","reconcile"],["_allowBeforeReady",false]];
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {false};
    if (!ITW_CLASH_HALReady && {!_allowBeforeReady}) exitWith {false};
    if (isNull _group || {!local _group}) exitWith {false};
    if ([_group] call ITW_CLASH_fnc_IsCommanderGroup) exitWith {false};
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

    private _isAnchorRefill = (
        _group getVariable ["ITW_CLASH_RefillObjective",-1]
    ) == _objectiveIndex;
    if (_isAnchorRefill && {
        count ITW_CLASH_ManagedGroups >= ITW_CLASH_MaxManagedGroups || {
            _sameObjectiveCount >= ITW_CLASH_MaxManagedPerObjective
        }
    }) then {
        private _victim = grpNull;
        private _victimSize = 1e10;

        {
            private _candidate = _x;
            if (!isNull _candidate && {
                (_candidate getVariable ["ITW_CLASH_AssignedObjective",-1]) == _objectiveIndex && {
                    (_candidate getVariable ["ITW_CLASH_AnchorObjective",-1]) < 0 && {
                        (_candidate getVariable ["ITW_CLASH_RefillObjective",-1]) < 0 && {
                            !(_candidate getVariable ["ITW_CLASH_Releasing",false])
                        }
                    }
                }
            }) then {
                private _candidateSize = [
                    units _candidate
                ] call ITW_CLASH_fnc_CountConscious;
                if (_candidateSize < _victimSize) then {
                    _victim = _candidate;
                    _victimSize = _candidateSize;
                };
            };
        } forEach +ITW_CLASH_ManagedGroups;

        if (isNull _victim && {
            count ITW_CLASH_ManagedGroups >= ITW_CLASH_MaxManagedGroups
        }) then {
            {
                private _candidate = _x;
                private _candidateObjective = _candidate getVariable [
                    "ITW_CLASH_AssignedObjective",
                    -1
                ];
                private _objectiveCount = {
                    !isNull _x && {
                        (_x getVariable ["ITW_CLASH_AssignedObjective",-1]) == _candidateObjective
                    }
                } count ITW_CLASH_ManagedGroups;
                if (!isNull _candidate && {
                    _objectiveCount > 1 && {
                        (_candidate getVariable ["ITW_CLASH_AnchorObjective",-1]) < 0 && {
                            (_candidate getVariable ["ITW_CLASH_RefillObjective",-1]) < 0 && {
                                !(_candidate getVariable ["ITW_CLASH_Releasing",false])
                            }
                        }
                    }
                }) then {
                    private _candidateSize = [
                        units _candidate
                    ] call ITW_CLASH_fnc_CountConscious;
                    if (_candidateSize < _victimSize) then {
                        _victim = _candidate;
                        _victimSize = _candidateSize;
                    };
                };
            } forEach +ITW_CLASH_ManagedGroups;
        };

        if (!isNull _victim) then {
            ["anchor-capacity-reclaim",[
                _objectiveIndex,
                [_victim] call ITW_CLASH_fnc_GroupId,
                _victimSize,
                [_group] call ITW_CLASH_fnc_GroupId
            ]] call ITW_CLASH_fnc_Log;
            [_victim,"anchor-refill-capacity"] call ITW_CLASH_fnc_ReleaseGroup;
            _sameObjectiveCount = {
                !isNull _x && {
                    (_x getVariable ["ITW_CLASH_Managed",false]) && {
                        VAR_GET_OBJ_IDX(_x) == _objectiveIndex
                    }
                }
            } count ITW_CLASH_ManagedGroups;
        };
    };

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
    _group setVariable ["ITW_CLASH_AssignedObjective",_objectiveIndex];
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
    private _anchorObjective = _group getVariable ["ITW_CLASH_AnchorObjective",-1];
    if (_anchorObjective >= 0) then {
        private _key = [_anchorObjective] call ITW_CLASH_fnc_AnchorKey;
        private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
        if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo _group}) then {
            [
                _anchorObjective,
                format ["release:%1",_reason]
            ] call ITW_CLASH_fnc_ClearAnchorSlot;
        };
    };
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
    _group setVariable ["ITW_CLASH_AssignedObjective",nil];
    _group setVariable ["ITW_CLASH_AnchorObjective",nil];
    _group setVariable ["ITW_CLASH_AnchorAssignedAt",nil];
    _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
    _group setVariable ["ITW_CLASH_RefillObjective",nil];
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
    ["pilot-failed",[_reason,_details,_released]] call ITW_CLASH_fnc_Log;
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
            ITW_CLASH_ReserveRatio
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
