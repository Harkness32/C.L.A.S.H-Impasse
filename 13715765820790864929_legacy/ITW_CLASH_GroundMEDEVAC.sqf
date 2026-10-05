#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_GroundMEDEVAC_Started",false]) exitWith {};
ITW_CLASH_GroundMEDEVAC_Started = true;
ITW_CLASH_GroundMEDEVAC_Version = 3;

// Ground MEDEVAC is a middle-tier extraction: safer/cheaper geography gets a
// road vehicle, long/air-only withdrawals remain CASEVAC candidates, and squads
// within the final 400 m of the rear destination continue walking.
ITW_CLASH_GroundMEDEVAC_MaxConcurrent = 2;
ITW_CLASH_GroundMEDEVAC_MinWithdrawalTime = 60;
ITW_CLASH_GroundMEDEVAC_MinDisengageDistance = 500;
ITW_CLASH_GroundMEDEVAC_EnemyClearance = 700;
ITW_CLASH_GroundMEDEVAC_InboundAbortClearance = 500;
ITW_CLASH_GroundMEDEVAC_ObjectiveClearance = 500;
ITW_CLASH_GroundMEDEVAC_MinEgressDistance = 400;
ITW_CLASH_GroundMEDEVAC_MaxPreferredEgressDistance = 3500;
ITW_CLASH_GroundMEDEVAC_PickupLeadDistance = 150;
ITW_CLASH_GroundMEDEVAC_RoadSearchRadius = 250;
ITW_CLASH_GroundMEDEVAC_RallyOffset = 30;
ITW_CLASH_GroundMEDEVAC_InboundTimeout = 240;
ITW_CLASH_GroundMEDEVAC_BoardingTimeout = 90;
ITW_CLASH_GroundMEDEVAC_RTBTimeout = 300;
ITW_CLASH_GroundMEDEVAC_RetryCooldown = 120;
ITW_CLASH_GroundMEDEVAC_AirFallbackDelay = 30;
ITW_CLASH_GroundMEDEVAC_Active = createHashMap;

// CASEVAC loads asynchronously in init.sqf. Wait until its shared safety helpers
// and eligibility function exist, then install ground/air arbitration before a
// withdrawal can ever satisfy the 60-second disengagement gate.
waitUntil {
    sleep 0.1;
    !isNil "ITW_CLASH_CASEVAC_fnc_Eligible" && {
        !isNil "ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance" && {
            !isNil "ITW_CLASH_CASEVAC_fnc_GetObjectiveClearance"
        }
    }
};

ITW_CLASH_GroundMEDEVAC_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["medevac-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_GroundMEDEVAC_fnc_GetGroundSpawn = {
    params [["_objectiveIndex",-1],["_side",sideUnknown]];
    if (_side == sideUnknown) then {
        _side = missionNamespace getVariable ["ITW_EnemySide",east];
    };

    private _resolved = [];
    if (!isNil "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn") then {
        _resolved = [
            _objectiveIndex,_side
        ] call ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn;
    };

    if (_resolved isEqualTo []) then {
        // Legacy OPFOR fallback while the symmetric generation graph is binding.
        if (
            isNil "ITW_CLASH_fnc_GetSupportCorridorSpawn"
            || {!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}}
        ) exitWith {[]};
        _resolved = [_objectiveIndex] call ITW_CLASH_fnc_GetSupportCorridorSpawn;
    };
    if (_resolved isEqualTo []) exitWith {[]};
    _resolved params ["_spawnPos","_ignoredObjective","_source","_baseIndex"];

    if (_spawnPos isEqualTo [] || {surfaceIsWater _spawnPos}) exitWith {[]};

    private _spawn = +_spawnPos;
    if (_baseIndex >= 0 && {
        !isNil "ITW_Objectives" && {_baseIndex < count ITW_Objectives}
    }) then {
        private _vehicleSpawn = +(ITW_Objectives#_baseIndex#ITW_OBJ_V_SPAWN);
        if (_vehicleSpawn isNotEqualTo [] && {!surfaceIsWater _vehicleSpawn}) then {
            _spawn = _vehicleSpawn;
            _source = _source + "-vehicle-staging";
        };
    };
    if (count _spawn < 3) then {_spawn pushBack 0};
    [_spawn,_baseIndex,_source]
};

ITW_CLASH_GroundMEDEVAC_fnc_FindRoadPickup = {
    params ["_group","_destination"];
    if (isNull _group || {_destination isEqualTo []}) exitWith {[]};

    private _origin = getPosATL leader _group;
    private _direction = _origin getDir _destination;
    private _candidate = _origin getPos [
        ITW_CLASH_GroundMEDEVAC_PickupLeadDistance,
        _direction
    ];

    private _roads = _candidate nearRoads ITW_CLASH_GroundMEDEVAC_RoadSearchRadius;
    if (_roads isEqualTo []) then {
        _roads = _origin nearRoads ITW_CLASH_GroundMEDEVAC_RoadSearchRadius;
    };
    if (_roads isEqualTo []) exitWith {[]};

    private _road = [_roads,_candidate] call BIS_fnc_nearestPosition;
    if (isNull _road) exitWith {[]};
    private _pickup = getPosATL _road;
    if (count _pickup < 3) then {_pickup pushBack 0};
    _pickup set [2,0];
    if (surfaceIsWater _pickup) exitWith {[]};

    private _groupSide = side _group;
    private _hostileNearPickup = allUnits findIf {
        alive _x && {
            (_groupSide getFriend (side _x)) < 0.6 && {
                _x distance2D _pickup < (ITW_CLASH_GroundMEDEVAC_EnemyClearance - 100)
            }
        }
    };
    if (_hostileNearPickup >= 0) exitWith {[]};

    // Keep infantry out of the road/vehicle collision box. Rally on the squad
    // side of the pickup, then physically board only after the vehicle stops.
    private _rallySeed = _pickup getPos [
        ITW_CLASH_GroundMEDEVAC_RallyOffset,
        _pickup getDir _origin
    ];
    private _rally = [
        _rallySeed,0,25,2,0,0.5,0,[],[_rallySeed,_rallySeed]
    ] call BIS_fnc_findSafePos;
    if (_rally isEqualTo [] || {_rally isEqualTo [0,0]}) then {_rally = +_rallySeed};
    if (count _rally < 3) then {_rally pushBack 0};
    _rally set [2,0];
    if (surfaceIsWater _rally) exitWith {[]};

    [_pickup,_rally,_road]
};

ITW_CLASH_GroundMEDEVAC_fnc_GetRoadReturnPoint = {
    params ["_returnPos"];
    if (_returnPos isEqualTo []) exitWith {[]};
    private _roads = _returnPos nearRoads 120;
    if (_roads isEqualTo []) exitWith {+_returnPos};
    private _road = [_roads,_returnPos] call BIS_fnc_nearestPosition;
    if (isNull _road) exitWith {+_returnPos};
    private _roadPos = getPosATL _road;
    if (_roadPos distance2D _returnPos > 140) exitWith {+_returnPos};
    if (count _roadPos < 3) then {_roadPos pushBack 0};
    _roadPos set [2,0];
    _roadPos
};

ITW_CLASH_GroundMEDEVAC_fnc_IsMedicalVehDef = {
    params ["_vehDef"];
    private _medical = false;
    {
        private _class = if (_x isEqualType []) then {
            if (_x isEqualTo []) then {""} else {_x#0}
        } else {_x};
        if !(_class isEqualType "") then {continue};
        private _name = toLowerANSI (
            _class + " " + getText (configFile >> "CfgVehicles" >> _class >> "displayName")
        );
        if ((_name find "ambulance") >= 0 || {
            (_name find "medical") >= 0 || {(_name find "medevac") >= 0}
        }) exitWith {_medical = true};
    } forEach (_vehDef#ITW_VEH_CLASSES);
    _medical
};

ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle = {
    params ["_seatCount","_spawnInfo",["_recoverySide",sideUnknown]];
    if (_spawnInfo isEqualTo []) exitWith {[]};
    if (_recoverySide == sideUnknown) then {
        _recoverySide = missionNamespace getVariable ["ITW_EnemySide",east];
    };

    private _context = [];
    if (!isNil "ITW_AtkReconstitutionTransportContexts") then {
        _context = ITW_AtkReconstitutionTransportContexts getOrDefault [
            toUpperANSI str _recoverySide,[]
        ];
    };
    if (_context isEqualTo []) then {
        _context = missionNamespace getVariable [
            "ITW_AtkReconstitutionTransportContext",[]
        ];
    };
    if (_context isEqualTo []) exitWith {[]};

    _context params [
        "_transport","_dualVeh","_crewTypes","_unitTypes","_side"
    ];
    if (_side != _recoverySide) exitWith {[]};

    // Emergency ground evacuation may exceed Impasse's normal concurrent
    // vehicle ceiling, just like CASEVAC. Tickets remain mandatory and counts
    // are still incremented so accounting remains truthful.
    private _candidates = (_transport + _dualVeh) select {
        (_x#ITW_VEH_TYPE) in [ITW_TYPE_VEH_CAR,ITW_TYPE_VEH_APC] && {
            (_x#ITW_VEH_REQD_TICKETS) <= (_x#ITW_VEH_CURR_TICKETS)
        }
    };
    if (_candidates isEqualTo []) exitWith {[]};

    private _medical = _candidates select {[_x] call ITW_CLASH_GroundMEDEVAC_fnc_IsMedicalVehDef};
    private _pureCars = (_candidates select {
        (_x#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT && {(_x#ITW_VEH_TYPE) == ITW_TYPE_VEH_CAR}
    }) - _medical;
    private _pureAPCs = (_candidates select {
        (_x#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT && {(_x#ITW_VEH_TYPE) == ITW_TYPE_VEH_APC}
    }) - _medical;
    private _dualCars = (_candidates select {
        (_x#ITW_VEH_ROLE) != ITW_VEH_ROLE_TRANSPORT && {(_x#ITW_VEH_TYPE) == ITW_TYPE_VEH_CAR}
    }) - _medical;
    private _dualAPCs = (_candidates select {
        (_x#ITW_VEH_ROLE) != ITW_VEH_ROLE_TRANSPORT && {(_x#ITW_VEH_TYPE) == ITW_TYPE_VEH_APC}
    }) - _medical;
    private _ordered = _medical + _pureCars + _pureAPCs + _dualCars + _dualAPCs;

    _spawnInfo params ["_spawnPos","_baseIndex","_spawnSource"];
    private _result = [];
    for "_candidateIndex" from 0 to ((count _ordered) - 1) do {
        if (_result isNotEqualTo []) then {continue};
        private _vehDef = _ordered#_candidateIndex;
        private _countBefore = _vehDef#ITW_VEH_COUNT;
        private _maxConfigured = _vehDef#ITW_VEH_MAX;
        private _bypassingCountCap = _countBefore >= _maxConfigured;

        private _veh = [
            _vehDef,_crewTypes,_unitTypes,_side,_spawnPos
        ] call ITW_AtkSpawnVeh;
        if (isNull _veh) then {continue};

        private _crewGroup = group driver _veh;
        if !(_veh isKindOf "LandVehicle") then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
            continue;
        };
        if ((_veh emptyPositions "cargo") < _seatCount) then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
            continue;
        };

        ITW_TICKET_SEM_CHECK;
        ITW_VEH_COUNT_INCR(_vehDef);
        _veh setVariable ["ITW_VehDef",_vehDef];
        ITW_TICKET_SEM_CHECK;
        ITW_TICKET_REDUCE(_vehDef);

        _veh setVariable ["ITW_CLASH_GroundMEDEVAC",true,true];
        _crewGroup setVariable ["ITW_CLASH_GroundMEDEVAC",true];
        _crewGroup setVariable ["noHeadless",true];
        _crewGroup setVariable ["itwInitGrp",true,true];
        _crewGroup allowFleeing 0;
        _crewGroup enableAttack false;
        _crewGroup setBehaviourStrong "CARELESS";
        _crewGroup setCombatMode "BLUE";
        _crewGroup setSpeedMode "FULL";
        _veh forceFollowRoad true;
        _veh limitSpeed 90;

        if (!isNil "ITW_AtkVehRemoveMagazines") then {
            [_veh] remoteExec ["ITW_AtkVehRemoveMagazines",_veh];
        };
        ALLOW_DAMAGE(_veh,true);
        {ALLOW_DAMAGE(_x,true)} forEach crew _veh;
        {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;

        if (_bypassingCountCap) then {
            ["cap-bypass",[
                typeOf _veh,_countBefore,_maxConfigured,_seatCount
            ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
        };

        _result = [_veh,_crewGroup,_vehDef,_baseIndex,_spawnSource,+_spawnPos];
    };

    if (_result isNotEqualTo []) then {
        ["spawn-selected",[
            typeOf (_result#0),_baseIndex,_spawnSource,_seatCount,
            [(_result#2)] call ITW_CLASH_GroundMEDEVAC_fnc_IsMedicalVehDef
        ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
    };
    _result
};

ITW_CLASH_GroundMEDEVAC_fnc_OrderVehicle = {
    params ["_veh","_crewGroup","_position",["_completion",25]];
    if (isNull _veh || {!alive _veh} || {isNull _crewGroup} || {_position isEqualTo []}) exitWith {false};
    {deleteWaypoint _x} forEachReversed waypoints _crewGroup;
    _crewGroup enableAttack false;
    _crewGroup setBehaviourStrong "CARELESS";
    _crewGroup setCombatMode "BLUE";
    _crewGroup setSpeedMode "FULL";
    _veh limitSpeed 90;
    private _wp = _crewGroup addWaypoint [_position,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius _completion;

    // Pickup uses doStop on the driver while survivors board. A new vehicle leg
    // must explicitly replace that individual stop order; a group waypoint alone
    // does not reliably release it in hosted Arma sessions.
    private _driver = driver _veh;
    if (!isNull _driver) then {
        _driver doMove _position;
    };
    true
};

ITW_CLASH_GroundMEDEVAC_fnc_OrderRally = {
    params ["_group","_rally"];
    if (isNull _group || {_rally isEqualTo []}) exitWith {false};
    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group enableAttack false;
    _group setCombatMode "BLUE";
    _group setBehaviourStrong "AWARE";
    _group setSpeedMode "FULL";
    private _wp = _group addWaypoint [_rally,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 15;
    true
};

private _extractionPath = "ITW_CLASH_GroundMEDEVAC_Extraction.sqf";
private _managerPath = "ITW_CLASH_GroundMEDEVAC_Manager.sqf";
if (!fileExists _extractionPath || {!fileExists _managerPath}) exitWith {
    ITW_CLASH_GroundMEDEVAC_Started = false;
    diag_log "CLASH BOOT | FAILED | ground-medevac-module-missing | CASEVAC/walking remain active";
};

private _extractionLoaded = call compile preprocessFileLineNumbers _extractionPath;
if !(_extractionLoaded isEqualTo true) exitWith {
    ITW_CLASH_GroundMEDEVAC_Started = false;
    diag_log "CLASH BOOT | FAILED | ground-medevac-extraction-load | CASEVAC/walking remain active";
};
private _managerLoaded = call compile preprocessFileLineNumbers _managerPath;
if !(_managerLoaded isEqualTo true) exitWith {
    ITW_CLASH_GroundMEDEVAC_Started = false;
    diag_log "CLASH BOOT | FAILED | ground-medevac-manager-load | CASEVAC/walking remain active";
};

diag_log format [
    "CLASH BOOT | ground-medevac-ready | version=%1 max=%2 range=%3-%4 disengage=%5 enemyClear=%6 rallyOffset=%7 capBypass=true tickets=true",
    ITW_CLASH_GroundMEDEVAC_Version,
    ITW_CLASH_GroundMEDEVAC_MaxConcurrent,
    ITW_CLASH_GroundMEDEVAC_MinEgressDistance,
    ITW_CLASH_GroundMEDEVAC_MaxPreferredEgressDistance,
    ITW_CLASH_GroundMEDEVAC_MinDisengageDistance,
    ITW_CLASH_GroundMEDEVAC_EnemyClearance,
    ITW_CLASH_GroundMEDEVAC_RallyOffset
];
