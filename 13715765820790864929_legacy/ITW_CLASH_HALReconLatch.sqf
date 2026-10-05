#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALReconLatchStarted",false]) exitWith {true};

ITW_CLASH_HALReconLatchStarted = true;
ITW_CLASH_HALReconLatchVersion = 1;
ITW_CLASH_HALReconLatchReady = false;

/*
    RydHQ_ReconDone, latched.

    HAL will not issue a capture order unless RydHQ_ReconDone is true. The
    alternative branch is a dice roll - RapidCapt (10) x (Recklessness + 0.01),
    about 5% per HAL cycle - so with ReconDone false a commander sits on a full
    order of battle and almost never attacks. A 20 minute run showed exactly
    that: 29 friendly groups, 37 included, two attack-available, nothing moving.

    Three things combine to hold the flag down, and only the third is ours.

    HAL dispatches recon only while the commander is completely blind
    (HQOrders.sqf:356 requires count RydHQ_KnEnemiesG == 0). After first
    contact, every recon tier - RAirG, reconG, FOG, snipersG - is skipped, so
    RydHQ_ReconStage can never climb again and GoRecon.sqf:732 can never set
    the flag.

    HAL_HQReset clears RydHQ_ReconDone and RydHQ_ReconStage unconditionally
    (HQReset.sqf:17-18). It resets ReconStage but NOT ReconStage2, which is the
    fingerprint this was diagnosed by: in the run, ReconStage2 stayed pinned at
    4 from the moment recon finished while ReconStage sat at 1 forever after.

    C.L.A.S.H. sets RydHQ_ResetTime to 30 (ITW_CLASH.sqf:2337) where HAL's own
    default is 600 (HQSitRepF.sqf:434), so that reset runs twenty times more
    often. Recon completed at 23:18:44 with the stage at 4; within thirty
    seconds the reset had wiped it; by 23:22:56 the commander knew of five
    enemy groups and the gate was shut for the rest of the mission.

    So the flag is earned once and then lost permanently. This restores it.

    The rule is the flag's own meaning: ReconDone says "I have scouted enough
    to attack", and a commander that knows where enemy groups are has scouted
    enough by any reading. So while a commander holds contact, the flag is held
    true. Nothing here invents an order, picks a target or touches another
    pool.

    It is a latch, never a controller: this file only ever writes true. When a
    commander goes blind again it stops holding the flag up and leaves it
    exactly as HAL left it, so HAL's own recon loop can run and set it the
    ordinary way. That is deliberate - a commander that has genuinely lost the
    enemy should scout again, and clearing the flag ourselves would be us
    deciding that, which is HAL's call.
*/

ITW_CLASH_HALReconLatchEnabled = missionNamespace getVariable [
    "ITW_CLASH_HALReconLatchEnabled",true
];
// Well under RydHQ_ResetTime, so a wipe is caught long before a HAL cycle can
// read the flag and fall through to the dice.
ITW_CLASH_HALReconLatchPoll = missionNamespace getVariable [
    "ITW_CLASH_HALReconLatchPoll",10
];
// Known enemy GROUPS, which is the same thing HQOrders.sqf:356 counts.
ITW_CLASH_HALReconLatchKnown = missionNamespace getVariable [
    "ITW_CLASH_HALReconLatchKnown",1
];
// One HAL cycle of grace, so a commander that spawns in contact still gets
// whatever recon it was going to get before the latch takes an interest.
ITW_CLASH_HALReconLatchSettle = missionNamespace getVariable [
    "ITW_CLASH_HALReconLatchSettle",120
];
// A reset every 30 seconds means a relatch every 30 seconds. Say so on a
// human timescale instead of twice a minute for the whole mission.
ITW_CLASH_HALReconLatchReportEvery = missionNamespace getVariable [
    "ITW_CLASH_HALReconLatchReportEvery",300
];

// side key -> [latched, relatches, lastReportAt, blind]
ITW_CLASH_HALReconLatchState = missionNamespace getVariable [
    "ITW_CLASH_HALReconLatchState",createHashMap
];

ITW_CLASH_HALReconLatch_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["recon-latch-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH RECON LATCH | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["recon-latch",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

ITW_CLASH_HALReconLatch_fnc_State = {
    params ["_side"];
    private _key = toUpperANSI str _side;
    private _state = ITW_CLASH_HALReconLatchState getOrDefault [_key,[]];
    if (_state isEqualTo []) then {
        _state = [false,0,-1e10,true];
        ITW_CLASH_HALReconLatchState set [_key,_state];
    };
    _state
};

// What HQOrders.sqf:356 counts, read the same way, so this agrees with the
// gate it is reasoning about rather than with a different notion of contact.
ITW_CLASH_HALReconLatch_fnc_Known = {
    params ["_hq"];
    if (isNull _hq) exitWith {0};
    private _known = _hq getVariable ["RydHQ_KnEnemiesG",[]];
    if !(_known isEqualType []) exitWith {0};
    count (_known select {!isNull _x})
};

/*
    One commander, one pass. Holds the flag up while there is contact, reports
    the first latch immediately and relatches quietly after that.
*/
ITW_CLASH_HALReconLatch_fnc_Hold = {
    params ["_side","_hq"];
    if (isNull _hq) exitWith {false};
    private _state = [_side] call ITW_CLASH_HALReconLatch_fnc_State;
    _state params ["_latched","_relatches","_reportedAt","_blind"];
    private _known = [_hq] call ITW_CLASH_HALReconLatch_fnc_Known;
    private _key = toUpperANSI str _side;

    if (_known < ITW_CLASH_HALReconLatchKnown) exitWith {
        // Blind again. Stand off and let HAL's own recon loop have it back.
        if (!_blind) then {
            _state set [3,true];
            ["blind",[_key,_relatches]] call ITW_CLASH_HALReconLatch_fnc_Log;
        };
        false
    };

    if (_blind) then {_state set [3,false]};
    private _done = _hq getVariable ["RydHQ_ReconDone",false];
    if (_done isEqualTo true) exitWith {false};

    _hq setVariable ["RydHQ_ReconDone",true];
    if (!_latched) then {
        _state set [0,true];
        _state set [2,time];
        ["latched",[
            _key,_known,_hq getVariable ["RydHQ_ReconStage",-1]
        ]] call ITW_CLASH_HALReconLatch_fnc_Log;
    } else {
        _state set [1,_relatches + 1];
        if ((time - _reportedAt) >= ITW_CLASH_HALReconLatchReportEvery) then {
            _state set [2,time];
            ["holding",[
                _key,_relatches + 1,_known,
                missionNamespace getVariable ["RydHQ_ResetTime",-1]
            ]] call ITW_CLASH_HALReconLatch_fnc_Log;
        };
    };
    true
};

[] spawn {
    scriptName "ITW_CLASH_HALReconLatch";
    waitUntil {
        sleep 1;
        (
            !isNil "ITW_CLASH_fnc_GetCommanderForSide"
            && {!isNil "ITW_PlayerSide"} && {!isNil "ITW_EnemySide"}
            && {missionNamespace getVariable ["ITW_CLASH_HALReady",false]}
        ) || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};
    sleep ITW_CLASH_HALReconLatchSettle;

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_HALReconLatchEnabled) then {
            {
                private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
                [_x,_hq] call ITW_CLASH_HALReconLatch_fnc_Hold;
            } forEach [ITW_PlayerSide,ITW_EnemySide];
        };
        sleep ITW_CLASH_HALReconLatchPoll;
    };
};

ITW_CLASH_HALReconLatchReady = true;
diag_log format [
    "CLASH BOOT | hal-recon-latch-ready | version=%1 poll=%2 known=%3 settle=%4 resetTime=%5 writesOnlyTrue=true",
    ITW_CLASH_HALReconLatchVersion,
    ITW_CLASH_HALReconLatchPoll,
    ITW_CLASH_HALReconLatchKnown,
    ITW_CLASH_HALReconLatchSettle,
    missionNamespace getVariable ["RydHQ_ResetTime",-1]
];
true
