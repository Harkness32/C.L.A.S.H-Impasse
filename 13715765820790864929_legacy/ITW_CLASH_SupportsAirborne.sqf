#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsAirborneStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-airborne-core-missing | airborne insertions not started";
    false
};

ITW_CLASH_SupportsAirborneStarted = true;
ITW_CLASH_SupportsAirborneVersion = 2;
ITW_CLASH_SupportsAirborneReady = false;

/*
    Commander supports: the airborne insertion. A helicopter or a transport
    plane with squads, and (v2) a vehicle delivered by its own carrier.

    Each has its own switch in the core. With a switch off nothing on its
    path in this file runs.

    The squads are the faction's own: a living squad's archetype, built with
    Impasse's own unit factory at the aircraft's origin and moved aboard. They
    exist only for this support until they are on the ground. In flight they
    carry the reconstitution transit flag, which every lifecycle owner already
    honours: Impasse's infantry loop, HAL admission and the lifecycle
    reservations all leave a transiting squad alone.

    The aircraft flies one straight line through the drop zone and the jump
    is Impasse's own (ITW_AtkUnloadAirplane, ITW_AtkParachute), timed by the
    paradrop owner's stick estimate so the stick is centred on the zone.

    Once a squad is down it is handed on, once, the way a reconstituted squad
    is: Impasse's own group callback, the general registration path, and one
    native order issued the way HAL's own dispatcher issues it - a capture
    order when the drop was to take the point, a defend order when it was to
    hold it. That order is the only HAL write in the support stack. After it,
    the squad is HAL's like any other, and nothing here touches it again.
    If HAL will not take the squad, Impasse's own engage routine does.

    Money: delivered is spent; lost with the aircraft is spent; a run that
    breaks off with the aircraft alive is refunded, and its squads, which
    never touched the ground, are removed.

    v2 (2026-10-17): the vehicle is no longer the plane drop's add-on built
    out of thin air at release; it is its own support (fnc_RunVehicle),
    carried inside the aircraft that drops it, the Blackfish by default.
    Neither has flown in a game yet: no drop was ever affordable before the
    core's v7, so read the airborne lines of the first runs and the console
    tests (ITW_CLASH_SupportsDebug.sqf) as the first evidence.

    Every number below is a placeholder for calibration.
*/

// Over the drop zone, above ground. The paradrop owner's floor is 45 m.
ITW_CLASH_SupportsAirborneHeliHeight = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneHeliHeight",50];
// A helicopter arrives higher and comes down for the run.
ITW_CLASH_SupportsAirborneHeliSpawnHeight = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneHeliSpawnHeight",150];
ITW_CLASH_SupportsAirbornePlaneHeight = missionNamespace getVariable ["ITW_CLASH_SupportsAirbornePlaneHeight",250];
ITW_CLASH_SupportsAirborneHeliSpeed = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneHeliSpeed",50];
ITW_CLASH_SupportsAirbornePlaneSpeed = missionNamespace getVariable ["ITW_CLASH_SupportsAirbornePlaneSpeed",80];
// Taking a point, the zone is this far short of it on the approach, so the
// stick lands on the edge of the fight rather than in its middle. Holding,
// it is the point itself.
ITW_CLASH_SupportsAirborneDZOffset = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneDZOffset",250];
ITW_CLASH_SupportsAirborneDZSearch = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneDZSearch",150];
// Further off the line than this at release is not a run.
ITW_CLASH_SupportsAirborneCrossLimit = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneCrossLimit",350];
ITW_CLASH_SupportsAirborneRunTimeout = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneRunTimeout",300];
ITW_CLASH_SupportsAirborneFlareRange = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneFlareRange",1200];
// A squad smaller than this is not a squad and is not flown.
ITW_CLASH_SupportsAirborneMinSquad = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneMinSquad",4];
// Bound on waiting for a squad to be on its feet; a 45 m drop lands in 10-22 s.
ITW_CLASH_SupportsAirborneLandWait = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneLandWait",90];
ITW_CLASH_SupportsAirborneSettle = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneSettle",10];
/*
    v2, vehicle delivery: the carrier's height over the zone and its speed
    on the spawn (m/s); the vehicle goes this many seconds of flight short
    of the zone, for the carry under its parachute; how many of the side's
    cars are tried for a fit; how long a falling vehicle is waited for.
*/
ITW_CLASH_SupportsVehicleDropHeight = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropHeight",200];
ITW_CLASH_SupportsVehicleDropSpeed = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropSpeed",70];
ITW_CLASH_SupportsVehicleDropLeadSeconds = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropLeadSeconds",2.5];
ITW_CLASH_SupportsVehicleDropTries = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropTries",4];
ITW_CLASH_SupportsVehicleDropFallWait = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropFallWait",180];

ITW_CLASH_SupportsAirborne_fnc_Log = {
    params ["_event",["_payload",[]]];
    ["airborne-" + _event,_payload] call ITW_CLASH_Supports_fnc_Log;
};

/*
    The drop zone: dry, open ground near the point, short of it on the
    approach when the drop is to take it. [] when there is none.
*/
ITW_CLASH_SupportsAirborne_fnc_DropZone = {
    params ["_support"];
    private _center = +(_support get "aim");
    if (_center isEqualTo []) exitWith {[]};
    private _spawn = _support get "spawn";
    private _point = +_center;
    if ((_support get "reason") isEqualTo "TAKE" && {_spawn isNotEqualTo []} && {ITW_CLASH_SupportsAirborneDZOffset > 0}) then {
        _point = _center getPos [ITW_CLASH_SupportsAirborneDZOffset,_center getDir _spawn];
    };
    private _safe = [
        _point,0,ITW_CLASH_SupportsAirborneDZSearch,4,0,0.4,0,[],[_point,_point]
    ] call BIS_fnc_findSafePos;
    if !(_safe isEqualType [] && {count _safe >= 2}) exitWith {[]};
    _safe = [_safe#0,_safe#1,0];
    if (surfaceIsWater _safe) exitWith {[]};
    _safe
};

// Every unit of every group, gone: squads that never touched the ground.
ITW_CLASH_SupportsAirborne_fnc_DeleteSquads = {
    params ["_squads"];
    {
        private _group = _x;
        if (isNull _group) then {continue};
        {
            if (vehicle _x != _x) then {moveOut _x};
            deleteVehicle _x;
        } forEach (units _group);
        deleteGroup _group;
    } forEach _squads;
    true
};

/*
    The squads, built on the ground at the aircraft's origin with Impasse's
    own unit factory, protected until they are aboard. Stamped from birth:
    the support's id, the transit flag, the archetype they were built from,
    and a lineage that says where they came from.
*/
ITW_CLASH_SupportsAirborne_fnc_CreateSquads = {
    params ["_support"];
    private _side = _support get "side";
    private _template = +(_support get "template");
    private _squadSize = (_support get "squadSize") min (count _template);
    private _origin = _support get "origin";
    if (_squadSize < ITW_CLASH_SupportsAirborneMinSquad || {_origin isEqualTo []}) exitWith {[]};
    private _ground = [_origin#0,_origin#1,0];
    private _squads = [];
    for "_index" from 1 to ((_support get "squads") max 1) do {
        private _group = createGroup [_side,true];
        if (isNull _group) exitWith {};
        _group setVariable ["ITW_CLASH_SupportAsset",_support get "id"];
        _group setVariable ["ITW_CLASH_ReconstitutionTransit",true];
        _group setVariable ["itwInitGrp",true,true];
        {
            [_group,[_x],_ground,false] call ITW_AtkUnitToGroup;
        } forEach (_template select [0,_squadSize]);
        private _members = units _group;
        if (count _members < ITW_CLASH_SupportsAirborneMinSquad) then {
            [[_group]] call ITW_CLASH_SupportsAirborne_fnc_DeleteSquads;
            continue
        };
        _group setVariable ["ITW_CLASH_Archetype",_members apply {toLowerANSI typeOf _x}];
        _group setVariable ["ITW_CLASH_Lineage",format ["support-%1-%2",_support get "id",_index]];
        VAR_SET_OBJ_IDX(_group,_support get "objective");
        _squads pushBack _group;
    };
    _squads
};

// Aboard, every man who fits; a squad left under strength stays behind.
ITW_CLASH_SupportsAirborne_fnc_Board = {
    params ["_squads","_veh"];
    private _aboard = [];
    {
        private _group = _x;
        {
            _x moveInCargo _veh;
            if (vehicle _x == _veh) then {
                _x assignAsCargo _veh;
                ALLOW_DAMAGE(_x,true);
            } else {
                deleteVehicle _x;
            };
        } forEach (units _group);
        if (({alive _x && {vehicle _x == _veh}} count (units _group)) < ITW_CLASH_SupportsAirborneMinSquad) then {
            [[_group]] call ITW_CLASH_SupportsAirborne_fnc_DeleteSquads;
        } else {
            _aboard pushBack _group;
        };
    } forEach _squads;
    _aboard
};

// The object HAL's capture order is written against: Impasse's own flag for
// commander A, C.L.A.S.H.'s private mirror for commander B.
ITW_CLASH_SupportsAirborne_fnc_Target = {
    params ["_side","_objective"];
    if (_objective < 0) exitWith {objNull};
    if (!isNil "ITW_PlayerSide" && {_side isEqualTo ITW_PlayerSide}) exitWith {
        if (isNil "ITW_CLASH_BLUFORObjectiveMirrors") exitWith {objNull};
        ITW_CLASH_BLUFORObjectiveMirrors getOrDefault [str _objective,objNull]
    };
    if (isNil "ITW_Objectives" || {_objective >= count ITW_Objectives}) exitWith {objNull};
    private _entry = ITW_Objectives#_objective;
    if (count _entry <= ITW_OBJ_FLAG) exitWith {objNull};
    private _flag = _entry#ITW_OBJ_FLAG;
    if !(_flag isEqualType objNull) exitWith {objNull};
    _flag
};

/*
    The one native order. Issued exactly as HAL's dispatcher issues it:
      TAKE  HQOrders.sqf:815-832 - Busy set, out of AttackAv, the target's
            Capturing stage and count raised, HAL_GoCapture spawned.
      HOLD  the anchor's own path (CommanderParity) - Break and Defending
            cleared, onto DefSpot, HAL_GoDef spawned at the point.
    Returns "TAKE", "HOLD", or "" when it could not be issued; a registered
    squad without an order is still HAL's, and HAL tasks it on its next pass.
*/
ITW_CLASH_SupportsAirborne_fnc_NativeOrder = {
    params ["_support","_group"];
    private _hq = _support get "hq";
    private _objective = _support get "objective";
    if (isNull _hq || {isNull _group} || {isNil "RYD_Spawn"}) exitWith {""};
    if (_group getVariable ["Busy" + str _group,false]) exitWith {""};

    if ((_support get "reason") isEqualTo "HOLD") exitWith {
        if (isNil "HAL_GoDef") exitWith {""};
        private _center = [_objective] call ITW_CLASH_Supports_fnc_ObjectivePos;
        if (_center isEqualTo []) exitWith {""};
        private _target = [_center,10,60,2,0,0.4,0,[],[_center,_center]] call BIS_fnc_findSafePos;
        if (!(_target isEqualType []) || {count _target < 2} || {surfaceIsWater _target}) then {_target = +_center};
        _group setVariable ["Break",false];
        _group setVariable ["Defending",false];
        private _defSpot = +(_hq getVariable ["RydHQ_DefSpot",[]]);
        _defSpot pushBackUnique _group;
        _hq setVariable ["RydHQ_DefSpot",_defSpot];
        [[_group,_target,0,0,false,_hq getVariable ["RydHQ_Angle",0],_hq],HAL_GoDef] call RYD_Spawn;
        "HOLD"
    };

    if (isNil "HAL_GoCapture") exitWith {""};
    private _trg = [_support get "side",_objective] call ITW_CLASH_SupportsAirborne_fnc_Target;
    if (isNull _trg) exitWith {""};
    _group setVariable ["Busy" + str _group,true];
    _hq setVariable ["RydHQ_AttackAv",(_hq getVariable ["RydHQ_AttackAv",[]]) - [_group]];
    private _key = "Capturing" + str _trg + str _hq;
    private _capturing = _trg getVariable [_key,[0,0]];
    if !(_capturing isEqualType [] && {count _capturing >= 2}) then {_capturing = [0,0]};
    _capturing params ["_stage","_count"];
    _trg setVariable [_key,[(_stage + 1) min 5,_count + count (units _group)]];
    [[_group,_stage,_hq,_trg],HAL_GoCapture] call RYD_Spawn;
    "TAKE"
};

/*
    A squad on the ground, handed on once. Waits until every living man is
    out of the aircraft and his chute, bounded, then lets it settle: HAL's
    canopy guard covers the rest, but an order should start on a squad that
    is standing.
*/
ITW_CLASH_SupportsAirborne_fnc_HandOff = {
    params ["_support","_group",["_how","landed"]];
    scriptName "ITW_CLASH_SupportsAirborne_HandOff";
    private _deadline = time + ITW_CLASH_SupportsAirborneLandWait;
    waitUntil {
        sleep 1;
        isNull _group
        || {((units _group) findIf {alive _x}) < 0}
        || {((units _group) findIf {alive _x && {vehicle _x != _x}}) < 0}
        || {time > _deadline}
    };
    if (isNull _group || {((units _group) findIf {alive _x}) < 0}) exitWith {
        ["handoff-empty",[_support get "id",_support get "sign",_how]] call ITW_CLASH_SupportsAirborne_fnc_Log;
        false
    };
    sleep ITW_CLASH_SupportsAirborneSettle;
    if (isNull _group || {((units _group) findIf {alive _x}) < 0}) exitWith {false};

    _group setVariable ["ITW_CLASH_ReconstitutionTransit",nil];
    _group setVariable ["itwInitGrp",nil,true];
    _group setVariable ["ITW_CLASH_SupportAsset",nil];
    _group setVariable ["ITW_CLASH_SupportDelivered",_support get "id"];
    VAR_SET_OBJ_IDX(_group,_support get "objective");

    // Impasse's own bookkeeping first, as the reconstitution hand-off does.
    if (!isNil "ITW_PlayerSide" && {side _group isEqualTo ITW_PlayerSide}) then {
        if (!isNil "ITW_AllyGroupCallback") then {[_group] call ITW_AllyGroupCallback};
    } else {
        if (!isNil "ITW_EnemyGroupCallback") then {[_group] call ITW_EnemyGroupCallback};
    };

    private _registered = !isNil "ITW_CLASH_DualHAL_fnc_RegisterGroup"
        && {[_group,"support-airborne"] call ITW_CLASH_DualHAL_fnc_RegisterGroup};
    private _order = "";
    if (_registered) then {
        _order = [_support,_group] call ITW_CLASH_SupportsAirborne_fnc_NativeOrder;
    } else {
        if (!isNil "ITW_AtkEngageInfantry") then {[_group,false] spawn ITW_AtkEngageInfantry};
    };
    ["handoff",[
        _support get "id",_support get "sign",[_group] call ITW_CLASH_Knowledge_fnc_GroupId,
        _how,{alive _x} count (units _group),round ((leader _group) distance2D (_support get "aim")),
        if (_registered) then {"hal"} else {"impasse"},
        if (_order isEqualTo "") then {"none"} else {_order}
    ]] call ITW_CLASH_SupportsAirborne_fnc_Log;
    true
};

/*
    v2. A delivered vehicle on the ground, handed on once: down, settled,
    unlocked and damageable again, then its crew goes to HAL. HAL tasks its
    own vehicles, so it gets no order from here.
*/
ITW_CLASH_SupportsAirborne_fnc_VehicleHandOff = {
    params ["_support","_car","_crew",["_how","landed"]];
    scriptName "ITW_CLASH_SupportsAirborne_VehicleHandOff";
    private _deadline = time + ITW_CLASH_SupportsVehicleDropFallWait;
    sleep 3;
    waitUntil {
        sleep 1;
        !alive _car || {isTouchingGround _car} || {((getPos _car)#2) < 2} || {time > _deadline}
    };
    if (!alive _car || {isNull _crew}) exitWith {
        ["vehicle-lost",[_support get "id",_support get "sign",_how]] call ITW_CLASH_SupportsAirborne_fnc_Log;
        false
    };
    // A parachute restores damage a second after touchdown.
    sleep (ITW_CLASH_SupportsAirborneSettle max 3);
    if (!alive _car) exitWith {false};
    _car allowDamage true;
    _car lock 0;
    _crew setVariable ["ITW_CLASH_ReconstitutionTransit",nil];
    _crew setVariable ["itwInitGrp",nil,true];
    _crew setVariable ["ITW_CLASH_SupportAsset",nil];
    _crew setVariable ["ITW_CLASH_SupportDelivered",_support get "id"];
    VAR_SET_OBJ_IDX(_crew,_support get "objective");
    private _registered = !isNil "ITW_CLASH_DualHAL_fnc_RegisterGroup"
        && {[_crew,"support-airborne-vehicle"] call ITW_CLASH_DualHAL_fnc_RegisterGroup};
    if (_registered) then {
        if (!isNil "ITW_CLASH_DualHAL_fnc_MarkVehicleCrew") then {
            [_crew,_car,"support-airborne"] call ITW_CLASH_DualHAL_fnc_MarkVehicleCrew;
        };
        if (!isNil "ITW_CLASH_DualHAL_fnc_TrackAsset") then {
            [_car,[],"support-airborne"] call ITW_CLASH_DualHAL_fnc_TrackAsset;
        };
        _car setVariable ["ITW_CLASH_DualHALManaged",true];
    };
    ["vehicle-handoff",[
        _support get "id",_support get "sign",typeOf _car,
        round (_car distance2D (_support get "aim")),_registered,_how
    ]] call ITW_CLASH_SupportsAirborne_fnc_Log;
    true
};

/*
    v2. The vehicle, inside the carrier. One of the side's own cars at a
    time, in a random order, built crewed by Impasse's own factory at the
    origin and loaded into the carrier in flight (setVehicleCargo); the first
    that fits goes, up to VehicleDropTries, and one that does not fit is
    removed with its crew. Locked and undamageable until it is down, so
    nobody gets out on the way and a hard landing does not wreck it.
    Returns [vehicle, crew group, classes tried].
*/
ITW_CLASH_SupportsAirborne_fnc_LoadVehicle = {
    params ["_support","_carrier","_cars"];
    private _side = _support get "side";
    ([_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes) params [["_crewTypes",[]],["_unitTypes",[]]];
    private _origin = _support get "origin";
    private _ground = [_origin#0,_origin#1,0];
    private _tried = [];
    private _car = objNull;
    {
        if ((count _tried) >= ITW_CLASH_SupportsVehicleDropTries) exitWith {};
        private _carClass = _x;
        _tried pushBack _carClass;
        private _candidate = [[_carClass],_crewTypes,_unitTypes,_side,_ground,-1] call ITW_AtkSpawnVeh;
        if (isNull _candidate) then {continue};
        private _fits = (_carrier canVehicleCargo _candidate) param [0,false];
        if (_fits && {_carrier setVehicleCargo _candidate}) exitWith {_car = _candidate};
        {deleteVehicle _x} forEach (crew _candidate);
        deleteVehicle _candidate;
    } forEach (_cars call BIS_fnc_arrayShuffle);
    if (isNull _car) exitWith {[objNull,grpNull,_tried]};
    private _crew = group (driver _car);
    if (isNull _crew) then {_crew = group ((crew _car) param [0,objNull])};
    _car allowDamage false;
    _car lock 2;
    _car setVariable ["ITW_CLASH_SupportAsset",_support get "id",true];
    if (!isNull _crew) then {
        _crew setVariable ["ITW_CLASH_SupportAsset",_support get "id"];
        _crew setVariable ["ITW_CLASH_ReconstitutionTransit",true];
        _crew setVariable ["itwInitGrp",true,true];
    };
    (_support get "assets") pushBack _car;
    [_car,_crew,_tried]
};

/*
    v2. Vehicle delivery, a support of its own (the core's VEHICLE_DROP). The
    carrier (the Blackfish by default) spawns on the run-in with the vehicle
    already inside it, flies one straight line through the zone at
    VehicleDropHeight, and lets the vehicle go VehicleDropLeadSeconds of
    flight short of the zone (objNull setVehicleCargo). A vehicle unloaded
    in the air gets the engine's own cargo parachute; if a second later
    nothing holds it, Impasse's vehicle parachute does, from where it is
    (ITW_FncVehicleHalo). Down and settled, its crew goes to HAL.

    Money as the drops: delivered or lost is spent, a run that breaks off
    with the carrier alive is refunded and its vehicle, never down, removed.
*/
ITW_CLASH_SupportsAirborne_fnc_RunVehicle = {
    params ["_support"];
    private _side = _support get "side";
    private _id = _support get "id";
    private _sign = _support get "sign";
    if (isNil "ITW_AtkSpawnVeh" || {isNil "ITW_CLASH_Checkbook_fnc_GetCrewTypes"}) exitWith {["REVOKED","NO_EXECUTOR"]};
    private _class = _support get "class";
    if (_class isEqualTo "") then {
        _class = ([_side,"VEHICLE_DROP"] call ITW_CLASH_Supports_fnc_PickClass) param [0,""];
    };
    if (_class isEqualTo "") exitWith {["REVOKED","NO_AIRCRAFT"]};
    private _dz = [_support] call ITW_CLASH_SupportsAirborne_fnc_DropZone;
    if (_dz isEqualTo []) exitWith {["REVOKED","NO_DZ"]};
    private _spawn = _support get "spawn";
    if (_spawn isEqualTo [] || {(_support get "origin") isEqualTo []}) exitWith {["REVOKED","NO_ORIGIN"]};
    private _cars = [_side,"CAR"] call ITW_CLASH_Supports_fnc_Classes;
    if (_cars isEqualTo []) exitWith {["REVOKED","NO_VEHICLE_FIT"]};

    private _heading = _spawn getDir _dz;
    private _height = ITW_CLASH_SupportsVehicleDropHeight;
    ([_support,_class,[_spawn#0,_spawn#1,_height],_heading,ITW_CLASH_SupportsVehicleDropSpeed] call
        ITW_CLASH_Supports_fnc_SpawnAircraft) params ["_veh","_group"];
    if (isNull _veh) exitWith {["REVOKED","SPAWN_FAILED"]};
    [_veh] call ITW_CLASH_Supports_fnc_StripAirToAir;
    ([_support,_veh,_cars] call ITW_CLASH_SupportsAirborne_fnc_LoadVehicle) params ["_car","_crew","_tried"];
    if (isNull _car) exitWith {
        ["vehicle-unfit",[_id,_sign,_class,_tried]] call ITW_CLASH_SupportsAirborne_fnc_Log;
        [_veh,_group] call ITW_CLASH_Supports_fnc_Despawn;
        ["REVOKED","NO_VEHICLE_FIT"]
    };
    ["vehicle-loaded",[
        _id,_sign,_class,typeOf _car,{alive _x} count (crew _car),_dz apply {round _x},
        round (_spawn distance2D _dz),round ((_support get "aim") distance2D _dz),count _tried
    ]] call ITW_CLASH_SupportsAirborne_fnc_Log;

    // One straight line through the zone and on past it.
    _veh flyInHeight _height;
    {deleteWaypoint _x} forEachReversed (waypoints _group);
    private _wp = _group addWaypoint [_dz getPos [1000,_heading],0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 200;

    private _deadline = time + ITW_CLASH_SupportsAirborneRunTimeout;
    private _flared = false;
    private _result = [];
    while {_result isEqualTo []} do {
        sleep 0.1;
        if (!alive _veh || {!canMove _veh} || {isNull driver _veh}) exitWith {_result = ["LOST","aircraft-lost"]};
        if (!alive _car) exitWith {_result = ["LOST","cargo-lost"]};
        if (time > _deadline) exitWith {_result = ["BREAKOFF","never-reached"]};
        ([getPosATL _veh,_dz,_heading] call ITW_CLASH_Supports_fnc_AlongCross) params ["_along","_cross"];
        if (!_flared && {_along <= ITW_CLASH_SupportsAirborneFlareRange}) then {
            _flared = true;
            [_veh,30,1] call ITW_CLASH_Supports_fnc_Flares;
        };
        private _lead = ((speed _veh) / 3.6) * ITW_CLASH_SupportsVehicleDropLeadSeconds;
        if (_along <= _lead) exitWith {
            _result = if (_cross > ITW_CLASH_SupportsAirborneCrossLimit) then {["BREAKOFF","passed-wide"]} else {
                ["RELEASE",format ["along-%1-cross-%2",round _along,round _cross]]
            };
        };
    };

    switch (_result#0) do {
        case "RELEASE": {
            private _unloaded = objNull setVehicleCargo _car;
            if (!_unloaded) exitWith {
                ["vehicle-unload-failed",[_id,_sign,_class,typeOf _car]] call ITW_CLASH_SupportsAirborne_fnc_Log;
                {deleteVehicle _x} forEach (crew _car);
                deleteVehicle _car;
                _result = ["BREAKOFF","unload-failed"];
            };
            sleep 1;
            private _chute = "engine";
            if (alive _car && {isNull (attachedTo _car)} && {((getPos _car)#2) > 20}) then {
                [_car] spawn ITW_FncVehicleHalo;
                _chute = "impasse";
            };
            ["vehicle-released",[
                _id,_sign,_class,typeOf _car,round speed _veh,round ((getPosATL _veh)#2),
                round (_veh distance2D _dz),_chute,_result#1
            ]] call ITW_CLASH_SupportsAirborne_fnc_Log;
            [_support,_car,_crew,"landed"] spawn ITW_CLASH_SupportsAirborne_fnc_VehicleHandOff;
            _result = ["DONE",format ["delivered-%1",typeOf _car]];
        };
        case "LOST": {
            // Whatever lives through the carrier is ours on the ground.
            if (alive _car) then {
                objNull setVehicleCargo _car;
                if (isNull (attachedTo _car) && {((getPos _car)#2) > 20} && {!isNil "ITW_FncVehicleHalo"}) then {[_car] spawn ITW_FncVehicleHalo};
                [_support,_car,_crew,"survived-loss"] spawn ITW_CLASH_SupportsAirborne_fnc_VehicleHandOff;
            };
        };
        default {
            // Never down, never anyone else's.
            if (!isNull _car) then {
                {deleteVehicle _x} forEach (crew _car);
                deleteVehicle _car;
            };
        };
    };
    [_veh,_group,_dz,_heading,4000,300,_support] spawn ITW_CLASH_Supports_fnc_Egress;
    _result
};

ITW_CLASH_SupportsAirborne_fnc_Run = {
    params ["_support"];
    private _side = _support get "side";
    private _flavor = _support get "flavor";
    private _id = _support get "id";
    private _sign = _support get "sign";
    if (isNil "ITW_AtkUnitToGroup" || {isNil "ITW_AtkUnloadAirplane"}) exitWith {["REVOKED","NO_EXECUTOR"]};
    private _class = _support get "class";
    if (_class isEqualTo "") then {
        _class = ([_side,_flavor] call ITW_CLASH_Supports_fnc_PickClass) param [0,""];
    };
    if (_class isEqualTo "") exitWith {["REVOKED","NO_AIRCRAFT"]};

    private _dz = [_support] call ITW_CLASH_SupportsAirborne_fnc_DropZone;
    if (_dz isEqualTo []) exitWith {["REVOKED","NO_DZ"]};
    private _spawn = _support get "spawn";
    if (_spawn isEqualTo []) exitWith {["REVOKED","NO_ORIGIN"]};

    // The squads first, so the aircraft does not fly empty while they are built.
    private _squads = [_support] call ITW_CLASH_SupportsAirborne_fnc_CreateSquads;
    if (_squads isEqualTo []) exitWith {["REVOKED","NO_SQUADS"]};

    private _plane = _flavor isEqualTo "AIRBORNE_PLANE";
    private _heading = _spawn getDir _dz;
    private _height = if (_plane) then {ITW_CLASH_SupportsAirbornePlaneHeight} else {ITW_CLASH_SupportsAirborneHeliHeight};
    private _start = [_spawn#0,_spawn#1,
        if (_plane) then {ITW_CLASH_SupportsAirbornePlaneHeight} else {ITW_CLASH_SupportsAirborneHeliSpawnHeight}
    ];
    private _speed = if (_plane) then {ITW_CLASH_SupportsAirbornePlaneSpeed} else {ITW_CLASH_SupportsAirborneHeliSpeed};

    ([_support,_class,_start,_heading,_speed] call ITW_CLASH_Supports_fnc_SpawnAircraft) params ["_veh","_group"];
    if (isNull _veh) exitWith {
        [_squads] call ITW_CLASH_SupportsAirborne_fnc_DeleteSquads;
        ["REVOKED","SPAWN_FAILED"]
    };
    [_veh] call ITW_CLASH_Supports_fnc_StripAirToAir;
    _squads = [_squads,_veh] call ITW_CLASH_SupportsAirborne_fnc_Board;
    if (_squads isEqualTo []) exitWith {
        [_veh,_group] call ITW_CLASH_Supports_fnc_Despawn;
        ["REVOKED","NO_SQUADS"]
    };
    private _men = 0;
    {_men = _men + ({alive _x} count (units _x))} forEach _squads;
    ["boarded",[
        _id,_sign,_flavor,_class,count _squads,_men,_dz apply {round _x},
        round (_spawn distance2D _dz),round ((_support get "aim") distance2D _dz)
    ]] call ITW_CLASH_SupportsAirborne_fnc_Log;

    // One straight line through the zone and on past it.
    _veh flyInHeight _height;
    if (_plane) then {
        private _floor = (getTerrainHeightASL _dz) + _height;
        _veh flyInHeightASL [_floor,_floor,_floor];
    };
    {deleteWaypoint _x} forEachReversed (waypoints _group);
    private _wp = _group addWaypoint [_dz getPos [1000,_heading],0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 200;

    private _deadline = time + ITW_CLASH_SupportsAirborneRunTimeout;
    private _flared = false;
    private _result = [];
    while {_result isEqualTo []} do {
        sleep 0.1;
        if (!alive _veh || {!canMove _veh} || {isNull driver _veh}) exitWith {_result = ["LOST","aircraft-lost"]};
        if (time > _deadline) exitWith {_result = ["BREAKOFF","never-reached"]};
        ([getPosATL _veh,_dz,_heading] call ITW_CLASH_Supports_fnc_AlongCross) params ["_along","_cross"];
        if (!_flared && {_along <= ITW_CLASH_SupportsAirborneFlareRange}) then {
            _flared = true;
            [_veh,30,1] call ITW_CLASH_Supports_fnc_Flares;
        };
        private _jumpers = 0;
        {_jumpers = _jumpers + ({alive _x && {vehicle _x == _veh}} count (units _x))} forEach _squads;
        private _lead = if (isNil "ITW_CLASH_HALUnload_fnc_StickLead") then {30} else {
            [_veh,_jumpers] call ITW_CLASH_HALUnload_fnc_StickLead
        };
        if (_along <= _lead) exitWith {
            _result = switch (true) do {
                case (_jumpers == 0): {["LOST","cargo-lost"]};
                case (_cross > ITW_CLASH_SupportsAirborneCrossLimit): {["BREAKOFF","passed-wide"]};
                default {["RELEASE",format ["along-%1-cross-%2",round _along,round _cross]]};
            };
        };
    };

    switch (_result#0) do {
        case "RELEASE": {
            // Impasse's own jump: no crew group and no point, so it touches no
            // waypoint and jumps everyone in these squads now.
            [_veh,grpNull,_squads,[]] call ITW_AtkUnloadAirplane;
            {
                if (!isNull _x && {!isNull leader _x}) then {
                    [units _x,leader _x] remoteExec ["doFollow",leader _x];
                };
            } forEach _squads;
            private _jumped = 0;
            {_jumped = _jumped + ({alive _x && {vehicle _x != _veh}} count (units _x))} forEach _squads;
            ["released",[
                _id,_sign,_flavor,count _squads,_jumped,round speed _veh,
                round ((getPosATL _veh)#2),round (_veh distance2D _dz),_result#1
            ]] call ITW_CLASH_SupportsAirborne_fnc_Log;
            {[_support,_x,"landed"] spawn ITW_CLASH_SupportsAirborne_fnc_HandOff} forEach _squads;
            _result = ["DONE",format ["dropped-%1x%2",count _squads,_jumped]];
        };
        case "LOST": {
            // Whoever lives through the aircraft is ours on the ground.
            {[_support,_x,"survived-loss"] spawn ITW_CLASH_SupportsAirborne_fnc_HandOff} forEach _squads;
        };
        default {
            // Never touched the ground, never existed for anyone else.
            [_squads] call ITW_CLASH_SupportsAirborne_fnc_DeleteSquads;
        };
    };
    // On past the zone, a turn on the colder side, and home.
    [_veh,_group,_dz,_heading,4000,300,_support] spawn ITW_CLASH_Supports_fnc_Egress;
    _result
};

ITW_CLASH_SupportsAirborneReady = true;
diag_log format [
    "CLASH BOOT | supports-airborne-ready | version=%1 heli=%2m plane=%3m dzOffset=%4 crossLimit=%5 minSquad=%6 landWait=%7s vehicleDrop=%8 vehicleHeight=%9m vehicleSpeed=%10 vehicleLead=%11s vehicleTries=%12 vehicleCarried=true vehicleOwnSupport=true impasseJump=true oneNativeOrder=true",
    ITW_CLASH_SupportsAirborneVersion,
    ITW_CLASH_SupportsAirborneHeliHeight,
    ITW_CLASH_SupportsAirbornePlaneHeight,
    ITW_CLASH_SupportsAirborneDZOffset,
    ITW_CLASH_SupportsAirborneCrossLimit,
    ITW_CLASH_SupportsAirborneMinSquad,
    ITW_CLASH_SupportsAirborneLandWait,
    ITW_CLASH_SupportsVehicleDropEnabled,
    ITW_CLASH_SupportsVehicleDropHeight,
    ITW_CLASH_SupportsVehicleDropSpeed,
    ITW_CLASH_SupportsVehicleDropLeadSeconds,
    ITW_CLASH_SupportsVehicleDropTries
];
true
