#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_DebugPreflightStarted",false]) exitWith {true};

ITW_CLASH_DebugPreflightStarted = true;
ITW_CLASH_DebugPreflightVersion = 1;
ITW_CLASH_DebugPreflightReady = false;

/*
    The preflight report. Read-only.

    Fourteen modules went in without a single in-game run, and each one logs its
    own boot line somewhere in roughly two hundred "CLASH BOOT" lines. Finding
    out which of them actually came up means reading the whole RPT preamble and
    knowing what to look for.

    This collapses that into one block under one greppable prefix. It reads the
    ready flags the modules already publish, asks the ETB and the air picture
    for the state they already expose, and prints it. It issues no orders, it
    writes no HAL pool, and it never touches another module's state - if this
    file is deleted mid-campaign nothing else changes behaviour.

    Three passes:
      - boot, once the load settles, so a missing module is caught before anyone
        spends an hour wondering why nothing bought;
      - periodically, so a long run has checkpoints to diff against;
      - on demand, from the debug console, via fnc_Now.

    Reading it: grep the RPT for "CLASH PREFLIGHT". A module reported MISSING did
    not load and its consequence is printed beside it. A module reported WAITING
    loaded but has not finished binding - the two runtime patches are scheduled
    against HAL's own bind, so WAITING is expected for the first minute or two
    and a problem after that.
*/

ITW_CLASH_DebugPreflightEnabled = missionNamespace getVariable [
    "ITW_CLASH_DebugPreflightEnabled",true
];
// The "C.L.A.S.H. debug output" mission parameter. Level 1 puts the preflight
// summary in chat, level 2 adds the live decision chat on top. The report
// itself always goes to the RPT regardless, because it costs nothing.
ITW_CLASH_DebugPreflightParamLevel = missionNamespace getVariable ["ITW_ParamCLASHDebug",0];
if !(ITW_CLASH_DebugPreflightParamLevel isEqualType 0) then {
    ITW_CLASH_DebugPreflightParamLevel = 0
};
// Long enough for the scheduled runtime patches to have bound against HAL.
ITW_CLASH_DebugPreflightDelay = missionNamespace getVariable [
    "ITW_CLASH_DebugPreflightDelay",180
];
ITW_CLASH_DebugPreflightRepeat = missionNamespace getVariable [
    "ITW_CLASH_DebugPreflightRepeat",600
];

/*
    The manifest. One row per module: the flag it publishes, the name to print,
    and what is lost when it is absent. The consequence matters more than the
    status - a MISSING line that says what broke saves working it out from
    behaviour an hour later.

    "Started" is checked as well as "Ready" to tell a module that never loaded
    from one still binding, which is the whole difference between MISSING and
    WAITING.
*/
ITW_CLASH_DebugPreflightManifest = [
    ["ITW_CLASH_AirPicture","air picture","enemy air seen only at HAL's cycle rate"],
    ["ITW_CLASH_ETB","emerging threats budget","threat counters compete for Impasse tickets"],
    ["ITW_CLASH_HALThreatCoverage","threat coverage","AA and AT threats go unanswered"],
    ["ITW_CLASH_SPAAOverwatch","SPAA overwatch","HAL dispatches air defence forward as armor"],
    ["ITW_CLASH_RearBaseCRAM","rear-base C-RAM","rear bases have no air defence"],
    ["ITW_CLASH_FOBAirDefence","FOB air defence","AA squads stay where they spawned"],
    ["ITW_CLASH_HALFront","HAL front","threats answered anywhere on the map"],
    ["ITW_CLASH_HALDispatcherAAFix","dispatcher AA fix","air risk measured against AT threats"],
    ["ITW_CLASH_HALCargoDiceFix","cargo dice fix","troop lifts stay a map-wide coin flip"],
    ["ITW_CLASH_HotDrop","hot drop","no contested-corridor troop insertion"],
    ["ITW_CLASH_ThunderRunAirTiers","thunder run air tiers","supply runs blocked by any air contact"],
    ["ITW_CLASH_CounterBattery","counter-battery","shelling never reveals a firing position"],
    ["ITW_CLASH_ArtilleryScoot","artillery scoot","gun lines fire from one grid all mission"],
    ["ITW_CLASH_Colossus","colossus v0","no ground picture"],
    ["ITW_CLASH_HALReconLatch","recon latch","capture orders stay on HAL's RapidCapt dice"],
    ["ITW_CLASH_HALSoftArmorFix","soft-armor fix","soft vehicles dispatched at tanks with no risk check"],
    ["ITW_CLASH_AttackRestore","attack restore","medevac'd squads stay unable to attack"],
    ["ITW_CLASH_HALTaxonomy","hal taxonomy","HAL classifies vehicles from its own heuristics alone"],
    ["ITW_CLASH_HALWaypointGuard","waypoint guard","HAL drops capture waypoints on an undefined _wp0"]
];

// Chat is asked for either by the parameter or by the loud debugger already
// being on, so turning either one on is enough and turning both on is not loud
// twice.
ITW_CLASH_DebugPreflight_fnc_Speaks = {
    if (ITW_CLASH_DebugPreflightParamLevel >= 1) exitWith {true};
    missionNamespace getVariable ["ITW_CLASH_LoudDebugEnabled",false]
};

ITW_CLASH_DebugPreflight_fnc_Log = {
    params ["_line"];
    diag_log format ["CLASH PREFLIGHT | %1",_line];
    true
};

/*
    A module's state, from the flags it already publishes. Nothing here is
    derived or guessed: a module that loaded sets Started, and sets Ready when
    it has finished binding.
*/
ITW_CLASH_DebugPreflight_fnc_State = {
    params ["_prefix"];
    private _started = missionNamespace getVariable [_prefix + "Started",false];
    private _ready = missionNamespace getVariable [_prefix + "Ready",false];
    if (_ready isEqualTo true) exitWith {"READY"};
    if (_started isEqualTo true) exitWith {"WAITING"};
    "MISSING"
};

/*
    The module block. Ready modules collapse onto one line because a healthy
    stack should not cost thirty lines of RPT; anything not ready gets its own
    line with its consequence, because that is the line worth reading.
*/
ITW_CLASH_DebugPreflight_fnc_Modules = {
    private _ready = [];
    private _problems = [];
    {
        _x params ["_prefix","_label","_consequence"];
        private _state = [_prefix] call ITW_CLASH_DebugPreflight_fnc_State;
        if (_state isEqualTo "READY") then {
            _ready pushBack _label;
        } else {
            _problems pushBack [_state,_label,_consequence];
        };
    } forEach ITW_CLASH_DebugPreflightManifest;

    [format [
        "modules | %1/%2 ready",
        count _ready,
        count ITW_CLASH_DebugPreflightManifest
    ]] call ITW_CLASH_DebugPreflight_fnc_Log;
    if (_ready isNotEqualTo []) then {
        [format ["ready | %1",_ready joinString ", "]] call
            ITW_CLASH_DebugPreflight_fnc_Log;
    };
    {
        _x params ["_state","_label","_consequence"];
        [format ["%1 | %2 | %3",_state,_label,_consequence]] call
            ITW_CLASH_DebugPreflight_fnc_Log;
    } forEach _problems;
    count _problems
};

// Both commanders, skipping either one that is not bound yet.
ITW_CLASH_DebugPreflight_fnc_Commanders = {
    if (isNil "ITW_PlayerSide" || {isNil "ITW_EnemySide"}) exitWith {[]};
    if (isNil "ITW_CLASH_fnc_GetCommanderForSide") exitWith {[]};
    private _out = [];
    {
        private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
        if (!isNull _hq) then {_out pushBack [_x,_hq]};
    } forEach [ITW_PlayerSide,ITW_EnemySide];
    _out
};

/*
    Per-commander runtime facts, in the order the design doc says to check them.

    HAL's own cycle length is first because every corridor timer is measured in
    it: a 90-second cycle and a 20-second cycle are different games, and the
    denial windows are only legible once it is known.
*/
ITW_CLASH_DebugPreflight_fnc_Commander = {
    params ["_side","_hq"];
    private _cycle = -1;
    if (!isNil "ITW_CLASH_AirPicture_fnc_HALCycleSeconds") then {
        _cycle = [_hq] call ITW_CLASH_AirPicture_fnc_HALCycleSeconds;
    };
    private _front = _hq getVariable ["RydHQ_Front",locationNull];
    private _groups = count (_hq getVariable ["RydHQ_Friends",[]]);
    private _known = count (_hq getVariable ["RydHQ_KnEnemies",[]]);
    private _art = count (_hq getVariable ["RydHQ_ArtG",[]]);
    private _denials = 0;
    if (!isNil "ITW_CLASH_AirPicture_fnc_Denials") then {
        _denials = count ([_hq] call ITW_CLASH_AirPicture_fnc_Denials);
    };

    [format [
        "%1 | halCycle=%2s front=%3 groups=%4 known=%5 artillery=%6 airDenials=%7",
        _side,
        round _cycle,
        if (isNull _front) then {"none"} else {str (size _front)},
        _groups,
        _known,
        _art,
        _denials
    ]] call ITW_CLASH_DebugPreflight_fnc_Log;

    // The ETB already prints its own ledger line; asking it is better than
    // re-deriving a balance here and risking the two disagreeing.
    if (!isNil "ITW_CLASH_ETB_fnc_Status" && {
        missionNamespace getVariable ["ITW_CLASH_ETBReady",false]
    }) then {
        [_side] call ITW_CLASH_ETB_fnc_Status;
    };

    // COLOSSUS v0's whole output is its recommendation, so surface whether it
    // has produced one yet rather than making anyone go looking.
    if (!isNil "ITW_CLASH_Colossus_fnc_Read" && {
        missionNamespace getVariable ["ITW_CLASH_ColossusReady",false]
    }) then {
        private _picture = [_side] call ITW_CLASH_Colossus_fnc_Read;
        [format [
            "%1 | colossus objectives=%2",
            _side,
            count _picture
        ]] call ITW_CLASH_DebugPreflight_fnc_Log;
    };
    true
};

/*
    One report. Deliberately noisy at boot and quiet afterwards: the boot pass
    is the one that catches a module that never loaded, and the later passes
    exist to be diffed against it.
*/
ITW_CLASH_DebugPreflight_fnc_Report = {
    params [["_label","periodic"]];
    ["------------------------------------------------------------"] call
        ITW_CLASH_DebugPreflight_fnc_Log;
    // Why AI see what they see. setSkill is applied flat at ITW_Attack.sqf:1558,
    // so spotDistance and spotTime are whatever the difficulty param says - and
    // the server's own coefficients scale the result again. A run where squads
    // walk past each other at 25m is unreadable without these two numbers, and
    // ITW_FncGetServerAiDifficultySetting already computes them from a probe
    // logic's skillFinal; nothing logged them.
    private _serverSkill = -1;
    if (!isNil "ITW_FncGetServerAiDifficultySetting") then {
        _serverSkill = call ITW_FncGetServerAiDifficultySetting;
    };
    private _coefficients = missionNamespace getVariable ["SERVER_AI_DIFFICULTY_SETTING",[]];
    [format [
        "ai | paramDifficulty=%1 paramFriendly=%2 serverSkill=%3 serverPrecision=%4",
        missionNamespace getVariable ["ITW_ParamDifficulty",-1],
        missionNamespace getVariable ["ITW_ParamFriendlySquadSkill",-1],
        if (_serverSkill < 0) then {"unknown"} else {(round (_serverSkill * 100)) / 100},
        if ((count _coefficients) < 2) then {"unknown"} else {(round ((_coefficients#1) * 100)) / 100}
    ]] call ITW_CLASH_DebugPreflight_fnc_Log;

    [format [
        "%1 | t=%2s version=%3 paramLevel=%4 loudDebug=%5",
        _label,
        round time,
        ITW_CLASH_DebugPreflightVersion,
        ITW_CLASH_DebugPreflightParamLevel,
        missionNamespace getVariable ["ITW_CLASH_LoudDebugEnabled",false]
    ]] call ITW_CLASH_DebugPreflight_fnc_Log;

    private _problems = call ITW_CLASH_DebugPreflight_fnc_Modules;

    private _commanders = call ITW_CLASH_DebugPreflight_fnc_Commanders;
    if (_commanders isEqualTo []) then {
        ["WARNING | no commander bound | nothing below this line is meaningful"] call
            ITW_CLASH_DebugPreflight_fnc_Log;
    };
    {_x call ITW_CLASH_DebugPreflight_fnc_Commander} forEach _commanders;

    ["------------------------------------------------------------"] call
        ITW_CLASH_DebugPreflight_fnc_Log;

    // Mirrored to chat only when it was asked for, so this never speaks in a run
    // nobody asked to be told about.
    if (call ITW_CLASH_DebugPreflight_fnc_Speaks) then {
        private _text = if (_problems > 0) then {
            format ["PREFLIGHT: %1 module(s) not ready - see RPT",_problems]
        } else {
            format [
                "PREFLIGHT: all %1 modules ready",
                count ITW_CLASH_DebugPreflightManifest
            ]
        };
        [_text] remoteExecCall ["systemChat",0];
    };
    _problems
};

// For the debug console, mid-run, when something looks wrong and the next
// scheduled pass is minutes away.
ITW_CLASH_DebugPreflight_fnc_Now = {
    ["on-demand"] call ITW_CLASH_DebugPreflight_fnc_Report
};

[] spawn {
    scriptName "ITW_CLASH_DebugPreflight";
    if (!ITW_CLASH_DebugPreflightEnabled) exitWith {
        ["disabled | no preflight report this run"] call
            ITW_CLASH_DebugPreflight_fnc_Log;
    };
    private _deadline = time + ITW_CLASH_DebugPreflightDelay;
    waitUntil {
        sleep 5;
        time >= _deadline || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};
    ["boot"] call ITW_CLASH_DebugPreflight_fnc_Report;

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        private _next = time + ITW_CLASH_DebugPreflightRepeat;
        waitUntil {
            sleep 5;
            time >= _next || {missionNamespace getVariable ["ITW_GameOver",false]}
        };
        if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};
        ["periodic"] call ITW_CLASH_DebugPreflight_fnc_Report;
    };
};

ITW_CLASH_DebugPreflightReady = true;
diag_log format [
    "CLASH BOOT | debug-preflight-ready | version=%1 delay=%2 repeat=%3 modules=%4 paramLevel=%5 chat=%6 readOnly=true",
    ITW_CLASH_DebugPreflightVersion,
    ITW_CLASH_DebugPreflightDelay,
    ITW_CLASH_DebugPreflightRepeat,
    count ITW_CLASH_DebugPreflightManifest,
    ITW_CLASH_DebugPreflightParamLevel,
    call ITW_CLASH_DebugPreflight_fnc_Speaks
];
true
