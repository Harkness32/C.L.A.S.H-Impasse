#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALCargoDiceFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALCargoDiceFixReady",false]
};

ITW_CLASH_HALCargoDiceFixStarted = true;
ITW_CLASH_HALCargoDiceFixReady = false;
ITW_CLASH_HALCargoDiceFixVersion = 3;
scriptName "ITW_CLASH_HALCargoDiceFix";

/*
    HAL's troop-lift dice, replaced by the helicopter threat tiers.

    When HAL picks a carrier for a cargo request it rejects an air transport on
    a coin flip (HAL/SCargo.sqf:186):

        ((count ((_HQ getVariable ["RydHQ_AAthreat",[]])
               + (_HQ getVariable ["RydHQ_Airthreat",[]]))) == 0)
        or (random 100 > (85/(0.5 + (2*(_HQ getVariable ["RydHQ_Recklessness",0.5])))))

    Position never enters it. The moment the commander knows of ANY air or AA
    threat anywhere on the map - a MANPADS team forty kilometres away, an
    unarmed transport, a static gun behind the enemy's own rear - every
    helicopter lift becomes a dice roll. At the default recklessness of 0.5 that
    is about a 57% rejection rate for the rest of the mission, on routes that may
    be completely clear.

    The tiers answer the question the dice were standing in for: is the ROUTE
    dangerous. Only a system built to kill aircraft closes it - a dedicated AA
    vehicle, a radar SAM site, an enemy fighter - or an area where two
    helicopters have recently been lost close together. Everything else lets the
    lift fly, and HotDrop decides how it flies once it is near the landing zone.

    SCargo has the route in scope already: _posS is where the cargo group stands
    and _posT is where it is going, so the replacement needs no new plumbing.

    No NR6 file is edited. The function's own source is read, the one expression
    is swapped, and the result is recompiled - the same all-or-nothing shape as
    ITW_CLASH_HALNativeSFFix.sqf. If the text no longer matches, this logs and
    leaves HAL's dice exactly as they were.
*/

ITW_CLASH_HALCargoDiceEnabled = missionNamespace getVariable [
    "ITW_CLASH_HALCargoDiceEnabled",true
];
// Rate limit for the decision log: SCargo is called per group per cycle.
ITW_CLASH_HALCargoDiceLogInterval = missionNamespace getVariable [
    "ITW_CLASH_HALCargoDiceLogInterval",30
];
ITW_CLASH_HALCargoDiceLastLog = createHashMap;

// Inside a live Impasse base, boarding is logistics bookkeeping rather than a
// tactical movement problem. HAL still selects the carrier and owns the mission;
// this only collapses the final walk-to-vehicle step for AI infantry when both
// parties are already inside the same friendly base.
ITW_CLASH_BaseEmbarkFastPathEnabled = missionNamespace getVariable [
    "ITW_CLASH_BaseEmbarkFastPathEnabled",true
];
ITW_CLASH_BaseEmbarkRadius = missionNamespace getVariable [
    "ITW_CLASH_BaseEmbarkRadius",150
];

ITW_CLASH_HALCargoDice_fnc_Log = {
    params ["_event",["_payload",[]],["_key",""]];
    // Flag and exit at function scope: an exitWith inside the then block below
    // would only leave the block, so the rate limit never suppressed anything
    // and this logger spammed the RPT once per group per HAL cycle.
    private _muted = false;
    if (_key isNotEqualTo "") then {
        private _last = ITW_CLASH_HALCargoDiceLastLog getOrDefault [_key,-1e6];
        if ((time - _last) < ITW_CLASH_HALCargoDiceLogInterval) then {
            _muted = true;
        } else {
            ITW_CLASH_HALCargoDiceLastLog set [_key,time];
        };
    };
    if (_muted) exitWith {};
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-cargo-dice-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL CARGO DICE | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["hal-cargo-dice",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

/*
    A base is resolved from Impasse's live base graph at the moment SCargo asks.
    No startup coordinate is cached, so when ITW advances its bases this fast
    path advances with them. The radius only abstracts the last bit of staging
    movement inside a secured logistics node.
*/
ITW_CLASH_HALCargoDice_fnc_BaseAtPosition = {
    params ["_side","_position"];
    if (
        isNil "ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices"
        || {isNil "ITW_Bases"}
        || {_position isEqualTo []}
    ) exitWith {-1};

    private _bestIndex = -1;
    private _bestDistance = 1e12;
    {
        private _baseIndex = _x;
        if (_baseIndex < 0 || {_baseIndex >= count ITW_Bases}) then {continue};
        private _base = ITW_Bases#_baseIndex;

        // A live Impasse base is larger than its abstract center. Air assets
        // can legitimately stage at A_SPAWN and ground transports at GARAGE_POS,
        // so any of those anchors establishes "at this base".
        private _anchors = [
            +(_base#ITW_BASE_POS),
            +(_base#ITW_BASE_A_SPAWN),
            +(_base#ITW_BASE_GARAGE_POS)
        ];
        {
            private _anchor = _x;
            if (
                _anchor isEqualTo []
                || {_anchor isEqualTo [0,0,0]}
                || {_anchor isEqualTo [-1000,-1000,0]}
                || {_anchor isEqualTo [999,999,0]}
            ) then {continue};
            if (count _anchor < 3) then {_anchor pushBack 0};
            private _distance = _position distance2D _anchor;
            if (_distance <= ITW_CLASH_BaseEmbarkRadius && {_distance < _bestDistance}) then {
                _bestDistance = _distance;
                _bestIndex = _baseIndex;
            };
        } forEach _anchors;
    } forEach ([_side] call ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices);

    _bestIndex
};

ITW_CLASH_HALCargoDice_fnc_BaseEmbark = {
    params ["_unitG","_vehicle",["_hq",grpNull]];
    if (!ITW_CLASH_BaseEmbarkFastPathEnabled) exitWith {false};
    if (isNull _unitG || {isNull _vehicle} || {!alive _vehicle}) exitWith {false};

    // This is deliberately not a recovery shortcut. Native SCargo passes
    // _withdraw/_request guards before calling us; these extra state guards
    // keep a future caller from bypassing GTFO/CASEVAC ownership accidentally.
    if (_unitG getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {false};

    private _troops = (units _unitG) select {alive _x};
    if (_troops isEqualTo []) exitWith {false};
    if ((_troops findIf {isPlayer _x}) >= 0) exitWith {false};
    if ((_troops findIf {
        !(_x isKindOf "CAManBase") || {vehicle _x != _x}
    }) >= 0) exitWith {false};

    // Only accelerate a real HAL transport. Empty vehicles use SCargo's
    // separate driver/gunner assignment path and must remain untouched.
    private _driver = assignedDriver _vehicle;
    if (isNull _driver) exitWith {false};
    private _carrierG = group _driver;
    if (isNull _carrierG || {_carrierG == _unitG}) exitWith {false};
    if (side _carrierG != side _unitG) exitWith {false};
    if ((_vehicle emptyPositions "Cargo") < count _troops) exitWith {false};

    private _side = side _unitG;
    private _troopBase = [_side,getPosATL (leader _unitG)] call
        ITW_CLASH_HALCargoDice_fnc_BaseAtPosition;
    if (_troopBase < 0) exitWith {false};
    private _carrierBase = [_side,getPosATL _vehicle] call
        ITW_CLASH_HALCargoDice_fnc_BaseAtPosition;
    if (_carrierBase != _troopBase) exitWith {false};

    {
        _x assignAsCargo _vehicle;
        _x moveInCargo _vehicle;
    } forEach _troops;

    private _failed = _troops select {vehicle _x != _vehicle};
    if (_failed isNotEqualTo []) exitWith {
        // Fail open back to native physical boarding. Roll back a partial
        // embarkation so SCargo never inherits a split squad.
        {
            if (vehicle _x == _vehicle) then {moveOut _x};
            [_x] remoteExecCall ["RYD_MP_unassignVehicle",0];
        } forEach _troops;
        diag_log format [
            "CLASH HAL CARGO | base-embark-failed | group=%1 vehicle=%2 base=%3 failed=%4",
            str _unitG,typeOf _vehicle,_troopBase,count _failed
        ];
        false
    };

    _unitG setVariable ["ITW_CLASH_BaseEmbarkFastPathed",true];
    _vehicle setVariable ["ITW_CLASH_BaseEmbarkLastAt",time];
    diag_log format [
        "CLASH HAL CARGO | base-embark-fastpath | group=%1 vehicle=%2 base=%3 troops=%4 radius=%5",
        str _unitG,typeOf _vehicle,_troopBase,count _troops,ITW_CLASH_BaseEmbarkRadius
    ];
    true
};

/*
    HAL's own rule, kept verbatim as the fallback. If the air picture is not
    loaded we must not simply wave every lift through: that would be a louder
    change than the one intended. Without a corridor to read, HAL's judgment
    stands.
*/
ITW_CLASH_HALCargoDice_fnc_NativeRoll = {
    params ["_hq"];
    if (isNull _hq) exitWith {true};
    private _threats = (_hq getVariable ["RydHQ_AAthreat",[]])
        + (_hq getVariable ["RydHQ_Airthreat",[]]);
    if (count _threats == 0) exitWith {true};
    private _recklessness = _hq getVariable ["RydHQ_Recklessness",0.5];
    random 100 > (85 / (0.5 + (2 * _recklessness)))
};

/*
    May this air lift be flown? Called from inside HAL's own carrier selection,
    in place of the dice, with the route it already has in scope.
*/
ITW_CLASH_HALCargoDice_fnc_Acceptable = {
    params ["_hq",["_from",[]],["_to",[]]];
    if (isNull _hq) exitWith {true};
    if (!ITW_CLASH_HALCargoDiceEnabled) exitWith {
        [_hq] call ITW_CLASH_HALCargoDice_fnc_NativeRoll
    };
    if (
        isNil "ITW_CLASH_AirPicture_fnc_ClassifyCorridor"
        || {_from isEqualTo []}
        || {_to isEqualTo []}
    ) exitWith {
        ["fallback-native-roll",[
            _hq getVariable ["RydHQ_CodeSign","?"],
            isNil "ITW_CLASH_AirPicture_fnc_ClassifyCorridor"
        ],"fallback"] call ITW_CLASH_HALCargoDice_fnc_Log;
        [_hq] call ITW_CLASH_HALCargoDice_fnc_NativeRoll
    };

    private _corridor = [_hq,_from,_to] call ITW_CLASH_AirPicture_fnc_ClassifyCorridor;
    private _state = _corridor getOrDefault ["state","COLD"];
    private _reason = _corridor getOrDefault ["reason",""];
    if (_reason isEqualTo "corridor-unavailable") exitWith {
        [_hq] call ITW_CLASH_HALCargoDice_fnc_NativeRoll
    };

    private _acceptable = _state isNotEqualTo "AIR_DENIED";
    private _sign = _hq getVariable ["RydHQ_CodeSign","?"];
    [
        if (_acceptable) then {"lift-allowed"} else {"lift-refused"},
        [_sign,_state,_reason,_from apply {round _x},_to apply {round _x}],
        format ["%1|%2",_sign,_state]
    ] call ITW_CLASH_HALCargoDice_fnc_Log;
    _acceptable
};

private _finishFailure = {
    params ["_reason",["_details",[]]];
    ITW_CLASH_HALCargoDiceFixReady = false;
    diag_log format [
        "CLASH BOOT | WARNING | hal-cargo-dice-fix-failed | reason=%1 details=%2 | HAL's lift dice retained",
        _reason,
        _details
    ];
    false
};

// Same all-or-nothing swap the native SF fix uses: refuse a duplicate anchor
// and refuse a missing one.
private _replaceExact = {
    params ["_source","_bad","_good","_label"];
    private _badAt = _source find _bad;
    private _goodAt = _source find _good;
    if (_badAt < 0) exitWith {
        if (_goodAt >= 0) then {
            [true,_source,_label + ":already-fixed"]
        } else {
            [false,_source,_label + ":signature-missing"]
        }
    };
    private _tailAt = _badAt + count _bad;
    if (((_source select [_tailAt]) find _bad) >= 0) exitWith {
        [false,_source,_label + ":signature-duplicate"]
    };
    [true,(_source select [0,_badAt]) + _good + (_source select [_tailAt]),_label + ":patched"]
};

private _deadline = diag_tickTime + 120;
waitUntil {
    sleep 0.05;
    (!isNil "RYD_Path" && {!isNil "HAL_SCargo"}) || {diag_tickTime >= _deadline}
};
if (isNil "RYD_Path" || {isNil "HAL_SCargo"}) exitWith {
    ["hal-runtime-bind-timeout",[]] call _finishFailure
};

/*
    The Checkbook installs its own cargo hook over HAL_SCargo
    (ITW_CLASH_DualHALCheckbook.sqf:1257), keeping the original in
    ITW_CLASH_Checkbook_fnc_NativeSCargo. Patching HAL_SCargo after that would
    throw the hook away, so wait for it and patch the native it holds. Without
    the hook, HAL_SCargo is the native.
*/
private _hookDeadline = diag_tickTime + 60;
waitUntil {
    sleep 0.1;
    (missionNamespace getVariable ["ITW_CLASH_CheckbookCargoHookReady",false])
    || {diag_tickTime >= _hookDeadline}
};
private _hooked = missionNamespace getVariable ["ITW_CLASH_CheckbookCargoHookReady",false]
    && {!isNil "ITW_CLASH_Checkbook_fnc_NativeSCargo"};

private _path = RYD_Path + "HAL\SCargo.sqf";
private _source = preprocessFileLineNumbers _path;
// NR6's distributed SQF is CRLF. The source patch signatures below are
// authored with LF newlines, so normalize carriage returns before matching.
// Without this, the multi-line base-embark anchor never matches and the whole
// SCargo patch correctly fails closed back to native HAL.
_source = (_source splitString (toString [13])) joinString "";
if (_source isEqualTo "") exitWith {
    ["native-source-missing",[_path]] call _finishFailure
};
if ((_source find "CargoChosen") < 0 || {(_source find "_posT") < 0}) exitWith {
    ["SCargo-signature-missing",[count _source]] call _finishFailure
};

private _step = [
    _source,
    '(((count ((_HQ getVariable ["RydHQ_AAthreat",[]]) + (_HQ getVariable ["RydHQ_Airthreat",[]]))) == 0) or (random 100 > (85/(0.5 + (2*(_HQ getVariable ["RydHQ_Recklessness",0.5]))))))',
    '([_HQ,_posS,_posT] call ITW_CLASH_HALCargoDice_fnc_Acceptable)',
    "SCargo-air-lift-dice"
] call _replaceExact;
if !(_step#0) exitWith {[_step#2,[count _source]] call _finishFailure};
_source = _step#1;

private _embarkStep = [
    _source,
    'if ((_enmyNrb) and not (_request)) exitwith {_unitG setVariable ["CargoChosen",false,true];_unitG setVariable [("CC" + (str _unitG)), true, true]};\n\n_lz = objNull;',
    'if ((_enmyNrb) and not (_request)) exitwith {_unitG setVariable ["CargoChosen",false,true];_unitG setVariable [("CC" + (str _unitG)), true, true]};\n\nprivate _clashBaseEmbarked = false; if (not (_withdraw) and not (_request) and not (_emptyV) and {!isNil "ITW_CLASH_HALCargoDice_fnc_BaseEmbark"}) then {_clashBaseEmbarked = [_unitG,_ChosenOne,_HQ] call ITW_CLASH_HALCargoDice_fnc_BaseEmbark;};\n\n_lz = objNull;',
    "SCargo-base-embark-entry"
] call _replaceExact;
if !(_embarkStep#0) exitWith {
    [_embarkStep#2,[count _source]] call _finishFailure
};
_source = _embarkStep#1;

private _assignStep = [
    _source,
    'if (((_ChosenOne emptyPositions "Cargo") > 0) and not (_request)) then',
    'if (not (_clashBaseEmbarked) and (((_ChosenOne emptyPositions "Cargo") > 0) and not (_request))) then',
    "SCargo-base-embark-physical-fallback"
] call _replaceExact;
if !(_assignStep#0) exitWith {
    [_assignStep#2,[count _source]] call _finishFailure
};
_source = _assignStep#1;

private _compiled = compile _source;
if !(_compiled isEqualType {}) exitWith {
    ["recompile-failed",[typeName _compiled]] call _finishFailure
};

if (_hooked) then {
    ITW_CLASH_Checkbook_fnc_NativeSCargo = _compiled;
} else {
    HAL_SCargo = _compiled;
};

ITW_CLASH_HALCargoDiceFixReady = true;
diag_log format [
    "CLASH BOOT | hal-cargo-dice-fix-ready | version=%1 result=%2 embark=%3/%4 target=%5 routeAware=true baseEmbark=true liveImpasseBases=true nr6Untouched=true",
    ITW_CLASH_HALCargoDiceFixVersion,
    _step#2,
    _embarkStep#2,
    _assignStep#2,
    if (_hooked) then {"checkbook-native-scargo"} else {"hal-scargo"}
];
true
