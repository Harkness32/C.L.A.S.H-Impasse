#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALWaypointGuardStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALWaypointGuardReady",false]
};

ITW_CLASH_HALWaypointGuardStarted = true;
ITW_CLASH_HALWaypointGuardReady = false;
ITW_CLASH_HALWaypointGuardVersion = 1;
scriptName "ITW_CLASH_HALWaypointGuardFix";

/*
    HAL drops a capture waypoint when _wp0 is not defined.

        Error in expression <...(str _unitG),false])) then
        {if (_wp0 isEqualTo []) then {_wp0 = [_unitG,...
        Error Undefined variable in expression: _wp0

    That line is what adds the group's MOVE waypoint onto the objective
    (GoCapture.sqf:342). When it throws, the group gets no waypoint and simply
    does not go, silently.

    It is stock HAL, and C.L.A.S.H. did not write it - but C.L.A.S.H. is why it
    is being hit. Before RydHQ_ReconDone was held up, HAL almost never issued a
    capture order, so GoCapture almost never ran: the 100 minute run before the
    latch logged this zero times, and both runs after it logged it.

    GoRest shows the shape plainly - its _wp0 = [] sits inside a conditional
    block (GoRest.sqf:236) while two later reads assume it ran. GoCapture's
    initialiser looks top-level, so why its read is out of scope is not
    something this file claims to understand. The guard does not depend on
    knowing: isNil is exactly as true when the variable is missing for a reason
    nobody has traced.

    Every read of the form "_wp0 isEqualTo []" becomes
    "isNil ""_wp0"" || {_wp0 isEqualTo []}", which is identical wherever _wp0
    is defined and simply does not throw where it is not. Nothing else about
    HAL's logic changes: an undefined _wp0 now takes the same branch an empty
    one takes, which is the branch that creates the waypoint.
*/

ITW_CLASH_HALWaypointGuard_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["hal-waypoint-guard-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH HAL WAYPOINT GUARD | %1 | %2",_event,_payload];
    };
};

// The HAL orders that read _wp0 without being sure it exists.
ITW_CLASH_HALWaypointGuardTargets = [
    "HAL_GoCapture","HAL_GoRecon","HAL_GoAttInf","HAL_GoRest"
];

ITW_CLASH_HALWaypointGuard_fnc_Unwrap = {
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

// Replace every occurrence, not the first: GoRest reads _wp0 twice.
ITW_CLASH_HALWaypointGuard_fnc_ReplaceAll = {
    params ["_source","_needle","_replacement"];
    private _out = "";
    private _rest = _source;
    private _count = 0;
    private _searching = true;
    while {_searching} do {
        private _at = _rest find _needle;
        if (_at < 0) then {
            _searching = false;
        } else {
            _out = _out + (_rest select [0,_at]) + _replacement;
            _rest = _rest select [_at + (count _needle)];
            _count = _count + 1;
        };
    };
    [_out + _rest,_count]
};

ITW_CLASH_HALWaypointGuard_fnc_Patch = {
    params ["_name"];
    private _needle = "_wp0 isEqualTo []";
    private _replacement = "isNil ""_wp0"" || {_wp0 isEqualTo []}";

    private _fn = missionNamespace getVariable [_name,nil];
    if (isNil "_fn") exitWith {["absent",0]};
    if !(_fn isEqualType {}) exitWith {["not-code",0]};

    ([toString _fn] call ITW_CLASH_HALWaypointGuard_fnc_Unwrap) params ["_source","_wrapped"];
    if (_source isEqualTo "") exitWith {["text-unavailable",0]};
    if ((_source find "isNil ""_wp0""") >= 0) exitWith {["already-guarded",0]};
    if ((_source find _needle) < 0) exitWith {["no-read",0]};

    ([_source,_needle,_replacement] call ITW_CLASH_HALWaypointGuard_fnc_ReplaceAll) params [
        "_patched","_hits"
    ];
    if (_hits <= 0) exitWith {["no-read",0]};

    private _compiled = compile _patched;
    if !(_compiled isEqualType {}) exitWith {["recompile-failed",0]};
    private _verify = ([toString _compiled] call ITW_CLASH_HALWaypointGuard_fnc_Unwrap)#0;
    // The guard has to be there, and the waypoint call it protects has to have
    // survived the round trip.
    if (
        (_verify find "isNil ""_wp0""") < 0
        || {(_verify find "RYD_WPadd") < 0}
    ) exitWith {["verification-failed",0]};

    missionNamespace setVariable [_name,_compiled];
    ["patched",_hits]
};

[] spawn {
    scriptName "ITW_CLASH_HALWaypointGuard";
    private _deadline = diag_tickTime + 120;
    waitUntil {
        sleep 0.05;
        !isNil "HAL_GoCapture" || {diag_tickTime >= _deadline}
    };

    private _results = [];
    private _patched = 0;
    {
        ([_x] call ITW_CLASH_HALWaypointGuard_fnc_Patch) params ["_status","_hits"];
        _results pushBack format ["%1:%2",_x,_status];
        if (_status isEqualTo "patched") then {_patched = _patched + _hits};
        // A target that is missing or already correct is not a failure: HAL may
        // have fixed it upstream, or a modpack may not ship that order at all.
        if (_status in ["recompile-failed","verification-failed","not-code"]) then {
            diag_log format [
                "CLASH BOOT | WARNING | hal-waypoint-guard-failed | %1 | %2 | stock HAL order retained",
                _x,_status
            ];
        };
    } forEach ITW_CLASH_HALWaypointGuardTargets;

    ITW_CLASH_HALWaypointGuardReady = true;
    ["result",[_patched,_results]] call ITW_CLASH_HALWaypointGuard_fnc_Log;
    diag_log format [
        "CLASH BOOT | hal-waypoint-guard-ready | version=%1 guards=%2 targets=%3 nr6Untouched=true",
        ITW_CLASH_HALWaypointGuardVersion,
        _patched,
        _results joinString ","
    ];
};
true
