#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ThunderRunAirTiersStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_ThunderRun_fnc_Classify") exitWith {
    diag_log "CLASH BOOT | WARNING | thunder-run-air-tiers-no-classifier | blunt air denial retained";
    false
};
if (isNil "ITW_CLASH_AirPicture_fnc_ClassifyCorridor") exitWith {
    diag_log "CLASH BOOT | WARNING | thunder-run-air-tiers-no-air-picture | blunt air denial retained";
    false
};

ITW_CLASH_ThunderRunAirTiersStarted = true;
ITW_CLASH_ThunderRunAirTiersVersion = 1;
ITW_CLASH_ThunderRunAirTiersReady = false;

/*
    Helicopter threat tiers, applied to Thunder Run's air denial.

    Thunder Run's own classifier closes a corridor on three blunt rules
    (ITW_CLASH_ThunderRun_Core.sqf:272-290):

      - any known enemy aircraft within ITW_CLASH_ThunderRunAirDenyRadius
        (5000 m) of the route. "Any" is literal: RydHQ_Airthreat is built from
        RydHQ_EnAir, and HAL's RHQ_NCAir is only the unarmed SUBSET of RHQ_Air
        rather than a removal from it (HAC_fnc2.sqf:2647-2651), so an unarmed
        enemy transport five kilometres off the route grounds a resupply run;
      - three AA soldiers within 1000 m, or four within 1500 m;
      - any AA within the outer band with no countermeasure launcher aboard.

    AIR_DENIED is not advisory. ITW_CLASH_Resupply.sqf:901 skips the delivery
    outright and ITW_CLASH_PlayerDemandNativeInterceptors.sqf:273 disposes the
    run. So those rules do not make a lift careful, they cancel it - and a
    MANPADS team or a passing transport is enough.

    The tiers replace that judgment with the one the design settles on: most air
    defence changes HOW a helicopter flies, not WHETHER it flies. Only a system
    built to kill aircraft closes a route - a dedicated AA vehicle, a radar SAM
    site, or a fixed-wing interceptor with four or more loaded air-to-air
    missiles - plus an area where we have recently lost two helicopters close
    together, whatever shot them down. Everything else makes the corridor hot or
    contested, and the run flies the low, fast profile it exists to fly.

    This layer only ever RELAXES a verdict. It re-examines an AIR_DENIED that
    came from an air or AA cause and never touches a ground-driven one, never
    upgrades, and never denies a route the base classifier allowed. If the air
    picture is unavailable it does nothing and the blunt rules stand.
*/

ITW_CLASH_ThunderRunAirTiersEnabled = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunAirTiersEnabled",true
];
/*
    A corridor the tiers find genuinely clear is reported CONTESTED rather than
    SAFE, deliberately. The base classifier had already denied it, so its own
    ground verdict for this route was never computed - claiming SAFE would assert
    something we did not evaluate. CONTESTED flies the profile, which is the
    outcome the design wants, without inventing a clean bill of health.
*/
ITW_CLASH_ThunderRunAirTiersClearState = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunAirTiersClearState","CONTESTED"
];

// The three AIR_DENIED causes that are air or AA judgments, and therefore ours
// to re-examine. Anything else the base classifier denies for stands.
ITW_CLASH_ThunderRunAirTiersCauses = [
    "enemy-air-corridor","aa-concentration","aa-no-countermeasures"
];

ITW_CLASH_ThunderRunAirTiers_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_ThunderRun_fnc_Log") then {
        ["air-tiers-" + _event,_payload] call ITW_CLASH_ThunderRun_fnc_Log;
    } else {
        diag_log format ["CLASH THUNDER RUN AIR TIERS | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["air-tiers",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

ITW_CLASH_ThunderRun_fnc_ClassifyTierBase = ITW_CLASH_ThunderRun_fnc_Classify;

ITW_CLASH_ThunderRun_fnc_Classify = {
    params ["_veh","_target","_hq"];
    private _result = [_veh,_target,_hq] call ITW_CLASH_ThunderRun_fnc_ClassifyTierBase;
    if (!ITW_CLASH_ThunderRunAirTiersEnabled) exitWith {_result};
    if (isNull _veh || {isNull _target} || {isNull _hq}) exitWith {_result};

    private _state = _result getOrDefault ["state","NORMAL"];
    private _reason = _result getOrDefault ["reason",""];
    // Only an air or AA denial is ours. A ground-driven verdict, and any state
    // other than AIR_DENIED, passes through untouched.
    if (_state isNotEqualTo "AIR_DENIED") exitWith {_result};
    if !(_reason in ITW_CLASH_ThunderRunAirTiersCauses) exitWith {_result};

    private _corridor = [
        _hq,getPosATL _veh,getPosATL _target
    ] call ITW_CLASH_AirPicture_fnc_ClassifyCorridor;
    private _tierState = _corridor getOrDefault ["state","AIR_DENIED"];
    private _tierReason = _corridor getOrDefault ["reason","corridor-unavailable"];

    // The air picture could not answer: leave the blunt verdict alone rather
    // than open a route on no information.
    if (_tierReason isEqualTo "corridor-unavailable") exitWith {_result};
    // A hard-kill system or a recent pair of losses really does close it.
    if (_tierState isEqualTo "AIR_DENIED") exitWith {
        ["upheld",[
            _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,_reason,_tierReason
        ]] call ITW_CLASH_ThunderRunAirTiers_fnc_Log;
        _result set ["reason",_reason + "|tier-" + _tierReason];
        _result
    };

    private _relaxed = if (_tierState isEqualTo "COLD") then {
        ITW_CLASH_ThunderRunAirTiersClearState
    } else {
        _tierState
    };
    _result set ["state",_relaxed];
    _result set ["reason",format ["tier-relaxed-%1-from-%2",_tierReason,_reason]];

    ["relaxed",[
        _hq getVariable ["RydHQ_CodeSign","?"],typeOf _veh,
        _reason,_tierState,_relaxed,
        round (_corridor getOrDefault ["aaDistance",-1]),
        round (_corridor getOrDefault ["airDistance",-1])
    ]] call ITW_CLASH_ThunderRunAirTiers_fnc_Log;
    _result
};

if (!isNil "SKL_fnc_CompileFinal") then {
    {[_x] call SKL_fnc_CompileFinal} forEach [
        "ITW_CLASH_ThunderRun_fnc_ClassifyTierBase",
        "ITW_CLASH_ThunderRun_fnc_Classify"
    ];
};

ITW_CLASH_ThunderRunAirTiersReady = true;
diag_log format [
    "CLASH BOOT | thunder-run-air-tiers-ready | version=%1 clearState=%2 causes=%3 relaxesOnly=true hardKillCloses=true unarmedTransportBlocks=false",
    ITW_CLASH_ThunderRunAirTiersVersion,
    ITW_CLASH_ThunderRunAirTiersClearState,
    ITW_CLASH_ThunderRunAirTiersCauses
];
true
