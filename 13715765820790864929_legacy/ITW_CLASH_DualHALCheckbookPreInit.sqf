#include "defines.hpp"

if (!isServer) exitWith {true};
if (missionNamespace getVariable ["ITW_CLASH_DualHALCheckbookPreInitStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_DualHALCheckbookPreInitReady",false]
};

ITW_CLASH_DualHALCheckbookPreInitStarted = true;
ITW_CLASH_DualHALCheckbookPreInitVersion = 1;
ITW_CLASH_DualHALCheckbookPreInitReady = false;

/*
    PreInit compatibility seam for the symmetric C.L.A.S.H. commander model.

    The runtime module is loaded later from init.sqf, but Impasse's attack
    writers are compiled/finalized here. These wrappers make no tactical
    decisions themselves: when the runtime dual-HAL layer is ready they offer
    the handoff to that layer; otherwise they fail open to untouched Impasse.
*/

if (
    isNil "ITW_AtkAddVehicle"
    || {isNil "ITW_AtkEngageInfantry"}
    || {isNil "ITW_AtkEngageVehicle"}
) exitWith {
    diag_log "CLASH BOOT | FAILED | dual-hal-preinit-source-missing";
    false
};

ITW_CLASH_DualHAL_fnc_AtkAddVehicleBase = ITW_AtkAddVehicle;
ITW_CLASH_DualHAL_fnc_AtkEngageInfantryBase = ITW_AtkEngageInfantry;
ITW_CLASH_DualHAL_fnc_AtkEngageVehicleBase = ITW_AtkEngageVehicle;

ITW_AtkAddVehicle = {
    params ["_vehInfo","_populateObjectives",["_teleportToAttackPos",true]];

    if (
        !isNil "ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter"
        && {!isNil "ITW_CLASH_DualHAL_fnc_StageFieldVehicle"}
    ) then {
        private _crewGroup = if (
            _vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CREW_GRP}
        ) then {_vehInfo#VEHINFO_CREW_GRP} else {grpNull};

        if ([_crewGroup,_vehInfo] call ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter) then {
            private _handled = [_vehInfo,_teleportToAttackPos,_populateObjectives] call
                ITW_CLASH_DualHAL_fnc_StageFieldVehicle;
            if (_handled) exitWith {
                private _veh = _vehInfo#VEHINFO_VEH;
                if (
                    !isNull _veh
                    && {_vehInfo#VEHINFO_ROLE == ITW_VEH_ROLE_TRANSPORT}
                    && {!isNil "ITW_AtkVehRemoveMagazines"}
                ) then {
                    [_veh] remoteExec ["ITW_AtkVehRemoveMagazines",_veh];
                };
                true
            };
        };
    };

    _this call ITW_CLASH_DualHAL_fnc_AtkAddVehicleBase
};

ITW_AtkEngageInfantry = {
    params ["_group","_teleportToAttackPos",["_objToPopulate",[]]];

    if (
        !isNil "ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup"
        && {!isNil "ITW_CLASH_DualHAL_fnc_StageFriendlyInfantry"}
        && {[_group] call ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup}
    ) then {
        private _handled = [_group,_teleportToAttackPos,_objToPopulate] call
            ITW_CLASH_DualHAL_fnc_StageFriendlyInfantry;
        if (_handled) exitWith {true};
    };

    _this call ITW_CLASH_DualHAL_fnc_AtkEngageInfantryBase
};

ITW_AtkEngageVehicle = {
    params ["_vehInfo",["_teleportToAttackPos",false],["_populateObjectives",false]];

    if (
        !isNil "ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter"
        && {!isNil "ITW_CLASH_DualHAL_fnc_StageFieldVehicle"}
    ) then {
        private _crewGroup = if (
            _vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CREW_GRP}
        ) then {_vehInfo#VEHINFO_CREW_GRP} else {grpNull};

        if ([_crewGroup,_vehInfo] call ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter) then {
            private _handled = [_vehInfo,_teleportToAttackPos,_populateObjectives] call
                ITW_CLASH_DualHAL_fnc_StageFieldVehicle;
            if (_handled) exitWith {true};
        };
    };

    _this call ITW_CLASH_DualHAL_fnc_AtkEngageVehicleBase
};

private _deferred = missionNamespace getVariable ["ITW_CLASH_DeferredFinalizers",[]];
_deferred = _deferred - [
    "ITW_AtkAddVehicle",
    "ITW_AtkEngageInfantry",
    "ITW_AtkEngageVehicle"
];
missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];

private _addFinal = ["ITW_AtkAddVehicle"] call SKL_fnc_CompileFinal;
private _infFinal = ["ITW_AtkEngageInfantry"] call SKL_fnc_CompileFinal;
private _vehFinal = ["ITW_AtkEngageVehicle"] call SKL_fnc_CompileFinal;

if (!_addFinal) then {
    ITW_AtkAddVehicle = ITW_CLASH_DualHAL_fnc_AtkAddVehicleBase;
};
if (!_infFinal) then {
    ITW_AtkEngageInfantry = ITW_CLASH_DualHAL_fnc_AtkEngageInfantryBase;
};
if (!_vehFinal) then {
    ITW_AtkEngageVehicle = ITW_CLASH_DualHAL_fnc_AtkEngageVehicleBase;
};

ITW_CLASH_DualHALCheckbookPreInitReady = _addFinal && _infFinal && _vehFinal;

diag_log format [
    "CLASH BOOT | dual-hal-checkbook-preinit-ready | version=%1 addVehicle=%2 infantryWriter=%3 vehicleWriter=%4 failOpen=true",
    ITW_CLASH_DualHALCheckbookPreInitVersion,
    _addFinal,
    _infFinal,
    _vehFinal
];

ITW_CLASH_DualHALCheckbookPreInitReady
