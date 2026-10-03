#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_LoudDebugStarted",false]) exitWith {true};

ITW_CLASH_LoudDebugStarted = true;
ITW_CLASH_LoudDebugVersion = 1;
ITW_CLASH_LoudDebugReady = false;

/*
    The loud debugger.

    Every air and budget decision already writes a parseable RPT line, which is
    the right record afterwards and useless while you are standing in the field
    watching a corridor close. This mirrors the interesting ones to in-game chat
    in plain language - "AIR CORRIDOR CLOSED ...", "X RESERVED FOR BACKLINE AA" -
    so a tester can see WHY the game just did something without alt-tabbing to a
    log.

    It is a debug surface and it is OFF by default. Nothing about it changes a
    decision: it is a formatter on the tail of logging that already happened. If
    it is disabled, or fails, every module keeps logging exactly as before.

    Hooking it costs each module one line in its own _fnc_Log, so an event added
    later is loud-capable for free. Events it has no sentence for still speak, in
    a generic form, rather than being silently dropped - a debugger that hides
    what it does not recognise is worse than a noisy one.
*/

// Driven by the "C.L.A.S.H. debug output" mission parameter: level 2 turns the
// live decision chat on from the lobby, so a tester never has to edit a file or
// remember a console command. An explicit ITW_CLASH_LoudDebugEnabled set before
// this file loads still wins, and fnc_Toggle still overrides either mid-mission.
ITW_CLASH_LoudDebugParamLevel = missionNamespace getVariable ["ITW_ParamCLASHDebug",0];
if !(ITW_CLASH_LoudDebugParamLevel isEqualType 0) then {ITW_CLASH_LoudDebugParamLevel = 0};
ITW_CLASH_LoudDebugEnabled = missionNamespace getVariable [
    "ITW_CLASH_LoudDebugEnabled",ITW_CLASH_LoudDebugParamLevel >= 2
];
// Sources to speak. Empty means every source that reports.
ITW_CLASH_LoudDebugSources = missionNamespace getVariable ["ITW_CLASH_LoudDebugSources",[]];
// Events this noisy are worth muting even while debugging: a per-commander
// heartbeat and a per-phase flight trace drown everything else.
ITW_CLASH_LoudDebugMuted = missionNamespace getVariable [
    "ITW_CLASH_LoudDebugMuted",["hot-drop|phase","hal-cargo-dice|lift-allowed"]
];
// The same line twice inside this window is said once.
ITW_CLASH_LoudDebugRepeat = missionNamespace getVariable ["ITW_CLASH_LoudDebugRepeat",8];
// Also mirror to the RPT with a marker, so a tester's screenshot and the log
// can be lined up afterwards.
ITW_CLASH_LoudDebugMirrorToLog = missionNamespace getVariable ["ITW_CLASH_LoudDebugMirrorToLog",true];

ITW_CLASH_LoudDebugLastSaid = createHashMap;

ITW_CLASH_LoudDebug_fnc_Position = {
    params ["_value"];
    if !(_value isEqualType []) exitWith {str _value};
    if (count _value < 2) exitWith {str _value};
    format ["%1,%2",round (_value#0),round (_value#1)]
};

// Plain-language sentence for an event, or "" to fall through to the generic
// form. One place, so the wording stays consistent across modules.
ITW_CLASH_LoudDebug_fnc_Sentence = {
    params ["_source","_event","_payload"];
    private _at = {[_payload param [_this,""]] call ITW_CLASH_LoudDebug_fnc_Position};
    private _p = {_payload param [_this,""]};

    switch (format ["%1|%2",_source,_event]) do {
        // ---- what closes and opens an air corridor ----
        case "air-picture|denial-opened": {
            format ["AIR CORRIDOR CLOSED BY %1 (%2) at %3 - commander %4, holds %5s",
                2 call _p,1 call _p,3 call _at,0 call _p,4 call _p]
        };
        case "air-picture|denial-closed": {
            format ["AIR CORRIDOR OPENED - %1 (%2) %3 after %4s unseen - commander %5",
                2 call _p,1 call _p,3 call _p,4 call _p,0 call _p]
        };
        case "air-picture|loss-area-closed": {
            format ["AIR CORRIDOR CLOSED BY LOSSES near %1 - %2 down - shut %3s (%4)",
                0 call _at,2 call _p,1 call _p,3 call _p]
        };
        case "air-picture|air-loss": {
            format ["AIRCRAFT LOST: %1 at %2",0 call _p,1 call _at]
        };
        case "air-picture|kill-trigger": {
            format ["ENEMY AIR KILLED OURS: %2 downed %3 at %4 - %1 counter-air funded now",
                0 call _p,1 call _p,2 call _p,3 call _at]
        };
        case "air-tiers|relaxed": {
            format ["CORRIDOR REOPENED BY TIERS - was %3, now %5 - %2 (commander %1)",
                0 call _p,1 call _p,2 call _p,3 call _p,4 call _p]
        };
        case "air-tiers|upheld": {
            format ["CORRIDOR STAYS CLOSED - hard kill confirmed (%4) - %2",
                0 call _p,1 call _p,2 call _p,3 call _p]
        };
        // ---- lift gating ----
        case "hal-cargo-dice|lift-refused": {
            format ["HELICOPTER LIFT REFUSED - route %4 to %5 is %2 (%3) - commander %1",
                0 call _p,1 call _p,2 call _p,3 call _at,4 call _at]
        };
        case "hal-cargo-dice|lift-allowed": {
            format ["HELICOPTER LIFT ALLOWED - route %2 - commander %1",1 call _p,0 call _p]
        };
        // ---- backline air defence ----
        case "spaa-overwatch|adopted": {
            format ["%2 RESERVED FOR BACKLINE AA - overwatch, never dispatched - commander %1",
                0 call _p,1 call _p]
        };
        case "spaa-overwatch|stationed": {
            format ["BACKLINE AA %1 %2 to %3 covering %4",
                1 call _p,5 call _p,3 call _at,4 call _at]
        };
        // ---- the flag that decides whether anyone attacks at all ----
        case "recon-latch|latched": {
            format ["RECON COMPLETE HELD FOR %1 - %2 enemy groups known, HAL stage %3 - capture orders unblocked",
                0 call _p,1 call _p,2 call _p]
        };
        case "recon-latch|holding": {
            format ["RECON FLAG RESTORED %2x FOR %1 - %3 enemy groups known - HAL reset every %4s keeps clearing it",
                0 call _p,1 call _p,2 call _p,3 call _p]
        };
        case "recon-latch|blind": {
            format ["RECON FLAG RELEASED FOR %1 - no enemy groups known, HAL may scout again (held %2x)",
                0 call _p,1 call _p]
        };
        case "rear-cram|placed": {
            format ["%2 EMPLACED AS REAR-BASE AIR DEFENCE at %3 - %1",
                0 call _p,1 call _p,2 call _at]
        };
        case "rear-cram|destroyed": {
            format ["REAR-BASE AIR DEFENCE DESTROYED - %1 - replaced in %2s",0 call _p,1 call _p]
        };
        case "rear-cram|replaced": {
            format ["REAR-BASE AIR DEFENCE REPLACED - %1",0 call _p]
        };
        case "fob-air-defence|sent": {
            format ["%2 RESERVED FOR BACKLINE AA - walking to FOB %3 (%4m) - commander %1",
                0 call _p,1 call _p,2 call _at,3 call _p]
        };
        case "fob-air-defence|handed-to-hal-garrison": {
            format ["%2 DUG IN AS FOB AIR DEFENCE at %3 - commander %1",
                0 call _p,1 call _p,2 call _at]
        };
        // ---- the budget ----
        case "etb|purchase": {
            format ["ETB BOUGHT %2 for %3 (cost %4) - commander %1 - threat %5",
                0 call _p,1 call _p,2 call _p,3 call _p,4 call _p]
        };
        case "etb|denied": {
            format ["ETB REFUSED %2 - %3 - commander %1",0 call _p,1 call _p,2 call _p]
        };
        case "etb|loss": {
            format ["ETB ASSET LOST: %2 (cost %3, no refund) - commander %1",
                0 call _p,1 call _p,2 call _p]
        };
        case "etb|idle-release": {
            format ["ETB RESERVE FREED - %2 idle %4s, still ours and still counted - commander %1",
                0 call _p,1 call _p,2 call _p,3 call _p]
        };
        // ---- demand ----
        case "hal-threat-coverage|demand-opened": {
            format ["DEMAND OPENED: %2 - threat %3, shortfall %4 - commander %1",
                0 call _p,1 call _p,2 call _p,3 call _p]
        };
        case "hal-threat-coverage|demand-closed": {
            format ["DEMAND CLOSED: %2 after %3s - commander %1",0 call _p,1 call _p,2 call _p]
        };
        case "hal-threat-coverage|provider-failed": {
            format ["PROVIDER FAILED for %2: %3 not employed, muted %4s - commander %1",
                0 call _p,1 call _p,2 call _p,3 call _p]
        };
        // ---- the hot drop ----
        case "hot-drop|claimed": {
            format ["HOT DROP: taking %2 into a %4 LZ (%5), %6m out - commander %1",
                0 call _p,1 call _p,2 call _p,3 call _p,4 call _p,5 call _p]
        };
        case "hot-drop|put-out": {
            format ["HOT DROP: troops out by %1 - %2 at %3m",0 call _p,1 call _p,3 call _p]
        };
        case "hot-drop|declined": {
            format ["HOT DROP DECLINED: %2 lift to a %4 corridor (%5) left with HAL - commander %1",
                0 call _p,1 call _p,2 call _p,3 call _p,4 call _p]
        };
        case "hot-drop|handback": {
            format ["HOT DROP %1: %2 handed back to HAL after %3s",0 call _p,1 call _p,2 call _p]
        };
        default {""};
    }
};

ITW_CLASH_LoudDebug_fnc_Say = {
    params ["_text"];
    if (_text isEqualTo "") exitWith {false};
    private _last = ITW_CLASH_LoudDebugLastSaid getOrDefault [_text,-1e6];
    if ((time - _last) < ITW_CLASH_LoudDebugRepeat) exitWith {false};
    ITW_CLASH_LoudDebugLastSaid set [_text,time];

    private _line = "CLASH: " + _text;
    [_line] remoteExecCall ["systemChat",0];
    if (ITW_CLASH_LoudDebugMirrorToLog) then {
        diag_log ("CLASH LOUD | " + _text);
    };
    true
};

/*
    The hook every module's own logger calls. Deliberately total: anything a
    module reports can be spoken, with a curated sentence where there is one and
    a generic rendering where there is not.
*/
ITW_CLASH_LoudDebug_fnc_Emit = {
    params ["_source","_event",["_payload",[]]];
    if (!ITW_CLASH_LoudDebugEnabled) exitWith {false};
    private _key = format ["%1|%2",_source,_event];
    if (_key in ITW_CLASH_LoudDebugMuted) exitWith {false};
    if (
        ITW_CLASH_LoudDebugSources isNotEqualTo []
        && {!(_source in ITW_CLASH_LoudDebugSources)}
    ) exitWith {false};

    private _text = [_source,_event,_payload] call ITW_CLASH_LoudDebug_fnc_Sentence;
    if (_text isEqualTo "") then {
        // No sentence for this one: say it anyway rather than hide it.
        _text = format ["%1 %2 %3",toUpperANSI _source,toUpperANSI _event,_payload];
    };
    [_text] call ITW_CLASH_LoudDebug_fnc_Say
};

// Turn it on or off from the debug console mid-mission, without a restart.
ITW_CLASH_LoudDebug_fnc_Toggle = {
    params [["_on",!ITW_CLASH_LoudDebugEnabled]];
    ITW_CLASH_LoudDebugEnabled = _on;
    [format ["LOUD DEBUG %1",if (_on) then {"ON"} else {"OFF"}]] call
        ITW_CLASH_LoudDebug_fnc_Say;
    diag_log format ["CLASH BOOT | loud-debug-toggled | enabled=%1",_on];
    _on
};

ITW_CLASH_LoudDebugReady = true;
diag_log format [
    "CLASH BOOT | loud-debug-ready | version=%1 enabled=%2 paramLevel=%6 sources=%3 muted=%4 repeat=%5 channel=systemChat decisionsUnaffected=true",
    ITW_CLASH_LoudDebugVersion,
    ITW_CLASH_LoudDebugEnabled,
    ITW_CLASH_LoudDebugSources,
    ITW_CLASH_LoudDebugMuted,
    ITW_CLASH_LoudDebugRepeat,
    ITW_CLASH_LoudDebugParamLevel
];
true
