#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALCargoDiceFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALCargoDiceFixReady",false]
};

ITW_CLASH_HALCargoDiceFixStarted = true;
ITW_CLASH_HALCargoDiceFixReady = false;
ITW_CLASH_HALCargoDiceFixVersion = 1;
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
    "CLASH BOOT | hal-cargo-dice-fix-ready | version=%1 result=%2 target=%3 routeAware=true nr6Untouched=true",
    ITW_CLASH_HALCargoDiceFixVersion,
    _step#2,
    if (_hooked) then {"checkbook-native-scargo"} else {"hal-scargo"}
];
true
