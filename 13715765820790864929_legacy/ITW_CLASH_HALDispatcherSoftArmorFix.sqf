#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALSoftArmorFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALSoftArmorFixReady",false]
};

ITW_CLASH_HALSoftArmorFixStarted = true;
ITW_CLASH_HALSoftArmorFixReady = false;
ITW_CLASH_HALSoftArmorFixVersion = 1;
scriptName "ITW_CLASH_HALDispatcherSoftArmorFix";

/*
    Trucks drive up to tanks because only armour ever checks for armour.

    RYD_Dispatcher's AT-risk resignation is gated on the chosen group being in
    _LArmorG or _HArmorG (HAC_fnc.sqf:1650). A soft-skinned vehicle group
    dispatched under an INF pattern is in neither pool, so it never runs the
    check at all: it is sent at a known tank with no risk assessment whatsoever,
    drives into gun range, and dies. The armour branch beside it and the ARM
    pattern below it both do the check properly.

    The fix appends one list to that one expression. HAL's own resignation -
    its distances, its recklessness scaling, its random roll - then applies to
    soft vehicle groups exactly as it already does to armour. No new doctrine,
    no second opinion about whether to go, and the smallest patch surface this
    could have: a single "+ list" inside a parenthesised group of pool lookups.

    ITW_CLASH_SoftVehicleGroups is what C.L.A.S.H. puts in that list. It holds
    the groups whose leader is riding in something the air picture grades as
    unprotected, refreshed on its own clock. Dismounted infantry is deliberately
    NOT in it - an AT team on foot is a legitimate answer to a tank, and
    grading a man would sweep every rifle squad into resigning.

    Defined before the patch is written and never cleared, because a nil global
    inside the dispatcher would throw on every dispatch for the rest of the
    mission.
*/

// Must exist before the patched dispatcher can ever run.
ITW_CLASH_SoftVehicleGroups = missionNamespace getVariable [
    "ITW_CLASH_SoftVehicleGroups",[]
];
ITW_CLASH_HALSoftArmorPoll = missionNamespace getVariable [
    "ITW_CLASH_HALSoftArmorPoll",15
];

ITW_CLASH_HALSoftArmor_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["hal-soft-armor-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH HAL SOFT ARMOR | %1 | %2",_event,_payload];
    };
};

/*
    Mounted in something unprotected.

    Two conditions, and the first is what keeps infantry out: the leader has to
    actually be in a vehicle. A man on foot returns himself from `vehicle`, and
    a man's own config armour would grade 0 and sweep every rifle squad in.
*/
ITW_CLASH_HALSoftArmor_fnc_IsSoftMounted = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    private _leader = leader _group;
    if (isNull _leader || {!alive _leader}) exitWith {false};
    private _veh = vehicle _leader;
    if (_veh isEqualTo _leader) exitWith {false};
    if (isNull _veh || {!alive _veh}) exitWith {false};
    if (isNil "ITW_CLASH_AirPicture_fnc_ProtectionGrade") exitWith {false};
    ([typeOf _veh] call ITW_CLASH_AirPicture_fnc_ProtectionGrade) < 1
};

ITW_CLASH_HALSoftArmor_fnc_Refresh = {
    private _soft = [];
    {
        private _hq = _x;
        if (isNull _hq) then {continue};
        {
            if ([_x] call ITW_CLASH_HALSoftArmor_fnc_IsSoftMounted) then {
                _soft pushBackUnique _x;
            };
        } forEach (_hq getVariable ["RydHQ_Friends",[]]);
    } forEach ([] call ITW_CLASH_HALSoftArmor_fnc_Commanders);
    // Replaced wholesale rather than mutated, so a group that dismounts or is
    // destroyed leaves the list on the next pass with no bookkeeping.
    ITW_CLASH_SoftVehicleGroups = _soft;
    count _soft
};

ITW_CLASH_HALSoftArmor_fnc_Commanders = {
    if (isNil "ITW_CLASH_fnc_GetCommanderForSide") exitWith {[]};
    if (isNil "ITW_PlayerSide" || {isNil "ITW_EnemySide"}) exitWith {[]};
    ([ITW_PlayerSide,ITW_EnemySide] apply {
        [_x] call ITW_CLASH_fnc_GetCommanderForSide
    }) select {!isNull _x}
};

private _finishFailure = {
    params ["_reason",["_details",[]]];
    ITW_CLASH_HALSoftArmorFixReady = false;
    ["patch-failed",[_reason,_details]] call ITW_CLASH_HALSoftArmor_fnc_Log;
    diag_log format [
        "CLASH BOOT | WARNING | hal-soft-armor-fix-failed | reason=%1 details=%2 | stock HAL dispatcher retained, soft vehicles keep driving at armor",
        _reason,_details
    ];
    false
};

// Same unwrap the AA fix uses: a compiled function's text may or may not carry
// its own outer braces.
ITW_CLASH_HALSoftArmor_fnc_Unwrap = {
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
([_raw] call ITW_CLASH_HALSoftArmor_fnc_Unwrap) params ["_source","_wrapped"];
if (
    (_source find "_ATthreat") < 0
    || {(_source find "RYD_CloseEnemyB") < 0}
) exitWith {
    ["dispatcher-signature-missing",[count _source,_wrapped]] call _finishFailure
};

if ((_source find "ITW_CLASH_SoftVehicleGroups") >= 0) exitWith {
    ITW_CLASH_HALSoftArmorFixReady = true;
    ["already-fixed",[count _source]] call ITW_CLASH_HALSoftArmor_fnc_Log;
    diag_log "CLASH BOOT | hal-soft-armor-fix-ready | patched=false reason=already-fixed";
    true
};

/*
    The anchor is the one place the two armour pools are added together. It
    occurs exactly once in the dispatcher, which is what makes it safe to
    rewrite without quoting a source line that normalization may have reshaped:
    find every _LArmorG, keep the ones followed closely by _HArmorG, and refuse
    the patch unless there is precisely one.
*/
private _pairs = [];
private _scan = 0;
private _searching = true;
while {_searching} do {
    private _hit = (_source select [_scan]) find "_LArmorG";
    if (_hit < 0) then {
        _searching = false;
    } else {
        private _at = _scan + _hit;
        private _after = _source select [_at + (count "_LArmorG"),24];
        private _plus = _after find "+";
        private _h = _after find "_HArmorG";
        if (_plus >= 0 && {_h > _plus}) then {
            _pairs pushBack [_at,_at + (count "_LArmorG") + _h + (count "_HArmorG")];
        };
        _scan = _at + (count "_LArmorG");
    };
};
if ((count _pairs) != 1) exitWith {
    ["armor-pool-pair-not-unique",[count _pairs,count _source]] call _finishFailure
};

(_pairs#0) params ["_from","_to"];
// It has to be the resignation's own test, not some other use of the pools.
private _context = _source select [_to,120];
if (
    (_context find "_ATthreat") < 0
    || {((_source select [(_from - 40) max 0,40]) find "_chosen") < 0}
) exitWith {
    ["armor-pool-context-missing",[_source select [(_from - 40) max 0,160]]] call _finishFailure
};

private _patched = (_source select [0,_to]) + " + ITW_CLASH_SoftVehicleGroups" +
    (_source select [_to]);

private _compiled = compile _patched;
if !(_compiled isEqualType {}) exitWith {
    ["recompile-failed",[typeName _compiled]] call _finishFailure
};
private _verify = ([toString _compiled] call ITW_CLASH_HALSoftArmor_fnc_Unwrap)#0;
if (
    (_verify find "ITW_CLASH_SoftVehicleGroups") < 0
    || {(_verify find "RYD_CloseEnemyB") < 0}
    || {(_verify find "_ATthreat") < 0}
) exitWith {
    ["verification-failed",[count _verify]] call _finishFailure
};

RYD_Dispatcher = _compiled;
if (!isNil "SKL_fnc_CompileFinal") then {
    ["ITW_CLASH_HALSoftArmor_fnc_Unwrap"] call SKL_fnc_CompileFinal;
    ["ITW_CLASH_HALSoftArmor_fnc_IsSoftMounted"] call SKL_fnc_CompileFinal;
    ["ITW_CLASH_HALSoftArmor_fnc_Commanders"] call SKL_fnc_CompileFinal;
    ["ITW_CLASH_HALSoftArmor_fnc_Refresh"] call SKL_fnc_CompileFinal;
};

[] spawn {
    scriptName "ITW_CLASH_HALSoftArmorRefresh";
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        private _count = call ITW_CLASH_HALSoftArmor_fnc_Refresh;
        if (_count != (missionNamespace getVariable ["ITW_CLASH_HALSoftArmorLast",-1])) then {
            missionNamespace setVariable ["ITW_CLASH_HALSoftArmorLast",_count];
            ["tracking",[_count]] call ITW_CLASH_HALSoftArmor_fnc_Log;
        };
        sleep ITW_CLASH_HALSoftArmorPoll;
    };
};

ITW_CLASH_HALSoftArmorFixReady = true;
["patched",[_to,count _source,_wrapped]] call ITW_CLASH_HALSoftArmor_fnc_Log;
diag_log format [
    "CLASH BOOT | hal-soft-armor-fix-ready | version=%1 patched=true offset=%2 length=%3 braces=%4 poll=%5 infantryExcluded=true nr6Untouched=true",
    ITW_CLASH_HALSoftArmorFixVersion,
    _to,
    count _source,
    _wrapped,
    ITW_CLASH_HALSoftArmorPoll
];
true
