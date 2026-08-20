#include "defines.hpp"

if (!isServer) exitWith {false};
ITW_CLASH_InfantryAuthorityVersion = 1;

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

ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints = {
    if (isNull ITW_CLASH_HALHQ) exitWith {false};

    // Remove only the compatibility constraints this layer wrote on the previous
    // pass. Anchors, GTFO and any native/manual NoAttack/NoRecon entries survive.
    private _previousGarrisons = missionNamespace getVariable [
        "ITW_CLASH_InfantryAuthorityGarrisons",
        []
    ];
    private _noAttack = +(ITW_CLASH_HALHQ getVariable ["RydHQ_NoAttack",[]]);
    private _noRecon = +(ITW_CLASH_HALHQ getVariable ["RydHQ_NoRecon",[]]);
    _noAttack = _noAttack - _previousGarrisons;
    _noRecon = _noRecon - _previousGarrisons;

    private _garrisons = [];
    private _sofGarrisonsIgnored = [];

    {
        private _group = _x;
        if (isNull _group || {!(_group getVariable ["ITW_Garrison",false])}) then {continue};
        if (_group getVariable ["ITW_CLASH_GTFO",false]) then {continue};

        // SOF doctrine outranks a stale/broad Impasse garrison marker. SOF stays
        // available to HAL for recon/direct action and can never become a static
        // objective holder through this compatibility constraint.
        private _isSOF = !isNil "ITW_CLASH_SOF_fnc_IsSOF" && {
            [_group] call ITW_CLASH_SOF_fnc_IsSOF
        };
        if (_isSOF) then {
            _sofGarrisonsIgnored pushBackUnique _group;
            continue;
        };

        _garrisons pushBackUnique _group;
        _noAttack pushBackUnique _group;
        _noRecon pushBackUnique _group;
    } forEach +ITW_CLASH_ManagedGroups;

    missionNamespace setVariable [
        "ITW_CLASH_InfantryAuthorityGarrisons",
        +_garrisons
    ];
    ITW_CLASH_HALHQ setVariable ["RydHQ_NoAttack",_noAttack];
    ITW_CLASH_HALHQ setVariable ["RydHQ_NoRecon",_noRecon];
    RydHQ_NoAttack = +_noAttack;
    RydHQ_NoRecon = +_noRecon;

    private _signature = str [
        _garrisons apply {[_x] call ITW_CLASH_fnc_GroupId},
        _sofGarrisonsIgnored apply {[_x] call ITW_CLASH_fnc_GroupId}
    ];
    if (_signature != missionNamespace getVariable ["ITW_CLASH_InfantryRoleSignature",""]) then {
        ITW_CLASH_InfantryRoleSignature = _signature;
        ["roles",[
            ["garrison-hal-defensive",_garrisons apply {[_x] call ITW_CLASH_fnc_GroupId}],
            ["sof-garrison-ignored",_sofGarrisonsIgnored apply {[_x] call ITW_CLASH_fnc_GroupId}]
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
    "CLASH BOOT | infantry-authority-ready | version=%1 allFieldedInfantry=true subAll=false legacyAdmissionCap=false objectiveAffinityOnly=true garrisonsHAL=true garrisonConstraintsSelfCleaning=true supportSpecialistsHAL=true transportHandoff=true",
    ITW_CLASH_InfantryAuthorityVersion
];

true
