#include "defines.hpp"

if (!isServer) exitWith {false};
ITW_CLASH_SOFDoctrineVersion = 1;
ITW_CLASH_SOFClassifierVersion = 3;

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

    Classifier v3 also reads the identity every modpack already declares:
    vanilla files recon, CTRG and Spetsnaz recon under
    EdSubcat_Personnel_SpecialForces, and CUP, RHS, 3CB and most faction mods
    reuse it or name theirs recon/SF/SOF/MARSOC/KSK. Checked against 6551
    CfgGroups squads from vanilla, CUP, RHS, 3CB, BWMod and TFC: every squad
    it marks is special forces. Snipers and spotters sit under the same
    subcategory but stay HAL snipers.

    SpecForG is withheld from HAL's attack, defense, capture and reserve
    tasking, so a faction that is mostly special forces would leave its
    commander nothing to fight with. Each side keeps at most
    ITW_CLASH_SOFMaxShare of its groups as SOF, but never fewer than
    ITW_CLASH_SOFMinTeams (HAL's raid odds only open up around four free
    teams, HAC_fnc2.sqf:1203) and never more than half. Extra SOF-capable
    groups fight as line infantry until a slot frees up.
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

// Words from the class name, display name, faction, editor subcategory and
// vehicle class. Adjacent words are also joined, so "Special Forces",
// "Force Recon" and "Delta Force" match as one word.
ITW_CLASH_SOFGenericWords = [
    "specialforces","specialoperations","specops","sf","sof",
    "recon","menrecon","forcerecon","marsoc","ksk","deltaforce",
    "especas","spetsnaz","ctrg","commando","commandos"
];
ITW_CLASH_SOFSniperWords = ["sniper","snipers","spotter","ghillie","mensniper"];

ITW_CLASH_SOFMaxShare = missionNamespace getVariable ["ITW_CLASH_SOFMaxShare",0.25];
ITW_CLASH_SOFMinTeams = missionNamespace getVariable ["ITW_CLASH_SOFMinTeams",4];

if (isNil "ITW_CLASH_SOFExactClasses") then {ITW_CLASH_SOFExactClasses = []};
if (isNil "ITW_CLASH_SOFDoctrineLogged") then {ITW_CLASH_SOFDoctrineLogged = []};
ITW_CLASH_SOFClassFamilyCache = createHashMap;

// SOF families one unit class belongs to, from its config identity. Cached.
ITW_CLASH_SOF_fnc_ClassFamilies = {
    params ["_className"];
    private _key = toLowerANSI _className;
    private _cached = ITW_CLASH_SOFClassFamilyCache get _key;
    if (!isNil "_cached") exitWith {_cached};

    private _cfg = configFile >> "CfgVehicles" >> _className;
    private _identity = toLowerANSI ([
        _className,
        getText (_cfg >> "displayName"),
        getText (_cfg >> "faction"),
        getText (_cfg >> "editorSubcategory"),
        getText (_cfg >> "vehicleClass")
    ] joinString " ");
    private _words = _identity splitString " _-/\\.:()[]{},";
    private _pairs = [];
    for "_i" from 0 to ((count _words) - 2) do {
        private _first = _words#_i;
        private _second = _words#(_i + 1);
        if ((count _first) >= 3 && {(count _second) >= 3}) then {
            _pairs pushBack (_first + _second);
        };
    };
    _words append _pairs;

    private _families = [];
    {
        _x params ["_family","_prefixes"];
        if ((_prefixes findIf {(_key find _x) == 0}) >= 0) then {
            _families pushBackUnique _family;
        };
    } forEach ITW_CLASH_SOFClassPrefixes;
    {
        _x params ["_family","_aliases"];
        if ((_aliases findIf {_x in _words}) >= 0) then {
            _families pushBackUnique _family;
        };
    } forEach ITW_CLASH_SOFTokenFamilies;
    if (
        (ITW_CLASH_SOFGenericWords findIf {_x in _words}) >= 0 &&
        {(ITW_CLASH_SOFSniperWords findIf {_x in _words}) < 0}
    ) then {
        _families pushBackUnique "special-forces";
    };

    ITW_CLASH_SOFClassFamilyCache set [_key,_families];
    _families
};

// [slot free, SOF groups held by the side (not counting _group), cap, side groups]
ITW_CLASH_SOF_fnc_SideSlot = {
    params ["_group"];
    private _side = side _group;
    private _groups = [];
    {
        _groups append (missionNamespace getVariable [_x,[]]);
    } forEach ["ITW_CLASH_ManagedGroups","ITW_CLASH_DualHALBLUFORGroups","ITW_CLASH_DualHALOPFORExtraGroups"];
    _groups = (_groups arrayIntersect _groups) select {
        !isNull _x && {side _x == _side} && {({alive _x} count units _x) > 0}
    };
    private _total = count _groups;
    private _cap = (ITW_CLASH_SOFMinTeams max (floor (ITW_CLASH_SOFMaxShare * _total))) min (floor (_total / 2));
    private _held = {
        _x != _group && {_x getVariable ["ITW_CLASH_ReconSOFLatched",false]}
    } count _groups;
    [_held < _cap,_held,_cap,_total]
};

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

    private _familyCounts = createHashMap;
    {
        {
            _familyCounts set [_x,(_familyCounts getOrDefault [_x,0]) + 1];
        } forEach ([_x] call ITW_CLASH_SOF_fnc_ClassFamilies);
    } forEach _sourceClasses;
    {
        _candidates pushBack [_x,_y];
    } forEach _familyCounts;

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
        // A named family (seal, viper...) labels the group over the generic one.
        private _named = _qualifying select {(_x#0) != "special-forces"};
        private _labelled = if (_named isNotEqualTo []) then {_named} else {_qualifying};
        _family = if ((count _labelled) > 1) then {"mixed-sof"} else {(_labelled#0)#0};
        private _bestQualified = 0;
        {
            if ((_x#1) > _bestQualified) then {
                _bestQualified = _x#1;
            };
        } forEach _qualifying;
        _bestCount = _bestQualified;
    };

    // Side cap, and never pull a group off an objective it is anchoring.
    if (_isSOF) then {
        private _slot = [_group] call ITW_CLASH_SOF_fnc_SideSlot;
        private _anchorObjective = _group getVariable ["ITW_CLASH_AnchorObjective",-1];
        if (!(_slot#0) || {_anchorObjective >= 0}) then {
            if !(_group getVariable ["ITW_CLASH_SOFHeldLogged",false]) then {
                _group setVariable ["ITW_CLASH_SOFHeldLogged",true];
                ["sof-doctrine-held-conventional",[
                    [_group] call ITW_CLASH_fnc_GroupId,
                    _family,
                    _slot#1,
                    _slot#2,
                    _slot#3,
                    _anchorObjective
                ]] call ITW_CLASH_fnc_Log;
            };
            _isSOF = false;
            _family = "held-conventional";
        };
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
    "CLASH BOOT | sof-doctrine-ready | version=%1 classifier=%2 compositionBased=true spawnArchetypePreferred=true majorityRequired=true latched=true anchors=false emergencyFallback=false configIdentity=true maxShare=%3 minTeams=%4",
    ITW_CLASH_SOFDoctrineVersion,
    ITW_CLASH_SOFClassifierVersion,
    ITW_CLASH_SOFMaxShare,
    ITW_CLASH_SOFMinTeams
];

true
