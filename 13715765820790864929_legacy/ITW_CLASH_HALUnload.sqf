#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALUnloadStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALUnloadReady",false]
};

ITW_CLASH_HALUnloadStarted = true;
ITW_CLASH_HALUnloadReady = false;
ITW_CLASH_HALUnloadVersion = 5;
scriptName "ITW_CLASH_HALUnload";

/*
    One owner for HAL troop-lift unloads.

    HAL owns whether a squad rides, which carrier is used, and the route.
    This module owns exactly one question about the insertion: LAND, PARADROP,
    or HOT_PARADROP.

    Since v5 the question is asked about a kilometre short of HAL's insertion
    waypoint, and a lift that is going to drop has that one waypoint moved past
    the drop zone so the aircraft flies through instead of arriving. A lift
    that is going to land is not touched at all. See "The run-in" below.

    The order-file hook is deliberately asynchronous. It spawns fnc_Unload and
    then deletes HAL's completed waypoint in the caller. A runtime error in this
    module therefore cannot strand the carrier on a waypoint - the failure mode
    that produced aee1341. If this module is absent entirely, the hook falls
    back to stock land "GET OUT" plus the existing carrier release helper.
*/

/*
    Drop run tuning.

    Hark, on the first successful paradrop through this owner: "it flew there,
    leveled out, raised then, then paradroped, then flew forward a bit and sat
    still... we need a paradrop to be smooth, fast, almost as though its one
    complete motion and then BOOM, j hook rtb."

    Each of those is a line of code, not a feel problem:

    - "leveled out, raised then" is the climb. flyInHeight was set AT the
      insertion waypoint, so the aircraft arrived at HAL's transit height and
      then climbed on top of the objective while Execute's own waitUntil held
      it there. Climbing en route removes the pause entirely: drop altitude is
      reached somewhere over the approach, and the climb wait passes on its
      first evaluation.
    - "flew forward a bit and sat still" is the absence of any egress. The
      waypoint statement deletes HAL's waypoint before Unload is even spawned,
      so the moment the chute is out the carrier has no destination at all. It
      coasts to a stop and hovers over the objective it just dropped into.
*/
// Climb to drop altitude during the transit, so the run-in is already level.
ITW_CLASH_HALUnloadClimbEnRoute = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadClimbEnRoute",true
];
/*
    How late to climb.

    v1 climbed the moment the chalk was aboard, which cured the hover over the
    objective but flew the WHOLE route at drop altitude. That is more exposure
    for longer on every lift, and the loss closure punishes air losses
    collectively, so it risked trading a cosmetic fault for fewer lifts
    overall - Hark's point, and he was right.

    So the climb waits until the last third of the run. The hover is still
    cured, because the aircraft is level well before it arrives, and the
    approach up to that point stays at whatever height HAL was flying.

    Fail-open: if the destination cannot be read off the engine there is no
    fraction to measure, and the climb happens immediately, which is v1.
*/
ITW_CLASH_HALUnloadClimbFraction = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadClimbFraction",0.34
];
// The J-hook: carry through past the drop, then bank away. Measured from the
// drop point along the inbound bearing, and perpendicular to it.
ITW_CLASH_HALUnloadEgress = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadEgress",true
];
// Native ITW's good habit: a paradrop is a fly-through, not an arrival.
// Arm a straight continuation BEFORE the first chute opens so the aircraft
// never loses forward intent over the objective.
ITW_CLASH_HALUnloadFlyThrough = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadFlyThrough",true
];
ITW_CLASH_HALUnloadEgressThrough = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadEgressThrough",1000
];
ITW_CLASH_HALUnloadEgressOffset = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadEgressOffset",600
];
ITW_CLASH_HALUnloadTransitHeight = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadTransitHeight",
    missionNamespace getVariable ["ITW_CLASH_HotDropTransitHeight",120]
];

/*
    The run-in: a paradrop is flown the way native ITW flies one.

    Hark, on v4: "we set the waypoint on the ground, helo paths to transport
    place, slows, lowers, gets there, then raises, then paradrops, then leaves.
    its stupid clunky."

    Every clause of that is the same cause. v4 decided the mode AT HAL's
    insertion waypoint, so the aircraft had to arrive there first, and an AI
    helicopter arrives at its last waypoint by braking for it. Run A measured
    it: 24 km/h at the seam, drop five seconds later, 89 km/h on the way out.

    Native ITW never puts a waypoint on the drop (ITW_AtkUnloadAirplane,
    ITW_Attack.sqf:4157). It moves the aircraft's destination 1500 m PAST the
    objective, watches the distance, and ejects as the aircraft passes. The
    aircraft is never arriving anywhere, so it never slows.

    This is that, on HAL's lift:

    - About ITW_CLASH_HALUnloadRunInDistance out, the mode is decided, with the
      same owner and the same table as the seam.
    - LAND and NO_LAND change nothing. HAL's waypoint stays where HAL put it.
    - PARADROP and HOT_PARADROP move HAL's OWN waypoint to the through point
      beyond the drop zone, and set drop height and full speed. No waypoint is
      deleted and none is added before the drop, so HAL's carrier wait and its
      statement are both still live.
    - The chalk goes out as the aircraft crosses the drop zone, through the
      same paradrop owner as before.
    - fnc_Egress appends the lateral break and home, exactly as in v4.

    Switched off, this file is v4: en-route climb, decision at the seam.
*/
ITW_CLASH_HALUnloadRunIn = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadRunIn",true
];
ITW_CLASH_HALUnloadRunInDistance = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadRunInDistance",1200
];
// Not armed on the pad. Metres above ground before the run-in may begin.
ITW_CLASH_HALUnloadRunInMinHeight = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadRunInMinHeight",10
];
// Armed but never crossed the drop zone: give HAL its waypoint back.
ITW_CLASH_HALUnloadRunInTimeout = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadRunInTimeout",120
];
// Metres to shift the release. Positive is earlier, on the friendly side.
ITW_CLASH_HALUnloadReleaseBias = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadReleaseBias",0
];
// How long the paradrop owner may wait for altitude on a fly-by. At the seam
// it waits ITW_CLASH_HALParadrop_ClimbTimeout, because the aircraft is
// standing over the point. On a run-in every second is 50 m further in.
ITW_CLASH_HALUnloadReleaseWait = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadReleaseWait",1
];
// Sideways miss, in metres, past which the pass is not a drop.
ITW_CLASH_HALUnloadMaxOffset = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadMaxOffset",350
];

/*
    Handing the aircraft back after a drop.

    HAL ends a lift in two places, and a paradrop reaches neither:

    - The order file waits in RYD_Wait until the carrier has NO waypoints
      (HAC_fnc.sqf:2143). The egress route is waypoints, so that wait does not
      end until the aircraft has been parked for three minutes.
    - It then clears CargoM on group (assignedDriver (assignedVehicle _UL)).
      ITW_AtkParachute unassigns every jumper (ITW_Attack.sqf:4244), so that
      is grpNull, the write goes nowhere, and SCargo keeps the carrier Busy
      until its 600 s standstill timer (SCargo.sqf:645).

    Run A showed that state 62 s after its one drop: three waypoints, Busy and
    CargoM both true.

    Both have a native input, and this uses those and nothing else:

    - RydHQ_MIA on the carrier group is HAL's own "stop waiting", read and
      cleared by RYD_Wait (HAC_fnc.sqf:1946). The order thread then carries on
      with the squad on the ground. ITW_CLASH_fnc_BeginRelease uses the same
      flag the same way.
    - CargoM false is SCargo's own exit. It sends the carrier home and frees
      Busy with its own code.

    CargoM waits for the break point, because SCargo's return leg replaces
    every waypoint the aircraft has, and the J-hook is two of them.
*/
ITW_CLASH_HALUnloadHandback = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadHandback",true
];
ITW_CLASH_HALUnloadHandbackRadius = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadHandbackRadius",250
];
ITW_CLASH_HALUnloadHandbackTimeout = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadHandbackTimeout",60
];
// RYD_Wait polls every 6 s on a carrier. Two polls, then the flag is taken
// back so it cannot end the NEXT lift's wait.
ITW_CLASH_HALUnloadOrderReleaseWait = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadOrderReleaseWait",15
];
/*
    GoFlank.sqf and GoSFAttack.sqf clear CargoM on the carrier group they
    already hold, on the line after their wait returns. Released at the drop,
    they would send the aircraft home from over the drop zone and the break
    would never be flown. These two are released at the break instead, which
    holds the squad's order for the length of the egress and no longer.
*/
ITW_CLASH_HALUnloadReleaseAtBreak = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadReleaseAtBreak",["GoFlank","GoSFAttack"]
];

ITW_CLASH_HALUnloadOrderSpecs = [
    ["HAL_GoAttInf","GoAttInf.sqf","GoAttInf"],
    ["HAL_GoRecon","GoRecon.sqf","GoRecon"],
    ["HAL_GoCapture","GoCapture.sqf","GoCapture"],
    ["HAL_GoRest","GoRest.sqf","GoRest"],
    ["HAL_GoAttSniper","GoAttSniper.sqf","GoAttSniper"],
    ["HAL_GoFlank","GoFlank.sqf","GoFlank"],
    ["HAL_GoSFAttack","GoSFAttack.sqf","GoSFAttack"]
];

ITW_CLASH_HALUnload_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-unload-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL UNLOAD | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["hal-unload",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

/*
    EVERY group riding in this aircraft, not just the first one found.

    Hark: "alpha 2-5 has two different groups in his helo, hes just sitting
    there forever."

    fnc_CargoGroup returns one group - the stamped one, or the first
    passenger's - and fnc_Unload acted on that one alone. HALParadrop_fnc_Execute
    is the same shape: it drops whatever is in ITW_CLASH_HALParadropCargoGroup
    and nothing else. So with two squads aboard, one gets out and the other
    rides home, or sits in a carrier that has already finished its job.

    HAL is entitled to put more than one group in a carrier. The single-group
    assumption was this layer's, not HAL's, and it is the kind that fails
    silently: nothing in the RPT said there were two, which is why the first
    evidence of it was Hark watching an aircraft do nothing.
*/
ITW_CLASH_HALUnload_fnc_CargoGroups = {
    params ["_carrierGroup","_carrier"];
    if (isNull _carrierGroup || {isNull _carrier}) exitWith {[]};
    private _groups = [];
    {
        private _unit = _x;
        if (!alive _unit) then {continue};
        if !(_unit isKindOf "CAManBase") then {continue};
        private _group = group _unit;
        if (isNull _group || {_group isEqualTo _carrierGroup}) then {continue};
        // Riding, not manning a turret.
        private _role = (assignedVehicleRole _unit) param [0,""];
        if (_role in ["Driver","Turret"]) then {continue};
        _groups pushBackUnique _group;
    } forEach (crew _carrier);

    // The stamped group counts even if it is still boarding, so a lift that
    // was planned for it does not lose it to a straggler ordering.
    private _stamped = _carrierGroup getVariable [
        "ITW_CLASH_HALUnloadCargoGroup",grpNull
    ];
    if (!isNull _stamped && {!(_stamped in _groups)} && {
        ((units _stamped) findIf {alive _x && {vehicle _x == _carrier}}) >= 0
    }) then {_groups pushBack _stamped};

    _groups
};

ITW_CLASH_HALUnload_fnc_CargoGroup = {
    params ["_carrierGroup","_carrier"];
    if (isNull _carrierGroup || {isNull _carrier}) exitWith {grpNull};

    private _stamped = _carrierGroup getVariable [
        "ITW_CLASH_HALUnloadCargoGroup",grpNull
    ];
    if (
        !isNull _stamped
        && {((units _stamped) findIf {
            alive _x && {vehicle _x == _carrier}
        }) >= 0}
    ) exitWith {_stamped};

    private _passengers = (crew _carrier) select {
        alive _x
        && {_x isKindOf "CAManBase"}
        && {group _x isNotEqualTo _carrierGroup}
    };
    if (_passengers isEqualTo []) exitWith {grpNull};
    group (_passengers#0)
};

/*
    Register the role relationship immediately, but stamp the pickup origin only
    when physical boarding actually happens. This observer owns no movement.
    It exists solely because HAL can build the destination order while the
    chalk is still walking to the aircraft.
*/
ITW_CLASH_HALUnload_fnc_TrackLift = {
    params ["_carrierGroup","_carrier","_cargoGroup",["_orderFile","UNKNOWN"]];
    if (
        isNull _carrierGroup
        || {isNull _carrier}
        || {isNull _cargoGroup}
    ) exitWith {false};

    _carrierGroup setVariable ["ITW_CLASH_HALUnloadCargoGroup",_cargoGroup];

    // A new lift. Whatever an earlier one left on this group is not its state:
    // the serial retires any watcher still running, and the phase tells the
    // seam that nothing has claimed this unload yet.
    private _serial = (_carrierGroup getVariable ["ITW_CLASH_HALUnloadSerial",0]) + 1;
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadSerial",_serial];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadPhase","TRANSIT"];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadRoll",nil];
    [_carrierGroup] call ITW_CLASH_HALUnload_fnc_ClearDropState;

    [_carrierGroup,_carrier,_cargoGroup,_orderFile,_serial] spawn {
        params ["_carrierGroup","_carrier","_cargoGroup","_orderFile","_serial"];
        private _deadline = time + 300;
        waitUntil {
            sleep 0.2;
            isNull _carrierGroup
            || {isNull _carrier}
            || {!alive _carrier}
            || {isNull _cargoGroup}
            || {time >= _deadline}
            || {
                ((units _cargoGroup) findIf {
                    alive _x && {vehicle _x == _carrier}
                }) >= 0
            }
        };
        if (
            !isNull _carrierGroup
            && {!isNull _carrier}
            && {alive _carrier}
            && {!isNull _cargoGroup}
            && {
                ((units _cargoGroup) findIf {
                    alive _x && {vehicle _x == _carrier}
                }) >= 0
            }
        ) then {
            _carrierGroup setVariable [
                "ITW_CLASH_HALUnloadOrigin",getPosATL _carrier
            ];
            /*
                The run-in owns the approach when it is on: it sets drop height
                itself, about a kilometre out, and only on a lift that is going
                to drop. The en-route climb below is the v4 approach and runs
                only when the run-in is switched off, so the two never both
                ask the same aircraft for a height.
            */
            if (ITW_CLASH_HALUnloadRunIn) exitWith {
                [_carrierGroup,_carrier,_cargoGroup,_orderFile,_serial] spawn
                    ITW_CLASH_HALUnload_fnc_RunIn;
            };
            /*
                Climb now, not over the objective.

                This spawn already waits for the chalk to be physically
                aboard, which is where the transit actually begins, so it is
                the earliest honest place to ask for drop altitude. The mode
                is not known yet - that is decided at the seam, by design -
                but every mode is served by it: PARADROP drops from here,
                HOT_PARADROP climbs the rest of the way at the seam instead of
                from HAL's transit height, and LAND simply descends as before.
            */
            if (ITW_CLASH_HALUnloadClimbEnRoute) then {
                [_carrier,_cargoGroup] spawn {
                    params ["_carrier","_cargoGroup"];
                    private _height = missionNamespace getVariable [
                        "ITW_CLASH_HALParadrop_MinAltitude",45
                    ];
                    private _destination = if (
                        isNil "ITW_CLASH_HotDrop_fnc_Destination"
                    ) then {[]} else {
                        [_carrier] call ITW_CLASH_HotDrop_fnc_Destination
                    };
                    // No destination to measure against: climb now, which is
                    // the behaviour this replaced.
                    if (_destination isEqualTo []) exitWith {
                        _carrier flyInHeight _height;
                    };

                    private _total = (getPosATL _carrier) distance2D _destination;
                    private _trigger = (_total * ITW_CLASH_HALUnloadClimbFraction) max 400;
                    if (_total <= _trigger) exitWith {_carrier flyInHeight _height};

                    private _deadline = time + 600;
                    waitUntil {
                        sleep 1;
                        !alive _carrier
                        || {!canMove _carrier}
                        || {time >= _deadline}
                        || {((units _cargoGroup) findIf {
                            alive _x && {vehicle _x == _carrier}
                        }) < 0}
                        || {(getPosATL _carrier) distance2D _destination <= _trigger}
                    };
                    if (alive _carrier && {canMove _carrier}) then {
                        _carrier flyInHeight _height;
                        ["climb",[
                            typeOf _carrier,round _total,round _trigger,_height
                        ]] call ITW_CLASH_HALUnload_fnc_Log;
                    };
                };
            };
        };
    };
    true
};

ITW_CLASH_HALUnload_fnc_Commander = {
    params ["_cargoGroup","_carrierGroup"];
    private _hq = grpNull;
    if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup" && {!isNull _cargoGroup}) then {
        _hq = [_cargoGroup] call ITW_CLASH_fnc_GetCommanderForGroup;
    };
    if (
        isNull _hq
        && {!isNil "ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup"}
        && {!isNull _cargoGroup}
    ) then {
        _hq = [_cargoGroup] call ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup;
    };
    if (
        isNull _hq
        && {!isNil "ITW_CLASH_fnc_GetCommanderForGroup"}
        && {!isNull _carrierGroup}
    ) then {
        _hq = [_carrierGroup] call ITW_CLASH_fnc_GetCommanderForGroup;
    };
    _hq
};

ITW_CLASH_HALUnload_fnc_Corridor = {
    // _destination is the drop zone when the question is asked on the run-in.
    // At the seam it is omitted, and the aircraft is standing on the answer.
    params ["_hq","_carrierGroup","_carrier",["_destination",[]]];
    private _fallback = createHashMapFromArray [
        ["state","COLD"],["reason","unload-corridor-unavailable"]
    ];
    if (
        isNull _hq
        || {isNull _carrierGroup}
        || {isNull _carrier}
        || {isNil "ITW_CLASH_AirPicture_fnc_ClassifyCorridor"}
    ) exitWith {_fallback};

    // SCargo records the transport's departure point on the carrier group.
    // That gives the execution-time classifier the real flown corridor without
    // adding a second route owner or caching startup base coordinates.
    private _origin = _carrierGroup getVariable ["ITW_CLASH_HALUnloadOrigin",[]];
    if (_origin isEqualTo []) then {
        _origin = _carrierGroup getVariable ["START" + str _carrierGroup,[]];
    };
    if !(_destination isEqualType [] && {count _destination >= 2}) then {
        _destination = getPosATL _carrier;
    };
    if (_origin isEqualTo [] || {_destination isEqualTo []}) exitWith {_fallback};

    [_hq,_origin,_destination] call ITW_CLASH_AirPicture_fnc_ClassifyCorridor
};

ITW_CLASH_HALUnload_fnc_Mode = {
    params ["_carrier",["_state","COLD"],["_carrierGroup",grpNull]];

    private _param = missionNamespace getVariable ["ITW_ParamHelisUnload",50];
    if !(_param isEqualType 0) then {_param = 50};

    private _capacity = 0;
    if (!isNil "ITW_CLASH_HALParadrop_fnc_CargoCapacity") then {
        _capacity = [_carrier] call ITW_CLASH_HALParadrop_fnc_CargoCapacity;
    };

    private _noLand = _state in ["HOT","AIR_DENIED","UNKNOWN"];

    // Preflight refuses these combinations before a helicopter is selected.
    // Re-check here because the air picture can worsen while a committed lift
    // is airborne. In that case HAL keeps the aircraft and its passengers;
    // C.L.A.S.H. only refuses to put the airframe on the ground forward.
    if (_param == 0) exitWith {
        [if (_noLand) then {"NO_LAND"} else {"LAND"},0,_capacity]
    };

    private _dropReady =
        missionNamespace getVariable ["ITW_CLASH_HALParadropReady",false]
        && {!isNil "ITW_CLASH_HALParadrop_fnc_Execute"};
    if (!_dropReady || {isNull _carrier} || {!(_carrier isKindOf "Helicopter")}) exitWith {
        ["LAND",0,_capacity]
    };

    if (_state in ["HOT","AIR_DENIED"]) exitWith {
        ["HOT_PARADROP",100,_capacity]
    };
    if (_state in ["CONTESTED","UNKNOWN"]) exitWith {
        ["PARADROP",100,_capacity]
    };

    if (isNil "ITW_CLASH_HALParadrop_fnc_ShouldUse") exitWith {
        ["LAND",0,_capacity]
    };
    /*
        One roll per lift.

        A quiet corridor is decided by chance, and the question is now asked
        twice: on the run-in, and again at the seam if the run-in left the lift
        alone. Two rolls could disagree, and a lift told LAND a kilometre out
        would then be told PARADROP on arrival, which is the v4 hover. The
        first answer is kept on the carrier group and TrackLift clears it for
        the next lift. Corridor doctrine above is not chance and is still read
        fresh every time.
    */
    private _roll = if (isNull _carrierGroup) then {[]} else {
        _carrierGroup getVariable ["ITW_CLASH_HALUnloadRoll",[]]
    };
    if (_roll isEqualTo []) then {
        _roll = [_carrier,false] call ITW_CLASH_HALParadrop_fnc_ShouldUse;
        if (!isNull _carrierGroup) then {
            _carrierGroup setVariable ["ITW_CLASH_HALUnloadRoll",_roll];
        };
    };
    _roll params ["_drop","_chance","_resolvedCapacity"];
    [if (_drop) then {"PARADROP"} else {"LAND"},_chance,_resolvedCapacity]
};

ITW_CLASH_HALUnload_fnc_Release = {
    params ["_carrierGroup","_carrier"];
    if (!isNil "ITW_CLASH_HALParadrop_fnc_ReleaseCarrier") exitWith {
        [_carrierGroup,_carrier] call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier
    };
    // Best possible fail-open on an older mission/newer addon combination.
    // There is nobody safe to wait on without the canonical helper.
    false
};

ITW_CLASH_HALUnload_fnc_Aboard = {
    params ["_carrier","_cargoGroup"];
    if (isNull _carrier || {isNull _cargoGroup}) exitWith {[]};
    (units _cargoGroup) select {alive _x && {vehicle _x == _carrier}}
};

/*
    HOT_PARADROP still does not become a second en-route pilot.

    HAL owns the lift all the way to its insertion seam. At that seam the
    centralized unload owner is allowed to replace HAL's now-finished waypoint
    with the same terminal fly-through continuation used by PARADROP. This flare
    helper itself owns no movement; it only dispenses countermeasures while the
    carrier follows that continuation.
*/
ITW_CLASH_HALUnload_fnc_StartHotFlares = {
    params ["_carrier","_cargoGroup"];
    if (
        isNull _carrier
        || {isNull _cargoGroup}
        || {isNil "ITW_CLASH_HotDrop_fnc_Flare"}
    ) exitWith {false};

    private _state = createHashMapFromArray [
        ["vehicle",_carrier],
        ["phase","POPUP"],
        ["countermeasureEmitter",
            if (isNil "ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter") then {[]} else {
                [_carrier] call ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter
            }
        ]
    ];
    if (!isNil "ITW_CLASH_ThunderRun_fnc_InitFlareBudget") then {
        [_state] call ITW_CLASH_ThunderRun_fnc_InitFlareBudget;
    };

    [_state,_carrier,_cargoGroup] spawn {
        params ["_state","_carrier","_cargoGroup"];
        private _deadline = time + (
            missionNamespace getVariable ["ITW_CLASH_HALParadrop_ClimbTimeout",45]
        );
        while {
            alive _carrier
            && {canMove _carrier}
            && {time < _deadline}
            && {([_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_Aboard) isNotEqualTo []}
        } do {
            [_state,"POPUP"] call ITW_CLASH_HotDrop_fnc_Flare;
            sleep 0.5;
        };
    };
    true
};

/*
    Arm the drop run BEFORE anyone leaves the aircraft.

    Native ITW gets the important physical behaviour right: the carrier is
    already flying THROUGH the drop when the first parachute opens. Our old
    sequence deleted HAL's insertion waypoint, ran the whole unload, and only
    then invented an escape route. That briefly left the helicopter with no
    forward destination in the hottest part of the flight.

    This function owns only the post-HAL continuation. HAL has reached its
    insertion seam and its waypoint statement is being retired. We replace that
    finished waypoint with one straight-through MOVE waypoint, preserve full
    speed, and let the existing paradrop helper eject passengers while the
    aircraft is still travelling toward it.

    The lateral break and RTB are appended by fnc_Egress after the chalk is
    clear. That ordering prevents the AI from beginning its turn while troops
    are still leaving the aircraft.
*/
ITW_CLASH_HALUnload_fnc_PrepareDropRun = {
    params ["_carrierGroup","_carrier",["_origin",[]]];
    if (!ITW_CLASH_HALUnloadFlyThrough) exitWith {false};
    if (isNull _carrierGroup || {isNull _carrier} || {!alive _carrier}) exitWith {false};
    if (!canMove _carrier) exitWith {false};
    if ((crew _carrier) findIf {isPlayer _x} >= 0) exitWith {false};

    private _here = getPosATL _carrier;
    private _bearing = if (
        _origin isEqualType []
        && {count _origin >= 2}
        && {(_origin distance2D _here) > 50}
    ) then {
        _origin getDir _here
    } else {
        getDir _carrier
    };
    private _through = _here getPos [
        ITW_CLASH_HALUnloadEgressThrough,_bearing
    ];

    _carrier land "NONE";
    _carrier limitSpeed 1e10;
    _carrier forceSpeed -1;

    if (!isNil "ITW_CLASH_fnc_ClearGroupWaypoints") then {
        [_carrierGroup] call ITW_CLASH_fnc_ClearGroupWaypoints;
    } else {
        {deleteWaypoint _x} forEachReversed waypoints _carrierGroup;
    };
    _carrierGroup setBehaviourStrong "CARELESS";
    _carrierGroup setCombatMode "BLUE";
    _carrierGroup setSpeedMode "FULL";

    private _wp = _carrierGroup addWaypoint [_through,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 120;

    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropRunArmed",true];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropBearing",_bearing];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropThrough",_through];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropPoint",_here];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropStarted",time];

    ["drop-run-armed",[
        typeOf _carrier,groupId _carrierGroup,
        round _bearing,
        round (_here distance2D _through),
        round speed _carrier,
        round ((getPosATL _carrier)#2)
    ]] call ITW_CLASH_HALUnload_fnc_Log;
    true
};

/*
    A prepared fly-through must not survive a decision to land instead.

    The normal paradrop failure path can still fall back to GET OUT on a safe
    corridor. Clear the continuation waypoint first so the landing command is
    not fighting a 1 km MOVE order.
*/
ITW_CLASH_HALUnload_fnc_CancelDropRun = {
    params ["_carrierGroup","_carrier",["_reason","cancelled"]];
    if (isNull _carrierGroup) exitWith {false};
    if !(_carrierGroup getVariable ["ITW_CLASH_HALUnloadDropRunArmed",false]) exitWith {false};

    if (!isNil "ITW_CLASH_fnc_ClearGroupWaypoints") then {
        [_carrierGroup] call ITW_CLASH_fnc_ClearGroupWaypoints;
    } else {
        {deleteWaypoint _x} forEachReversed waypoints _carrierGroup;
    };

    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropRunArmed",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropBearing",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropThrough",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropPoint",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropStarted",nil];

    ["drop-run-cancelled",[
        if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
        groupId _carrierGroup,_reason
    ]] call ITW_CLASH_HALUnload_fnc_Log;
    true
};

/*
    Finish the J-hook AFTER the drop.

    The straight-through waypoint already exists while passengers are leaving.
    Once the chalk is clear, append a lateral break and then home. A legacy or
    failed-preparation path still gets a complete through/break/home route here.

    This is not C.L.A.S.H. becoming a second pilot. HAL has already finished
    this insertion and its waypoint was retired by the order statement. These
    are ordinary waypoints, so HAL's next dispatch can replace them cleanly.
*/
ITW_CLASH_HALUnload_fnc_Egress = {
    params ["_carrierGroup","_carrier",["_origin",[]]];
    if (!ITW_CLASH_HALUnloadEgress) exitWith {false};
    if (isNull _carrierGroup || {isNull _carrier} || {!alive _carrier}) exitWith {false};
    if (!canMove _carrier) exitWith {false};
    if ((crew _carrier) findIf {isPlayer _x} >= 0) exitWith {false};

    private _here = getPosATL _carrier;
    private _prepared = _carrierGroup getVariable [
        "ITW_CLASH_HALUnloadDropRunArmed",false
    ];
    private _bearing = _carrierGroup getVariable [
        "ITW_CLASH_HALUnloadDropBearing",-1
    ];
    private _through = _carrierGroup getVariable [
        "ITW_CLASH_HALUnloadDropThrough",[]
    ];
    private _dropPoint = _carrierGroup getVariable [
        "ITW_CLASH_HALUnloadDropPoint",_here
    ];
    private _started = _carrierGroup getVariable [
        "ITW_CLASH_HALUnloadDropStarted",-1
    ];

    if (_bearing < 0) then {
        _bearing = if (
            _origin isEqualType []
            && {count _origin >= 2}
            && {(_origin distance2D _here) > 50}
        ) then {_origin getDir _here} else {getDir _carrier};
    };
    if !(_through isEqualType [] && {count _through >= 2}) then {
        _through = _here getPos [
            ITW_CLASH_HALUnloadEgressThrough,_bearing
        ];
        _prepared = false;
    };

    private _side = if (
        (_carrier call BIS_fnc_netId) select [0,1] in ["1","3","5","7","9"]
    ) then {90} else {-90};
    private _break = _through getPos [
        ITW_CLASH_HALUnloadEgressOffset,_bearing + _side
    ];
    private _home = if (
        _origin isEqualType [] && {count _origin >= 2}
    ) then {_origin} else {_break};

    _carrier land "NONE";
    _carrier flyInHeight ITW_CLASH_HALUnloadTransitHeight;
    _carrier limitSpeed 1e10;
    _carrier forceSpeed -1;

    // A prepared run already owns the straight-through waypoint. Only the
    // fallback path has to manufacture it here.
    if (!_prepared) then {
        if (!isNil "ITW_CLASH_fnc_ClearGroupWaypoints") then {
            [_carrierGroup] call ITW_CLASH_fnc_ClearGroupWaypoints;
        } else {
            {deleteWaypoint _x} forEachReversed waypoints _carrierGroup;
        };
    };
    _carrierGroup setBehaviourStrong "CARELESS";
    _carrierGroup setCombatMode "BLUE";
    _carrierGroup setSpeedMode "FULL";

    if (!_prepared) then {
        private _wpThrough = _carrierGroup addWaypoint [_through,0];
        _wpThrough setWaypointType "MOVE";
        _wpThrough setWaypointSpeed "FULL";
        _wpThrough setWaypointBehaviour "CARELESS";
        _wpThrough setWaypointCombatMode "BLUE";
        _wpThrough setWaypointCompletionRadius 120;
    };

    {
        _x params ["_pos","_radius"];
        private _wp = _carrierGroup addWaypoint [_pos,0];
        _wp setWaypointType "MOVE";
        _wp setWaypointSpeed "FULL";
        _wp setWaypointBehaviour "CARELESS";
        _wp setWaypointCombatMode "BLUE";
        _wp setWaypointCompletionRadius _radius;
    } forEach [[_break,150],[_home,200]];

    // Where the handback gives the aircraft back to SCargo.
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadBreak",_break];

    private _dwell = if (_started >= 0) then {time - _started} else {-1};
    ["egress",[
        typeOf _carrier,groupId _carrierGroup,_prepared,
        round _bearing,_side,
        round (_dropPoint distance2D _through),
        round (_through distance2D _break),
        round (_here distance2D _home),
        round speed _carrier,
        round ((getPosATL _carrier)#2),
        round _dwell
    ]] call ITW_CLASH_HALUnload_fnc_Log;

    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropRunArmed",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropBearing",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropThrough",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropPoint",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropStarted",nil];
    true
};

// One format for the line that answers the whole insertion question, whichever
// path wrote it. _via says which: the seam, or the run-in.
ITW_CLASH_HALUnload_fnc_LiftLine = {
    params [
        "_cargoGroup","_carrier","_orderFile","_param","_state","_mode",
        "_result","_reason","_chance","_capacity",["_via","seam"]
    ];
    private _group = if (isNull _cargoGroup) then {"<none>"} else {groupId _cargoGroup};
    private _aircraft = if (isNull _carrier) then {"<null>"} else {typeOf _carrier};
    diag_log format [
        "CLASH HAL UNLOAD | lift | group=%1 aircraft=%2 order=%3 param=%4 corridor=%5 mode=%6 result=%7 reason=%8 chance=%9 capacity=%10 via=%11",
        _group,_aircraft,_orderFile,_param,_state,_mode,_result,_reason,_chance,_capacity,_via
    ];
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["hal-unload","lift",[
            _group,_aircraft,_orderFile,_param,_state,_mode,_result,_reason,
            _chance,_capacity,_via
        ]] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
    true
};

ITW_CLASH_HALUnload_fnc_ClearDropState = {
    params ["_carrierGroup"];
    if (isNull _carrierGroup) exitWith {false};
    {
        _carrierGroup setVariable [_x,nil];
    } forEach [
        "ITW_CLASH_HALUnloadDropRunArmed",
        "ITW_CLASH_HALUnloadDropBearing",
        "ITW_CLASH_HALUnloadDropThrough",
        "ITW_CLASH_HALUnloadDropPoint",
        "ITW_CLASH_HALUnloadDropStarted",
        "ITW_CLASH_HALUnloadDropZone",
        "ITW_CLASH_HALUnloadDropRadius",
        "ITW_CLASH_HALUnloadBreak"
    ];
    true
};

/*
    Who owns this unload: the run-in, or the seam.

    Two threads can reach the same aircraft. The run-in watcher is one. HAL's
    waypoint statement, which spawns fnc_Unload, is the other, and it fires
    whenever the engine decides the waypoint is complete. Whichever gets there
    first has to be the only one that acts.

    Phases, on the carrier group:

        TRANSIT   tracked, nothing decided              (TrackLift)
        RUN_IN    HAL's waypoint is at the through point (run-in)
        DROPPING  the chalk is going out                 (run-in)
        DROPPED   the run-in finished the lift           (run-in)
        SEAM      fnc_Unload has it                      (seam)

    The move is made inside isNil, which the scheduler cannot interrupt, so a
    check and its write are one step. A script is otherwise free to be paused
    between any two statements, sleep or no sleep.
*/
ITW_CLASH_HALUnload_fnc_Claim = {
    params ["_carrierGroup","_from","_to"];
    private _was = "";
    private _ok = false;
    if (isNull _carrierGroup) exitWith {[false,_was]};
    isNil {
        _was = _carrierGroup getVariable ["ITW_CLASH_HALUnloadPhase",""];
        if (_was in _from) then {
            _carrierGroup setVariable ["ITW_CLASH_HALUnloadPhase",_to];
            _ok = true;
        };
    };
    [_ok,_was]
};

/*
    HAL's outbound waypoint, found by what it does and not by where it sits.

    PatchSource writes the statement, so the statement names this module. The
    index is not stored: HAL deletes waypoint 0 from inside its own statements
    and every later index moves when it does.
*/
ITW_CLASH_HALUnload_fnc_HALWaypoint = {
    params ["_carrierGroup"];
    if (isNull _carrierGroup) exitWith {[]};
    private _found = [];
    {
        private _statement = (waypointStatements _x) param [1,""];
        if ((_statement find "ITW_CLASH_HALUnload_fnc_Unload") >= 0) exitWith {
            _found = _x;
        };
    } forEach (waypoints _carrierGroup);
    _found
};

/*
    How far short of the drop zone the first jumper leaves.

    ITW_AtkParachute spaces jumpers by speed, 40/kph seconds each, held between
    0.1 and 0.5 (ITW_Attack.sqf:4228). Between 80 and 400 km/h that is one
    jumper every 11 m of track whatever the speed, so the stick is about 11 m
    per man. Each chute opens 30 m behind the aircraft (modelToWorld
    [7,-30,-20]). Half the stick, less those 30 m, plus half a second of flight
    for this watcher's poll and the paradrop owner's first look, centres the
    stick on the point HAL chose.

    It is an estimate. moveOut takes frames that the arithmetic does not see,
    so the real stick runs longer than this. The release line in the RPT
    carries the planned lead and the distances actually flown, and
    ITW_CLASH_HALUnloadReleaseBias moves it.
*/
ITW_CLASH_HALUnload_fnc_StickLead = {
    params ["_carrier","_jumpers"];
    private _kph = (speed _carrier) max 1;
    private _mps = _kph / 3.6;
    private _interval = (0.1 max (40 / _kph)) min 0.5;
    private _stick = _jumpers * _interval * _mps;
    (((_stick / 2) - 30 + (_mps * 0.5) + ITW_CLASH_HALUnloadReleaseBias) max 0) min 300
};

/*
    Arm the run-in: HAL's own waypoint, moved past the drop zone.

    Nothing is deleted and nothing is added. HAL's carrier wait counts
    waypoints and still counts one. HAL's statement is still on it and still
    fires, at the through point now, where fnc_Unload finds the lift already
    finished. If anything after this goes wrong, the aircraft is flying a
    waypoint HAL wrote, with HAL's unload on the end of it.

    The move is the last line on purpose. Everything before it only sets
    height, speed and bookkeeping, so a fault part way through leaves the
    waypoint where HAL put it and the seam handles the lift as it did in v4.
*/
ITW_CLASH_HALUnload_fnc_ArmRunIn = {
    params ["_carrierGroup","_carrier","_dropZone","_mode"];
    if (isNull _carrierGroup || {isNull _carrier} || {!alive _carrier}) exitWith {false};
    if (!canMove _carrier) exitWith {false};
    if ((crew _carrier) findIf {isPlayer _x} >= 0) exitWith {false};
    if !(_dropZone isEqualType [] && {count _dropZone >= 2}) exitWith {false};

    private _wp = [_carrierGroup] call ITW_CLASH_HALUnload_fnc_HALWaypoint;
    if (_wp isEqualTo []) exitWith {false};

    private _here = getPosATL _carrier;
    // The line the aircraft is already flying, carried on through the point.
    private _bearing = if ((_here distance2D _dropZone) > 50) then {
        _here getDir _dropZone
    } else {
        getDir _carrier
    };
    private _through = _dropZone getPos [
        ITW_CLASH_HALUnloadEgressThrough,_bearing
    ];
    private _height = if (_mode isEqualTo "HOT_PARADROP") then {
        missionNamespace getVariable ["ITW_CLASH_HotDropDropHeight",130]
    } else {
        missionNamespace getVariable ["ITW_CLASH_HALParadrop_MinAltitude",45]
    };

    _carrier land "NONE";
    _carrier flyInHeight _height;
    _carrier limitSpeed 1e10;
    _carrier forceSpeed -1;
    _carrierGroup setBehaviourStrong "CARELESS";
    _carrierGroup setCombatMode "BLUE";
    _carrierGroup setSpeedMode "FULL";

    // The names fnc_Egress already reads, so it appends the break and home to
    // this run exactly as it does to one armed at the seam.
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropRunArmed",true];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropBearing",_bearing];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropThrough",_through];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropPoint",_dropZone];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropStarted",time];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropZone",_dropZone];
    _carrierGroup setVariable [
        "ITW_CLASH_HALUnloadDropRadius",waypointCompletionRadius _wp
    ];

    ["run-in-armed",[
        typeOf _carrier,groupId _carrierGroup,_mode,
        round _bearing,
        round (_here distance2D _dropZone),
        round speed _carrier,
        round (_here#2),
        _height
    ]] call ITW_CLASH_HALUnload_fnc_Log;

    _wp setWaypointCompletionRadius 120;
    _wp setWaypointPosition [_through,0];
    true
};

/*
    Give HAL its waypoint back.

    A pass that did not drop, with the chalk still aboard, is not finished and
    is not this module's to finish any other way. The waypoint goes back to the
    drop zone HAL chose and the seam takes the lift when the aircraft gets
    there: the v4 behaviour, hover and all, which is the worst this can do.
*/
ITW_CLASH_HALUnload_fnc_AbortRunIn = {
    params ["_carrierGroup","_carrier",["_reason","aborted"]];
    if (isNull _carrierGroup) exitWith {false};

    private _dropZone = _carrierGroup getVariable ["ITW_CLASH_HALUnloadDropZone",[]];
    private _radius = _carrierGroup getVariable ["ITW_CLASH_HALUnloadDropRadius",0];
    private _wp = [_carrierGroup] call ITW_CLASH_HALUnload_fnc_HALWaypoint;
    private _restored = false;
    if (
        _wp isNotEqualTo []
        && {_dropZone isEqualType []}
        && {count _dropZone >= 2}
    ) then {
        _wp setWaypointCompletionRadius _radius;
        _wp setWaypointPosition [_dropZone,0];
        _restored = true;
    };

    [_carrierGroup] call ITW_CLASH_HALUnload_fnc_ClearDropState;
    _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadPhase","TRANSIT"];

    ["run-in-aborted",[
        if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
        groupId _carrierGroup,_reason,_restored
    ]] call ITW_CLASH_HALUnload_fnc_Log;
    _restored
};

/*
    Release the order thread, once per squad that was aboard.

    RYD_Wait clears the flag when it reads it, so one flag ends one wait. Two
    squads in one aircraft are two order threads in two waits on the same
    carrier group, and each needs its own.

    A flag nobody reads is taken back. Left set, it would end the wait of the
    next lift this aircraft flies, on its first poll, with the chalk aboard.
    The serial is the same guard from the other side: if the group has started
    a new lift, this thread has no business writing to it.
*/
ITW_CLASH_HALUnload_fnc_OrderRelease = {
    params ["_carrierGroup","_orders","_serial"];
    private _current = {
        !isNull _carrierGroup
        && {(_carrierGroup getVariable ["ITW_CLASH_HALUnloadSerial",-1]) isEqualTo _serial}
    };
    for "_i" from 1 to (_orders max 1) do {
        if !(call _current) exitWith {};
        _carrierGroup setVariable ["RydHQ_MIA",true];
        private _deadline = time + ITW_CLASH_HALUnloadOrderReleaseWait;
        waitUntil {
            sleep 0.5;
            isNull _carrierGroup
            || {!(_carrierGroup getVariable ["RydHQ_MIA",false])}
            || {time >= _deadline}
        };
        if (!isNull _carrierGroup && {_carrierGroup getVariable ["RydHQ_MIA",false]}) exitWith {
            _carrierGroup setVariable ["RydHQ_MIA",nil];
            ["order-release-unread",[
                groupId _carrierGroup,_i,_orders
            ]] call ITW_CLASH_HALUnload_fnc_Log;
        };
    };
};

ITW_CLASH_HALUnload_fnc_Handback = {
    params ["_carrierGroup","_carrier",["_orderFile","UNKNOWN"],["_orders",1]];
    if (!ITW_CLASH_HALUnloadHandback) exitWith {false};
    if (isNull _carrierGroup) exitWith {false};
    // A player at the controls is not HAL's lift to end.
    if (!isNull _carrier && {(crew _carrier) findIf {isPlayer _x} >= 0}) exitWith {false};

    private _serial = _carrierGroup getVariable ["ITW_CLASH_HALUnloadSerial",-1];
    [_carrierGroup,_carrier,_orderFile,_orders,_serial] spawn {
        params ["_carrierGroup","_carrier","_orderFile","_orders","_serial"];
        scriptName "ITW_CLASH_HALUnload_Handback";
        private _started = time;
        private _atBreak = _orderFile in ITW_CLASH_HALUnloadReleaseAtBreak;

        if (!_atBreak) then {
            [_carrierGroup,_orders,_serial] spawn ITW_CLASH_HALUnload_fnc_OrderRelease;
        };

        private _break = _carrierGroup getVariable ["ITW_CLASH_HALUnloadBreak",[]];
        private _deadline = time + ITW_CLASH_HALUnloadHandbackTimeout;
        private _why = "no-break";
        if (_break isEqualType [] && {count _break >= 2}) then {
            _why = "";
            waitUntil {
                sleep 0.5;
                _why = switch (true) do {
                    case (isNull _carrierGroup): {"group-gone"};
                    case (isNull _carrier): {"carrier-lost"};
                    case (!alive _carrier || {!canMove _carrier}): {"carrier-lost"};
                    case ((_carrier distance2D _break) <= ITW_CLASH_HALUnloadHandbackRadius): {"break"};
                    case (time >= _deadline): {"timeout"};
                    default {""};
                };
                _why isNotEqualTo ""
            };
        };

        if (isNull _carrierGroup) exitWith {};
        if ((_carrierGroup getVariable ["ITW_CLASH_HALUnloadSerial",-1]) isNotEqualTo _serial) exitWith {
            ["handback-superseded",[
                groupId _carrierGroup,_orderFile,_why
            ]] call ITW_CLASH_HALUnload_fnc_Log;
        };

        if (_atBreak) then {
            [_carrierGroup,_orders,_serial] spawn ITW_CLASH_HALUnload_fnc_OrderRelease;
        };

        // SCargo's own exit. It reads this every 5 s and does the rest itself.
        private _busy = _carrierGroup getVariable ["Busy" + str _carrierGroup,false];
        _carrierGroup setVariable ["CargoM" + str _carrierGroup,false];
        _carrierGroup setVariable ["ITW_CLASH_HALUnloadBreak",nil];

        ["handback",[
            if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
            groupId _carrierGroup,_orderFile,_why,
            round (time - _started),
            count (waypoints _carrierGroup),
            _busy,_atBreak,_orders
        ]] call ITW_CLASH_HALUnload_fnc_Log;
    };
    true
};

/*
    The run-in watcher. One per lift, started when the chalk is aboard.

    It reads HAL's waypoint and decides nothing until the aircraft is close.
    Until it arms, it has touched nothing, and any exit before that point is a
    v4 lift.
*/
ITW_CLASH_HALUnload_fnc_RunIn = {
    params ["_carrierGroup","_carrier","_cargoGroup","_orderFile","_serial"];
    scriptName "ITW_CLASH_HALUnload_RunIn";

    private _live = {
        !isNull _carrierGroup
        && {!isNull _carrier}
        && {alive _carrier}
        && {canMove _carrier}
        && {(_carrierGroup getVariable ["ITW_CLASH_HALUnloadSerial",-1]) isEqualTo _serial}
    };
    private _phase = {_carrierGroup getVariable ["ITW_CLASH_HALUnloadPhase",""]};
    private _skip = {
        params ["_why"];
        ["run-in-skipped",[
            if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
            if (isNull _carrierGroup) then {"<null>"} else {groupId _carrierGroup},
            _orderFile,_why
        ]] call ITW_CLASH_HALUnload_fnc_Log;
    };

    // --- transit: wait for HAL's waypoint, then for the run-in distance.
    private _dropZone = [];
    private _seen = false;
    private _seenBy = time + 60;
    private _deadline = time + 900;
    private _stop = "";
    waitUntil {
        sleep 0.5;
        _stop = switch (true) do {
            case (!(call _live)): {"lift-gone"};
            case ((call _phase) isNotEqualTo "TRANSIT"): {"seam-first"};
            case (!_seen && {time >= _seenBy}): {"no-hal-waypoint"};
            case (time >= _deadline): {"transit-timeout"};
            default {""};
        };
        if (_stop isEqualTo "") then {
            private _wp = [_carrierGroup] call ITW_CLASH_HALUnload_fnc_HALWaypoint;
            if (_wp isEqualTo []) then {
                // Not written yet, or already completed and deleted.
                if (_seen) then {_stop = "hal-waypoint-gone"};
            } else {
                // Read every pass. HAL moves this waypoint when it wants an
                // early drop, and the drop zone is wherever HAL has it now.
                private _position = waypointPosition _wp;
                if (_position isNotEqualTo [0,0,0]) then {
                    _dropZone = _position;
                    _seen = true;
                };
            };
        };
        // Airborne as well as close. A short lift is inside the distance while
        // it is still on the pad, and the armed run has a clock on it.
        _stop isNotEqualTo ""
        || {
            _seen
            && {((getPosATL _carrier)#2) > ITW_CLASH_HALUnloadRunInMinHeight}
            && {(_carrier distance2D _dropZone) <= ITW_CLASH_HALUnloadRunInDistance}
        }
    };
    if (_stop isNotEqualTo "") exitWith {[_stop] call _skip};

    // --- decide, with the seam's own owner and table.
    private _cargoGroups = [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_CargoGroups;
    private _primary = [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_CargoGroup;
    if (isNull _primary || {_cargoGroups isEqualTo []}) exitWith {["no-cargo"] call _skip};

    private _hq = [_primary,_carrierGroup] call ITW_CLASH_HALUnload_fnc_Commander;
    private _corridor = [_hq,_carrierGroup,_carrier,_dropZone] call ITW_CLASH_HALUnload_fnc_Corridor;
    private _state = _corridor getOrDefault ["state","COLD"];
    private _reason = _corridor getOrDefault ["reason",""];
    ([_carrier,_state,_carrierGroup] call ITW_CLASH_HALUnload_fnc_Mode) params [
        "_mode","_chance","_capacity"
    ];
    // Any player touching the lift gets stock HAL landing behavior.
    if (
        ((crew _carrier) findIf {isPlayer _x}) >= 0
        || {(_cargoGroups findIf {((units _x) findIf {isPlayer _x}) >= 0}) >= 0}
    ) then {
        _mode = "LAND";
        _reason = _reason + "|player-touch";
    };

    ["run-in",[
        typeOf _carrier,groupId _carrierGroup,_orderFile,_state,_mode,
        round (_carrier distance2D _dropZone),
        round speed _carrier,
        round ((getPosATL _carrier)#2),
        _reason
    ]] call ITW_CLASH_HALUnload_fnc_Log;

    // LAND and NO_LAND are HAL's lift, untouched, to HAL's waypoint.
    if !(_mode in ["PARADROP","HOT_PARADROP"]) exitWith {};

    // --- arm.
    if !(([_carrierGroup,["TRANSIT"],"RUN_IN"] call ITW_CLASH_HALUnload_fnc_Claim)#0) exitWith {
        ["seam-first"] call _skip
    };
    if !([_carrierGroup,_carrier,_dropZone,_mode] call ITW_CLASH_HALUnload_fnc_ArmRunIn) exitWith {
        [_carrierGroup,["RUN_IN"],"TRANSIT"] call ITW_CLASH_HALUnload_fnc_Claim;
        [_carrierGroup] call ITW_CLASH_HALUnload_fnc_ClearDropState;
        ["arm-refused"] call _skip
    };
    if (_mode isEqualTo "HOT_PARADROP") then {
        [_carrier,_primary] call ITW_CLASH_HALUnload_fnc_StartHotFlares;
    };

    // --- fly it. Distance still to run along the approach line: positive
    // short of the drop zone, zero abeam of it, negative past it. Measured
    // along the line and not as a radius, so an aircraft that passes wide
    // still reaches zero, and one that never comes back does not.
    private _bearing = _carrierGroup getVariable ["ITW_CLASH_HALUnloadDropBearing",0];
    private _jumpers = 0;
    {
        _jumpers = _jumpers + count ([_carrier,_x] call ITW_CLASH_HALUnload_fnc_Aboard);
    } forEach _cargoGroups;
    private _along = 1e9;
    private _cross = 0;
    private _lead = 0;
    _deadline = time + ITW_CLASH_HALUnloadRunInTimeout;
    waitUntil {
        sleep 0.1;
        private _here = getPosATL _carrier;
        private _range = _here distance2D _dropZone;
        private _angle = (_here getDir _dropZone) - _bearing;
        _along = _range * cos _angle;
        _cross = abs (_range * sin _angle);
        _lead = [_carrier,_jumpers] call ITW_CLASH_HALUnload_fnc_StickLead;
        !(call _live)
        || {(call _phase) isNotEqualTo "RUN_IN"}
        || {time >= _deadline}
        || {_along <= _lead}
    };

    // From here the run-in either has the unload or has nothing to do with it.
    if !(([_carrierGroup,["RUN_IN"],"DROPPING"] call ITW_CLASH_HALUnload_fnc_Claim)#0) exitWith {
        ["seam-first"] call _skip
    };
    if !(call _live) exitWith {
        _carrierGroup setVariable ["ITW_CLASH_HALUnloadPhase","TRANSIT"];
        ["lift-gone"] call _skip
    };
    if (_along > _lead) exitWith {
        [_carrierGroup,_carrier,"never-crossed"] call ITW_CLASH_HALUnload_fnc_AbortRunIn;
    };
    if (_cross > ITW_CLASH_HALUnloadMaxOffset) exitWith {
        [_carrierGroup,_carrier,"passed-wide"] call ITW_CLASH_HALUnload_fnc_AbortRunIn;
    };

    // --- drop. One pass per group aboard, through the paradrop owner, which
    // is never allowed to land an aircraft that is flying through.
    private _origin = _carrierGroup getVariable ["ITW_CLASH_HALUnloadOrigin",[]];
    private _releasedAt = time;
    private _releaseSpeed = speed _carrier;
    private _releaseHeight = (getPosATL _carrier)#2;
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadDropStarted",_releasedAt];
    _cargoGroups = [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_CargoGroups;
    if (count _cargoGroups > 1) then {
        ["multi-group-lift",[
            typeOf _carrier,groupId _carrierGroup,
            _cargoGroups apply {groupId _x}
        ]] call ITW_CLASH_HALUnload_fnc_Log;
    };
    private _dropped = 0;
    {
        _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_x];
        _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",_origin];
        if ([_carrierGroup,_carrier,false,ITW_CLASH_HALUnloadReleaseWait] call
            ITW_CLASH_HALParadrop_fnc_Execute
        ) then {_dropped = _dropped + 1};
    } forEach _cargoGroups;

    private _aboard = 0;
    {
        _aboard = _aboard + count ([_carrier,_x] call ITW_CLASH_HALUnload_fnc_Aboard);
    } forEach _cargoGroups;

    // Planned against flown, so the lead can be tuned from the log.
    ["release",[
        typeOf _carrier,groupId _carrierGroup,
        round _lead,round _along,round _cross,
        round _releaseSpeed,round _releaseHeight,
        _jumpers,_dropped,_aboard,
        round ((getPosATL _carrier) distance2D _dropZone),
        (round ((time - _releasedAt) * 10)) / 10
    ]] call ITW_CLASH_HALUnload_fnc_Log;

    // Nobody out and the chalk still aboard: not a drop. HAL gets its
    // waypoint back and the seam finishes the lift.
    if (_dropped == 0 && {_aboard > 0}) exitWith {
        [_carrierGroup,_carrier,"drop-declined"] call ITW_CLASH_HALUnload_fnc_AbortRunIn;
    };

    _carrierGroup setVariable ["ITW_CLASH_HALUnloadPhase","DROPPED"];
    private _result = if (_dropped > 0) then {_mode} else {_mode + "_DECLINED_EMPTY"};

    [_carrierGroup,_carrier,_origin] call ITW_CLASH_HALUnload_fnc_Egress;
    [_carrierGroup,_carrier,_orderFile,count _cargoGroups] call ITW_CLASH_HALUnload_fnc_Handback;

    _carrierGroup setVariable ["ITW_CLASH_HALUnloadCargoGroup",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadOrigin",nil];

    private _param = missionNamespace getVariable ["ITW_ParamHelisUnload",50];
    if !(_param isEqualType 0) then {_param = 50};
    [
        _primary,_carrier,_orderFile,_param,_state,_mode,_result,_reason,
        _chance,_capacity,"run-in"
    ] call ITW_CLASH_HALUnload_fnc_LiftLine;
    _result
};

ITW_CLASH_HALUnload_fnc_Unload = {
    params ["_carrierGroup","_carrier",["_orderFile","UNKNOWN"]];

    /*
        The seam, after the run-in.

        HAL's statement spawns this whenever its waypoint completes. On a lift
        the run-in dropped, that is at the through point, a kilometre past the
        drop zone, with nobody aboard and nothing left to decide. On a lift
        the run-in left alone, or never reached, it is where it always was and
        this is the v4 seam.
    */
    ([
        _carrierGroup,["","TRANSIT","RUN_IN","SEAM"],"SEAM"
    ] call ITW_CLASH_HALUnload_fnc_Claim) params ["_mine","_was"];
    if (!_mine && {!isNull _carrierGroup}) exitWith {
        ["seam-after-run-in",[
            if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
            groupId _carrierGroup,_orderFile,_was
        ]] call ITW_CLASH_HALUnload_fnc_Log;
        "RUN_IN"
    };
    if (_was isEqualTo "RUN_IN") then {
        // Armed, and the waypoint completed before the watcher released.
        // The run is this function's now, from wherever the aircraft is.
        private _dropZone = _carrierGroup getVariable ["ITW_CLASH_HALUnloadDropZone",[]];
        ["seam-took-over",[
            if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
            groupId _carrierGroup,_orderFile,
            if (isNull _carrier || {_dropZone isEqualTo []}) then {-1} else {
                round (_carrier distance2D _dropZone)
            }
        ]] call ITW_CLASH_HALUnload_fnc_Log;
        [_carrierGroup] call ITW_CLASH_HALUnload_fnc_ClearDropState;
    };

    private _param = missionNamespace getVariable ["ITW_ParamHelisUnload",50];
    if !(_param isEqualType 0) then {_param = 50};
    private _cargoGroups = [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_CargoGroups;
    private _cargoGroup = [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_CargoGroup;
    if (count _cargoGroups > 1) then {
        ["multi-group-lift",[
            typeOf _carrier,groupId _carrierGroup,
            _cargoGroups apply {groupId _x}
        ]] call ITW_CLASH_HALUnload_fnc_Log;
    };
    private _result = "NO_CARGO";
    private _state = "COLD";
    private _reason = "no-cargo-group";
    private _mode = "LAND";
    private _chance = 0;
    private _capacity = 0;

    if (!isNull _carrier && {!isNull _cargoGroup}) then {
        private _hq = [_cargoGroup,_carrierGroup] call ITW_CLASH_HALUnload_fnc_Commander;
        private _corridor = [_hq,_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_Corridor;
        _state = _corridor getOrDefault ["state","COLD"];
        _reason = _corridor getOrDefault ["reason",""];

        ([_carrier,_state,_carrierGroup] call ITW_CLASH_HALUnload_fnc_Mode) params [
            "_resolvedMode","_resolvedChance","_resolvedCapacity"
        ];
        _mode = _resolvedMode;
        _chance = _resolvedChance;
        _capacity = _resolvedCapacity;

        // Any player touching the lift gets stock HAL landing behavior.
        if (
            ((crew _carrier) findIf {isPlayer _x}) >= 0
            || {((units _cargoGroup) findIf {isPlayer _x}) >= 0}
        ) then {
            _mode = "LAND";
            _reason = _reason + "|player-touch";
        };

        switch (_mode) do {
            case "PARADROP": {
                _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_cargoGroup];
                private _origin = _carrierGroup getVariable ["ITW_CLASH_HALUnloadOrigin",[]];
                _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",_origin];
                _carrier land "NONE";
                _carrier flyInHeight (
                    missionNamespace getVariable ["ITW_CLASH_HALParadrop_MinAltitude",45]
                );
                [_carrierGroup,_carrier,_origin] call
                    ITW_CLASH_HALUnload_fnc_PrepareDropRun;
                private _noLand = _state in ["HOT","AIR_DENIED","UNKNOWN"];
                /*
                    One pass per group aboard. Execute reads the stamp, so the
                    stamp is moved between passes rather than the function being
                    taught about lists - which keeps the paradrop owner's
                    contract unchanged and makes a multi-group lift simply
                    several single-group drops from the same aircraft.
                */
                private _dropped = false;
                {
                    _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_x];
                    if ([_carrierGroup,_carrier,!_noLand] call
                        ITW_CLASH_HALParadrop_fnc_Execute
                    ) then {_dropped = true};
                } forEach _cargoGroups;
                if (_dropped) then {
                    _result = "PARADROP";
                    [_carrierGroup,_carrier,_origin] call ITW_CLASH_HALUnload_fnc_Egress;
                    [_carrierGroup,_carrier,_orderFile,count _cargoGroups] call
                        ITW_CLASH_HALUnload_fnc_Handback
                } else {
                    if (([_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_Aboard) isNotEqualTo []) then {
                        if (_noLand) then {
                            _carrier land "NONE";
                            _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
                            _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",nil];
                            _result = "NO_LAND"
                        } else {
                            [_carrierGroup,_carrier,"land-fallback"] call
                                ITW_CLASH_HALUnload_fnc_CancelDropRun;
                            _carrier land "GET OUT";
                            [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_Release;
                            _result = "LAND_FALLBACK"
                        };
                    } else {
                        _result = "PARADROP_DECLINED_EMPTY"
                    };
                };
            };
            case "HOT_PARADROP": {
                _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_cargoGroup];
                private _origin = _carrierGroup getVariable ["ITW_CLASH_HALUnloadOrigin",[]];
                _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",_origin];
                _carrier land "NONE";
                _carrier flyInHeight (
                    missionNamespace getVariable ["ITW_CLASH_HotDropDropHeight",130]
                );
                [_carrierGroup,_carrier,_origin] call
                    ITW_CLASH_HALUnload_fnc_PrepareDropRun;
                [_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_StartHotFlares;
                private _dropped = false;
                {
                    _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_x];
                    if ([_carrierGroup,_carrier,false] call
                        ITW_CLASH_HALParadrop_fnc_Execute
                    ) then {_dropped = true};
                } forEach _cargoGroups;
                if (_dropped) then {
                    _result = "HOT_PARADROP";
                    [_carrierGroup,_carrier,_origin] call ITW_CLASH_HALUnload_fnc_Egress;
                    [_carrierGroup,_carrier,_orderFile,count _cargoGroups] call
                        ITW_CLASH_HALUnload_fnc_Handback
                } else {
                    if (([_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_Aboard) isNotEqualTo []) then {
                        _carrier land "NONE";
                        _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
                        _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",nil];
                        _result = "NO_LAND"
                    } else {
                        _result = "HOT_PARADROP_DECLINED_EMPTY"
                    };
                };
            };
            case "NO_LAND": {
                _carrier land "NONE";
                _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
                _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",nil];
                _result = "NO_LAND";
            };
            default {
                _carrier land "GET OUT";
                [_carrierGroup,_carrier] call ITW_CLASH_HALUnload_fnc_Release;
                _result = "LAND";
            };
        };
    };

    _carrierGroup setVariable ["ITW_CLASH_HALUnloadCargoGroup",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALUnloadOrigin",nil];

    // One line answers the whole insertion question.
    [
        _cargoGroup,_carrier,_orderFile,_param,_state,_mode,_result,_reason,
        _chance,_capacity,"seam"
    ] call ITW_CLASH_HALUnload_fnc_LiftLine;
    _result
};

ITW_CLASH_HALUnload_fnc_PatchSource = {
    params ["_source","_orderFile"];
    private _anchor = 'if (((group (assigneddriver _AV)) in (_HQ getVariable ["RydHQ_AirG",[]])) and (_unitG in (_HQ getVariable ["RydHQ_NCrewInfG",[]]))) then {_sts = ["true","(vehicle this) land ''GET OUT'';deletewaypoint [(group this), 0]"]};';
    _source = (_source splitString (toString [13])) joinString "";

    private _at = _source find _anchor;
    if (_at < 0) exitWith {
        if ((_source find "ITW_CLASH_HALUnload_fnc_Unload") >= 0) then {
            [true,_source,"already-patched"]
        } else {
            [false,_source,"signature-missing"]
        }
    };
    private _tail = _at + count _anchor;
    if (((_source select [_tail]) find _anchor) >= 0) exitWith {
        [false,_source,"signature-duplicate"]
    };

    private _track =
        "private _cg = group (assigneddriver _AV); "
        + "[_cg,_AV,_unitG," + str _orderFile + "] call ITW_CLASH_HALUnload_fnc_TrackLift; ";

    private _script =
        "private _g = group this; private _v = vehicle this; "
        + "if (isNil ""ITW_CLASH_HALUnload_fnc_Unload"") then {"
        + "_v land ""GET OUT""; "
        + "if (!isNil ""ITW_CLASH_HALParadrop_fnc_ReleaseCarrier"") then {"
        + "[_g,_v] call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier};"
        + "} else {[_g,_v," + str _orderFile + "] spawn ITW_CLASH_HALUnload_fnc_Unload}; "
        + "deletewaypoint [(group this), 0]";

    private _replacement =
        'if (((group (assigneddriver _AV)) in (_HQ getVariable ["RydHQ_AirG",[]])) and (_unitG in (_HQ getVariable ["RydHQ_NCrewInfG",[]]))) then {'
        + _track
        + '_sts = ["true",' + str _script + ']};';

    [
        true,
        (_source select [0,_at]) + _replacement + (_source select [_tail]),
        "patched"
    ]
};

private _finishFailure = {
    params ["_reason",["_details",[]]];
    ITW_CLASH_HALUnloadReady = false;
    diag_log format [
        "CLASH BOOT | WARNING | hal-unload-failed | reason=%1 details=%2 | stock HAL unload retained",
        _reason,_details
    ];
    false
};

// Wait for HAL Additions to publish the exact sources it replaced. This is
// earlier than the recon/service wrappers, so those wrappers capture the
// corrected executor rather than being overwritten by it.
private _deadline = diag_tickTime + 120;
waitUntil {
    sleep 0.05;
    (
        !isNil "RYD_Path"
        && {!isNil "CLASH_HALAdd_SourcePaths"}
        && {!isNil "HAL_GoAttInf"}
        && {!isNil "HAL_GoCapture"}
        && {!isNil "HAL_GoRecon"}
    ) || {diag_tickTime >= _deadline}
};
if (
    isNil "RYD_Path"
    || {isNil "CLASH_HALAdd_SourcePaths"}
    || {isNil "HAL_GoAttInf"}
) exitWith {
    ["hal-runtime-bind-timeout",[]] call _finishFailure
};

private _compiled = createHashMap;
private _sources = [];
private _failure = "";
{
    _x params ["_global","_file","_orderFile"];
    if (_failure isNotEqualTo "") then {continue};

    private _source = "";
    private _sourceLabel = "";
    if (
        _global isEqualTo "HAL_GoSFAttack"
        && {!isNil "ITW_CLASH_HALNativeSF_Source"}
    ) then {
        _source = ITW_CLASH_HALNativeSF_Source;
        _sourceLabel = "native-sf-repaired-source";
    } else {
        private _path = CLASH_HALAdd_SourcePaths getOrDefault [
            _global,
            RYD_Path + "HAL\" + _file
        ];
        _source = preprocessFileLineNumbers _path;
        _sourceLabel = _path;
    };

    if (_source isEqualTo "") then {
        _failure = format ["%1:source-missing",_orderFile];
    } else {
        ([_source,_orderFile] call ITW_CLASH_HALUnload_fnc_PatchSource) params [
            "_ok","_patched","_status"
        ];
        if (!_ok) then {
            _failure = format ["%1:%2",_orderFile,_status];
        } else {
            private _fn = compile _patched;
            if !(_fn isEqualType {}) then {
                _failure = format ["%1:compile-failed",_orderFile];
            } else {
                _compiled set [_global,_fn];
                _sources pushBack [_global,_sourceLabel,_status];
            };
        };
    };
} forEach ITW_CLASH_HALUnloadOrderSpecs;

if (_failure isNotEqualTo "") exitWith {
    [_failure,_sources] call _finishFailure
};

// All seven validated before the first global changes.
{
    _x params ["_global"];
    missionNamespace setVariable [_global,_compiled get _global];
} forEach ITW_CLASH_HALUnloadOrderSpecs;

// HALWaypointGuard may have won the scheduler race and patched these functions
// just before this source-based install. If so, reapply its orthogonal guard.
// If it has not run yet, it will patch the functions above in place later.
if (
    missionNamespace getVariable ["ITW_CLASH_HALWaypointGuardReady",false]
    && {!isNil "ITW_CLASH_HALWaypointGuard_fnc_Patch"}
) then {
    {
        [_x] call ITW_CLASH_HALWaypointGuard_fnc_Patch;
    } forEach ["HAL_GoCapture","HAL_GoRecon","HAL_GoAttInf","HAL_GoRest"];
};

ITW_CLASH_HALUnloadReady = true;
diag_log format [
    "CLASH BOOT | hal-unload-ready | version=%1 sites=%2 executionTime=true oneOwner=true halOwnsFlight=true terminalFlyThrough=%3 through=%4 break=%5 hotDropOwnsMovement=false runIn=%6 runInDistance=%7 handback=%8 sources=%9",
    ITW_CLASH_HALUnloadVersion,
    count ITW_CLASH_HALUnloadOrderSpecs,
    ITW_CLASH_HALUnloadFlyThrough,
    ITW_CLASH_HALUnloadEgressThrough,
    ITW_CLASH_HALUnloadEgressOffset,
    ITW_CLASH_HALUnloadRunIn,
    ITW_CLASH_HALUnloadRunInDistance,
    ITW_CLASH_HALUnloadHandback,
    _sources
];
true
