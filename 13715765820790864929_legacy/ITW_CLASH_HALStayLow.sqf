if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALStayLowStarted",false]) exitWith {true};

ITW_CLASH_HALStayLowStarted = true;
ITW_CLASH_HALStayLowVersion = 1;

/*
    One owner for how high and how fast a HAL troop lift flies.

    Hark, after the first run-in flight: "we land on clear corridors, that
    causes our helos to raise in the air to slow themselves down. they expose
    themselves to the entire map this way, we seriously need to work on some
    'stay the fuck down' mechanics."

    The 2026-10-10 23:22 RPT has it on every leg that ends at a waypoint, not
    only the delivery. A Huron flying to a pickup:

        metres out   km/h   height
           892        251     102
           603        169     281
           407        102     291
           280         67     262

    Two things in that table, and the same two in all five such legs:

    - From about 900 m the aircraft holds speed = 0.07 x distance. That is the
      engine's arrival law for a last waypoint, and at 250 km/h it is a
      0.45 g stop.
    - The stop is a nose-up flare, and the speed it sheds turns into height
      almost one for one. 251 to 102 km/h is 207 m of kinetic energy; the
      aircraft climbed 189 m.

    Afterwards the pilot comes back down at 8 to 10 m/s and no faster, so the
    balloon costs half a minute above 100 m. Three aircraft were lost on that
    flight and all three were above 100 m: two in the climb to the old 120 m
    egress height, one in a 197 m balloon on a landing.

    HAL owns the route and every waypoint. It never sets flyInHeight or
    limitSpeed on a transport, so those two are free inputs, and this module
    sets them and nothing else:

    - Cruise at ITW_CLASH_HALStayLowCruiseHeight instead of the engine's 50 m.
    - On any leg that ends by arriving, hold the speed under a schedule that
      sheds energy slowly enough for the pilot's height hold to keep up, and
      bring the height down with it. The aircraft reaches the arrival law
      already slow, so there is nothing left to flare off.

    A lift that is going to paradrop does not arrive, and is not slowed. From
    the moment the unload owner arms its run-in to the moment the egress route
    is written, that owner has height and speed and this module does not write.

    tools/approach_sim.py is the model behind the numbers. docs/STAY_LOW.md is
    what it can and cannot tell.
*/
ITW_CLASH_HALStayLow = missionNamespace getVariable ["ITW_CLASH_HALStayLow",true];

// Shared with the unload owner's egress height, by name, so there is one knob.
ITW_CLASH_HALStayLowCruiseHeight = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowCruiseHeight",30
];

/*
    The schedule.

    ITW slows its own helicopters with a seven-rung ladder
    (ITW_Attack.sqf:3812). Its last rung is 80 km/h and 10 m inside 300 m,
    which is the arrival law's own speed at 300 m, so the aircraft joins the
    law without braking. Those three numbers are kept.

    Above that, ITW's rungs fall on a straight line in distance, which sheds
    energy fastest where the aircraft is fastest, and a ladder steps. This is
    the same idea with constant power instead:

        v^3 = v_end^3 + 3 P (d - d_end)

    Decel times speed is then P at every point, so the zoom rate, P / g, is
    the same all the way in and never steps. P is in m^2/s^3. At 20 the zoom
    is 2 m/s, against the 25 to 37 m/s of the unassisted stop.

    ITW's seven heights are one line in its own speeds, 0.18 m per km/h above
    the last rung, and that line is kept as it is.
*/
ITW_CLASH_HALStayLowPower = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowPower",20
];
ITW_CLASH_HALStayLowFinalKmh = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowFinalKmh",80
];
ITW_CLASH_HALStayLowFinalDistance = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowFinalDistance",300
];
ITW_CLASH_HALStayLowFinalHeight = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowFinalHeight",10
];
ITW_CLASH_HALStayLowHeightPerKmh = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowHeightPerKmh",0.18
];
ITW_CLASH_HALStayLowPoll = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowPoll",0.5
];
/*
    SCargo takes the aircraft off its books a moment before it writes the
    flight home (SCargo.sqf:737 to 809), so for that moment the aircraft is no
    longer a chosen carrier and has no waypoint to say it is going anywhere.
    It is watched this long for the return leg to appear, and not written to.
*/
ITW_CLASH_HALStayLowLinger = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowLinger",15
];
// How long an answer to "will this lift arrive or drop" is trusted.
ITW_CLASH_HALStayLowIntentSeconds = missionNamespace getVariable [
    "ITW_CLASH_HALStayLowIntentSeconds",5
];

ITW_CLASH_HALStayLow_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-stay-low-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL STAY LOW | %1 | %2",_event,_payload];
    };
};

// Metres to go in, [speed limit in km/h, height in metres] out.
ITW_CLASH_HALStayLow_fnc_Schedule = {
    params ["_metres"];
    private _end = ITW_CLASH_HALStayLowFinalKmh / 3.6;
    private _beyond = (_metres - ITW_CLASH_HALStayLowFinalDistance) max 0;
    private _kmh = 3.6 * (
        ((_end ^ 3) + (3 * ITW_CLASH_HALStayLowPower * _beyond)) ^ (1 / 3)
    );
    private _height = (
        ITW_CLASH_HALStayLowFinalHeight
        + (ITW_CLASH_HALStayLowHeightPerKmh * ((_kmh - ITW_CLASH_HALStayLowFinalKmh) max 0))
    ) min ITW_CLASH_HALStayLowCruiseHeight;
    [_kmh,_height]
};

/*
    Every helicopter HAL has chosen for a troop lift, read off HAL's own
    bookkeeping: SCargo marks the squad CargoChosen and names the aircraft in
    AssignedCargo from the moment it picks one until it sends it home.
*/
ITW_CLASH_HALStayLow_fnc_Carriers = {
    private _carriers = [];
    {
        if (_x getVariable ["CargoChosen",false]) then {
            private _carrier = _x getVariable ["AssignedCargo" + str _x,objNull];
            if (!isNull _carrier && {_carrier isKindOf "Helicopter"}) then {
                _carriers pushBackUnique _carrier;
            };
        };
    } forEach allGroups;
    _carriers
};

/*
    What the crew is flying to, read off the waypoint HAL wrote.

    HAL says what a leg is for in the waypoint's statement. A pickup lands
    'GET IN', the flight home lands 'LAND', a stock delivery lands 'GET OUT',
    and a delivery the unload owner has patched names that owner. Anything
    else is somewhere the aircraft is passing through.
*/
ITW_CLASH_HALStayLow_fnc_Leg = {
    params ["_group"];
    if (isNull _group) exitWith {["NONE",[]]};
    private _waypoints = waypoints _group;
    private _index = currentWaypoint _group;
    if (_index < 0 || {_index >= count _waypoints}) exitWith {["NONE",[]]};

    private _waypoint = _waypoints select _index;
    private _position = waypointPosition _waypoint;
    if (_position isEqualTo [0,0,0]) exitWith {["NONE",[]]};

    private _statement = (waypointStatements _waypoint) param [1,""];
    if ((_statement find "ITW_CLASH_HALUnload_fnc_Unload") >= 0) exitWith {
        ["DELIVERY",_position]
    };
    if ((_statement find "land 'GET IN'") >= 0) exitWith {["PICKUP",_position]};
    if ((_statement find "land 'LAND'") >= 0) exitWith {["RETURN",_position]};
    if ((_statement find "land 'GET OUT'") >= 0) exitWith {["LANDING",_position]};
    ["TRANSIT",_position]
};

/*
    Will this delivery arrive at its waypoint, or fly through it?

    The unload owner answers, with the function its own run-in uses, so the
    two cannot disagree about a lift. LAND and NO_LAND both arrive: NO_LAND
    keeps the chalk aboard but still stops over the point, and it is the stop
    that balloons. The answer is asked again every few seconds because the
    corridor is, and the roll for a quiet corridor is the unload owner's one
    roll per lift, so asking does not change it.

    With no unload owner bound, every lift is a stock HAL landing.

    An empty answer means nobody is aboard, and that is not an arrival. After
    a run-in drop the aircraft is still flying HAL's delivery waypoint, moved
    out to the through point, with an empty cabin. Slowing it there would be
    braking the egress.
*/
ITW_CLASH_HALStayLow_fnc_Arrives = {
    params ["_group","_carrier","_position"];
    if (
        isNil "ITW_CLASH_HALUnload_fnc_Decide"
        || {!(missionNamespace getVariable ["ITW_CLASH_HALUnloadReady",false])}
    ) exitWith {true};

    private _cached = _group getVariable ["ITW_CLASH_HALStayLowIntent",[]];
    if (_cached isNotEqualTo [] && {time < (_cached select 1)}) exitWith {
        _cached select 0
    };
    private _mode = ([_group,_carrier,_position] call ITW_CLASH_HALUnload_fnc_Decide) param [0,""];
    private _arrives = _mode in ["LAND","NO_LAND"];
    _group setVariable [
        "ITW_CLASH_HALStayLowIntent",
        [_arrives,time + ITW_CLASH_HALStayLowIntentSeconds]
    ];
    _arrives
};

/*
    Let go of the aircraft.

    A speed limit left on a helicopter is an 80 km/h helicopter for the rest
    of the mission, and a height left at 10 m is the next system's problem.
    Every way out of an approach comes through here, and the approach is
    written to the RPT on the way: how far out it began, the highest the
    aircraft got, and the fastest. That one line is the measurement the
    schedule is tuned against.
*/
ITW_CLASH_HALStayLow_fnc_Release = {
    params ["_carrier",["_why","done"]];
    if (isNull _carrier) exitWith {false};
    private _approach = _carrier getVariable ["ITW_CLASH_HALStayLowApproach",[]];
    if (_approach isEqualTo []) exitWith {false};

    _carrier limitSpeed 1e10;
    if (alive _carrier) then {
        _carrier flyInHeight ITW_CLASH_HALStayLowCruiseHeight;
    };
    _carrier setVariable ["ITW_CLASH_HALStayLowApproach",nil];

    _approach params ["_kind","_began","_from","_peak","_fastest","_to"];
    ["approach",[
        typeOf _carrier,
        groupId (group (driver _carrier)),
        _kind,_why,
        round _from,round _to,
        round _peak,round _fastest,
        round (time - _began),
        ITW_CLASH_HALStayLowPower
    ]] call ITW_CLASH_HALStayLow_fnc_Log;
    true
};

/*
    One pass over one aircraft. Returns false when there is nothing HAL-shaped
    left to follow, and the caller stops tracking it.
*/
ITW_CLASH_HALStayLow_fnc_Tick = {
    params ["_carrier","_isCarrier"];
    if (isNull _carrier || {!alive _carrier}) exitWith {
        [_carrier,"lost"] call ITW_CLASH_HALStayLow_fnc_Release;
        false
    };
    private _group = group (driver _carrier);
    if (isNull _group) exitWith {
        [_carrier,"no-crew"] call ITW_CLASH_HALStayLow_fnc_Release;
        false
    };

    // Somebody else is flying it.
    if (
        ((crew _carrier) findIf {isPlayer _x}) >= 0
        || {_carrier getVariable ["ITW_CLASH_ThunderRunActive",false]}
        || {_carrier getVariable ["ITW_CLASH_HotDropActive",false]}
    ) exitWith {
        [_carrier,"other-owner"] call ITW_CLASH_HALStayLow_fnc_Release;
        false
    };

    // A drop run has height and speed from arming to egress.
    if (
        _group getVariable ["ITW_CLASH_HALUnloadDropRunArmed",false]
        || {(_group getVariable ["ITW_CLASH_HALUnloadPhase",""]) in ["RUN_IN","DROPPING"]}
    ) exitWith {
        if ((_carrier getVariable ["ITW_CLASH_HALStayLowApproach",[]]) isNotEqualTo []) then {
            // Released without the limit or height writes: the run owns both.
            _carrier setVariable ["ITW_CLASH_HALStayLowApproach",nil];
        };
        true
    };

    ([_group] call ITW_CLASH_HALStayLow_fnc_Leg) params ["_kind","_position"];
    if (_isCarrier || {_kind in ["PICKUP","RETURN"]}) then {
        _carrier setVariable ["ITW_CLASH_HALStayLowSeen",time];
    };
    private _arrives = switch (_kind) do {
        case "PICKUP";
        case "RETURN";
        case "LANDING": {true};
        case "DELIVERY": {
            [_group,_carrier,_position] call ITW_CLASH_HALStayLow_fnc_Arrives
        };
        default {false};
    };

    if (_arrives) exitWith {
        private _metres = _carrier distance2D _position;
        private _height = (getPosATL _carrier) select 2;
        private _kmh = speed _carrier;
        private _approach = _carrier getVariable ["ITW_CLASH_HALStayLowApproach",[]];
        if (_approach isEqualTo []) then {
            _approach = [_kind,time,_metres,_height,_kmh,_metres];
        } else {
            _approach set [3,(_approach select 3) max _height];
            _approach set [4,(_approach select 4) max _kmh];
            _approach set [5,_metres];
        };
        _carrier setVariable ["ITW_CLASH_HALStayLowApproach",_approach];

        ([_metres] call ITW_CLASH_HALStayLow_fnc_Schedule) params ["_limit","_ask"];
        // Every pass, the way ITW and CASEVAC do, and in small steps: the
        // limit moves a few km/h between passes, so the pilot is never far
        // over it and never brakes hard for it.
        _carrier limitSpeed _limit;
        _carrier flyInHeight _ask;
        true
    };

    // Not arriving anywhere. Whatever approach was under way is over.
    [_carrier,"leg-ended"] call ITW_CLASH_HALStayLow_fnc_Release;

    // Off SCargo's books and not on a leg of its own: not this module's to
    // hold. Nothing is written; it is only watched for the return leg.
    if (!_isCarrier) exitWith {
        (time - (_carrier getVariable ["ITW_CLASH_HALStayLowSeen",0]))
            < ITW_CLASH_HALStayLowLinger
    };

    // A chosen carrier in transit or waiting: cruise height, no limit.
    private _asked = _carrier getVariable ["ITW_CLASH_HALStayLowCruiseAsked",-1];
    if (time >= _asked) then {
        _carrier flyInHeight ITW_CLASH_HALStayLowCruiseHeight;
        _carrier setVariable ["ITW_CLASH_HALStayLowCruiseAsked",time + 5];
    };
    true
};

[] spawn {
    scriptName "ITW_CLASH_HALStayLow";
    waitUntil {
        sleep 0.5;
        missionNamespace getVariable ["ITW_CLASH_HALReady",false]
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if !(missionNamespace getVariable ["ITW_CLASH_HALReady",false]) exitWith {};

    ([1000] call ITW_CLASH_HALStayLow_fnc_Schedule) params ["_kmhAt1000","_heightAt1000"];
    diag_log format [
        "CLASH BOOT | hal-stay-low-ready | version=%1 enabled=%2 cruise=%3 power=%4 final=%5kmh/%6m/%7m at1000=%8kmh/%9m halOwnsRoute=true writes=flyInHeight,limitSpeed",
        ITW_CLASH_HALStayLowVersion,
        ITW_CLASH_HALStayLow,
        ITW_CLASH_HALStayLowCruiseHeight,
        ITW_CLASH_HALStayLowPower,
        ITW_CLASH_HALStayLowFinalKmh,
        ITW_CLASH_HALStayLowFinalHeight,
        ITW_CLASH_HALStayLowFinalDistance,
        round _kmhAt1000,
        round _heightAt1000
    ];

    private _tracked = [];
    private _carriers = [];
    private _nextScan = 0;
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_HALStayLowPoll;

        if (!ITW_CLASH_HALStayLow) then {
            // Switched off in flight: give every aircraft back first.
            {[_x,"switched-off"] call ITW_CLASH_HALStayLow_fnc_Release} forEach _tracked;
            _tracked = [];
            continue
        };

        if (time >= _nextScan) then {
            _carriers = call ITW_CLASH_HALStayLow_fnc_Carriers;
            {_tracked pushBackUnique _x} forEach _carriers;
            _nextScan = time + 2;
        };

        _tracked = _tracked select {
            [_x,_x in _carriers] call ITW_CLASH_HALStayLow_fnc_Tick
        };
    };
};

true
