#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALUnloadStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALUnloadReady",false]
};

ITW_CLASH_HALUnloadStarted = true;
ITW_CLASH_HALUnloadReady = false;
ITW_CLASH_HALUnloadVersion = 3;
scriptName "ITW_CLASH_HALUnload";

/*
    One owner for HAL troop-lift unloads.

    HAL owns whether a squad rides, which carrier is used, and every waypoint.
    This module owns exactly one question when HAL's insertion waypoint fires:
    LAND, PARADROP, or HOT_PARADROP.

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
ITW_CLASH_HALUnloadEgressThrough = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadEgressThrough",700
];
ITW_CLASH_HALUnloadEgressOffset = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadEgressOffset",450
];
ITW_CLASH_HALUnloadTransitHeight = missionNamespace getVariable [
    "ITW_CLASH_HALUnloadTransitHeight",
    missionNamespace getVariable ["ITW_CLASH_HotDropTransitHeight",120]
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
    params ["_carrierGroup","_carrier","_cargoGroup"];
    if (
        isNull _carrierGroup
        || {isNull _carrier}
        || {isNull _cargoGroup}
    ) exitWith {false};

    _carrierGroup setVariable ["ITW_CLASH_HALUnloadCargoGroup",_cargoGroup];

    [_carrierGroup,_carrier,_cargoGroup] spawn {
        params ["_carrierGroup","_carrier","_cargoGroup"];
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
    params ["_hq","_carrierGroup","_carrier"];
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
    private _destination = getPosATL _carrier;
    if (_origin isEqualTo [] || {_destination isEqualTo []}) exitWith {_fallback};

    [_hq,_origin,_destination] call ITW_CLASH_AirPicture_fnc_ClassifyCorridor
};

ITW_CLASH_HALUnload_fnc_Mode = {
    params ["_carrier",["_state","COLD"]];

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
    ([_carrier,false] call ITW_CLASH_HALParadrop_fnc_ShouldUse) params [
        "_drop","_chance","_resolvedCapacity"
    ];
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
    HOT_PARADROP in the rebuild is deliberately not a second pilot.

    It may change altitude and dispense countermeasures, but it never deletes
    HAL waypoints, calls doMove, claims the aircraft, or hands it back. HAL has
    already flown the carrier to its insertion waypoint. The richer low-ingress
    phase remains in the old HotDrop executor until this centralized lifecycle
    earns a green live run; Step 4 can then retire that executor without
    smuggling a second route owner back in.
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
    The J-hook.

    HAL's waypoint is deleted by the waypoint statement before this module is
    even spawned, so after the drop the carrier is a helicopter with no
    destination: it coasts, stops, and hovers over the objective. That is what
    Hark saw, and it is also the worst place in the mission to be stationary.

    So: carry through past the drop on the inbound bearing, bank off to one
    side, then run home. Two waypoints rather than one, because a single
    waypoint back to base makes the aircraft pivot on the spot - the thing that
    reads as a stall - while a through-point turns the exit into one continuous
    motion.

    This is not C.L.A.S.H. becoming a second pilot. The rule that broke run8
    was taking an aircraft HAL was actively flying; here HAL has already
    finished with it and left it with nothing. Waypoints, not doMove, precisely
    so HAL's next dispatch replaces this cleanly through its own machinery - the
    same shape CASEVAC_fnc_SendHeliHome uses to send its airframes home.

    The side it banks to alternates on the carrier's own id, so a pair of
    aircraft working the same objective do not cross.
*/
ITW_CLASH_HALUnload_fnc_Egress = {
    params ["_carrierGroup","_carrier",["_origin",[]]];
    if (!ITW_CLASH_HALUnloadEgress) exitWith {false};
    if (isNull _carrierGroup || {isNull _carrier} || {!alive _carrier}) exitWith {false};
    if (!canMove _carrier) exitWith {false};
    if ((crew _carrier) findIf {isPlayer _x} >= 0) exitWith {false};

    private _here = getPosATL _carrier;
    // Inbound bearing. With no usable origin, carry on the way it is pointing.
    private _bearing = if (
        _origin isEqualType [] && {count _origin >= 2} && {(_origin distance2D _here) > 50}
    ) then {_origin getDir _here} else {getDir _carrier};

    private _side = if ((_carrier call BIS_fnc_netId) select [0,1] in ["1","3","5","7","9"]) then {90} else {-90};
    private _through = _here getPos [ITW_CLASH_HALUnloadEgressThrough,_bearing];
    _through = _through getPos [ITW_CLASH_HALUnloadEgressOffset,_bearing + _side];

    private _home = if (
        _origin isEqualType [] && {count _origin >= 2}
    ) then {_origin} else {_through};

    _carrier land "NONE";
    _carrier flyInHeight ITW_CLASH_HALUnloadTransitHeight;
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

    {
        _x params ["_pos","_radius"];
        private _wp = _carrierGroup addWaypoint [_pos,0];
        _wp setWaypointType "MOVE";
        _wp setWaypointSpeed "FULL";
        _wp setWaypointBehaviour "CARELESS";
        _wp setWaypointCombatMode "BLUE";
        _wp setWaypointCompletionRadius _radius;
    } forEach [[_through,150],[_home,200]];

    ["egress",[
        typeOf _carrier,groupId _carrierGroup,
        round _bearing,_side,
        round (_here distance2D _through),
        round (_here distance2D _home)
    ]] call ITW_CLASH_HALUnload_fnc_Log;
    true
};

ITW_CLASH_HALUnload_fnc_Unload = {
    params ["_carrierGroup","_carrier",["_orderFile","UNKNOWN"]];

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

        ([_carrier,_state] call ITW_CLASH_HALUnload_fnc_Mode) params [
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
                    [_carrierGroup,_carrier,_origin] call ITW_CLASH_HALUnload_fnc_Egress
                } else {
                    if (([_carrier,_cargoGroup] call ITW_CLASH_HALUnload_fnc_Aboard) isNotEqualTo []) then {
                        if (_noLand) then {
                            _carrier land "NONE";
                            _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
                            _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",nil];
                            _result = "NO_LAND"
                        } else {
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
                    [_carrierGroup,_carrier,_origin] call ITW_CLASH_HALUnload_fnc_Egress
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
    diag_log format [
        "CLASH HAL UNLOAD | lift | group=%1 aircraft=%2 order=%3 param=%4 corridor=%5 mode=%6 result=%7 reason=%8 chance=%9 capacity=%10",
        if (isNull _cargoGroup) then {"<none>"} else {groupId _cargoGroup},
        if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
        _orderFile,_param,_state,_mode,_result,_reason,_chance,_capacity
    ];
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["hal-unload","lift",[
            if (isNull _cargoGroup) then {"<none>"} else {groupId _cargoGroup},
            if (isNull _carrier) then {"<null>"} else {typeOf _carrier},
            _orderFile,_param,_state,_mode,_result,_reason,_chance,_capacity
        ]] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
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
        + "[_cg,_AV,_unitG] call ITW_CLASH_HALUnload_fnc_TrackLift; ";

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
    "CLASH BOOT | hal-unload-ready | version=%1 sites=%2 executionTime=true oneOwner=true halOwnsFlight=true hotDropOwnsMovement=false sources=%3",
    ITW_CLASH_HALUnloadVersion,count ITW_CLASH_HALUnloadOrderSpecs,_sources
];
true
