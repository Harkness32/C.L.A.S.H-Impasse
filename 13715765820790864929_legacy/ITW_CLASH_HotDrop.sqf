#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HotDropStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_AirPicture_fnc_ClassifyCorridor") exitWith {
    diag_log "CLASH BOOT | WARNING | hot-drop-no-air-picture | troop lifts fly HAL's own profile";
    false
};

ITW_CLASH_HotDropStarted = true;
ITW_CLASH_HotDropVersion = 2;
ITW_CLASH_HotDropReady = false;

/*
    HotDrop: the troop-insertion profile.

    Thunder Run is the logistics profile. It exists to put a crate on the
    ground, and it is welded to that job in three places - its entry demands a
    box and a CLASH service-pool entry, its staging slingloads the crate and
    writes RydHQ_AmmoPoints, and its release hands the package to RYD_AmmoDrop.
    A troop lift has none of those, so bending it into one would mean
    parameterizing proven resupply code and risking the delivery path that
    currently works.

    HotDrop is its own thing with the same idea: when a troop lift is going
    somewhere dangerous, fly it low and fast, pop up at the last moment, put the
    infantry out, and get away. Transport and logistics stay separate. What it
    borrows is the machinery that never cared about the payload in the first
    place - countermeasure discovery, the flare budget and its per-phase cadence,
    and the corridor classifier - by calling those functions, not by copying
    them.

    It never asks HAL for a lift and never changes HAL's mind about one. It
    watches for a lift HAL has already launched, takes the airframe for the last
    few kilometres when the corridor says the approach is contested or hot, and
    hands it straight back afterwards. A clear route is left entirely alone:
    HAL's own profile is fine when nothing is shooting.

    The line this sits on, and it is a decided one: a tasked helicopter's
    MISSION is never changed. No recall, no diversion, no corridor shutdown that
    grounds a flight already under way - a committed flight goes in, and the
    corridor rules only ever gate a lift that has not launched yet. What HotDrop
    changes is BEHAVIOUR: the same aircraft, the same troops, the same landing
    zone, flown lower and faster and unloaded from the air. If a future change
    here would move a destination, cancel a run or park an airframe to keep it
    safe, it is the wrong change.

    Two rules come from the host, not from us:
      - ITW_ParamHelisUnload 0 means the host wants troops landed, never
        dropped. HotDrop then flies the profile and lands, and never forces a
        parachute.
      - Anything a player is flying, riding or leading is untouched.
*/

ITW_CLASH_HotDropEnabled = missionNamespace getVariable ["ITW_CLASH_HotDropEnabled",true];
ITW_CLASH_HotDropPoll = missionNamespace getVariable ["ITW_CLASH_HotDropPoll",10];
// Corridor verdicts worth flying the profile for. A COLD route is left to HAL.
ITW_CLASH_HotDropStates = missionNamespace getVariable [
    "ITW_CLASH_HotDropStates",["CONTESTED","HOT","AIR_DENIED"]
];
// Take the airframe only for the last leg, the way Thunder Run does.
ITW_CLASH_HotDropTakeoverRadius = missionNamespace getVariable ["ITW_CLASH_HotDropTakeoverRadius",3000];
ITW_CLASH_HotDropIngressHeight = missionNamespace getVariable ["ITW_CLASH_HotDropIngressHeight",25];
// The claim window: on the ground, loaded, before takeoff. Decided here and
// not revisited, so it has to be a height a loading aircraft is actually at.
ITW_CLASH_HotDropBoardingHeight = missionNamespace getVariable [
    "ITW_CLASH_HotDropBoardingHeight",3
];
ITW_CLASH_HotDropIPRadius = missionNamespace getVariable ["ITW_CLASH_HotDropIPRadius",1200];
ITW_CLASH_HotDropPopupRadius = missionNamespace getVariable ["ITW_CLASH_HotDropPopupRadius",700];
// Above the paradrop module's own 55 m minimum, so the pop-up puts the aircraft
// where the drop wants it without a second climb.
ITW_CLASH_HotDropDropHeight = missionNamespace getVariable ["ITW_CLASH_HotDropDropHeight",130];
ITW_CLASH_HotDropEgressDistance = missionNamespace getVariable ["ITW_CLASH_HotDropEgressDistance",1000];
ITW_CLASH_HotDropTransitHeight = missionNamespace getVariable ["ITW_CLASH_HotDropTransitHeight",120];
ITW_CLASH_HotDropFlareStart = missionNamespace getVariable ["ITW_CLASH_HotDropFlareStart",1500];
// Per-phase watchdogs. A run that stops making progress hands the airframe back
// rather than holding it forever.
ITW_CLASH_HotDropPhaseTimeout = missionNamespace getVariable ["ITW_CLASH_HotDropPhaseTimeout",120];
// One airframe should not be taken over again immediately after a run.
ITW_CLASH_HotDropCooldown = missionNamespace getVariable ["ITW_CLASH_HotDropCooldown",180];

ITW_CLASH_HotDropRuns = createHashMap;

ITW_CLASH_HotDrop_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hot-drop-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HOT DROP | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["hot-drop",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

// The infantry riding in this helicopter, as their own group. Cargo is a group
// other than the crew's; a door gunner is not cargo.
ITW_CLASH_HotDrop_fnc_CargoGroup = {
    params ["_veh"];
    if (isNull _veh) exitWith {grpNull};
    private _crewGroup = group effectiveCommander _veh;
    private _found = grpNull;
    {
        private _unit = _x;
        if (!alive _unit || {isPlayer _unit}) then {continue};
        if !(_unit isKindOf "CAManBase") then {continue};
        private _unitGroup = group _unit;
        if (isNull _unitGroup || {_unitGroup isEqualTo _crewGroup}) then {continue};
        // Riding, not manning a turret.
        private _role = (assignedVehicleRole _unit) param [0,""];
        if (_role in ["Driver","Turret"]) then {continue};
        _found = _unitGroup;
    } forEach (crew _veh);
    _found
};

// Where HAL is taking it, read off the engine rather than HAL's internals.
ITW_CLASH_HotDrop_fnc_Destination = {
    params ["_veh"];
    if (isNull _veh) exitWith {[]};
    private _driver = driver _veh;
    if (isNull _driver) exitWith {[]};
    private _expected = expectedDestination _driver;
    if !(_expected isEqualType []) exitWith {[]};
    private _position = _expected param [0,[]];
    if !(_position isEqualType []) exitWith {[]};
    if (count _position < 3) exitWith {[]};
    if (_position isEqualTo [0,0,0]) exitWith {[]};
    _position
};

/*
    Is this a lift HotDrop may take? Everything a player touches, everything
    another C.L.A.S.H. system already owns, and everything that is not actually
    carrying infantry somewhere is left alone.
*/
ITW_CLASH_HotDrop_fnc_IsEligible = {
    params ["_veh"];
    if (isNull _veh || {!alive _veh} || {!canMove _veh}) exitWith {false};
    if !(_veh isKindOf "Helicopter") exitWith {false};
    if (_veh getVariable ["ITW_CLASH_HotDropActive",false]) exitWith {false};
    if (_veh getVariable ["ITW_CLASH_ThunderRunActive",false]) exitWith {false};
    if (time < (_veh getVariable ["ITW_CLASH_HotDropCooldownUntil",0])) exitWith {false};
    if ((crew _veh) findIf {isPlayer _x} >= 0) exitWith {false};

    private _driver = driver _veh;
    if (isNull _driver || {!alive _driver}) exitWith {false};
    private _crewGroup = group _driver;
    // Recovery and medical lifts belong to their own owners.
    if (
        (_crewGroup getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo ""
        || {(_crewGroup getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo ""}
    ) exitWith {false};
    // Decided once, on the ground, before anyone commits to a profile.
    //
    // This used to claim airborne lifts, which is how an aircraft another
    // system had already planned got taken two minutes into its own flight:
    // ITW_CLASH_HALNativeSFFix.sqf:147 selected a carrier and cargo pair for
    // an SF insertion, and thirteen seconds later a map-wide scan found the
    // same aircraft airborne near a destination and flew it somewhere else.
    // Seizing work in progress is the defect, not a missing check, so the
    // window is now the ground before takeoff and nothing else.
    if (((getPosATL _veh)#2) > ITW_CLASH_HotDropBoardingHeight) exitWith {false};
    // Another owner already has this lift. The marker is set by the native SF
    // insertion path and by this module, so it answers for both.
    if !(isNil {_crewGroup getVariable "ITW_CLASH_HALParadropCargoGroup"}) exitWith {false};
    // Declined once is declined for this lift: the corridor is read at
    // boarding and not revisited, so re-asking every poll would only produce
    // a different answer to a question already settled.
    if (_veh getVariable ["ITW_CLASH_HotDropDeclined",false]) exitWith {false};
    true
};

/*
    Are the passengers actually aboard?

    Asked at claim time, which the airborne version never did - it tested that
    a cargo group existed, not that anyone was in the aircraft, so an empty
    helicopter could fly a full contested-corridor profile and report success.
    Same test the DROP phase uses, so the two cannot disagree.
*/
ITW_CLASH_HotDrop_fnc_Aboard = {
    params ["_veh","_cargoGroup"];
    if (isNull _veh || {isNull _cargoGroup}) exitWith {[]};
    (units _cargoGroup) select {alive _x && {vehicle _x == _veh}}
};

ITW_CLASH_HotDrop_fnc_Claim = {
    params ["_veh","_cargoGroup","_destination","_hq","_corridorState"];
    private _crewGroup = group driver _veh;
    private _state = createHashMapFromArray [
        ["vehicle",_veh],
        ["crewGroup",_crewGroup],
        ["cargoGroup",_cargoGroup],
        ["hq",_hq],
        ["destination",+_destination],
        ["startedAt",time],
        ["phase","TAKEOVER"],
        ["corridorState",_corridorState],
        ["countermeasureEmitter",
            if (isNil "ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter") then {[]} else {
                [_veh] call ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter
            }
        ]
    ];
    // Borrowed wholesale: the flare budget and its per-phase split never cared
    // what the aircraft was carrying.
    if (!isNil "ITW_CLASH_ThunderRun_fnc_InitFlareBudget") then {
        [_state] call ITW_CLASH_ThunderRun_fnc_InitFlareBudget;
    };

    _veh setVariable ["ITW_CLASH_HotDropActive",true,true];
    _veh setVariable ["ITW_CLASH_HotDrop",_state];
    _crewGroup setVariable ["ITW_CLASH_HotDropActive",true];
    ITW_CLASH_HotDropRuns set [str _veh,_state];
    _state
};

ITW_CLASH_HotDrop_fnc_SetPhase = {
    params ["_state","_phase"];
    _state set ["phase",_phase];
    _state set ["phaseAt",time];
    private _veh = _state getOrDefault ["vehicle",objNull];
    if (!isNull _veh) then {_veh setVariable ["ITW_CLASH_HotDrop",_state]};

    ["phase",[
        _phase,
        if (isNull _veh) then {""} else {typeOf _veh},
        if (isNull _veh) then {[]} else {(getPosATL _veh) apply {round _x}},
        if (isNull _veh) then {0} else {round ((getPosATL _veh)#2)},
        if (isNil "ITW_CLASH_ThunderRun_fnc_FlareRemaining") then {-1} else {
            [_state] call ITW_CLASH_ThunderRun_fnc_FlareRemaining
        }
    ]] call ITW_CLASH_HotDrop_fnc_Log;
    true
};

// Flares, on Thunder Run's own cadence. HotDrop's DROP phase is that machinery's
// RELEASE, so it is named as such when asking for a flare and nowhere else.
ITW_CLASH_HotDrop_fnc_Flare = {
    params ["_state","_phase"];
    if (isNil "ITW_CLASH_ThunderRun_fnc_MaybeFlare") exitWith {false};
    private _mapped = if (_phase isEqualTo "DROP") then {"RELEASE"} else {_phase};
    [_state,_mapped] call ITW_CLASH_ThunderRun_fnc_MaybeFlare
};

/*
    Hand the airframe back exactly as it was found: AI restored, transit height,
    speed released, marks cleared. HAL owns it again from here and is free to
    give it its next job.
*/
ITW_CLASH_HotDrop_fnc_Handback = {
    params ["_state",["_outcome","COMPLETE"]];
    private _veh = _state getOrDefault ["vehicle",objNull];
    private _crewGroup = _state getOrDefault ["crewGroup",grpNull];

    if (!isNull _veh) then {
        _veh enableAI "TARGET";
        _veh enableAI "AUTOTARGET";
        _veh forceSpeed -1;
        _veh flyInHeight ITW_CLASH_HotDropTransitHeight;
        _veh setVariable ["ITW_CLASH_HotDropActive",false,true];
        _veh setVariable ["ITW_CLASH_HotDrop",nil];
        _veh setVariable ["ITW_CLASH_HotDropCooldownUntil",time + ITW_CLASH_HotDropCooldown];
        ITW_CLASH_HotDropRuns deleteAt (str _veh);
    };
    if (!isNull _crewGroup) then {
        _crewGroup setVariable ["ITW_CLASH_HotDropActive",false];
        _crewGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
    };

    ["handback",[
        _outcome,
        if (isNull _veh) then {""} else {typeOf _veh},
        round (time - (_state getOrDefault ["startedAt",time]))
    ]] call ITW_CLASH_HotDrop_fnc_Log;
    true
};

/*
    Put the infantry out. A parachute where the host allows one and the aircraft
    is high enough, a landing otherwise - the paradrop module owns both of those
    answers already, including its own fallback to land when it is too low, so
    the decision is asked for rather than reimplemented.
*/
ITW_CLASH_HotDrop_fnc_PutOut = {
    params ["_state"];
    private _veh = _state getOrDefault ["vehicle",objNull];
    private _crewGroup = _state getOrDefault ["crewGroup",grpNull];
    private _cargoGroup = _state getOrDefault ["cargoGroup",grpNull];
    if (isNull _veh || {isNull _cargoGroup}) exitWith {["NONE",false]};

    private _unload = missionNamespace getVariable ["ITW_ParamHelisUnload",50];
    if !(_unload isEqualType 0) then {_unload = 50};
    // The host asked for landings. Fly the profile, then land: never force a
    // parachute on a mission configured against it.
    private _mayDrop = _unload > 0
        && {!isNil "ITW_CLASH_HALParadrop_fnc_Execute"}
        && {missionNamespace getVariable ["ITW_CLASH_HALParadropReady",false]};

    if (!_mayDrop) exitWith {
        _veh land "GET OUT";
        ["put-out",["LAND",typeOf _veh,groupId _cargoGroup,round ((getPosATL _veh)#2)]] call
            ITW_CLASH_HotDrop_fnc_Log;
        ["LAND",true]
    };

    _crewGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_cargoGroup];
    private _dropped = [_crewGroup,_veh] call ITW_CLASH_HALParadrop_fnc_Execute;
    private _method = if (_dropped) then {"PARADROP"} else {"LAND_FALLBACK"};

    // The paradrop module lands for itself on exactly one of its five false
    // returns - too low, at HALParadrop.sqf:110. The others (no cargo group,
    // nobody aboard) just return false, and this used to call all of them
    // LAND_FALLBACK and report success, so troops could fly home still
    // aboard with the log saying they were delivered. Land for real unless
    // they are already out.
    if (!_dropped && {([_veh,_cargoGroup] call ITW_CLASH_HotDrop_fnc_Aboard) isNotEqualTo []}) then {
        _veh land "GET OUT";
    };
    ["put-out",[
        _method,typeOf _veh,groupId _cargoGroup,round ((getPosATL _veh)#2)
    ]] call ITW_CLASH_HotDrop_fnc_Log;
    [_method,true]
};

ITW_CLASH_HotDrop_fnc_Run = {
    params ["_state"];
    private _veh = _state getOrDefault ["vehicle",objNull];
    private _destination = +(_state getOrDefault ["destination",[]]);
    private _driver = driver _veh;
    private _crewGroup = _state getOrDefault ["crewGroup",grpNull];

    private _abort = {
        params ["_why"];
        [_state,_why] call ITW_CLASH_HotDrop_fnc_Handback;
    };
    private _alive = {
        !isNull _veh && {alive _veh} && {canMove _veh}
        && {!isNull _driver} && {alive _driver}
    };
    if !(call _alive) exitWith {["AIRFRAME_LOST"] call _abort};

    // Take control: no autonomous target chasing on the way in.
    _veh disableAI "TARGET";
    _veh disableAI "AUTOTARGET";
    if (!isNil "RYD_WPdel") then {[_crewGroup] call RYD_WPdel};

    // --- INGRESS: low and fast to the initial point ---------------------
    [_state,"INGRESS"] call ITW_CLASH_HotDrop_fnc_SetPhase;
    _veh flyInHeight ITW_CLASH_HotDropIngressHeight;
    (group _driver) setSpeedMode "FULL";
    private _direction = _destination getDir (getPosATL _veh);
    private _ip = _destination getPos [ITW_CLASH_HotDropIPRadius,_direction];
    if (count _ip < 3) then {_ip pushBack 0};
    _driver doMove _ip;

    private _deadline = time + ITW_CLASH_HotDropPhaseTimeout;
    waitUntil {
        sleep 0.5;
        if (call _alive && {(getPosATL _veh) distance2D _destination < ITW_CLASH_HotDropFlareStart}) then {
            [_state,"INGRESS"] call ITW_CLASH_HotDrop_fnc_Flare;
        };
        !(call _alive)
        || {time >= _deadline}
        || {(getPosATL _veh) distance2D _destination <= ITW_CLASH_HotDropPopupRadius}
    };
    if !(call _alive) exitWith {["AIRFRAME_LOST"] call _abort};

    // --- POPUP: climb to drop height ------------------------------------
    [_state,"POPUP"] call ITW_CLASH_HotDrop_fnc_SetPhase;
    _veh flyInHeight ITW_CLASH_HotDropDropHeight;
    _driver doMove _destination;
    _deadline = time + ITW_CLASH_HotDropPhaseTimeout;
    waitUntil {
        sleep 0.5;
        [_state,"POPUP"] call ITW_CLASH_HotDrop_fnc_Flare;
        !(call _alive)
        || {time >= _deadline}
        || {((getPosATL _veh)#2) >= (ITW_CLASH_HotDropDropHeight * 0.8)}
    };
    if !(call _alive) exitWith {["AIRFRAME_LOST"] call _abort};

    // --- DROP: infantry out ---------------------------------------------
    [_state,"DROP"] call ITW_CLASH_HotDrop_fnc_SetPhase;
    [_state,"DROP"] call ITW_CLASH_HotDrop_fnc_Flare;
    ([_state] call ITW_CLASH_HotDrop_fnc_PutOut) params ["_method"];
    _state set ["method",_method];

    private _cargoGroup = _state getOrDefault ["cargoGroup",grpNull];
    _deadline = time + ITW_CLASH_HotDropPhaseTimeout;
    waitUntil {
        sleep 0.5;
        [_state,"DROP"] call ITW_CLASH_HotDrop_fnc_Flare;
        !(call _alive)
        || {time >= _deadline}
        || {isNull _cargoGroup}
        || {((units _cargoGroup) select {alive _x && {vehicle _x == _veh}}) isEqualTo []}
    };
    if !(call _alive) exitWith {["AIRFRAME_LOST"] call _abort};

    // --- EGRESS: turn away, stay low ------------------------------------
    [_state,"EGRESS"] call ITW_CLASH_HotDrop_fnc_SetPhase;
    _veh flyInHeight ITW_CLASH_HotDropIngressHeight;
    private _away = _destination getPos [
        ITW_CLASH_HotDropEgressDistance,
        _destination getDir (getPosATL _veh)
    ];
    if (count _away < 3) then {_away pushBack 0};
    _driver doMove _away;
    _deadline = time + ITW_CLASH_HotDropPhaseTimeout;
    waitUntil {
        sleep 0.5;
        [_state,"EGRESS"] call ITW_CLASH_HotDrop_fnc_Flare;
        !(call _alive)
        || {time >= _deadline}
        || {(getPosATL _veh) distance2D _destination >= ITW_CLASH_HotDropEgressDistance}
    };

    [_state,if (call _alive) then {"COMPLETE"} else {"AIRFRAME_LOST"}] call
        ITW_CLASH_HotDrop_fnc_Handback;
};

ITW_CLASH_HotDrop_fnc_Consider = {
    params ["_veh"];
    if !([_veh] call ITW_CLASH_HotDrop_fnc_IsEligible) exitWith {false};
    private _cargoGroup = [_veh] call ITW_CLASH_HotDrop_fnc_CargoGroup;
    if (isNull _cargoGroup) exitWith {false};
    if (((units _cargoGroup) findIf {isPlayer _x}) >= 0) exitWith {false};
    // Loaded, not merely assigned. Still boarding is not a decision point, so
    // this is the one rejection that does not mark the lift declined.
    if (([_veh,_cargoGroup] call ITW_CLASH_HotDrop_fnc_Aboard) isEqualTo []) exitWith {false};

    private _destination = [_veh] call ITW_CLASH_HotDrop_fnc_Destination;
    if (_destination isEqualTo []) exitWith {false};
    if ((getPosATL _veh) distance2D _destination > ITW_CLASH_HotDropTakeoverRadius) exitWith {false};

    private _hq = if (isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {grpNull} else {
        [group effectiveCommander _veh] call ITW_CLASH_fnc_GetCommanderForGroup
    };
    if (isNull _hq) exitWith {false};

    private _corridor = [
        _hq,getPosATL _veh,_destination
    ] call ITW_CLASH_AirPicture_fnc_ClassifyCorridor;
    private _corridorState = _corridor getOrDefault ["state","COLD"];
    // A clear approach is HAL's to fly. HotDrop is for the bad ones. Read once
    // at boarding and settled: a lift that launches into a quiet corridor
    // stays HAL's even if it sours, and one that launches into a bad one flies
    // the profile even if the corridor clears. Air defence is identified
    // reactively, so a cautious profile flown into a corridor that turns out
    // to be cold costs nothing worth a second decision.
    if !(_corridorState in ITW_CLASH_HotDropStates) exitWith {
        _veh setVariable ["ITW_CLASH_HotDropDeclined",true];
        ["declined",[
            _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,groupId _cargoGroup,
            _corridorState,_corridor getOrDefault ["reason",""]
        ]] call ITW_CLASH_HotDrop_fnc_Log;
        false
    };

    private _state = [
        _veh,_cargoGroup,_destination,_hq,_corridorState
    ] call ITW_CLASH_HotDrop_fnc_Claim;
    ["claimed",[
        _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,groupId _cargoGroup,
        _corridorState,_corridor getOrDefault ["reason",""],
        round ((getPosATL _veh) distance2D _destination)
    ]] call ITW_CLASH_HotDrop_fnc_Log;

    [_state] spawn {
        scriptName "ITW_CLASH_HotDropRun";
        (_this) call ITW_CLASH_HotDrop_fnc_Run;
    };
    true
};

[] spawn {
    scriptName "ITW_CLASH_HotDrop";
    waitUntil {
        sleep 1;
        (
            !isNil "ITW_CLASH_fnc_GetCommanderForGroup"
            && {missionNamespace getVariable ["ITW_CLASH_AirPictureReady",false]}
        ) || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_HotDropEnabled) then {
            // Loading aircraft only. This is a boarding trigger that happens
            // to be polled rather than a map-wide hunt for lifts to take over.
            {
                [_x] call ITW_CLASH_HotDrop_fnc_Consider;
            } forEach (
                vehicles select {
                    _x isKindOf "Helicopter"
                    && {alive _x}
                    && {((getPosATL _x)#2) <= ITW_CLASH_HotDropBoardingHeight}
                    && {(crew _x) isNotEqualTo []}
                }
            );
        };
        sleep ITW_CLASH_HotDropPoll;
    };
};

ITW_CLASH_HotDropReady = true;
diag_log format [
    "CLASH BOOT | hot-drop-ready | version=%1 states=%2 takeover=%3 ingress=%4 popup=%5 dropHeight=%6 poll=%7 boardingHeight=%8 payload=troops claimedAt=boarding seizesAirborne=false logisticsUntouched=true borrows=flares,corridor,paradrop",
    ITW_CLASH_HotDropVersion,
    ITW_CLASH_HotDropStates,
    ITW_CLASH_HotDropTakeoverRadius,
    ITW_CLASH_HotDropIngressHeight,
    ITW_CLASH_HotDropPopupRadius,
    ITW_CLASH_HotDropDropHeight,
    ITW_CLASH_HotDropPoll,
    ITW_CLASH_HotDropBoardingHeight
];
true
