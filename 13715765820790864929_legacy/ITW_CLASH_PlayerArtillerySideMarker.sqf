if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerArtillerySideMarkerStarted",false]) exitWith {true};

ITW_CLASH_PlayerArtillerySideMarkerStarted = true;
ITW_CLASH_PlayerArtillerySideMarkerVersion = 1;

ITW_CLASH_PlayerArtillerySideMarker_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_Log") then {
        ["artillery-side-marker-" + _event,_payload] call
            ITW_CLASH_PlayerTasks_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER ARTILLERY SIDE MARKER | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerArtillerySideMarker_fnc_Name = {
    params ["_jobId"];
    "ITW_CLASH_ARTY_SIDE_" + ((_jobId splitString "-") joinString "_")
};

ITW_CLASH_PlayerArtillerySideMarker_fnc_Creator = {
    params ["_group"];
    if (isNull _group) exitWith {objNull};
    private _players = units _group select {isPlayer _x};
    if (_players isEqualTo []) exitWith {objNull};
    _players#0
};

ITW_CLASH_PlayerArtillerySideMarker_fnc_Publish = {
    params ["_group","_jobId"];
    if (isNull _group || {_jobId isEqualTo ""}) exitWith {false};

    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    if (count _job == 0) exitWith {false};
    private _targetPosition = +(_job getOrDefault ["targetPosition",[]]);
    private _targetRadius = _job getOrDefault [
        "targetRadius",
        missionNamespace getVariable ["ITW_CLASH_PlayerArtilleryAimRadius",150]
    ];
    if (count _targetPosition < 2 || {_targetRadius <= 0}) exitWith {false};

    private _creator = [_group] call
        ITW_CLASH_PlayerArtillerySideMarker_fnc_Creator;
    if (isNull _creator) exitWith {false};

    private _markerName = [_jobId] call
        ITW_CLASH_PlayerArtillerySideMarker_fnc_Name;
    deleteMarker _markerName;

    // Channel 1 is Arma's Side channel. The creator determines which side can
    // see the networked marker, including JIP clients. This is intentionally a
    // friendly fire-coordination product, not global battlefield intelligence.
    private _marker = createMarker [
        _markerName,
        _targetPosition,
        1,
        _creator
    ];
    if (_marker isEqualTo "") exitWith {false};
    _marker setMarkerShape "ELLIPSE";
    _marker setMarkerBrush "Border";
    _marker setMarkerColor "ColorRed";
    _marker setMarkerSize [_targetRadius,_targetRadius];
    _marker setMarkerAlpha 0.9;

    _job set ["sideTargetAreaMarker",_markerName];
    _job set ["sideTargetAreaCreator",_creator];
    _job set ["sideTargetAreaRadius",_targetRadius];
    ITW_CLASH_PlayerJobs set [_jobId,_job];

    ["published",[
        _jobId,
        str (side _group),
        getPlayerUID _creator,
        _targetPosition,
        _targetRadius,
        1
    ]] call ITW_CLASH_PlayerArtillerySideMarker_fnc_Log;
    true
};

ITW_CLASH_PlayerArtillerySideMarker_fnc_Clear = {
    params ["_group","_jobId"];
    if (_jobId isEqualTo "") exitWith {false};

    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    private _markerName = if (count _job > 0) then {
        _job getOrDefault ["sideTargetAreaMarker",""]
    } else {""};
    if (_markerName isEqualTo "") then {
        _markerName = [_jobId] call ITW_CLASH_PlayerArtillerySideMarker_fnc_Name;
    };
    deleteMarker _markerName;

    if (count _job > 0) then {
        _job deleteAt "sideTargetAreaMarker";
        _job deleteAt "sideTargetAreaCreator";
        _job deleteAt "sideTargetAreaRadius";
        ITW_CLASH_PlayerJobs set [_jobId,_job];
    };
    ["cleared",[_jobId,if (isNull _group) then {"UNKNOWN"} else {str (side _group)}]] call
        ITW_CLASH_PlayerArtillerySideMarker_fnc_Log;
    true
};

if (
    isNil "ITW_CLASH_PlayerArtillery_fnc_PushClientAssignment"
    || {isNil "ITW_CLASH_PlayerArtillery_fnc_ClearClientAssignment"}
) exitWith {
    diag_log "CLASH BOOT | player-artillery-side-marker-bind-failed | artillery client assignment functions unavailable";
    false
};

// Keep the existing gun-crew assignment untouched: only the actual artillery
// group receives the Fired EH / shot-report authority. The side marker is a
// separate communication product layered on top of that proven executor.
ITW_CLASH_PlayerArtillerySideMarker_fnc_PushClientAssignmentBase =
    ITW_CLASH_PlayerArtillery_fnc_PushClientAssignment;
ITW_CLASH_PlayerArtillery_fnc_PushClientAssignment = {
    params ["_group","_jobId","_vehicle","_allowedMagazines"];
    private _result = _this call
        ITW_CLASH_PlayerArtillerySideMarker_fnc_PushClientAssignmentBase;
    if (_result) then {
        [_group,_jobId] call ITW_CLASH_PlayerArtillerySideMarker_fnc_Publish;
    };
    _result
};

ITW_CLASH_PlayerArtillerySideMarker_fnc_ClearClientAssignmentBase =
    ITW_CLASH_PlayerArtillery_fnc_ClearClientAssignment;
ITW_CLASH_PlayerArtillery_fnc_ClearClientAssignment = {
    params ["_group","_jobId"];
    private _result = _this call
        ITW_CLASH_PlayerArtillerySideMarker_fnc_ClearClientAssignmentBase;
    [_group,_jobId] call ITW_CLASH_PlayerArtillerySideMarker_fnc_Clear;
    _result
};

diag_log format [
    "CLASH BOOT | player-artillery-side-marker-ready | version=%1 sideChannel=1 jip=true aimRadius=%2 enemyVisible=false gunCrewAuthorityUnchanged=true acceptanceRadiusInvisible=%3",
    ITW_CLASH_PlayerArtillerySideMarkerVersion,
    missionNamespace getVariable ["ITW_CLASH_PlayerArtilleryAimRadius",150],
    missionNamespace getVariable ["ITW_CLASH_PlayerArtilleryImpactAcceptanceRadius",250]
];

true
