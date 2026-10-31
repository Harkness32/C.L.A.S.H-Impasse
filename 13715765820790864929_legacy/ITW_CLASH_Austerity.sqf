#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AusterityStarted",false]) exitWith {true};

ITW_CLASH_AusterityStarted = true;
ITW_CLASH_AusterityVersion = 2;

/*
    Austerity: the server's ledger behind the reward HUD.

    Each player has their own cash, keyed by Steam id and kept for the session.
    The client only ever draws what this file sends it
    (ITW_CLASH_AusterityClient.sqf).

    It pays the draft prices from the 2026-10-27 brainstorm: a flat bonus for a
    finished job, never per head, with rescue on top and artillery last, and a
    bounty for a kill. Nothing spends this money yet. The base store still has
    its own wallet, per side and switched off.
*/
ITW_CLASH_AusterityEnabled = missionNamespace getVariable ["ITW_CLASH_AusterityEnabled",true];
ITW_CLASH_AusterityPoll = missionNamespace getVariable ["ITW_CLASH_AusterityPoll",0.5];

// Every finished job reads the same on the HUD, whatever it was.
ITW_CLASH_AusterityJobLabel = "TASK COMPLETE";
// Job type -> bonus. Paid to everyone on the job.
ITW_CLASH_AusterityJobPay = createHashMapFromArray [
    ["TRANSPORT_LIFT",1000],
    ["LOGISTICS_AMMO_SLING",500],
    ["RECON_REACQUIRE_CONTACT",300],
    ["ARTILLERY_FIRE_MISSION",100]
];
// A strike pays half the kill's bounty on top of the bounty itself.
ITW_CLASH_AusterityStrikePay = createHashMapFromArray [
    ["STRIKE_HEAVY_ARMOR",450],
    ["STRIKE_LIGHT_ARMOR",190],
    ["STRIKE_SOFT",60]
];
// One rescue job at one price, whoever is being carried home.
ITW_CLASH_AusterityRescueKinds = ["CSAR_CREW","MEDEVAC_SEVERE","MEDEVAC_SQUAD"];
ITW_CLASH_AusterityRescuePay = 1500;

ITW_CLASH_AusterityBountyMan = 25;
ITW_CLASH_AusterityBountyCar = 120;
ITW_CLASH_AusterityBountyAPC = 375;
ITW_CLASH_AusterityBountyTank = 900;
ITW_CLASH_AusterityBountyHelicopter = 500;
ITW_CLASH_AusterityBountyPlane = 900;
ITW_CLASH_AusterityBountyStatic = 60;
ITW_CLASH_AusterityBountyShip = 120;

ITW_CLASH_AusterityCash = createHashMap;
ITW_CLASH_AusterityPaid = createHashMap;

ITW_CLASH_Austerity_fnc_Log = {
    params ["_event",["_payload",[]]];
    diag_log format ["CLASH AUSTERITY | %1 | %2",_event,_payload];
};

ITW_CLASH_Austerity_fnc_PublishCash = {
    params [["_uid",""],["_delta",0],["_label",""],["_kind","sync"]];
    if (_uid isEqualTo "") exitWith {false};
    private _index = allPlayers findIf {getPlayerUID _x == _uid};
    if (_index < 0) exitWith {false};
    [
        ITW_CLASH_AusterityCash getOrDefault [_uid,0],_delta,_label,_kind
    ] remoteExecCall ["ITW_CLASH_AusterityClient_fnc_ReceiveCash",owner (allPlayers#_index)];
    true
};

ITW_CLASH_Austerity_fnc_Award = {
    params [["_uid",""],["_amount",0],["_label",""],["_kind","kill"]];
    if (_uid isEqualTo "" || {_amount <= 0}) exitWith {false};
    private _cash = (ITW_CLASH_AusterityCash getOrDefault [_uid,0]) + _amount;
    ITW_CLASH_AusterityCash set [_uid,_cash];
    [_uid,_amount,_label,_kind] call ITW_CLASH_Austerity_fnc_PublishCash;
    ["cash-awarded",[_uid,_amount,_cash,_label,_kind]] call ITW_CLASH_Austerity_fnc_Log;
    true
};

// Each job or demand pays once, whatever the poll sees afterwards.
ITW_CLASH_Austerity_fnc_PayOnce = {
    params ["_key","_roster","_amount"];
    if (ITW_CLASH_AusterityPaid getOrDefault [_key,false]) exitWith {false};
    if (_roster isEqualTo []) exitWith {false};
    ITW_CLASH_AusterityPaid set [_key,true];
    {
        [_x param [0,""],_amount,ITW_CLASH_AusterityJobLabel,"job"] call ITW_CLASH_Austerity_fnc_Award;
    } forEach _roster;
    ["job-paid",[_key,_amount,count _roster]] call ITW_CLASH_Austerity_fnc_Log;
    true
};

ITW_CLASH_Austerity_fnc_SweepJobs = {
    {
        private _job = ITW_CLASH_PlayerJobs getOrDefault [_x,createHashMap];
        if ((_job getOrDefault ["state",""]) != "COMPLETED") then {continue};
        private _roster = _job getOrDefault ["participants",[]];
        private _type = _job getOrDefault ["type",""];
        if (_type isEqualTo "STRIKE_TARGET") then {
            [
                _x,_roster,
                ITW_CLASH_AusterityStrikePay getOrDefault [_job getOrDefault ["requestType",""],0]
            ] call ITW_CLASH_Austerity_fnc_PayOnce;
            continue
        };
        private _amount = ITW_CLASH_AusterityJobPay getOrDefault [_type,0];
        if (_amount > 0) then {
            [_x,_roster,_amount] call ITW_CLASH_Austerity_fnc_PayOnce;
        };
    } forEach (keys ITW_CLASH_PlayerJobs);
};

ITW_CLASH_Austerity_fnc_SweepRescues = {
    if (isNil "ITW_CLASH_PlayerDemands") exitWith {};
    {
        private _demand = ITW_CLASH_PlayerDemands getOrDefault [_x,createHashMap];
        if ((_demand getOrDefault ["state",""]) != "COMPLETED") then {continue};
        if !((_demand getOrDefault ["kind",""]) in ITW_CLASH_AusterityRescueKinds) then {continue};
        [
            _x,
            [_demand getOrDefault ["reservedGroup",grpNull]] call ITW_CLASH_PlayerTasks_fnc_HumanRoster,
            ITW_CLASH_AusterityRescuePay
        ] call ITW_CLASH_Austerity_fnc_PayOnce;
    } forEach (keys ITW_CLASH_PlayerDemands);
};

// 0 for anything without a price. Tanks and APCs share a base class, so the
// editor's own category tells them apart.
ITW_CLASH_Austerity_fnc_Bounty = {
    params ["_killed"];
    if (_killed isKindOf "CAManBase") exitWith {ITW_CLASH_AusterityBountyMan};
    private _subcategory = getText (configOf _killed >> "editorSubcategory");
    if (_subcategory isEqualTo "EdSubcat_Tanks") exitWith {ITW_CLASH_AusterityBountyTank};
    if (_subcategory isEqualTo "EdSubcat_APCs") exitWith {ITW_CLASH_AusterityBountyAPC};
    if (_killed isKindOf "Helicopter") exitWith {ITW_CLASH_AusterityBountyHelicopter};
    if (_killed isKindOf "Plane") exitWith {ITW_CLASH_AusterityBountyPlane};
    if (_killed isKindOf "StaticWeapon") exitWith {ITW_CLASH_AusterityBountyStatic};
    if (_killed isKindOf "Ship") exitWith {ITW_CLASH_AusterityBountyShip};
    // Tracked AA and artillery are filed under neither category above.
    if (_killed isKindOf "Tank") exitWith {ITW_CLASH_AusterityBountyAPC};
    if (_killed isKindOf "Car") exitWith {ITW_CLASH_AusterityBountyCar};
    0
};

// A vehicle with nobody aboard belongs to no side, so an empty hull pays nothing.
ITW_CLASH_Austerity_fnc_WasEnemy = {
    params ["_killed"];
    private _owner = if (_killed isKindOf "CAManBase") then {group _killed} else {
        group ((crew _killed) param [0,objNull])
    };
    !isNull _owner && {side _owner == ITW_EnemySide}
};

// The player who gets the kill: the shooter, or the commander of an AI gunner.
ITW_CLASH_Austerity_fnc_Shooter = {
    params ["_killer","_instigator"];
    private _shooter = if (isNull _instigator) then {effectiveCommander _killer} else {_instigator};
    if (isNull _shooter) exitWith {objNull};
    if (!isPlayer _shooter) then {_shooter = effectiveCommander (vehicle _shooter)};
    if (isNull _shooter || {!isPlayer _shooter} || {side group _shooter != ITW_PlayerSide}) exitWith {objNull};
    _shooter
};

ITW_CLASH_Austerity_fnc_OnKilled = {
    params ["_killed","_killer","_instigator"];
    if (isNull _killed || {isNil "ITW_EnemySide"} || {isNil "ITW_PlayerSide"}) exitWith {false};
    private _shooter = [_killer,_instigator] call ITW_CLASH_Austerity_fnc_Shooter;
    if (isNull _shooter || {!([_killed] call ITW_CLASH_Austerity_fnc_WasEnemy)}) exitWith {false};
    [
        getPlayerUID _shooter,
        [_killed] call ITW_CLASH_Austerity_fnc_Bounty,
        toUpper getText (configOf _killed >> "displayName"),
        "kill"
    ] call ITW_CLASH_Austerity_fnc_Award
};

ITW_CLASH_Austerity_fnc_RequestSync = {
    params [["_player",objNull]];
    if (isNull _player || {!isPlayer _player}) exitWith {false};
    if (isRemoteExecuted && {remoteExecutedOwner != owner _player}) exitWith {false};
    [getPlayerUID _player] call ITW_CLASH_Austerity_fnc_PublishCash
};

if (!ITW_CLASH_AusterityEnabled) exitWith {
    ITW_CLASH_Austerity_fnc_RequestSync = {false};
    diag_log "CLASH BOOT | austerity-disabled";
    true
};

addMissionEventHandler ["EntityKilled",{_this call ITW_CLASH_Austerity_fnc_OnKilled}];

[] spawn {
    scriptName "ITW_CLASH_AusterityRewardObserver";
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        call ITW_CLASH_Austerity_fnc_SweepJobs;
        call ITW_CLASH_Austerity_fnc_SweepRescues;
        sleep ITW_CLASH_AusterityPoll;
    };
};

diag_log format [
    "CLASH BOOT | austerity-ready | version=%1 wallet=per-player persistence=session-only rescuePay=%2 manBounty=%3 storeLinked=false",
    ITW_CLASH_AusterityVersion,
    ITW_CLASH_AusterityRescuePay,
    ITW_CLASH_AusterityBountyMan
];

true
