#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsUAVStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-uav-core-missing | recon UAV not started";
    false
};

ITW_CLASH_SupportsUAVStarted = true;
ITW_CLASH_SupportsUAVVersion = 4;
ITW_CLASH_SupportsUAVReady = false;

/*
    Commander supports: the recon UAV.

    One per side at a time: it holds the RECON lane, never the COMMIT lane, so
    it never stands between a commander and a strike. It flies unarmed from
    the rear to wherever the core says the commander should be looking, and
    circles there. The core rewrites that point every assessment, so the UAV
    follows the commander's attention without a new roll.

    While it flies it is a sensor like any squad, and no more:
      - its crew is a registered sensor group, so its own knowledge reaches
        the knowledge layer the same way a squad's does;
      - what its sensors and crew have seen recently is revealed to its
        commander's HQ group, which is how a sighting reaches HAL (HAL counts
        what its HQ group knows, HAC_fnc2.sqf:271); the knowledge layer never
        reads the HQ group, so nothing is counted twice;
      - the place it circles is stamped as looked at, which is what lets an
        empty objective read as RECENTLY_CLEARED instead of UNOBSERVED, and
        what the air picture accepts as eyes on a destination.

    It ends after its loiter, or when it is shot down. One that never gets on
    station and comes home is refunded; one that is lost is spent and blocks
    the next launch for a while (the core's relaunch delay): shooting it down
    costs the other side its eyes, not only an aircraft.

    Every number below is a placeholder for calibration.
*/

/*
    Loiter height above the ground. v1 flew every UAV at 500 m, inside SPAA
    reach: on 2026-10-16 a Greyhawk died 5 s after reaching its station on
    each side, over objectives covered by Cheetahs. v2 flies fixed-wing UAVs
    at 2000 m, set on the spawn, the flight height and the loiter waypoint.
    The sweep's 3 km is measured over the ground, and the far edge of the
    look is about 2.6 km slant from the loiter ring; whether the airframe's
    own sensors see that far is the airframe's. A rotary one, used only when the faction has no
    fixed-wing UAV, keeps 500 m: a quadcopter is built for low and close.

    v3 (2026-10-17): 2000 m was not enough everywhere. Four of A's five UAVs
    died 5 to 10 s after reaching the same station, with no killer recorded,
    so the air picture never closed it. A UAV lost within a minute of arriving
    now marks a killbox in the core (ITW_CLASH_Supports_fnc_MarkKillbox), and
    no UAV is sent or retasked there for a while.

    v4 (second 2026-10-17 run): the engine's sensors and the AI crew do not
    see down from a loiter ring. Across all 12 sorties at 2000 m the most a
    UAV ever had at once was 2 contacts, and one that loitered the full 15
    minutes over a contested objective had none. On a 700 m ring at 2000 m
    the objective sits 70 degrees below the horizon. So (Hark: "why don't we
    just reveal all targets below the UAV that aren't inside?"):
      - The footprint: every enemy man, vehicle and static within Footprint
        metres of the point under the UAV, unless something covers it from
        above (fnc_Covered: a building's roof by default; any overhead
        geometry, canopy included, with CoverAny) or the ground hides it
        from the UAV. That is the camera's look, which the engine does not
        model from up here.
      - What it finds is revealed to the commander's HQ group as before (so
        HAL, and HAL's map markers, have it) and handed to the knowledge
        layer as a UAV report: the position where the camera saw it, now,
        with ReportError metres of error, ageing from then like any other
        report (ITW_CLASH_KnowledgeUAVSightings). It is a measurement, read
        once at the look, as a strike jet's own sensor track is.
      - The camera is pointed at the station every poll (lockCameraTo), so
        the turret's own sensors and crew look at the ground too, unless a
        player is connected to the UAV.
*/
ITW_CLASH_SupportsUAVHeight = missionNamespace getVariable ["ITW_CLASH_SupportsUAVHeight",2000];
ITW_CLASH_SupportsUAVHeightRotary = missionNamespace getVariable ["ITW_CLASH_SupportsUAVHeightRotary",500];
ITW_CLASH_SupportsUAVSpawnSpeed = missionNamespace getVariable ["ITW_CLASH_SupportsUAVSpawnSpeed",55];
ITW_CLASH_SupportsUAVLoiterRadius = missionNamespace getVariable ["ITW_CLASH_SupportsUAVLoiterRadius",700];
// Time on task, counted from first arrival.
ITW_CLASH_SupportsUAVLoiter = missionNamespace getVariable ["ITW_CLASH_SupportsUAVLoiter",900];
ITW_CLASH_SupportsUAVOnStation = missionNamespace getVariable ["ITW_CLASH_SupportsUAVOnStation",1500];
// The footprint a look stamps around the station.
ITW_CLASH_SupportsUAVLookRadius = missionNamespace getVariable ["ITW_CLASH_SupportsUAVLookRadius",1000];
// A new task closer than this to the current station is not worth a turn.
ITW_CLASH_SupportsUAVRetask = missionNamespace getVariable ["ITW_CLASH_SupportsUAVRetask",300];
ITW_CLASH_SupportsUAVPoll = missionNamespace getVariable ["ITW_CLASH_SupportsUAVPoll",5];
ITW_CLASH_SupportsUAVTransitTimeout = missionNamespace getVariable ["ITW_CLASH_SupportsUAVTransitTimeout",600];
// HAL's own known-enemy floor is 0.05; this is comfortably above it.
ITW_CLASH_SupportsUAVRevealLevel = missionNamespace getVariable ["ITW_CLASH_SupportsUAVRevealLevel",1.5];
// Only what was seen this recently is passed on.
ITW_CLASH_SupportsUAVRevealAge = missionNamespace getVariable ["ITW_CLASH_SupportsUAVRevealAge",30];
ITW_CLASH_SupportsUAVSensorRange = missionNamespace getVariable ["ITW_CLASH_SupportsUAVSensorRange",3000];
/*
    v4. The footprint: how far from the point under the UAV it sees (the
    station's centre stays inside it all the way round a 700 m ring); how
    high the cover ray goes; whether anything overhead covers (true) or only
    a building (false, Hark's "aren't inside"); the error a UAV report
    carries; the most it reveals in one poll.
*/
ITW_CLASH_SupportsUAVFootprint = missionNamespace getVariable ["ITW_CLASH_SupportsUAVFootprint",1200];
ITW_CLASH_SupportsUAVCoverRay = missionNamespace getVariable ["ITW_CLASH_SupportsUAVCoverRay",40];
ITW_CLASH_SupportsUAVCoverAny = missionNamespace getVariable ["ITW_CLASH_SupportsUAVCoverAny",false];
ITW_CLASH_SupportsUAVReportError = missionNamespace getVariable ["ITW_CLASH_SupportsUAVReportError",10];
ITW_CLASH_SupportsUAVFootprintCap = missionNamespace getVariable ["ITW_CLASH_SupportsUAVFootprintCap",80];
// v4. Point the camera at the station every poll.
ITW_CLASH_SupportsUAVCameraLock = missionNamespace getVariable ["ITW_CLASH_SupportsUAVCameraLock",true];

ITW_CLASH_SupportsUAV_fnc_Log = {
    params ["_event",["_payload",[]]];
    ["uav-" + _event,_payload] call ITW_CLASH_Supports_fnc_Log;
};

// Every pylon emptied and every magazine but countermeasures removed: it
// looks, it does not shoot, and it can never read as armed to anyone.
ITW_CLASH_SupportsUAV_fnc_Disarm = {
    params ["_veh"];
    if (isNull _veh) exitWith {0};
    private _removed = 0;
    {
        if (_x isNotEqualTo "") then {
            _veh setPylonLoadout [_forEachIndex + 1,"",true];
            _removed = _removed + 1;
        };
    } forEach (getPylonMagazines _veh);
    private _seen = [];
    {
        _x params ["_magazine","_turret"];
        if ([_magazine,_turret] in _seen) then {continue};
        _seen pushBack [_magazine,_turret];
        private _ammo = getText (configFile >> "CfgMagazines" >> _magazine >> "ammo");
        private _simulation = toLowerANSI getText (configFile >> "CfgAmmo" >> _ammo >> "simulation");
        if (_simulation isNotEqualTo "shotcm") then {
            _veh removeMagazinesTurret [_magazine,_turret];
            _removed = _removed + 1;
        };
    } forEach (magazinesAllTurrets _veh);
    _removed
};

// One loiter waypoint over the station, replacing whatever was there.
ITW_CLASH_SupportsUAV_fnc_Station = {
    params ["_group","_position",["_height",ITW_CLASH_SupportsUAVHeight]];
    {deleteWaypoint _x} forEachReversed (waypoints _group);
    private _wp = _group addWaypoint [_position,0];
    _wp setWaypointType "LOITER";
    _wp setWaypointLoiterType "CIRCLE_L";
    _wp setWaypointLoiterRadius ITW_CLASH_SupportsUAVLoiterRadius;
    _wp setWaypointLoiterAltitude _height;
    _wp setWaypointSpeed "NORMAL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _group setCurrentWaypoint _wp;
    _wp
};

/*
    v4. Is something over this man or vehicle that a camera above cannot see
    through: a straight ray up from its aim point, CoverRay metres. Only a
    building counts unless CoverAny, when anything overhead does (canopy,
    nets, a bridge).
*/
ITW_CLASH_SupportsUAV_fnc_Covered = {
    params ["_object"];
    if (isNull _object) exitWith {true};
    private _from = aimPos _object;
    private _to = _from vectorAdd [0,0,ITW_CLASH_SupportsUAVCoverRay];
    private _hits = lineIntersectsSurfaces [_from,_to,_object,vehicle _object,true,3,"GEOM","NONE"];
    if (ITW_CLASH_SupportsUAVCoverAny) exitWith {_hits isNotEqualTo []};
    (_hits findIf {
        private _thing = if (isNull (_x#3)) then {_x#2} else {_x#3};
        !isNull _thing && {_thing isKindOf "Building"}
    }) >= 0
};

/*
    v4. The footprint: the enemy's men on foot, vehicles and statics with
    anyone alive in them, within Footprint metres of the point under the
    UAV, that nothing covers and no ridge hides from the UAV itself.
    Returns [found, covered or hidden count].
*/
ITW_CLASH_SupportsUAV_fnc_Footprint = {
    params ["_veh","_side"];
    if (isNull _veh || {!alive _veh}) exitWith {[[],0]};
    private _under = getPosATL _veh;
    _under set [2,0];
    private _eye = getPosASL _veh;
    private _found = [];
    private _covered = 0;
    {
        private _object = _x;
        if (!alive _object) then {continue};
        private _crew = if (_object isKindOf "CAManBase") then {[_object]} else {(crew _object) select {alive _x}};
        if (_crew isEqualTo []) then {continue};
        if !([_side,side group (_crew#0)] call BIS_fnc_sideIsEnemy) then {continue};
        if (terrainIntersectASL [_eye,(aimPos _object) vectorAdd [0,0,1]] || {[_object] call ITW_CLASH_SupportsUAV_fnc_Covered}) then {
            _covered = _covered + 1;
            continue
        };
        _found pushBack _object;
        if ((count _found) >= ITW_CLASH_SupportsUAVFootprintCap) then {break};
    } forEach (_under nearEntities [["CAManBase","LandVehicle","StaticWeapon","Ship"],ITW_CLASH_SupportsUAVFootprint]);
    [_found,_covered]
};

/*
    v4. A UAV report to the knowledge layer: where the camera saw it, now,
    with ReportError. The layer weighs it against every other report on its
    next update (ITW_CLASH_Knowledge.sqf v6) and it ages like any of them.
*/
ITW_CLASH_SupportsUAV_fnc_Report = {
    params ["_side","_objects","_by"];
    if (_objects isEqualTo [] || {isNil "ITW_CLASH_KnowledgeUAVSightings"} || {isNil "ITW_CLASH_Knowledge_fnc_ContactKey"}) exitWith {0};
    private _sideKey = [_side] call ITW_CLASH_Knowledge_fnc_SideKey;
    private _store = ITW_CLASH_KnowledgeUAVSightings getOrDefault [_sideKey,createHashMap,true];
    private _now = time;
    {
        private _position = getPosATL _x;
        _store set [[_x] call ITW_CLASH_Knowledge_fnc_ContactKey,[
            _x,[_position#0,_position#1,0],_now,ITW_CLASH_SupportsUAVReportError,_by
        ]];
    } forEach _objects;
    count _objects
};

/*
    v4. The camera on the station, so the turret's own sensors and its crew
    look at the ground. Left alone while a player is connected to the UAV.
*/
ITW_CLASH_SupportsUAV_fnc_PointCamera = {
    params ["_veh","_station"];
    if (!ITW_CLASH_SupportsUAVCameraLock || {isNull _veh} || {!alive _veh} || {_station isEqualTo []}) exitWith {false};
    if (((UAVControl _veh) findIf {_x isEqualType objNull && {!isNull _x} && {isPlayer _x}}) >= 0) exitWith {false};
    private _turret = (allTurrets [_veh,false]) param [0,[]];
    if (_turret isEqualTo []) exitWith {false};
    _veh lockCameraTo [[_station#0,_station#1,(getTerrainHeightASL [_station#0,_station#1]) + 2],_turret];
    true
};

/*
    What the UAV has seen, passed to its commander: enemy ground contacts on
    its own sensors, in its crew's recent knowledge within its sensor range,
    and (v4) in its footprint. All of it is revealed to the HQ group; the
    footprint is also reported to the knowledge layer, which reads the crew
    for itself (a registered sensor group). Returns [all, footprint, covered].
*/
ITW_CLASH_SupportsUAV_fnc_Sweep = {
    params ["_veh","_hq",["_side",sideUnknown],["_by",""]];
    if (isNull _veh || {!alive _veh}) exitWith {[0,0,0]};
    private _seen = [];
    {
        _x params [["_object",objNull],"",["_relationship",""]];
        if (!isNull _object && {_relationship isEqualTo "enemy"}) then {_seen pushBackUnique _object};
    } forEach (getSensorTargets _veh);
    private _crew = driver _veh;
    if (!isNull _crew && {alive _crew}) then {
        {_seen pushBackUnique _x} forEach (_crew targets [
            true,ITW_CLASH_SupportsUAVSensorRange,[],ITW_CLASH_SupportsUAVRevealAge
        ]);
    };
    private _ground = _seen select {
        alive _x
        && {!(_x isKindOf "Air")}
        && {(_x distance2D _veh) <= ITW_CLASH_SupportsUAVSensorRange}
    };
    ([_veh,_side] call ITW_CLASH_SupportsUAV_fnc_Footprint) params ["_footprint","_covered"];
    {_ground pushBackUnique _x} forEach _footprint;
    if (!isNull _hq) then {
        {_hq reveal [_x,ITW_CLASH_SupportsUAVRevealLevel]} forEach _ground;
    };
    [_side,_footprint,_by] call ITW_CLASH_SupportsUAV_fnc_Report;
    [count _ground,count _footprint,_covered]
};

ITW_CLASH_SupportsUAV_fnc_Run = {
    params ["_support"];
    private _side = _support get "side";
    private _hq = _support get "hq";
    private _id = _support get "id";
    private _sign = _support get "sign";
    private _sideKey = [_side] call ITW_CLASH_Supports_fnc_SideKey;
    private _class = _support get "class";
    if (_class isEqualTo "") then {
        _class = ([_side,"UAV"] call ITW_CLASH_Supports_fnc_PickClass) param [0,""];
    };
    if (_class isEqualTo "") exitWith {["REVOKED","NO_AIRCRAFT"]};

    private _station = +(_support get "aim");
    private _spawn = _support get "spawn";
    if (_station isEqualTo [] || {_spawn isEqualTo []}) exitWith {["REVOKED","NO_ORIGIN"]};
    private _heading = _spawn getDir _station;
    private _height = if (_class isKindOf "Plane") then {ITW_CLASH_SupportsUAVHeight} else {ITW_CLASH_SupportsUAVHeightRotary};
    private _start = [_spawn#0,_spawn#1,_height];

    ([_support,_class,_start,_heading,ITW_CLASH_SupportsUAVSpawnSpeed] call
        ITW_CLASH_Supports_fnc_SpawnAircraft) params ["_veh","_group"];
    if (isNull _veh) exitWith {["REVOKED","SPAWN_FAILED"]};
    private _disarmed = [_veh] call ITW_CLASH_SupportsUAV_fnc_Disarm;
    _veh flyInHeight _height;
    [_group,_station,_height] call ITW_CLASH_SupportsUAV_fnc_Station;
    ["launched",[
        _id,_sign,_class,_station apply {round _x},_support get "objective",
        round (_spawn distance2D _station),_disarmed,_height
    ]] call ITW_CLASH_SupportsUAV_fnc_Log;

    private _arrivedAt = -1;
    private _transitUntil = time + ITW_CLASH_SupportsUAVTransitTimeout;
    private _peak = 0;
    // v4: the most the footprint had at once, and the most it found covered.
    private _footPeak = 0;
    private _coverPeak = 0;
    private _reported = 0;
    private _looks = 0;
    private _retasks = 0;
    private _result = [];
    while {_result isEqualTo []} do {
        sleep ITW_CLASH_SupportsUAVPoll;
        if (!alive _veh || {!canMove _veh}) exitWith {
            _result = if (_arrivedAt < 0) then {["LOST","lost-in-transit"]} else {
                ["LOST",format ["lost-on-station-%1s",round (time - _arrivedAt)]]
            };
        };

        // Follow the commander's attention; the core rewrites it every assessment.
        (ITW_CLASH_SupportsUAVTasks getOrDefault [_sideKey,[]]) params [
            ["_taskPos",[]],["_taskObjective",-1],["_taskWhy",""]
        ];
        if (_taskPos isNotEqualTo [] && {(_taskPos distance2D _station) > ITW_CLASH_SupportsUAVRetask}) then {
            ["retasked",[
                _id,_sign,_taskObjective,_taskWhy,round (_taskPos distance2D _station)
            ]] call ITW_CLASH_SupportsUAV_fnc_Log;
            _station = +_taskPos;
            [_group,_station,_height] call ITW_CLASH_SupportsUAV_fnc_Station;
            _retasks = _retasks + 1;
        };

        // v4: the camera on the station, then everything it and the crew have.
        [_veh,_station] call ITW_CLASH_SupportsUAV_fnc_PointCamera;
        ([_veh,_hq,_side,_id] call ITW_CLASH_SupportsUAV_fnc_Sweep) params ["_all","_foot","_cover"];
        _peak = _peak max _all;
        _footPeak = _footPeak max _foot;
        _coverPeak = _coverPeak max _cover;
        _reported = _reported + _foot;

        if ((_veh distance2D _station) <= ITW_CLASH_SupportsUAVOnStation) then {
            if (_arrivedAt < 0) then {
                _arrivedAt = time;
                ["on-station",[
                    _id,_sign,_station apply {round _x},
                    round (time - (_support get "reservedAt"))
                ]] call ITW_CLASH_SupportsUAV_fnc_Log;
            };
            [_side,_station,ITW_CLASH_SupportsUAVLookRadius,"uav"] call ITW_CLASH_Knowledge_fnc_StampLook;
            _looks = _looks + 1;
        };
        if (_arrivedAt >= 0 && {(time - _arrivedAt) >= ITW_CLASH_SupportsUAVLoiter}) exitWith {
            _result = ["DONE","loiter-complete"];
        };
        if (_arrivedAt < 0 && {time > _transitUntil}) exitWith {
            _result = ["BREAKOFF","never-on-station"];
        };
    };

    ["ended",[
        _id,_sign,_result#0,_result#1,
        if (_arrivedAt < 0) then {0} else {round (time - _arrivedAt)},
        _looks,_peak,_retasks,_footPeak,_coverPeak,_reported
    ]] call ITW_CLASH_SupportsUAV_fnc_Log;
    // v5: dead within a minute of arriving: where it died is a killbox.
    if (
        (_result#0) isEqualTo "LOST"
        && {_arrivedAt >= 0}
        && {(time - _arrivedAt) <= ITW_CLASH_SupportsUAVKillboxSeconds}
        && {!isNull _veh}
        && {!isNil "ITW_CLASH_Supports_fnc_MarkKillbox"}
    ) then {
        [_side,getPosATL _veh] call ITW_CLASH_Supports_fnc_MarkKillbox;
    };
    // Home the way it came; a wreck is left where it fell.
    [_veh,_group,getPosATL _veh,_veh getDir _spawn] spawn ITW_CLASH_Supports_fnc_Egress;
    _result
};

ITW_CLASH_SupportsUAVReady = true;
diag_log format [
    "CLASH BOOT | supports-uav-ready | version=%1 height=%2/rotary%10 loiter=%3s radius=%4 onStation=%5 look=%6 retask=%7 reveal=%8 revealAge=%9s footprint=%11m coverRay=%12m coverAny=%13 reportError=%14m footprintCap=%15 cameraLock=%16 footprintReports=true unarmed=true followsAssessment=true killboxOnQuickLoss=true",
    ITW_CLASH_SupportsUAVVersion,
    ITW_CLASH_SupportsUAVHeight,
    ITW_CLASH_SupportsUAVLoiter,
    ITW_CLASH_SupportsUAVLoiterRadius,
    ITW_CLASH_SupportsUAVOnStation,
    ITW_CLASH_SupportsUAVLookRadius,
    ITW_CLASH_SupportsUAVRetask,
    ITW_CLASH_SupportsUAVRevealLevel,
    ITW_CLASH_SupportsUAVRevealAge,
    ITW_CLASH_SupportsUAVHeightRotary,
    ITW_CLASH_SupportsUAVFootprint,
    ITW_CLASH_SupportsUAVCoverRay,
    ITW_CLASH_SupportsUAVCoverAny,
    ITW_CLASH_SupportsUAVReportError,
    ITW_CLASH_SupportsUAVFootprintCap,
    ITW_CLASH_SupportsUAVCameraLock
];
true
