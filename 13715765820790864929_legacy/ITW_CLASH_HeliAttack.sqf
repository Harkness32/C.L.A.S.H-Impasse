#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HeliAttackStarted",false]) exitWith {true};

ITW_CLASH_HeliAttackStarted = true;
ITW_CLASH_HeliAttackVersion = 2;
ITW_CLASH_HeliAttackReady = false;

/*
    How a HAL attack helicopter flies its sortie, from the order to "come home".

    HAL's GoAttAir puts one search-and-destroy waypoint on the target itself,
    radius 0, and waits for it to complete. Run of 2026-10-15: the stub-wing
    Ghost Hawks spent their sorties 15 to 200 m from the infantry they were
    sent at, flying tight circles, pitching up and doubling back, never
    setting up a run. Their only weapon, the DAGR-M, has no AI fire mode
    inside 300 m. Search-and-destroy also completes once the group sees no
    enemy near its point, and completion is what ends HAL's sortie, so simply
    moving HAL's point outward would send helicopters home early.

    So C.L.A.S.H.'s copy of GoAttAir hands helicopter sorties here, and HAL
    keeps every decision: what to attack and when (its dispatcher), when a
    sortie must end (damage, fuel, its Busy flag), and the return and landing
    afterwards. This owns only the movement in between, after ALiVE's CAS
    state machine (sup_combatsupport cas.fsm, GPL; the pattern, not its code):

      - Pick a centre. A contact our side has reported near HAL's point, that
        the rack can hit, nearest and most precise first. HAL's own point if
        the knowledge layer has nothing and the rack can hit what HAL named.
      - RUN when only the airframe can aim (pylons, pilot guns): attack runs,
        sized from the rack (ITW_CLASH_RackProfile.sqf, fnc_Run). Each run
        flies straight at the centre from the side the helicopter is on, to
        a break point outside the weapons' floor (600 m at least), then out
        to an ingress point 60 degrees round, past where its weapons can
        first fire, so the next run comes from a new direction. Two move
        waypoints per run, so it flies through the break without stopping.
      - ORBIT when a gunner can shoot from the ring (turrets, door guns): keep
        moving around a ring sized from the rack, ALiVE style, entering on
        the near side.
      - Combat mode YELLOW and attack off, both modes: the crew fires at will
        but does not leave its line to chase. v1 held a search-and-destroy
        point (STATION) with RED. 2026-10-16: the DAP shot well on its way in,
        from 2.7 to 1.6 km at 265 km/h, then never reached its point; it left
        it for a Panther and fought it from 342 to 685 m, at 25 to 250 km/h,
        until it lost its rotor. Search-and-destroy with RED hands movement to
        the AI's own engagement, which is what HAL's radius-0 point did too.
      - Reveal to the crew what the commander already knows near the centre,
        and nothing else. The AI picks its own shots; nothing here fires.
      - Re-pick the centre every pass (a run, or a lap of the ring). Two passes
        with nothing the rack can hit near it, and the sortie is over.

    HAL's sortie rules end it from here too, so its return-to-base tail runs
    unchanged afterwards. When something else takes the group mid-sortie (a
    CLASH release or withdrawal, HAL's own Break), the sortie stops within a
    poll, leaves that owner's orders standing, and GoAttAir exits the way it
    does when RYD_Wait reports the group gone: no return leg on top of them.
*/

// Contacts this far from HAL's point can become the centre.
ITW_CLASH_HeliAttackRetargetRadius = missionNamespace getVariable ["ITW_CLASH_HeliAttackRetargetRadius",1500];
// A contact more uncertain than this is not worth orbiting.
ITW_CLASH_HeliAttackMaxUncertainty = missionNamespace getVariable ["ITW_CLASH_HeliAttackMaxUncertainty",300];
// Degrees per step around the ring (ORBIT).
ITW_CLASH_HeliAttackStep = missionNamespace getVariable ["ITW_CLASH_HeliAttackStep",45];
// The most one ring leg may take, and arrival at a ring point.
ITW_CLASH_HeliAttackLegTimeout = missionNamespace getVariable ["ITW_CLASH_HeliAttackLegTimeout",120];
ITW_CLASH_HeliAttackArrival = missionNamespace getVariable ["ITW_CLASH_HeliAttackArrival",150];
/*
    RUN: degrees between one run's radial and the next. The way out never
    comes closer to the centre than the break point while cos(offset) is at
    most break / ingress: at 60, while ingress is at least twice the break
    (2900 against 600 for the DAP). Arrival
    at the next ingress point, and the slowest a run may average before it
    times out.
*/
ITW_CLASH_HeliAttackRunOffset = missionNamespace getVariable ["ITW_CLASH_HeliAttackRunOffset",60];
ITW_CLASH_HeliAttackRunArrival = missionNamespace getVariable ["ITW_CLASH_HeliAttackRunArrival",400];
ITW_CLASH_HeliAttackRunMinSpeed = missionNamespace getVariable ["ITW_CLASH_HeliAttackRunMinSpeed",20];
// Passes (runs or laps) with nothing to hit before the sortie ends.
ITW_CLASH_HeliAttackClearLaps = missionNamespace getVariable ["ITW_CLASH_HeliAttackClearLaps",2];
// HAL's own cap on a CAS loop (GoAttAir.sqf: _ct >= 1200).
ITW_CLASH_HeliAttackMaxTime = missionNamespace getVariable ["ITW_CLASH_HeliAttackMaxTime",1200];
// HAL's own sortie limits (GoAttAir.sqf mustRTB).
ITW_CLASH_HeliAttackMaxDamage = missionNamespace getVariable ["ITW_CLASH_HeliAttackMaxDamage",0.5];
ITW_CLASH_HeliAttackMinFuel = missionNamespace getVariable ["ITW_CLASH_HeliAttackMinFuel",0.3];
// Height, from the ring radius or the run's break distance, inside these bounds.
ITW_CLASH_HeliAttackHeightMin = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightMin",50];
ITW_CLASH_HeliAttackHeightMax = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightMax",150];
ITW_CLASH_HeliAttackHeightRatio = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightRatio",0.15];
ITW_CLASH_HeliAttackPoll = missionNamespace getVariable ["ITW_CLASH_HeliAttackPoll",2];
// Marks the run waypoints this places, so a hand-back removes only those.
ITW_CLASH_HeliAttackWaypointName = "clash-heli-attack";

ITW_CLASH_HeliAttack_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["heli-attack-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HELI-ATTACK | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_HeliAttack_fnc_GroupId = {
    params ["_group"];
    if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") exitWith {[_group] call ITW_CLASH_DualHAL_fnc_GroupId};
    str _group
};

// The contact type HAL's own target is, in the knowledge layer's words.
ITW_CLASH_HeliAttack_fnc_TypeOf = {
    params ["_target"];
    if (isNull _target) exitWith {""};
    if (!isNil "ITW_CLASH_Knowledge_fnc_Class") exitWith {
        [vehicle _target] call ITW_CLASH_Knowledge_fnc_Class
    };
    private _veh = vehicle _target;
    switch (true) do {
        case (_veh isKindOf "Air"): {"AIR"};
        case (_veh isKindOf "CAManBase"): {"INFANTRY"};
        case (_veh isKindOf "StaticWeapon"): {"STATIC"};
        case (_veh isKindOf "Tank"): {"ARMOR"};
        default {"VEHICLE"};
    }
};

/*
    The centre for the next lap: [position, type, source] or [].
    Reported positions only; HAL's point stands in when the layer has nothing.
*/
ITW_CLASH_HeliAttack_fnc_PickCentre = {
    params ["_side","_ordered","_target","_types"];
    private _best = [];
    private _bestScore = 1e10;
    if (!isNil "ITW_CLASH_Knowledge_fnc_Contacts") then {
        {
            _x params ["","_record"];
            private _type = _record getOrDefault ["class",""];
            if (((_types getOrDefault [_type,[0,-1,""]])#0) <= 0) then {continue};
            private _position = _record getOrDefault ["position",[]];
            if (_position isEqualTo []) then {continue};
            private _distance = _position distance2D _ordered;
            if (_distance > ITW_CLASH_HeliAttackRetargetRadius) then {continue};
            private _r = [_record,0] call ITW_CLASH_Knowledge_fnc_Uncertainty;
            if (_r > ITW_CLASH_HeliAttackMaxUncertainty) then {continue};
            private _score = _distance + _r;
            if (_score < _bestScore) then {
                _bestScore = _score;
                _best = [+_position,_type,"reported"];
            };
        } forEach ([_side] call ITW_CLASH_Knowledge_fnc_Contacts);
    };
    if (_best isNotEqualTo []) exitWith {_best};
    private _type = [_target] call ITW_CLASH_HeliAttack_fnc_TypeOf;
    if (((_types getOrDefault [_type,[0,-1,""]])#0) > 0) exitWith {[+_ordered,_type,"hal-point"]};
    []
};

// What the commander knows inside the ring, told to the crew. Nothing more.
ITW_CLASH_HeliAttack_fnc_Brief = {
    params ["_group","_hq","_centre","_radius"];
    private _told = 0;
    {
        if (!isNull _x && {alive _x} && {(_x distance2D _centre) <= (_radius + 300)}) then {
            _group reveal [vehicle _x,1.5];
            _told = _told + 1;
        };
    } forEach (_hq getVariable ["RydHQ_KnEnemies",[]]);
    _told
};

ITW_CLASH_HeliAttack_fnc_ClearWaypoints = {
    params ["_group"];
    if (!isNil "RYD_WPdel") exitWith {[_group] call RYD_WPdel};
    for "_i" from (count waypoints _group - 1) to 0 step -1 do {deleteWaypoint [_group,_i]};
};

/*
    Weapons free every pass, without waiting for a waypoint to apply it:
    COMBAT, fire at will (YELLOW), and attack off, so the crew shoots what it
    sees from the line it is flying instead of leaving it to close in.
*/
ITW_CLASH_HeliAttack_fnc_Arm = {
    params ["_group","_flight","_height"];
    _group setBehaviourStrong "COMBAT";
    _group setCombatMode "YELLOW";
    _group enableAttack false;
    {
        _x enableAI "TARGET";
        _x enableAI "AUTOTARGET";
    } forEach ((units _group) select {alive _x});
    {
        // Clears anything a lift left behind (stay-low's 30 m, a hot drop's
        // speed limit) along with setting this sortie's height.
        _x limitSpeed 1e10;
        _x forceSpeed -1;
        _x flyInHeight _height;
    } forEach _flight;
};

ITW_CLASH_HeliAttack_fnc_Height = {
    params ["_radius"];
    ((_radius * ITW_CLASH_HeliAttackHeightRatio) max ITW_CLASH_HeliAttackHeightMin) min ITW_CLASH_HeliAttackHeightMax
};

/*
    Why this sortie must stop now, or "". The first five mean the group is no
    longer ours to fly: someone else (HAL, a CLASH release, a withdrawal) has
    it or is about to give it orders, so the sortie leaves its waypoints alone
    and GoAttAir takes its not-alive exit, which issues no return leg.

    RydHQ_MIA is a handshake: whoever waits on a HAL group clears it on reading
    it, and the setter (ITW_CLASH_fnc_BeginRelease, HALUnload) watches for that.
    RYD_Wait does it in its own check, so this does it here.
*/
ITW_CLASH_HeliAttackForeignStops = ["lost","mia","break","withdrawing","released"];

ITW_CLASH_HeliAttack_fnc_Stop = {
    params ["_group","_flight","_started"];
    private _lead = leader _group;
    if (isNull _group || {({alive _x} count units _group) < 1}) exitWith {"lost"};
    if (isNull _lead || {!alive (vehicle _lead)}) exitWith {"lost"};
    if (_group getVariable ["RydHQ_MIA",false]) exitWith {_group setVariable ["RydHQ_MIA",nil]; "mia"};
    if (_group getVariable ["Break",false]) exitWith {"break"};
    // GTFO's withdrawal keeps the group HAL-managed and sets neither of the above.
    if (_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {"withdrawing"};
    if !(_group getVariable ["Busy" + str _group,false]) exitWith {"released"};
    // canMove: a lost rotor can leave overall damage low (G63, 2026-10-16).
    if ((_flight findIf {
        !alive _x || {!canMove _x} || {damage _x > ITW_CLASH_HeliAttackMaxDamage} || {fuel _x < ITW_CLASH_HeliAttackMinFuel}
    }) >= 0) exitWith {"rtb-condition"};
    if ((time - _started) > ITW_CLASH_HeliAttackMaxTime) exitWith {"time"};
    ""
};

// Shots, for the log: missiles and rockets one by one, guns per lap.
ITW_CLASH_HeliAttack_fnc_WatchShots = {
    params ["_veh","_group"];
    _veh setVariable ["ITW_CLASH_HeliAttackShots",createHashMap];
    _veh setVariable ["ITW_CLASH_HeliAttackGroup",_group];
    _veh addEventHandler ["Fired",{
        params ["_unit","_weapon","","","_ammo","","","_gunner"];
        private _shots = _unit getVariable ["ITW_CLASH_HeliAttackShots",createHashMap];
        _shots set [_weapon,(_shots getOrDefault [_weapon,0]) + 1];
        private _simulation = toLowerANSI getText (configFile >> "CfgAmmo" >> _ammo >> "simulation");
        if (_simulation in ["shotmissile","shotrocket"]) then {
            private _target = if (isNull _gunner) then {objNull} else {assignedTarget _gunner};
            ["shot",[
                [_unit getVariable ["ITW_CLASH_HeliAttackGroup",grpNull]] call ITW_CLASH_HeliAttack_fnc_GroupId,
                typeOf _unit,_weapon,
                if (isNull _target) then {""} else {typeOf _target},
                if (isNull _target) then {-1} else {round (_unit distance _target)},
                round ((getPosATL _unit)#2),
                round (speed _unit)
            ]] call ITW_CLASH_HeliAttack_fnc_Log;
        };
    }]
};

/*
    Shots each aircraft has fired since this was last asked, by weapon, and
    reset. One line's worth, not a ledger.
*/
ITW_CLASH_HeliAttack_fnc_TakeShots = {
    params ["_flight"];
    private _shots = createHashMap;
    {
        private _veh = _x;
        {_shots set [_x,(_shots getOrDefault [_x,0]) + _y]} forEach (_veh getVariable ["ITW_CLASH_HeliAttackShots",createHashMap]);
        _veh setVariable ["ITW_CLASH_HeliAttackShots",createHashMap];
    } forEach (_flight select {alive _x});
    (keys _shots) apply {[_x,_shots get _x]}
};

/*
    The sortie. Returns [alive, reason]; alive false when the flight or its
    group is gone or no longer ours (ITW_CLASH_HeliAttackForeignStops), as
    HAL's own RYD_Wait reports a lost, MIA or broken group.
*/
ITW_CLASH_HeliAttack_fnc_Fly = {
    params ["_group","_hq","_target","_ordered","_flight"];
    private _started = time;
    private _side = side _group;
    private _id = [_group] call ITW_CLASH_HeliAttack_fnc_GroupId;
    private _step = ITW_CLASH_HeliAttackStep;
    private _ordered2 = [_ordered#0,_ordered#1,0];
    private _halType = [_target] call ITW_CLASH_HeliAttack_fnc_TypeOf;

    ([_flight,_step] call ITW_CLASH_Rack_fnc_Profile) params ["_entries","_types"];
    private _anyUsable = (values _types) findIf {(_x#0) > 0};
    if (_anyUsable < 0) exitWith {
        ["start",[_id,typeOf (_flight#0),"rack-empty",_halType]] call ITW_CLASH_HeliAttack_fnc_Log;
        [true,"rack-empty"]
    };

    private _handlers = _flight apply {[_x,[_x,_group] call ITW_CLASH_HeliAttack_fnc_WatchShots]};
    [_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;
    // Arm turns attack off; a sortie ending on its own terms puts it back.
    private _attackWas = attackEnabled _group;

    private _centre = [];
    private _type = "";
    private _source = "";
    private _radius = -1;
    private _mode = "";
    private _break = -1;
    private _ingress = -1;
    private _bearing = 0;
    private _direction = 1;
    private _pass = 0;
    private _legsLeft = 0;
    private _emptyPasses = 0;
    private _reason = "";
    private _hadTarget = false;
    // Measured each pass, for the "flown" line: how close it really came.
    private _closest = 1e10;
    private _closestSpeed = -1;
    private _closestHeight = -1;
    private _passStart = time;

    while {true} do {
        _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
        if (_reason isNotEqualTo "") exitWith {};

        // A new pass: re-read the rack and the picture.
        if (_legsLeft <= 0) then {
            ([_flight,_step] call ITW_CLASH_Rack_fnc_Profile) params ["_nowEntries","_nowTypes"];
            _types = _nowTypes;
            // Out of everything that can hit anything: HAL's pylon rule, read
            // from the rack instead of a pylon count.
            if (((values _types) findIf {(_x#0) > 0}) < 0) exitWith {_reason = "winchester"};
            private _pick = [_side,_ordered2,_target,_types] call ITW_CLASH_HeliAttack_fnc_PickCentre;
            private _profile = [];
            if (_pick isEqualTo []) then {
                _emptyPasses = _emptyPasses + 1;
                if (_centre isEqualTo []) then {
                    // Nothing to hit from the start: one pass at HAL's point
                    // on whatever the rack can reach, then go home.
                    _centre = _ordered2;
                    _source = "hal-point-hold";
                    _type = "";
                    private _fallback = (values _types) select {(_x#0) > 0};
                    if (_fallback isNotEqualTo []) then {_profile = _fallback#0};
                };
            } else {
                _emptyPasses = 0;
                _hadTarget = true;
                _pick params ["_pickCentre","_pickType","_pickSource"];
                _centre = _pickCentre;
                _type = _pickType;
                _source = _pickSource;
                _profile = _types getOrDefault [_type,[]];
            };
            if (_profile isNotEqualTo []) then {
                _profile params ["","_pRadius","_pMode","_pBreak","_pIngress"];
                _radius = _pRadius;
                _mode = _pMode;
                _break = _pBreak;
                _ingress = _pIngress;
            };
            if (_emptyPasses >= ITW_CLASH_HeliAttackClearLaps) exitWith {
                _reason = if (_hadTarget) then {"clear"} else {"nothing-to-hit"};
            };
            if ((_mode isEqualTo "RUN" && {_break < 0}) || {_mode isEqualTo "ORBIT" && {_radius < 0}} || {_mode isEqualTo ""}) exitWith {
                _reason = "winchester";
            };

            private _height = [if (_mode isEqualTo "RUN") then {_break} else {_radius}] call ITW_CLASH_HeliAttack_fnc_Height;
            [_group,_flight,_height] call ITW_CLASH_HeliAttack_fnc_Arm;
            // Come in from the side we are already on, so no pass starts with
            // an overflight. A run always does; a ring only enters that way.
            if (_pass == 0 || {_mode isEqualTo "RUN"}) then {_bearing = _centre getDir (vehicle leader _group)};
            [if (_pass == 0) then {"start"} else {"pass"},[
                _id,typeOf (_flight#0),_pass,_source,_type,_halType,
                (_centre apply {round _x}) select [0,2],
                _mode,
                round (if (_mode isEqualTo "RUN") then {_break} else {_radius}),
                round _ingress,
                round _height,
                [_group,_hq,_centre,if (_mode isEqualTo "RUN") then {_ingress} else {_radius}] call ITW_CLASH_HeliAttack_fnc_Brief
            ]] call ITW_CLASH_HeliAttack_fnc_Log;
            _pass = _pass + 1;
            _legsLeft = if (_mode isEqualTo "RUN") then {1} else {round (360 / _step)};
            _closest = 1e10;
            _closestSpeed = -1;
            _closestHeight = -1;
            _passStart = time;
        };
        if (_reason isNotEqualTo "") exitWith {};

        // One leg: a whole run, or one step around the ring.
        private _points = [];
        private _runBearing = _bearing;
        if (_mode isEqualTo "RUN") then {
            private _breakPoint = _centre getPos [_break,_bearing];
            private _nextBearing = _bearing + (_direction * ITW_CLASH_HeliAttackRunOffset);
            private _ingressPoint = _centre getPos [_ingress,_nextBearing];
            _breakPoint set [2,0];
            _ingressPoint set [2,0];
            _points = [_breakPoint,_ingressPoint];
            _bearing = _nextBearing;
        } else {
            _bearing = _bearing + (_direction * _step);
            private _point = _centre getPos [_radius,_bearing];
            _point set [2,0];
            _points = [_point];
        };
        private _lead = leader _group;
        private _last = _points select ((count _points) - 1);
        // Check and order in one unscheduled step, so a withdrawal or release
        // that lands between them is not overwritten by this leg.
        isNil {
            _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
            if (_reason isEqualTo "") then {
                if (_mode isEqualTo "RUN") then {
                    [_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;
                    {
                        private _wp = _group addWaypoint [_x,0];
                        _wp setWaypointType "MOVE";
                        _wp setWaypointBehaviour "COMBAT";
                        _wp setWaypointCombatMode "YELLOW";
                        _wp setWaypointSpeed "NORMAL";
                        // Through the break, not to it: the next leg takes
                        // over well before arrival so it never slows there.
                        _wp setWaypointCompletionRadius (if (_forEachIndex == 0) then {200} else {ITW_CLASH_HeliAttackRunArrival});
                        _wp setWaypointName ITW_CLASH_HeliAttackWaypointName;
                        if (_forEachIndex == 0) then {_group setCurrentWaypoint _wp};
                    } forEach _points;
                } else {
                    _lead doMove (_points#0);
                };
            };
        };
        if (_reason isNotEqualTo "") exitWith {};
        [_group,_hq,_centre,if (_mode isEqualTo "RUN") then {_ingress} else {_radius}] call ITW_CLASH_HeliAttack_fnc_Brief;

        private _veh = vehicle _lead;
        private _path = 0;
        private _from = getPosATL _veh;
        {_path = _path + (_from distance2D _x); _from = _x} forEach _points;
        private _timeout = if (_mode isEqualTo "RUN") then {
            ITW_CLASH_HeliAttackLegTimeout max ((_path / ITW_CLASH_HeliAttackRunMinSpeed) + 30)
        } else {ITW_CLASH_HeliAttackLegTimeout};
        private _arrival = if (_mode isEqualTo "RUN") then {ITW_CLASH_HeliAttackRunArrival} else {ITW_CLASH_HeliAttackArrival};
        private _legStart = time;
        private _checkPos = getPosATL _veh;
        private _checkAt = time;
        waitUntil {
            sleep ITW_CLASH_HeliAttackPoll;
            _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
            if (_reason isNotEqualTo "") exitWith {true};
            _veh = vehicle leader _group;
            private _range = _veh distance2D _centre;
            if (_range < _closest) then {
                _closest = _range;
                _closestSpeed = speed _veh;
                _closestHeight = (getPosATL _veh)#2;
            };
            private _here = (_veh distance2D _last) <= _arrival;
            // Stalled for 20 s counts as there, as ALiVE's unitReadyRemote does.
            if ((time - _checkAt) >= 20) then {
                if ((getPosATL _veh) distance _checkPos < 10) then {_here = true};
                _checkPos = getPosATL _veh;
                _checkAt = time;
            };
            _here || {(time - _legStart) > _timeout}
        };
        if (_reason isNotEqualTo "") exitWith {};
        _legsLeft = _legsLeft - 1;
        if (_legsLeft <= 0) then {
            // The pass as flown: closest it came to the centre, how fast and
            // how high it was then, and what it fired. A RUN whose closest is
            // well inside its break is a run the AI left to close in.
            ["flown",[
                _id,_pass,_mode,round _runBearing,
                if (_mode isEqualTo "RUN") then {round _break} else {round _radius},
                round _closest,round _closestSpeed,round _closestHeight,
                round (time - _passStart),
                [_flight] call ITW_CLASH_HeliAttack_fnc_TakeShots
            ]] call ITW_CLASH_HeliAttack_fnc_Log;
        };
    };

    // Hand the flight back the way HAL left it: no orders of ours pending.
    {
        _x params ["_veh","_handler"];
        if (!isNull _veh) then {_veh removeEventHandler ["Fired",_handler]};
    } forEach _handlers;
    if (!isNull _group) then {
        isNil {
            // A sortie ending on its own terms can still have been taken
            // since the last poll; the late reason wins.
            if !(_reason in ITW_CLASH_HeliAttackForeignStops) then {
                private _late = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
                if (_late in ITW_CLASH_HeliAttackForeignStops) then {_reason = _late};
            };
            private _lead = leader _group;
            if (_reason in ITW_CLASH_HeliAttackForeignStops) then {
                // Someone else's orders may already be on the group: remove
                // only ours, and cancel the lead's doMove only if we gave one.
                for "_i" from ((count waypoints _group) - 1) to 0 step -1 do {
                    if ((waypointName [_group,_i]) isEqualTo ITW_CLASH_HeliAttackWaypointName) then {
                        deleteWaypoint [_group,_i];
                    };
                };
                if (_mode isEqualTo "ORBIT" && {!isNull _lead}) then {_lead doFollow _lead};
            } else {
                [_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;
                if (!isNull _lead) then {{_x doFollow _lead} forEach units _group};
                _group enableAttack _attackWas;
            };
        };
    };
    private _alive = !(_reason in ITW_CLASH_HeliAttackForeignStops);
    ["end",[
        _id,_reason,_pass,round (time - _started),_source,_type,
        [_flight] call ITW_CLASH_HeliAttack_fnc_TakeShots
    ]] call ITW_CLASH_HeliAttack_fnc_Log;
    [_alive,_reason]
};

ITW_CLASH_HeliAttackReady = true;
diag_log format [
    "CLASH BOOT | heli-attack-ready | version=%1 retarget=%2 maxUncertainty=%3 step=%4 runOffset=%5 legTimeout=%6 clearPasses=%7 maxTime=%8 height=%9-%10 modes=ORBIT,RUN combatMode=YELLOW attack=false noSAD=true halOwnsDecision=true reportedCentres=true revealsKnownOnly=true nativeFire=true yieldsToOwners=true",
    ITW_CLASH_HeliAttackVersion,
    ITW_CLASH_HeliAttackRetargetRadius,
    ITW_CLASH_HeliAttackMaxUncertainty,
    ITW_CLASH_HeliAttackStep,
    ITW_CLASH_HeliAttackRunOffset,
    ITW_CLASH_HeliAttackLegTimeout,
    ITW_CLASH_HeliAttackClearLaps,
    ITW_CLASH_HeliAttackMaxTime,
    ITW_CLASH_HeliAttackHeightMin,
    ITW_CLASH_HeliAttackHeightMax
];
true
