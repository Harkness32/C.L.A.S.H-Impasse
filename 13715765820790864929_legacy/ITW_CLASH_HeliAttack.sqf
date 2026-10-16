#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HeliAttackStarted",false]) exitWith {true};

ITW_CLASH_HeliAttackStarted = true;
ITW_CLASH_HeliAttackVersion = 3;
ITW_CLASH_HeliAttackReady = false;

/*
    How a HAL attack helicopter flies its sortie, from the order to "come home".

    HAL's GoAttAir puts one search-and-destroy waypoint on the target itself,
    radius 0, and waits for it to complete. Run of 2026-10-15: the stub-wing
    Ghost Hawks spent their sorties 15 to 200 m from the infantry they were
    sent at, flying tight circles, pitching up and doubling back, never
    setting up a run. Their only weapon, the DAGR-M, has no AI fire mode
    inside 300 m.

    So C.L.A.S.H.'s copy of GoAttAir hands helicopter sorties here, and HAL
    keeps every decision: what to attack and when (its dispatcher), when a
    sortie must end (damage, fuel, its Busy flag), and the return and landing
    afterwards. This owns only the movement in between. The crew picks and
    takes every shot; nothing here fires. Two ways to fly it, from the rack
    (ITW_CLASH_RackProfile.sqf):

      - ORBIT when a gunner can shoot (chin guns, turrets, door guns): keep
        moving around a ring sized from the rack, ALiVE style (cas.fsm, GPL;
        the pattern, not its code). Good for attack helicopters with chin
        guns (Hark, 2026-10-16), and kept as it was.
      - POINT when only the airframe can aim (pylons, pilot guns): detect a
        target, get far, point at it, point at, point at, break off, detect
        again (Hark, 2026-10-16). v1 held a search-and-destroy point and the
        AI left it to knife-fight a Panther from 342 to 685 m; v2 flew attack
        runs, which still passed over targets and swung wide circles between
        their two points. POINT hovers at a standoff and turns the nose onto
        what the crew knows of, so the crew acquires and shoots, then hops a
        short way to the side and does it again. See fnc_FlyPoint.

    Combat mode YELLOW and attack off in both: the crew fires at will but
    does not leave its line to chase.

    HAL's sortie rules end it from here too, so its return-to-base tail runs
    unchanged afterwards. When something else takes the group mid-sortie (a
    CLASH release or withdrawal, HAL's own Break), the sortie stops within a
    poll, leaves that owner's orders standing, and GoAttAir exits the way it
    does when RYD_Wait reports the group gone: no return leg on top of them.
*/

// Contacts this far from HAL's point can be looked at or pointed at.
ITW_CLASH_HeliAttackRetargetRadius = missionNamespace getVariable ["ITW_CLASH_HeliAttackRetargetRadius",1500];
// A reported contact more uncertain than this is not worth looking at.
ITW_CLASH_HeliAttackMaxUncertainty = missionNamespace getVariable ["ITW_CLASH_HeliAttackMaxUncertainty",300];
// ORBIT: degrees per step around the ring, the most one leg may take, arrival.
ITW_CLASH_HeliAttackStep = missionNamespace getVariable ["ITW_CLASH_HeliAttackStep",45];
ITW_CLASH_HeliAttackLegTimeout = missionNamespace getVariable ["ITW_CLASH_HeliAttackLegTimeout",120];
ITW_CLASH_HeliAttackArrival = missionNamespace getVariable ["ITW_CLASH_HeliAttackArrival",150];
// Laps (ORBIT) or looks (POINT) with nothing to hit before the sortie ends.
ITW_CLASH_HeliAttackClearLaps = missionNamespace getVariable ["ITW_CLASH_HeliAttackClearLaps",2];
// HAL's own cap on a CAS loop (GoAttAir.sqf: _ct >= 1200).
ITW_CLASH_HeliAttackMaxTime = missionNamespace getVariable ["ITW_CLASH_HeliAttackMaxTime",1200];
// HAL's own sortie limits (GoAttAir.sqf mustRTB).
ITW_CLASH_HeliAttackMaxDamage = missionNamespace getVariable ["ITW_CLASH_HeliAttackMaxDamage",0.5];
ITW_CLASH_HeliAttackMinFuel = missionNamespace getVariable ["ITW_CLASH_HeliAttackMinFuel",0.3];
// Height, from the ring radius or the standoff, inside these bounds.
ITW_CLASH_HeliAttackHeightMin = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightMin",50];
ITW_CLASH_HeliAttackHeightMax = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightMax",150];
ITW_CLASH_HeliAttackHeightRatio = missionNamespace getVariable ["ITW_CLASH_HeliAttackHeightRatio",0.15];
ITW_CLASH_HeliAttackPoll = missionNamespace getVariable ["ITW_CLASH_HeliAttackPoll",2];

/*
    POINT. Point-ats per firing position; how close the nose must be (degrees)
    to count as on; how long to wait for that; how long the native AI gets
    to turn before the yaw assist helps; how long to hold once on. A shot by
    the crew ends the point-at two seconds later.
*/
ITW_CLASH_HeliAttackPointAims = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointAims",3];
ITW_CLASH_HeliAttackPointAlign = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointAlign",8];
ITW_CLASH_HeliAttackPointAlignTimeout = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointAlignTimeout",8];
ITW_CLASH_HeliAttackPointAssistAfter = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointAssistAfter",1.5];
ITW_CLASH_HeliAttackPointHold = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointHold",8];
/*
    Break off: the next position is a hop this long to the side at the same
    standoff (the bearing step it takes, capped), alternating sides. A move
    shorter than HopFar is flown at HopSpeed (km/h) so it turns tight and
    stops sharp; a longer one at the airframe's own speed. Arrival radius and
    the slowest a move may average before it times out (m/s).
*/
ITW_CLASH_HeliAttackPointHop = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointHop",700];
ITW_CLASH_HeliAttackPointHopMaxStep = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointHopMaxStep",40];
ITW_CLASH_HeliAttackPointHopFar = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointHopFar",1500];
ITW_CLASH_HeliAttackPointHopSpeed = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointHopSpeed",120];
ITW_CLASH_HeliAttackPointArrival = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointArrival",120];
ITW_CLASH_HeliAttackPointMinSpeed = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointMinSpeed",12];
// Looking with nothing found: how long to watch from a standoff.
ITW_CLASH_HeliAttackPointLookWait = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointLookWait",20];
// A sighting older than this is not pointed at (revealed, unseen targets are).
ITW_CLASH_HeliAttackPointKnownAge = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointKnownAge",120];
// A firing position is not chosen within this of another known enemy if avoidable.
ITW_CLASH_HeliAttackPointClearRadius = missionNamespace getVariable ["ITW_CLASH_HeliAttackPointClearRadius",600];
/*
    Yaw assist: rad/s of turn per radian of heading error, the most it turns
    (rad/s), and only below this speed (km/h). The sign is the engine's
    angular velocity convention: positive about the up axis turns left under
    the right-hand rule, so a target to the right needs negative. If a turn
    ever opens the error instead, fnc_Aim flips it once and says so.
*/
ITW_CLASH_HeliAttackYawGain = missionNamespace getVariable ["ITW_CLASH_HeliAttackYawGain",2];
ITW_CLASH_HeliAttackYawRate = missionNamespace getVariable ["ITW_CLASH_HeliAttackYawRate",0.8];
ITW_CLASH_HeliAttackYawMaxSpeed = missionNamespace getVariable ["ITW_CLASH_HeliAttackYawMaxSpeed",40];
ITW_CLASH_HeliAttackYawSign = missionNamespace getVariable ["ITW_CLASH_HeliAttackYawSign",-1];

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

// What the commander knows near the centre, told to the crew. Nothing more.
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

// Shots, for the log: missiles and rockets one by one, guns per pass; and a
// running total per aircraft, which a point-at reads to see the crew fire.
ITW_CLASH_HeliAttack_fnc_WatchShots = {
    params ["_veh","_group"];
    _veh setVariable ["ITW_CLASH_HeliAttackShots",createHashMap];
    _veh setVariable ["ITW_CLASH_HeliAttackGroup",_group];
    _veh addEventHandler ["Fired",{
        params ["_unit","_weapon","","","_ammo","","","_gunner"];
        private _simulation = toLowerANSI getText (configFile >> "CfgAmmo" >> _ammo >> "simulation");
        // Flares and smoke are not shots.
        if (!isNil "ITW_CLASH_Rack_fnc_IsCountermeasure" && {[_weapon,_simulation] call ITW_CLASH_Rack_fnc_IsCountermeasure}) exitWith {};
        private _shots = _unit getVariable ["ITW_CLASH_HeliAttackShots",createHashMap];
        _shots set [_weapon,(_shots getOrDefault [_weapon,0]) + 1];
        _unit setVariable ["ITW_CLASH_HeliAttackShotTotal",(_unit getVariable ["ITW_CLASH_HeliAttackShotTotal",0]) + 1];
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

// Degrees the target is off the nose, -180 to 180; positive is to the right.
ITW_CLASH_HeliAttack_fnc_HeadingError = {
    params ["_veh","_pos"];
    ((((_veh getDir _pos) - (getDir _veh)) + 540) mod 360) - 180
};

/*
    Where the crew thinks a target is: the leader's targetKnowledge, never the
    object's true position. [] when the group does not know it, or when its
    last sighting is older than _maxAge. A target the crew knows of but has
    never seen itself (revealed: lastSeen is -2147483.648) still counts; that
    is the knowledge a point-at turns into a sighting.
*/
ITW_CLASH_HeliAttack_fnc_Perceived = {
    params ["_group","_object",["_maxAge",-1]];
    private _lead = leader _group;
    if (isNull _lead || {isNull _object}) exitWith {[]};
    private _intel = _lead targetKnowledge _object;
    if !(_intel isEqualType [] && {count _intel >= 7}) exitWith {[]};
    _intel params ["_byGroup","_byUnit","_lastSeen","","","","_pos"];
    if (!(_byGroup isEqualTo true) && {!(_byUnit isEqualTo true)}) exitWith {[]};
    if (_maxAge > 0 && {_lastSeen isEqualType 0} && {_lastSeen >= 0} && {(time - _lastSeen) > _maxAge}) exitWith {[]};
    if !(_pos isEqualType [] && {count _pos >= 2}) exitWith {[]};
    [_pos#0,_pos#1,0]
};

/*
    Detect: what the crew knows of near the centre that the rack can hit,
    [[vehicle, class, perceived position], ...], best first: HAL's own target,
    then armour, vehicles, statics, men, each nearest first. The crew's own
    knowledge (targets), which includes what Brief revealed from the
    commander; never true positions.
*/
ITW_CLASH_HeliAttack_fnc_Detect = {
    params ["_group","_types","_centre","_halTarget"];
    private _halVeh = if (isNull _halTarget) then {objNull} else {vehicle _halTarget};
    private _from = vehicle leader _group;
    private _seen = [];
    private _found = [];
    {
        private _veh = vehicle _x;
        if (_veh in _seen || {!alive _veh}) then {continue};
        _seen pushBack _veh;
        private _class = [_veh] call ITW_CLASH_HeliAttack_fnc_TypeOf;
        if (((_types getOrDefault [_class,[0]])#0) <= 0) then {continue};
        private _pos = [_group,_veh,ITW_CLASH_HeliAttackPointKnownAge] call ITW_CLASH_HeliAttack_fnc_Perceived;
        if (_pos isEqualTo [] || {(_pos distance2D _centre) > ITW_CLASH_HeliAttackRetargetRadius}) then {continue};
        private _rank = if (_veh isEqualTo _halVeh) then {-1} else {(["ARMOR","VEHICLE","STATIC","INFANTRY"] find _class) max 0};
        _found pushBack [_rank,_from distance2D _pos,_veh,_class,_pos];
    } forEach (_group targets [true,ITW_CLASH_HeliAttackRetargetRadius,[],0,_centre]);
    _found = [_found,[],{((_x#0) + 1) * 1e6 + (_x#1)},"ASCEND"] call BIS_fnc_sortBy;
    _found apply {[_x#2,_x#3,_x#4]}
};

/*
    Where to point from: _standoff metres from the target, on bearing _base
    or 30 or 60 degrees either side, preferring the one that sees the target
    over the terrain from the height it will hover at, then the one with
    fewest other known enemies within ClearRadius (so it is not parked over
    another target), then the smallest turn off _base.
    Returns [position, bearing, line of sight, enemies near].
*/
ITW_CLASH_HeliAttack_fnc_FiringPosition = {
    params ["_targetPos","_standoff","_base","_height","_others"];
    private _eye = [_targetPos#0,_targetPos#1,(getTerrainHeightASL [_targetPos#0,_targetPos#1]) + 2];
    private _best = [];
    private _bestScore = 1e10;
    {
        private _offset = _x;
        private _bearing = _base + _offset;
        private _pos = _targetPos getPos [_standoff,_bearing];
        _pos set [2,0];
        private _from = [_pos#0,_pos#1,(getTerrainHeightASL [_pos#0,_pos#1]) + _height];
        private _los = !(terrainIntersectASL [_from,_eye]);
        private _near = {(_x distance2D _pos) < ITW_CLASH_HeliAttackPointClearRadius} count _others;
        private _score = (if (_los) then {0} else {1000}) + (_near * 100) + (abs _offset);
        if (_score < _bestScore) then {
            _bestScore = _score;
            _best = [_pos,_bearing,_los,_near];
        };
    } forEach [0,30,-30,60,-60];
    _best
};

// The bearing step a hop of PointHop metres is at this standoff, capped.
ITW_CLASH_HeliAttack_fnc_HopStep = {
    params ["_standoff"];
    (2 * (asin ((ITW_CLASH_HeliAttackPointHop / (2 * (_standoff max 1))) min 1))) min ITW_CLASH_HeliAttackPointHopMaxStep
};

// Hit, or a missile inbound: the moment to break off a firing position.
ITW_CLASH_HeliAttack_fnc_WatchThreats = {
    params ["_veh"];
    [
        _veh addEventHandler ["Hit",{(_this#0) setVariable ["ITW_CLASH_HeliAttackThreatAt",time]}],
        _veh addEventHandler ["IncomingMissile",{(_this#0) setVariable ["ITW_CLASH_HeliAttackThreatAt",time]}]
    ]
};

// Drop what this told the crews to watch and target.
ITW_CLASH_HeliAttack_fnc_Unwatch = {
    params ["_flight"];
    {
        private _veh = _x;
        {
            if (!isNull _x && {alive _x}) then {_x doWatch objNull; _x doTarget objNull};
        } forEach [driver _veh,gunner _veh];
    } forEach (_flight select {!isNull _x});
};

/*
    Yaw assist. While a helicopter hovers on a firing position and its nose
    has not come round, turn it at a rate proportional to the heading error,
    capped. Heading only: pitch, and the shot, stay the AI's. Every frame from
    one mission handler; an entry lapses 1.5 s after the last point-at poll
    renewed it, so a dead script cannot leave an aircraft turning. Local
    aircraft only: angular velocity is set where the vehicle is simulated.
    Entry: [vehicle, perceived target position, until].
*/
ITW_CLASH_HeliAttackYaw = [];

ITW_CLASH_HeliAttack_fnc_YawHold = {
    params ["_veh","_pos"];
    isNil {
        private _entry = [_veh,+_pos,time + 1.5];
        private _i = ITW_CLASH_HeliAttackYaw findIf {(_x#0) isEqualTo _veh};
        if (_i < 0) then {ITW_CLASH_HeliAttackYaw pushBack _entry} else {ITW_CLASH_HeliAttackYaw set [_i,_entry]};
    };
};

ITW_CLASH_HeliAttack_fnc_YawRelease = {
    params ["_veh"];
    isNil {ITW_CLASH_HeliAttackYaw = ITW_CLASH_HeliAttackYaw select {!((_x#0) isEqualTo _veh)}};
};

ITW_CLASH_HeliAttack_fnc_YawFrame = {
    if (ITW_CLASH_HeliAttackYaw isEqualTo []) exitWith {};
    ITW_CLASH_HeliAttackYaw = ITW_CLASH_HeliAttackYaw select {
        !isNull (_x#0) && {alive (_x#0)} && {local (_x#0)} && {time <= (_x#2)}
    };
    {
        _x params ["_veh","_pos"];
        if ((speed _veh) > ITW_CLASH_HeliAttackYawMaxSpeed || {((getPosATL _veh)#2) < 5}) then {continue};
        private _err = [_veh,_pos] call ITW_CLASH_HeliAttack_fnc_HeadingError;
        private _rate = (((rad _err) * ITW_CLASH_HeliAttackYawGain) max (-ITW_CLASH_HeliAttackYawRate)) min ITW_CLASH_HeliAttackYawRate;
        private _w = angularVelocityModelSpace _veh;
        _veh setAngularVelocityModelSpace [_w#0,_w#1,_rate * ITW_CLASH_HeliAttackYawSign];
    } forEach ITW_CLASH_HeliAttackYaw;
};

if (isNil "ITW_CLASH_HeliAttackYawHandler") then {
    ITW_CLASH_HeliAttackYawHandler = addMissionEventHandler ["EachFrame",{call ITW_CLASH_HeliAttack_fnc_YawFrame}];
};

/*
    One point-at: nose onto a target, held while the crew decides to shoot.
    The pilot and any gunner are told to watch and target it, which is all
    the native AI needs if it turns for its own weapons; if the nose has not
    come round within AssistAfter seconds, the yaw assist turns the airframe
    while it hovers. Never fires.

    Done once on target and held for Hold seconds, or two seconds after the
    crew's first shot, or when it never comes on within AlignTimeout. Out
    early when the target dies, the crew loses it, the aircraft is hit or a
    missile comes in, or the sortie must stop.

    Returns [class, seconds to come on or -1, assisted, shots, alive after, why].
*/
ITW_CLASH_HeliAttack_fnc_Aim = {
    params ["_ctx","_tgt","_class"];
    private _group = _ctx get "group";
    private _all = _ctx get "flight";
    private _started = _ctx get "started";
    private _flight = _all select {alive _x};
    private _shotsNow = {
        private _sum = 0;
        {_sum = _sum + (_x getVariable ["ITW_CLASH_HeliAttackShotTotal",0])} forEach _flight;
        _sum
    };
    private _before = call _shotsNow;
    {
        private _veh = _x;
        private _crew = [driver _veh];
        if (!isNull (gunner _veh) && {(gunner _veh) isNotEqualTo (driver _veh)}) then {_crew pushBack (gunner _veh)};
        {
            if (!isNull _x && {alive _x}) then {_x doWatch _tgt; _x doTarget _tgt};
        } forEach _crew;
    } forEach _flight;

    private _start = time;
    private _onAt = -1;
    private _shotAt = -1;
    private _assisted = false;
    private _assistErr = -1;
    private _checkSignAt = -1;
    private _why = "";
    waitUntil {
        sleep 0.5;
        _why = [_group,_all,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
        if (_why isNotEqualTo "") exitWith {true};
        if (!alive _tgt) exitWith {_why = "dead"; true};
        private _pos = [_group,_tgt] call ITW_CLASH_HeliAttack_fnc_Perceived;
        if (_pos isEqualTo []) exitWith {_why = "lost"; true};
        if ((_flight findIf {(_x getVariable ["ITW_CLASH_HeliAttackThreatAt",-1]) >= _start}) >= 0) exitWith {
            _why = "threat";
            true
        };
        private _err = abs ([vehicle leader _group,_pos] call ITW_CLASH_HeliAttack_fnc_HeadingError);
        if (_err <= ITW_CLASH_HeliAttackPointAlign && {_onAt < 0}) then {_onAt = time};
        if (_shotAt < 0 && {(call _shotsNow) > _before}) then {_shotAt = time};
        // The nose has not come round on its own: turn it.
        if (!_assisted && {_onAt < 0} && {(time - _start) >= ITW_CLASH_HeliAttackPointAssistAfter}) then {
            _assisted = true;
            _assistErr = _err;
            _checkSignAt = time + 1.5;
        };
        if (_assisted) then {
            {[_x,_pos] call ITW_CLASH_HeliAttack_fnc_YawHold} forEach _flight;
            // A turn that opened the error ran the wrong way: learn the
            // engine's sign once, for every sortie after.
            if (_checkSignAt > 0 && {time >= _checkSignAt}) then {
                _checkSignAt = -1;
                if (_onAt < 0 && {_err > (_assistErr + 10)}) then {
                    ITW_CLASH_HeliAttackYawSign = -ITW_CLASH_HeliAttackYawSign;
                    ["yaw-sign-flipped",[_ctx get "id",ITW_CLASH_HeliAttackYawSign,round _assistErr,round _err]] call
                        ITW_CLASH_HeliAttack_fnc_Log;
                };
            };
        };
        (_onAt >= 0 && {(time - _onAt) >= ITW_CLASH_HeliAttackPointHold})
        || {_shotAt >= 0 && {(time - _shotAt) >= 2}}
        || {_onAt < 0 && {(time - _start) >= ITW_CLASH_HeliAttackPointAlignTimeout}}
    };
    {[_x] call ITW_CLASH_HeliAttack_fnc_YawRelease} forEach _flight;
    [
        _class,
        if (_onAt < 0) then {-1} else {(round ((_onAt - _start) * 10)) / 10},
        _assisted,
        (call _shotsNow) - _before,
        alive _tgt,
        _why
    ]
};

/*
    Fly to a position and stop there. A move shorter than HopFar is flown at
    HopSpeed, so it turns tight and stops sharp instead of swinging wide; a
    longer one at the airframe's own speed. Ordered in one unscheduled step
    with the stop check, so a withdrawal or release that lands between them
    is not overwritten. Returns a stop reason or "".
*/
ITW_CLASH_HeliAttack_fnc_MoveTo = {
    params ["_ctx","_point"];
    private _group = _ctx get "group";
    private _flight = _ctx get "flight";
    private _started = _ctx get "started";
    private _veh = vehicle leader _group;
    private _distance = _veh distance2D _point;
    private _limit = if (_distance <= ITW_CLASH_HeliAttackPointHopFar) then {ITW_CLASH_HeliAttackPointHopSpeed} else {1e10};
    private _reason = "";
    [_flight] call ITW_CLASH_HeliAttack_fnc_Unwatch;
    isNil {
        _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
        if (_reason isEqualTo "") then {
            {_x limitSpeed _limit} forEach (_flight select {alive _x});
            (leader _group) doMove _point;
        };
    };
    if (_reason isNotEqualTo "") exitWith {_reason};
    private _timeout = ITW_CLASH_HeliAttackLegTimeout max ((_distance / ITW_CLASH_HeliAttackPointMinSpeed) + 30);
    private _start = time;
    private _checkPos = getPosATL _veh;
    private _checkAt = time;
    waitUntil {
        sleep ITW_CLASH_HeliAttackPoll;
        _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
        if (_reason isNotEqualTo "") exitWith {true};
        _veh = vehicle leader _group;
        private _here = (_veh distance2D _point) <= ITW_CLASH_HeliAttackPointArrival;
        // Stalled for 20 s counts as there, as ALiVE's unitReadyRemote does.
        if ((time - _checkAt) >= 20) then {
            if ((getPosATL _veh) distance _checkPos < 10) then {_here = true};
            _checkPos = getPosATL _veh;
            _checkAt = time;
        };
        _here || {(time - _start) > _timeout}
    };
    _reason
};

/*
    ORBIT: a ring around the centre for racks a gunner can shoot from. As in
    v2: re-pick the centre every lap; two laps with nothing to hit near it,
    and the sortie is over.
*/
ITW_CLASH_HeliAttack_fnc_FlyOrbit = {
    params ["_ctx"];
    private _group = _ctx get "group";
    private _hq = _ctx get "hq";
    private _target = _ctx get "target";
    private _flight = _ctx get "flight";
    private _started = _ctx get "started";
    private _ordered2 = _ctx get "ordered";
    private _side = _ctx get "side";
    private _id = _ctx get "id";
    private _halType = _ctx get "halType";
    private _step = ITW_CLASH_HeliAttackStep;
    private _types = _ctx get "types";
    private _centre = [];
    private _type = "";
    private _source = "";
    private _radius = -1;
    private _bearing = 0;
    private _pass = 0;
    private _legsLeft = 0;
    private _emptyPasses = 0;
    private _reason = "";
    private _hadTarget = false;
    private _closest = 1e10;
    private _closestSpeed = -1;
    private _closestHeight = -1;
    private _passStart = time;

    while {true} do {
        _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
        if (_reason isNotEqualTo "") exitWith {};

        // A new lap: re-read the rack and the picture.
        if (_legsLeft <= 0) then {
            ([_flight,_step] call ITW_CLASH_Rack_fnc_Profile) params ["","_nowTypes"];
            _types = _nowTypes;
            // Out of everything that can hit anything: HAL's pylon rule, read
            // from the rack instead of a pylon count.
            if (((values _types) findIf {(_x#0) > 0}) < 0) exitWith {_reason = "winchester"};
            private _pick = [_side,_ordered2,_target,_types] call ITW_CLASH_HeliAttack_fnc_PickCentre;
            private _profile = [];
            if (_pick isEqualTo []) then {
                _emptyPasses = _emptyPasses + 1;
                if (_centre isEqualTo []) then {
                    // Nothing to hit from the start: one lap at HAL's point on
                    // whatever ring the rack has, then go home.
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
            if (_profile isNotEqualTo []) then {_radius = _profile#1};
            if (_emptyPasses >= ITW_CLASH_HeliAttackClearLaps) exitWith {
                _reason = if (_hadTarget) then {"clear"} else {"nothing-to-hit"};
            };
            if (_radius < 0) exitWith {_reason = "winchester"};

            private _height = [_radius] call ITW_CLASH_HeliAttack_fnc_Height;
            [_group,_flight,_height] call ITW_CLASH_HeliAttack_fnc_Arm;
            // Enter on the side we are already on, so arrival is not an overflight.
            if (_pass == 0) then {_bearing = _centre getDir (vehicle leader _group)};
            [if (_pass == 0) then {"start"} else {"pass"},[
                _id,typeOf (_flight#0),_pass,_source,_type,_halType,
                (_centre apply {round _x}) select [0,2],
                "ORBIT",round _radius,round _height,
                [_group,_hq,_centre,_radius] call ITW_CLASH_HeliAttack_fnc_Brief
            ]] call ITW_CLASH_HeliAttack_fnc_Log;
            _pass = _pass + 1;
            _legsLeft = round (360 / _step);
            _closest = 1e10;
            _closestSpeed = -1;
            _closestHeight = -1;
            _passStart = time;
        };
        if (_reason isNotEqualTo "") exitWith {};

        // One step around the ring.
        _bearing = _bearing + _step;
        private _point = _centre getPos [_radius,_bearing];
        _point set [2,0];
        private _lead = leader _group;
        // Check and order in one unscheduled step, so a withdrawal or release
        // that lands between them is not overwritten by this leg.
        isNil {
            _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
            if (_reason isEqualTo "") then {_lead doMove _point};
        };
        if (_reason isNotEqualTo "") exitWith {};
        [_group,_hq,_centre,_radius] call ITW_CLASH_HeliAttack_fnc_Brief;

        private _veh = vehicle _lead;
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
            private _here = (_veh distance2D _point) <= ITW_CLASH_HeliAttackArrival;
            // Stalled for 20 s counts as there, as ALiVE's unitReadyRemote does.
            if ((time - _checkAt) >= 20) then {
                if ((getPosATL _veh) distance _checkPos < 10) then {_here = true};
                _checkPos = getPosATL _veh;
                _checkAt = time;
            };
            _here || {(time - _legStart) > ITW_CLASH_HeliAttackLegTimeout}
        };
        if (_reason isNotEqualTo "") exitWith {};
        _legsLeft = _legsLeft - 1;
        if (_legsLeft <= 0) then {
            // The lap as flown: closest it came to the centre, how fast and
            // how high it was then, and what it fired.
            ["flown",[
                _id,_pass,"ORBIT",round _radius,
                round _closest,round _closestSpeed,round _closestHeight,
                round (time - _passStart),
                [_flight] call ITW_CLASH_HeliAttack_fnc_TakeShots
            ]] call ITW_CLASH_HeliAttack_fnc_Log;
        };
    };
    _ctx set ["passes",_pass];
    _ctx set ["source",_source];
    _ctx set ["type",_type];
    _reason
};

/*
    POINT, for racks only the airframe can aim. "Detect something, get far,
    point at, point at, point at, break off, detect something" (Hark,
    2026-10-16). A loop over firing positions:

      - Detect what the crew knows of near the centre that the rack can hit
        (fnc_Detect), after telling it what the commander knows there. The
        centre is a contact our side has reported, or HAL's point.
        Nothing: look from a standoff on our side for a while, nose on the
        centre; two looks with nothing and the sortie is over.
      - Get far: a firing position at the rack's standoff from the best
        target (2 km for guided weapons, 1 km for unguided), on the side the
        helicopter is on, that sees the target over the terrain and is clear
        of other known enemies (fnc_FiringPosition). Flown to and stopped.
      - Point at, up to three times: nose onto the best target first, then
        others it knows of, each held while the crew decides to shoot
        (fnc_Aim). The crew pulls the trigger; this only points.
      - Break off: the next position is a hop of about 700 m to the side at
        the same standoff, alternating sides, flown slow so it turns tight:
        a zig-zag across the front, never a circle and never over the top.
        A hit or a missile inbound breaks off at once.
*/
ITW_CLASH_HeliAttack_fnc_FlyPoint = {
    params ["_ctx"];
    private _group = _ctx get "group";
    private _hq = _ctx get "hq";
    private _target = _ctx get "target";
    private _flight = _ctx get "flight";
    private _started = _ctx get "started";
    private _ordered2 = _ctx get "ordered";
    private _side = _ctx get "side";
    private _id = _ctx get "id";
    private _halType = _ctx get "halType";
    private _reason = "";
    private _looks = 0;
    private _hadTarget = false;
    private _positions = 0;
    private _zig = 1;
    private _moved = false;
    private _source = "";
    private _type = "";

    private _startTypes = _ctx get "types";
    ["start",[
        _id,typeOf (_flight#0),"POINT",_halType,(_ordered2 apply {round _x}) select [0,2],
        ((keys _startTypes) select {((_startTypes get _x)#0) > 0}) apply {[_x,(_startTypes get _x)#3]}
    ]] call ITW_CLASH_HeliAttack_fnc_Log;

    while {true} do {
        _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
        if (_reason isNotEqualTo "") exitWith {};
        // Re-read the rack each position: out of everything that can hit
        // anything is HAL's pylon rule, read from the rack.
        ([_flight,ITW_CLASH_HeliAttackStep] call ITW_CLASH_Rack_fnc_Profile) params ["","_types"];
        private _usableTypes = (values _types) select {(_x#0) > 0};
        if (_usableTypes isEqualTo []) exitWith {_reason = "winchester"};
        private _pick = [_side,_ordered2,_target,_types] call ITW_CLASH_HeliAttack_fnc_PickCentre;
        private _centre = if (_pick isEqualTo []) then {+_ordered2} else {_pick#0};
        _source = if (_pick isEqualTo []) then {"hal-point"} else {_pick#2};
        private _farthest = selectMax (_usableTypes apply {_x#3});
        [_group,_hq,_centre,_farthest] call ITW_CLASH_HeliAttack_fnc_Brief;
        private _found = [_group,_types,_centre,_target] call ITW_CLASH_HeliAttack_fnc_Detect;
        private _heli = vehicle leader _group;

        if (_found isEqualTo []) then {
            _looks = _looks + 1;
            if (_looks > ITW_CLASH_HeliAttackClearLaps) exitWith {
                _reason = if (_hadTarget) then {"clear"} else {"nothing-to-hit"};
            };
            // Look from as far out as the rack points from, nose on the centre.
            private _height = [_farthest] call ITW_CLASH_HeliAttack_fnc_Height;
            [_group,_flight,_height] call ITW_CLASH_HeliAttack_fnc_Arm;
            private _base = _centre getDir _heli;
            if (_moved) then {_base = _base + (_zig * ([_farthest] call ITW_CLASH_HeliAttack_fnc_HopStep)); _zig = -_zig};
            ([_centre,_farthest,_base,_height,[]] call ITW_CLASH_HeliAttack_fnc_FiringPosition) params ["_pos","_bearing","_los"];
            _reason = [_ctx,_pos] call ITW_CLASH_HeliAttack_fnc_MoveTo;
            if (_reason isNotEqualTo "") exitWith {};
            _moved = true;
            {
                if (!isNull (driver _x)) then {(driver _x) doWatch [_centre#0,_centre#1,0]};
            } forEach (_flight select {alive _x});
            private _lookStart = time;
            private _seen = false;
            waitUntil {
                sleep ITW_CLASH_HeliAttackPoll;
                _reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;
                if (_reason isNotEqualTo "") exitWith {true};
                _seen = ([_group,_types,_centre,_target] call ITW_CLASH_HeliAttack_fnc_Detect) isNotEqualTo [];
                _seen || {(time - _lookStart) >= ITW_CLASH_HeliAttackPointLookWait}
            };
            [_flight] call ITW_CLASH_HeliAttack_fnc_Unwatch;
            ["look",[
                _id,_looks,_source,(_centre apply {round _x}) select [0,2],
                round _farthest,round _bearing,_los,_seen,round (time - _lookStart)
            ]] call ITW_CLASH_HeliAttack_fnc_Log;
            if (_seen) then {_looks = 0};
        } else {
            _looks = 0;
            _hadTarget = true;
            (_found#0) params ["_primary","_class","_primaryPos"];
            _type = _class;
            private _standoff = (_types getOrDefault [_class,[0,-1,"",_farthest]])#3;
            private _height = [_standoff] call ITW_CLASH_HeliAttack_fnc_Height;
            [_group,_flight,_height] call ITW_CLASH_HeliAttack_fnc_Arm;
            // Get far: from the side it is on; after the first, a hop to the side.
            private _base = _primaryPos getDir _heli;
            if (_moved) then {_base = _base + (_zig * ([_standoff] call ITW_CLASH_HeliAttack_fnc_HopStep)); _zig = -_zig};
            private _others = (_found apply {_x#2}) select [1,count _found];
            ([_primaryPos,_standoff,_base,_height,_others] call ITW_CLASH_HeliAttack_fnc_FiringPosition) params ["_pos","_bearing","_los","_near"];
            private _positionStart = time;
            _reason = [_ctx,_pos] call ITW_CLASH_HeliAttack_fnc_MoveTo;
            if (_reason isNotEqualTo "") exitWith {};
            _moved = true;
            _positions = _positions + 1;
            private _arrived = round ((vehicle leader _group) distance2D _primaryPos);

            // Point at, up to three times: the best first, then what else it
            // knows of from here, the ones not pointed at yet first.
            private _aims = [];
            private _aimed = [];
            private _leave = "aims-done";
            for "_i" from 1 to ITW_CLASH_HeliAttackPointAims do {
                private _now = [_group,_types,_centre,_target] call ITW_CLASH_HeliAttack_fnc_Detect;
                if (_now isEqualTo []) exitWith {_leave = "nothing-left"};
                private _next = _now findIf {!((_x#0) in _aimed)};
                if (_next < 0) then {_next = 0};
                (_now#_next) params ["_tgt","_tgtClass"];
                _aimed pushBackUnique _tgt;
                private _result = [_ctx,_tgt,_tgtClass] call ITW_CLASH_HeliAttack_fnc_Aim;
                _aims pushBack _result;
                private _why = _result#5;
                if (_why in ITW_CLASH_HeliAttackForeignStops || {_why in ["rtb-condition","time"]}) exitWith {
                    _reason = _why;
                    _leave = _why;
                };
                if (_why isEqualTo "threat") exitWith {_leave = "threat"};
            };
            [_flight] call ITW_CLASH_HeliAttack_fnc_Unwatch;
            // The position as flown: what it pointed at, how long the nose
            // took to come on (-1 never), whether the assist turned it, what
            // the crew fired, and why it left.
            ["engage",[
                _id,_positions,_class,_source,round _standoff,_arrived,round _bearing,_los,_near,
                _aims,_leave,round (time - _positionStart),
                [_flight] call ITW_CLASH_HeliAttack_fnc_TakeShots
            ]] call ITW_CLASH_HeliAttack_fnc_Log;
        };
        if (_reason isNotEqualTo "") exitWith {};
    };
    _ctx set ["passes",_positions];
    _ctx set ["source",_source];
    _ctx set ["type",_type];
    _reason
};

/*
    The sortie. Returns [alive, reason]; alive false when the flight or its
    group is gone or no longer ours (ITW_CLASH_HeliAttackForeignStops), as
    HAL's own RYD_Wait reports a lost, MIA or broken group.
*/
ITW_CLASH_HeliAttack_fnc_Fly = {
    params ["_group","_hq","_target","_ordered","_flight"];
    private _ctx = createHashMapFromArray [
        ["group",_group],["hq",_hq],["target",_target],
        ["ordered",[_ordered#0,_ordered#1,0]],["flight",_flight],
        ["started",time],["side",side _group],
        ["id",[_group] call ITW_CLASH_HeliAttack_fnc_GroupId],
        ["halType",[_target] call ITW_CLASH_HeliAttack_fnc_TypeOf],
        ["passes",0],["source",""],["type",""]
    ];
    private _id = _ctx get "id";

    ([_flight,ITW_CLASH_HeliAttackStep] call ITW_CLASH_Rack_fnc_Profile) params ["_entries","_types"];
    if (((values _types) findIf {(_x#0) > 0}) < 0) exitWith {
        ["start",[_id,typeOf (_flight#0),"rack-empty",_ctx get "halType"]] call ITW_CLASH_HeliAttack_fnc_Log;
        [true,"rack-empty"]
    };
    // A gunner anywhere on the rack: the ring. Only the airframe aims: point at.
    private _mode = if (((values _types) findIf {((_x#0) > 0) && {(_x#2) isEqualTo "ORBIT"}}) >= 0) then {"ORBIT"} else {"POINT"};
    _ctx set ["mode",_mode];
    _ctx set ["types",_types];

    private _handlers = _flight apply {[_x,[_x,_group] call ITW_CLASH_HeliAttack_fnc_WatchShots,[_x] call ITW_CLASH_HeliAttack_fnc_WatchThreats]};
    [_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;
    // Arm turns attack off; a sortie ending on its own terms puts it back.
    private _attackWas = attackEnabled _group;

    private _reason = if (_mode isEqualTo "ORBIT") then {
        [_ctx] call ITW_CLASH_HeliAttack_fnc_FlyOrbit
    } else {
        [_ctx] call ITW_CLASH_HeliAttack_fnc_FlyPoint
    };

    // Hand the flight back the way HAL left it: nothing of ours pending.
    {
        _x params ["_veh","_fired","_threats"];
        if (!isNull _veh) then {
            _veh removeEventHandler ["Fired",_fired];
            _veh removeEventHandler ["Hit",_threats#0];
            _veh removeEventHandler ["IncomingMissile",_threats#1];
            [_veh] call ITW_CLASH_HeliAttack_fnc_YawRelease;
            _veh limitSpeed 1e10;
        };
    } forEach _handlers;
    [_flight] call ITW_CLASH_HeliAttack_fnc_Unwatch;
    if (!isNull _group) then {
        isNil {
            // A sortie ending on its own terms can still have been taken
            // since the last poll; the late reason wins.
            if !(_reason in ITW_CLASH_HeliAttackForeignStops) then {
                private _late = [_group,_flight,_ctx get "started"] call ITW_CLASH_HeliAttack_fnc_Stop;
                if (_late in ITW_CLASH_HeliAttackForeignStops) then {_reason = _late};
            };
            private _lead = leader _group;
            if (_reason in ITW_CLASH_HeliAttackForeignStops) then {
                // Someone else's orders may already be on the group: leave its
                // waypoints and attack setting alone; cancel only our doMove.
                if (!isNull _lead) then {_lead doFollow _lead};
            } else {
                [_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;
                if (!isNull _lead) then {{_x doFollow _lead} forEach units _group};
                _group enableAttack _attackWas;
            };
        };
    };
    private _alive = !(_reason in ITW_CLASH_HeliAttackForeignStops);
    ["end",[
        _id,_reason,_ctx get "passes",round (time - (_ctx get "started")),
        _ctx get "source",_ctx get "type",
        [_flight] call ITW_CLASH_HeliAttack_fnc_TakeShots
    ]] call ITW_CLASH_HeliAttack_fnc_Log;
    [_alive,_reason]
};

ITW_CLASH_HeliAttackReady = true;
diag_log format [
    "CLASH BOOT | heli-attack-ready | version=%1 retarget=%2 maxUncertainty=%3 step=%4 clearPasses=%5 maxTime=%6 height=%7-%8 modes=ORBIT,POINT pointAims=%9 align=%10 assistAfter=%11 hold=%12 hop=%13 hopSpeed=%14 yawGain=%15 yawRate=%16 yawSign=%17 combatMode=YELLOW attack=false noSAD=true crewFires=true halOwnsDecision=true reportedCentres=true revealsKnownOnly=true yieldsToOwners=true",
    ITW_CLASH_HeliAttackVersion,
    ITW_CLASH_HeliAttackRetargetRadius,
    ITW_CLASH_HeliAttackMaxUncertainty,
    ITW_CLASH_HeliAttackStep,
    ITW_CLASH_HeliAttackClearLaps,
    ITW_CLASH_HeliAttackMaxTime,
    ITW_CLASH_HeliAttackHeightMin,
    ITW_CLASH_HeliAttackHeightMax,
    ITW_CLASH_HeliAttackPointAims,
    ITW_CLASH_HeliAttackPointAlign,
    ITW_CLASH_HeliAttackPointAssistAfter,
    ITW_CLASH_HeliAttackPointHold,
    ITW_CLASH_HeliAttackPointHop,
    ITW_CLASH_HeliAttackPointHopSpeed,
    ITW_CLASH_HeliAttackYawGain,
    ITW_CLASH_HeliAttackYawRate,
    ITW_CLASH_HeliAttackYawSign
];
true
