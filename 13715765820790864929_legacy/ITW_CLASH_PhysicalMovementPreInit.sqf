#include "defines.hpp"

ITW_CLASH_PhysicalMovementPreInitVersion = 3;

// Every machine receives this helper before gameplay. The server-side
// ITW_AtkSafeMove override uses it when a group is owned by a headless client,
// so C.L.A.S.H. mode never falls through to that machine's finalized baseline
// setPos-based SafeMove implementation.
ITW_CLASH_fnc_PhysicalMoveLocal = {
    params ["_group","_destination"];
    if (isNull _group || {!local _group} || {_destination isEqualTo []}) exitWith {false};
    if (surfaceIsWater _destination) exitWith {false};
    _group setSpeedMode "FULL";
    _group move _destination;
    true
};
["ITW_CLASH_fnc_PhysicalMoveLocal"] call SKL_fnc_CompileFinal;

if (!isServer) exitWith {true};
if (missionNamespace getVariable ["ITW_CLASH_PhysicalMovementPreInitStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_PhysicalMovementPreInitReady",false]
};
ITW_CLASH_PhysicalMovementPreInitStarted = true;
ITW_CLASH_PhysicalMovementPreInitReady = false;

if (isNil "ITW_AtkSafeMove" || {isNil "ITW_AtkAddVehicle"}) exitWith {
    diag_log "CLASH BOOT | FAILED | physical-movement-source-missing";
    false
};

ITW_CLASH_AtkSafeMove_Baseline = ITW_AtkSafeMove;
ITW_CLASH_AtkAddVehicle_Baseline = ITW_AtkAddVehicle;

ITW_CLASH_fnc_PhysicalMovementActive = {
    (missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]) || {
        (missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]) && {
            (missionNamespace getVariable ["ITW_ParamCLASHObserver",0]) == 2
        }
    }
};
["ITW_CLASH_fnc_PhysicalMovementActive"] call SKL_fnc_CompileFinal;

ITW_AtkSafeMove = {
    params ["_group","_pos"];

    // Preserve exact baseline Impasse semantics when C.L.A.S.H. is disabled or
    // its bootstrap failed. Once a validated mode-2 bootstrap exists, suppress
    // strategic teleportation even before the scheduled HAL live loop starts.
    if !(call ITW_CLASH_fnc_PhysicalMovementActive) exitWith {
        _this call ITW_CLASH_AtkSafeMove_Baseline
    };
    if (isNull _group || {_pos isEqualTo []}) exitWith {};

    private _destination = +_pos;
    if (count _destination < 3) then {_destination pushBack 0};
    _destination set [2,0];

    private _leader = leader _group;
    private _from = if (isNull _leader) then {[0,0,0]} else {getPosATL _leader};
    private _distance = if (isNull _leader) then {-1} else {round (_leader distance2D _destination)};
    private _id = if (isNil "ITW_CLASH_fnc_GroupId") then {str _group} else {
        [_group] call ITW_CLASH_fnc_GroupId
    };

    if (surfaceIsWater _destination) exitWith {
        if (!isNil "ITW_CLASH_fnc_Log") then {
            ["physical-move-rejected-water",[
                _id,_from,_destination,_distance
            ]] call ITW_CLASH_fnc_Log;
        };
    };

    // Never remote-execute ITW_AtkSafeMove itself in C.L.A.S.H. mode: a
    // headless client owns a finalized baseline copy. Execute the dedicated
    // physical helper on whichever machine owns the group instead.
    if (local _group) then {
        [_group,_destination] call ITW_CLASH_fnc_PhysicalMoveLocal;
    } else {
        [[_group,_destination],"ITW_CLASH_fnc_PhysicalMoveLocal",_group] call ITW_FncRemoteLocalGroup;
    };

    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["strategic-teleport-suppressed",[
            _id,_from,_destination,_distance,
            _group getVariable ["ITW_CLASH_AssignedObjective",VAR_GET_OBJ_IDX(_group)],
            groupOwner _group
        ]] call ITW_CLASH_fnc_Log;
    };
};

ITW_AtkAddVehicle = {
    private _args = +_this;
    private _requestedTeleport = if (count _args > 2) then {_args#2} else {true};

    if (call ITW_CLASH_fnc_PhysicalMovementActive) then {
        if (count _args > 2) then {
            _args set [2,false];
        } else {
            _args pushBack false;
        };

        if (_requestedTeleport && {!isNil "ITW_CLASH_fnc_Log"}) then {
            private _vehInfo = if (_args isEqualTo []) then {[]} else {_args#0};
            private _veh = if (count _vehInfo > VEHINFO_VEH) then {_vehInfo#VEHINFO_VEH} else {objNull};
            private _crew = if (count _vehInfo > VEHINFO_CREW_GRP) then {_vehInfo#VEHINFO_CREW_GRP} else {grpNull};
            ["vehicle-teleport-suppressed",[
                if (isNull _veh) then {""} else {typeOf _veh},
                if (isNull _crew) then {"<null>"} else {str _crew},
                if (isNull _veh) then {[0,0,0]} else {getPosATL _veh}
            ]] call ITW_CLASH_fnc_Log;
        };
    };

    _args call ITW_CLASH_AtkAddVehicle_Baseline
};

isNil {
    private _deferred = missionNamespace getVariable ["ITW_CLASH_DeferredFinalizers",[]];
    _deferred = _deferred - ["ITW_AtkSafeMove","ITW_AtkAddVehicle"];
    missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];
};

private _safeMoveFinal = ["ITW_AtkSafeMove"] call SKL_fnc_CompileFinal;
private _addVehicleFinal = ["ITW_AtkAddVehicle"] call SKL_fnc_CompileFinal;
ITW_CLASH_PhysicalMovementPreInitReady = _safeMoveFinal && _addVehicleFinal;

diag_log format [
    "CLASH BOOT | physical-movement-ready | version=%1 safeMove=%2 addVehicle=%3 strategicTeleport=false hcSafe=true failOpen=true",
    ITW_CLASH_PhysicalMovementPreInitVersion,
    _safeMoveFinal,
    _addVehicleFinal
];

ITW_CLASH_PhysicalMovementPreInitReady