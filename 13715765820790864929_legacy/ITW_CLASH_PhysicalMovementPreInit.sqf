#include "defines.hpp"

ITW_CLASH_PhysicalMovementPreInitVersion = 5;

// Baseline Impasse deliberately uses SafeMove/vehicle repositioning during
// initial force staging. Preserve that deployment abstraction. C.L.A.S.H. only
// replaces the explicit mid-battle InfantryMoveUp catch-up teleport.
ITW_CLASH_fnc_PhysicalMoveUpLocal = {
    params ["_group","_toPos"];
    if (isNull _group || {!local _group} || {_toPos isEqualTo []}) exitWith {false};

    private _leader = leader _group;
    if (isNull _leader) exitWith {false};

    private _radius = 50 max (ITW_ParamObjectiveSize - 100);
    private _wpPos = _toPos getPos [
        _radius,
        _toPos getDir (getPosATL _leader)
    ];
    if (surfaceIsWater _wpPos) then {
        _wpPos = [_toPos,ITW_ParamObjectiveSize] call ITW_AtkWpPoint;
    };
    if (_wpPos isEqualTo [] || {_wpPos isEqualTo [0,0]}) exitWith {false};
    if (count _wpPos < 3) then {_wpPos pushBack 0};

    {deleteWaypoint _x} forEachReversed waypoints _group;
    private _wp = _group addWaypoint [_wpPos,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "YELLOW";
    _wp setWaypointCompletionRadius 50;
    true
};
["ITW_CLASH_fnc_PhysicalMoveUpLocal"] call SKL_fnc_CompileFinal;

if (!isServer) exitWith {true};
if (missionNamespace getVariable ["ITW_CLASH_PhysicalMovementPreInitStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_PhysicalMovementPreInitReady",false]
};
ITW_CLASH_PhysicalMovementPreInitStarted = true;
ITW_CLASH_PhysicalMovementPreInitReady = false;

if (isNil "ITW_AtkInfantryMoveUp") exitWith {
    diag_log "CLASH BOOT | FAILED | physical-movement-source-missing | ITW_AtkInfantryMoveUp";
    false
};

ITW_CLASH_AtkInfantryMoveUp_Baseline = ITW_AtkInfantryMoveUp;

ITW_CLASH_fnc_PhysicalMovementActive = {
    (missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]) || {
        (missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]) && {
            (missionNamespace getVariable ["ITW_ParamCLASHObserver",0]) == 2
        }
    }
};
["ITW_CLASH_fnc_PhysicalMovementActive"] call SKL_fnc_CompileFinal;

ITW_AtkInfantryMoveUp = {
    params ["_group","_toPos"];

    // If C.L.A.S.H. is disabled or failed bootstrap, preserve stock Impasse
    // behavior exactly, including the original SafeMove catch-up relocation.
    if !(call ITW_CLASH_fnc_PhysicalMovementActive) exitWith {
        _this call ITW_CLASH_AtkInfantryMoveUp_Baseline
    };
    if (isNull _group || {_toPos isEqualTo []}) exitWith {false};

    // HAL-owned field formations and explicit recovery/transit states are not
    // candidates for an Impasse tactical move-up. This applies symmetrically to
    // legacy OPFOR ownership and the new dual-HAL BLUFOR lane.
    if (_group getVariable ["ITW_CLASH_Managed",false] || {
        _group getVariable ["ITW_CLASH_DualHALManaged",false] || {
            _group getVariable ["ITW_CLASH_Withdrawing",false] || {
                _group getVariable ["ITW_CLASH_ReconstitutionTransit",false]
            }
        }
    }) exitWith {false};

    private _leader = leader _group;
    if (isNull _leader) exitWith {false};
    private _from = getPosATL _leader;
    private _distance = round (_leader distance2D _toPos);
    private _id = if (isNil "ITW_CLASH_fnc_GroupId") then {str _group} else {
        [_group] call ITW_CLASH_fnc_GroupId
    };

    // Do not reproduce the baseline candidate-position SafeMove. Reassert a
    // normal physical objective-edge waypoint on the machine that owns the
    // group. The formation must now cover the distance in-world.
    if (local _group) then {
        [_group,_toPos] call ITW_CLASH_fnc_PhysicalMoveUpLocal;
    } else {
        [[_group,_toPos],"ITW_CLASH_fnc_PhysicalMoveUpLocal",_group] call ITW_FncRemoteLocalGroup;
    };

    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["strategic-teleport-suppressed",[
            _id,"infantry-move-up",_from,+_toPos,_distance,
            _group getVariable ["ITW_CLASH_AssignedObjective",VAR_GET_OBJ_IDX(_group)],
            groupOwner _group
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

isNil {
    private _deferred = missionNamespace getVariable ["ITW_CLASH_DeferredFinalizers",[]];
    _deferred = _deferred - ["ITW_AtkInfantryMoveUp"];
    missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];
};

private _moveUpFinal = ["ITW_AtkInfantryMoveUp"] call SKL_fnc_CompileFinal;
ITW_CLASH_PhysicalMovementPreInitReady = _moveUpFinal;

diag_log format [
    "CLASH BOOT | physical-movement-ready | version=%1 moveUp=%2 midBattleMoveUpTeleport=false initialStaging=true safeMoveBaseline=true dualHALProtected=true failOpen=true",
    ITW_CLASH_PhysicalMovementPreInitVersion,
    _moveUpFinal
];

ITW_CLASH_PhysicalMovementPreInitReady