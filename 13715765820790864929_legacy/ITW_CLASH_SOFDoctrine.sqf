#include "defines.hpp"

if (!isServer) exitWith {false};
ITW_CLASH_SOFDoctrineVersion = 1;
ITW_CLASH_SOFClassifierVersion = 2;

/*
    Shared SOF identity + C.L.A.S.H. anchor doctrine.

    Conventional infantry holds ground. SOF screens the rear and performs
    special operations. A positively identified SOF formation is never eligible
    for a C.L.A.S.H. objective anchor.

    Classifier v2 uses the immutable native Impasse spawn archetype whenever it
    exists. One SOF-class specialist embedded in an otherwise conventional
    formation must not turn the whole group into SpecFor. Automatic SOF identity
    therefore requires a majority of the formation template to resolve to the
    same SOF family. Explicit group policy still wins.
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
    private _aliveClasses = _alive apply {typeOf _x};

    // Explicit operator policy wins over every automatic/latching rule.
    private _manual = _group getVariable ["ITW_CLASH_ReconSOFManual",nil];
    if (!isNil "_manual" && {_manual isEqualType true}) exitWith {
        private _family = if (_manual) then {"manual-allow"} else {"manual-deny"};
        _group setVariable ["ITW_CLASH_ReconSOF",_manual];
        _group setVariable ["ITW_CLASH_ReconSOFFamily",_family];
        _group setVariable ["ITW_CLASH_ReconSOFClassifierVersion",ITW_CLASH_SOFClassifierVersion];
        if (_manual) then {
            _group setVariable ["ITW_CLASH_ReconSOFLatched",true];
            _group setVariable ["ITW_CLASH_ReconSOFLatchedFamily",_family];
        } else {
            _group setVariable ["ITW_CLASH_ReconSOFLatched",nil];
            _group setVariable ["ITW_CLASH_ReconSOFLatchedFamily",nil];
        };
        [_manual,_family,if (_manual) then {1} else {0},count _alive,_aliveClasses]
    };

    private _spawnClasses = +(_group getVariable ["ITW_CLASH_SpawnArchetype",[]]);
    private _sourceClasses = if (_spawnClasses isNotEqualTo []) then {
        _spawnClasses
    } else {
        _aliveClasses
    };
    private _sourceCount = count _sourceClasses;
    if (_sourceCount < 1) exitWith {[false,"no-identity-source",0,0,[]]};

    // A v2 latch is safe because it was produced by the composition classifier.
    // Older presence-based latches are deliberately re-evaluated and may clear.
    if (
        _group getVariable ["ITW_CLASH_ReconSOFLatched",false] &&
        {(_group getVariable ["ITW_CLASH_ReconSOFClassifierVersion",0]) >= ITW_CLASH_SOFClassifierVersion}
    ) exitWith {
        private _family = _group getVariable ["ITW_CLASH_ReconSOFLatchedFamily","sof"];
        _group setVariable ["ITW_CLASH_ReconSOF",true];
        _group setVariable ["ITW_CLASH_ReconSOFFamily",_family];
        [true,_family,_sourceCount,_sourceCount,_sourceClasses]
    };

    private _configuredExact = +ITW_CLASH_SOFExactClasses;
    if (!isNil "ITW_CLASH_ReconSOFExactClasses") then {
        _configuredExact append ITW_CLASH_ReconSOFExactClasses;
    };
    _configuredExact = _configuredExact apply {toLowerANSI _x};

    private _candidates = [];

    if (_configuredExact isNotEqualTo []) then {
        private _exactCount = {
            (toLowerANSI _x) in _configuredExact
        } count _sourceClasses;
        if (_exactCount > 0) then {
            _candidates pushBack ["exact-class",_exactCount];
        };
    };

    {
        _x params ["_family","_prefixes"];
        private _matched = 0;
        {
            private _class = toLowerANSI _x;
            if ((_prefixes findIf {(_class find _x) == 0}) >= 0) then {
                _matched = _matched + 1;
            };
        } forEach _sourceClasses;
        if (_matched > 0) then {
            _candidates pushBack [_family,_matched];
        };
    } forEach ITW_CLASH_SOFClassPrefixes;

    {
        _x params ["_family","_aliases"];
        private _matched = 0;
        {
            private _className = _x;
            private _cfg = configFile >> "CfgVehicles" >> _className;
            private _identity = toLowerANSI ([
                _className,
                getText (_cfg >> "displayName"),
                getText (_cfg >> "faction"),
                getText (_cfg >> "editorSubcategory"),
                getText (_cfg >> "vehicleClass")
            ] joinString " ");
            private _words = _identity splitString " _-/\\.:()[]{}";
            if ((_aliases findIf {_x in _words}) >= 0) then {
                _matched = _matched + 1;
            };
        } forEach _sourceClasses;
        if (_matched > 0) then {
            private _existing = _candidates findIf {(_x#0) isEqualTo _family};
            if (_existing >= 0) then {
                if (_matched > ((_candidates#_existing)#1)) then {
                    _candidates set [_existing,[_family,_matched]];
                };
            } else {
                _candidates pushBack [_family,_matched];
            };
        };
    } forEach ITW_CLASH_SOFTokenFamilies;

    private _minimum = if (_sourceCount <= 2) then {
        _sourceCount
    } else {
        (floor (_sourceCount / 2)) + 1
    };

    private _qualifying = _candidates select {(_x#1) >= _minimum};
    private _bestFamily = "";
    private _bestCount = 0;
    {
        if ((_x#1) > _bestCount) then {
            _bestFamily = _x#0;
            _bestCount = _x#1;
        };
    } forEach _candidates;

    private _isSOF = _qualifying isNotEqualTo [];
    private _family = "non-sof";
    if (_isSOF) then {
        _family = if ((count _qualifying) > 1) then {"mixed-sof"} else {(_qualifying#0)#0};
        private _bestQualified = 0;
        {
            if ((_x#1) > _bestQualified) then {
                _bestQualified = _x#1;
                if ((count _qualifying) == 1) then {_family = _x#0};
            };
        } forEach _qualifying;
        _bestCount = _bestQualified;
    };

    _group setVariable ["ITW_CLASH_ReconSOF",_isSOF];
    _group setVariable ["ITW_CLASH_ReconSOFFamily",_family];
    _group setVariable ["ITW_CLASH_ReconSOFClassifierVersion",ITW_CLASH_SOFClassifierVersion];

    if (_isSOF) then {
        _group setVariable ["ITW_CLASH_ReconSOFLatched",true];
        _group setVariable ["ITW_CLASH_ReconSOFLatchedFamily",_family];
        if !(_group in ITW_CLASH_SOFDoctrineLogged) then {
            ITW_CLASH_SOFDoctrineLogged pushBack _group;
            ["sof-doctrine-detected",[
                [_group] call ITW_CLASH_fnc_GroupId,
                _family,
                _bestCount,
                _sourceCount,
                _sourceClasses
            ]] call ITW_CLASH_fnc_Log;
        };
    } else {
        // Clear any v1 presence-based latch so the planning bridge can remove a
        // previously injected semantic SpecFor membership on its next cycle.
        _group setVariable ["ITW_CLASH_ReconSOFLatched",nil];
        _group setVariable ["ITW_CLASH_ReconSOFLatchedFamily",nil];
    };

    [_isSOF,_family,_bestCount,_sourceCount,_sourceClasses]
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
    // Keep canonical scoring/strength logic untouched. Present it a synchronous
    // view containing only conventional formations, then restore the managed set.
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
    // Demote stale/save-state SOF anchors before the canonical audit.
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
    "CLASH BOOT | sof-doctrine-ready | version=%1 classifier=%2 compositionBased=true spawnArchetypePreferred=true majorityRequired=true latched=true anchors=false emergencyFallback=false",
    ITW_CLASH_SOFDoctrineVersion,
    ITW_CLASH_SOFClassifierVersion
];

true
