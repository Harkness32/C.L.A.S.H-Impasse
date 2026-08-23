#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskSupportStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskSupportStarted = true;
ITW_CLASH_PlayerTaskSupportVersion = 2;
ITW_CLASH_PlayerTaskSupportReady = false;
ITW_CLASH_DisableNativeHC = true;
ITW_CLASH_PlayerTaskGroups = [];
ITW_CLASH_PlayerJobs = createHashMap;
ITW_CLASH_PlayerJobEvents = [];
ITW_CLASH_LogisticsPackages = [];
ITW_CLASH_PlayerJobTypes = [
    "COMBAT","TRANSPORT","MEDEVAC","LOGISTICS","ARTILLERY"
];
ITW_CLASH_PlayerAmmoDeliveryRadius = missionNamespace getVariable [
    "ITW_CLASH_PlayerAmmoDeliveryRadius",100
];
ITW_CLASH_PlayerAmmoJobTimeout = missionNamespace getVariable [
    "ITW_CLASH_PlayerAmmoJobTimeout",1800
];
ITW_CLASH_AmmoPackageMaxOutstandingPerHQ = missionNamespace getVariable [
    "ITW_CLASH_AmmoPackageMaxOutstandingPerHQ",1
];

ITW_CLASH_PlayerTasks_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["player-tasks-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER TASKS | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerTasks_fnc_RecordEvent = {
    params ["_type",["_payload",createHashMap]];
    private _event = createHashMapFromArray [
        ["type",_type],
        ["payload",_payload],
        ["time",time]
    ];
    ITW_CLASH_PlayerJobEvents pushBack _event;
    if (count ITW_CLASH_PlayerJobEvents > 200) then {
        ITW_CLASH_PlayerJobEvents deleteAt 0;
    };
    ["job-event",[_type,_payload]] call ITW_CLASH_PlayerTasks_fnc_Log;
    _event
};

ITW_CLASH_PlayerTasks_fnc_GroupFromSubject = {
    params ["_subject"];
    if (_subject isEqualType grpNull) exitWith {_subject};
    if (_subject isEqualType objNull && {!isNull _subject}) exitWith {group _subject};
    grpNull
};

ITW_CLASH_PlayerTasks_fnc_HumanRoster = {
    params ["_group"];
    if (isNull _group) exitWith {[]};
    (units _group select {isPlayer _x}) apply {
        [getPlayerUID _x,name _x]
    }
};

ITW_CLASH_PlayerTasks_fnc_GetSubscriptions = {
    params ["_subject"];
    private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
    if (isNull _group) exitWith {[]};

    private _subscriptions = +(_group getVariable [
        "ITW_CLASH_PlayerJobSubscriptions",[]
    ]);
    _subscriptions = _subscriptions select {
        _x isEqualType ""
        && {_x in ITW_CLASH_PlayerJobTypes}
    };
    _subscriptions arrayIntersect ITW_CLASH_PlayerJobTypes
};

ITW_CLASH_PlayerTasks_fnc_IsSubscribed = {
    params ["_subject","_jobType"];
    if !(_jobType isEqualType "") exitWith {false};
    _jobType = toUpperANSI _jobType;
    _jobType in ([_subject] call
        ITW_CLASH_PlayerTasks_fnc_GetSubscriptions)
};

ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle = {
    params ["_group"];
    if (isNull _group) exitWith {objNull};

    private _leader = leader _group;
    private _vehicle = if (isNull _leader) then {objNull} else {
        vehicle _leader
    };
    if (!isNull _leader && {_vehicle == _leader}) then {
        _vehicle = objNull;
    };
    if (isNull _vehicle) then {
        {
            if (isPlayer _x && {vehicle _x != _x}) exitWith {
                _vehicle = vehicle _x;
            };
        } forEach units _group;
    };
    if (isNull _vehicle || {!alive _vehicle} || {!canMove _vehicle}) exitWith {
        objNull
    };
    _vehicle
};

ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity = {
    params ["_vehicle"];
    if (isNull _vehicle) exitWith {false};
    private _configured = getNumber (
        configFile >> "CfgVehicles" >> typeOf _vehicle >> "transportSoldier"
    );
    _configured > 0 || {
        (fullCrew [_vehicle,"cargo",true]) isNotEqualTo []
    }
};

ITW_CLASH_PlayerTasks_fnc_HasArtilleryCapability = {
    params ["_vehicle"];
    if (isNull _vehicle) exitWith {false};
    private _supportTypes = getArray (
        configFile >> "CfgVehicles" >> typeOf _vehicle
        >> "availableForSupportTypes"
    );
    "Artillery" in _supportTypes
    && {(getArtilleryAmmo [_vehicle]) isNotEqualTo []}
};

ITW_CLASH_PlayerTasks_fnc_HasExecutableSubscription = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    private _subscriptions = [_group] call
        ITW_CLASH_PlayerTasks_fnc_GetSubscriptions;
    if (_subscriptions isEqualTo []) exitWith {false};
    if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {
        false
    };
    if ("COMBAT" in _subscriptions) exitWith {true};

    private _vehicle = [_group] call
        ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
    if (
        ("TRANSPORT" in _subscriptions || {"MEDEVAC" in _subscriptions})
        && {[_vehicle] call
            ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity}
    ) exitWith {true};
    if (
        "LOGISTICS" in _subscriptions
        && {!isNull ([_group] call
            ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle)}
    ) exitWith {true};
    if (
        "ARTILLERY" in _subscriptions
        && {[_vehicle] call
            ITW_CLASH_PlayerTasks_fnc_HasArtilleryCapability}
    ) exitWith {true};
    false
};

ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState = {
    params ["_subject",["_source","sync"]];
    private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
    if (isNull _group || {isNil "ITW_PlayerSide"} || {
        side _group != ITW_PlayerSide
    }) exitWith {false};

    private _subscriptions = [_group] call
        ITW_CLASH_PlayerTasks_fnc_GetSubscriptions;
    private _active = _subscriptions isNotEqualTo [];
    private _executable = _active && {
        [_group] call
            ITW_CLASH_PlayerTasks_fnc_HasExecutableSubscription
    };
    private _previous = _group getVariable [
        "ITW_CLASH_PlayerTaskAvailable",-1
    ];

    _group setVariable ["EnableHALActions",true,true];
    _group setVariable ["ITW_CLASH_PlayerTaskInitialized",true,true];
    _group setVariable ["ITW_CLASH_PlayerTaskOptIn",_active,true];
    _group setVariable ["ITW_CLASH_PlayerTaskAvailable",_executable,true];
    _group setVariable ["Unable",!_executable,true];
    _group setVariable ["BUnable",!_executable,true];

    if (_active) then {
        ITW_CLASH_PlayerTaskGroups pushBackUnique _group;
    } else {
        ITW_CLASH_PlayerTaskGroups = ITW_CLASH_PlayerTaskGroups - [_group];
    };

    if !(_previous isEqualTo _executable) then {
        ["availability-changed",[
            if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId
            } else {str _group},
            _executable,
            _subscriptions,
            _source
        ]] call ITW_CLASH_PlayerTasks_fnc_Log;
    };
    true
};

ITW_CLASH_PlayerTasks_fnc_SetSubscriptions = {
    params ["_subject","_subscriptions",["_source","api"]];
    private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
    if (
        isNull _group
        || {isNil "ITW_PlayerSide"}
        || {side _group != ITW_PlayerSide}
        || {!(_subscriptions isEqualType [])}
    ) exitWith {false};

    _subscriptions = _subscriptions select {
        _x isEqualType ""
        && {_x in ITW_CLASH_PlayerJobTypes}
    };
    _subscriptions = _subscriptions arrayIntersect
        ITW_CLASH_PlayerJobTypes;
    _group setVariable [
        "ITW_CLASH_PlayerJobSubscriptions",_subscriptions,true
    ];
    [_group,_source] call
        ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;

    ["subscriptions-changed",[
        if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
            [_group] call ITW_CLASH_DualHAL_fnc_GroupId
        } else {str _group},
        _subscriptions,
        _source,
        [_group] call ITW_CLASH_PlayerTasks_fnc_HumanRoster
    ]] call ITW_CLASH_PlayerTasks_fnc_Log;

    if (!isNil "ITW_CLASH_DualHAL_fnc_SyncIncluded") then {
        call ITW_CLASH_DualHAL_fnc_SyncIncluded;
    };
    true
};

ITW_CLASH_PlayerTasks_fnc_SetSubscription = {
    params ["_subject","_jobType","_enabled",["_source","api"]];
    if !(_jobType isEqualType "" && {_enabled isEqualType true}) exitWith {
        false
    };
    _jobType = toUpperANSI _jobType;
    if !(_jobType in ITW_CLASH_PlayerJobTypes) exitWith {false};

    private _subscriptions = [_subject] call
        ITW_CLASH_PlayerTasks_fnc_GetSubscriptions;
    if (_enabled) then {
        _subscriptions pushBackUnique _jobType;
    } else {
        _subscriptions = _subscriptions - [_jobType];
    };
    [_subject,_subscriptions,_source] call
        ITW_CLASH_PlayerTasks_fnc_SetSubscriptions
};

ITW_CLASH_PlayerTasks_fnc_SetOptIn = {
    params ["_subject","_enabled"];
    [
        _subject,
        if (_enabled) then {+ITW_CLASH_PlayerJobTypes} else {[]},
        "legacy-opt-in"
    ] call ITW_CLASH_PlayerTasks_fnc_SetSubscriptions
};

ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid = {
    params ["_player",["_leaderRequired",true]];
    _player isEqualType objNull
    && {!isNull _player}
    && {isRemoteExecuted}
    && {remoteExecutedOwner == owner _player}
    && {isPlayer _player}
    && {!_leaderRequired || {leader group _player == _player}}
};

ITW_CLASH_PlayerTasks_fnc_SendEmploymentState = {
    params ["_player","_success","_message"];
    if (isNull _player || {!isPlayer _player}) exitWith {false};
    [
        _success,
        _message,
        [group _player] call
            ITW_CLASH_PlayerTasks_fnc_GetSubscriptions
    ] remoteExecCall [
        "ITW_CLASH_PlayerEmployment_fnc_ReceiveState",owner _player
    ];
    true
};

ITW_CLASH_PlayerTasks_fnc_SetSubscriptionRemote = {
    params ["_player","_jobType","_enabled"];
    if !([_player,true] call
        ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid
    ) exitWith {
        if ([_player,false] call
            ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid
        ) then {
            [
                _player,false,
                "Only the group leader can change HAL employment."
            ] call ITW_CLASH_PlayerTasks_fnc_SendEmploymentState;
        };
        false
    };

    private _success = [
        _player,_jobType,_enabled,"player-menu"
    ] call ITW_CLASH_PlayerTasks_fnc_SetSubscription;
    [
        _player,
        _success,
        if (_success) then {
            format [
                "HAL employment updated: %1 %2.",
                toUpperANSI _jobType,
                if (_enabled) then {"enabled"} else {"disabled"}
            ]
        } else {
            "HAL employment update rejected."
        }
    ] call ITW_CLASH_PlayerTasks_fnc_SendEmploymentState;
    _success
};

ITW_CLASH_PlayerTasks_fnc_SetAllSubscriptionsRemote = {
    params ["_player","_enabled"];
    if !([_player,true] call
        ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid
    ) exitWith {
        if ([_player,false] call
            ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid
        ) then {
            [
                _player,false,
                "Only the group leader can change HAL employment."
            ] call ITW_CLASH_PlayerTasks_fnc_SendEmploymentState;
        };
        false
    };
    if !(_enabled isEqualType true) exitWith {false};

    private _success = [
        _player,
        if (_enabled) then {+ITW_CLASH_PlayerJobTypes} else {[]},
        "player-menu-all"
    ] call ITW_CLASH_PlayerTasks_fnc_SetSubscriptions;
    [
        _player,
        _success,
        if (_enabled) then {
            "All HAL employment channels enabled."
        } else {
            "All HAL employment channels disabled."
        }
    ] call ITW_CLASH_PlayerTasks_fnc_SendEmploymentState;
    _success
};

ITW_CLASH_PlayerTasks_fnc_SetOptInRemote = {
    params ["_player","_enabled"];
    if !([_player,true] call
        ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid
    ) exitWith {false};
    private _success = [_player,_enabled] call
        ITW_CLASH_PlayerTasks_fnc_SetOptIn;
    [
        _player,_success,
        if (_enabled) then {
            "All HAL employment channels enabled."
        } else {
            "All HAL employment channels disabled."
        }
    ] call ITW_CLASH_PlayerTasks_fnc_SendEmploymentState;
    _success
};

ITW_CLASH_PlayerTasks_fnc_CancelRemote = {
    params ["_player"];
    if !(_player isEqualType objNull) exitWith {false};
    if (isNull _player || {!isRemoteExecuted} || {
        remoteExecutedOwner != owner _player
    } || {!isPlayer _player}) exitWith {false};
    [_player] call ITW_CLASH_PlayerTasks_fnc_CancelGroupJob
};

ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle = {
    params ["_group"];
    if (isNull _group) exitWith {objNull};
    private _leader = leader _group;
    if (isNull _leader) exitWith {objNull};
    private _vehicle = vehicle _leader;
    if (_vehicle == _leader || {!(_vehicle isKindOf "Helicopter")} || {
        !alive _vehicle || {!canMove _vehicle}
    }) exitWith {objNull};

    private _maxCargo = getNumber (
        configFile >> "CfgVehicles" >> typeOf _vehicle >> "slingLoadMaxCargoMass"
    );
    if (_maxCargo <= 0) exitWith {objNull};
    _vehicle
};

ITW_CLASH_PlayerTasks_fnc_SyncLogisticsRole = {
    params ["_group"];
    if (isNull _group) exitWith {false};

    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {
        grpNull
    };
    if (isNull _hq) exitWith {false};

    private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle;
    private _eligible = (
        [_group,"LOGISTICS"] call
            ITW_CLASH_PlayerTasks_fnc_IsSubscribed
        && {!(_group getVariable ["Unable",false])}
        && {!(_group getVariable ["ITW_CLASH_AuthorityHold",false])}
        && {!isNull _vehicle}
    );
    if (_eligible) then {
        private _knownBoxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
        _knownBoxes = _knownBoxes select {!isNull _x && {alive _x}};
        if (_knownBoxes isNotEqualTo []) then {
            _eligible = (
                _knownBoxes findIf {_vehicle canSlingLoad _x}
            ) >= 0;
        };
    };
    private _previous = _group getVariable [
        "ITW_CLASH_PlayerLogisticsAir",false
    ];

    private _drops = +(_hq getVariable ["RydHQ_AmmoDrop",[]]);
    if (_eligible) then {
        _drops pushBackUnique _group;
    } else {
        _drops = _drops - [_group];
    };
    _hq setVariable ["RydHQ_AmmoDrop",_drops];
    _group setVariable ["ITW_CLASH_PlayerLogisticsAir",_eligible,true];

    if (_eligible != _previous) then {
        ["logistics-role",[
            if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId
            } else {str _group},
            _eligible,
            if (isNull _vehicle) then {"<none>"} else {typeOf _vehicle}
        ]] call ITW_CLASH_PlayerTasks_fnc_Log;
    };
    _eligible
};

ITW_CLASH_PlayerTasks_fnc_SyncIncludedBase =
    ITW_CLASH_DualHAL_fnc_SyncIncluded;
ITW_CLASH_DualHAL_fnc_SyncIncluded = {
    private _result = call ITW_CLASH_PlayerTasks_fnc_SyncIncludedBase;

    ITW_CLASH_PlayerTaskGroups = ITW_CLASH_PlayerTaskGroups select {
        !isNull _x
        && {side _x == ITW_PlayerSide}
        && {{alive _x && {isPlayer _x}} count units _x > 0}
        && {([_x] call
            ITW_CLASH_PlayerTasks_fnc_GetSubscriptions) isNotEqualTo []}
    };

    if (!isNull ITW_CLASH_BLUFORHQ) then {
        private _included = +(
            ITW_CLASH_BLUFORHQ getVariable ["RydHQ_Included",[]]
        );
        {_included pushBackUnique _x} forEach ITW_CLASH_PlayerTaskGroups;
        ITW_CLASH_BLUFORHQ setVariable ["RydHQ_Included",_included];
        RydHQB_Included = +_included;
    };
    _result
};

ITW_CLASH_PlayerTasks_fnc_GetAmmoPackageClasses = {
    params ["_side"];
    private _classes = if (_side == ITW_PlayerSide) then {
        missionNamespace getVariable ["ITW_CLASH_PlayerAmmoPackageClasses",[]]
    } else {
        missionNamespace getVariable ["ITW_CLASH_EnemyAmmoPackageClasses",[]]
    };

    if (_classes isEqualTo []) then {
        _classes = switch (_side) do {
            case west: {["Box_NATO_AmmoVeh_F"]};
            case east: {["Box_East_AmmoVeh_F"]};
            case resistance: {["Box_IND_AmmoVeh_F"]};
            default {["Box_NATO_AmmoVeh_F"]};
        };
    };
    _classes select {
        _x isEqualType ""
        && {_x isNotEqualTo ""}
        && {isClass (configFile >> "CfgVehicles" >> _x)}
    }
};

ITW_CLASH_PlayerTasks_fnc_OutstandingPackages = {
    params ["_hq"];
    ITW_CLASH_LogisticsPackages = ITW_CLASH_LogisticsPackages select {
        !isNull _x
    };
    ITW_CLASH_LogisticsPackages select {
        (_x getVariable ["ITW_CLASH_LogisticsPackageHQ",grpNull]) == _hq
        && {
            (_x getVariable ["ITW_CLASH_LogisticsPackageState",""]) in [
                "AVAILABLE_AT_REAR","RESERVED","IN_TRANSIT"
            ]
        }
    }
};

ITW_CLASH_PlayerTasks_fnc_SetPackageState = {
    params ["_box","_state",["_reason",""]];
    if (isNull _box) exitWith {false};
    _box setVariable ["ITW_CLASH_LogisticsPackageState",_state,true];
    _box setVariable ["ITW_CLASH_LogisticsPackageStateAt",time,true];
    _box setVariable ["ITW_CLASH_LogisticsPackageReason",_reason,true];
    ["package-state",[
        _box getVariable ["ITW_CLASH_CheckbookRequest",""],
        _state,_reason,getPosATL _box
    ]] call ITW_CLASH_PlayerTasks_fnc_Log;
    true
};

ITW_CLASH_PlayerTasks_fnc_PackageProvider = {
    private _request = _this;
    private _side = _request getOrDefault ["side",sideUnknown];
    private _requester = _request getOrDefault ["requester",grpNull];
    private _requirements = _request getOrDefault [
        "requirements",createHashMap
    ];
    private _hq = _requirements getOrDefault ["hq",grpNull];
    if (isNull _hq) then {
        _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;
    };
    if (isNull _hq) exitWith {
        [_request,"DEFERRED",[],"commander-unavailable","ammo-package-v1"] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _outstanding = [_hq] call
        ITW_CLASH_PlayerTasks_fnc_OutstandingPackages;
    if (count _outstanding >= ITW_CLASH_AmmoPackageMaxOutstandingPerHQ) exitWith {
        [_request,"DEFERRED",[],"package-already-outstanding","ammo-package-v1"] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _reference = +(_requirements getOrDefault [
        "reference",
        if (isNull _requester) then {getPosATL leader _hq} else {
            getPosATL leader _requester
        }
    ]);
    private _generation = [
        _side,"LOGISTICS_PACKAGE_AMMO","REAR_AIR",_reference
    ] call ITW_CLASH_Generation_fnc_Resolve;
    if ((_generation getOrDefault ["status",""]) != "RESOLVED") exitWith {
        [
            _request,"DEFERRED",[],
            _generation getOrDefault ["reason","node-unresolved"],
            "ammo-package-v1",createHashMap,_generation
        ] call ITW_CLASH_Checkbook_fnc_Response
    };

    private _classes = [_side] call
        ITW_CLASH_PlayerTasks_fnc_GetAmmoPackageClasses;
    if (_classes isEqualTo []) exitWith {
        [_request,"DENIED",[],"no-ammo-package-class","ammo-package-v1"] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _origin = +(_generation get "origin");
    private _spawn = [
        _origin,20,100,4,0,0.35,0,[],_origin
    ] call BIS_fnc_findSafePos;
    if (_spawn isEqualTo [] || {_spawn isEqualTo [0]}) then {
        _spawn = _origin getPos [30,random 360];
    };
    if (count _spawn < 3) then {_spawn pushBack 0};
    _spawn set [2,0];

    private _class = selectRandom _classes;
    private _box = _class createVehicle _spawn;
    if (isNull _box) exitWith {
        [_request,"FAILED",[],"package-spawn-failed","ammo-package-v1"] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    _box setDir random 360;
    _box setAmmoCargo 1;
    _box allowDamage true;
    _box setVariable ["persistent",true];
    _box setVariable ["ITW_CLASH_LogisticsPackage",true,true];
    _box setVariable ["ITW_CLASH_LogisticsPayload","AMMO",true];
    _box setVariable ["ITW_CLASH_LogisticsPackageHQ",_hq];
    _box setVariable ["ITW_CLASH_LogisticsPackageSide",_side,true];
    _box setVariable [
        "ITW_CLASH_CheckbookRequest",_request get "id",true
    ];
    _box setVariable ["ITW_CLASH_LogisticsPackageOrigin",+_spawn,true];
    [_box,"AVAILABLE_AT_REAR","checkbook-approved"] call
        ITW_CLASH_PlayerTasks_fnc_SetPackageState;

    ITW_CLASH_LogisticsPackages pushBack _box;
    private _boxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
    _boxes pushBackUnique _box;
    _hq setVariable ["RydHQ_AmmoBoxes",_boxes];
    {_x addCuratorEditableObjects [[_box],true]} forEach allCurators;

    private _billing = createHashMapFromArray [
        ["model","ITW_OUTSTANDING_PACKAGE_CAP_V1"],
        ["ticketCost",0],
        ["outstanding",count ITW_CLASH_LogisticsPackages],
        ["maxOutstandingPerHQ",ITW_CLASH_AmmoPackageMaxOutstandingPerHQ]
    ];
    private _metadata = createHashMapFromArray [
        ["payload","AMMO"],
        ["class",_class],
        ["halAmmoBoxPool",true]
    ];

    ["package-provided",[
        _request get "id",_side,_class,
        _generation get "rearBase",_spawn
    ]] call ITW_CLASH_PlayerTasks_fnc_Log;

    [
        _request,"APPROVED",[_box],"provided","ammo-package-v1",
        _billing,_generation,_metadata
    ] call ITW_CLASH_Checkbook_fnc_Response
};

[
    "LOGISTICS_PACKAGE_AMMO",
    ITW_CLASH_PlayerTasks_fnc_PackageProvider
] call ITW_CLASH_Checkbook_fnc_RegisterProvider;

ITW_CLASH_PlayerTasks_fnc_NewJob = {
    params ["_group","_box","_target","_hq"];
    private _requestId = _box getVariable [
        "ITW_CLASH_CheckbookRequest","external-box"
    ];
    private _jobId = format [
        "CLASH-JOB-%1-%2",
        round (diag_tickTime * 1000),
        _requestId
    ];
    private _roster = [_group] call ITW_CLASH_PlayerTasks_fnc_HumanRoster;
    private _job = createHashMapFromArray [
        ["id",_jobId],
        ["type","LOGISTICS_AMMO_SLING"],
        ["state","ASSIGNED"],
        ["group",_group],
        ["package",_box],
        ["target",_target],
        ["hq",_hq],
        ["participants",_roster],
        ["assignedAt",time],
        ["activeAt",-1],
        ["completedAt",-1],
        ["outcome",""]
    ];
    ITW_CLASH_PlayerJobs set [_jobId,_job];
    ["JOB_ASSIGNED",_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    _jobId
};

ITW_CLASH_PlayerTasks_fnc_SetJobState = {
    params ["_jobId","_state",["_outcome",""]];
    private _job = ITW_CLASH_PlayerJobs getOrDefault [
        _jobId,createHashMap
    ];
    if (count _job == 0) exitWith {false};
    _job set ["state",_state];
    _job set ["outcome",_outcome];
    if (_state == "ACTIVE") then {_job set ["activeAt",time]};
    if (_state in ["COMPLETED","FAILED","CANCELED"]) then {
        _job set ["completedAt",time]
    };
    ITW_CLASH_PlayerJobs set [_jobId,_job];
    ["JOB_" + _state,_job] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    true
};

ITW_CLASH_PlayerTasks_fnc_ReleasePackage = {
    params ["_box","_hq","_recoverable",["_reason","job-ended"]];
    if (isNull _box) exitWith {false};

    if (_recoverable) then {
        _box setAmmoCargo 1;
        [_box,"AVAILABLE_AT_REAR",_reason] call
            ITW_CLASH_PlayerTasks_fnc_SetPackageState;
        private _boxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
        _boxes pushBackUnique _box;
        _hq setVariable ["RydHQ_AmmoBoxes",_boxes];
    } else {
        _box setAmmoCargo 0;
        [_box,"LOST",_reason] call
            ITW_CLASH_PlayerTasks_fnc_SetPackageState;
        [_box] spawn {
            params ["_box"];
            private _deleteAt = time + 300;
            waitUntil {
                sleep 10;
                isNull _box || {
                    time >= _deleteAt && {
                        (allPlayers findIf {_x distance2D _box < 100}) < 0
                    }
                }
            };
            if (!isNull _box) then {deleteVehicle _box};
        };
    };
    true
};

ITW_CLASH_PlayerTasks_fnc_PackageDelivered = {
    params ["_box","_target","_hq",["_reason","delivered"]];
    if (isNull _box) exitWith {false};

    _box setAmmoCargo 1;
    [_box,"DELIVERED",_reason] call
        ITW_CLASH_PlayerTasks_fnc_SetPackageState;

    private _drops = +(_hq getVariable ["RydHQ_OrdnanceDrops",[]]);
    _drops pushBackUnique _box;
    _hq setVariable ["RydHQ_OrdnanceDrops",_drops];

    private _targetUnit = if (_target isKindOf "Man") then {
        _target
    } else {
        effectiveCommander _target
    };
    if (!isNull _targetUnit) then {
        private _boxed = +(_hq getVariable ["RydHQ_Boxed",[]]);
        _boxed pushBackUnique (group _targetUnit);
        _hq setVariable ["RydHQ_Boxed",_boxed];
    };
    true
};

ITW_CLASH_PlayerTasks_fnc_MonitorAIPackage = {
    params ["_box","_target","_hq"];
    if (isNull _box || {isNull _target} || {isNull _hq}) exitWith {};

    [_box,"RESERVED","hal-ai-assigned"] call
        ITW_CLASH_PlayerTasks_fnc_SetPackageState;
    private _origin = +(_box getVariable [
        "ITW_CLASH_LogisticsPackageOrigin",getPosATL _box
    ]);
    private _pickedUp = false;
    private _delivered = false;
    private _deadline = time + ITW_CLASH_PlayerAmmoJobTimeout;

    waitUntil {
        sleep 3;
        if (isNull _box || {isNull _target} || {
            !alive _box || {!alive _target}
        }) exitWith {true};

        private _carried = !isNull attachedTo _box || {
            !isNull ropeAttachedTo _box
        };
        if (_carried && {!_pickedUp}) then {
            _pickedUp = true;
            [_box,"IN_TRANSIT","hal-ai-carrier"] call
                ITW_CLASH_PlayerTasks_fnc_SetPackageState;
        };

        _delivered = (
            _pickedUp
            && {!_carried}
            && {_box distance2D _target <= ITW_CLASH_PlayerAmmoDeliveryRadius}
            && {isTouchingGround _box || {(getPosATL _box)#2 < 2}}
            && {abs speed _box < 5}
        );
        _delivered || {time >= _deadline}
    };

    if (!isNull _box && {_delivered}) then {
        [_box,_target,_hq,"hal-ai-delivered"] call
            ITW_CLASH_PlayerTasks_fnc_PackageDelivered;
    } else {
        if (!isNull _box) then {
            private _recoverable = !_pickedUp && {
                _box distance2D _origin < 100
            };
            [_box,_hq,_recoverable,"hal-ai-delivery-failed"] call
                ITW_CLASH_PlayerTasks_fnc_ReleasePackage;
        };
    };
};

ITW_CLASH_PlayerTasks_fnc_ClearAmmoReservation = {
    params ["_hq","_target"];
    if (isNull _hq || {isNull _target}) exitWith {false};

    private _points = +(_hq getVariable ["RydHQ_AmmoPoints",[]]);
    _hq setVariable ["RydHQ_AmmoPoints",_points - [_target]];

    private _targetUnit = if (_target isKindOf "Man") then {
        _target
    } else {
        effectiveCommander _target
    };
    if (!isNull _targetUnit) then {
        private _supported = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
        _hq setVariable [
            "RydHQ_ASupportedG",_supported - [group _targetUnit]
        ];
    };
    true
};

ITW_CLASH_PlayerTasks_fnc_PlayerAmmoJob = {
    params [
        "_vehicle","_target",["_hollow",[]],["_soldiers",[]],
        ["_drop",true],["_box",objNull],["_hq",grpNull]
    ];
    if (isNull _vehicle || {isNull _target} || {isNull _box} || {
        isNull _hq
    }) exitWith {};

    private _driver = assignedDriver _vehicle;
    if (isNull _driver) then {_driver = driver _vehicle};
    if (isNull _driver) exitWith {};
    private _group = group _driver;
    private _players = units _group select {isPlayer _x};
    if (_players isEqualTo []) exitWith {};

    if !(_vehicle canSlingLoad _box) exitWith {
        [_box,_hq,true,"carrier-cannot-sling-package"] call
            ITW_CLASH_PlayerTasks_fnc_ReleasePackage;
        [_hq,_target] call
            ITW_CLASH_PlayerTasks_fnc_ClearAmmoReservation;
        _group setVariable ["Busy" + str _group,false];
        ["ammo-job-rejected",[
            groupId _group,typeOf _vehicle,typeOf _box,
            "carrier-cannot-sling-package"
        ]] call ITW_CLASH_PlayerTasks_fnc_Log;
    };

    private _jobId = [_group,_box,_target,_hq] call
        ITW_CLASH_PlayerTasks_fnc_NewJob;
    _group setVariable ["ITW_CLASH_PlayerAmmoJobId",_jobId,true];
    _group setVariable ["ITW_CLASH_PlayerAmmoJobCancel",false,true];
    _group setVariable ["Busy" + str _group,true];

    [_box,"RESERVED","hal-player-assigned"] call
        ITW_CLASH_PlayerTasks_fnc_SetPackageState;
    _box setVariable ["ITW_CLASH_LogisticsAssignedGroup",_group,true];
    _box setVariable ["ITW_CLASH_LogisticsTarget",_target,true];

    private _ammoPoints = +(_hq getVariable ["RydHQ_AmmoPoints",[]]);
    _ammoPoints pushBackUnique _target;
    _hq setVariable ["RydHQ_AmmoPoints",_ammoPoints];

    private _taskId = "ITW_" + _jobId;
    private _targetUnit = if (_target isKindOf "Man") then {
        _target
    } else {
        effectiveCommander _target
    };
    private _targetName = if (isNull _targetUnit) then {
        typeOf _target
    } else {
        groupId (group _targetUnit)
    };
    [
        _players,
        _taskId,
        [
            format [
                "Sling-load the ammunition package at the rear logistics node and deliver it within %1 meters of %2.",
                ITW_CLASH_PlayerAmmoDeliveryRadius,
                _targetName
            ],
            "HAL Logistics: Ammunition Sling",
            ""
        ],
        _box,
        "ASSIGNED",
        1,
        true,
        "rearm",
        true
    ] call BIS_fnc_taskCreate;

    ["ammo-job-assigned",[
        _jobId,groupId _group,typeOf _vehicle,typeOf _box,
        _targetName,[_group] call ITW_CLASH_PlayerTasks_fnc_HumanRoster
    ]] call ITW_CLASH_PlayerTasks_fnc_Log;

    private _origin = +(_box getVariable [
        "ITW_CLASH_LogisticsPackageOrigin",getPosATL _box
    ]);
    private _pickedUp = false;
    private _success = false;
    private _canceled = false;
    private _deadline = time + ITW_CLASH_PlayerAmmoJobTimeout;

    waitUntil {
        sleep 2;
        if (isNull _box || {isNull _target} || {
            !alive _box || {!alive _target} || {
                !alive _vehicle || {!canMove _vehicle}
            }
        }) exitWith {true};
        if (_group getVariable ["ITW_CLASH_PlayerAmmoJobCancel",false]) exitWith {
            _canceled = true;
            true
        };
        if ({alive _x && {isPlayer _x}} count units _group == 0) exitWith {true};

        private _carried = !isNull attachedTo _box || {
            !isNull ropeAttachedTo _box
        };
        if (_carried && {!_pickedUp}) then {
            _pickedUp = true;
            [_box,"IN_TRANSIT","player-sling-attached"] call
                ITW_CLASH_PlayerTasks_fnc_SetPackageState;
            [_jobId,"ACTIVE","package-picked-up"] call
                ITW_CLASH_PlayerTasks_fnc_SetJobState;
            [_taskId,[_target,true]] call BIS_fnc_taskSetDestination;
        };

        _success = (
            _pickedUp
            && {!_carried}
            && {_box distance2D _target <= ITW_CLASH_PlayerAmmoDeliveryRadius}
            && {isTouchingGround _box || {(getPosATL _box)#2 < 2}}
            && {abs speed _box < 5}
        );
        _success || {time >= _deadline}
    };

    if (!isNull _box && {_success}) then {
        [_box,_target,_hq,"hal-player-delivered"] call
            ITW_CLASH_PlayerTasks_fnc_PackageDelivered;
        [_jobId,"COMPLETED","delivered"] call
            ITW_CLASH_PlayerTasks_fnc_SetJobState;
        [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
    } else {
        private _state = if (_canceled) then {"CANCELED"} else {"FAILED"};
        private _outcome = if (_canceled) then {
            "player-denied-task"
        } else {
            if (time >= _deadline) then {"timeout"} else {"asset-or-target-lost"}
        };
        [_jobId,_state,_outcome] call
            ITW_CLASH_PlayerTasks_fnc_SetJobState;
        [_taskId,if (_canceled) then {"CANCELED"} else {"FAILED"},true] call
            BIS_fnc_taskSetState;

        if (!isNull _box) then {
            private _recoverable = !_pickedUp && {
                _box distance2D _origin < 100
            };
            [_box,_hq,_recoverable,_outcome] call
                ITW_CLASH_PlayerTasks_fnc_ReleasePackage;
        };
    };

    _group setVariable ["Busy" + str _group,false];
    _group setVariable ["ITW_CLASH_PlayerAmmoJobId",nil,true];
    _group setVariable ["ITW_CLASH_PlayerAmmoJobCancel",nil,true];

    [_hq,_target] call
        ITW_CLASH_PlayerTasks_fnc_ClearAmmoReservation;
};

ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {
    params ["_subject"];
    private _group = [_subject] call ITW_CLASH_PlayerTasks_fnc_GroupFromSubject;
    if (isNull _group) exitWith {false};
    if ((_group getVariable ["ITW_CLASH_PlayerAmmoJobId",""]) isEqualTo "") exitWith {
        false
    };
    _group setVariable ["ITW_CLASH_PlayerAmmoJobCancel",true,true];
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskHALBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.25;
        diag_tickTime >= _deadline || {
            !isNil "Action1ct"
            && {!isNil "Action2ct"}
            && {!isNil "Action3ct"}
            && {!isNil "HAL_GoAmmoSupp"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        ["bind-timeout",[]] call ITW_CLASH_PlayerTasks_fnc_Log;
    };

    ITW_CLASH_PlayerTasks_fnc_NativeAction1 = Action1ct;
    ITW_CLASH_PlayerTasks_fnc_NativeAction2 = Action2ct;
    ITW_CLASH_PlayerTasks_fnc_NativeAction3 = Action3ct;
    ITW_CLASH_PlayerTasks_fnc_NativeGoAmmoSupp = HAL_GoAmmoSupp;

    Action1ct = {
        private _result = _this call ITW_CLASH_PlayerTasks_fnc_NativeAction1;
        private _unit = _this param [0,objNull];
        if (isNull _unit && {hasInterface}) then {_unit = player};
        if (!isNull _unit) then {
            [_unit] call ITW_CLASH_PlayerTasks_fnc_CancelGroupJob;
        };
        _result
    };
    Action2ct = {
        private _result = _this call ITW_CLASH_PlayerTasks_fnc_NativeAction2;
        private _unit = _this param [0,objNull];
        if (isNull _unit && {hasInterface}) then {_unit = player};
        if (!isNull _unit) then {
            [_unit,false] call ITW_CLASH_PlayerTasks_fnc_SetOptIn;
        };
        _result
    };
    Action3ct = {
        private _result = _this call ITW_CLASH_PlayerTasks_fnc_NativeAction3;
        private _unit = _this param [0,objNull];
        if (isNull _unit && {hasInterface}) then {_unit = player};
        if (!isNull _unit) then {
            [_unit,true] call ITW_CLASH_PlayerTasks_fnc_SetOptIn;
        };
        _result
    };

    HAL_GoAmmoSupp = {
        private _vehicle = _this param [0,objNull];
        private _target = _this param [1,objNull];
        private _drop = _this param [4,false];
        private _box = _this param [5,objNull];
        private _hq = _this param [6,grpNull];

        private _driver = if (isNull _vehicle) then {objNull} else {
            assignedDriver _vehicle
        };
        if (isNull _driver && {!isNull _vehicle}) then {_driver = driver _vehicle};
        private _providerGroup = if (isNull _driver) then {grpNull} else {
            group _driver
        };
        private _humanProvider = !isNull _providerGroup && {
            (units _providerGroup findIf {isPlayer _x}) >= 0
        };
        private _playerProvider = _humanProvider && {
            [_providerGroup,"LOGISTICS"] call
                ITW_CLASH_PlayerTasks_fnc_IsSubscribed
        } && {
            _providerGroup getVariable [
                "ITW_CLASH_PlayerLogisticsAir",false
            ]
        } && {!(_providerGroup getVariable ["Unable",false])};

        if (_humanProvider && {!_playerProvider}) exitWith {
            if (!isNull _box) then {
                private _boxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
                _boxes pushBackUnique _box;
                _hq setVariable ["RydHQ_AmmoBoxes",_boxes];
                if (_box getVariable [
                    "ITW_CLASH_LogisticsPackage",false
                ]) then {
                    [_box,"AVAILABLE_AT_REAR","player-provider-opted-out"] call
                        ITW_CLASH_PlayerTasks_fnc_SetPackageState;
                };
            };
            [_hq,_target] call
                ITW_CLASH_PlayerTasks_fnc_ClearAmmoReservation;
            _providerGroup setVariable ["Busy" + str _providerGroup,false];
            ["ammo-job-rejected",[
                groupId _providerGroup,"player-provider-opted-out"
            ]] call ITW_CLASH_PlayerTasks_fnc_Log;
            false
        };

        if (_drop && {!isNull _box} && {
            _box getVariable ["ITW_CLASH_LogisticsPackage",false]
        }) then {
            _box setVariable ["ITW_CLASH_LogisticsAssignedGroup",_providerGroup,true];
            _box setVariable ["ITW_CLASH_LogisticsTarget",_target,true];
            [_box,"RESERVED",if (_playerProvider) then {
                "hal-player-assigned"
            } else {
                "hal-ai-assigned"
            }] call ITW_CLASH_PlayerTasks_fnc_SetPackageState;
        };

        if (_drop && {_playerProvider} && {!isNull _box}) exitWith {
            _this spawn ITW_CLASH_PlayerTasks_fnc_PlayerAmmoJob
        };

        if (_drop && {!isNull _box} && {
            _box getVariable ["ITW_CLASH_LogisticsPackage",false]
        }) then {
            [_box,_target,_hq] spawn
                ITW_CLASH_PlayerTasks_fnc_MonitorAIPackage;
        };
        _this call ITW_CLASH_PlayerTasks_fnc_NativeGoAmmoSupp
    };

    RydxHQ_SlingDrop = true;
    publicVariable "RydxHQ_SlingDrop";
    ITW_CLASH_PlayerTaskSupportReady = true;
    diag_log format [
        "CLASH BOOT | player-task-support-ready | version=%1 nativeToggle=compat employmentMenu=clash persistentSubscriptions=true vehicleResets=false slingDrop=true humanExecutor=true sharedRosterLedger=true highCommand=false",
        ITW_CLASH_PlayerTaskSupportVersion
    ];
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskRoster";
    waitUntil {
        sleep 0.5;
        (
            !isNil "ITW_PlayerSide"
            && {missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]}
        )
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        private _current = [];
        {
            private _group = group _x;
            if (isNull _group || {side _group != ITW_PlayerSide}) then {continue};
            _current pushBackUnique _group;
            _group setVariable ["EnableHALActions",true,true];

            if !(_group getVariable [
                "ITW_CLASH_PlayerTaskInitialized",false
            ]) then {
                private _initialSubscriptions = if (
                    _group getVariable ["ITW_CLASH_PlayerTaskOptIn",false]
                ) then {
                    +ITW_CLASH_PlayerJobTypes
                } else {
                    []
                };
                [
                    _group,_initialSubscriptions,"roster-init"
                ] call ITW_CLASH_PlayerTasks_fnc_SetSubscriptions;
            } else {
                [_group,"roster-refresh"] call
                    ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState;
            };
            [_group] call ITW_CLASH_PlayerTasks_fnc_SyncLogisticsRole;
        } forEach allPlayers;

        {
            if !(_x in _current) then {
                private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForGroup;
                if (!isNull _hq) then {
                    private _drops = +(_hq getVariable ["RydHQ_AmmoDrop",[]]);
                    _hq setVariable ["RydHQ_AmmoDrop",_drops - [_x]];
                };
                ITW_CLASH_PlayerTaskGroups =
                    ITW_CLASH_PlayerTaskGroups - [_x];
            };
        } forEach +ITW_CLASH_PlayerTaskGroups;

        call ITW_CLASH_DualHAL_fnc_SyncIncluded;
        sleep 2;
    };
};

true
