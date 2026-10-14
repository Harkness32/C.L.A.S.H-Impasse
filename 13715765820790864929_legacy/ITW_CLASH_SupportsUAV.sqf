#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsUAVStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-uav-core-missing | recon UAV not started";
    false
};

ITW_CLASH_SupportsUAVStarted = true;
ITW_CLASH_SupportsUAVVersion = 1;
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

ITW_CLASH_SupportsUAVHeight = missionNamespace getVariable ["ITW_CLASH_SupportsUAVHeight",500];
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
    params ["_group","_position"];
    {deleteWaypoint _x} forEachReversed (waypoints _group);
    private _wp = _group addWaypoint [_position,0];
    _wp setWaypointType "LOITER";
    _wp setWaypointLoiterType "CIRCLE_L";
    _wp setWaypointLoiterRadius ITW_CLASH_SupportsUAVLoiterRadius;
    _wp setWaypointSpeed "NORMAL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _group setCurrentWaypoint _wp;
    _wp
};

/*
    What the UAV has seen, passed to its commander: enemy ground contacts on
    its own sensors and in its crew's recent knowledge, within its sensor
    range. Returns how many.
*/
ITW_CLASH_SupportsUAV_fnc_Sweep = {
    params ["_veh","_hq"];
    if (isNull _veh || {!alive _veh}) exitWith {0};
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
    if (!isNull _hq) then {
        {_hq reveal [_x,ITW_CLASH_SupportsUAVRevealLevel]} forEach _ground;
    };
    count _ground
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
    private _start = [_spawn#0,_spawn#1,ITW_CLASH_SupportsUAVHeight];

    ([_support,_class,_start,_heading,ITW_CLASH_SupportsUAVSpawnSpeed] call
        ITW_CLASH_Supports_fnc_SpawnAircraft) params ["_veh","_group"];
    if (isNull _veh) exitWith {["REVOKED","SPAWN_FAILED"]};
    private _disarmed = [_veh] call ITW_CLASH_SupportsUAV_fnc_Disarm;
    _veh flyInHeight ITW_CLASH_SupportsUAVHeight;
    [_group,_station] call ITW_CLASH_SupportsUAV_fnc_Station;
    ["launched",[
        _id,_sign,_class,_station apply {round _x},_support get "objective",
        round (_spawn distance2D _station),_disarmed
    ]] call ITW_CLASH_SupportsUAV_fnc_Log;

    private _arrivedAt = -1;
    private _transitUntil = time + ITW_CLASH_SupportsUAVTransitTimeout;
    private _peak = 0;
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
            [_group,_station] call ITW_CLASH_SupportsUAV_fnc_Station;
            _retasks = _retasks + 1;
        };

        _peak = _peak max ([_veh,_hq] call ITW_CLASH_SupportsUAV_fnc_Sweep);

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
        _looks,_peak,_retasks
    ]] call ITW_CLASH_SupportsUAV_fnc_Log;
    // Home the way it came; a wreck is left where it fell.
    [_veh,_group,getPosATL _veh,_veh getDir _spawn] spawn ITW_CLASH_Supports_fnc_Egress;
    _result
};

ITW_CLASH_SupportsUAVReady = true;
diag_log format [
    "CLASH BOOT | supports-uav-ready | version=%1 height=%2 loiter=%3s radius=%4 onStation=%5 look=%6 retask=%7 reveal=%8 revealAge=%9s unarmed=true followsAssessment=true",
    ITW_CLASH_SupportsUAVVersion,
    ITW_CLASH_SupportsUAVHeight,
    ITW_CLASH_SupportsUAVLoiter,
    ITW_CLASH_SupportsUAVLoiterRadius,
    ITW_CLASH_SupportsUAVOnStation,
    ITW_CLASH_SupportsUAVLookRadius,
    ITW_CLASH_SupportsUAVRetask,
    ITW_CLASH_SupportsUAVRevealLevel,
    ITW_CLASH_SupportsUAVRevealAge
];
true
