if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALNativeSFFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALNativeSFFixReady",false]
};

ITW_CLASH_HALNativeSFFixStarted = true;
ITW_CLASH_HALNativeSFFixReady = false;
ITW_CLASH_HALNativeSFFixFinished = false;
ITW_CLASH_HALNativeSFFixVersion = 1;
scriptName "ITW_CLASH_HALNativeSFFix";

private _finishFailure = {
    params ["_reason",["_details",[]]];
    ITW_CLASH_HALNativeSFFixReady = false;
    ITW_CLASH_HALNativeSFFixFinished = true;
    diag_log format [
        "CLASH BOOT | WARNING | native-sf-fix-failed | reason=%1 details=%2",
        _reason,
        _details
    ];
    false
};

// HAL_GoSFAttack/HAL_SFIdleOrd are assigned by NR6 VarInit from the readable
// addon SQF sources. Wait for that canonical binding to complete, then replace
// only the exact known-bad source fragments. Unknown NR6 source is never guessed.
private _deadline = diag_tickTime + 120;
waitUntil {
    sleep 0.05;
    (
        !isNil "RYD_Path" && {
            !isNil "HAL_GoSFAttack" && {
                !isNil "HAL_SFIdleOrd"
            }
        }
    ) || {diag_tickTime >= _deadline}
};

if (isNil "RYD_Path" || {isNil "HAL_GoSFAttack" || {isNil "HAL_SFIdleOrd"}}) exitWith {
    ["hal-runtime-bind-timeout",[]] call _finishFailure
};

private _idlePath = RYD_Path + "HAL\SFIdleOrd.sqf";
private _attackPath = RYD_Path + "HAL\GoSFAttack.sqf";
private _idleSource = preprocessFileLineNumbers _idlePath;
private _attackSource = preprocessFileLineNumbers _attackPath;

if (_idleSource isEqualTo "" || {_attackSource isEqualTo ""}) exitWith {
    ["native-source-missing",[_idlePath,_attackPath,count _idleSource,count _attackSource]] call _finishFailure
};

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

    [
        true,
        (_source select [0,_badAt]) + _good + (_source select [_tailAt]),
        _label + ":patched"
    ]
};

private _results = [];
private _step = [
    _idleSource,
    "while {((_isWater) or (_cnt > 100))} do",
    "while {_isWater && {_cnt < 100}} do",
    "SFIdleOrd-water-retry"
] call _replaceExact;
_results pushBack (_step#2);
if !(_step#0) exitWith {[_step#2,_results] call _finishFailure};
_idleSource = _step#1;

_step = [
    _attackSource,
    "_obj = _HQ getVariable [""RydHQ_Obj"",_ldr];",
    "_obj = _HQ getVariable [""RydHQ_Obj"",leader _HQ];",
    "GoSFAttack-objective-fallback"
] call _replaceExact;
_results pushBack (_step#2);
if !(_step#0) exitWith {[_step#2,_results] call _finishFailure};
_attackSource = _step#1;

_step = [
    _attackSource,
    "_posXWP3 = (_posXWP4 + (_BEnemyPos select 0))/2;",
    "_posXWP4 = (_posXWP4 + (_BEnemyPos select 0))/2;",
    "GoSFAttack-WP4-X"
] call _replaceExact;
_results pushBack (_step#2);
if !(_step#0) exitWith {[_step#2,_results] call _finishFailure};
_attackSource = _step#1;

_step = [
    _attackSource,
    "_posYWP3 = (_posYWP4 + (_BEnemyPos select 1))/2;",
    "_posYWP4 = (_posYWP4 + (_BEnemyPos select 1))/2;",
    "GoSFAttack-WP4-Y"
] call _replaceExact;
_results pushBack (_step#2);
if !(_step#0) exitWith {[_step#2,_results] call _finishFailure};
_attackSource = _step#1;

// Recompile the same two globals VarInit owns. This is intentionally a runtime
// correction rather than a second SF implementation, so all untouched HAL logic
// remains byte-for-byte source-equivalent after preprocessing.
HAL_SFIdleOrd = compile _idleSource;
HAL_GoSFAttack = compile _attackSource;

ITW_CLASH_HALNativeSFFixReady = true;
ITW_CLASH_HALNativeSFFixFinished = true;
diag_log format [
    "CLASH BOOT | native-sf-fix-ready | version=%1 sourceMatched=true results=%2 idleChars=%3 attackChars=%4",
    ITW_CLASH_HALNativeSFFixVersion,
    _results,
    count _idleSource,
    count _attackSource
];
true
