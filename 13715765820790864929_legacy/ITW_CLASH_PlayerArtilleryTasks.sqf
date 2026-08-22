
#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerArtilleryTasksStarted",false]) exitWith {true};

ITW_CLASH_PlayerArtilleryTasksStarted = true;
ITW_CLASH_PlayerArtilleryTasksReady = false;
ITW_CLASH_PlayerArtilleryTasksVersion = 1;
ITW_CLASH_PlayerArtillerySerial = 0;
ITW_CLASH_PlayerArtilleryMissionRadius = missionNamespace getVariable [
    "ITW_CLASH_PlayerArtilleryMissionRadius",200
];
ITW_CLASH_PlayerArtilleryDangerCloseRadius = missionNamespace getVariable [
    "ITW_CLASH_PlayerArtilleryDangerCloseRadius",300
];
ITW_CLASH_PlayerArtilleryTaskTimeout = missionNamespace getVariable [
    "ITW_CLASH_PlayerArtilleryTaskTimeout",900
];
ITW_CLASH_PlayerArtilleryMaxRounds = missionNamespace getVariable [
    "ITW_CLASH_PlayerArtilleryMaxRounds",8
];
ITW_CLASH_PlayerArtilleryImpactRatio = missionNamespace getVariable [
    "ITW_CLASH_PlayerArtilleryImpactRatio",0.67
];

ITW_CLASH_PlayerArtillery_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_Log") then {
        ["artillery-" + _event,_payload] call ITW_CLASH_PlayerTasks_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER ARTILLERY | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerArtillery_fnc_IsHumanGroup = {
    params ["_group"];
    !isNull _group && {
        (units _group findIf {isPlayer _x}) >= 0
    }
};

ITW_CLASH_PlayerArtillery_fnc_GetVehicle = {
    params ["_group"];
    if (isNull _group) exitWith {objNull};

    private _vehicles = [];
    {
        private _vehicle = vehicle _x;
        if (
            !isNull _vehicle
            && {_vehicle != _x}
            && {alive _vehicle}
            && {canMove _vehicle}
        ) then {
            _vehicles pushBackUnique _vehicle;
        };
    } forEach units _group;

    private _index = _vehicles findIf {
        private _vehicle = _x;
        private _supportTypes = getArray (
            configFile >> "CfgVehicles" >> typeOf _vehicle >> "availableForSupportTypes"
        );
        private _playerGunner = (
            fullCrew [_vehicle,"gunner",true]
        ) findIf {
            private _unit = _x param [0,objNull];
            !isNull _unit && {isPlayer _unit}
        };
        (
            "Artillery" in _supportTypes
            && {_playerGunner >= 0}
            && {(getArtilleryAmmo [_vehicle]) isNotEqualTo []}
        )
    };
    if (_index < 0) exitWith {objNull};
    _vehicles#_index
};

ITW_CLASH_PlayerArtillery_fnc_OutsideRearSanctuary = {
    params ["_vehicle","_side"];
    if (
        isNull _vehicle
        || {isNil "ITW_CLASH_Generation_fnc_Resolve"}
        || {isNil "ITW_CLASH_GenerationSanctuaryRadius"}
    ) exitWith {false};

    private _generation = [
        _side,"PLAYER_ARTILLERY","INTERSTITIAL",getPosATL _vehicle
    ] call ITW_CLASH_Generation_fnc_Resolve;
    if ((_generation getOrDefault ["status",""]) != "RESOLVED") exitWith {false};

    _vehicle distance2D (_generation get "rearPosition")
        >= ITW_CLASH_GenerationSanctuaryRadius
};

ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle = {
    params ["_group"];
    if (
        isNull _group
        || {!(_group getVariable ["ITW_CLASH_PlayerTaskOptIn",false])}
        || {_group getVariable ["Unable",false]}
        || {_group getVariable ["ITW_CLASH_AuthorityHold",false]}
        || {_group getVariable ["RydHQ_BatteryBusy",false]}
        || {_group getVariable ["Busy" + str _group,false]}
        || {(_group getVariable ["ITW_CLASH_PlayerArtilleryJobId",""]) isNotEqualTo ""}
    ) exitWith {objNull};

    private _vehicle = [_group] call ITW_CLASH_PlayerArtillery_fnc_GetVehicle;
    if (isNull _vehicle) exitWith {objNull};
    if !(_vehicle getVariable ["ITW_CLASH_PlayerGarageAsset",false]) exitWith {objNull};
    if (
        (_vehicle getVariable ["ITW_CLASH_PlayerArtyDeploymentState",""])
        != "DEPLOYED"
    ) exitWith {objNull};
    if !([_vehicle,side _group] call
        ITW_CLASH_PlayerArtillery_fnc_OutsideRearSanctuary
    ) exitWith {objNull};
    _vehicle
};

ITW_CLASH_PlayerArtillery_fnc_DangerClose = {
    params ["_position","_friends"];
    private _unsafe = false;
    {
        if (isNull _x) then {continue};
        {
            if (
                alive _x
                && {_x distance2D _position
                    < ITW_CLASH_PlayerArtilleryDangerCloseRadius}
            ) exitWith {_unsafe = true};
        } forEach units _x;
        if (_unsafe) exitWith {};
    } forEach _friends;
    _unsafe
};

ITW_CLASH_PlayerArtillery_fnc_PushClientAssignment = {
    params ["_group","_jobId","_vehicle","_allowedMagazines"];
    private _owners = [];
    {
        if (isPlayer _x) then {_owners pushBackUnique (owner _x)};
    } forEach units _group;
    {
        [_jobId,_vehicle,_allowedMagazines] remoteExecCall [
            "ITW_CLASH_PlayerTaskClient_fnc_AssignArtilleryJob",_x
        ];
    } forEach _owners;
    true
};

ITW_CLASH_PlayerArtillery_fnc_ClearClientAssignment = {
    params ["_group","_jobId"];
    private _owners = [];
    {
        if (isPlayer _x) then {_owners pushBackUnique (owner _x)};
    } forEach units _group;
    {
        [_jobId] remoteExecCall [
            "ITW_CLASH_PlayerTaskClient_fnc_ClearArtilleryJob",_x
        ];
    } forEach _owners;
    true
};

ITW_CLASH_PlayerArtillery_fnc_NewJob = {
    params [
        "_group","_vehicle","_target","_targetPosition","_hq",
        "_allowedMagazines","_authorizedRounds"
    ];

    ITW_CLASH_PlayerArtillerySerial = ITW_CLASH_PlayerArtillerySerial + 1;
    private _jobId = format [
        "CLASH-ARTY-%1-%2",
        round (diag_tickTime * 1000),
        ITW_CLASH_PlayerArtillerySerial
    ];
    private _roster = [_group] call ITW_CLASH_PlayerTasks_fnc_HumanRoster;
    private _requiredImpacts = (
        ceil (_authorizedRounds * ITW_CLASH_PlayerArtilleryImpactRatio)
    ) max 1;
    private _taskId = "ITW_" + _jobId;
    private _job = createHashMapFromArray [
        ["id",_jobId],
        ["type","ARTILLERY_FIRE_MISSION"],
        ["state","ASSIGNED"],
        ["group",_group],
        ["vehicle",_vehicle],
        ["target",_target],
        ["targetPosition",+_targetPosition],
        ["targetRadius",ITW_CLASH_PlayerArtilleryMissionRadius],
        ["hq",_hq],
        ["participants",_roster],
        ["allowedMagazines",+_allowedMagazines],
        ["authorizedRounds",_authorizedRounds],
        ["requiredImpacts",_requiredImpacts],
        ["roundsFired",0],
        ["roundsResolved",0],
        ["roundsOnTarget",0],
        ["shotIds",[]],
        ["resolvedShotIds",[]],
        ["assignedAt",time],
        ["activeAt",-1],
        ["completedAt",-1],
        ["outcome",""],
        ["taskId",_taskId]
    ];

    ITW_CLASH_PlayerJobs set [_jobId,_job];
    ["JOB_ASSIGNED",_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;

    private _players = units _group select {isPlayer _x};
    [
        _players,
        _taskId,
        [
            format [
                "HAL fire mission. Deliver %1 HE rounds into the marked %2 meter target area. HAL selected the target; you choose the firing position. Danger-close fire is not authorized.",
                _authorizedRounds,
                ITW_CLASH_PlayerArtilleryMissionRadius
            ],
            "HAL Artillery: Fire Mission",
            ""
        ],
        _targetPosition,
        "ASSIGNED",
        1,
        true,
        "destroy",
        true
    ] call BIS_fnc_taskCreate;

    _group setVariable ["ITW_CLASH_PlayerArtilleryJobId",_jobId,true];
    _group setVariable ["ITW_CLASH_PlayerArtilleryJobCancel",false,true];
    _group setVariable ["RydHQ_BatteryBusy",true];
    _group setVariable ["Busy" + str _group,true];
    _vehicle setVariable ["ITW_CLASH_PlayerArtilleryJobId",_jobId,true];

    [_group,_jobId,_vehicle,_allowedMagazines] call
        ITW_CLASH_PlayerArtillery_fnc_PushClientAssignment;

    ["assigned",[
        _jobId,
        groupId _group,
        typeOf _vehicle,
        _targetPosition,
        _authorizedRounds,
        _requiredImpacts,
        _roster
    ]] call ITW_CLASH_PlayerArtillery_fnc_Log;
    _jobId
};

ITW_CLASH_PlayerArtillery_fnc_FinishJob = {
    params ["_jobId","_state","_outcome"];
    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    if (count _job == 0) exitWith {false};
    if ((_job getOrDefault ["state",""]) in [
        "COMPLETED","FAILED","CANCELED"
    ]) exitWith {false};

    private _group = _job getOrDefault ["group",grpNull];
    private _vehicle = _job getOrDefault ["vehicle",objNull];
    private _taskId = _job getOrDefault ["taskId",""];

    ITW_CLASH_PlayerJobs set [_jobId,_job];
    [_jobId,_state,_outcome] call ITW_CLASH_PlayerTasks_fnc_SetJobState;
    _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,_job];

    if (!isNull _group) then {
        _group setVariable ["ITW_CLASH_PlayerArtilleryJobId",nil,true];
        _group setVariable ["ITW_CLASH_PlayerArtilleryJobCancel",nil,true];
        _group setVariable ["RydHQ_BatteryBusy",false];
        _group setVariable ["Busy" + str _group,false];
        [_group,_jobId] call
            ITW_CLASH_PlayerArtillery_fnc_ClearClientAssignment;
    };
    if (!isNull _vehicle) then {
        _vehicle setVariable ["ITW_CLASH_PlayerArtilleryJobId",nil,true];
    };
    if (_taskId isNotEqualTo "") then {
        private _taskState = switch (_state) do {
            case "COMPLETED": {"SUCCEEDED"};
            case "CANCELED": {"CANCELED"};
            default {"FAILED"};
        };
        [_taskId,_taskState,true] call BIS_fnc_taskSetState;
    };

    if (_state == "COMPLETED") then {
        ["ARTILLERY_MISSION_COMPLETED",_job] call
            ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    } else {
        ["ARTILLERY_MISSION_" + _state,_job] call
            ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    };
    ["finished",[_jobId,_state,_outcome]] call
        ITW_CLASH_PlayerArtillery_fnc_Log;
    true
};

ITW_CLASH_PlayerArtillery_fnc_ValidateRemoteReport = {
    params ["_reporter","_jobId","_vehicle"];
    if (
        !isRemoteExecuted
        || {isNull _reporter}
        || {!isPlayer _reporter}
        || {remoteExecutedOwner != owner _reporter}
        || {isNull _vehicle}
    ) exitWith {createHashMap};

    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    if (
        count _job == 0
        || {(_job getOrDefault ["vehicle",objNull]) != _vehicle}
        || {(_job getOrDefault ["state",""]) in [
            "COMPLETED","FAILED","CANCELED"
        ]}
    ) exitWith {createHashMap};

    private _uid = getPlayerUID _reporter;
    private _roster = _job getOrDefault ["participants",[]];
    if ((_roster findIf {(_x param [0,""]) == _uid}) < 0) exitWith {
        createHashMap
    };
    _job
};

ITW_CLASH_PlayerArtillery_fnc_ReportFiredRemote = {
    params [
        "_reporter","_jobId","_vehicle","_shotId","_magazine","_firingPosition"
    ];
    private _job = [
        _reporter,_jobId,_vehicle
    ] call ITW_CLASH_PlayerArtillery_fnc_ValidateRemoteReport;
    if (count _job == 0) exitWith {false};
    if !(_reporter in crew _vehicle) exitWith {false};
    if !(_magazine in (_job getOrDefault ["allowedMagazines",[]])) exitWith {
        false
    };
    if !(_shotId isEqualType "" && {_shotId isNotEqualTo ""}) exitWith {false};

    private _shotIds = +(_job getOrDefault ["shotIds",[]]);
    if (_shotId in _shotIds) exitWith {false};
    private _roundsFired = _job getOrDefault ["roundsFired",0];
    private _authorized = _job getOrDefault ["authorizedRounds",0];
    if (_roundsFired >= _authorized) exitWith {
        ["ARTILLERY_ROUND_EXCESS",createHashMapFromArray [
            ["jobId",_jobId],
            ["reporter",getPlayerUID _reporter],
            ["magazine",_magazine]
        ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
        false
    };

    _shotIds pushBack _shotId;
    _job set ["shotIds",_shotIds];
    _job set ["roundsFired",_roundsFired + 1];
    if ((_job getOrDefault ["state",""]) == "ASSIGNED") then {
        _job set ["activeAt",time];
        ITW_CLASH_PlayerJobs set [_jobId,_job];
        [_jobId,"ACTIVE","first-authorized-round"] call
            ITW_CLASH_PlayerTasks_fnc_SetJobState;
        _vehicle setVariable [
            "ITW_CLASH_ArtilleryEmission",
            [_jobId,+_firingPosition,time],
            true
        ];
        ["ARTILLERY_FIRING_POSITION_EMITTED",createHashMapFromArray [
            ["jobId",_jobId],
            ["vehicle",_vehicle],
            ["group",_job get "group"],
            ["position",+_firingPosition],
            ["time",time]
        ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    } else {
        ITW_CLASH_PlayerJobs set [_jobId,_job];
    };
    ["round-fired",[
        _jobId,
        _roundsFired + 1,
        _authorized,
        _magazine,
        _firingPosition
    ]] call ITW_CLASH_PlayerArtillery_fnc_Log;
    true
};

ITW_CLASH_PlayerArtillery_fnc_ReportImpactRemote = {
    params [
        "_reporter","_jobId","_vehicle","_shotId","_magazine","_impactPosition"
    ];
    private _job = [
        _reporter,_jobId,_vehicle
    ] call ITW_CLASH_PlayerArtillery_fnc_ValidateRemoteReport;
    if (count _job == 0) exitWith {false};
    if !(_shotId in (_job getOrDefault ["shotIds",[]])) exitWith {false};
    if (_shotId in (_job getOrDefault ["resolvedShotIds",[]])) exitWith {
        false
    };
    if !(_impactPosition isEqualType [] && {count _impactPosition >= 2}) exitWith {
        false
    };

    private _resolved = +(_job getOrDefault ["resolvedShotIds",[]]);
    _resolved pushBack _shotId;
    _job set ["resolvedShotIds",_resolved];
    private _roundsResolved = (_job getOrDefault ["roundsResolved",0]) + 1;
    _job set ["roundsResolved",_roundsResolved];

    private _targetPosition = _job getOrDefault ["targetPosition",[]];
    private _radius = _job getOrDefault [
        "targetRadius",ITW_CLASH_PlayerArtilleryMissionRadius
    ];
    private _onTarget = (
        _targetPosition isNotEqualTo []
        && {_impactPosition distance2D _targetPosition <= _radius}
    );
    if (_onTarget) then {
        _job set [
            "roundsOnTarget",
            (_job getOrDefault ["roundsOnTarget",0]) + 1
        ];
    };
    ITW_CLASH_PlayerJobs set [_jobId,_job];

    ["ARTILLERY_ROUND_IMPACT",createHashMapFromArray [
        ["jobId",_jobId],
        ["magazine",_magazine],
        ["position",+_impactPosition],
        ["onTarget",_onTarget],
        ["resolved",_roundsResolved]
    ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;

    private _authorized = _job getOrDefault ["authorizedRounds",0];
    private _fired = _job getOrDefault ["roundsFired",0];
    if (_fired >= _authorized && {_roundsResolved >= _authorized}) then {
        private _hits = _job getOrDefault ["roundsOnTarget",0];
        private _required = _job getOrDefault ["requiredImpacts",1];
        if (_hits >= _required) then {
            [_jobId,"COMPLETED","validated-impact-pattern"] call
                ITW_CLASH_PlayerArtillery_fnc_FinishJob;
        } else {
            [_jobId,"FAILED","insufficient-impacts-in-target-area"] call
                ITW_CLASH_PlayerArtillery_fnc_FinishJob;
        };
    };
    true
};

ITW_CLASH_PlayerArtillery_fnc_Assign = {
    params ["_artilleryGroups","_target","_friends","_hq"];
    if (isNull _target || {isNil "RYD_ArtyMission"}) exitWith {""};
    private _targetPosition = getPosATL _target;
    if ([
        _targetPosition,_friends
    ] call ITW_CLASH_PlayerArtillery_fnc_DangerClose) exitWith {
        ["danger-close-denied",[_targetPosition]] call
            ITW_CLASH_PlayerArtillery_fnc_Log;
        ""
    };

    private _amount = (
        missionNamespace getVariable ["RydART_Amount",6]
    ) min ITW_CLASH_PlayerArtilleryMaxRounds;
    _amount = (round _amount) max 1;
    private _selectedGroup = grpNull;
    private _selectedVehicle = objNull;
    private _selectedResult = [];

    {
        private _vehicle = [_x] call
            ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle;
        if (isNull _vehicle) then {continue};
        private _result = [
            _targetPosition,[_x],"HE",_amount,objNull
        ] call RYD_ArtyMission;
        if (
            _result isEqualType []
            && {count _result >= 5}
            && {_result#0}
            && {(_result#1) isNotEqualTo []}
        ) exitWith {
            _selectedGroup = _x;
            _selectedVehicle = _vehicle;
            _selectedResult = _result;
        };
    } forEach _artilleryGroups;

    if (isNull _selectedGroup || {isNull _selectedVehicle}) exitWith {""};
    private _magazines = (_selectedResult#3) arrayIntersect (_selectedResult#3);
    if (_magazines isEqualTo []) exitWith {""};
    private _authorized = (_amount min (_selectedResult#4)) max 1;
    _authorized = round _authorized;

    [
        _selectedGroup,
        _selectedVehicle,
        _target,
        _targetPosition,
        _hq,
        _magazines,
        _authorized
    ] call ITW_CLASH_PlayerArtillery_fnc_NewJob
};

ITW_CLASH_PlayerArtillery_fnc_Monitor = {
    params ["_jobId"];
    private _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
    if (count _job == 0) exitWith {};
    private _deadline = time + ITW_CLASH_PlayerArtilleryTaskTimeout;

    waitUntil {
        sleep 2;
        _job = ITW_CLASH_PlayerJobs getOrDefault [_jobId,createHashMap];
        if (count _job == 0) exitWith {true};
        if ((_job getOrDefault ["state",""]) in [
            "COMPLETED","FAILED","CANCELED"
        ]) exitWith {true};

        private _group = _job getOrDefault ["group",grpNull];
        private _vehicle = _job getOrDefault ["vehicle",objNull];
        if (
            isNull _group
            || {isNull _vehicle}
            || {!alive _vehicle}
            || {{alive _x && {isPlayer _x}} count units _group == 0}
        ) exitWith {
            [_jobId,"FAILED","provider-lost"] call
                ITW_CLASH_PlayerArtillery_fnc_FinishJob;
            true
        };
        if (_group getVariable [
            "ITW_CLASH_PlayerArtilleryJobCancel",false
        ]) exitWith {
            [_jobId,"CANCELED","player-denied-task"] call
                ITW_CLASH_PlayerArtillery_fnc_FinishJob;
            true
        };
        if (time >= _deadline) exitWith {
            [_jobId,"FAILED","timeout"] call
                ITW_CLASH_PlayerArtillery_fnc_FinishJob;
            true
        };
        false
    };
};

[] spawn {
    scriptName "ITW_CLASH_PlayerArtilleryHALBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.25;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable [
                "ITW_CLASH_PlayerTaskSupportReady",false
            ]
            && {!isNil "RYD_CFF"}
            && {!isNil "RYD_CFF_TGT"}
            && {!isNil "RYD_ArtyMission"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        ["bind-timeout",[]] call ITW_CLASH_PlayerArtillery_fnc_Log;
    };

    ITW_CLASH_PlayerArtillery_fnc_NativeCFF = RYD_CFF;
    RYD_CFF = {
        private _artilleryGroups = +(_this param [0,[]]);
        private _knownEnemies = +(_this param [1,[]]);
        private _friends = +(_this param [3,[]]);
        private _leader = _this param [5,objNull];
        private _hq = if (isNull _leader) then {grpNull} else {group _leader};

        private _humanGroups = _artilleryGroups select {
            [_x] call ITW_CLASH_PlayerArtillery_fnc_IsHumanGroup
        };
        private _aiGroups = _artilleryGroups - _humanGroups;
        private _eligiblePlayers = _humanGroups select {
            !isNull ([_x] call
                ITW_CLASH_PlayerArtillery_fnc_EligibleVehicle)
        };

        private _jobId = "";
        if (_eligiblePlayers isNotEqualTo [] && {
            _knownEnemies isNotEqualTo []
        }) then {
            private _target = [_knownEnemies] call RYD_CFF_TGT;
            if (!isNull _target) then {
                _jobId = [
                    _eligiblePlayers,_target,_friends,_hq
                ] call ITW_CLASH_PlayerArtillery_fnc_Assign;
            };
        };

        if (_jobId isNotEqualTo "") exitWith {
            [_jobId] spawn ITW_CLASH_PlayerArtillery_fnc_Monitor;
        };
        if (_aiGroups isEqualTo []) exitWith {};

        private _nativeArgs = +_this;
        _nativeArgs set [0,_aiGroups];
        _nativeArgs call ITW_CLASH_PlayerArtillery_fnc_NativeCFF
    };

    ITW_CLASH_PlayerArtillery_fnc_CancelGroupJobBase =
        ITW_CLASH_PlayerTasks_fnc_CancelGroupJob;
    ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {
        private _baseResult = _this call
            ITW_CLASH_PlayerArtillery_fnc_CancelGroupJobBase;
        private _subject = _this param [0,grpNull];
        private _group = [_subject] call
            ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
        if (isNull _group) exitWith {_baseResult};
        private _jobId = _group getVariable [
            "ITW_CLASH_PlayerArtilleryJobId",""
        ];
        if (_jobId isEqualTo "") exitWith {_baseResult};
        _group setVariable [
            "ITW_CLASH_PlayerArtilleryJobCancel",true,true
        ];
        true
    };

    ITW_CLASH_PlayerArtilleryTasksReady = true;
    diag_log format [
        "CLASH BOOT | player-artillery-tasks-ready | version=%1 halTargeting=true humanFireControl=true HEOnly=true impactValidated=true economyNeutral=true",
        ITW_CLASH_PlayerArtilleryTasksVersion
    ];
};

true

