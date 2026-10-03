#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_CounterBatteryStarted",false]) exitWith {true};

ITW_CLASH_CounterBatteryStarted = true;
ITW_CLASH_CounterBatteryVersion = 1;
ITW_CLASH_CounterBatteryReady = false;

/*
    Counter-battery: working out where the shelling came from.

    This is an ACQUISITION model, not a lookup. The server knows which gun fired
    every round, and using that directly would hand each commander a perfect
    map of the other's batteries - which is both a cheat and bad play, because
    it makes a gun line indefensible and shoot-and-scoot pointless.

    Instead a side earns a fix the way a real counter-battery radar does: by
    being shot at. Every artillery round is followed to its impact. If the
    rounds landed near that side's own people, the side acquires a fix on the
    firing position, with an error radius that shrinks as more rounds of the
    same mission are observed. Shelling nobody tells nobody anything.

    The fix is on where the gun WAS. ITW_CLASH_ArtilleryScoot.sqf moves a gun
    after it has fired, so a battery that displaces leaves a stale fix behind
    and a battery that sits still does not. The two files are each other's
    counterplay, and a fix is deliberately a lead rather than a target - what
    consumes it decides what to do about it.

    It observes and publishes. It never tasks, fires or buys anything.
*/

ITW_CLASH_CounterBatteryEnabled = missionNamespace getVariable ["ITW_CLASH_CounterBatteryEnabled",true];
// How near our people a round has to land before we have been shelled at all.
ITW_CLASH_CounterBatteryAcquireRadius = missionNamespace getVariable ["ITW_CLASH_CounterBatteryAcquireRadius",400];
// Error on the fix: wide on the first round, tightening as the mission goes on.
ITW_CLASH_CounterBatteryErrorFirst = missionNamespace getVariable ["ITW_CLASH_CounterBatteryErrorFirst",450];
ITW_CLASH_CounterBatteryErrorFloor = missionNamespace getVariable ["ITW_CLASH_CounterBatteryErrorFloor",120];
// Rounds observed at which the error reaches its floor.
ITW_CLASH_CounterBatteryErrorRounds = missionNamespace getVariable ["ITW_CLASH_CounterBatteryErrorRounds",4];
// A fix goes cold. Guns move, and an hour-old grid is a guess.
ITW_CLASH_CounterBatteryFixLife = missionNamespace getVariable ["ITW_CLASH_CounterBatteryFixLife",900];
// Rounds in flight are followed no longer than this, so nothing leaks.
ITW_CLASH_CounterBatteryFlightCap = missionNamespace getVariable ["ITW_CLASH_CounterBatteryFlightCap",120];
ITW_CLASH_CounterBatteryPoll = missionNamespace getVariable ["ITW_CLASH_CounterBatteryPoll",30];

// sideKey -> (fix key -> [position, firstSeenAt, lastSeenAt, rounds, error, shooterClass])
ITW_CLASH_CounterBatteryFixes = createHashMap;
// Guns we have already put a handler on.
ITW_CLASH_CounterBatteryWatched = [];

ITW_CLASH_CounterBattery_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["counter-battery-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH COUNTER BATTERY | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["counter-battery",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

ITW_CLASH_CounterBattery_fnc_SideKey = {
    params ["_side"];
    toUpperANSI str _side
};

ITW_CLASH_CounterBattery_fnc_Fixes = {
    params ["_side"];
    private _key = [_side] call ITW_CLASH_CounterBattery_fnc_SideKey;
    private _fixes = ITW_CLASH_CounterBatteryFixes getOrDefault [_key,createHashMap];
    if (count _fixes == 0) then {ITW_CLASH_CounterBatteryFixes set [_key,_fixes]};
    _fixes
};

// Error on a fix built from this many observed rounds.
ITW_CLASH_CounterBattery_fnc_Error = {
    params ["_rounds"];
    if (_rounds >= ITW_CLASH_CounterBatteryErrorRounds) exitWith {
        ITW_CLASH_CounterBatteryErrorFloor
    };
    private _span = ITW_CLASH_CounterBatteryErrorFirst - ITW_CLASH_CounterBatteryErrorFloor;
    private _progress = ((_rounds - 1) max 0) / ((ITW_CLASH_CounterBatteryErrorRounds - 1) max 1);
    ITW_CLASH_CounterBatteryErrorFirst - (_span * _progress)
};

/*
    One observed impact. The side that was shelled gains or sharpens a fix on
    the firing position; a round that lands near nobody is noted and dropped.
*/
ITW_CLASH_CounterBattery_fnc_Observe = {
    params ["_shooter","_shooterPosition","_impact"];
    if (_impact isEqualTo [] || {_shooterPosition isEqualTo []}) exitWith {false};
    private _shooterSide = if (isNull _shooter) then {sideUnknown} else {
        side (group effectiveCommander _shooter)
    };

    private _sides = [];
    if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
    if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};

    {
        private _side = _x;
        if (_side isEqualTo _shooterSide) then {continue};
        // Were any of this side's people near where the rounds fell?
        private _witnesses = (allUnits + vehicles) select {
            alive _x
            && {(getPosATL _x) distance2D _impact <= ITW_CLASH_CounterBatteryAcquireRadius}
            && {
                private _commander = effectiveCommander _x;
                private _owner = if (isNull _commander) then {_x} else {_commander};
                side (group _owner) isEqualTo _side
            }
        };
        if (_witnesses isEqualTo []) then {continue};

        private _fixes = [_side] call ITW_CLASH_CounterBattery_fnc_Fixes;
        private _key = if (isNull _shooter) then {str _shooterPosition} else {
            netId _shooter
        };
        if (_key isEqualTo "" || {_key isEqualTo "0:0"}) then {_key = str _shooter};
        private _entry = _fixes getOrDefault [_key,[]];
        if (_entry isEqualTo []) then {
            _fixes set [_key,[
                +_shooterPosition,time,time,1,
                [1] call ITW_CLASH_CounterBattery_fnc_Error,
                if (isNull _shooter) then {""} else {typeOf _shooter}
            ]];
            ["fix-acquired",[
                toUpperANSI str _side,
                if (isNull _shooter) then {"unknown"} else {typeOf _shooter},
                _shooterPosition apply {round _x},
                round ([1] call ITW_CLASH_CounterBattery_fnc_Error),
                count _witnesses
            ]] call ITW_CLASH_CounterBattery_fnc_Log;
        } else {
            private _rounds = (_entry#3) + 1;
            _entry set [0,+_shooterPosition];
            _entry set [2,time];
            _entry set [3,_rounds];
            _entry set [4,[_rounds] call ITW_CLASH_CounterBattery_fnc_Error];
            if (_rounds == ITW_CLASH_CounterBatteryErrorRounds) then {
                ["fix-sharpened",[
                    toUpperANSI str _side,_entry#5,
                    _shooterPosition apply {round _x},round (_entry#4),_rounds
                ]] call ITW_CLASH_CounterBattery_fnc_Log;
            };
        };
    } forEach _sides;
    true
};

/*
    Follow one round to the ground. The projectile is tracked rather than its
    firing solution read, so the impact is where the shell actually landed.
*/
ITW_CLASH_CounterBattery_fnc_Track = {
    params ["_shooter","_shooterPosition","_projectile"];
    if (isNull _projectile) exitWith {false};
    private _last = getPosATL _projectile;
    private _deadline = time + ITW_CLASH_CounterBatteryFlightCap;
    waitUntil {
        sleep 0.5;
        if (!isNull _projectile) then {_last = getPosATL _projectile};
        isNull _projectile || {time >= _deadline}
    };
    [_shooter,_shooterPosition,_last] call ITW_CLASH_CounterBattery_fnc_Observe
};

/*
    A gun gets our own Fired handler, in addition to HAL's own round counter.
    HAL's tells us a gun has been working; this tells us where its rounds went,
    which is the only thing that can honestly produce a fix.
*/
ITW_CLASH_CounterBattery_fnc_Watch = {
    params ["_veh"];
    if (isNull _veh) exitWith {false};
    if (_veh getVariable ["ITW_CLASH_CounterBatteryWatched",false]) exitWith {true};
    _veh setVariable ["ITW_CLASH_CounterBatteryWatched",true];
    ITW_CLASH_CounterBatteryWatched pushBackUnique _veh;

    _veh addEventHandler ["Fired",{
        params ["_unit","","","","","","_projectile"];
        if (!ITW_CLASH_CounterBatteryEnabled) exitWith {};
        if (isNull _projectile) exitWith {};
        [_unit,getPosATL _unit,_projectile] spawn {
            scriptName "ITW_CLASH_CounterBatteryTrack";
            _this call ITW_CLASH_CounterBattery_fnc_Track;
        };
    }];
    ["watching",[typeOf _veh,(getPosATL _veh) apply {round _x}]] call
        ITW_CLASH_CounterBattery_fnc_Log;
    true
};

// Every artillery piece in play, either side. Identified the way the echelon
// rule does it, from the config rather than a class list.
ITW_CLASH_CounterBattery_fnc_Sweep = {
    private _count = 0;
    {
        private _veh = _x;
        if (isNull _veh || {!alive _veh}) then {continue};
        if (_veh getVariable ["ITW_CLASH_CounterBatteryWatched",false]) then {continue};
        private _scanner = getNumber (configFile >> "CfgVehicles" >> typeOf _veh >> "artilleryScanner") == 1;
        if (!_scanner) then {continue};
        if ([_veh] call ITW_CLASH_CounterBattery_fnc_Watch) then {_count = _count + 1};
    } forEach vehicles;
    _count
};

/*
    The public read: what this side believes about the other's guns, as
    [position, error, rounds, lastSeenAt, shooterClass]. A lead, not a target -
    the position is where the rounds came from when they were fired, and the
    error is how sure we are.
*/
ITW_CLASH_CounterBattery_fnc_Leads = {
    params ["_side"];
    if !(_side isEqualType sideUnknown) exitWith {[]};
    private _fixes = [_side] call ITW_CLASH_CounterBattery_fnc_Fixes;
    private _result = [];
    {
        _y params ["_position","","_lastSeenAt","_rounds","_error","_class"];
        if ((time - _lastSeenAt) > ITW_CLASH_CounterBatteryFixLife) then {continue};
        _result pushBack [+_position,_error,_rounds,_lastSeenAt,_class];
    } forEach _fixes;
    // Sharpest first: the fix worth acting on is the one we are surest of.
    [_result,[],{_x#1},"ASCEND"] call BIS_fnc_sortBy
};

ITW_CLASH_CounterBattery_fnc_Expire = {
    private _dropped = 0;
    {
        private _fixes = _y;
        {
            private _entry = _fixes getOrDefault [_x,[]];
            if (_entry isEqualTo []) then {continue};
            if ((time - (_entry#2)) > ITW_CLASH_CounterBatteryFixLife) then {
                _fixes deleteAt _x;
                _dropped = _dropped + 1;
                ["fix-cold",[_entry#5,(_entry#0) apply {round _x},round (time - (_entry#2))]] call
                    ITW_CLASH_CounterBattery_fnc_Log;
            };
        } forEach (keys _fixes);
    } forEach ITW_CLASH_CounterBatteryFixes;
    _dropped
};

[] spawn {
    scriptName "ITW_CLASH_CounterBattery";
    waitUntil {
        sleep 1;
        (!isNil "ITW_PlayerSide" && {!isNil "ITW_EnemySide"})
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_CounterBatteryEnabled) then {
            call ITW_CLASH_CounterBattery_fnc_Sweep;
            call ITW_CLASH_CounterBattery_fnc_Expire;
            ITW_CLASH_CounterBatteryWatched = ITW_CLASH_CounterBatteryWatched select {
                !isNull _x && {alive _x}
            };
        };
        sleep ITW_CLASH_CounterBatteryPoll;
    };
};

ITW_CLASH_CounterBatteryReady = true;
diag_log format [
    "CLASH BOOT | counter-battery-ready | version=%1 acquire=%2 error=%3-%4 over=%5rounds fixLife=%6 poll=%7 model=acquisition observeOnly=true",
    ITW_CLASH_CounterBatteryVersion,
    ITW_CLASH_CounterBatteryAcquireRadius,
    ITW_CLASH_CounterBatteryErrorFirst,
    ITW_CLASH_CounterBatteryErrorFloor,
    ITW_CLASH_CounterBatteryErrorRounds,
    ITW_CLASH_CounterBatteryFixLife,
    ITW_CLASH_CounterBatteryPoll
];
true
