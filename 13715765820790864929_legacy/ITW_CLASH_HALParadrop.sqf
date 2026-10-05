if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALParadropReady",false]) exitWith {true};

ITW_CLASH_HALParadropVersion = 2;
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
    "ITW_CLASH_HALParadrop_MinAltitude",55
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
    params ["_carrierGroup","_carrier"];
    if (
        isNull _carrierGroup
        || {isNull _carrier}
        || {!alive _carrier}
        || {!canMove _carrier}
    ) exitWith {false};

    private _cargoGroup = _carrierGroup getVariable [
        "ITW_CLASH_HALParadropCargoGroup",grpNull
    ];
    if (isNull _cargoGroup) exitWith {false};

    private _aboard = units _cargoGroup select {
        alive _x && {vehicle _x == _carrier}
    };
    if (_aboard isEqualTo []) exitWith {
        _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];
        false
    };

    private _deadline = time + 8;
    waitUntil {
        sleep 0.2;
        !alive _carrier
        || {!canMove _carrier}
        || {(getPosATL _carrier)#2 >= ITW_CLASH_HALParadrop_MinAltitude}
        || {time >= _deadline}
    };
    if (!alive _carrier || {!canMove _carrier}) exitWith {false};

    private _altitude = (getPosATL _carrier)#2;
    if (
        _altitude < ITW_CLASH_HALParadrop_FallbackAltitude
        || {isNil "ITW_AllyParadropCargo"}
    ) exitWith {
        _carrier land "GET OUT";
        [_carrierGroup,_carrier] call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier;
        ["fallback-land",[
            typeOf _carrier,
            groupId _cargoGroup,
            round _altitude,
            count _aboard
        ]] call ITW_CLASH_HALParadrop_fnc_Log;
        false
    };

    [_carrier,_cargoGroup] call ITW_AllyParadropCargo;
    _carrier land "NONE";
    _carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",nil];

    ["executed",[
        typeOf _carrier,
        groupId _cargoGroup,
        round _altitude,
        count _aboard
    ]] call ITW_CLASH_HALParadrop_fnc_Log;
    true
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
