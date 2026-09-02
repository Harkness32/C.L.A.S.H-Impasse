if (!hasInterface) exitWith {true};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskClientStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskClientStarted = true;
ITW_CLASH_PlayerTaskClientReady = false;
ITW_CLASH_ClientArtilleryJobs = createHashMap;

ITW_CLASH_PlayerTaskClient_fnc_ArtilleryMarkerName = {
    params ["_jobId"];
    "ITW_CLASH_ARTY_RADIUS_" + ((_jobId splitString "-") joinString "_")
};

ITW_CLASH_PlayerTaskClient_fnc_DeleteArtilleryTargetArea = {
    params ["_entry"];
    if !(_entry isEqualType createHashMap) exitWith {false};
    private _markerName = _entry getOrDefault ["targetAreaMarker",""];
    if (_markerName isNotEqualTo "") then {
        deleteMarkerLocal _markerName;
    };
    true
};

ITW_CLASH_PlayerTaskClient_fnc_AssignArtilleryJob = {
    params [
        "_jobId","_vehicle","_allowedMagazines",
        ["_targetPosition",[]],["_targetRadius",150]
    ];
    if (
        isRemoteExecuted
        && {remoteExecutedOwner != 2}
    ) exitWith {false};
    if (
        !(_jobId isEqualType "")
        || {_jobId isEqualTo ""}
        || {isNull _vehicle}
        || {!(_allowedMagazines isEqualType [])}
        || {!(_targetPosition isEqualType [])}
        || {!(_targetRadius isEqualType 0)}
    ) exitWith {false};

    private _existing = ITW_CLASH_ClientArtilleryJobs getOrDefault [
        _jobId,createHashMap
    ];
    if (count _existing > 0) then {
        [_existing] call
            ITW_CLASH_PlayerTaskClient_fnc_DeleteArtilleryTargetArea;
    };

    private _markerName = "";
    if (count _targetPosition >= 2 && {_targetRadius > 0}) then {
        _markerName = [_jobId] call
            ITW_CLASH_PlayerTaskClient_fnc_ArtilleryMarkerName;
        deleteMarkerLocal _markerName;
        private _marker = createMarkerLocal [_markerName,_targetPosition];
        _marker setMarkerShapeLocal "ELLIPSE";
        _marker setMarkerBrushLocal "Border";
        _marker setMarkerColorLocal "ColorRed";
        _marker setMarkerSizeLocal [_targetRadius,_targetRadius];
        _marker setMarkerAlphaLocal 0.9;
    };

    ITW_CLASH_ClientArtilleryJobs set [
        _jobId,
        createHashMapFromArray [
            ["vehicle",_vehicle],
            ["allowedMagazines",+_allowedMagazines],
            ["targetPosition",+_targetPosition],
            ["targetRadius",_targetRadius],
            ["targetAreaMarker",_markerName],
            ["ehId",-1]
        ]
    ];
    _vehicle setVariable ["ITW_CLASH_ClientArtilleryJobId",_jobId];
    true
};

ITW_CLASH_PlayerTaskClient_fnc_ClearArtilleryJob = {
    params ["_jobId"];
    if (
        isRemoteExecuted
        && {remoteExecutedOwner != 2}
    ) exitWith {false};
    private _entry = ITW_CLASH_ClientArtilleryJobs getOrDefault [
        _jobId,createHashMap
    ];
    if (count _entry == 0) exitWith {false};
    private _vehicle = _entry getOrDefault ["vehicle",objNull];
    private _ehId = _entry getOrDefault ["ehId",-1];
    if (!isNull _vehicle && {_ehId >= 0}) then {
        _vehicle removeEventHandler ["Fired",_ehId];
    };
    [_entry] call ITW_CLASH_PlayerTaskClient_fnc_DeleteArtilleryTargetArea;
    if (!isNull _vehicle && {
        (_vehicle getVariable ["ITW_CLASH_ClientArtilleryJobId",""])
        == _jobId
    }) then {
        _vehicle setVariable ["ITW_CLASH_ClientArtilleryJobId",nil];
    };
    ITW_CLASH_ClientArtilleryJobs deleteAt _jobId;
    true
};

ITW_CLASH_PlayerTaskClient_fnc_InstallArtilleryEH = {
    params ["_jobId","_entry"];
    private _vehicle = _entry getOrDefault ["vehicle",objNull];
    if (isNull _vehicle || {!local _vehicle}) exitWith {false};
    if ((_entry getOrDefault ["ehId",-1]) >= 0) exitWith {true};

    private _ehId = _vehicle addEventHandler ["Fired",{
        params [
            "_vehicle","_weapon","_muzzle","_mode",
            "_ammo","_magazine","_projectile","_gunner"
        ];
        private _jobId = _vehicle getVariable [
            "ITW_CLASH_ClientArtilleryJobId",""
        ];
        if (_jobId isEqualTo "") exitWith {};
        private _entry = ITW_CLASH_ClientArtilleryJobs getOrDefault [
            _jobId,createHashMap
        ];
        if (count _entry == 0) exitWith {};
        if !(_magazine in (
            _entry getOrDefault ["allowedMagazines",[]]
        )) exitWith {};
        if !(player in crew _vehicle) exitWith {};

        private _shotId = format [
            "%1:%2:%3:%4",
            getPlayerUID player,
            round (diag_tickTime * 1000),
            netId _projectile,
            floor (random 1000000000)
        ];
        private _firingPosition = getPosATL _vehicle;
        [
            player,
            _jobId,
            _vehicle,
            _shotId,
            _magazine,
            _firingPosition
        ] remoteExecCall [
            "ITW_CLASH_PlayerArtillery_fnc_ReportFiredRemote",2
        ];

        [
            _projectile,
            player,
            _jobId,
            _vehicle,
            _shotId,
            _magazine,
            _firingPosition
        ] spawn {
            params [
                "_projectile","_reporter","_jobId","_vehicle",
                "_shotId","_magazine","_lastPosition"
            ];
            private _deadline = time + 240;
            waitUntil {
                sleep 0.05;
                if (!isNull _projectile) then {
                    _lastPosition = getPosATL _projectile;
                };
                isNull _projectile || {time >= _deadline}
            };
            if (time < _deadline) then {
                [
                    _reporter,
                    _jobId,
                    _vehicle,
                    _shotId,
                    _magazine,
                    _lastPosition
                ] remoteExecCall [
                    "ITW_CLASH_PlayerArtillery_fnc_ReportImpactRemote",2
                ];
            };
        };
    }];
    _entry set ["ehId",_ehId];
    ITW_CLASH_ClientArtilleryJobs set [_jobId,_entry];
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerArtilleryClientMonitor";
    while {true} do {
        {
            private _jobId = _x;
            private _entry = ITW_CLASH_ClientArtilleryJobs getOrDefault [
                _jobId,createHashMap
            ];
            private _vehicle = _entry getOrDefault ["vehicle",objNull];
            if (isNull _vehicle) then {
                [_entry] call
                    ITW_CLASH_PlayerTaskClient_fnc_DeleteArtilleryTargetArea;
                ITW_CLASH_ClientArtilleryJobs deleteAt _jobId;
            } else {
                if (local _vehicle) then {
                    [_jobId,_entry] call
                        ITW_CLASH_PlayerTaskClient_fnc_InstallArtilleryEH;
                } else {
                    private _ehId = _entry getOrDefault ["ehId",-1];
                    if (_ehId >= 0) then {
                        _vehicle removeEventHandler ["Fired",_ehId];
                        _entry set ["ehId",-1];
                        ITW_CLASH_ClientArtilleryJobs set [_jobId,_entry];
                    };
                };
            };
        } forEach keys ITW_CLASH_ClientArtilleryJobs;
        sleep 0.5;
    };
};

if (isServer) exitWith {
    ITW_CLASH_PlayerTaskClientReady = true;
    diag_log "CLASH PLAYER TASK CLIENT | ready | hosted artillery impact observer | red artillery target-area marker | server HAL toggle bridge retained";
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskClientBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.25;
        diag_tickTime >= _deadline || {
            !isNil "Action1ct" && {!isNil "Action2ct"} && {!isNil "Action3ct"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH PLAYER TASK CLIENT | native HAL action bind timeout";
    };

    ITW_CLASH_PlayerTaskClient_fnc_NativeAction1 = Action1ct;
    ITW_CLASH_PlayerTaskClient_fnc_NativeAction2 = Action2ct;
    ITW_CLASH_PlayerTaskClient_fnc_NativeAction3 = Action3ct;

    Action1ct = {
        private _result = _this call ITW_CLASH_PlayerTaskClient_fnc_NativeAction1;
        [player] remoteExecCall ["ITW_CLASH_PlayerTasks_fnc_CancelRemote",2];
        _result
    };
    Action2ct = {
        private _result = _this call ITW_CLASH_PlayerTaskClient_fnc_NativeAction2;
        [player,false] remoteExecCall ["ITW_CLASH_PlayerTasks_fnc_SetOptInRemote",2];
        _result
    };
    Action3ct = {
        private _result = _this call ITW_CLASH_PlayerTaskClient_fnc_NativeAction3;
        [player,true] remoteExecCall ["ITW_CLASH_PlayerTasks_fnc_SetOptInRemote",2];
        _result
    };

    ITW_CLASH_PlayerTaskClientReady = true;
    diag_log "CLASH PLAYER TASK CLIENT | ready | native HAL toggle bridged | artillery impact observer ready | red target-area marker ready";
};

true