#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_ReconPhase0Started",false]) exitWith {};

ITW_CLASH_ReconPhase0Started = true;
ITW_CLASH_ReconPhase0Version = 2;
ITW_CLASH_ReconPollInterval = 2;
ITW_CLASH_ReconActiveGroups = createHashMap;

/*
    C.L.A.S.H. 1.0 reconnaissance doctrine

    HAL owns reconnaissance selection and execution. C.L.A.S.H. no longer turns
    reconnaissance into a SOF-only job and no longer rejects conventional groups
    selected by native HAL. Native HAL's own ReconAv construction decides which
    formations are reconnaissance-capable.

    SOF identity is protected separately by the planning bridge, which keeps
    semantically recognized SOF in RydHQ_SpecForG before HAL plans. Native HAL
    deliberately subtracts SpecForG from its ordinary reconnaissance pool.

    This file therefore observes native GoRecon/GoDefRecon only. It does not
    spawn units, spend tickets, alter HAL candidate lists, reveal targets, or
    create a second reconnaissance implementation.
*/

ITW_CLASH_Recon_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["recon-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_Recon_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_fnc_GroupId
    };
    str _group
};

ITW_CLASH_Recon_fnc_Classify = {
    params ["_group"];
    if (isNull _group) exitWith {[false,"null-group",0,0,[]]};
    if (!isNil "ITW_CLASH_SOF_fnc_Classify") exitWith {
        [_group] call ITW_CLASH_SOF_fnc_Classify
    };
    [false,"unclassified",0,{alive _x} count units _group,(units _group) apply {typeOf _x}]
};

ITW_CLASH_Recon_fnc_MonitorMission = {
    params ["_mode","_group","_hq"];
    if (isNull _group || {isNull _hq}) exitWith {};

    private _seen = [];
    private _knownAtStart = +(_hq getVariable ["RydHQ_KnEnemies",[]]);
    while {
        !isNull _group && {
            !isNull _hq && {
                (_group getVariable ["ITW_CLASH_ReconPhase0Active",false]) && {
                    {alive _x} count units _group > 0
                }
            }
        }
    } do {
        sleep ITW_CLASH_ReconPollInterval;
        if (isNull _group || {isNull _hq}) then {continue};

        private _targets = [];
        {
            if (isNull _x) then {continue};
            {
                if (alive _x) then {
                    _targets pushBackUnique (vehicle _x);
                };
            } forEach units _x;
        } forEach (_hq getVariable ["RydHQ_Enemies",[]]);

        {
            private _target = _x;
            if (isNull _target || {!alive _target} || {_target in _seen}) then {continue};

            private _knowledge = 0;
            {
                if (alive _x) then {
                    _knowledge = _knowledge max (_x knowsAbout _target);
                };
            } forEach units _group;
            if (_knowledge < 0.05) then {continue};

            _seen pushBack _target;
            private _globallyKnown = _target in (_hq getVariable ["RydHQ_KnEnemies",[]]);
            ["contact",[
                [_group] call ITW_CLASH_Recon_fnc_GroupId,
                _mode,
                typeOf _target,
                round (leader _group distance2D _target),
                _knowledge,
                _globallyKnown
            ]] call ITW_CLASH_Recon_fnc_Log;

            if (_globallyKnown && {!(_target in _knownAtStart)}) then {
                ["intel-gained",[
                    [_group] call ITW_CLASH_Recon_fnc_GroupId,
                    _mode,
                    typeOf _target,
                    round (leader _group distance2D _target),
                    _knowledge
                ]] call ITW_CLASH_Recon_fnc_Log;
                _knownAtStart pushBack _target;
            };
        } forEach _targets;
    };
};

ITW_CLASH_Recon_fnc_BeginMission = {
    params ["_mode","_group","_hq","_destination"];
    if (isNull _group || {isNull _hq}) exitWith {};

    private _classification = [_group] call ITW_CLASH_Recon_fnc_Classify;
    private _isSOF = _classification#0;
    _group setVariable ["ITW_CLASH_ReconPhase0Active",true];
    _group setVariable ["ITW_CLASH_ReconPhase0Mode",_mode];
    ITW_CLASH_ReconActiveGroups set [str _group,[_group,_mode,time]];

    ["assigned",[
        [_group] call ITW_CLASH_Recon_fnc_GroupId,
        _mode,
        _classification#1,
        _isSOF,
        {alive _x} count units _group,
        round (leader _group distance2D _destination),
        _destination
    ]] call ITW_CLASH_Recon_fnc_Log;

    if (_isSOF) then {
        ["unexpected-specfor-assignment",[
            [_group] call ITW_CLASH_Recon_fnc_GroupId,
            _mode,
            _classification#1,
            _group in (_hq getVariable ["RydHQ_SpecForG",[]])
        ]] call ITW_CLASH_Recon_fnc_Log;
    };

    [_mode,_group,_hq] spawn ITW_CLASH_Recon_fnc_MonitorMission;
};

ITW_CLASH_Recon_fnc_EndMission = {
    params ["_mode","_group","_startedAt"];
    if (isNull _group) exitWith {};

    _group setVariable ["ITW_CLASH_ReconPhase0Active",nil];
    _group setVariable ["ITW_CLASH_ReconPhase0Mode",nil];
    ITW_CLASH_ReconActiveGroups deleteAt (str _group);

    private _alive = {alive _x} count units _group;
    private _event = if (_alive == 0) then {"wiped"} else {
        if (_group getVariable ["ITW_CLASH_Withdrawing",false]) then {"aborted"} else {"complete"}
    };
    [_event,[
        [_group] call ITW_CLASH_Recon_fnc_GroupId,
        _mode,
        _alive,
        round (time - _startedAt)
    ]] call ITW_CLASH_Recon_fnc_Log;
};

[] spawn {
    scriptName "ITW_CLASH_ReconObserver";

    private _deadline = time + 120;
    waitUntil {
        sleep 0.25;
        (
            missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]
            && {missionNamespace getVariable ["ITW_CLASH_HALReady",false]}
            && {!isNil "HAL_GoRecon"}
            && {!isNil "HAL_GoDefRecon"}
        ) || {time > _deadline}
    };

    if !(missionNamespace getVariable ["ITW_CLASH_HALReady",false]) exitWith {
        ITW_CLASH_ReconPhase0Started = false;
        diag_log "CLASH BOOT | recon-observer-deferred | HAL not ready; native HAL recon retained";
    };
    if (isNil "HAL_GoRecon" || {isNil "HAL_GoDefRecon"}) exitWith {
        ITW_CLASH_ReconPhase0Started = false;
        diag_log "CLASH BOOT | recon-observer-fail-open | native HAL recon functions unavailable";
    };

    ITW_CLASH_Recon_fnc_NativeGoRecon = HAL_GoRecon;
    ITW_CLASH_Recon_fnc_NativeGoDefRecon = HAL_GoDefRecon;

    HAL_GoRecon = {
        private _group = _this param [0,grpNull];
        private _destination = _this param [1,[]];
        private _hq = _this param [3,grpNull];
        if (isNull _hq) then {
            _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
        };

        private _startedAt = time;
        ["offensive",_group,_hq,_destination] call ITW_CLASH_Recon_fnc_BeginMission;
        _this call ITW_CLASH_Recon_fnc_NativeGoRecon;
        ["offensive",_group,_startedAt] call ITW_CLASH_Recon_fnc_EndMission;
        true
    };

    HAL_GoDefRecon = {
        private _group = _this param [0,grpNull];
        private _destination = _this param [1,[]];
        private _hq = _this param [3,grpNull];
        if (isNull _hq) then {
            _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
        };

        private _startedAt = time;
        ["defensive",_group,_hq,_destination] call ITW_CLASH_Recon_fnc_BeginMission;
        _this call ITW_CLASH_Recon_fnc_NativeGoDefRecon;
        ["defensive",_group,_startedAt] call ITW_CLASH_Recon_fnc_EndMission;
        true
    };

    diag_log format [
        "CLASH BOOT | recon-observer-ready | version=%1 nativeBroadRecon=true observerOnly=true specForExcludedByHAL=true spawning=false requisition=false reveal=false",
        ITW_CLASH_ReconPhase0Version
    ];
};
