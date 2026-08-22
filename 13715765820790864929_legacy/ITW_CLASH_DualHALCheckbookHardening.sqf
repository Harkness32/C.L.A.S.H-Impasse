#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_DualHALCheckbookHardeningStarted",false]) exitWith {true};
ITW_CLASH_DualHALCheckbookHardeningStarted = true;
ITW_CLASH_DualHALCheckbookHardeningVersion = 5;
ITW_CLASH_DualHALHardeningLastBZone = -1;

if (
    isNil "ITW_CLASH_DualHAL_fnc_PrepareCommanderB" ||
    {isNil "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved"} ||
    {isNil "ITW_CLASH_DualHAL_fnc_StageFieldVehicle"} ||
    {isNil "ITW_CLASH_DualHAL_fnc_TrackAsset"} ||
    {isNil "ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives"} ||
    {isNil "ITW_CLASH_Checkbook_fnc_RequestTransport"}
) exitWith {
    diag_log "CLASH BOOT | WARNING | dual-hal-checkbook-hardening-source-missing";
    false
};

ITW_CLASH_DualHALHardening_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hardening-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH DUAL HAL HARDENING | %1 | %2",_event,_payload];
    };
};

/*
    Commander B is a real HAL HQ but also an invisible compatibility object.
    Impasse's infantry query and stuck handler both explicitly ignore groups
    tagged ITW_CLASH_Commander. Commander A already carries that tag; B must too.
*/
ITW_CLASH_DualHALHardening_fnc_PrepareCommanderBBase = ITW_CLASH_DualHAL_fnc_PrepareCommanderB;
ITW_CLASH_DualHAL_fnc_PrepareCommanderB = {
    private _result = [] call ITW_CLASH_DualHALHardening_fnc_PrepareCommanderBBase;
    if (_result && {!isNull ITW_CLASH_BLUFORHQ}) then {
        ITW_CLASH_BLUFORHQ setVariable ["ITW_CLASH_Commander",true];
        ITW_CLASH_BLUFORHQ setVariable ["ITW_CLASH_ExcludeHAL",true];
        ITW_CLASH_BLUFORHQ setVariable ["zbe_cacheDisabled",true];
        if (!isNull ITW_CLASH_BLUFORLeader) then {
            ITW_CLASH_BLUFORLeader setVariable ["itw_dmgBlocked",true];
        };
    };
    _result
};

/*
    Expand the lifecycle reservation predicate. The compatibility layer is not
    the owner while another C.L.A.S.H. lifecycle explicitly leases a group or
    vehicle. This remains a negative gate only; no movement/order is issued.
*/
ITW_CLASH_DualHALHardening_fnc_IsLifecycleReservedBase = ITW_CLASH_DualHAL_fnc_IsLifecycleReserved;
ITW_CLASH_DualHAL_fnc_IsLifecycleReserved = {
    params ["_group",["_veh",objNull]];
    if ([_group,_veh] call ITW_CLASH_DualHALHardening_fnc_IsLifecycleReservedBase) exitWith {true};
    if (isNull _group) exitWith {true};

    if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {true};
    if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") exitWith {true};
    if ((_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") exitWith {true};
    if (_group getVariable ["ITW_CLASH_Withdrawing",false] && {
        !(_group getVariable ["ITW_CLASH_DualHALManaged",false])
    }) exitWith {true};

    if (!isNull _veh) then {
        if (_veh getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {true};
        if ((_veh getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") exitWith {true};
        if ((_veh getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") exitWith {true};
    };
    false
};

/*
    ITW_AtkDispatchReconstitutionTransport calls ITW_AtkAddVehicle after the
    replacement group is already aboard. The transport crew itself is ordinary,
    while the cargo group carries ITW_CLASH_ReconstitutionTransit. Therefore the
    field handoff must inspect every cargo group before it unloads/re-stages an
    Impasse wave. Same protection applies to CASEVAC/MEDEVAC authority.
*/
ITW_CLASH_DualHALHardening_fnc_StageFieldVehicleBase = ITW_CLASH_DualHAL_fnc_StageFieldVehicle;
ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {
    params ["_vehInfo",["_teleportToAttackPos",false],["_populateObjectives",false]];
    if !(_vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CARGO_GRPS}) exitWith {false};

    private _veh = _vehInfo#VEHINFO_VEH;
    private _crewGroup = _vehInfo#VEHINFO_CREW_GRP;
    private _cargoGroups = +(_vehInfo#VEHINFO_CARGO_GRPS);

    private _reservedCargo = _cargoGroups findIf {
        private _cargoGroup = _x;
        !isNull _cargoGroup && {
            [_cargoGroup,_veh] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved
        }
    };
    if (_reservedCargo >= 0) exitWith {
        private _cargoGroup = _cargoGroups#_reservedCargo;
        ["vehicle-handoff-bypassed",[
            if (isNull _veh) then {"<null>"} else {typeOf _veh},
            if (isNull _crewGroup) then {"<null>"} else {[_crewGroup] call ITW_CLASH_DualHAL_fnc_GroupId},
            [_cargoGroup] call ITW_CLASH_DualHAL_fnc_GroupId,
            "reserved-cargo-lifecycle"
        ]] call ITW_CLASH_DualHALHardening_fnc_Log;
        false
    };

    private _result = _this call ITW_CLASH_DualHALHardening_fnc_StageFieldVehicleBase;

    // Suppressing baseline ITW_AtkAddVehicle also suppresses its dedicated
    // transport disarm step. Preserve that non-tactical Impasse vehicle policy.
    if (_result && {!isNull _veh} && {
        (_vehInfo#VEHINFO_ROLE) == ITW_VEH_ROLE_TRANSPORT && {
            !isNil "ITW_AtkVehRemoveMagazines"
        }
    }) then {
        [_veh] remoteExec ["ITW_AtkVehRemoveMagazines",_veh];
    };
    _result
};

/*
    Impasse owns live vehicle accounting. ITW_AtkVehicleManager periodically
    zeros all ITW_VEH_COUNT values and rebuilds them from live vehicles carrying
    ITW_VehDef. Checkbook pays/increments once at creation, then stores no mutable
    count reference in its cleanup ledger so it cannot double-decrement between
    Impasse recounts.
*/
ITW_CLASH_DualHALHardening_fnc_TrackAssetBase = ITW_CLASH_DualHAL_fnc_TrackAsset;
ITW_CLASH_DualHAL_fnc_TrackAsset = {
    params ["_veh",["_vehDef",[]],["_source","impasse-field"]];
    private _result = _this call ITW_CLASH_DualHALHardening_fnc_TrackAssetBase;
    if (_result && {!isNull _veh}) then {
        for "_i" from ((count ITW_CLASH_CheckbookAssets) - 1) to 0 step -1 do {
            private _entry = ITW_CLASH_CheckbookAssets#_i;
            if ((_entry#0) isEqualTo _veh) exitWith {
                _entry set [1,[]];
                ITW_CLASH_CheckbookAssets set [_i,_entry];
            };
        };
    };
    _result
};

/*
    V5 deliberately does not wrap RequestTransport. The RPT showed that the
    legacy base function's breakOut escaped the wrapper assignment and left
    `_result` undefined. V2 uses typed local control flow and the generic API's
    side/capability lease, so transport, artillery and logistics share one
    serialization contract without a global cross-side lock.
*/

/*
    Match Commander A's mature simple-objective contract. SetTakenA is stored on
    B's private mirror object, while RydHQ_Taken is the planner-level list that
    Orders.sqf subtracts from objectives before selecting reconnaissance/attack
    targets. Because mirrors are private to B there is no A/B state collision.

    HAL's objective cursor is stateful. When Impasse advances to another zone,
    reset B to objective stage 1 exactly as Commander A's canonical mirror does.
*/
ITW_CLASH_DualHALHardening_fnc_RefreshBLUFORObjectivesBase = ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives;
ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives = {
    private _mirrors = [] call ITW_CLASH_DualHALHardening_fnc_RefreshBLUFORObjectivesBase;
    private _taken = _mirrors select {
        _x getVariable ["ITW_CLASH_BLUFOROwned",false]
    };

    RydHQB_Taken = +_taken;
    if (!isNull ITW_CLASH_BLUFORHQ) then {
        ITW_CLASH_BLUFORHQ setVariable ["RydHQ_Taken",+_taken];
        ITW_CLASH_BLUFORHQ setVariable ["RydHQ_Objectives",+_mirrors];
    };

    private _zone = missionNamespace getVariable ["ITW_ZoneIndex",-1];
    if (_zone != ITW_CLASH_DualHALHardeningLastBZone) then {
        RydHQB_NObj = 1;
        if (!isNull ITW_CLASH_BLUFORHQ) then {
            ITW_CLASH_BLUFORHQ setVariable ["RydHQ_NObj",1];
        };
        ["commander-b-objective-zone-reset",[
            ITW_CLASH_DualHALHardeningLastBZone,_zone,count _mirrors,count _taken
        ]] call ITW_CLASH_DualHALHardening_fnc_Log;
        ITW_CLASH_DualHALHardeningLastBZone = _zone;
    };
    _mirrors
};

/*
    Commander B may be created before Impasse has finalized Base 0. Bind its
    hidden physical leader to the real strategic rear base once the campaign is
    ready. This happens once and does not become a tactical relocation system.
*/
[] spawn {
    scriptName "ITW_CLASH_DualHAL_CommanderBBaseBind";
    private _deadline = time + 300;
    waitUntil {
        sleep 0.5;
        time >= _deadline || {
            !isNull ITW_CLASH_BLUFORHQ && {
                !isNull ITW_CLASH_BLUFORLeader && {
                    missionNamespace getVariable ["ITW_GameReady",false] && {
                        !isNil "ITW_Bases" && {count ITW_Bases > 0}
                    }
                }
            }
        }
    };

    if (time >= _deadline || {isNull ITW_CLASH_BLUFORLeader}) exitWith {
        ["commander-b-base-bind-timeout",[]] call ITW_CLASH_DualHALHardening_fnc_Log;
    };

    private _basePos = +(ITW_Bases#0#ITW_BASE_POS);
    if (_basePos isEqualTo []) exitWith {
        ["commander-b-base-bind-failed",["empty-base0-position"]] call ITW_CLASH_DualHALHardening_fnc_Log;
    };
    if (count _basePos < 3) then {_basePos pushBack 0};

    ITW_CLASH_BLUFORLeader setPosATL _basePos;
    ITW_CLASH_BLUFORHQ setVariable ["ITW_CLASH_StrategicHome",+_basePos];
    ["commander-b-base-bound",[_basePos]] call ITW_CLASH_DualHALHardening_fnc_Log;
};

diag_log format [
    "CLASH BOOT | dual-hal-checkbook-hardening-ready | version=%1 commanderProtected=true lifecycleCargoBypass=true impasseOwnsVehicleCount=true purchaseLease=api-v2 takenSync=true zoneReset=true base0Bind=true",
    ITW_CLASH_DualHALCheckbookHardeningVersion
];

true
