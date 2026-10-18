#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AirIdleDiagStarted",false]) exitWith {true};

ITW_CLASH_AirIdleDiagStarted = true;
ITW_CLASH_AirIdleDiagVersion = 1;

/*
    Why a HAL helicopter is not being sent. Observe only: it reads HAL's own
    lists and runs HAL's own ammo helpers, and writes nothing HAL reads.

    Hark, 2026-10-17 run 4: "stub wing helicopters no longer move out". Seven
    stub-wing Ghost Hawks (four WEST, three GUER) were handed to HAL and none
    flew a sortie; a GUER one hovered over its spawn at 48 m from 17:21 to
    17:53. The 04:49 run had eight stub-wing sorties. Nothing at the hand-off
    differed (same class taxonomy, same loadout, same DUAL deployment, not
    busy, not unable, not on NoAttack), and HAL does not say why it passes a
    group over, so this does.

    HAL only sends a group it has put in AttackAv (HQOrders.sqf:159-213),
    which needs all of:
      - not Busy, not Unable, not already FlankAv;
      - not on its exclusion lists: ReconG, FOG, NCCargoG (less NCrewInfG),
        SupportG, NoAttack, StaticG, ArtG, SpecForG, AmmoDrop, CargoOnly;
      - the vehicle: canMove, fuel above 0.1, damage at most 0.5, and for an
        armed aircraft at least one magazine;
      - the crew: RYD_AmmoFullCount at 0.15 or more, every man at most 0.5
        damaged and able to stand, and its strength: summed damage plus the
        men missing since HAL first counted it ("Nominal"), over the men
        left, at most 0.4 x (recklessness / 1.2 + 1).
    Its air dispatch then also draws from AirG less NCAirG, NCrewInfG and
    AmmoDrop, and resigns near known AA (RydHQ_AAthreat within 1500 m of the
    run). Each line here gives every one of those for one helicopter.

    dual-hal-air-idle (every Poll seconds, each helicopter group HAL lists
    that has no waypoint left and is not Busy):
      [group, side, class, height, blocks, ammoFull, ammoCount, magazines,
       fuel, damage, canMove, lists it is on, AA HAL knows of, nearest of
       them in metres, [men HAL first counted, men now]]
    "blocks" names each AttackAv gate it fails; [] means HAL may send it.

    First answer (2026-10-18): both GUER stub-wings blocked by "NCCargoG" and
    "air-pool-NCAirG", HAL's autofill having filed a pylon-armed class as
    unarmed lift. Fixed in ITW_CLASH_HALTaxonomy.sqf v4.

    From the console (Local Exec on a hosted game, Server Exec on a
    dedicated one), now, with the same fields:
      [] call ITW_CLASH_AirIdleDiag_fnc_Report;
*/

ITW_CLASH_AirIdleDiagEnabled = missionNamespace getVariable ["ITW_CLASH_AirIdleDiagEnabled",true];
ITW_CLASH_AirIdleDiagPoll = missionNamespace getVariable ["ITW_CLASH_AirIdleDiagPoll",120];

ITW_CLASH_AirIdleDiag_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        [_event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH AIR IDLE | %1 | %2",_event,_payload];
    };
};

// One helicopter group, every gate HAL applies before it can be sent.
ITW_CLASH_AirIdleDiag_fnc_Gates = {
    params ["_hq","_group"];
    private _veh = vehicle (leader _group);
    private _on = {params ["_name"]; _group in (_hq getVariable [_name,[]])};
    private _blocks = [];
    if (_group getVariable ["Busy" + str _group,false]) then {_blocks pushBack "busy"};
    if (_group getVariable ["Unable",false]) then {_blocks pushBack "unable"};
    if (["RydHQ_FlankAv"] call _on) then {_blocks pushBack "flank"};
    {
        if ([_x] call _on) then {_blocks pushBack (_x select [7])};
    } forEach [
        "RydHQ_reconG","RydHQ_FOG","RydHQ_SupportG","RydHQ_NoAttack","RydHQ_StaticG",
        "RydHQ_ArtG","RydHQ_SpecForG","RydHQ_AmmoDrop","RydHQ_CargoOnly"
    ];
    if ((["RydHQ_NCCargoG"] call _on) && {!(["RydHQ_NCrewInfG"] call _on)}) then {_blocks pushBack "NCCargoG"};
    private _ncVeh = _hq getVariable ["RydHQ_NCVeh",[]];
    private _ammoFull = if (isNil "RYD_AmmoFullCount") then {-1} else {[_group,_ncVeh] call RYD_AmmoFullCount};
    private _ammoCount = if (isNil "RYD_AmmoCount") then {-1} else {[_group,_ncVeh] call RYD_AmmoCount};
    private _armedAir = (["RydHQ_AirG"] call _on) && {!(["RydHQ_NCAirG"] call _on)};
    if (!canMove _veh) then {_blocks pushBack "cannot-move"};
    if ((fuel _veh) <= 0.1) then {_blocks pushBack "fuel"};
    if ((damage _veh) > 0.5) then {_blocks pushBack "damage"};
    if (_armedAir && {(count (magazines _veh)) == 0}) then {_blocks pushBack "no-magazines"};
    if (_ammoFull >= 0 && {_ammoFull < 0.15}) then {_blocks pushBack "ammo-full-count"};
    if (((units _group) findIf {(damage _x) > 0.5 || {!canStand _x}}) >= 0) then {_blocks pushBack "crew-hurt"};
    // HAL's strength test (HQOrders.sqf:190-197): damage summed over the crew
    // plus the men missing since HAL first counted the group ("Nominal").
    private _current = count (units _group);
    private _nominal = _group getVariable ["Nominal" + str _group,_current];
    private _gDamage = _nominal - _current;
    {_gDamage = _gDamage + (damage _x)} forEach (units _group);
    private _reck = _hq getVariable ["RydHQ_Recklessness",0.5];
    if ((_gDamage / (_current + 0.1)) > (0.4 * ((_reck / 1.2) + 1))) then {_blocks pushBack "strength"};
    private _lists = [
        "RydHQ_Friends","RydHQ_AirG","RydHQ_NCAirG","RydHQ_NCrewInfG","RydHQ_BAirG","RydHQ_RCAS",
        "RydHQ_AttackAv","RydHQ_CombatAv","RydHQ_Exhausted","RydHQ_Garrison"
    ] select {[_x] call _on};
    if (_armedAir && {["RydHQ_NCrewInfG"] call _on}) then {_blocks pushBack "air-pool-NCrewInfG"};
    if ((["RydHQ_AirG"] call _on) && {["RydHQ_NCAirG"] call _on}) then {_blocks pushBack "air-pool-NCAirG"};
    if !(["RydHQ_AirG"] call _on) then {_blocks pushBack "not-AirG"};
    private _aa = (_hq getVariable ["RydHQ_AAthreat",[]]) select {!isNull _x && {!isNull leader _x}};
    private _nearest = -1;
    {
        private _d = _veh distance2D (vehicle (leader _x));
        if (_nearest < 0 || {_d < _nearest}) then {_nearest = _d};
    } forEach _aa;
    [
        if (isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {groupId _group} else {[_group] call ITW_CLASH_DualHAL_fnc_GroupId},
        str (side _group),typeOf _veh,round ((getPosATL _veh)#2),_blocks,
        (round (_ammoFull * 100)) / 100,_ammoCount,count (magazines _veh),
        (round ((fuel _veh) * 100)) / 100,(round ((damage _veh) * 100)) / 100,canMove _veh,
        _lists,count _aa,round _nearest,[_nominal,_current]
    ]
};

// Every helicopter group either commander lists.
ITW_CLASH_AirIdleDiag_fnc_Report = {
    params [["_idleOnly",false]];
    private _out = [];
    {
        private _hq = missionNamespace getVariable [_x,grpNull];
        if (isNull _hq) then {continue};
        {
            private _group = _x;
            if (isNull _group || {isNull leader _group}) then {continue};
            if !((vehicle (leader _group)) isKindOf "Helicopter") then {continue};
            if (isPlayer (leader _group)) then {continue};
            if (_idleOnly && {
                (_group getVariable ["Busy" + str _group,false])
                || {(currentWaypoint _group) < (count (waypoints _group))}
            }) then {continue};
            _out pushBack ([_hq,_group] call ITW_CLASH_AirIdleDiag_fnc_Gates);
        } forEach (_hq getVariable ["RydHQ_Friends",[]]);
    } forEach ["ITW_CLASH_HALHQ","ITW_CLASH_BLUFORHQ"];
    if (!_idleOnly) then {
        {["air-idle-report",_x] call ITW_CLASH_AirIdleDiag_fnc_Log} forEach _out;
        if (hasInterface) then {copyToClipboard str _out};
    };
    _out
};

if (ITW_CLASH_AirIdleDiagEnabled) then {
    [] spawn {
        scriptName "ITW_CLASH_AirIdleDiag";
        waitUntil {sleep 5; (missionNamespace getVariable ["ITW_CLASH_HALReady",false]) || {missionNamespace getVariable ["ITW_GameOver",false]}};
        while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
            sleep ITW_CLASH_AirIdleDiagPoll;
            {["air-idle",_x] call ITW_CLASH_AirIdleDiag_fnc_Log} forEach ([true] call ITW_CLASH_AirIdleDiag_fnc_Report);
        };
    };
};

diag_log format [
    "CLASH BOOT | air-idle-diag-ready | version=%1 enabled=%2 poll=%3s observeOnly=true gates=HQOrders-AttackAv,air-pool,AA-threat console=ITW_CLASH_AirIdleDiag_fnc_Report",
    ITW_CLASH_AirIdleDiagVersion,
    ITW_CLASH_AirIdleDiagEnabled,
    ITW_CLASH_AirIdleDiagPoll
];
true
