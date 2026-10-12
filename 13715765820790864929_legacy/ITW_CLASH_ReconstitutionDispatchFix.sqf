#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ReconstitutionDispatchFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_ReconstitutionDispatchFixReady",false]
};
ITW_CLASH_ReconstitutionDispatchFixStarted = true;
ITW_CLASH_ReconstitutionDispatchFixVersion = 7;
ITW_CLASH_ReconstitutionDispatchFixReady = false;

// Resolve the exact active objective's attack-source forward FOB. Prefer the
// symmetric generation resolver when it resolves the requested objective; keep
// a direct Impasse-graph fallback so reconstitution remains fail-open while the
// later Checkbook/ForceGeneration layer is still binding.
ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn = {
    params [["_objectiveIndex",-1],["_side",sideUnknown]];
    if (_objectiveIndex < 0 || {isNil "ITW_Objectives"} || {
        _objectiveIndex >= count ITW_Objectives
    }) exitWith {[]};
    if (_side == sideUnknown) then {
        _side = missionNamespace getVariable ["ITW_EnemySide",east]
    };

    private _reference = +((ITW_Objectives#_objectiveIndex)#ITW_OBJ_POS);
    if (!isNil "ITW_CLASH_Generation_fnc_Resolve") then {
        private _resolved = [
            _side,"RECONSTITUTION","FORWARD",_reference
        ] call ITW_CLASH_Generation_fnc_Resolve;
        if (_resolved isEqualType createHashMap && {
            (_resolved getOrDefault ["status",""]) == "RESOLVED" && {
                (_resolved getOrDefault ["objective",-1]) == _objectiveIndex
            }
        }) exitWith {
            [
                +(_resolved get "origin"),
                _objectiveIndex,
                "reconstitution-forward-fob-" + (_resolved getOrDefault ["source","generation"]),
                _resolved getOrDefault ["forwardBase",-1]
            ]
        };
    };

    if (isNil "ITW_Bases" || {isNil "ITW_PlayerSide"} || {isNil "ITW_EnemySide"}) exitWith {[]};
    private _friendly = _side == ITW_PlayerSide;
    private _slot = if (_friendly) then {ITW_ATTACK_LAND_F} else {ITW_ATTACK_LAND_E};
    private _attacks = (ITW_Objectives#_objectiveIndex)#ITW_OBJ_ATTACKS;
    if (_slot < 0 || {_slot >= count _attacks}) exitWith {[]};
    private _baseIndex = _attacks#_slot;
    if (_baseIndex < 0 || {_baseIndex >= count ITW_Bases}) exitWith {[]};

    private _position = +(ITW_Bases#_baseIndex#ITW_BASE_A_SPAWN);
    private _source = "reconstitution-forward-fob-ai-spawn";
    if (_position isEqualTo [] && {_baseIndex < count ITW_Objectives}) then {
        _position = +(ITW_Objectives#_baseIndex#ITW_OBJ_V_SPAWN);
        _source = "reconstitution-forward-fob-vehicle-spawn";
    };
    if (_position isEqualTo []) then {
        _position = +(ITW_Bases#_baseIndex#ITW_BASE_POS);
        _source = "reconstitution-forward-fob-base-position";
    };
    if (_position isEqualTo []) exitWith {[]};
    if (count _position < 3) then {_position pushBack 0};
    [_position,_objectiveIndex,_source,_baseIndex]
};

/*
    v7: the replacement squad is handed to its commander where it is born.

    Run of 2026-10-11 20:23, mission 2. Two replacement lifts flew, one a side,
    and neither squad was ever handed over:

        RC1 (BLUFOR, for objective 8)   flown to objective 23, 6.7 km away,
                                        dropped 20:59:20, no order to 21:07
        RC2 (enemy, for objective 8)    dropped 21:02:54, 590 m out, waiting on
                                        "physical-dismount" to 21:07

    "reconstitution-transit-arrived" appears 0 times in that log. The lift is a
    third kind of lift, between Impasse and HAL, with a handoff at each end and
    one in the middle, and each of the three had its own fault (the fallback
    below and ITW_CLASH_ReconstitutionTransitFix.sqf v6 say which).

    Every other squad either side fields is given to its commander at the base
    it spawns at and HAL decides where it goes and whether it flies. The
    handoff a replacement squad gets at the end of its lift is the same one:
    ITW_CLASH_fnc_AcknowledgeReconstitution stamps lineage, archetype and the
    objective it was raised for, registers the group, and writes no waypoint
    and no order. So it is called here, once the squad stands at the forward
    FOB, on both sides.

    If the commander takes the squad the dedicated lift is never bought. If he
    does not (HAL is not up, the bridge is frozen for a zone change, the enemy
    roster is full) the squad goes down the transit path exactly as before.
*/
ITW_CLASH_ReconstitutionSpawnHandoff = missionNamespace getVariable [
    "ITW_CLASH_ReconstitutionSpawnHandoff",true
];

ITW_CLASH_Reconstitution_fnc_SpawnHandoff = {
    params [
        "_group","_requestId","_objectiveIndex","_archetype","_lineage",["_queuedAt",0]
    ];
    if (!ITW_CLASH_ReconstitutionSpawnHandoff) exitWith {false};
    if (isNull _group || {isNil "ITW_CLASH_fnc_AcknowledgeReconstitution"}) exitWith {false};
    if (_objectiveIndex < 0 || {isNil "ITW_Objectives"} || {
        _objectiveIndex >= count ITW_Objectives
    }) exitWith {false};

    // Both commanders refuse a group that Impasse still marks as being built.
    // The transit manager clears the mark at its own handoff for that reason.
    _group setVariable ["itwInitGrp",nil,true];
    VAR_SET_OBJ_IDX(_group,_objectiveIndex);

    private _accepted = [
        _group,_requestId,_objectiveIndex,_archetype,_lineage,_queuedAt
    ] call ITW_CLASH_fnc_AcknowledgeReconstitution;
    if (isNil "_accepted") then {_accepted = false};

    private _friendly = !isNil "ITW_PlayerSide" && {side _group == ITW_PlayerSide};
    private _distance = round (
        leader _group distance2D ((ITW_Objectives#_objectiveIndex)#ITW_OBJ_POS)
    );

    if (!_accepted) exitWith {
        // Back to what the transit path expects to find.
        _group setVariable ["itwInitGrp",true,true];
        if (!isNil "ITW_CLASH_fnc_Log") then {
            ["reconstitution-spawn-handoff-refused",[
                _requestId,_lineage,_objectiveIndex,side _group,
                {alive _x} count units _group,_distance,
                missionNamespace getVariable ["ITW_CLASH_HALReady",false],
                missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]
            ]] call ITW_CLASH_fnc_Log;
        };
        false
    };

    // Same closing step the transit manager's handoff takes for the enemy.
    if (
        !_friendly
        && {!isNil "ITW_EnemySide"}
        && {side _group == ITW_EnemySide}
        && {!isNil "ITW_EnemyGroupCallback"}
    ) then {
        [_group] call ITW_EnemyGroupCallback
    };

    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["reconstitution-spawn-handoff",[
            _requestId,_lineage,_objectiveIndex,side _group,
            {alive _x} count units _group,_distance,
            _group getVariable ["ITW_CLASH_ReconstitutionSupportBase",-1],
            _group getVariable ["ITW_CLASH_ReconstitutionSpawnSource",""]
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

// Reconstituted combat squads are born at the forward FOB, not the logistics
// corridor. From v7 the commander is offered the squad there. Only a squad he
// does not take remains in transit, and that one is not handed back to HAL
// until the existing transit manager observes its physical return to the AO.
if (isNil "ITW_AtkBeginReconstitutionTransit") exitWith {
    diag_log "CLASH BOOT | FAILED | reconstitution-origin-fix-source-missing";
    false
};

ITW_AtkBeginReconstitutionTransit = {
    params [
        "_group","_requestId","_objectiveIndex","_archetype","_lineage",["_queuedAt",0]
    ];
    if (!isServer || {isNull _group}) exitWith {false};

    private _forward = [
        _objectiveIndex,side _group
    ] call ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn;
    if (_forward isNotEqualTo []) then {
        _forward params ["_forwardPos","_forwardObjective","_spawnSource","_baseIndex"];
        private _members = units _group select {alive _x};
        {
            private _offset = _forwardPos getPos [2 + random 10,random 360];
            _offset set [2,0];
            _x setPosATL _offset;
        } forEach _members;
        _group setVariable ["ITW_CLASH_ReconstitutionSupportBase",_baseIndex];
        _group setVariable ["ITW_CLASH_ReconstitutionSpawnSource",_spawnSource];
        if (!isNil "ITW_CLASH_fnc_Log") then {
            ["reconstitution-forward-fob-spawn",[
                _requestId,_lineage,_objectiveIndex,_baseIndex,_spawnSource,
                count _members,+_forwardPos
            ]] call ITW_CLASH_fnc_Log;
        };
    };

    if ([
        _group,_requestId,_objectiveIndex,_archetype,_lineage,_queuedAt
    ] call ITW_CLASH_Reconstitution_fnc_SpawnHandoff) exitWith {true};

    _group setVariable ["ITW_CLASH_ReconstitutionTransit",true];
    _group setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];
    _group setVariable ["ITW_CLASH_TransitState","waiting-transport"];
    _group setVariable ["ITW_CLASH_ReconstitutionRequest",_requestId];
    _group setVariable ["ITW_CLASH_Archetype",+_archetype];
    _group setVariable ["ITW_CLASH_Lineage",_lineage];
    _group setVariable ["itwInitGrp",true,true];

    ITW_AtkReconstitutionTransits pushBack [
        _group,_requestId,_objectiveIndex,+_archetype,_lineage,_queuedAt,time,-1000,"waiting-transport"
    ];

    if (!ITW_AtkReconstitutionTransitManagerStarted) then {
        ITW_AtkReconstitutionTransitManagerStarted = true;
        0 spawn ITW_AtkReconstitutionTransitManager;
    };

    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["reconstitution-transit-queued",[
            _requestId,_lineage,_objectiveIndex,count _archetype,
            _group getVariable ["ITW_CLASH_ReconstitutionSupportBase",-1],
            _group getVariable ["ITW_CLASH_ReconstitutionSpawnSource",""]
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

// This file is compiled synchronously from preInit immediately after
// ITW_Attack.sqf. preInit defers these two SKL finalizers, so the canonical
// definitions exist but remain mutable here.
if (isNil "ITW_AtkDispatchReconstitutionTransport") exitWith {
    diag_log "CLASH BOOT | FAILED | reconstitution-dispatch-fix-source-missing";
    false
};

ITW_AtkDispatchReconstitutionTransport = {
    params ["_group","_requestId","_objectiveIndex","_lineage"];
    if (!isServer || {isNull _group}) exitWith {false};
    private _context = [];
    if (!isNil "ITW_AtkReconstitutionTransportContexts") then {
        _context = ITW_AtkReconstitutionTransportContexts getOrDefault [
            toUpperANSI str (side _group),[]
        ];
    };
    if (_context isEqualTo []) then {
        _context = missionNamespace getVariable [
            "ITW_AtkReconstitutionTransportContext",[]
        ];
    };
    if (_context isEqualTo []) exitWith {false};

    _context params [
        "_transport","_dualVeh","_crewTypes","_unitTypes","_side"
    ];
    if (side _group != _side) exitWith {false};

    private _forward = [
        _objectiveIndex,side _group
    ] call ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn;
    if (_forward isEqualTo []) exitWith {false};
    private _baseIndex = _forward#3;
    private _spawnPt = +(_forward#0);
    private _spawnSource = _forward#2;

    if (_baseIndex >= 0 && {_baseIndex < count ITW_Objectives}) then {
        private _vehicleSpawn = +(ITW_Objectives#_baseIndex#ITW_OBJ_V_SPAWN);
        if (_vehicleSpawn isNotEqualTo []) then {
            _spawnPt = _vehicleSpawn;
            _spawnSource = _spawnSource + "-vehicle-staging";
        };
    };
    if (count _spawnPt < 3) then {_spawnPt pushBack 0};

    private _members = units _group select {alive _x};
    if (_members isEqualTo []) exitWith {false};
    private _requiredSeats = count _members;

    private _candidates = (_transport + _dualVeh) select {
        private _vehDef = _x;
        private _type = _vehDef#ITW_VEH_TYPE;
        _type != ITW_TYPE_VEH_SHIP && {
            (_vehDef#ITW_VEH_REQD_TICKETS) <= (_vehDef#ITW_VEH_CURR_TICKETS) && {
                (_vehDef#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT || {
                    (_vehDef#ITW_VEH_COUNT) < (_vehDef#ITW_VEH_MAX)
                }
            }
        }
    };
    if (_candidates isEqualTo []) exitWith {false};

    private _routeDistance = _spawnPt distance2D ((ITW_Objectives#_objectiveIndex)#ITW_OBJ_POS);
    private _preferAir = _routeDistance > 2500;
    private _preferred = _candidates select {
        private _type = _x#ITW_VEH_TYPE;
        if (_preferAir) then {ITW_VEH_IS_AIR(_type)} else {ITW_VEH_IS_LAND(_type)}
    };
    private _fallback = _candidates - _preferred;
    _preferred = [_preferred,[],{
        _x#ITW_VEH_REQD_TICKETS
    },"ASCEND"] call BIS_fnc_sortBy;
    _fallback = [_fallback,[],{
        _x#ITW_VEH_REQD_TICKETS
    },"ASCEND"] call BIS_fnc_sortBy;
    private _ordered = _preferred + _fallback;

    private _dispatched = false;
    for "_candidateIndex" from 0 to ((count _ordered) - 1) do {
        if (_dispatched) then {continue};

        private _vehDef = _ordered#_candidateIndex;
        private _veh = [_vehDef,_crewTypes,_unitTypes,_side,_spawnPt] call ITW_AtkSpawnVeh;
        if (isNull _veh) then {continue};

        private _crewGroup = group driver _veh;
        private _availableSeats = _veh emptyPositions "";
        // This lift is born at the forward FOB: rear-echelon vehicles (IFVs
        // and anything that can kill a tank) must path there instead.
        private _rearEchelon = !isNil "ITW_CLASH_DualHAL_fnc_IsRearEchelon" && {
            [_veh,"reconstitution-lift"] call ITW_CLASH_DualHAL_fnc_IsRearEchelon
        };
        if (_availableSeats < _requiredSeats || {_rearEchelon}) then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
            continue;
        };

        private _loaded = true;
        {
            if !(_x moveInAny _veh) then {_loaded = false};
        } forEach _members;
        if (!_loaded || {_members findIf {vehicle _x != _veh} >= 0}) then {
            {
                if (vehicle _x == _veh) then {
                    unassignVehicle _x;
                    moveOut _x;
                };
            } forEach _members;
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
            continue;
        };

        _group setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];
        _group setVariable ["ITW_CLASH_TransitVehicle",_veh];
        _group setVariable ["ITW_CLASH_TransitState","transport"];
        _group setVariable ["ITW_CLASH_ReconstitutionSupportBase",_baseIndex];
        _group setVariable ["ITW_CLASH_ReconstitutionSpawnSource",_spawnSource];
        _crewGroup setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];
        _crewGroup setVariable ["ITW_CLASH_CapExempt",true];

        // While replacement infantry is physically aboard, keep this vehicle
        // under Impasse's transit manager. The generic Dual-HAL handoff would
        // otherwise interpret it as idle transport, unload the squad, and turn
        // it into standing HAL cargo before the reconstitution trip begins.
        _veh setVariable ["ITW_CLASH_ReconstitutionTransport",true,true];

        // v7: and it stays Impasse's for the rest of its life. The flag above
        // is dropped when the squad is out, and from that moment the Dual-HAL
        // migration took the empty aircraft out of ITW_ManagedVehs, two
        // seconds before Impasse would have sent it home. HAL had no order for
        // it and nothing else returns a carrier that never flew a HAL lift:
        // Bravo 2-4 hovered at Impasse's last waypoint from 21:00:09 to the end
        // of the log, in the enemy commander's known contacts throughout. This
        // mark is never cleared. ShouldSuppressImpasseVehicleWriter reads it,
        // so Impasse's vehicle manager flies the empty lift back to where it
        // started and deletes it there.
        _veh setVariable ["ITW_CLASH_ReconstitutionLift",true,true];

        private _vehInfo = [
            _vehDef#ITW_VEH_TYPE,
            _vehDef#ITW_VEH_ROLE,
            _veh,
            _crewGroup,
            [_group],
            getPosATL _veh,
            _vehDef#ITW_VEH_IS_DUAL_AS_TRANSPORT
        ];
        [_vehInfo,false,false] call ITW_AtkAddVehicle;

        ITW_TICKET_SEM_CHECK;
        ITW_VEH_COUNT_INCR(_vehDef);
        _veh setVariable ["ITW_VehDef",_vehDef];
        ITW_TICKET_SEM_CHECK;
        ITW_TICKET_REDUCE(_vehDef);

        private _hcIDs = allPlayers select {_x isKindOf "HeadlessClient_F"} apply {owner _x};
        _hcIDs pushBack 2;
        [_veh] remoteExec ["ITW_AtkUnloadProtect",_hcIDs];
        {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;
        if (
            !isNil "ITW_EnemySide"
            && {side _crewGroup == ITW_EnemySide}
            && {!isNil "ITW_EnemyGroupCallback"}
        ) then {
            [_crewGroup] call ITW_EnemyGroupCallback
        };

        if (!isNil "ITW_CLASH_fnc_Log") then {
            ["reconstitution-transport-dispatched",[
                _requestId,_lineage,_objectiveIndex,_baseIndex,_spawnSource,
                typeOf _veh,_requiredSeats,_vehDef#ITW_VEH_TYPE,round _routeDistance,
                if (_preferAir) then {"air-preferred"} else {"land-preferred"}
            ]] call ITW_CLASH_fnc_Log;
        };
        _dispatched = true;
    };

    private _vehicle = _group getVariable ["ITW_CLASH_TransitVehicle",objNull];
    private _state = _group getVariable ["ITW_CLASH_TransitState",""];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["reconstitution-dispatch-return",[
            _requestId,_lineage,_objectiveIndex,_dispatched,_state,
            if (isNull _vehicle) then {""} else {typeOf _vehicle}
        ]] call ITW_CLASH_fnc_Log;
    };
    _dispatched
};

isNil {
    private _deferred = missionNamespace getVariable ["ITW_CLASH_DeferredFinalizers",[]];
    _deferred = _deferred - [
        "ITW_AtkBeginReconstitutionTransit",
        "ITW_AtkDispatchReconstitutionTransport"
    ];
    missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];
};

private _beginFinalized = ["ITW_AtkBeginReconstitutionTransit"] call SKL_fnc_CompileFinal;
private _dispatchFinalized = ["ITW_AtkDispatchReconstitutionTransport"] call SKL_fnc_CompileFinal;
private _finalized = _beginFinalized && _dispatchFinalized;
ITW_CLASH_ReconstitutionDispatchFixReady = _finalized;
if (_finalized) then {
    diag_log format [
        "CLASH BOOT | reconstitution-dispatch-fix-ready | version=%1 forwardFOB=true origin=true transport=true sideContexts=true capExemptCrew=true lifecycleReserved=true costEfficientLiftOrder=true preInit=true spawnHandoff=%2 liftReturnsToImpasse=true",
        ITW_CLASH_ReconstitutionDispatchFixVersion,
        ITW_CLASH_ReconstitutionSpawnHandoff
    ];
} else {
    diag_log format [
        "CLASH BOOT | FAILED | reconstitution-dispatch-fix-finalization | begin=%1 dispatch=%2",
        _beginFinalized,_dispatchFinalized
    ];
};
_finalized