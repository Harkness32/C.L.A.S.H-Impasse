#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsJTACStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Supports_fnc_Admit") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-jtac-core-missing | no JTAC calls";
    false
};

ITW_CLASH_SupportsJTACStarted = true;
ITW_CLASH_SupportsJTACVersion = 1;
ITW_CLASH_SupportsJTACReady = false;

/*
    Commander supports: the JTAC.

    Hark, 2026-10-27: COLOSSUS is the supreme commander and calls supports from
    the whole picture; a JTAC is a special forces team on the ground calling a
    strike on what it can see itself. A split, not one pool: the JTAC has its
    own lane and its own clock, so neither waits on the other.
      - Strike only. A JTAC never generates or directs forces.
      - One call per side every Cooldown seconds (10 minutes), shared by every
        team of that side. COLOSSUS's own flavor cooldowns are neither read nor
        started, and nor is the per-objective cooldown: a JTAC call does not
        lock COLOSSUS off a point.
      - Free: no wallet pays for it. Its scarcity is in the world - one team,
        one cone of terrain, one clock - and charging money on top would count
        the same constraint twice.

    Uncapped because myopic, so the sight test is the whole balance:
      1. a controller is a team on HAL's own special forces list, on foot, not
         withdrawing, that has held its ground for Settle seconds (a team that
         crests a ridge cannot call at once);
      2. the cluster is within Range of it;
      3. the team ITSELF saw a member within SightAge seconds - its own men's
         targetKnowledge, never the commander's or another group's report;
      4. there is a line of sight from the controller's eyes to where the team
         saw it, through terrain and through objects.
    Cheapest first: the line-of-sight calls only run on what passed the rest.

    Everything else is the strike pipeline's, unchanged: the class weights,
    bomb's need for an observed or fixed contact, the acquiring floor, an ETB
    counter already answering, danger close, an aircraft and an origin, and a
    denied corridor. The jet acquires on site as every bomb and guided pass
    does; the controller places the report, it never picks the jet's target.
    Before the jet spawns the core asks again whether the controller still has
    eyes on it (NO_SIGHT), so a team that lost sight or died during the setup
    delay costs a revoke, not a blind pass.

    The best option wins outright, by class weight times the cluster's worth
    times the corridor: with one call in ten minutes, teams compete on target
    quality, and a team watching a battery beats one watching a truck.

    Not yet: the terminal-control reveal while the jet runs in, and charging
    the main bank for an airframe lost on a JTAC call (it is spent at 0 today).
*/

ITW_CLASH_SupportsJTACEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsJTACEnabled",true];
ITW_CLASH_SupportsJTACPoll = missionNamespace getVariable ["ITW_CLASH_SupportsJTACPoll",10];
ITW_CLASH_SupportsJTACCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsJTACCooldown",600];
ITW_CLASH_SupportsJTACFlavors = missionNamespace getVariable ["ITW_CLASH_SupportsJTACFlavors",["BOMB","GUIDED"]];
ITW_CLASH_SupportsJTACRange = missionNamespace getVariable ["ITW_CLASH_SupportsJTACRange",2000];
ITW_CLASH_SupportsJTACSightAge = missionNamespace getVariable ["ITW_CLASH_SupportsJTACSightAge",30];
ITW_CLASH_SupportsJTACSettle = missionNamespace getVariable ["ITW_CLASH_SupportsJTACSettle",60];
// A controller still counts as settled while its leader stays this close to
// where it stopped.
ITW_CLASH_SupportsJTACSettleRadius = missionNamespace getVariable ["ITW_CLASH_SupportsJTACSettleRadius",50];
ITW_CLASH_SupportsJTACLane = "JTAC";
// The sight refusals, nearest to seeing last, so a cluster reports how close
// any team came.
ITW_CLASH_SupportsJTACSightOrder = ["out-of-range","not-seen","no-los"];

ITW_CLASH_SupportsLoudEvents pushBackUnique "jtac-call";

/*
    The teams that may call: on foot, not withdrawing, and settled. Every poll
    keeps each team's settle mark current, so a team that moves starts again.
*/
ITW_CLASH_SupportsJTAC_fnc_Controllers = {
    params ["_hq"];
    private _result = [];
    {
        private _group = _x;
        if (isNull _group) then {continue};
        private _leader = leader _group;
        if (isNull _leader || {!alive _leader}) then {continue};
        if (vehicle _leader != _leader || {_group getVariable ["ITW_CLASH_Withdrawing",false]}) then {
            _group setVariable ["ITW_CLASH_JTACSettle",nil];
            continue
        };
        private _position = getPosATL _leader;
        private _settle = _group getVariable ["ITW_CLASH_JTACSettle",[]];
        if (_settle isEqualTo [] || {((_settle#0) distance2D _position) > ITW_CLASH_SupportsJTACSettleRadius}) then {
            _settle = [_position,time];
            _group setVariable ["ITW_CLASH_JTACSettle",_settle];
        };
        if ((time - (_settle#1)) >= ITW_CLASH_SupportsJTACSettle) then {_result pushBack _group};
    } forEach (_hq getVariable ["RydHQ_SpecForG",[]]);
    _result
};

/*
    Does this team see this contact now? ["", distance] or [why, distance].
    _reported is the knowledge layer's position, used only for the range test;
    the line of sight goes to where the team's own men saw it.
*/
ITW_CLASH_SupportsJTAC_fnc_Sight = {
    params ["_group","_entity","_reported"];
    private _leader = leader _group;
    if (isNull _leader || {!alive _leader} || {isNull _entity}) exitWith {["not-seen",-1]};
    private _distance = _leader distance2D _reported;
    if (_distance > ITW_CLASH_SupportsJTACRange) exitWith {["out-of-range",_distance]};
    private _seenAt = -1e10;
    private _seenPos = [];
    {
        if (!alive _x) then {continue};
        private _intel = _x targetKnowledge _entity;
        if !(_intel isEqualType [] && {count _intel >= 7}) then {continue};
        private _lastSeen = _intel#2;
        if !(_lastSeen isEqualType 0 && {_lastSeen >= 0} && {_lastSeen <= (time + 1)}) then {continue};
        private _position = _intel#6;
        if !(_position isEqualType [] && {count _position >= 2}) then {continue};
        if (_lastSeen > _seenAt) then {
            _seenAt = _lastSeen;
            _seenPos = _position;
        };
    } forEach (units _group);
    if ((time - _seenAt) > ITW_CLASH_SupportsJTACSightAge) exitWith {["not-seen",_distance]};
    private _eye = eyePos _leader;
    private _point = AGLToASL [_seenPos#0,_seenPos#1,1.5];
    if (terrainIntersectASL [_eye,_point]) exitWith {["no-los",_distance]};
    if ((lineIntersectsSurfaces [_eye,_point,_leader,_entity,true,1,"VIEW","GEOM"]) isNotEqualTo []) exitWith {
        ["no-los",_distance]
    };
    ["",_distance]
};

/*
    The nearest controller that sees any member of the cluster, as
    [group, distance], or [why] for the closest any team came.
*/
ITW_CLASH_SupportsJTAC_fnc_Eyes = {
    params ["_side","_cluster","_controllers"];
    private _eyes = [];
    private _closest = 0;
    {
        private _record = [_side,_x] call ITW_CLASH_Knowledge_fnc_Record;
        private _entity = _record getOrDefault ["entity",objNull];
        if (isNull _entity) then {continue};
        private _reported = _record get "position";
        {
            private _group = _x;
            ([_group,_entity,_reported] call ITW_CLASH_SupportsJTAC_fnc_Sight) params ["_why","_distance"];
            if (_why isEqualTo "") then {
                if (_eyes isEqualTo [] || {_distance < (_eyes#1)}) then {_eyes = [_group,_distance]};
            } else {
                _closest = _closest max (ITW_CLASH_SupportsJTACSightOrder find _why);
            };
        } forEach _controllers;
    } forEach (_cluster get "keys");
    if (_eyes isNotEqualTo []) exitWith {_eyes};
    [ITW_CLASH_SupportsJTACSightOrder select (_closest max 0)]
};

/*
    One flavor against one cluster: the strike pipeline's own gates.
    ["", weight, route, aircraft, ahead] or [denial].
*/
ITW_CLASH_SupportsJTAC_fnc_Option = {
    params ["_context","_flavor","_cluster"];
    private _side = _context get "side";
    private _class = _cluster get "class";
    private _row = [_flavor] call ITW_CLASH_Supports_fnc_Row;
    private _base = (_row getOrDefault ["weights",createHashMap]) getOrDefault [_class,0];
    if (_flavor isEqualTo "GUIDED" && {_class isEqualTo "LEAD_ONLY"}) then {
        _base = if ((_cluster get "vehicles") > 0) then {1} else {0};
    };
    private _aim = _cluster get "aim";
    private _footprint = [_flavor,"footprint",50] call ITW_CLASH_Supports_fnc_RowNumber;
    private _why = switch (true) do {
        case !([_flavor] call ITW_CLASH_Supports_fnc_Enabled): {"DISABLED"};
        case (_base <= 0): {"NOT_FOR_" + _class};
        case (_flavor isEqualTo "BOMB" && {!((_cluster get "best") in ["OBSERVED","FIXED"])}): {"NO_CONTACT"};
        case ((_cluster get "worth") < ITW_CLASH_SupportsValueFloorAcquire): {"BELOW_FLOOR"};
        case (
            (_cluster get "vehicles") > 0
            && {[_context get "hq",([_side,_cluster get "keys",0] call ITW_CLASH_Supports_fnc_TargetNow) param [3,[]]] call ITW_CLASH_Supports_fnc_ETBAnswering}
        ): {"ETB_ANSWERING"};
        case ([_context get "friendlies",_aim,_footprint,_flavor,true] call ITW_CLASH_Supports_fnc_DangerClose): {"DANGER_CLOSE"};
        default {""};
    };
    if (_why isNotEqualTo "") exitWith {[_why]};
    ([_side,_flavor] call ITW_CLASH_Supports_fnc_PickClass) params ["_aircraft","_noAircraft"];
    if (_aircraft isEqualTo "") exitWith {[_noAircraft]};
    ([_side,_flavor,_aim] call ITW_CLASH_Supports_fnc_Origin) params ["_origin","_noOrigin"];
    if (_origin isEqualTo []) exitWith {[_noOrigin]};
    private _distance = [_flavor] call ITW_CLASH_Supports_fnc_SpawnDistance;
    private _spawn = [_origin,_aim,_distance] call ITW_CLASH_Supports_fnc_SpawnPoint;
    private _corridor = ([_context get "hq",_spawn,_aim,_row getOrDefault ["fighterRule","HARD_KILL"]] call
        ITW_CLASH_Supports_fnc_Corridor) getOrDefault ["state","COLD"];
    if (_corridor isEqualTo "AIR_DENIED") exitWith {["AIR_DENIED"]};
    [
        "",
        _base * (_cluster get "worth") * ([_corridor] call ITW_CLASH_Supports_fnc_CorridorFactor),
        [_corridor,_origin,_spawn],
        _aircraft,
        _distance / ([_flavor] call ITW_CLASH_Supports_fnc_ProjectionSpeed)
    ]
};

/*
    One side's poll. Nothing is asked while the clock or the lane says no. A
    side that wanted to call and could not says why once, and again only when
    the reasons change.
*/
ITW_CLASH_SupportsJTAC_fnc_Assess = {
    params ["_hq"];
    private _side = side _hq;
    private _controllers = [_hq] call ITW_CLASH_SupportsJTAC_fnc_Controllers;
    if (_controllers isEqualTo []) exitWith {false};
    private _ledger = [_side] call ITW_CLASH_Supports_fnc_Ledger;
    if ([_ledger,"jtac"] call ITW_CLASH_Supports_fnc_OnCooldown) exitWith {false};
    if (((_ledger get "lanes") getOrDefault [ITW_CLASH_SupportsJTACLane,""]) isNotEqualTo "") exitWith {false};
    private _context = [_side] call ITW_CLASH_Supports_fnc_MakeContext;
    if (count _context == 0) exitWith {false};
    private _clusters = [
        _side,_controllers apply {getPosATL leader _x},ITW_CLASH_SupportsJTACRange
    ] call ITW_CLASH_Supports_fnc_Clusters;
    if (_clusters isEqualTo []) exitWith {false};

    private _best = [];
    private _bestWeight = 0;
    private _refused = createHashMap;
    {
        private _cluster = _x;
        private _eyes = [_side,_cluster,_controllers] call ITW_CLASH_SupportsJTAC_fnc_Eyes;
        if (count _eyes < 2) then {
            _refused set [_eyes#0,(_refused getOrDefault [_eyes#0,0]) + 1];
            continue
        };
        _eyes params ["_controller","_range"];
        {
            private _flavor = _x;
            private _option = [_context,_flavor,_cluster] call ITW_CLASH_SupportsJTAC_fnc_Option;
            if ((_option#0) isNotEqualTo "") then {
                _refused set [_option#0,(_refused getOrDefault [_option#0,0]) + 1];
                continue
            };
            _option params ["","_weight","_route","_aircraft","_ahead"];
            if (_weight > _bestWeight) then {
                _bestWeight = _weight;
                _best = [_flavor,_cluster,_weight,_route,_aircraft,_ahead,_controller,_range];
            };
        } forEach ITW_CLASH_SupportsJTACFlavors;
    } forEach _clusters;

    private _sign = _context get "sign";
    if (_best isEqualTo []) exitWith {
        private _held = [_refused toArray false,[],{_x#0},"ASCEND"] call BIS_fnc_sortBy;
        if ((_ledger getOrDefault ["jtacSaid",""]) isNotEqualTo (str _held)) then {
            _ledger set ["jtacSaid",str _held];
            ["jtac-held",[_sign,count _controllers,count _clusters,_held]] call ITW_CLASH_Supports_fnc_Log;
        };
        false
    };
    _ledger set ["jtacSaid",""];

    _best params ["_flavor","_cluster","_weight","_route","_aircraft","_ahead","_controller","_range"];
    (_context get "classes") set [_flavor,_aircraft];
    private _pick = [
        "STRIKE",_flavor,-1,"JTAC",_cluster get "aim",_weight,_route,_cluster,
        createHashMapFromArray [
            ["ahead",_ahead],["lane",ITW_CLASH_SupportsJTACLane],["wallet","FREE"],["price",0],
            ["controller",_controller]
        ]
    ] call ITW_CLASH_Supports_fnc_Candidate;
    _context set ["admitted",""];
    if !([_context,_pick] call ITW_CLASH_Supports_fnc_Admit) exitWith {false};
    (_ledger get "cooldowns") set ["jtac",time + ITW_CLASH_SupportsJTACCooldown];
    ["jtac-call",[
        _sign,_context getOrDefault ["admitted",""],_flavor,
        [_controller] call ITW_CLASH_Knowledge_fnc_GroupId,round _range,
        _cluster get "key",_cluster get "class",_cluster get "best",
        (round ((_cluster get "worth") * 10)) / 10,(round (_weight * 100)) / 100,
        _route#0,count _controllers
    ]] call ITW_CLASH_Supports_fnc_Log;
    true
};

/*
    Asked by the core before the jet spawns: does the controller still see any
    member of what it called? A team that lost sight or died since revokes.
*/
ITW_CLASH_SupportsJTAC_fnc_StillSees = {
    params ["_support"];
    private _group = _support getOrDefault ["controller",grpNull];
    if (isNull _group) exitWith {false};
    private _side = _support get "side";
    (((_support get "target") getOrDefault ["keys",[]]) findIf {
        private _record = [_side,_x] call ITW_CLASH_Knowledge_fnc_Record;
        private _entity = _record getOrDefault ["entity",objNull];
        !isNull _entity && {(([_group,_entity,_record get "position"] call ITW_CLASH_SupportsJTAC_fnc_Sight)#0) isEqualTo ""}
    }) >= 0
};

[] spawn {
    scriptName "ITW_CLASH_SupportsJTAC";
    waitUntil {
        sleep 1;
        !isNil "ITW_CLASH_fnc_GetCommanderForSide" || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    while {!(missionNamespace getVariable ["ITW_GameOver",false])} do {
        if (ITW_CLASH_SupportsEnabled && {ITW_CLASH_SupportsJTACEnabled}) then {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            {
                private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
                if (!isNull _hq) then {[_hq] call ITW_CLASH_SupportsJTAC_fnc_Assess};
            } forEach _sides;
        };
        sleep ITW_CLASH_SupportsJTACPoll;
    };
};

ITW_CLASH_SupportsJTACReady = true;
diag_log format [
    "CLASH BOOT | supports-jtac-ready | version=%1 enabled=%2 cooldown=%3 flavors=%4 range=%5 sightAge=%6 settle=%7 lane=%8 wallet=FREE objectiveCooldown=false colossusCooldowns=false sightRecheckedBeforeSpawn=true",
    ITW_CLASH_SupportsJTACVersion,
    ITW_CLASH_SupportsJTACEnabled,
    ITW_CLASH_SupportsJTACCooldown,
    ITW_CLASH_SupportsJTACFlavors,
    ITW_CLASH_SupportsJTACRange,
    ITW_CLASH_SupportsJTACSightAge,
    ITW_CLASH_SupportsJTACSettle,
    ITW_CLASH_SupportsJTACLane
];

true
