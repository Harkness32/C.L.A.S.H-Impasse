#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_ReconPlanningBridgeStarted",false]) exitWith {};
ITW_CLASH_ReconPlanningBridgeStarted = true;
ITW_CLASH_ReconPlanningBridgeVersion = 4;

/*
    C.L.A.S.H. 1.0 HAL planning bridge

    Native HAL already has the doctrine we want: ReconAv is a broad capability
    pool and RydHQ_SpecForG is explicitly subtracted from ordinary reconnaissance
    and conventional tasking. C.L.A.S.H. therefore does not create a SOF-only
    recon pool or rewrite HAL's normal recon candidate lists.

    Impasse faction classes are not guaranteed to appear in HAL's stock SpecFor
    class table. Immediately before native HQOrders/HQOrdersDef, this bridge adds
    only C.L.A.S.H.-recognized SOF formations belonging to that exact HAL HQ.

    Version 4 is commander-scoped for Dual-HAL. Commander A and Commander B have
    separate semantic SpecFor snapshots/signatures and can never import a group
    from the opposite side. Native HAL memberships remain the base and are never
    removed unless C.L.A.S.H. itself injected them on an earlier planning pass.
*/

ITW_CLASH_ReconPlanning_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["recon-bridge-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_ReconPlanning_fnc_GetCommanderCandidates = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};

    private _candidates = [];
    if (!isNil "ITW_CLASH_ManagedGroups") then {
        _candidates append ITW_CLASH_ManagedGroups;
    };
    if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
        _candidates append ITW_CLASH_DualHALBLUFORGroups;
    };
    if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
        _candidates append ITW_CLASH_DualHALOPFORExtraGroups;
    };
    _candidates = _candidates arrayIntersect _candidates;

    private _hqSide = side _hq;
    _candidates select {
        private _group = _x;
        !isNull _group && {
            side _group == _hqSide && {
                _group getVariable ["ITW_CLASH_Managed",false] || {
                    _group getVariable ["ITW_CLASH_DualHALManaged",false]
                }
            }
        }
    }
};

ITW_CLASH_ReconPlanning_fnc_SyncSpecFor = {
    params [["_hq",grpNull],["_mode","planning"]];
    if (isNull _hq || {isNil "ITW_CLASH_SOF_fnc_Classify"}) exitWith {[]};

    private _specFor = +(_hq getVariable ["RydHQ_SpecForG",[]]);
    private _previousSemantic = +(_hq getVariable [
        "ITW_CLASH_ReconPlanningSemanticSpecFor",
        []
    ]);
    _previousSemantic = _previousSemantic select {!isNull _x};

    // Recover v2/v3 semantic tags only when the tagged group actually belongs
    // to this HQ's side. This prevents a global HAL planner wrapper from leaking
    // Commander A semantic identity into Commander B or vice versa.
    {
        if (
            side _x == side _hq && {
                _x getVariable ["ITW_CLASH_SOFNativeProtected",false]
            }
        ) then {
            _previousSemantic pushBackUnique _x;
        };
    } forEach _specFor;

    // Remove only memberships previously injected by C.L.A.S.H. Any SpecFor
    // group native HAL supplied independently remains untouched.
    _specFor = _specFor - _previousSemantic;

    private _semanticSOF = [];
    private _candidates = [_hq] call ITW_CLASH_ReconPlanning_fnc_GetCommanderCandidates;

    {
        private _group = _x;
        if (isNull _group || {{alive _x} count units _group == 0}) then {continue};

        private _classification = [_group] call ITW_CLASH_SOF_fnc_Classify;
        if !(_classification#0) then {continue};

        _semanticSOF pushBackUnique _group;
        _specFor pushBackUnique _group;
        _group setVariable ["ITW_CLASH_SOFNativeProtected",true];
    } forEach _candidates;

    {
        if !(_x in _semanticSOF) then {
            _x setVariable ["ITW_CLASH_SOFNativeProtected",nil];
        };
    } forEach _previousSemantic;

    _hq setVariable ["RydHQ_SpecForG",_specFor];
    _hq setVariable ["ITW_CLASH_ReconPlanningSemanticSpecFor",+_semanticSOF];

    private _signature = str (_semanticSOF apply {
        [
            [_x] call ITW_CLASH_fnc_GroupId,
            _x getVariable ["ITW_CLASH_ReconSOFFamily","sof"]
        ]
    });
    private _previousSignature = _hq getVariable [
        "ITW_CLASH_ReconPlanningSpecForSignature",
        ""
    ];
    if (_signature != _previousSignature) then {
        _hq setVariable ["ITW_CLASH_ReconPlanningSpecForSignature",_signature];
        ["specfor-sync",[
            _mode,
            _hq getVariable ["RydHQ_CodeSign","?"],
            side _hq,
            count _semanticSOF,
            count _specFor,
            _semanticSOF apply {[
                [_x] call ITW_CLASH_fnc_GroupId,
                _x getVariable ["ITW_CLASH_ReconSOFFamily","sof"]
            ]},
            (_previousSemantic - _semanticSOF) apply {
                [_x] call ITW_CLASH_fnc_GroupId
            }
        ]] call ITW_CLASH_ReconPlanning_fnc_Log;
    };

    _semanticSOF
};

[] spawn {
    scriptName "ITW_CLASH_ReconPlanningBridge";

    private _deadline = time + 120;
    waitUntil {
        sleep 0.1;
        (
            missionNamespace getVariable ["ITW_CLASH_HALReady",false]
            && {!isNil "HAL_HQOrders"}
            && {!isNil "HAL_HQOrdersDef"}
            && {!isNil "ITW_CLASH_SOF_fnc_Classify"}
            && {!isNil "ITW_CLASH_Recon_fnc_NativeGoRecon"}
            && {!isNil "ITW_CLASH_Recon_fnc_NativeGoDefRecon"}
        ) || {time > _deadline}
    };

    if (isNil "HAL_HQOrders" || {isNil "HAL_HQOrdersDef"}) exitWith {
        ITW_CLASH_ReconPlanningBridgeStarted = false;
        diag_log "CLASH BOOT | recon-planning-bridge-fail-open | native HAL planners unavailable";
    };
    if (isNil "ITW_CLASH_SOF_fnc_Classify") exitWith {
        ITW_CLASH_ReconPlanningBridgeStarted = false;
        diag_log "CLASH BOOT | recon-planning-bridge-fail-open | shared SOF doctrine unavailable";
    };

    ITW_CLASH_ReconPlanning_fnc_NativeHQOrders = HAL_HQOrders;
    ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef = HAL_HQOrdersDef;

    HAL_HQOrders = {
        private _hq = _this param [0,grpNull];
        [_hq,"offensive"] call ITW_CLASH_ReconPlanning_fnc_SyncSpecFor;
        _this call ITW_CLASH_ReconPlanning_fnc_NativeHQOrders
    };

    HAL_HQOrdersDef = {
        private _hq = _this param [0,grpNull];
        [_hq,"defensive"] call ITW_CLASH_ReconPlanning_fnc_SyncSpecFor;
        _this call ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef
    };

    diag_log format [
        "CLASH BOOT | recon-planning-bridge-ready | version=%1 nativeBroadRecon=true semanticSpecForBridge=true commanderScoped=true staleSemanticRemoval=true reconPoolMutation=false noReconMutation=false friendsMutation=false halChooses=true",
        ITW_CLASH_ReconPlanningBridgeVersion
    ];
};

// Required 1.0 burn-in hardening is a separate late runtime overlay. It waits
// for GTFO/CASEVAC/HAL surfaces internally, so scheduling it here does not seize
// planning authority or depend on load order beyond this required bridge.
if (fileExists "ITW_CLASH_OneZeroHardening.sqf") then {
    [] execVM "ITW_CLASH_OneZeroHardening.sqf";
    diag_log "CLASH BOOT | one-zero-hardening-scheduled";
} else {
    diag_log "CLASH BOOT | WARNING | one-zero-hardening-missing";
};