#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsDebugStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-debug-core-missing | no support console tests";
    false
};

ITW_CLASH_SupportsDebugStarted = true;
ITW_CLASH_SupportsDebugVersion = 1;

/*
    Console tests for the commander's drops and bite-back waves (supports v7).

    Run them from the debug console with "Server Exec" (on a hosted game
    "Local Exec" is the server too). Each one flies the real thing through
    the real executor, with every normal log line, and says what it did in
    chat. A test pays nothing, holds a lane of its own so it never blocks a
    commander, and skips the map's gates (frozen points, the drop zone's
    intelligence, headroom, a denied corridor); the aircraft, the route and
    the squads are found exactly as a commander's would be.

    Where: an objective index, a position, an object, or nothing for the
    objective nearest to the first player. Side: west, independent, east;
    nothing for the players' side.

      ["AIRBORNE_HELI"] call ITW_CLASH_SupportsDebug_fnc_Drop;
      ["AIRBORNE_PLANE",23] call ITW_CLASH_SupportsDebug_fnc_Drop;
      ["VEHICLE_DROP",player,independent] call ITW_CLASH_SupportsDebug_fnc_Drop;
          A helicopter drop, a plane drop, a vehicle delivery. HOLD when the
          side holds the point, TAKE when not; a fourth argument forces it.

      [] call ITW_CLASH_SupportsDebug_fnc_BiteBack;
      [23,independent] call ITW_CLASH_SupportsDebug_fnc_BiteBack;
          A bite-back wave, now, to the nearest point the side holds.

      [] call ITW_CLASH_SupportsDebug_fnc_Status;
          Every wallet, lane, and held point's flag and bite-back cooldown.

      [west,"DROP"] call ITW_CLASH_SupportsDebug_fnc_Fill;
          Fills a wallet (MAIN, DROP or BITE) to its cap, so the commander's
          own next assessment can buy from it: the real decision path.
*/

ITW_CLASH_SupportsDebugDelay = missionNamespace getVariable ["ITW_CLASH_SupportsDebugDelay",5];

ITW_CLASH_SupportsDebug_fnc_Say = {
    params ["_text"];
    diag_log ("CLASH SUPPORTS TEST | " + _text);
    ("[C.L.A.S.H. test] " + _text) remoteExec ["systemChat",0];
    _text
};

ITW_CLASH_SupportsDebug_fnc_Side = {
    params [["_side",sideUnknown]];
    if (_side isEqualType sideUnknown && {_side isNotEqualTo sideUnknown}) exitWith {_side};
    if (isNil "ITW_PlayerSide") exitWith {sideUnknown};
    ITW_PlayerSide
};

/*
    Which objective: an index as given; for a position or an object, the
    active objective nearest to it; for nothing, the nearest to the first
    player. With _heldBy, only those that side holds.
*/
ITW_CLASH_SupportsDebug_fnc_Objective = {
    params [["_where",objNull],["_heldBy",sideUnknown]];
    if (_where isEqualType 0) exitWith {_where};
    private _position = switch (true) do {
        case (_where isEqualType objNull && {!isNull _where}): {getPosATL _where};
        case (_where isEqualType [] && {count _where >= 2}): {_where};
        default {
            private _players = allPlayers - (entities "HeadlessClient_F");
            if (_players isEqualTo []) then {[]} else {getPosATL (_players#0)}
        };
    };
    if (_position isEqualTo [] || {isNil "ITW_Objectives"}) exitWith {-1};
    private _ids = [];
    if (!isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds") then {
        _ids = call ITW_CLASH_Generation_fnc_ActiveObjectiveIds;
    } else {
        for "_i" from 0 to ((count ITW_Objectives) - 1) do {_ids pushBack _i};
    };
    if (_heldBy isNotEqualTo sideUnknown) then {
        _ids = _ids select {[_heldBy,_x] call ITW_CLASH_Supports_fnc_HeldBy};
    };
    private _best = -1;
    private _bestDistance = 1e10;
    {
        private _at = [_x] call ITW_CLASH_Supports_fnc_ObjectivePos;
        if (_at isNotEqualTo [] && {(_at distance2D _position) < _bestDistance}) then {
            _best = _x;
            _bestDistance = _at distance2D _position;
        };
    } forEach _ids;
    _best
};

ITW_CLASH_SupportsDebug_fnc_Drop = {
    params [["_flavor","AIRBORNE_HELI"],["_where",objNull],["_side",sideUnknown],["_reason",""]];
    _side = [_side] call ITW_CLASH_SupportsDebug_fnc_Side;
    if !(_flavor in (ITW_CLASH_SupportsDropFlavors + ITW_CLASH_SupportsVehicleFlavors)) exitWith {
        [format ["%1 is not a drop: AIRBORNE_HELI, AIRBORNE_PLANE or VEHICLE_DROP",_flavor]] call ITW_CLASH_SupportsDebug_fnc_Say;
        ""
    };
    private _objective = [_where] call ITW_CLASH_SupportsDebug_fnc_Objective;
    if (_objective < 0) exitWith {["no objective to drop on"] call ITW_CLASH_SupportsDebug_fnc_Say; ""};
    private _context = [_side] call ITW_CLASH_Supports_fnc_MakeContext;
    if (count _context == 0) exitWith {[format ["no commander for %1",_side]] call ITW_CLASH_SupportsDebug_fnc_Say; ""};
    if !(_reason in ["TAKE","HOLD"]) then {
        _reason = if ([_side,_objective] call ITW_CLASH_Supports_fnc_HeldBy) then {"HOLD"} else {"TAKE"};
    };
    ([_context,_flavor,_objective,_reason] call ITW_CLASH_Supports_fnc_DirectPick) params ["_pick","_why"];
    if (_pick isEqualTo []) exitWith {
        [format ["%1 %2 to objective %3 refused: %4",_context get "sign",_flavor,_objective,_why]] call ITW_CLASH_SupportsDebug_fnc_Say;
        ""
    };
    _pick set ["lane",format ["TEST-%1",ITW_CLASH_SupportsSerial + 1]];
    _pick set ["wallet","TEST"];
    _pick set ["price",0];
    _pick set ["delay",ITW_CLASH_SupportsDebugDelay];
    _pick set ["test",true];
    _context set ["admitted",""];
    if !([_context,_pick] call ITW_CLASH_Supports_fnc_Admit) exitWith {
        [format ["%1 %2 to objective %3: admission refused",_context get "sign",_flavor,_objective]] call ITW_CLASH_SupportsDebug_fnc_Say;
        ""
    };
    private _id = _context getOrDefault ["admitted",""];
    private _class = (_context get "classes") getOrDefault [_flavor,""];
    ["test-launched",[_context get "sign",_flavor,_objective,_reason,_id,_class]] call ITW_CLASH_Supports_fnc_Log;
    [format [
        "%1 %2 (%3) to objective %4, %5: %6, wheels up in %7 s",
        _context get "sign",_flavor,_class,_objective,_reason,_id,ITW_CLASH_SupportsDebugDelay
    ]] call ITW_CLASH_SupportsDebug_fnc_Say;
    _id
};

ITW_CLASH_SupportsDebug_fnc_BiteBack = {
    params [["_where",objNull],["_side",sideUnknown]];
    _side = [_side] call ITW_CLASH_SupportsDebug_fnc_Side;
    private _objective = [_where,_side] call ITW_CLASH_SupportsDebug_fnc_Objective;
    if (_objective < 0) exitWith {[format ["%1 holds no objective to answer",_side]] call ITW_CLASH_SupportsDebug_fnc_Say; false};
    private _context = [_side] call ITW_CLASH_Supports_fnc_MakeContext;
    if (count _context == 0) exitWith {[format ["no commander for %1",_side]] call ITW_CLASH_SupportsDebug_fnc_Say; false};
    ([_side,_objective] call ITW_CLASH_Supports_fnc_FlagState) params ["_ours","_phase"];
    private _sent = [_context,_objective,"test",_phase,0,true] call ITW_CLASH_Supports_fnc_LaunchWave;
    [format [
        "%1 bite-back wave to objective %2 (flag %3 at %4): %5",
        _context get "sign",_objective,if (_ours) then {"ours"} else {"theirs"},(round (_phase * 100)) / 100,
        if (_sent) then {"sent, see biteback-wave in the RPT"} else {"refused, see biteback-refused in the RPT"}
    ]] call ITW_CLASH_SupportsDebug_fnc_Say;
    _sent
};

ITW_CLASH_SupportsDebug_fnc_Status = {
    params [["_side",sideUnknown]];
    private _sides = if (_side isEqualType sideUnknown && {_side isNotEqualTo sideUnknown}) then {[_side]} else {
        [missionNamespace getVariable ["ITW_PlayerSide",sideUnknown],missionNamespace getVariable ["ITW_EnemySide",sideUnknown]] select {_x isNotEqualTo sideUnknown}
    };
    private _lines = [];
    {
        private _s = _x;
        [_s] call ITW_CLASH_Supports_fnc_Accrue;
        private _ledger = [_s] call ITW_CLASH_Supports_fnc_Ledger;
        private _lanes = _ledger get "lanes";
        private _busy = (keys _lanes) select {(_lanes get _x) isNotEqualTo ""};
        _lines pushBack format [
            "%1: bank %2/%3, drops %4/%5, bite-back %6/%7 wave; busy lanes %8",
            [_s] call ITW_CLASH_Supports_fnc_CodeSign,
            round (_ledger get "cash"),round (call ITW_CLASH_Supports_fnc_Cap),
            round (_ledger getOrDefault ["dropCash",0]),round (call ITW_CLASH_Supports_fnc_DropCap),
            (round ((_ledger getOrDefault ["biteCash",0]) * 100)) / 100,ITW_CLASH_SupportsBiteBackCap,
            if (_busy isEqualTo []) then {"none"} else {_busy apply {_x + "=" + (_lanes get _x)}}
        ];
        private _ids = if (isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds") then {[]} else {call ITW_CLASH_Generation_fnc_ActiveObjectiveIds};
        {
            if !([_s,_x] call ITW_CLASH_Supports_fnc_HeldBy) then {continue};
            ([_s,_x] call ITW_CLASH_Supports_fnc_FlagState) params ["_ours","_phase"];
            private _until = (_ledger get "cooldowns") getOrDefault ["bite:" + str _x,0];
            _lines pushBack format [
                "  holds %1: flag %2 at %3, bite-back %4",
                _x,if (_ours) then {"ours"} else {"THEIRS"},(round (_phase * 100)) / 100,
                if (_until > time) then {format ["in %1 s",round (_until - time)]} else {"ready"}
            ];
        } forEach _ids;
    } forEach _sides;
    {[_x] call ITW_CLASH_SupportsDebug_fnc_Say} forEach _lines;
    _lines
};

ITW_CLASH_SupportsDebug_fnc_Fill = {
    params [["_side",sideUnknown],["_wallet","DROP"]];
    _side = [_side] call ITW_CLASH_SupportsDebug_fnc_Side;
    if !(_wallet in ["MAIN","DROP","BITE"]) exitWith {[format ["%1 is not a wallet: MAIN, DROP or BITE",_wallet]] call ITW_CLASH_SupportsDebug_fnc_Say; false};
    private _ledger = [_side] call ITW_CLASH_Supports_fnc_Ledger;
    private _cap = [_wallet] call ITW_CLASH_Supports_fnc_WalletCap;
    _ledger set [[_wallet] call ITW_CLASH_Supports_fnc_WalletKey,_cap];
    ["test-filled",[[_side] call ITW_CLASH_Supports_fnc_CodeSign,_wallet,(round (_cap * 100)) / 100]] call ITW_CLASH_Supports_fnc_Log;
    [format ["%1 %2 wallet filled to %3; its commander decides on its next assessment",[_side] call ITW_CLASH_Supports_fnc_CodeSign,_wallet,(round (_cap * 100)) / 100]] call
        ITW_CLASH_SupportsDebug_fnc_Say;
    true
};

diag_log format [
    "CLASH BOOT | supports-debug-ready | version=%1 delay=%2s commands=Drop,BiteBack,Status,Fill free=true ownLanes=true skipsMapGates=true",
    ITW_CLASH_SupportsDebugVersion,
    ITW_CLASH_SupportsDebugDelay
];
true
