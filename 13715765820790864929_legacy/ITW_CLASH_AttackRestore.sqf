#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AttackRestoreStarted",false]) exitWith {true};

ITW_CLASH_AttackRestoreStarted = true;
ITW_CLASH_AttackRestoreVersion = 1;
ITW_CLASH_AttackRestoreReady = false;

/*
    Give a squad its weapons back after the medics are done with it.

    Eight files in this mission call `enableAttack false`. Two call
    `enableAttack true`, and both of those belong to unrelated paths - the GTFO
    withdrawal's own completion and the reconstitution transit fix. Everything
    else disables and never restores.

    For a purpose-spawned CASEVAC helicopter crew or ground ambulance crew that
    is correct: they exist only to carry casualties and should never stop to
    fight. But the same call is made on the CASUALTY'S OWN SQUAD -
    CASEVAC.sqf:764 orders it to an LZ and GroundMEDEVAC_Manager.sqf:112 orders
    it to a rally, both through functions that disable attack on the group they
    are given. Those are line groups. They get picked up, they get released
    back to HAL, and they spend the rest of the mission unable to shoot at
    anything.

    A 100 minute run logged 345 contact anomalies naming group-attack-disabled,
    including an APC cannon crew sitting 180 m from an enemy AT rifleman on RED
    with COMBAT behaviour, not engaging. That is what walking past the enemy
    looks like from the inside.

    Fixing it at each release path would mean tracing every exit of two large
    managers and hoping none was missed - and the evidence is that the misses
    are exactly the problem. This restores the invariant instead: a group that
    nothing currently owns should be able to defend itself.

    Deliberately conservative, because HAL disables attack too and restores it
    itself (GoRest.sqf:74/709, GoDefRecon.sqf:59/255, GoAttSniper.sqf:270/286).
    Restoring a group mid-rest would break HAL's own behaviour, so a group is
    left alone while HAL is running an order on it, while it is resting, while
    any service still claims it, and if it is a dedicated service crew.
*/

ITW_CLASH_AttackRestoreEnabled = missionNamespace getVariable [
    "ITW_CLASH_AttackRestoreEnabled",true
];
ITW_CLASH_AttackRestorePoll = missionNamespace getVariable [
    "ITW_CLASH_AttackRestorePoll",20
];
// Seen idle, unowned and disarmed for this long before anything is restored,
// so a handover that takes a moment is never raced.
ITW_CLASH_AttackRestoreGrace = missionNamespace getVariable [
    "ITW_CLASH_AttackRestoreGrace",30
];

ITW_CLASH_AttackRestore_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["attack-restore-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH ATTACK RESTORE | %1 | %2",_event,_payload];
    };
};

/*
    Is this group somebody's right now?

    Every exclusion here is a case where attack is disabled on purpose and
    somebody else is responsible for turning it back on.
*/
ITW_CLASH_AttackRestore_fnc_Owned = {
    params ["_group"];
    private _var = str _group;
    // A dedicated service crew: the vehicle is the point, it never fights.
    if (_group getVariable ["ITW_CLASH_CASEVAC",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_GroundMEDEVAC",false]) exitWith {true};
    // Still being carried, rallied or extracted.
    if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") exitWith {true};
    if ((_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") exitWith {true};
    // Withdrawing: the GTFO path disables attack on purpose and restores it
    // at ITW_CLASH.sqf:1428 when the withdrawal completes.
    if (_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_ResupplyClaimed",false]) exitWith {true};
    // HAL is running an order on it. GoRest and GoDefRecon disable attack for
    // the length of the order and re-enable it themselves.
    if (_group getVariable ["Busy" + _var,false]) exitWith {true};
    if (_group getVariable ["Resting" + _var,false]) exitWith {true};
    false
};

ITW_CLASH_AttackRestore_fnc_Sweep = {
    private _restored = 0;
    {
        private _group = _x;
        if (isNull _group) then {continue};
        if (((units _group) select {alive _x}) isEqualTo []) then {continue};
        if (((units _group) findIf {isPlayer _x}) >= 0) then {continue};
        if (attackEnabled _group) then {
            _group setVariable ["ITW_CLASH_AttackDisabledSince",nil];
            continue
        };
        if ([_group] call ITW_CLASH_AttackRestore_fnc_Owned) then {
            _group setVariable ["ITW_CLASH_AttackDisabledSince",nil];
            continue
        };

        // Unowned and disarmed. Start a clock rather than acting at once, so a
        // handover in progress is never raced.
        private _since = _group getVariable ["ITW_CLASH_AttackDisabledSince",-1];
        if (_since < 0) then {
            _group setVariable ["ITW_CLASH_AttackDisabledSince",time];
            continue
        };
        if ((time - _since) < ITW_CLASH_AttackRestoreGrace) then {continue};

        _group enableAttack true;
        {if (alive _x) then {_x enableAttack true}} forEach units _group;
        _group setVariable ["ITW_CLASH_AttackDisabledSince",nil];
        _restored = _restored + 1;
        ["restored",[
            groupId _group,
            str (side _group),
            typeOf (vehicle leader _group),
            round (time - _since)
        ]] call ITW_CLASH_AttackRestore_fnc_Log;
    } forEach allGroups;
    _restored
};

[] spawn {
    scriptName "ITW_CLASH_AttackRestore";
    waitUntil {
        sleep 1;
        (!isNil "ITW_PlayerSide" && {!isNil "ITW_EnemySide"})
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_AttackRestoreEnabled) then {
            call ITW_CLASH_AttackRestore_fnc_Sweep;
        };
        sleep ITW_CLASH_AttackRestorePoll;
    };
};

ITW_CLASH_AttackRestoreReady = true;
diag_log format [
    "CLASH BOOT | attack-restore-ready | version=%1 poll=%2 grace=%3 excludes=service-crew,in-service,withdrawing,resupply,busy,resting,players",
    ITW_CLASH_AttackRestoreVersion,
    ITW_CLASH_AttackRestorePoll,
    ITW_CLASH_AttackRestoreGrace
];
true
