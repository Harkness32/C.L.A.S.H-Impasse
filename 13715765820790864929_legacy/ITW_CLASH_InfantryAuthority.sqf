#include "defines.hpp"

if (!isServer) exitWith {false};
ITW_CLASH_InfantryAuthorityVersion = 4;

/*
    Persistent infantry authority doctrine

    HAL owns tactical behavior for every server-local, fielded enemy infantry
    formation. Impasse still owns force generation, transport, economy, campaign
    state and explicit lifecycle handoffs. C.L.A.S.H. translates those boundaries;
    objective allocation is affinity metadata, never tactical ownership.

    Explicit non-HAL states remain:
      - spawn/delivery transition
      - player/headless ownership
      - transport embarkation / managed vehicle cargo
      - objective reset / zone transition bridge freeze
      - non-infantry formations
      - recovery after successful physical boarding (handled by GTFO)
*/

// Retire the pilot admission ceiling. Keep the legacy variables valid because
// RegisterGroup telemetry and old code still read them, but make them unreachable
// as practical limits rather than growing a second registration implementation.
ITW_CLASH_MaxManagedGroups = 1e9;
ITW_CLASH_MaxManagedPerObjective = 1e9;

// Objective-waypoint drift is no longer a release condition. HAL may maneuver a
// formation away from its Impasse affinity; the affinity changes when Impasse
// reallocates it, while tactical ownership remains HAL's.
ITW_CLASH_AllocationDriftMargin = 1e9;
ITW_CLASH_AllocationDriftCooldown = 0;

ITW_CLASH_fnc_ClassifyGroup_InfantryAuthorityBase = ITW_CLASH_fnc_ClassifyGroup;
ITW_CLASH_fnc_ApplyObjectiveDoctrine_InfantryAuthorityBase = ITW_CLASH_fnc_ApplyObjectiveDoctrine;
ITW_CLASH_fnc_ObserveWriter_InfantryAuthorityBase = ITW_CLASH_fnc_ObserveWriter;
ITW_CLASH_fnc_ObserveLifecycle_InfantryAuthorityBase = ITW_CLASH_fnc_ObserveLifecycle;

ITW_CLASH_InfantryAuthority_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["infantry-authority-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_InfantryAuthority_fnc_IsHardHandoff = {
    params ["_group"];
    if (isNull _group) exitWith {[true,"null-group",[]]};
    if ([_group] call ITW_CLASH_fnc_IsCommanderGroup) exitWith {[true,"clash-commander",[]]};
    if (isNil "ITW_EnemySide") exitWith {[true,"side-not-ready",[]]};
    if (side _group != ITW_EnemySide) exitWith {[true,"not-opfor",[side _group]]};

    private _members = units _group;
    private _alive = _members select {alive _x};
    if (_alive isEqualTo []) exitWith {[true,"dead-or-empty",[count _members]]};
    if (_alive findIf {isPlayer _x} >= 0) exitWith {[true,"player-group",[]]};
    if (!local _group) exitWith {[true,"headless-or-remote",[groupOwner _group]]};

    if (_group getVariable ["itwInitGrp",false]) exitWith {[true,"spawn-transition",[]]};
    if (_group getVariable ["itwDelivery",false]) exitWith {[true,"delivery",[]]};
    if (_group getVariable ["VarWaitingTransport",false]) exitWith {[true,"awaiting-transport",[]]};

    private _getInState = _group getVariable ["ITW_getInState",-1];
    if (_getInState != -1) exitWith {[true,"transport-transition",[_getInState]]};
    if (_group getVariable ["ITW_OkayToReset",false]) exitWith {[true,"objective-reset",[]]};
    if (missionNamespace getVariable ["ITW_ObjZonesUpdating",false]) exitWith {[true,"zone-transition",[]]};
    if (ITW_CLASH_Transitioning || {time < ITW_CLASH_RegistrationFrozenUntil}) exitWith {
        [true,"bridge-frozen",[ITW_CLASH_RegistrationFrozenUntil - time]]
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
    if (_managedVehicleIndex >= 0) exitWith {
        [true,"vehicle-managed",[_managedVehicleIndex]]
    };
    if (assignedVehicles _group isNotEqualTo []) exitWith {[true,"assigned-vehicle",[]]};
    if (_alive findIf {vehicle _x != _x} >= 0) exitWith {[true,"vehicle-or-cargo",[]]};
    if (_alive findIf {!(_x isKindOf "CAManBase")} >= 0) exitWith {[true,"not-infantry",[]]};

    [false,"fielded-infantry",[
        count _alive,
        VAR_GET_OBJ_IDX(_group),
        groupOwner _group,
        _group getVariable ["ITW_Garrison",false]
    ]]
};

ITW_CLASH_InfantryAuthority_fnc_IsManagedFielded = {
    params ["_group"];
    if (isNull _group || {!(_group getVariable ["ITW_CLASH_Managed",false])}) exitWith {false};
    private _handoff = [_group] call ITW_CLASH_InfantryAuthority_fnc_IsHardHandoff;
    !(_handoff#0)
};

ITW_CLASH_fnc_ClassifyGroup = {
    params ["_group"];

    // Preserve GTFO's explicit HAL-owned exception verbatim. Recovery releases
    // happen after boarding and therefore never reach this path as managed GTFO.
    if (!isNull _group && {
        _group getVariable ["ITW_CLASH_GTFO",false] && {
            _group getVariable ["ITW_CLASH_Managed",false]
        }
    }) exitWith {
        [_group] call ITW_CLASH_fnc_ClassifyGroup_InfantryAuthorityBase
    };

    private _handoff = [_group] call ITW_CLASH_InfantryAuthority_fnc_IsHardHandoff;
    if (_handoff#0) exitWith {[false,_handoff#1,_handoff#2]};

    private _objectiveIndex = VAR_GET_OBJ_IDX(_group);
    private _assigned = _group getVariable ["ITW_CLASH_AssignedObjective",-1];

    // Reallocation is a strategic-affinity update, not a HAL release. Only adopt
    // non-negative Impasse objective metadata; an unassigned frame never erases
    // a previously useful affinity while the squad is already fielded.
    if (_group getVariable ["ITW_CLASH_Managed",false] && {
        _objectiveIndex >= 0 && {_objectiveIndex != _assigned}
    }) then {
        _group setVariable ["ITW_CLASH_AssignedObjective",_objectiveIndex];
        ["affinity-updated",[
            [_group] call ITW_CLASH_fnc_GroupId,
            _assigned,
            _objectiveIndex
        ]] call ITW_CLASH_InfantryAuthority_fnc_Log;
    };

    [true,"fielded-infantry",[
        {alive _x} count units _group,
        _objectiveIndex,
        groupOwner _group,
        _group getVariable ["ITW_Garrison",false]
    ]]
};

ITW_CLASH_fnc_ObserveWriter = {
    params ["_writer","_group"];

    // These are tactical Impasse writers. Once a formation is physically fielded
    // and HAL-managed, they must back off rather than release HAL ownership merely
    // to replace movement or garrison orders. The small-group merge path is left
    // to the baseline observer because that source group immediately ceases to exist.
    private _tacticalWriters = [
        "engage-infantry",
        "stuck-handler",
        "infantry-manager-garrison",
        "infantry-manager-waypoints",
        "infantry-manager-move-up",
        "infantry-move-up"
    ];

    if (_writer in _tacticalWriters && {
        [_group] call ITW_CLASH_InfantryAuthority_fnc_IsManagedFielded
    }) exitWith {
        private _id = [_group] call ITW_CLASH_fnc_GroupId;
        private _shouldLog = true;
        if (!isNil "ITW_CLASH_ObserverWriterLast") then {
            private _key = format ["%1|persistent-authority|%2",_id,_writer];
            private _last = ITW_CLASH_ObserverWriterLast getOrDefault [_key,-1000];
            _shouldLog = time - _last >= 10;
            if (_shouldLog) then {ITW_CLASH_ObserverWriterLast set [_key,time]};
        };
        if (_shouldLog) then {
            ["writer-suppressed",[
                _id,
                _writer,
                _group getVariable ["ITW_CLASH_AssignedObjective",-1],
                VAR_GET_OBJ_IDX(_group),
                {alive _x} count units _group
            ]] call ITW_CLASH_InfantryAuthority_fnc_Log;
        };
        true
    };

    [_writer,_group] call ITW_CLASH_fnc_ObserveWriter_InfantryAuthorityBase
};

ITW_CLASH_fnc_ObserveLifecycle = {
    params ["_event",["_details",[]]];

    // Defend phase is a campaign phase change, not a temporary tactical ownership
    // handoff. Preserve anchor reset and observer diagnostics, but do not ReleaseAll
    // and do not freeze registration. The preInit manager filter simultaneously
    // prevents ITW_AtkDefendStart/Done from directly rewriting HAL infantry.
    if (_event in ["defend-start","defend-done"] && {
        isServer && {ITW_CLASH_ObserverEnabled}
    }) exitWith {
        if (ITW_CLASH_LiveEnabled) then {
            [_event] call ITW_CLASH_fnc_ResetAnchors;
        };
        [_event] call ITW_CLASH_fnc_WouldReleaseAll;
        ["lifecycle",[_event,_details]] call ITW_CLASH_fnc_Log;
        ["defend-phase-persistent",[
            _event,
            count (ITW_CLASH_ManagedGroups select {!isNull _x}),
            ITW_CLASH_RegistrationFrozenUntil
        ]] call ITW_CLASH_InfantryAuthority_fnc_Log;
        true
    };

    [_event,_details] call ITW_CLASH_fnc_ObserveLifecycle_InfantryAuthorityBase
};

ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints = {
    private _candidates = +ITW_CLASH_ManagedGroups;
    if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
        {_candidates pushBackUnique _x} forEach +ITW_CLASH_DualHALBLUFORGroups;
    };
    if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
        {_candidates pushBackUnique _x} forEach +ITW_CLASH_DualHALOPFORExtraGroups;
    };

    private _currentBySide = createHashMap;
    private _garrisons = [];
    private _sofGarrisonsIgnored = [];

    {
        private _group = _x;
        if (isNull _group || {!(_group getVariable ["ITW_Garrison",false])}) then {continue};
        if (((units _group) findIf {isPlayer _x}) >= 0) then {continue};
        if (_group getVariable ["ITW_CLASH_GTFO",false]) then {continue};

        private _isSOF = !isNil "ITW_CLASH_SOF_fnc_IsSOF" && {
            [_group] call ITW_CLASH_SOF_fnc_IsSOF
        };
        if (_isSOF) then {
            _sofGarrisonsIgnored pushBackUnique _group;
            continue;
        };

        private _key = toUpperANSI str (side _group);
        private _sideGarrisons = _currentBySide getOrDefault [_key,[]];
        _sideGarrisons pushBackUnique _group;
        _currentBySide set [_key,_sideGarrisons];
        _garrisons pushBackUnique _group;
    } forEach _candidates;

    private _previousBySide = missionNamespace getVariable [
        "ITW_CLASH_InfantryAuthorityGarrisonsBySide",
        createHashMap
    ];
    if !(_previousBySide isEqualType createHashMap) then {
        _previousBySide = createHashMap;
    };

    private _sides = [];
    if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
    if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};

    {
        private _side = _x;
        private _key = toUpperANSI str _side;
        private _previous = _previousBySide getOrDefault [_key,[]];
        private _current = _currentBySide getOrDefault [_key,[]];

        if (!isNil "ITW_CLASH_CommanderParity_fnc_ReconcileConstraintMembership") then {
            [
                _side,
                ["NoAttack","NoRecon"],
                _previous,
                _current
            ] call ITW_CLASH_CommanderParity_fnc_ReconcileConstraintMembership;
        };
    } forEach _sides;

    missionNamespace setVariable [
        "ITW_CLASH_InfantryAuthorityGarrisonsBySide",
        _currentBySide
    ];
    missionNamespace setVariable [
        "ITW_CLASH_InfantryAuthorityGarrisons",
        +_garrisons
    ];

    private _signature = str [
        _garrisons apply {
            [
                [_x] call ITW_CLASH_fnc_GroupId,
                side _x
            ]
        },
        _sofGarrisonsIgnored apply {
            [
                [_x] call ITW_CLASH_fnc_GroupId,
                side _x
            ]
        }
    ];
    if (_signature != missionNamespace getVariable ["ITW_CLASH_InfantryRoleSignature",""]) then {
        ITW_CLASH_InfantryRoleSignature = _signature;
        ["roles",[
            ["garrison-hal-defensive",_garrisons apply {
                [[_x] call ITW_CLASH_fnc_GroupId,side _x]
            }],
            ["sof-garrison-ignored",_sofGarrisonsIgnored apply {
                [[_x] call ITW_CLASH_fnc_GroupId,side _x]
            }]
        ]] call ITW_CLASH_InfantryAuthority_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_ApplyObjectiveDoctrine = {
    private _result = call ITW_CLASH_fnc_ApplyObjectiveDoctrine_InfantryAuthorityBase;
    call ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints;
    _result
};

diag_log format [
    "CLASH BOOT | infantry-authority-ready | version=%1 allFieldedInfantry=true subAll=false legacyAdmissionCap=false objectiveAffinityOnly=true garrisonsHAL=true garrisonConstraintsSelfCleaning=true garrisonConstraintsBothSides=true symmetricCommanderFallback=true supportSpecialistsHAL=true transportHandoff=true impasseTacticalWritersSuppressed=true defendPhasePersistent=true",
    ITW_CLASH_InfantryAuthorityVersion
];

true
