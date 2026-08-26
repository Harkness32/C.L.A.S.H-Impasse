if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestStrikeClassifierV2Started",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestStrikeClassifierV2Started = true;
ITW_CLASH_PlayerTaskRequestStrikeClassifierV2Version = 2;

if (isNil "ITW_CLASH_PlayerTaskRequestStrike_fnc_SelectTarget") exitWith {
    diag_log "CLASH BOOT | strike-classifier-v2-missing-base | classifier override disabled";
    false
};

// HAL knowledge remains the only admission source.  Union the two native HAL
// knowledge projections so a partially stale KnEnemiesG cache cannot hide a
// contact that HAL still exposes through KnEnemies.  This never discovers a
// new enemy; both inputs are authority-owned HAL state.
ITW_CLASH_PlayerTaskRequestStrike_fnc_KnownGroups = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};

    private _known = +(_hq getVariable ["RydHQ_KnEnemiesG",[]]);
    {
        if (!isNull _x) then {
            private _g = group _x;
            if (!isNull _g) then {_known pushBackUnique _g};
        };
    } forEach +(_hq getVariable ["RydHQ_KnEnemies",[]]);

    _known select {
        !isNull _x && {{alive _x} count units _x > 0}
    }
};

// Build a live copy of one native RHQ type family.  HQSitRep uses the same
// RHQ_* + RYD_WS_*_class - RHQs_* contract.  Normalize class strings because
// native StatusQuo compares them against lower-cased typeOf values.
ITW_CLASH_PlayerTaskRequestStrike_fnc_RHQTypeSet = {
    params ["_baseName","_autoName","_excludeName"];

    private _types = +(missionNamespace getVariable [_baseName,[]]);
    _types append +(missionNamespace getVariable [_autoName,[]]);
    private _excluded = +(missionNamespace getVariable [_excludeName,[]]);

    _types = _types select {_x isEqualType ""};
    _excluded = _excluded select {_x isEqualType ""};
    _types = _types apply {toLower _x};
    _excluded = _excluded apply {toLower _x};

    (_types arrayIntersect _types) - _excluded
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_RHQTaxonomy = {
    private _heavy = [
        "RHQ_HArmor","RYD_WS_HArmor_class","RHQs_HArmor"
    ] call ITW_CLASH_PlayerTaskRequestStrike_fnc_RHQTypeSet;

    private _light = [];
    {
        _x params ["_base","_auto","_exclude"];
        _light append ([_base,_auto,_exclude] call
            ITW_CLASH_PlayerTaskRequestStrike_fnc_RHQTypeSet);
    } forEach [
        ["RHQ_MArmor","RYD_WS_MArmor_class","RHQs_MArmor"],
        ["RHQ_LArmor","RYD_WS_LArmor_class","RHQs_LArmor"],
        ["RHQ_LArmorAT","RYD_WS_LArmorAT_class","RHQs_LArmorAT"]
    ];
    _light = (_light arrayIntersect _light) - _heavy;

    private _soft = [];
    {
        _x params ["_base","_auto","_exclude"];
        _soft append ([_base,_auto,_exclude] call
            ITW_CLASH_PlayerTaskRequestStrike_fnc_RHQTypeSet);
    } forEach [
        ["RHQ_Inf","RYD_WS_Inf_class","RHQs_Inf"],
        ["RHQ_Static","RYD_WS_Static_class","RHQs_Static"],
        ["RHQ_Cars","RYD_WS_Cars_class","RHQs_Cars"],
        ["RHQ_Art","RYD_WS_Art_class","RHQs_Art"],
        ["RHQ_Support","RYD_WS_Support_class","RHQs_Support"],
        ["RHQ_Cargo","RYD_WS_Cargo_class","RHQs_Cargo"],
        ["RHQ_NCCargo","RYD_WS_NCCargo_class","RHQs_NCCargo"]
    ];
    _soft = (_soft arrayIntersect _soft) - _heavy - _light;

    createHashMapFromArray [
        ["HEAVY",_heavy],
        ["LIGHT",_light],
        ["SOFT",_soft]
    ]
};

// Mirror native StatusQuo's useful distinction between a unit's own class and
// the vehicle operated by that group.  Passenger infantry do not become armor
// merely because another group is driving the carrier.
ITW_CLASH_PlayerTaskRequestStrike_fnc_GroupTypes = {
    params ["_group"];
    if (isNull _group) exitWith {[]};

    private _types = [];
    {
        private _unit = _x;
        if (!alive _unit) then {continue};
        _types pushBackUnique (toLower (typeOf _unit));

        private _vehicle = vehicle _unit;
        if (_vehicle == _unit || {isNull _vehicle} || {!alive _vehicle}) then {
            continue
        };

        private _driver = driver _vehicle;
        private _gunner = gunner _vehicle;
        private _commander = commander _vehicle;
        private _operatedByGroup = (
            (!isNull _driver && {group _driver == _group})
            || {(!isNull _gunner && {group _gunner == _group})}
            || {(!isNull _commander && {group _commander == _group})}
        );
        if (_operatedByGroup) then {
            _types pushBackUnique (toLower (typeOf _vehicle));
        };
    } forEach units _group;

    _types
};

ITW_CLASH_PlayerTaskRequestStrike_fnc_ClassifyKnownGroup = {
    params ["_group","_taxonomy"];
    if (isNull _group) exitWith {["UNCLASSIFIED",[]]};

    private _types = [_group] call
        ITW_CLASH_PlayerTaskRequestStrike_fnc_GroupTypes;
    private _heavy = _taxonomy getOrDefault ["HEAVY",[]];
    private _light = _taxonomy getOrDefault ["LIGHT",[]];
    private _soft = _taxonomy getOrDefault ["SOFT",[]];

    // Precedence preserves the old category subtraction semantics for mixed
    // groups: heavy armor beats light armor, and armor beats soft components.
    if ((_types arrayIntersect _heavy) isNotEqualTo []) exitWith {
        ["HEAVY",_types]
    };
    if ((_types arrayIntersect _light) isNotEqualTo []) exitWith {
        ["LIGHT",_types]
    };
    if ((_types arrayIntersect _soft) isNotEqualTo []) exitWith {
        ["SOFT",_types]
    };
    ["UNCLASSIFIED",_types]
};

// Replace the v1 selector's fragile KnEnemiesG ∩ RydHQ_En*G intersection.
// Only HAL-known groups are ever inspected; classification is resolved live
// from HAL's own RHQ taxonomy at the moment the player asks for work.
ITW_CLASH_PlayerTaskRequestStrike_fnc_SelectTarget = {
    params ["_hq","_requestType"];
    if (isNull _hq) exitWith {grpNull};

    private _wanted = switch (_requestType) do {
        case "STRIKE_HEAVY_ARMOR": {"HEAVY"};
        case "STRIKE_LIGHT_ARMOR": {"LIGHT"};
        case "STRIKE_SOFT": {"SOFT"};
        default {""};
    };
    if (_wanted isEqualTo "") exitWith {grpNull};

    private _knownGroupProjection = +(_hq getVariable ["RydHQ_KnEnemiesG",[]]);
    private _knownObjectProjection = +(_hq getVariable ["RydHQ_KnEnemies",[]]);
    private _known = [_hq] call ITW_CLASH_PlayerTaskRequestStrike_fnc_KnownGroups;
    private _taxonomy = call ITW_CLASH_PlayerTaskRequestStrike_fnc_RHQTaxonomy;
    private _candidates = [];
    private _heavyCount = 0;
    private _lightCount = 0;
    private _softCount = 0;
    private _unclassifiedCount = 0;
    private _reservedCount = 0;

    {
        private _targetGroup = _x;
        private _classified = [_targetGroup,_taxonomy] call
            ITW_CLASH_PlayerTaskRequestStrike_fnc_ClassifyKnownGroup;
        _classified params ["_class","_types"];

        switch (_class) do {
            case "HEAVY": {_heavyCount = _heavyCount + 1};
            case "LIGHT": {_lightCount = _lightCount + 1};
            case "SOFT": {_softCount = _softCount + 1};
            default {_unclassifiedCount = _unclassifiedCount + 1};
        };

        private _reserved = (
            (_targetGroup getVariable ["ITW_CLASH_PlayerStrikeReservation",""])
            isNotEqualTo ""
        );
        if (_reserved) then {_reservedCount = _reservedCount + 1};

        ["target-classified",[
            groupId _targetGroup,_requestType,_class,_types,_reserved
        ]] call ITW_CLASH_PlayerTaskRequestStrike_fnc_Log;

        if (_class == _wanted && {!_reserved} && {
            {alive _x} count units _targetGroup > 0
        }) then {
            _candidates pushBack _targetGroup;
        };
    } forEach _known;

    if (_candidates isEqualTo []) exitWith {
        ["no-candidate",[
            str _hq,_requestType,
            "knEnemiesG",count _knownGroupProjection,
            "knEnemies",count _knownObjectProjection,
            "knownLiveGroups",count _known,
            "heavy",_heavyCount,
            "light",_lightCount,
            "soft",_softCount,
            "unclassified",_unclassifiedCount,
            "reserved",_reservedCount,
            "rhqHeavyTypes",count (_taxonomy getOrDefault ["HEAVY",[]]),
            "rhqLightTypes",count (_taxonomy getOrDefault ["LIGHT",[]]),
            "rhqSoftTypes",count (_taxonomy getOrDefault ["SOFT",[]])
        ]] call ITW_CLASH_PlayerTaskRequestStrike_fnc_Log;
        grpNull
    };

    // Preserve native HQOrders' immediate-threat heuristic after the requested
    // class filter: nearest qualifying HAL-known formation to this HAL HQ.
    private _hqVehicle = vehicle leader _hq;
    private _best = _candidates#0;
    private _bestDistance = (vehicle leader _best) distance2D _hqVehicle;
    {
        private _distance = (vehicle leader _x) distance2D _hqVehicle;
        if (_distance < _bestDistance) then {
            _best = _x;
            _bestDistance = _distance;
        };
    } forEach _candidates;

    ["candidate-selected",[
        groupId _best,_requestType,_wanted,_bestDistance,count _candidates
    ]] call ITW_CLASH_PlayerTaskRequestStrike_fnc_Log;
    _best
};

ITW_CLASH_PlayerTaskRequestStrikeVersion = 2;
ITW_CLASH_PlayerTaskRequestStrikeClassifierV2Ready = true;
diag_log format [
    "CLASH BOOT | strike-classifier-v2-ready | version=%1 halKnowledgeUnion=true rhqLiveTaxonomy=true cachedEnemyCategoryIntersection=false omniscientScan=false classifiedTelemetry=true",
    ITW_CLASH_PlayerTaskRequestStrikeClassifierV2Version
];

true
