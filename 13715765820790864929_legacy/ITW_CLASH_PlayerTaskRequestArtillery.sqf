#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestArtilleryStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestArtilleryStarted = true;
ITW_CLASH_PlayerTaskRequestArtilleryReady = false;
ITW_CLASH_PlayerTaskRequestArtilleryVersion = 1;
ITW_CLASH_PlayerTaskRequestArtillerySerial = 0;

ITW_CLASH_PlayerTaskRequestArtillery_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTaskRequests_fnc_Log") then {
        ["artillery-" + _event,_payload] call ITW_CLASH_PlayerTaskRequests_fnc_Log;
    } else {
        diag_log format ["CLASH TASK REQUEST ARTILLERY | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerTaskRequestArtillery_fnc_EligibleVehicle = {
    params ["_group"];
    if (isNull _group) exitWith {objNull};
    if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {objNull};
    if (_group getVariable ["RydHQ_BatteryBusy",false]) exitWith {objNull};
    if (_group getVariable ["Busy" + str _group,false]) exitWith {objNull};
    if ((_group getVariable ["ITW_CLASH_PlayerArtilleryJobId",""]) isNotEqualTo "") exitWith {objNull};

    private _vehicle = [_group] call ITW_CLASH_PlayerArtillery_fnc_GetVehicle;
    if (isNull _vehicle) exitWith {objNull};
    if !(_vehicle getVariable ["ITW_CLASH_PlayerGarageAsset",false]) exitWith {objNull};
    if ((_vehicle getVariable ["ITW_CLASH_PlayerArtyDeploymentState",""]) != "DEPLOYED") exitWith {objNull};
    if !([_vehicle,side _group] call ITW_CLASH_PlayerArtillery_fnc_OutsideRearSanctuary) exitWith {objNull};
    _vehicle
};

ITW_CLASH_PlayerTaskRequestArtillery_fnc_TargetGroup = {
    params ["_target"];
    if (isNull _target) exitWith {grpNull};
    group _target
};

ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReleaseReservation = {
    params ["_targetGroup","_ownerToken",["_reason","release"]];
    if (isNull _targetGroup) exitWith {false};
    private _current = _targetGroup getVariable [
        "ITW_CLASH_PlayerRequestedCFFReservation",""
    ];
    if (_current != _ownerToken) exitWith {false};

    _targetGroup setVariable ["ITW_CLASH_PlayerRequestedCFFReservation",nil];
    _targetGroup setVariable ["CFF_Taken",false];
    ["reservation-released",[
        groupId _targetGroup,_ownerToken,_reason
    ]] call ITW_CLASH_PlayerTaskRequestArtillery_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReserveTarget = {
    params ["_target","_token"];
    private _targetGroup = [_target] call
        ITW_CLASH_PlayerTaskRequestArtillery_fnc_TargetGroup;
    if (isNull _targetGroup) exitWith {false};
    if (_targetGroup getVariable ["CFF_Taken",false]) exitWith {false};
    if ((_targetGroup getVariable ["ITW_CLASH_PlayerRequestedCFFReservation",""]) isNotEqualTo "") exitWith {false};

    _targetGroup setVariable ["CFF_Taken",true];
    _targetGroup setVariable ["ITW_CLASH_PlayerRequestedCFFReservation",_token];
    ["reservation-acquired",[
        groupId _targetGroup,_token,typeOf (vehicle leader _targetGroup)
    ]] call ITW_CLASH_PlayerTaskRequestArtillery_fnc_Log;
    true
};

ITW_CLASH_PlayerTaskRequestArtillery_fnc_FilterKnownTargets = {
    params ["_knownEnemies","_friends"];
    private _eligible = [];
    {
        private _target = _x;
        if (isNull _target || {!alive _target}) then {continue};
        private _targetGroup = group _target;
        if (isNull _targetGroup) then {continue};
        if (_targetGroup getVariable ["CFF_Taken",false]) then {continue};
        private _position = getPosATL (vehicle _target);
        if ([_position,_friends] call ITW_CLASH_PlayerArtillery_fnc_DangerClose) then {continue};
        _eligible pushBack _target;
    } forEach _knownEnemies;
    _eligible
};

ITW_CLASH_PlayerTaskRequestArtillery_fnc_Request = {
    params ["_group","_hq","_requestType"];

    private _vehicle = [_group] call
        ITW_CLASH_PlayerTaskRequestArtillery_fnc_EligibleVehicle;
    if (isNull _vehicle) exitWith {
        [
            "NO_CAPABILITY",
            "Unable. Deploy a player-gunned artillery asset outside the rear sanctuary before requesting a fire mission."
        ] call ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    private _knownEnemies = +(_hq getVariable ["RydHQ_KnEnemies",[]]);
    private _friends = +(_hq getVariable ["RydHQ_Friends",[]]);
    _knownEnemies = [
        _knownEnemies,_friends
    ] call ITW_CLASH_PlayerTaskRequestArtillery_fnc_FilterKnownTargets;

    if (_knownEnemies isEqualTo []) exitWith {
        ["NO_TASK","No suitable HAL-known fire mission is available."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    private _target = [_knownEnemies] call RYD_CFF_TGT;
    if (isNull _target) exitWith {
        ["NO_TASK","No suitable HAL-known fire mission is available."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    ITW_CLASH_PlayerTaskRequestArtillerySerial =
        ITW_CLASH_PlayerTaskRequestArtillerySerial + 1;
    private _token = format [
        "CLASH-CFF-REQUEST-%1-%2",
        round (diag_tickTime * 1000),
        ITW_CLASH_PlayerTaskRequestArtillerySerial
    ];

    if !([_target,_token] call
        ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReserveTarget
    ) exitWith {
        ["NO_TASK","HAL target was taken by another fire mission."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    private _amount = (
        missionNamespace getVariable ["RydART_Amount",6]
    ) min ITW_CLASH_PlayerArtilleryMaxRounds;
    _amount = (round _amount) max 1;
    private _targetPosition = getPosATL _target;
    private _result = [
        _targetPosition,[_group],"HE",_amount,objNull
    ] call RYD_ArtyMission;

    if !(
        _result isEqualType []
        && {count _result >= 5}
        && {_result#0}
        && {(_result#1) isNotEqualTo []}
    ) exitWith {
        [group _target,_token,"no-compatible-fire-solution"] call
            ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReleaseReservation;
        ["NO_TASK","HAL has no compatible fire solution for your current gun and ammunition."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    private _magazines = (_result#3) arrayIntersect (_result#3);
    if (_magazines isEqualTo []) exitWith {
        [group _target,_token,"no-authorized-magazines"] call
            ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReleaseReservation;
        ["NO_TASK","HAL has no compatible HE ammunition authorization for this target."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    private _authorized = (_amount min (_result#4)) max 1;
    _authorized = round _authorized;
    private _jobId = [
        _group,
        _vehicle,
        _target,
        _targetPosition,
        _hq,
        _magazines,
        _authorized
    ] call ITW_CLASH_PlayerArtillery_fnc_NewJob;

    if (_jobId isEqualTo "") exitWith {
        [group _target,_token,"job-create-failed"] call
            ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReleaseReservation;
        ["NO_TASK","HAL could not establish the requested fire mission."] call
            ITW_CLASH_PlayerTaskRequests_fnc_Result
    };

    private _targetGroup = group _target;
    _targetGroup setVariable [
        "ITW_CLASH_PlayerRequestedCFFReservation",_jobId
    ];

    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    if (count _job > 0) then {
        _job set ["origin","PLAYER_REQUEST"];
        _job set ["requestType","ARTILLERY"];
        _job set ["sourceKey","CFF|" + str _targetGroup];
        _job set ["rewardClass","ARTILLERY"];
        ITW_CLASH_PlayerJobs set [_jobId,_job];
    };

    [_jobId] spawn ITW_CLASH_PlayerArtillery_fnc_Monitor;
    ["target-selected",[
        _jobId,
        groupId _group,
        groupId _targetGroup,
        typeOf (vehicle _target),
        _targetPosition,
        _authorized,
        _magazines
    ]] call ITW_CLASH_PlayerTaskRequestArtillery_fnc_Log;

    [
        "MATCHED",
        format ["HAL fire mission assigned. %1 HE rounds authorized.",_authorized],
        _jobId
    ] call ITW_CLASH_PlayerTaskRequests_fnc_Result
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskRequestArtilleryBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestsReady",false]
            && {missionNamespace getVariable ["ITW_CLASH_PlayerArtilleryTasksReady",false]}
            && {!isNil "ITW_CLASH_PlayerArtillery_fnc_NewJob"}
            && {!isNil "ITW_CLASH_PlayerArtillery_fnc_Monitor"}
            && {!isNil "ITW_CLASH_PlayerArtillery_fnc_FinishJob"}
            && {!isNil "RYD_CFF_TGT"}
            && {!isNil "RYD_ArtyMission"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-task-request-artillery-bind-timeout | explicit artillery remains unavailable";
    };

    ITW_CLASH_PlayerTaskRequestArtillery_fnc_FinishJobBase =
        ITW_CLASH_PlayerArtillery_fnc_FinishJob;
    ITW_CLASH_PlayerArtillery_fnc_FinishJob = {
        params ["_jobId","_state","_outcome"];
        private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
        private _target = _job getOrDefault ["target",objNull];
        private _origin = _job getOrDefault ["origin",""];
        private _result = _this call
            ITW_CLASH_PlayerTaskRequestArtillery_fnc_FinishJobBase;

        if (_result && {_origin == "PLAYER_REQUEST"} && {!isNull _target}) then {
            [
                group _target,_jobId,format ["terminal-%1-%2",_state,_outcome]
            ] call ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReleaseReservation;
        };
        _result
    };

    [
        "ARTILLERY",
        ITW_CLASH_PlayerTaskRequestArtillery_fnc_Request
    ] call ITW_CLASH_PlayerTaskRequests_fnc_RegisterAdapter;

    ITW_CLASH_PlayerTaskRequestArtilleryReady = true;
    diag_log format [
        "CLASH BOOT | player-task-request-artillery-ready | version=%1 nativeKnownTargets=true nativeCFFTakenReservation=true existingExecutor=true subscriptionRequired=false capabilityAtRequest=true",
        ITW_CLASH_PlayerTaskRequestArtilleryVersion
    ];
};

true
