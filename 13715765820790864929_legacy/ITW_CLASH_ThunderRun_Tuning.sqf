#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ThunderRunTuningStarted",false]) exitWith {true};
if !(missionNamespace getVariable ["ITW_CLASH_ThunderRunEnhancementsReady",false]) exitWith {
    diag_log "CLASH BOOT | thunder-run-tuning-prereq-failed";
    false
};

ITW_CLASH_ThunderRunTuningStarted = true;
ITW_CLASH_ThunderRunTuningReady = false;
ITW_CLASH_ThunderRunTuningVersion = 1;

/*
    Live-burn tuning layer.

    - Preserve the visible exact sling package and vehicle-ammo bridge.
    - Increase transit/terminal speed without hardcoding an airframe classname.
    - Accelerate flare cadence, add a six-shot release burst, then a dense egress stream.
    - Begin RTB immediately at COLD instead of waiting for parachute touchdown.
    - Harden RTB with both a HAL-style group waypoint and direct pilot destination.
    - Apply the existing ACE MagicRearm workaround to successful vehicle Thunder Runs.
*/

ITW_CLASH_ThunderRunTransitSpeedFraction = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunTransitSpeedFraction",0.75
];
ITW_CLASH_ThunderRunTerminalSpeedFraction = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunTerminalSpeedFraction",0.90
];
ITW_CLASH_ThunderRunFlareCadenceScale = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunFlareCadenceScale",0.80
];
ITW_CLASH_ThunderRunReleaseBurstCount = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunReleaseBurstCount",6
];
ITW_CLASH_ThunderRunReleaseBurstCadence = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunReleaseBurstCadence",0.16
];
ITW_CLASH_ThunderRunEgressFlareCadence = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunEgressFlareCadence",0.90
];

ITW_CLASH_ThunderRun_fnc_InitFlareBudgetPreTune = ITW_CLASH_ThunderRun_fnc_InitFlareBudget;
ITW_CLASH_ThunderRun_fnc_MaybeFlarePreTune = ITW_CLASH_ThunderRun_fnc_MaybeFlare;
ITW_CLASH_ThunderRun_fnc_SetPhasePreTune = ITW_CLASH_ThunderRun_fnc_SetPhase;
ITW_CLASH_ThunderRun_fnc_DisposePreTune = ITW_CLASH_ThunderRun_fnc_Dispose;
ITW_CLASH_ThunderRun_fnc_ReturnHomePreTune = ITW_CLASH_ThunderRun_fnc_ReturnHome;
ITW_CLASH_ThunderRun_fnc_PackageMonitorPreTune = ITW_CLASH_ThunderRun_fnc_PackageMonitor;

ITW_CLASH_ThunderRun_fnc_MaxConfiguredSpeed = {
    params ["_veh"];
    if (isNull _veh) exitWith {-1};
    private _max = getNumber (
        configFile >> "CfgVehicles" >> typeOf _veh >> "maxSpeed"
    );
    if (_max <= 0) exitWith {-1};
    _max
};

ITW_CLASH_ThunderRun_fnc_ApplySpeed = {
    params ["_state","_phase"];
    private _veh = _state getOrDefault ["vehicle",objNull];
    if (isNull _veh || {!alive _veh}) exitWith {false};

    private _max = [_veh] call ITW_CLASH_ThunderRun_fnc_MaxConfiguredSpeed;
    if (_max <= 0) exitWith {false};

    private _fraction = switch (_phase) do {
        case "TRANSIT": {ITW_CLASH_ThunderRunTransitSpeedFraction};
        case "TAKEOVER": {ITW_CLASH_ThunderRunTerminalSpeedFraction};
        case "INGRESS": {ITW_CLASH_ThunderRunTerminalSpeedFraction};
        case "POPUP": {ITW_CLASH_ThunderRunTerminalSpeedFraction};
        case "RELEASE": {ITW_CLASH_ThunderRunTerminalSpeedFraction};
        case "EGRESS": {ITW_CLASH_ThunderRunTerminalSpeedFraction};
        default {-1};
    };
    if (_fraction < 0) exitWith {
        _veh forceSpeed -1;
        false
    };

    private _desired = (_max * _fraction) max 80;
    _veh forceSpeed _desired;
    ["phase-speed",[
        _state getOrDefault ["poolId","?"],_phase,
        typeOf _veh,_max,_fraction,_desired
    ]] call ITW_CLASH_ThunderRun_fnc_Log;
    true
};

ITW_CLASH_ThunderRun_fnc_InitFlareBudget = {
    params ["_state"];
    [_state] call ITW_CLASH_ThunderRun_fnc_InitFlareBudgetPreTune;

    private _emitter = _state getOrDefault ["countermeasureEmitter",[]];
    private _rounds = if (_emitter isEqualTo []) then {0} else {_emitter#3};
    private _budget = (_rounds min 40) max 0;

    private _ingress = floor (_budget * 0.10);
    private _popup = floor (_budget * 0.30);
    private _remaining = (_budget - _ingress - _popup) max 0;
    private _release = ITW_CLASH_ThunderRunReleaseBurstCount min _remaining;
    private _egress = (_remaining - _release) max 0;

    _state set ["flareLimits",createHashMapFromArray [
        ["INGRESS",_ingress],["POPUP",_popup],
        ["RELEASE",_release],["EGRESS",_egress]
    ]];
    _state set ["flareUsed",createHashMap];
    _state set ["nextFlareAt",0];
    _state set ["releaseBurstStarted",false];
    _state set ["releaseBurstUntil",0];
    _state
};

ITW_CLASH_ThunderRun_fnc_FlareBurst = {
    params ["_state","_phase","_requested","_cadence"];
    private _limits = _state getOrDefault ["flareLimits",createHashMap];
    private _used = _state getOrDefault ["flareUsed",createHashMap];
    private _limit = _limits getOrDefault [_phase,0];
    private _spent = _used getOrDefault [_phase,0];
    private _available = (_limit - _spent) max 0;
    private _shots = _requested min _available;
    if (_shots <= 0) exitWith {false};

    ["flare-burst",[
        _state getOrDefault ["poolId","?"],_phase,_shots,_cadence,
        [_state] call ITW_CLASH_ThunderRun_fnc_FlareRemaining
    ]] call ITW_CLASH_ThunderRun_fnc_Log;

    for "_i" from 1 to _shots do {
        if !([_state] call ITW_CLASH_ThunderRun_fnc_FireCountermeasure) exitWith {};
        _used = _state getOrDefault ["flareUsed",createHashMap];
        _spent = _used getOrDefault [_phase,0];
        _used set [_phase,_spent + 1];
        _state set ["flareUsed",_used];
        if (_i < _shots) then {sleep _cadence};
    };
    _state set ["nextFlareAt",time + _cadence];
    true
};

ITW_CLASH_ThunderRun_fnc_MaybeFlare = {
    params ["_state","_phase"];
    private _emitter = _state getOrDefault ["countermeasureEmitter",[]];
    if (_emitter isEqualTo []) exitWith {false};

    if (_phase == "RELEASE") exitWith {
        if (_state getOrDefault ["releaseBurstStarted",false]) exitWith {false};
        _state set ["releaseBurstStarted",true];
        private _count = ITW_CLASH_ThunderRunReleaseBurstCount;
        private _cadence = ITW_CLASH_ThunderRunReleaseBurstCadence;
        _state set ["releaseBurstUntil",time + ((_count max 1) * _cadence)];
        [_state,"RELEASE",_count,_cadence] spawn
            ITW_CLASH_ThunderRun_fnc_FlareBurst;
        true
    };

    if (
        _phase == "EGRESS"
        && {time < (_state getOrDefault ["releaseBurstUntil",0])}
    ) exitWith {false};

    private _limits = _state getOrDefault ["flareLimits",createHashMap];
    private _used = _state getOrDefault ["flareUsed",createHashMap];
    private _limit = _limits getOrDefault [_phase,0];
    private _spent = _used getOrDefault [_phase,0];
    if (
        _spent >= _limit
        || {time < (_state getOrDefault ["nextFlareAt",0])}
    ) exitWith {false};

    if !([_state] call ITW_CLASH_ThunderRun_fnc_FireCountermeasure) exitWith {false};
    _used set [_phase,_spent + 1];
    _state set ["flareUsed",_used];

    private _cadence = switch (_phase) do {
        case "POPUP": {1.5 * ITW_CLASH_ThunderRunFlareCadenceScale};
        case "EGRESS": {ITW_CLASH_ThunderRunEgressFlareCadence};
        default {3 * ITW_CLASH_ThunderRunFlareCadenceScale};
    };
    _state set ["nextFlareAt",time + _cadence];
    true
};

ITW_CLASH_ThunderRun_fnc_SetPhase = {
    params ["_state","_phase"];
    private _result = [_state,_phase] call ITW_CLASH_ThunderRun_fnc_SetPhasePreTune;
    [_state,_phase] call ITW_CLASH_ThunderRun_fnc_ApplySpeed;
    _result
};

// Robust RTB: install a group waypoint, issue direct doMove, then repair a
// lingering DoNotPlan state exactly as the abort-handback code does.
ITW_CLASH_ThunderRun_fnc_ReturnHome = {
    params ["_state"];
    private _attempt = _state getOrDefault ["rtbAttemptCount",0];
    if (_state getOrDefault ["rtbAtHome",false]) exitWith {true};
    if (_attempt >= 2) exitWith {false};
    _state set ["rtbAttemptCount",_attempt + 1];

    private _veh = _state getOrDefault ["vehicle",objNull];
    private _home = +(_state getOrDefault ["home",[]]);
    if (
        isNull _veh || {!alive _veh} || {!canMove _veh}
        || {_home isEqualTo []}
    ) exitWith {false};

    private _driver = driver _veh;
    private _group = if (isNull _driver) then {grpNull} else {group _driver};
    if (isNull _driver || {!alive _driver} || {isNull _group}) exitWith {false};

    [_state,"RTB"] call ITW_CLASH_ThunderRun_fnc_SetPhase;
    _veh forceSpeed -1;
    _driver forceSpeed -1;
    _veh flyInHeight ITW_CLASH_ThunderRunTransitHeight;
    _group setBehaviour "CARELESS";
    _group setCombatMode "BLUE";
    _group setSpeedMode "FULL";

    [_group] call RYD_WPdel;
    [
        _group,_home,"MOVE","CARELESS","BLUE","FULL",
        ["true","deletewaypoint [(group this), 0]"]
    ] call RYD_WPadd;
    _group setCurrentWaypoint [_group,currentWaypoint _group];
    _driver doMove _home;

    sleep 1;
    private _expected = expectedDestination _driver;
    private _escalated = false;
    if (
        count _expected > 1
        && {(_expected#1) isEqualTo "DoNotPlan"}
    ) then {
        private _wpPos = waypointPosition [_group,currentWaypoint _group];
        _driver setDestination [_wpPos,"LEADER PLANNED",true];
        _escalated = true;
    };

    ["rtb-ordered",[
        _state getOrDefault ["poolId","?"],_attempt + 1,
        getPosATL _veh,+_home,_escalated,expectedDestination _driver
    ]] call ITW_CLASH_ThunderRun_fnc_Log;

    private _deadline = time + 300;
    waitUntil {
        sleep 1;
        isNull _veh || {!alive _veh} || {!canMove _veh}
        || {isNull _driver} || {!alive _driver}
        || {_veh distance2D _home < 250}
        || {time >= _deadline}
    };

    if (
        isNull _veh || {!alive _veh} || {!canMove _veh}
        || {isNull _driver} || {!alive _driver}
        || {_veh distance2D _home >= 250}
    ) exitWith {
        ["rtb-failed",[
            _state getOrDefault ["poolId","?"],_attempt + 1,
            if (isNull _veh) then {-1} else {_veh distance2D _home},
            if (isNull _driver) then {[]} else {expectedDestination _driver}
        ]] call ITW_CLASH_ThunderRun_fnc_Log;
        false
    };

    _veh land "LAND";
    private _landDeadline = time + 120;
    waitUntil {
        sleep 1;
        isNull _veh || {!alive _veh}
        || {
            ((getPosATL _veh)#2 < 3)
            && {abs speed _veh < 3}
        }
        || {time >= _landDeadline}
    };

    private _atHome = !isNull _veh && {alive _veh} && {
        ((getPosATL _veh)#2 < 5)
        && {abs speed _veh < 5}
        && {_veh distance2D _home < 300}
    };
    _state set ["rtbAtHome",_atHome];
    ["rtb-settled",[
        _state getOrDefault ["poolId","?"],_atHome,
        if (isNull _veh) then {[]} else {getPosATL _veh}
    ]] call ITW_CLASH_ThunderRun_fnc_Log;
    _atHome
};

ITW_CLASH_ThunderRun_fnc_Dispose = {
    params ["_state","_outcome"];

    // On the happy path, aircraft survival is now independent of parachute
    // touchdown. Start RTB the instant the J-hook reaches COLD; the package
    // monitor continues asynchronously and the inherited disposition later
    // consumes its already-set delivery result.
    if (
        _outcome == "SUCCESS"
        && {_state getOrDefault ["released",false]}
        && {!(_state getOrDefault ["rtbAtHome",false])}
    ) then {
        ["rtb-immediate-after-cold",[
            _state getOrDefault ["poolId","?"],
            _state getOrDefault ["phase","?"]
        ]] call ITW_CLASH_ThunderRun_fnc_Log;
        [_state] call ITW_CLASH_ThunderRun_fnc_ReturnHome;
    };

    [_state,_outcome] call ITW_CLASH_ThunderRun_fnc_DisposePreTune
};

ITW_CLASH_ThunderRun_fnc_PackageMonitor = {
    params ["_state"];
    [_state] call ITW_CLASH_ThunderRun_fnc_PackageMonitorPreTune;

    private _source = _state getOrDefault ["source","UNKNOWN"];
    private _target = _state getOrDefault ["target",objNull];
    private _delivered = (_state getOrDefault ["deliveryOutcome",""]) == "DELIVERED";
    private _ace = missionNamespace getVariable ["ITW_CLASH_ACEActive",false];
    private _magic = missionNamespace getVariable ["RydxHQ_MagicRearm",false];

    if (
        _source == "CLASH_VEHICLE_AMMO_AIR"
        && {_delivered}
        && {!isNull _target}
        && {!(_target isKindOf "Man")}
        && {alive _target}
        && {_ace}
        && {_magic}
    ) then {
        _target setVehicleAmmo 1;
        _target setVariable ["ITW_CLASH_ThunderRunVehicleRearmed",time,true];
        ["vehicle-ace-rearm",[
            _state getOrDefault ["poolId","?"],typeOf _target,
            getPosATL _target,someAmmo _target
        ]] call ITW_CLASH_ThunderRun_fnc_Log;
    };
};

ITW_CLASH_ThunderRunTuningReady = true;
diag_log format [
    "CLASH BOOT | thunder-run-tuning-ready | version=%1 transitSpeedFraction=%2 terminalSpeedFraction=%3 flareCadenceScale=%4 releaseBurst=%5 releaseBurstCadence=%6 egressCadence=%7 immediateColdRTB=true robustRTB=true aceVehicleRearm=true",
    ITW_CLASH_ThunderRunTuningVersion,
    ITW_CLASH_ThunderRunTransitSpeedFraction,
    ITW_CLASH_ThunderRunTerminalSpeedFraction,
    ITW_CLASH_ThunderRunFlareCadenceScale,
    ITW_CLASH_ThunderRunReleaseBurstCount,
    ITW_CLASH_ThunderRunReleaseBurstCadence,
    ITW_CLASH_ThunderRunEgressFlareCadence
];

true
