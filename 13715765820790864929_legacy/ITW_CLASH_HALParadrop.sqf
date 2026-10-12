if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALParadropReady",false]) exitWith {true};

ITW_CLASH_HALParadropVersion = 7;
ITW_CLASH_HALParadropReady = false;

ITW_CLASH_HALParadrop_HeavyCargoSeats = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_HeavyCargoSeats",8
];
ITW_CLASH_HALParadrop_HeavyChance = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_HeavyChance",75
];
ITW_CLASH_HALParadrop_ThreatChance = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_ThreatChance",90
];
ITW_CLASH_HALParadrop_MinAltitude = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_MinAltitude",45
];
ITW_CLASH_HALParadrop_FallbackAltitude = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_FallbackAltitude",18
];
// How long to wait for passengers to clear the aircraft before releasing it
// anyway. A bound, not a schedule: it only matters when someone is wounded,
// stuck in a seat, or dies on the way out.
ITW_CLASH_HALParadrop_ReleaseTimeout = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_ReleaseTimeout",60
];
/*
    Never put a squad out where it got in.

    The 8 second altitude wait below assumed the statement fires in the air
    over the drop point. It can fire while the carrier is still on the ground
    at base - and a helicopter cannot reach 55m from a standstill in 8s, so the
    deadline expired at altitude ~0, the low-altitude fallback landed, and eight
    men were dumped back onto the pad they had just been teleported into. Hark
    saw exactly that: "landed at base and kicked them out."

    This is the same fault HotDrop had (troops out over the pickup point) and
    the same cure: require the lift to have actually gone somewhere. The origin
    is stamped when the paradrop is selected, so distance from it is knowable.
*/
ITW_CLASH_HALParadrop_MinRun = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_MinRun",400
];
// Long enough for a climb from the ground, not only for a cruising aircraft.
ITW_CLASH_HALParadrop_ClimbTimeout = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_ClimbTimeout",45
];

ITW_CLASH_HALParadrop_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["hal-paradrop-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH HAL PARADROP | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_HALParadrop_fnc_CargoCapacity = {
    params ["_veh"];
    if (isNull _veh) exitWith {0};

    if (
        missionNamespace getVariable ["ITW_CLASH_ServiceCapacityPolicyReady",false]
        && {!isNil "ITW_CLASH_ServiceCapacity_fnc_ConfigCargoSeats"}
    ) exitWith {
        [typeOf _veh] call ITW_CLASH_ServiceCapacity_fnc_ConfigCargoSeats
    };

    private _cfg = configFile >> "CfgVehicles" >> typeOf _veh;
    if !(isClass _cfg) exitWith {0};
    round getNumber (_cfg >> "transportSoldier")
};

ITW_CLASH_HALParadrop_fnc_ShouldUse = {
    params ["_veh",["_threatened",false]];
    if (isNull _veh || {!(_veh isKindOf "Helicopter")}) exitWith {[false,0,0]};

    private _capacity = [_veh] call ITW_CLASH_HALParadrop_fnc_CargoCapacity;
    private _chance = missionNamespace getVariable ["ITW_ParamHelisUnload",50];
    if !(_chance isEqualType 0) then {_chance = 50};
    if (_chance == 777) then {_chance = selectRandom [0,25,50,75,100]};

    // Respect explicit ITW "land only" (0) and "parachute only" (100)
    // settings. C.L.A.S.H. only biases the mixed modes toward safer drops.
    if (_chance > 0 && {_chance < 100}) then {
        if (_capacity >= ITW_CLASH_HALParadrop_HeavyCargoSeats) then {
            _chance = _chance max ITW_CLASH_HALParadrop_HeavyChance;
        };
        if (_threatened) then {
            _chance = _chance max ITW_CLASH_HALParadrop_ThreatChance;
        };
        if (_threatened && {_capacity >= ITW_CLASH_HALParadrop_HeavyCargoSeats}) then {
            _chance = 100;
        };
    };

    [random 100 < _chance,_chance,_capacity]
};

/*
    Let the helicopter leave once its passengers are out.

    `land "GET OUT"` is sticky: it holds the aircraft on the ground until
    `land "NONE"` cancels it, and a NEW WAYPOINT DOES NOT CANCEL IT. HAL issues
    land 'NONE' in every pickup path (GoAttInf:185, GoCapture:192, GoRecon:234,
    and throughout SCargo) but nowhere after a drop-off, so a carrier that
    lands to unload sits there until some later dispatch happens to re-task it
    through SCargo. That is stock behaviour, and it was invisible for as long
    as the air unload itself was broken - no landing, no stranded helicopter.

    The paradrop path already releases correctly (land "NONE" after
    ITW_AllyParadropCargo). This is the same courtesy for every path that lands
    instead, including this file's own low-altitude fallback.

    Passengers are anyone aboard who is not of the carrier's own crew group, so
    no cargo-group bookkeeping is needed and a squad that was never stamped is
    still handled. Spawned, because a waypoint statement cannot wait.
*/
ITW_CLASH_HALParadrop_fnc_ReleaseCarrier = {
    params ["_carrierGroup","_carrier"];
    if (isNull _carrier) exitWith {false};
    [_carrierGroup,_carrier] spawn {
        params ["_carrierGroup","_carrier"];
        private _deadline = time + ITW_CLASH_HALParadrop_ReleaseTimeout;
        waitUntil {
            sleep 1;
            !alive _carrier
            || {time >= _deadline}
            || {
                ((crew _carrier) select {
                    alive _x && {group _x != _carrierGroup}
                }) isEqualTo []
            }
        };
        if (!alive _carrier) exitWith {};
        _carrier land "NONE";
        ["carrier-released",[
            typeOf _carrier,
            groupId _carrierGroup,
            count ((crew _carrier) select {alive _x && {group _x != _carrierGroup}}),
            time >= _deadline
        ]] call ITW_CLASH_HALParadrop_fnc_Log;
    };
    true
};

ITW_CLASH_HALParadrop_fnc_Execute = {
    /*
        _allowLandFallback defaults TRUE so the two-argument caller
        (HotDrop.sqf:445) keeps the behaviour it has always had. It was added
        to the fallback branch below without being declared here, which made
        `if (!_allowLandFallback)` a read of an undefined local: a type error
        that aborted the exitWith block AND the spawned thread it runs in. No
        land "NONE", no land "GET OUT", no carrier release, the cargo-group
        stamp left on the carrier, and the one-line-per-lift trace in
        HALUnload never reached - the symptom was silence.
    */
    /*
        _climbTimeout bounds the altitude wait below. Omitted, it is
        ITW_CLASH_HALParadrop_ClimbTimeout, which is sized for an aircraft
        standing over the point and climbing from wherever it arrived. A
        caller that releases on a fly-by passes about a second: an aircraft
        crossing the drop zone at speed cannot be asked to wait there.
    */
    params [
        "_carrierGroup","_carrier",
        ["_allowLandFallback",true],["_climbTimeout",-1]
    ];
    if (
        isNull _carrierGroup
        || {isNull _carrier}
        || {!alive _carrier}
        || {!canMove _carrier}
    ) exitWith {
        ["declined",["carrier-gone"]] call ITW_CLASH_HALParadrop_fnc_Log;
        false
    };

    private _cargoGroup = _carrierGroup getVariable [
        "ITW_CLASH_HALParadropCargoGroup",grpNull
    ];
    if (isNull _cargoGroup) exitWith {
        ["declined",["no-cargo-group",typeOf _carrier]] call ITW_CLASH_HALParadrop_fnc_Log;
        false
    };

    private _aboard = units _cargoGroup select {
        alive _x && {vehicle _x == _carrier}
    };
    if (_aboard isEqualTo []) exitWith {
        _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
        _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",nil];
        ["declined",["nobody-aboard",typeOf _carrier,groupId _cargoGroup]] call
            ITW_CLASH_HALParadrop_fnc_Log;
        false
    };

    private _deadline = time + ITW_CLASH_HALParadrop_ClimbTimeout;
    if (_climbTimeout >= 0) then {_deadline = time + _climbTimeout};
    waitUntil {
        sleep 0.2;
        !alive _carrier
        || {!canMove _carrier}
        || {(getPosATL _carrier)#2 >= ITW_CLASH_HALParadrop_MinAltitude}
        || {time >= _deadline}
    };
    if (!alive _carrier || {!canMove _carrier}) exitWith {
        ["declined",["carrier-lost-in-climb",typeOf _carrier]] call
            ITW_CLASH_HALParadrop_fnc_Log;
        false
    };

    private _altitude = (getPosATL _carrier)#2;

    /*
        Too low to drop AND still where we started: do nothing at all.

        Landing here would unload at the pickup point. Returning false without
        landing leaves the stamp in place, so the carrier keeps its cargo and
        the waypoint's own unload - or a later attempt - handles it at the
        destination, which is the whole point of the lift.
    */
    private _origin = _carrierGroup getVariable [
        "ITW_CLASH_HALParadropOrigin",[]
    ];
    if (
        _altitude < ITW_CLASH_HALParadrop_FallbackAltitude
        && {_origin isNotEqualTo []}
        && {(getPosATL _carrier) distance2D _origin < ITW_CLASH_HALParadrop_MinRun}
    ) exitWith {
        ["declined",[
            "still-at-origin",
            typeOf _carrier,
            groupId _cargoGroup,
            round _altitude,
            round ((getPosATL _carrier) distance2D _origin)
        ]] call ITW_CLASH_HALParadrop_fnc_Log;
        false
    };

    if (
        _altitude < ITW_CLASH_HALParadrop_FallbackAltitude
        || {isNil "ITW_AllyParadropCargo"}
    ) exitWith {
        if (!_allowLandFallback) then {
            _carrier land "NONE";
            ["fallback-refused",[
                typeOf _carrier,
                groupId _cargoGroup,
                round _altitude,
                count _aboard,
                "landing-forbidden"
            ]] call ITW_CLASH_HALParadrop_fnc_Log;
        } else {
            _carrier land "GET OUT";
            [_carrierGroup,_carrier] call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier;
            ["fallback-land",[
                typeOf _carrier,
                groupId _cargoGroup,
                round _altitude,
                count _aboard
            ]] call ITW_CLASH_HALParadrop_fnc_Log;
        };
        false
    };

    [_carrier,_cargoGroup] call ITW_AllyParadropCargo;
    /*
        Every other caller of ITW_AllyParadropCargo follows it with this line:
        ITW itself (ITW_Ally.sqf:1019) and the player transport bridge
        (ITW_CLASH_PlayerTransportNativeBridge.sqf:113). moveOut and a
        parachute seat take each man out of his formation, and HAL has no
        doFollow anywhere to put him back. This was the one caller without it,
        and it is the caller every HAL paradrop goes through.
    */
    [units _cargoGroup,leader _cargoGroup] remoteExec ["doFollow",leader _cargoGroup];
    _carrier land "NONE";
    _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
    _carrierGroup setVariable ["ITW_CLASH_HALParadropOrigin",nil];

    ["executed",[
        typeOf _carrier,
        groupId _cargoGroup,
        round _altitude,
        count _aboard
    ]] call ITW_CLASH_HALParadrop_fnc_Log;
    true
};

/*
    HAL never starts a wait on a squad that is still under canopy.

    Hark, 2026-10-11: "seems like we still have job wipe on delivery".

    RYD_Wait takes the leader's vehicle once, when it starts
    (HAC_fnc.sqf:1929, _AV = vehicle _UL), and on every pass after that reads
    that vehicle being null as the group being lost (HAC_fnc.sqf:1944). A
    parachute is a vehicle, and it is deleted when the man lands. So any wait
    that STARTS while the leader is in his chute ends on touchdown with
    _alive false, and every order file answers that with
    "if not (_alive) exitwith" and clears Busy.

    The unload owner's v7 fixed the one way in that it had made itself: it
    used to release the order at the drop, and now waits for the squad to be
    standing. But the order is also woken by its carrier dying, because its
    carrier wait is a RYD_Wait on the carrier group and a dead aircraft ends
    that one too. Run of 2026-10-11, mission 2, G51 on a capture order:

        20:46:28  dropped from 54 m by Bravo 1-2
        20:46:30  Bravo 1-2 shot down by an AA vehicle
        20:46:34  order awake: waypoint to the objective written, and its
                  next wait started, leader under canopy
        20:46:48  leader on foot
        20:46:53  Busy false. The capture order is gone.
        20:47:03  HAL gives the squad a new order and asks for another lift

    The other four drops on that flight kept their orders. Their carriers
    lived through the descent.

    A carrier killed in the ten to twenty seconds after its drop is not rare:
    it is where the fire is. So the hazard is closed where it lives rather
    than at each thing that can wake an order. RYD_Wait is wrapped, and the
    wrapper holds a wait until the leader is out of his chute and the chute is
    no longer his assigned vehicle (the cargo form of the wait reads that
    instead, HAC_fnc.sqf:1954). Then HAL's own function runs, untouched, and
    sees a man on foot. Nothing is changed for a wait whose leader is not in a
    parachute, which is every other wait in the mission.

    HAL source is not edited. The hold is bounded, and at the bound HAL's wait
    runs as it always did.
*/
ITW_CLASH_HALParadrop_CanopyGuard = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_CanopyGuard",true
];
// A drop from 45 m lands in 10 to 22 s. This is a bound, not an estimate.
ITW_CLASH_HALParadrop_CanopyWait = missionNamespace getVariable [
    "ITW_CLASH_HALParadrop_CanopyWait",90
];

ITW_CLASH_HALParadrop_fnc_UnderCanopy = {
    params ["_group"];
    if !(_group isEqualType grpNull) exitWith {false};
    if (isNull _group) exitWith {false};
    private _leader = leader _group;
    if (isNull _leader || {!alive _leader}) exitWith {false};
    (vehicle _leader) isKindOf "ParachuteBase"
    || {(assignedVehicle _leader) isKindOf "ParachuteBase"}
};

ITW_CLASH_HALParadrop_fnc_HoldForLanding = {
    params ["_group"];
    if (!ITW_CLASH_HALParadrop_CanopyGuard) exitWith {0};
    if !([_group] call ITW_CLASH_HALParadrop_fnc_UnderCanopy) exitWith {0};
    // RYD_Wait sleeps, so it is never called where this could not.
    if (!canSuspend) exitWith {0};

    private _began = time;
    private _deadline = time + ITW_CLASH_HALParadrop_CanopyWait;
    waitUntil {
        sleep 0.5;
        !([_group] call ITW_CLASH_HALParadrop_fnc_UnderCanopy)
        || {time >= _deadline}
    };
    private _held = time - _began;
    ["wait-held-for-landing",[
        if (isNull _group) then {"<null>"} else {groupId _group},
        (round (_held * 10)) / 10,
        time >= _deadline
    ]] call ITW_CLASH_HALParadrop_fnc_Log;
    _held
};

[] spawn {
    scriptName "ITW_CLASH_HALParadrop_CanopyGuard";
    // HAC_fnc.sqf defines RYD_Wait and VarInit.sqf, run straight after it,
    // defines the orders (RydHQInit.sqf:102-104). Both there means HAL's
    // one init has finished and will not write RYD_Wait again.
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.5;
        (!isNil "RYD_Wait" && {!isNil "HAL_GoCapture"})
        || {diag_tickTime >= _deadline}
    };
    if (isNil "RYD_Wait" || {isNil "HAL_GoCapture"}) exitWith {
        diag_log "CLASH BOOT | WARNING | hal-paradrop-canopy-guard-failed | reason=hal-wait-missing | an order woken under canopy can still end on landing";
    };
    if (!isNil "ITW_CLASH_HALParadrop_fnc_WaitBase") exitWith {};

    ITW_CLASH_HALParadrop_fnc_WaitBase = RYD_Wait;
    // No locals of its own: HAL's wait reads its caller's variables, and the
    // caller is still one call away.
    RYD_Wait = {
        [_this param [0,grpNull]] call ITW_CLASH_HALParadrop_fnc_HoldForLanding;
        _this call ITW_CLASH_HALParadrop_fnc_WaitBase
    };
    ITW_CLASH_HALParadrop_CanopyGuardReady = true;
    diag_log format [
        "CLASH BOOT | hal-paradrop-canopy-guard-ready | version=%1 enabled=%2 bound=%3s wraps=RYD_Wait halSourceEdited=false",
        ITW_CLASH_HALParadropVersion,
        ITW_CLASH_HALParadrop_CanopyGuard,
        ITW_CLASH_HALParadrop_CanopyWait
    ];
};

ITW_CLASH_HALParadropReady = true;
diag_log format [
    "CLASH BOOT | hal-paradrop-ready | version=%1 nativeITWParachute=true baselineParam=ITW_ParamHelisUnload heavySeats=%2 heavyChance=%3 threatChance=%4 minAltitude=%5 classnamesHardcoded=false",
    ITW_CLASH_HALParadropVersion,
    ITW_CLASH_HALParadrop_HeavyCargoSeats,
    ITW_CLASH_HALParadrop_HeavyChance,
    ITW_CLASH_HALParadrop_ThreatChance,
    ITW_CLASH_HALParadrop_MinAltitude
];
true
