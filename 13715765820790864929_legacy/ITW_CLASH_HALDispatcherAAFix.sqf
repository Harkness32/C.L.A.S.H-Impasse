#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALDispatcherAAFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALDispatcherAAFixReady",false]
};

ITW_CLASH_HALDispatcherAAFixStarted = true;
ITW_CLASH_HALDispatcherAAFixReady = false;
ITW_CLASH_HALDispatcherAAFixFinished = false;
ITW_CLASH_HALDispatcherAAFixVersion = 1;
scriptName "ITW_CLASH_HALDispatcherAAFix";

/*
    RYD_Dispatcher weighs an aircraft's AA risk against the wrong threat list.

    In the AIR/AIRCAP branch (HAC_fnc.sqf:1725-1745) HAL correctly gates on
    "does this commander know of any AA?" (count _AAthreat > 0) and then scores
    the risk with _AAriskResign - but it measures the distance to the nearest
    _ATthreat, not the nearest _AAthreat (HAC_fnc.sqf:1730). So HAL sends
    aircraft past real SPAA whenever no AT vehicle happens to sit near the
    route, and resigns from clear routes that merely pass an enemy tank. The
    armor branch above it uses _ATthreat correctly in both of its two copies.

    Fixing this in NR6 HAL would force a mod re-upload and would not execute at
    all in test (the Workshop HAL runs, not the repo copy), so C.L.A.S.H. reads
    the compiled function's own text, swaps that one reference, and recompiles.
    Nothing under NR6 Hal/ is touched.

    The anchor is positional rather than a quoted source line, because the text
    that comes back from a compiled function is normalized: the last _AAthreat
    in the function IS the AIR branch's own gate, and the target is the first
    _ATthreat after it (the armor branch, with all of its _ATthreat uses, sits
    above). All of it is checked before anything is written: the reference has
    to sit inside a RYD_CloseEnemyB call, and there has to be exactly one such
    reference after the gate. Any miss - HAL fixed it upstream, HAL rewrote the
    branch - logs and leaves stock HAL compiled.
*/

ITW_CLASH_HALDispatcherAAFix_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["hal-dispatcher-aa-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH HAL DISPATCHER AA | %1 | %2",_event,_payload];
    };
};

// Last index at which _needle occurs in _haystack, or -1. SQF has no rfind.
ITW_CLASH_HALDispatcherAAFix_fnc_LastIndexOf = {
    params ["_haystack","_needle"];
    private _length = count _needle;
    if (_length <= 0) exitWith {-1};
    private _found = -1;
    private _scan = 0;
    private _searching = true;
    while {_searching} do {
        private _hit = (_haystack select [_scan]) find _needle;
        if (_hit < 0) then {
            _searching = false;
        } else {
            _found = _scan + _hit;
            _scan = _found + _length;
        };
    };
    _found
};

// A compiled function's text may or may not carry its own outer braces. Strip
// them when it does, so `compile` yields the function again and not a function
// that returns one.
ITW_CLASH_HALDispatcherAAFix_fnc_Unwrap = {
    params ["_source"];
    private _trimmed = _source;
    while {_trimmed isNotEqualTo "" && {(_trimmed select [0,1]) in [" ",toString [9],toString [10],toString [13]]}} do {
        _trimmed = _trimmed select [1];
    };
    while {_trimmed isNotEqualTo "" && {(_trimmed select [(count _trimmed) - 1,1]) in [" ",toString [9],toString [10],toString [13]]}} do {
        _trimmed = _trimmed select [0,(count _trimmed) - 1];
    };
    if (
        (count _trimmed) > 1
        && {(_trimmed select [0,1]) isEqualTo "{"}
        && {(_trimmed select [(count _trimmed) - 1,1]) isEqualTo "}"}
    ) exitWith {[_trimmed select [1,(count _trimmed) - 2],true]};
    [_source,false]
};

private _finishFailure = {
    params ["_reason",["_details",[]]];
    ITW_CLASH_HALDispatcherAAFixReady = false;
    ITW_CLASH_HALDispatcherAAFixFinished = true;
    ["patch-failed",[_reason,_details]] call ITW_CLASH_HALDispatcherAAFix_fnc_Log;
    diag_log format [
        "CLASH BOOT | WARNING | hal-dispatcher-aa-fix-failed | reason=%1 details=%2 | stock HAL dispatcher retained",
        _reason,
        _details
    ];
    false
};

private _deadline = diag_tickTime + 120;
waitUntil {
    sleep 0.05;
    !isNil "RYD_Dispatcher" || {diag_tickTime >= _deadline}
};
if (isNil "RYD_Dispatcher") exitWith {
    ["hal-runtime-bind-timeout",[]] call _finishFailure
};
if !(RYD_Dispatcher isEqualType {}) exitWith {
    ["dispatcher-not-code",[typeName RYD_Dispatcher]] call _finishFailure
};

private _raw = toString RYD_Dispatcher;
if (_raw isEqualTo "") exitWith {
    ["dispatcher-text-unavailable",[]] call _finishFailure
};

([_raw] call ITW_CLASH_HALDispatcherAAFix_fnc_Unwrap) params ["_source","_wrapped"];

// Refuse to rewrite a dispatcher we do not recognise.
if (
    (_source find "_AAriskResign") < 0
    || {(_source find "RYD_CloseEnemyB") < 0}
    || {(_source find "RYD_PointToSecDst") < 0}
) exitWith {
    ["dispatcher-signature-missing",[count _source,_wrapped]] call _finishFailure
};

private _gate = [_source,"_AAthreat"] call ITW_CLASH_HALDispatcherAAFix_fnc_LastIndexOf;
if (_gate < 0) exitWith {
    ["aa-gate-missing",[count _source]] call _finishFailure
};

private _tailAt = _gate + (count "_AAthreat");
private _tail = _source select [_tailAt];
private _relative = _tail find "_ATthreat";
if (_relative < 0) exitWith {
    // Already correct: the AIR branch's own measurement is the last threat-list
    // reference in the function, which is exactly the post-patch shape.
    ITW_CLASH_HALDispatcherAAFixReady = true;
    ITW_CLASH_HALDispatcherAAFixFinished = true;
    ["already-fixed",[count _source]] call ITW_CLASH_HALDispatcherAAFix_fnc_Log;
    diag_log "CLASH BOOT | hal-dispatcher-aa-fix-ready | patched=false reason=already-fixed";
    true
};

private _afterTarget = _tail select [_relative + (count "_ATthreat")];
if ((_afterTarget find "_ATthreat") >= 0) exitWith {
    ["aa-reference-ambiguous",[count _source,_relative]] call _finishFailure
};
// The reference we are about to change has to be the argument of the very
// RYD_CloseEnemyB call the AA gate guards, not some other later use.
private _window = _afterTarget select [0,80];
if (
    (_window find "RYD_CloseEnemyB") < 0
    || {((_tail select [0,_relative]) find "_chVP") < 0}
) exitWith {
    ["aa-reference-context-missing",[_window]] call _finishFailure
};

private _target = _tailAt + _relative;
private _patched = (_source select [0,_target]) + "_AAthreat" +
    (_source select [_target + (count "_ATthreat")]);

private _compiled = compile _patched;
if !(_compiled isEqualType {}) exitWith {
    ["recompile-failed",[typeName _compiled]] call _finishFailure
};
// The recompiled function has to read back with the AIR branch's measurement
// fixed and nothing left to patch, or it is not the function we meant to build.
private _verify = ([toString _compiled] call ITW_CLASH_HALDispatcherAAFix_fnc_Unwrap)#0;
private _verifyGate = [_verify,"_AAthreat"] call ITW_CLASH_HALDispatcherAAFix_fnc_LastIndexOf;
if (
    _verifyGate < 0
    || {((_verify select [_verifyGate + (count "_AAthreat")]) find "_ATthreat") >= 0}
    || {(_verify find "_AAriskResign") < 0}
) exitWith {
    ["verification-failed",[count _verify,_verifyGate]] call _finishFailure
};

RYD_Dispatcher = _compiled;
if (!isNil "SKL_fnc_CompileFinal") then {
    ["ITW_CLASH_HALDispatcherAAFix_fnc_LastIndexOf"] call SKL_fnc_CompileFinal;
    ["ITW_CLASH_HALDispatcherAAFix_fnc_Unwrap"] call SKL_fnc_CompileFinal;
};

ITW_CLASH_HALDispatcherAAFixReady = true;
ITW_CLASH_HALDispatcherAAFixFinished = true;
["patched",[_target,count _source,_wrapped]] call ITW_CLASH_HALDispatcherAAFix_fnc_Log;
diag_log format [
    "CLASH BOOT | hal-dispatcher-aa-fix-ready | version=%1 patched=true offset=%2 length=%3 braces=%4 nr6Untouched=true",
    ITW_CLASH_HALDispatcherAAFixVersion,
    _target,
    count _source,
    _wrapped
];
true
