if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_RemnantEvacStarted",false]) exitWith {true};

ITW_CLASH_RemnantEvacStarted = true;
ITW_CLASH_RemnantEvacVersion = 1;
ITW_CLASH_RemnantEvacMaxSurvivors = missionNamespace getVariable [
    "ITW_CLASH_RemnantEvacMaxSurvivors",2
];
ITW_CLASH_RemnantEvacMaxFraction = missionNamespace getVariable [
    "ITW_CLASH_RemnantEvacMaxFraction",0.5
];
ITW_CLASH_RemnantEvacMinOriginalStrength = missionNamespace getVariable [
    "ITW_CLASH_RemnantEvacMinOriginalStrength",3
];
ITW_CLASH_RemnantEvacRetryDelay = missionNamespace getVariable [
    "ITW_CLASH_RemnantEvacRetryDelay",30
];
ITW_CLASH_RemnantEvacMinWithdrawalTime = missionNamespace getVariable [
    "ITW_CLASH_RemnantEvacMinWithdrawalTime",20
];

ITW_CLASH_RemnantEvac_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["remnant-evac-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH REMNANT EVAC | %1 | %2",_event,_payload];
    };
};

[] spawn {
    scriptName "ITW_CLASH_RemnantEvac";
    waitUntil {
        sleep 1;
        (
            missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]
            && {missionNamespace getVariable ["ITW_CLASH_HALReady",false]}
            && {!isNil "ITW_CLASH_fnc_StartWithdrawal"}
        ) || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 3;

        {
            private _group = _x;
            if (isNull _group) then {continue};

            private _managed =
                _group getVariable ["ITW_CLASH_Managed",false]
                || {_group getVariable ["ITW_CLASH_DualHALManaged",false]};
            if (!_managed) then {continue};
            if (_group getVariable ["ITW_CLASH_Withdrawing",false]) then {continue};
            if (_group getVariable ["ITW_CLASH_VehicleCrewGroup",false]) then {continue};
            if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") then {continue};
            if ((_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") then {continue};
            if ((units _group) findIf {isPlayer _x} >= 0) then {continue};
            if (!isNil "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" && {
                [_group] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved
            }) then {continue};

            private _alive = units _group select {alive _x};
            private _aliveCount = count _alive;
            if (_aliveCount < 1 || {_aliveCount > ITW_CLASH_RemnantEvacMaxSurvivors}) then {
                continue
            };
            if (_alive findIf {!(_x isKindOf "CAManBase")} >= 0) then {continue};
            if (_alive findIf {vehicle _x != _x} >= 0) then {continue};

            private _archetype = +(_group getVariable ["ITW_CLASH_Archetype",[]]);
            if (_archetype isEqualTo [] && {!isNil "ITW_CLASH_fnc_GetArchetype"}) then {
                _archetype = [_group] call ITW_CLASH_fnc_GetArchetype;
            };
            private _originalStrength = count _archetype;
            if (_originalStrength < ITW_CLASH_RemnantEvacMinOriginalStrength) then {continue};

            private _fraction = _aliveCount / (_originalStrength max 1);
            if (_fraction > ITW_CLASH_RemnantEvacMaxFraction) then {continue};

            private _retryAt = _group getVariable ["ITW_CLASH_RemnantEvacRetryAt",0];
            if (time < _retryAt) then {continue};
            _group setVariable [
                "ITW_CLASH_RemnantEvacRetryAt",
                time + ITW_CLASH_RemnantEvacRetryDelay
            ];

            if ([_group,"combat-remnant"] call ITW_CLASH_fnc_StartWithdrawal) then {
                _group setVariable ["ITW_CLASH_RemnantEvac",true,true];
                _group setVariable ["ITW_CLASH_RemnantEvacSince",time,true];
                ["withdrawal-forced",[
                    if (!isNil "ITW_CLASH_fnc_GroupId") then {
                        [_group] call ITW_CLASH_fnc_GroupId
                    } else {str _group},
                    side _group,_aliveCount,_originalStrength,_fraction
                ]] call ITW_CLASH_RemnantEvac_fnc_Log;
            } else {
                ["withdrawal-deferred",[
                    str _group,side _group,_aliveCount,_originalStrength,_fraction
                ]] call ITW_CLASH_RemnantEvac_fnc_Log;
            };
        } forEach +allGroups;
    };
};

diag_log format [
    "CLASH BOOT | remnant-evac-ready | version=%1 maxSurvivors=%2 maxFraction=%3 minOriginal=%4 fastEligibility=%5",
    ITW_CLASH_RemnantEvacVersion,
    ITW_CLASH_RemnantEvacMaxSurvivors,
    ITW_CLASH_RemnantEvacMaxFraction,
    ITW_CLASH_RemnantEvacMinOriginalStrength,
    ITW_CLASH_RemnantEvacMinWithdrawalTime
];
true
