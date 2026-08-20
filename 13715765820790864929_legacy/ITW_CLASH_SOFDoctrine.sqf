#include "defines.hpp"

if (!isServer) exitWith {false};
ITW_CLASH_SOFDoctrineVersion = 1;

/*
    Shared SOF identity + C.L.A.S.H. anchor doctrine.

    Conventional infantry holds ground. SOF finds, screens, raids and kills.
    A positively identified SOF formation is never eligible for a C.L.A.S.H.
    objective anchor, even when no conventional anchor is available.

    This identity helper is synchronous so anchor selection cannot race the
    later Recon Phase 0 observer poll. It intentionally mirrors the established
    presence-based/latched Recon Phase 0 doctrine.
*/

ITW_CLASH_SOFTokenFamilies = [
    ["ranger",["ranger","rangers"]],
    ["seal",["seal","seals"]],
    ["fsb",["fsb"]],
    ["oss",["oss"]],
    ["viper",["viper"]]
];
ITW_CLASH_SOFClassPrefixes = [
    ["viper",["o_v_"]]
];
if (isNil "ITW_CLASH_SOFExactClasses") then {ITW_CLASH_SOFExactClasses = []};
if (isNil "ITW_CLASH_SOFDoctrineLogged") then {ITW_CLASH_SOFDoctrineLogged = []};

ITW_CLASH_SOF_fnc_Classify = {
    params ["_group"];
    if (isNull _group) exitWith {[false,"null-group",0,0,[]]};

    private _alive = (units _group) select {alive _x};
    private _classes = _alive apply {typeOf _x};

    // Explicit operator policy wins over every automatic/latching rule.
    private _manual = _group getVariable ["ITW_CLASH_ReconSOFManual",nil];
    if (!isNil "_manual" && {_manual isEqualType true}) exitWith {
        private _result = [
            _manual,
            if (_manual) then {"manual-allow"} else {"manual-deny"},
            if (_manual) then {1} else {0},
            count _alive,
            _classes
        ];
        _group setVariable ["ITW_CLASH_ReconSOF",_manual];
        _group setVariable ["ITW_CLASH_ReconSOFFamily",_result#1];
        if (_manual) then {
            _group setVariable ["ITW_CLASH_ReconSOFLatched",true];
            _group setVariable ["ITW_CLASH_ReconSOFLatchedFamily",_result#1];
        };
        _result
    };

    if (_alive isEqualTo []) exitWith {[false,"no-alive-units",0,0,[]]};

    if (_group getVariable ["ITW_CLASH_ReconSOFLatched",false]) exitWith {
        private _family = _group getVariable ["ITW_CLASH_ReconSOFLatchedFamily","sof"];
        _group setVariable ["ITW_CLASH_ReconSOF",true];
        _group setVariable ["ITW_CLASH_ReconSOFFamily",_family];
        [true,_family,0,count _alive,_classes]
    };

    private _configuredExact = +ITW_CLASH_SOFExactClasses;
    if (!isNil "ITW_CLASH_ReconSOFExactClasses") then {
        _configuredExact append ITW_CLASH_ReconSOFExactClasses;
    };
    _configuredExact = _configuredExact apply {toLowerANSI _x};

    private _exactMatched = _alive select {
        (toLowerANSI typeOf _x) in _configuredExact
    };
    if (_exactMatched isNotEqualTo []) exitWith {
        private _result = [true,"exact-class",count _exactMatched,count _alive,_classes];
        _group setVariable ["ITW_CLASH_ReconSOF",true];
        _group setVariable ["ITW_CLASH_ReconSOFFamily","exact-class"];
        _group setVariable ["ITW_CLASH_ReconSOFLatched",true];
        _group setVariable ["ITW_CLASH_ReconSOFLatchedFamily","exact-class"];
        _result
    };

    private _bestFamily = "";
    private _bestCount = 0;
    private _familiesPresent = [];

    {
        _x params ["_family","_prefixes"];
        private _matched = 0;
        {
            private _class = toLowerANSI typeOf _x;
            if ((_prefixes findIf {(_class find _x) == 0}) >= 0) then {
                _matched = _matched + 1;
            };
        } forEach _alive;
        if (_matched > 0) then {_familiesPresent pushBackUnique _family};
        if (_matched > _bestCount) then {
            _bestCount = _matched;
            _bestFamily = _family;
        };
    } forEach ITW_CLASH_SOFClassPrefixes;

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
        if (_matched > 0) then {_familiesPresent pushBackUnique _family};
        if (_matched > _bestCount) then {
            _bestCount = _matched;
            _bestFamily = _family;
        };
    } forEach ITW_CLASH_SOFTokenFamilies;

    private _isSOF = _bestCount > 0;
    private _family = if (!_isSOF) then {"non-sof"} else {
        if ((count _familiesPresent) > 1) then {"mixed-sof"} else {_bestFamily}
    };

    _group setVariable ["ITW_CLASH_ReconSOF",_isSOF];
    _group setVariable ["ITW_CLASH_ReconSOFFamily",_family];
    if (_isSOF) then {
        _group setVariable ["ITW_CLASH_ReconSOFLatched",true];
        _group setVariable ["ITW_CLASH_ReconSOFLatchedFamily",_family];
        if !(_group in ITW_CLASH_SOFDoctrineLogged) then {
            ITW_CLASH_SOFDoctrineLogged pushBack _group;
            ["sof-doctrine-detected",[
                [_group] call ITW_CLASH_fnc_GroupId,
                _family,
                _bestCount,
                count _alive,
                _classes
            ]] call ITW_CLASH_fnc_Log;
        };
    };

    [_isSOF,_family,_bestCount,count _alive,_classes]
};

ITW_CLASH_SOF_fnc_IsSOF = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    ([_group] call ITW_CLASH_SOF_fnc_Classify)#0
};

// Preserve the corrected V6 anchor implementations below the policy bridge.
ITW_CLASH_fnc_SelectAnchorGroup_SOFBase = ITW_CLASH_fnc_SelectAnchorGroup;
ITW_CLASH_fnc_AuditAnchors_SOFBase = ITW_CLASH_fnc_AuditAnchors;

ITW_CLASH_fnc_SelectAnchorGroup = {
    // Keep the canonical scoring/strength logic untouched. Present it a
    // synchronous view containing only conventional formations, then restore the
    // managed set before returning. There is deliberately no SOF fallback.
    private _snapshot = +ITW_CLASH_ManagedGroups;
    private _sofExcluded = _snapshot select {
        !isNull _x && {[_x] call ITW_CLASH_SOF_fnc_IsSOF}
    };

    ITW_CLASH_ManagedGroups = _snapshot - _sofExcluded;
    private _selected = _this call ITW_CLASH_fnc_SelectAnchorGroup_SOFBase;
    ITW_CLASH_ManagedGroups = _snapshot;

    if (_sofExcluded isNotEqualTo []) then {
        ["anchor-sof-excluded",[
            _this param [0,-1],
            _sofExcluded apply {[
                [_x] call ITW_CLASH_fnc_GroupId,
                _x getVariable ["ITW_CLASH_ReconSOFFamily","sof"]
            ]},
            if (isNull _selected) then {"<none>"} else {[_selected] call ITW_CLASH_fnc_GroupId}
        ]] call ITW_CLASH_fnc_Log;
    };
    _selected
};

ITW_CLASH_fnc_AuditAnchors = {
    // If a SOF formation was anchored by an older state/save or by a race before
    // this policy became authoritative, demote it before the canonical audit.
    private _demoted = [];
    {
        private _group = _x;
        if (isNull _group) then {continue};
        private _anchorObjective = _group getVariable ["ITW_CLASH_AnchorObjective",-1];
        if (_anchorObjective < 0) then {continue};
        if !([_group] call ITW_CLASH_SOF_fnc_IsSOF) then {continue};

        [_anchorObjective,"sof-ineligible"] call ITW_CLASH_fnc_ClearAnchorSlot;
        _demoted pushBack [
            _anchorObjective,
            [_group] call ITW_CLASH_fnc_GroupId,
            _group getVariable ["ITW_CLASH_ReconSOFFamily","sof"]
        ];
    } forEach +ITW_CLASH_ManagedGroups;

    if (_demoted isNotEqualTo []) then {
        ["anchor-sof-demoted",_demoted] call ITW_CLASH_fnc_Log;
    };

    call ITW_CLASH_fnc_AuditAnchors_SOFBase
};

diag_log format [
    "CLASH BOOT | sof-doctrine-ready | version=%1 presenceBased=true latched=true anchors=false emergencyFallback=false",
    ITW_CLASH_SOFDoctrineVersion
];

true
