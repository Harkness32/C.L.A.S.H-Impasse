#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_ReconPlanningBridgeStarted",false]) exitWith {};
ITW_CLASH_ReconPlanningBridgeStarted = true;
ITW_CLASH_ReconPlanningBridgeVersion = 2;

/*
    C.L.A.S.H. 1.0 HAL planning bridge

    Native HAL already has the doctrine we want: ReconAv is a broad capability
    pool and RydHQ_SpecForG is explicitly subtracted from ordinary reconnaissance
    and conventional tasking. C.L.A.S.H. therefore no longer opens a temporary
    SOF-only recon window, touches ReconG, blocks conventional scouts, or rewrites
    Friends/NoRecon/NoDef around each planning call.

    The only compatibility work retained here is semantic SOF identity. Impasse
    faction classes are not guaranteed to appear in HAL's stock SpecFor class
    table, so immediately before native HQOrders/HQOrdersDef runs we add every
    C.L.A.S.H.-recognized SOF formation to that HQ's RydHQ_SpecForG. HAL then
    performs all normal selection using its own native exclusions and routines.
*/

ITW_CLASH_ReconPlanning_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["recon-bridge-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_ReconPlanning_fnc_SyncSpecFor = {
    params [["_hq",grpNull],["_mode","planning"]];
    if (isNull _hq || {isNil "ITW_CLASH_SOF_fnc_Classify"}) exitWith {[]};

    private _specFor = +(_hq getVariable ["RydHQ_SpecForG",[]]);
    private _semanticSOF = [];

    {
        private _group = _x;
        if (isNull _group || {{alive _x} count units _group == 0}) then {continue};
        if !(_group getVariable ["ITW_CLASH_Managed",false]) then {continue};

        private _classification = [_group] call ITW_CLASH_SOF_fnc_Classify;
        if !(_classification#0) then {continue};

        _semanticSOF pushBackUnique _group;
        _specFor pushBackUnique _group;
        _group setVariable ["ITW_CLASH_SOFNativeProtected",true];
    } forEach +ITW_CLASH_ManagedGroups;

    _hq setVariable ["RydHQ_SpecForG",_specFor];

    private _signature = str (_semanticSOF apply {
        [
            [_x] call ITW_CLASH_fnc_GroupId,
            _x getVariable ["ITW_CLASH_ReconSOFFamily","sof"]
        ]
    });
    if (_signature != missionNamespace getVariable ["ITW_CLASH_ReconPlanningSpecForSignature",""]) then {
        ITW_CLASH_ReconPlanningSpecForSignature = _signature;
        ["specfor-sync",[
            _mode,
            count _semanticSOF,
            count _specFor,
            _semanticSOF apply {[
                [_x] call ITW_CLASH_fnc_GroupId,
                _x getVariable ["ITW_CLASH_ReconSOFFamily","sof"]
            ]}
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
        "CLASH BOOT | recon-planning-bridge-ready | version=%1 nativeBroadRecon=true semanticSpecForBridge=true reconPoolMutation=false noReconMutation=false friendsMutation=false halChooses=true",
        ITW_CLASH_ReconPlanningBridgeVersion
    ];
};
