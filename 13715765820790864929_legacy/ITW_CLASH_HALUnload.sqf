#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALUnloadStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALUnloadReady",false]
};

ITW_CLASH_HALUnloadStarted = true;
ITW_CLASH_HALUnloadReady = false;
ITW_CLASH_HALUnloadVersion = 1;
scriptName "ITW_CLASH_HALUnload";

/*
    One owner for HAL troop-lift unloads.

    HAL owns whether a squad rides, which carrier is used, and every waypoint.
    This module owns exactly one question when HAL's insertion waypoint fires:
    LAND, PARADROP, or HOT_PARADROP.

    The order-file hook is deliberately asynchronous. It spawns fnc_Unload and
    then deletes HAL's completed waypoint in the caller. A runtime error in this
    module therefore cannot strand the carrier on a waypoint - the failure mode
    that produced aee1341. If this module is absent entirely, the hook falls
    back to stock land "GET OUT" plus the existing carrier release helper.
*/

ITW_CLASH_HALUnloadOrderSpecs = [
    ["HAL_GoAttInf","GoAttInf.sqf","GoAttInf"],
    ["HAL_GoRecon","GoRecon.sqf","GoRecon"],
    ["HAL_GoCapture","GoCapture.sqf","GoCapture"],
    ["HAL_GoRest","GoRest.sqf","GoRest"],
    ["HAL_GoAttSniper","GoAttSniper.sqf","GoAttSniper"],
    ["HAL_GoFlank","GoFlank.sqf","GoFlank"],
    ["HAL_GoSFAttack","GoSFAttack.sqf","GoSFAttack"]
];

ITW_CLASH_HALUnload_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-unload-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL UNLOAD | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["hal-unload",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

ITW_CLASH_HALUnload_fnc_CargoGroup = {
    params ["_carrierGroup","_carrier"];
    if (isNull _carrierGroup || {isNull _carrier}) exitWith {grpNull};
    private _found = grpNull;
    {
        if (!alive _x || {vehicle _x != _carrier}) then {continue};
        private _group = group _x;
        if (isNull _group || {_group isEqualTo _carrierGroup}) then {continue};
        if !(_x isKindOf "CAManBase") then {continue};
        _found = _group;
        break;
    } forEach (crew _carrier);
    _found
};

ITW_CLASH_HALUnload_fnc_Commander = {
    params ["_cargoGroup","_carrierGroup"];
    private _hq = grpNull;
    if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup" && {!isNull _cargoGroup}) then {
        _hq = [_cargoGroup] call ITW_CLASH_fnc_GetCommanderForGroup;
    };
    if (
        isNull _hq
        && {!isNil "ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup"}
        && {!isNull _cargoGroup}
    ) then {
        _hq = [_cargoGroup] call ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup;
    };
    if (
        isNull _hq
        && {!isNil "ITW_CLASH_fnc_GetCommanderForGroup"}
        && {!isNull _carrierGroup}
    ) then {
        _hq = [_carrierGroup] call ITW_CLASH_fnc_GetCommanderForGroup;
    };
    _hq
};

ITW_CLASH_HALUnload_fnc_Corridor = {
    params ["_hq","_carrierGroup","_carrier"];
    private _fallback = createHashMapFromArray [
        ["state","COLD"],["reason","unload-corridor-unavailable"]
    ];
    if (
        isNull _hq
        || {isNull _carrierGroup}
        || {isNull _carrier}
        || {isNil "ITW_CLASH_AirPicture_fnc_ClassifyCorridor"}
    ) exitWith {_fallback};

    // SCargo records the transport's departure point on the carrier group.
    // That gives the execution-time classifier the real flown corridor without
    // adding a second route owner or caching startup base coordinates.
    private _origin = _carrierGroup getVariable ["START" + str _carrierGroup,[]];
    private _destination = getPosATL _carrier;
    if (_origin isEqualTo [] || {_destination isEqualTo []}) exitWith {_fallback};

    [_hq,_origin,_destination] call ITW_CLASH_AirPicture_fnc_ClassifyCorridor
};

ITW_CLASH_HALUnload_fnc_Mode = {
    params ["_carrier",["_state","COLD"]];

    private _param = missionNamespace getVariable ["ITW_ParamHelisUnload",50];
    if !(_param isEqualType 0) then {_param = 50};

    private _capacity = 0;
    if (!isNil "ITW_CLASH_HALParadrop_fnc_CargoCapacity") then {
        _capacity = [_carrier] call ITW_CLASH_HALParadrop_fnc_CargoCapacity;
    };

    // The host's explicit land-only setting wins at execution. Unsafe
    // Param=0 launches are prevented in SCargo preflight; a corridor that
    // worsens after launch still completes rather than inventing a stranded
    // "abort with passengers aboard" state here.
    if (_param == 0) exitWith {["LAND",0,_capacity]};

    private _dropReady =
        missionNamespace getVariable ["ITW_CLASH_HALParadropReady",false]
        && {!isNil "ITW_CLASH_HALParadrop_fnc_Execute"};
    if (!_dropReady || {isNull _carrier} || {!(_carrier isKindOf "Helicopter")}) exitWith {
        ["LAND",0,_capacity]
    };

    if (_state in ["HOT","AIR_DENIED"]) exitWith {
        ["HOT_PARADROP",100,_capacity]
    };
    if (_state in ["CONTESTED","UNKNOWN"]) exitWith {
        ["PARADROP",100,_capacity]
    };

    if (isNil "ITW_CLASH_HALParadrop_fnc_ShouldUse") exitWith {
        ["LAND",0,_capacity]
    };
    ([_carrier,false] call ITW_CLASH_HALParadrop_fnc_ShouldUse) params [
        "_drop","_chance","_resolvedCapacity"
    ];
    [if (_drop) then {"PARADROP"} else {"LAND"},_chance,_resolvedCapacity]
};

ITW_CLASH_HALUnload_fnc_Release = {
    params ["_carrierGroup","_carrier"];
    if (!isNil "ITW_CLASH_HALParadrop_fnc_ReleaseCarrier") exitWith {
        [_carrierGroup,_carrier] call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier
    };
    // Best possible fail-open on an older mission/newer addon combination.
    // There is nobody safe to wait on without the canonical helper.
    false
};

ITW_CLASH_HALUnload_fnc_Aboard = {
    params ["_carrier","_cargoGroup"];
    if (isNull _carrier || {isNull _cargoGroup}) exitWith {[]};
    (units _cargoGroup) select {alive _x && {vehicle _x == _carrier}}
};

/*
    HOT_PARADROP in the rebuild is deliberately not a second pilot.

    It may change altitude and dispense countermeasures, but it never deletes
    HAL waypoints, calls doMove, claims the aircraft, or hands it back. HAL has
    already flown the carrier to its insertion waypoint. The richer low-ingress
    phase remains in the old HotDrop executor until this centralized lifecycle
    earns a green live run; Step 4 can then retire that executor without
    smuggling a second route owner back in.
*/
ITW_CLASH_HALUnload_fnc_StartHotFlares = {
    params ["_carrier","_cargoGroup"];
    if (
        isNull _carrier
        || {isNull _cargoGroup}
        || {isNil "ITW_CLASH_HotDrop_fnc_Flare"}
    ) exitWith {false};

    private _state = createHashMapFromArray [
        ["vehicle",_carrier],
        ["phase","POPUP"],
        ["countermeasureEmitter",
            if (isNil "ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter") then {[]} else {
                [_carrier] call ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter
            }
        ]
    ];
    if (!isNil "ITW_CLASH_ThunderRun_fnc_InitFlareBudget") then {
        [_state] call ITW_CLASH_ThunderRun_fnc_InitFlareBudget;
    };

    [_state,_carrier,_cargoGroup] spawn {
        params ["_state","_carrier","_cargoGroup"];
        private _deadline = time + (
            missionNamespace getVariable ["ITW_CLASH_HALParadrop_ClimbTimeout",45]
        );
        while {
            alive _carrier
            && {canMove _carrier}
            && {time < _deadline}
            && {([_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_Aboard) isNotEqualTo []}
        } do {
            [_state,"POPUP"] call ITW_CLASH_HotDrop_fnc_Flare;
            sleep 0.5;
        };
    };
    true
};

ITW_CLASH_HALUnload_fnc_Unload = {
    params ["_carrierGroup","_carrier",["_orderFile","UNKNOWN"]];

    private _param = missionNamespace getVariable ["ITW_ParamHelisUnload",50];
    if !(_param isEqualType 0) then {_param = 50};
    private _cargoGroup = [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_CargoGroup;
    private _result = "NO_CARGO";
    private _state = "COLD";
    private _reason = "no-cargo-group";
    private _mode = "LAND";
    private _chance = 0;
    private _capacity = 0;

    if (!isNull _carrier && {!isNull _cargoGroup}) then {
        private _hq = [_cargoGroup,_carrierGroup] call ITW_CLASH_HALUnload_fnc_Commander;
        private _corridor = [_hq,_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_Corridor;
        _state = _corridor getOrDefault ["state","COLD"];
        _reason = _corridor getOrDefault ["reason",""];

        ([_carrier,_state] call ITW_CLASH_HALUnload_fnc_Mode) params [
            "_resolvedMode","_resolvedChance","_resolvedCapacity"
        ];
        _mode = _resolvedMode;
        _chance = _resolvedChance;
        _capacity = _resolvedCapacity;

        // Any player touching the lift gets stock HAL landing behavior.
        if (
            ((crew _carrier) findIf {isPlayer _x}) >= 0
            || {((units _cargoGroup) findIf {isPlayer _x}) >= 0}
        ) then {
            _mode = "LAND";
            _reason = _reason + "|player-touch";
        };

        switch (_mode) do {
            case "PARADROP": {
                _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_cargoGroup];
                private _origin = _carrierGroup getVariable ["START" + str _carrierGroup,[]];
                _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",_origin];
                _carrier land "NONE";
                _carrier flyInHeight (
                    missionNamespace getVariable ["ITW_CLASH_HALParadrop_MinAltitude",55]
                );
                private _dropped = [_carrierGroup,_carrier] call
                    ITW_CLASH_HALParadrop_fnc_Execute;
                if (_dropped) then {
                    _result = "PARADROP"
                } else {
                    if (([_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_Aboard) isNotEqualTo []) then {
                        _carrier land "GET OUT";
                        [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_Release;
                        _result = "LAND_FALLBACK"
                    } else {
                        _result = "PARADROP_DECLINED_EMPTY"
                    };
                };
            };
            case "HOT_PARADROP": {
                _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_cargoGroup];
                private _origin = _carrierGroup getVariable ["START" + str _carrierGroup,[]];
                _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",_origin];
                _carrier land "NONE";
                _carrier flyInHeight (
                    missionNamespace getVariable ["ITW_CLASH_HotDropDropHeight",130]
                );
                [_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_StartHotFlares;
                private _dropped = [_carrierGroup,_carrier] call
                    ITW_CLASH_HALParadrop_fnc_Execute;
                if (_dropped) then {
                    _result = "HOT_PARADROP"
                } else {
                    if (([_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_Aboard) isNotEqualTo []) then {
                        _carrier land "GET OUT";
                        [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_Release;
                        _result = "LAND_FALLBACK"
                    } else {
                        _result = "HOT_PARADROP_DECLINED_EMPTY"
                    };
                };
            };
            default {
                _carrier land "GET OUT";
                [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_Release;
                _result = "LAND";
            };
        };
    };

    // One line answers the whole insertion question.
    diag_log format [
        "CLASH HAL UNLOAD | lift | group=%1 aircraft=%2 order=%3 param=%4 corridor=%5 mode=%6 result=%7 reason=%8 chance=%9 capacity=%10",
        if (isNull _cargoGroup) then {"<none>"} else {groupId _cargoGroup},
        if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
        _orderFile,_param,_state,_mode,_result,_reason,_chance,_capacity
    ];
    ["lift",[
        if (isNull _cargoGroup) then {"<none>"} else {groupId _cargoGroup},
        if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
        _orderFile,_param,_state,_mode,_result,_reason,_chance,_capacity
    ]] call ITW_CLASH_HALUnload_fnc_Log;
    _result
};

private _anchor = 'if (((group (assigneddriver _AV)) in (_HQ getVariable ["RydHQ_AirG",[]])) and (_unitG in (_HQ getVariable ["RydHQ_NCrewInfG",[]]))) then {_sts = ["true","(vehicle this) land ''GET OUT'';deletewaypoint [(group this), 0]"]};';

ITW_CLASH_HALUnload_fnc_PatchSource = {
    params ["_source","_orderFile"];
    private _anchor = 'if (((group (assigneddriver _AV)) in (_HQ getVariable ["RydHQ_AirG",[]])) and (_unitG in (_HQ getVariable ["RydHQ_NCrewInfG",[]]))) then {_sts = ["true","(vehicle this) land ''GET OUT'';deletewaypoint [(group this), 0]"]};';
    _source = (_source splitString (toString [13])) joinString "";

    private _at = _source find _anchor;
    if (_at < 0) exitWith {
        if ((_source find "ITW_CLASH_HALUnload_fnc_Unload") >= 0) then {
            [true,_source,"already-patched"]
        } else {
            [false,_source,"signature-missing"]
        }
    };
    private _tail = _at + count _anchor;
    if (((_source select [_tail]) find _anchor) >= 0) exitWith {
        [false,_source,"signature-duplicate"]
    };

    private _script =
        "private _g = group this; private _v = vehicle this; "
        + "if (isNil ""ITW_CLASH_HALUnload_fnc_Unload"") then {"
        + "_v land ""GET OUT""; "
        + "if (!isNil ""ITW_CLASH_HALParadrop_fnc_ReleaseCarrier"") then {"
        + "[_g,_v] call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier};"
        + "} else {[_g,_v," + str _orderFile + "] spawn ITW_CLASH_HALUnload_fnc_Unload}; "
        + "deletewaypoint [(group this), 0]";

    private _replacement =
        'if (((group (assigneddriver _AV)) in (_HQ getVariable ["RydHQ_AirG",[]])) and (_unitG in (_HQ getVariable ["RydHQ_NCrewInfG",[]]))) then {_sts = ["true",'
        + str _script + ']};';

    [
        true,
        (_source select [0,_at]) + _replacement + (_source select [_tail]),
        "patched"
    ]
};

private _finishFailure = {
    params ["_reason",["_details",[]]];
    ITW_CLASH_HALUnloadReady = false;
    diag_log format [
        "CLASH BOOT | WARNING | hal-unload-failed | reason=%1 details=%2 | stock HAL unload retained",
        _reason,_details
    ];
    false
};

// Wait for HAL Additions to publish the exact sources it replaced. This is
// earlier than the recon/service wrappers, so those wrappers capture the
// corrected executor rather than being overwritten by it.
private _deadline = diag_tickTime + 120;
waitUntil {
    sleep 0.05;
    (
        !isNil "RYD_Path"
        && {!isNil "CLASH_HALAdd_SourcePaths"}
        && {!isNil "HAL_GoAttInf"}
        && {!isNil "HAL_GoCapture"}
        && {!isNil "HAL_GoRecon"}
    ) || {diag_tickTime >= _deadline}
};
if (
    isNil "RYD_Path"
    || {isNil "CLASH_HALAdd_SourcePaths"}
    || {isNil "HAL_GoAttInf"}
) exitWith {
    ["hal-runtime-bind-timeout",[]] call _finishFailure
};

private _compiled = createHashMap;
private _sources = [];
private _failure = "";
{
    _x params ["_global","_file","_orderFile"];
    if (_failure isNotEqualTo "") then {continue};

    private _source = "";
    private _sourceLabel = "";
    if (
        _global isEqualTo "HAL_GoSFAttack"
        && {!isNil "ITW_CLASH_HALNativeSF_Source"}
    ) then {
        _source = ITW_CLASH_HALNativeSF_Source;
        _sourceLabel = "native-sf-repaired-source";
    } else {
        private _path = CLASH_HALAdd_SourcePaths getOrDefault [
            _global,
            RYD_Path + "HAL\" + _file
        ];
        _source = preprocessFileLineNumbers _path;
        _sourceLabel = _path;
    };

    if (_source isEqualTo "") then {
        _failure = format ["%1:source-missing",_orderFile];
    } else {
        ([_source,_orderFile] call ITW_CLASH_HALUnload_fnc_PatchSource) params [
            "_ok","_patched","_status"
        ];
        if (!_ok) then {
            _failure = format ["%1:%2",_orderFile,_status];
        } else {
            private _fn = compile _patched;
            if !(_fn isEqualType {}) then {
                _failure = format ["%1:compile-failed",_orderFile];
            } else {
                _compiled set [_global,_fn];
                _sources pushBack [_global,_sourceLabel,_status];
            };
        };
    };
} forEach ITW_CLASH_HALUnloadOrderSpecs;

if (_failure isNotEqualTo "") exitWith {
    [_failure,_sources] call _finishFailure
};

// All seven validated before the first global changes.
{
    _x params ["_global"];
    missionNamespace setVariable [_global,_compiled get _global];
} forEach ITW_CLASH_HALUnloadOrderSpecs;

// HALWaypointGuard may have won the scheduler race and patched these functions
// just before this source-based install. If so, reapply its orthogonal guard.
// If it has not run yet, it will patch the functions above in place later.
if (
    missionNamespace getVariable ["ITW_CLASH_HALWaypointGuardReady",false]
    && {!isNil "ITW_CLASH_HALWaypointGuard_fnc_Patch"}
) then {
    {
        [_x] call ITW_CLASH_HALWaypointGuard_fnc_Patch;
    } forEach ["HAL_GoCapture","HAL_GoRecon","HAL_GoAttInf","HAL_GoRest"];
};

ITW_CLASH_HALUnloadReady = true;
diag_log format [
    "CLASH BOOT | hal-unload-ready | version=%1 sites=%2 executionTime=true oneOwner=true halOwnsFlight=true hotDropOwnsMovement=false sources=%3",
    ITW_CLASH_HALUnloadVersion,count ITW_CLASH_HALUnloadOrderSpecs,_sources
];
true
