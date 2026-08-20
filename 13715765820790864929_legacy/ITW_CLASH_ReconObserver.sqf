#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_ReconPhase0Started",false]) exitWith {};
ITW_CLASH_ReconPhase0Started = true;
ITW_CLASH_ReconPhase0Version = 1;

/*
    C.L.A.S.H. Recon Phase 0 — SOF observation and native HAL task gate.

    Doctrine:
    - Only SOF may receive dedicated HAL reconnaissance missions.
    - Ordinary combat groups may still discover/report enemies naturally.
    - HAL still decides whether/when reconnaissance is required.
    - Impasse/C.L.A.S.H. does not spawn, purchase, replace, or requisition SOF here.
    - Phase 0 does not force SOF into recon-only duty; Rangers/SEALs/FSB/OSS remain
      available for their other HAL tasks unless HAL itself selects them for recon.

    This module uses HAL's native GoRecon / GoDefRecon implementations. It adds
    a mission-side eligibility gate and telemetry without repacking NR6.
*/

ITW_CLASH_ReconSOFTokenFamilies = [
    ["ranger",["ranger","rangers"]],
    ["seal",["seal","seals"]],
    ["fsb",["fsb"]],
    ["oss",["oss"]]
];
ITW_CLASH_ReconSOFExactClasses = [];
ITW_CLASH_ReconPollInterval = 5;
ITW_CLASH_ReconActiveGroups = createHashMap;
ITW_CLASH_ReconSpecForWarned = [];
ITW_CLASH_ReconDetectedLogged = [];

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

ITW_CLASH_Recon_fnc_ClassifySOFGroup = {
    params ["_group"];
    if (isNull _group) exitWith {[false,"null-group",0,0,[]]};

    private _manual = _group getVariable ["ITW_CLASH_ReconSOFManual",nil];
    if (!isNil "_manual" && {_manual isEqualType true}) exitWith {
        [_manual,if (_manual) then {"manual-allow"} else {"manual-deny"},0,{alive _x} count units _group,(units _group) apply {typeOf _x}]
    };

    private _alive = (units _group) select {alive _x};
    if (_alive isEqualTo []) exitWith {[false,"no-alive-units",0,0,[]]};

    private _classes = _alive apply {typeOf _x};
    private _exactMatched = _alive select {
        (toLowerANSI typeOf _x) in (ITW_CLASH_ReconSOFExactClasses apply {toLowerANSI _x})
    };
    if (_exactMatched isNotEqualTo []) exitWith {
        private _needed = ceil ((count _alive) * 0.5);
        private _count = count _exactMatched;
        [_count >= _needed,"exact-class",_count,count _alive,_classes]
    };

    private _bestFamily = "";
    private _bestCount = 0;
    {
        _x params ["_family","_aliases"];
        private _matched = 0;
        {
            private _cfg = configFile >> "CfgVehicles" >> typeOf _x;
            private _identity = toLowerANSI ([
                typeOf _x,
                getText (_cfg >> "displayName"),
                getText (_cfg >> "faction"),
                getText (_cfg >> "editorSubcategory"),
                getText (_cfg >> "vehicleClass")
            ] joinString " ");
            private _words = _identity splitString " _-/\\.:()[]{}";
            if ((_aliases findIf {_x in _words}) >= 0) then {
                _matched = _matched + 1;
            };
        } forEach _alive;
        if (_matched > _bestCount) then {
            _bestCount = _matched;
            _bestFamily = _family;
        };
    } forEach ITW_CLASH_ReconSOFTokenFamilies;

    // Majority classification prevents one embedded SOF/specialist unit from
    // turning an otherwise conventional squad into a dedicated recon asset.
    private _required = ceil ((count _alive) * 0.5);
    private _isSOF = _bestCount >= _required;
    [
        _isSOF,
        if (_isSOF) then {_bestFamily} else {"non-sof"},
        _bestCount,
        count _alive,
        _classes
    ]
};

ITW_CLASH_Recon_fnc_MarkSOF = {
    params ["_group","_classification"];
    if (isNull _group) exitWith {};
    _group setVariable ["ITW_CLASH_ReconSOF",_classification#0];
    _group setVariable ["ITW_CLASH_ReconSOFFamily",_classification#1];

    if ((_classification#0) && {!(_group in ITW_CLASH_ReconDetectedLogged)}) then {
        ITW_CLASH_ReconDetectedLogged pushBack _group;
        ["sof-detected",[
            [_group] call ITW_CLASH_Recon_fnc_GroupId,
            _classification#1,
            _classification#2,
            _classification#3,
            _classification#4
        ]] call ITW_CLASH_Recon_fnc_Log;
    };
};

ITW_CLASH_Recon_fnc_BlockNativeMission = {
    params ["_mode","_group","_hq","_classification"];
    if (!isNull _group) then {
        _group setVariable ["Busy" + str _group,false];
        _group setVariable ["ITW_CLASH_ReconPhase0Active",nil];
        _group setVariable ["ITW_CLASH_ReconPhase0Mode",nil];
    };

    ["blocked-nonsof",[
        if (isNull _group) then {"<null>"} else {[_group] call ITW_CLASH_Recon_fnc_GroupId},
        _mode,
        _classification#1,
        _classification#2,
        _classification#3,
        _classification#4
    ]] call ITW_CLASH_Recon_fnc_Log;

    // HQOrdersDef appends the group to RecDefSpot immediately after spawning
    // GoDefRecon. Remove a rejected candidate after that bookkeeping write has
    // occurred so it cannot become a permanent phantom defensive-recon slot.
    if (_mode isEqualTo "defensive" && {!isNull _hq}) then {
        [_group,_hq] spawn {
            params ["_group","_hq"];
            sleep 0.25;
            if (!isNull _hq) then {
                _hq setVariable [
                    "RydHQ_RecDefSpot",
                    (_hq getVariable ["RydHQ_RecDefSpot",[]]) - [_group]
                ];
            };
        };
    };
    false
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
    params ["_mode","_group","_hq","_destination","_classification"];
    if (isNull _group || {isNull _hq}) exitWith {};
    _group setVariable ["ITW_CLASH_ReconPhase0Active",true];
    _group setVariable ["ITW_CLASH_ReconPhase0Mode",_mode];
    ITW_CLASH_ReconActiveGroups set [str _group,[_group,_mode,time]];

    ["assigned",[
        [_group] call ITW_CLASH_Recon_fnc_GroupId,
        _mode,
        _classification#1,
        {alive _x} count units _group,
        round (leader _group distance2D _destination),
        _destination
    ]] call ITW_CLASH_Recon_fnc_Log;
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
    scriptName "ITW_CLASH_ReconPhase0";

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
        diag_log "CLASH BOOT | recon-phase0-deferred | HAL not ready; baseline HAL recon retained";
    };
    if (isNil "HAL_GoRecon" || {isNil "HAL_GoDefRecon"}) exitWith {
        ITW_CLASH_ReconPhase0Started = false;
        diag_log "CLASH BOOT | recon-phase0-fail-open | native HAL recon functions unavailable";
    };

    ITW_CLASH_Recon_fnc_NativeGoRecon = HAL_GoRecon;
    ITW_CLASH_Recon_fnc_NativeGoDefRecon = HAL_GoDefRecon;

    HAL_GoRecon = {
        private _group = _this param [0,grpNull];
        private _destination = _this param [1,[]];
        private _hq = _this param [3,grpNull];
        private _classification = [_group] call ITW_CLASH_Recon_fnc_ClassifySOFGroup;
        [_group,_classification] call ITW_CLASH_Recon_fnc_MarkSOF;
        if !(_classification#0) exitWith {
            ["offensive",_group,_hq,_classification] call ITW_CLASH_Recon_fnc_BlockNativeMission
        };

        private _startedAt = time;
        ["offensive",_group,_hq,_destination,_classification] call ITW_CLASH_Recon_fnc_BeginMission;
        private _result = _this call ITW_CLASH_Recon_fnc_NativeGoRecon;
        ["offensive",_group,_startedAt] call ITW_CLASH_Recon_fnc_EndMission;
        _result
    };

    HAL_GoDefRecon = {
        private _group = _this param [0,grpNull];
        private _destination = _this param [1,[]];
        private _hq = _this param [3,grpNull];
        private _classification = [_group] call ITW_CLASH_Recon_fnc_ClassifySOFGroup;
        [_group,_classification] call ITW_CLASH_Recon_fnc_MarkSOF;
        if !(_classification#0) exitWith {
            ["defensive",_group,_hq,_classification] call ITW_CLASH_Recon_fnc_BlockNativeMission
        };

        private _startedAt = time;
        ["defensive",_group,_hq,_destination,_classification] call ITW_CLASH_Recon_fnc_BeginMission;
        private _result = _this call ITW_CLASH_Recon_fnc_NativeGoDefRecon;
        ["defensive",_group,_startedAt] call ITW_CLASH_Recon_fnc_EndMission;
        _result
    };

    diag_log format [
        "CLASH BOOT | recon-phase0-ready | version=%1 sofOnly=true nativeHAL=true spawning=false requisition=false",
        ITW_CLASH_ReconPhase0Version
    ];

    // First-line offensive filter. HAL's native defensive-recon candidate list
    // does not honor NoRecon, so the wrappers above remain the authoritative
    // last-line gate for both paths.
    while {
        isNil "ITW_GameOver" || {!ITW_GameOver}
    } do {
        sleep ITW_CLASH_ReconPollInterval;
        if !(missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]) then {continue};
        if !(missionNamespace getVariable ["ITW_CLASH_HALReady",false]) then {continue};
        if (isNull ITW_CLASH_HALHQ) then {continue};

        private _managed = +ITW_CLASH_ManagedGroups;
        private _nonSOF = [];
        {
            private _group = _x;
            if (isNull _group || {{alive _x} count units _group == 0}) then {continue};
            private _classification = [_group] call ITW_CLASH_Recon_fnc_ClassifySOFGroup;
            [_group,_classification] call ITW_CLASH_Recon_fnc_MarkSOF;
            if (_classification#0) then {
                if (_group in (ITW_CLASH_HALHQ getVariable ["RydHQ_SpecForG",[]]) && {
                    !(_group in ITW_CLASH_ReconSpecForWarned)
                }) then {
                    ITW_CLASH_ReconSpecForWarned pushBack _group;
                    ["sof-native-specfor-excluded",[
                        [_group] call ITW_CLASH_Recon_fnc_GroupId,
                        _classification#1,
                        _classification#4
                    ]] call ITW_CLASH_Recon_fnc_Log;
                };
            } else {
                _nonSOF pushBack _group;
            };
        } forEach _managed;

        private _noRecon = +(ITW_CLASH_HALHQ getVariable ["RydHQ_NoRecon",[]]);
        {
            _noRecon pushBackUnique _x;
        } forEach _nonSOF;
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoRecon",_noRecon];

        ITW_CLASH_ReconDetectedLogged = ITW_CLASH_ReconDetectedLogged select {
            !isNull _x && {{alive _x} count units _x > 0}
        };
        ITW_CLASH_ReconSpecForWarned = ITW_CLASH_ReconSpecForWarned select {
            !isNull _x && {{alive _x} count units _x > 0}
        };
    };

    ITW_CLASH_ReconPhase0Started = false;
    diag_log "CLASH BOOT | recon-phase0-stopped";
};

true
