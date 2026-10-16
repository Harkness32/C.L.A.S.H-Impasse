#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HeliAttackStarted",false]) exitWith {true};

ITW_CLASH_HeliAttackStarted = true;
ITW_CLASH_HeliAttackVersion = 1;
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
      - Size the ring from the rack (ITW_CLASH_RackProfile.sqf): the radius
        whose whole stepped ring sits inside the most AI fire bands of the
        weapons that can hit that contact.
      - ORBIT when a gunner can shoot from the ring (turrets, door guns): keep
        moving around it, ALiVE style, entering on the near side.
        STATION when only the airframe can aim (pylons, pilot guns): hold a
        search-and-destroy point on the ring for a while, then the next one.
        That is the stand-off the AI needs to set up its own attack pass.
      - Reveal to the crew what the commander already knows inside the ring,
        and nothing else. The AI picks its own shots; nothing here fires.
      - Re-pick the centre every lap. Two laps with nothing the rack can hit
        near it, and the sortie is over.

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
// Degrees per step around the ring.
ITW_CLASH_HeliAttackStep = missionNamespace getVariable ["ITW_CLASH_HeliAttackStep",45];
// Station hold once arrived, and the most any one leg may take.
ITW_CLASH_HeliAttackStationDwell = missionNamespace getVariable ["ITW_CLASH_HeliAttackStationDwell",40];
ITW_CLASH_HeliAttackLegTimeout = missionNamespace getVariable ["ITW_CLASH_HeliAttackLegTimeout",120];
ITW_CLASH_HeliAttackArrival = missionNamespace getVariable ["ITW_CLASH_HeliAttackArrival",150];
// Laps with nothing to hit before the sortie ends.
ITW_CLASH_HeliAttackClearLaps = missionNamespace getVariable ["ITW_CLASH_HeliAttackClearLaps",2];
// HAL's own cap on a CAS loop (GoAttAir.sqf: _ct >= 1200).
ITW_CLASH_HeliAttackMaxTime = missionNamespace getVariable ["ITW_CLASH_HeliAttackMaxTime",1200];
// HAL's own sortie limits (GoAttAir.sqf mustRTB).
ITW_CLASH_HeliAttackMaxDamage = missionNamespace getVariable ["ITW_CLASH_HeliAttackMaxDamage",0.5];
ITW_CLASH_HeliAttackMinFuel = missionNamespace getVariable ["ITW_CLASH_HeliAttackMinFuel",0.3];
// Height over the ring, from its radius, inside these bounds.
ITW_CLASH_HeliAttackHeightMin = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightMin",50];
ITW_CLASH_HeliAttackHeightMax = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightMax",150];
ITW_CLASH_HeliAttackHeightRatio = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightRatio",0.15];
ITW_CLASH_HeliAttackPoll = missionNamespace getVariable ["ITW_CLASH_HeliAttackPoll",2];
// Marks the station waypoints this places, so a hand-back removes only those.
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

// Weapons free, every sortie, without waiting for a waypoint to apply it.
ITW_CLASH_HeliAttack_fnc_Arm = {
    params ["_group","_flight","_height"];
    _group setBehaviourStrong "COMBAT";
    _group setCombatMode "RED";
    _group enableAttack true;
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
    if ((_flight findIf {
        !alive _x || {damage _x > ITW_CLASH_HeliAttackMaxDamage} || {fuel _x < ITW_CLASH_HeliAttackMinFuel}
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

    ([_flight,_step] call ITW_CLASH_Rack_fnc_Profile) params ["_entries","_types"];
    private _anyUsable = (values _types) findIf {(_x#0) > 0};
    if (_anyUsable < 0) exitWith {
        ["start",[_id,typeOf (_flight#0),"rack-empty",[_target] call ITW_CLASH_HeliAttack_fnc_TypeOf]] call
            ITW_CLASH_HeliAttack_fnc_Log;
        [true,"rack-empty"]
    };

    private _handlers = _flight apply {[_x,[_x,_group] call ITW_CLASH_HeliAttack_fnc_WatchShots]};
    [_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;

    private _centre = [];
    private _type = "";
    private _source = "";
    private _radius = -1;
    private _mode = "";
    private _bearing = 0;
    private _direction = 1;
    private _lap = 0;
    private _stepsThisLap = 0;
    private _emptyLaps = 0;
    private _reason = "";
    private _hadTarget = false;

    while {true} do {
        _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
        if (_reason isNotEqualTo "") exitWith {};

        // A new lap: re-read the rack and the picture.
        if (_stepsThisLap <= 0) then {
            ([_flight,_step] call ITW_CLASH_Rack_fnc_Profile) params ["_nowEntries","_nowTypes"];
            _types = _nowTypes;
            // Out of everything that can hit anything: HAL's pylon rule, read
            // from the rack instead of a pylon count.
            if (((values _types) findIf {(_x#0) > 0}) < 0) exitWith {_reason = "winchester"};
            private _pick = [_side,_ordered2,_target,_types] call ITW_CLASH_HeliAttack_fnc_PickCentre;
            if (_pick isEqualTo []) then {
                _emptyLaps = _emptyLaps + 1;
                if (_centre isEqualTo []) then {
                    // Nothing to hit from the start: hold one lap at HAL's
                    // point on whatever the rack can reach, then go home.
                    _centre = _ordered2;
                    _source = "hal-point-hold";
                    private _fallback = (values _types) select {(_x#0) > 0};
                    _type = "";
                    _radius = if (_fallback isEqualTo []) then {-1} else {(_fallback#0)#1};
                    _mode = if (_fallback isEqualTo []) then {""} else {(_fallback#0)#2};
                };
            } else {
                _emptyLaps = 0;
                _hadTarget = true;
                _pick params ["_pickCentre","_pickType","_pickSource"];
                _centre = _pickCentre;
                _type = _pickType;
                _source = _pickSource;
                (_types get _type) params ["","_pickRadius","_pickMode"];
                _radius = _pickRadius;
                _mode = _pickMode;
            };
            if (_radius < 0) exitWith {_reason = "winchester"};
            if (_emptyLaps >= ITW_CLASH_HeliAttackClearLaps) exitWith {
                _reason = if (_hadTarget) then {"clear"} else {"nothing-to-hit"};
            };

            private _height = [_radius] call ITW_CLASH_HeliAttack_fnc_Height;
            [_group,_flight,_height] call ITW_CLASH_HeliAttack_fnc_Arm;
            // Enter on the side we are already on, so arrival is not an overflight.
            if (_lap == 0) then {_bearing = _centre getDir (vehicle leader _group)};
            private _shots = createHashMap;
            {
                private _veh = _x;
                {_shots set [_x,(_shots getOrDefault [_x,0]) + _y]} forEach (_veh getVariable ["ITW_CLASH_HeliAttackShots",createHashMap]);
                _veh setVariable ["ITW_CLASH_HeliAttackShots",createHashMap];
            } forEach (_flight select {alive _x});
            [if (_lap == 0) then {"start"} else {"lap"},[
                _id,typeOf (_flight#0),_lap,_source,_type,
                (_centre apply {round _x}) select [0,2],
                round _radius,_mode,round _height,
                [_group,_hq,_centre,_radius] call ITW_CLASH_HeliAttack_fnc_Brief,
                (keys _shots) apply {[_x,_shots get _x]}
            ]] call ITW_CLASH_HeliAttack_fnc_Log;
            _lap = _lap + 1;
            _stepsThisLap = round (360 / _step);
        };
        if (_reason isNotEqualTo "") exitWith {};

        // One step around the ring.
        _bearing = _bearing + (_direction * _step);
        private _point = _centre getPos [_radius,_bearing];
        _point set [2,0];
        private _lead = leader _group;
        // Check and order in one unscheduled step, so a withdrawal or release
        // that lands between them is not overwritten by this leg.
        isNil {
            _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
            if (_reason isEqualTo "") then {
                if (_mode isEqualTo "STATION") then {
                    [_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;
                    private _wp = _group addWaypoint [_point,0];
                    _wp setWaypointType "SAD";
                    _wp setWaypointBehaviour "COMBAT";
                    _wp setWaypointCombatMode "RED";
                    _wp setWaypointSpeed "NORMAL";
                    _wp setWaypointCompletionRadius 100;
                    _wp setWaypointName ITW_CLASH_HeliAttackWaypointName;
                    _group setCurrentWaypoint _wp;
                } else {
                    _lead doMove _point;
                };
            };
        };
        if (_reason isNotEqualTo "") exitWith {};
        [_group,_hq,_centre,_radius] call ITW_CLASH_HeliAttack_fnc_Brief;

        private _legStart = time;
        private _arrivedAt = -1;
        private _checkPos = getPosATL (vehicle _lead);
        private _checkAt = time;
        waitUntil {
            sleep ITW_CLASH_HeliAttackPoll;
            _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
            if (_reason isNotEqualTo "") exitWith {true};
            private _veh = vehicle leader _group;
            private _here = (_veh distance2D _point) <= ITW_CLASH_HeliAttackArrival;
            // Stalled for 20 s counts as there, as ALiVE's unitReadyRemote does.
            if ((time - _checkAt) >= 20) then {
                if ((getPosATL _veh) distance _checkPos < 10) then {_here = true};
                _checkPos = getPosATL _veh;
                _checkAt = time;
            };
            if (_here && {_arrivedAt < 0}) then {_arrivedAt = time};
            private _dwell = if (_mode isEqualTo "STATION") then {ITW_CLASH_HeliAttackStationDwell} else {0};
            (_arrivedAt >= 0 && {(time - _arrivedAt) >= _dwell})
            || {(time - _legStart) > ITW_CLASH_HeliAttackLegTimeout}
        };
        if (_reason isNotEqualTo "") exitWith {};
        _stepsThisLap = _stepsThisLap - 1;
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
            };
        };
    };
    private _alive = !(_reason in ITW_CLASH_HeliAttackForeignStops);
    ["end",[_id,_reason,_lap,round (time - _started),_source,_type]] call ITW_CLASH_HeliAttack_fnc_Log;
    [_alive,_reason]
};

ITW_CLASH_HeliAttackReady = true;
diag_log format [
    "CLASH BOOT | heli-attack-ready | version=%1 retarget=%2 maxUncertainty=%3 step=%4 dwell=%5 legTimeout=%6 clearLaps=%7 maxTime=%8 height=%9-%10 modes=ORBIT,STATION halOwnsDecision=true reportedCentres=true revealsKnownOnly=true nativeFire=true yieldsToOwners=true",
    ITW_CLASH_HeliAttackVersion,
    ITW_CLASH_HeliAttackRetargetRadius,
    ITW_CLASH_HeliAttackMaxUncertainty,
    ITW_CLASH_HeliAttackStep,
    ITW_CLASH_HeliAttackStationDwell,
    ITW_CLASH_HeliAttackLegTimeout,
    ITW_CLASH_HeliAttackClearLaps,
    ITW_CLASH_HeliAttackMaxTime,
    ITW_CLASH_HeliAttackHeightMin,
    ITW_CLASH_HeliAttackHeightMax
];
true
