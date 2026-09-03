#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ThunderRunStarted",false]) exitWith {true};

ITW_CLASH_ThunderRunStarted = true;
ITW_CLASH_ThunderRunReady = false;
ITW_CLASH_ThunderRunVersion = 1;

ITW_CLASH_ThunderRunTakeoverRadius = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunTakeoverRadius",3000
];
ITW_CLASH_ThunderRunIngressHeight = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunIngressHeight",25
];
ITW_CLASH_ThunderRunPopupRadius = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunPopupRadius",700
];
ITW_CLASH_ThunderRunDropHeight = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunDropHeight",130
];
ITW_CLASH_ThunderRunReleaseLead = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunReleaseLead",180
];
ITW_CLASH_ThunderRunFlareStart = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunFlareStart",1500
];
ITW_CLASH_ThunderRunColdRadius = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunColdRadius",2500
];
ITW_CLASH_ThunderRunEgressDistance = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunEgressDistance",1000
];
ITW_CLASH_ThunderRunTransitHeight = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunTransitHeight",120
];
ITW_CLASH_ThunderRunAirDenyRadius = missionNamespace getVariable [
    "ITW_CLASH_ThunderRunAirDenyRadius",5000
];

ITW_CLASH_ThunderRuns = createHashMap;

ITW_CLASH_ThunderRun_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_HALLogistics_fnc_Log") then {
        ["thunder-run-" + _event,_payload] call ITW_CLASH_HALLogistics_fnc_Log;
    } else {
        diag_log format ["CLASH THUNDER RUN | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_ThunderRun_fnc_TargetGroup = {
    params ["_target"];
    if (!isNil "ITW_CLASH_AmmoDispatch_fnc_TargetGroup") exitWith {
        [_target] call ITW_CLASH_AmmoDispatch_fnc_TargetGroup
    };
    if (isNull _target) exitWith {grpNull};
    if (_target isKindOf "Man") exitWith {group _target};
    private _commander = effectiveCommander _target;
    if (isNull _commander) exitWith {grpNull};
    group _commander
};

/*
    Use HAL's intelligence lists and HAL's own point-to-segment geometry. This
    deliberately does not create another contact model; it asks a different
    doctrinal question of the picture HAL already maintains.
*/
ITW_CLASH_ThunderRun_fnc_CorridorStats = {
    params ["_origin","_destination",["_groups",[]]];
    private _minimum = 1e12;
    private _within1500 = 0;
    private _within1000 = 0;
    {
        private _threatGroup = _x;
        if (
            isNull _threatGroup
            || {{alive _x} count units _threatGroup <= 0}
        ) then {continue};
        private _threatLeader = leader _threatGroup;
        if (isNull _threatLeader) then {continue};
        private _distance = [
            _origin,_destination,getPosATL (vehicle _threatLeader)
        ] call RYD_PointToSecDst;
        if (_distance < _minimum) then {_minimum = _distance};
        if (_distance < 1500) then {_within1500 = _within1500 + 1};
        if (_distance < 1000) then {_within1000 = _within1000 + 1};
    } forEach _groups;
    [_minimum,_within1500,_within1000]
};

ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter = {
    params ["_veh"];
    if (isNull _veh) exitWith {[]};
    private _result = [];

    {
        private _magazine = _x param [0,""];
        private _turret = _x param [1,[]];
        private _rounds = _x param [2,0];
        if (_magazine isEqualTo "" || {_rounds <= 0}) then {continue};

        private _ammoClass = getText (
            configFile >> "CfgMagazines" >> _magazine >> "ammo"
        );
        if (_ammoClass isEqualTo "") then {continue};
        private _simulation = toLowerANSI getText (
            configFile >> "CfgAmmo" >> _ammoClass >> "simulation"
        );
        if (_simulation != "shotcm") then {continue};

        private _operator = _veh turretUnit _turret;
        if (isNull _operator) then {_operator = driver _veh};
        if (isNull _operator) then {continue};

        {
            private _weapon = _x;
            private _weaponCfg = configFile >> "CfgWeapons" >> _weapon;
            private _weaponMagazines = getArray (_weaponCfg >> "magazines");
            if !(_magazine in _weaponMagazines) then {continue};

            private _modes = getArray (_weaponCfg >> "modes");
            private _mode = if (_modes isEqualTo []) then {_weapon} else {_modes#0};
            _result = [_operator,_weapon,_mode,_rounds,_turret];
            break;
        } forEach (_veh weaponsTurret _turret);

        if (_result isNotEqualTo []) exitWith {};
    } forEach (magazinesAllTurrets [_veh,true]);

    _result
};

ITW_CLASH_ThunderRun_fnc_InitFlareBudget = {
    params ["_state"];
    private _emitter = _state getOrDefault ["countermeasureEmitter",[]];
    private _rounds = if (_emitter isEqualTo []) then {0} else {_emitter#3};
    private _budget = (_rounds min 40) max 0;

    private _ingress = floor (_budget * 0.10);
    private _popup = floor (_budget * 0.35);
    private _release = floor (_budget * 0.15);
    private _egress = (_budget - _ingress - _popup - _release) max 0;

    _state set ["flareLimits",createHashMapFromArray [
        ["INGRESS",_ingress],["POPUP",_popup],
        ["RELEASE",_release],["EGRESS",_egress]
    ]];
    _state set ["flareUsed",createHashMap];
    _state set ["nextFlareAt",0];
    _state
};

ITW_CLASH_ThunderRun_fnc_MaybeFlare = {
    params ["_state","_phase"];
    private _emitter = _state getOrDefault ["countermeasureEmitter",[]];
    if (_emitter isEqualTo []) exitWith {false};

    private _limits = _state getOrDefault ["flareLimits",createHashMap];
    private _used = _state getOrDefault ["flareUsed",createHashMap];
    private _limit = _limits getOrDefault [_phase,0];
    private _spent = _used getOrDefault [_phase,0];
    if (
        _spent >= _limit
        || {time < (_state getOrDefault ["nextFlareAt",0])}
    ) exitWith {false};

    _emitter params ["_operator","_weapon","_mode"];
    if (isNull _operator || {!alive _operator}) exitWith {false};

    _operator forceWeaponFire [_weapon,_mode];
    _used set [_phase,_spent + 1];
    _state set ["flareUsed",_used];

    private _cadence = switch (_phase) do {
        case "POPUP": {1.5};
        case "RELEASE": {1.2};
        case "EGRESS": {1.8};
        default {3};
    };
    _state set ["nextFlareAt",time + _cadence];
    true
};

ITW_CLASH_ThunderRun_fnc_Classify = {
    params ["_veh","_target","_hq"];
    private _result = createHashMapFromArray [
        ["state","NORMAL"],["reason","not-eligible"],
        ["aaDistance",1e12],["airDistance",1e12],
        ["groundDistance",1e12],["missionDistance",0],["outerAA",4000]
    ];
    if (
        isNull _veh || {isNull _target} || {isNull _hq}
        || {!(_veh isKindOf "Helicopter")}
        || {isNil "RYD_PointToSecDst"}
    ) exitWith {_result};

    private _origin = getPosATL _veh;
    private _destination = getPosATL _target;
    private _missionDistance = _origin distance2D _destination;

    // Distance is exposure, not a separate doctrine axis. Longer flights widen
    // the band where a slow sling sortie is considered contested.
    private _outerAA = if (_missionDistance < 2000) then {2500} else {
        if (_missionDistance < 5000) then {4000} else {5000}
    };

    private _aa = [
        _origin,_destination,+(_hq getVariable ["RydHQ_AAthreat",[]])
    ] call ITW_CLASH_ThunderRun_fnc_CorridorStats;
    private _air = [
        _origin,_destination,+(_hq getVariable ["RydHQ_Airthreat",[]])
    ] call ITW_CLASH_ThunderRun_fnc_CorridorStats;
    private _ground = [
        _origin,_destination,+(_hq getVariable ["RydHQ_KnEnemiesG",[]])
    ] call ITW_CLASH_ThunderRun_fnc_CorridorStats;

    _aa params ["_aaDistance","_aa1500","_aa1000"];
    private _airDistance = _air#0;
    private _groundDistance = _ground#0;

    _result set ["aaDistance",_aaDistance];
    _result set ["airDistance",_airDistance];
    _result set ["groundDistance",_groundDistance];
    _result set ["missionDistance",_missionDistance];
    _result set ["outerAA",_outerAA];

    // Thunder Run reduces exposure to ground fire. It is not an answer to
    // hostile aircraft or a dense overlapping AA corridor.
    if (_airDistance < ITW_CLASH_ThunderRunAirDenyRadius) exitWith {
        _result set ["state","AIR_DENIED"];
        _result set ["reason","enemy-air-corridor"];
        _result
    };
    if (_aa1000 >= 3 || {_aa1500 >= 4}) exitWith {
        _result set ["state","AIR_DENIED"];
        _result set ["reason","aa-concentration"];
        _result
    };

    private _countermeasures = [
        _veh
    ] call ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter;
    if (_aaDistance < _outerAA && {_countermeasures isEqualTo []}) exitWith {
        _result set ["state","AIR_DENIED"];
        _result set ["reason","aa-no-countermeasures"];
        _result
    };

    if (_aaDistance < 1500 || {_groundDistance < 500}) exitWith {
        _result set ["state","HOT"];
        _result set ["reason",if (_aaDistance < 1500) then {
            "aa-hot-corridor"
        } else {
            "ground-hot-corridor"
        }];
        _result
    };

    if (_aaDistance < _outerAA || {_groundDistance < 1000}) exitWith {
        _result set ["state","CONTESTED"];
        _result set ["reason",if (_aaDistance < _outerAA) then {
            "aa-contested-corridor"
        } else {
            "ground-contested-corridor"
        }];
        _result
    };

    _result set ["state","SAFE"];
    _result set ["reason","corridor-clear"];
    _result
};

ITW_CLASH_ThunderRun_fnc_IsEligible = {
    params ["_veh","_target","_box","_hq","_providerHuman"];
    if (
        _providerHuman
        || {isNull _veh} || {isNull _target} || {isNull _box}
        || {isNull _hq} || {!alive _veh} || {!canMove _veh}
        || {!(_veh isKindOf "Helicopter")}
        || {!isNull getSlingLoad _veh}
        || {isNil "RYD_AmmoDrop"}
        || {isNil "ITW_CLASH_Service_fnc_FindEntry"}
        || {isNil "ITW_CLASH_ServiceHome_fnc_ResolveAndStore"}
    ) exitWith {false};

    private _poolId = _veh getVariable ["ITW_CLASH_ServicePoolId",""];
    if (_poolId isEqualTo "") exitWith {false};
    ([_poolId] call ITW_CLASH_Service_fnc_FindEntry) >= 0
};

ITW_CLASH_ThunderRun_fnc_SetPhase = {
    params ["_state","_phase"];
    _state set ["phase",_phase];

    private _veh = _state getOrDefault ["vehicle",objNull];
    if (!isNull _veh) then {
        _veh setVariable ["ITW_CLASH_ThunderRun",_state]
    };
    private _driver = if (isNull _veh) then {objNull} else {driver _veh};

    ["phase",[
        _state getOrDefault ["poolId","?"],_phase,
        if (isNull _veh) then {[]} else {getPosATL _veh},
        if (isNull _veh) then {0} else {(getPosATL _veh)#2},
        if (isNull _veh) then {0} else {speed _veh},
        if (isNull _driver) then {[]} else {expectedDestination _driver},
        _state getOrDefault ["classification",""],
        _state getOrDefault ["classificationReason",""]
    ]] call ITW_CLASH_ThunderRun_fnc_Log;
};

ITW_CLASH_ThunderRun_fnc_ClearASupported = {
    params ["_state"];
    private _context = _state getOrDefault ["context",createHashMap];
    if !(_context getOrDefault ["supportedWritten",false]) exitWith {false};

    private _hq = _state getOrDefault ["hq",grpNull];
    private _target = _state getOrDefault ["target",objNull];
    if (isNull _hq || {isNull _target}) exitWith {false};

    private _targetGroup = [_target] call ITW_CLASH_ThunderRun_fnc_TargetGroup;
    if (isNull _targetGroup) exitWith {false};

    private _supported = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
    _hq setVariable ["RydHQ_ASupportedG",_supported - [_targetGroup]];
    true
};

ITW_CLASH_ThunderRun_fnc_ClearAmmoPoint = {
    params ["_state"];
    private _hq = _state getOrDefault ["hq",grpNull];
    private _target = _state getOrDefault ["target",objNull];
    if (isNull _hq || {isNull _target}) exitWith {false};

    private _points = +(_hq getVariable ["RydHQ_AmmoPoints",[]]);
    _hq setVariable ["RydHQ_AmmoPoints",_points - [_target]];
    true
};

ITW_CLASH_ThunderRun_fnc_ReconcileAbort = {
    params ["_state","_reason"];
    if (_state getOrDefault ["reservationReconciled",false]) exitWith {true};

    private _hq = _state getOrDefault ["hq",grpNull];
    private _target = _state getOrDefault ["target",objNull];
    private _box = _state getOrDefault ["box",objNull];
    private _origin = +(_state getOrDefault ["boxOrigin",[]]);
    private _context = _state getOrDefault ["context",createHashMap];

    if (!isNull _box && {alive _box}) then {
        _box hideObjectGlobal false;
        _box enableSimulationGlobal true;
        if (_origin isNotEqualTo []) then {_box setPosATL _origin};
    } else {
        if (
            !isNull _box
            && {_box getVariable ["ITW_CLASH_LogisticsPackage",false]}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_ReleasePackage"}
        ) then {
            [_box,_hq,false,"thunder-run-" + toLowerANSI _reason] call
                ITW_CLASH_PlayerTasks_fnc_ReleasePackage;
        };
    };

    [_hq,_target,_box,_context,"thunder-run-" + toLowerANSI _reason] call
        ITW_CLASH_AmmoDispatch_fnc_ReconcilePreDispatch;
    [_state] call ITW_CLASH_ThunderRun_fnc_ClearAmmoPoint;
    _state set ["reservationReconciled",true];
    true
};

ITW_CLASH_ThunderRun_fnc_EgressThreatCount = {
    params ["_hq","_position"];
    private _count = 0;
    {
        private _threatGroup = _x;
        if (
            isNull _threatGroup
            || {{alive _x} count units _threatGroup <= 0}
        ) then {continue};

        if ((vehicle leader _threatGroup) distance2D _position < 1500) then {
            _count = _count + 1
        };
    } forEach (_hq getVariable ["RydHQ_KnEnemiesG",[]]);
    _count
};

ITW_CLASH_ThunderRun_fnc_ReturnHome = {
    params ["_state"];
    private _veh = _state getOrDefault ["vehicle",objNull];
    private _home = +(_state getOrDefault ["home",[]]);
    if (
        isNull _veh || {!alive _veh} || {!canMove _veh}
        || {_home isEqualTo []}
    ) exitWith {false};

    private _driver = driver _veh;
    if (isNull _driver || {!alive _driver}) exitWith {false};

    [_state,"RTB"] call ITW_CLASH_ThunderRun_fnc_SetPhase;
    _veh forceSpeed -1;
    _veh flyInHeight ITW_CLASH_ThunderRunTransitHeight;
    (group _driver) setSpeedMode "FULL";
    _driver doMove _home;

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
    ) exitWith {false};

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

    !isNull _veh && {alive _veh} && {
        ((getPosATL _veh)#2 < 5)
        && {abs speed _veh < 5}
        && {_veh distance2D _home < 300}
    }
};

ITW_CLASH_ThunderRun_fnc_Finalize = {
    params ["_state","_outcome",["_atHome",false]];
    if (_state getOrDefault ["finalized",false]) exitWith {true};
    _state set ["finalized",true];

    private _veh = _state getOrDefault ["vehicle",objNull];
    private _group = _state getOrDefault ["group",grpNull];
    private _poolId = _state getOrDefault ["poolId",""];

    if (!isNull _veh) then {
        _veh setVariable ["ITW_CLASH_ThunderRunActive",false,true];
        _veh setVariable ["ITW_CLASH_ThunderRun",nil];
        _veh forceSpeed -1;
        _veh enableAI "TARGET";
        _veh enableAI "AUTOTARGET";
    };
    if (!isNull _group) then {
        _group setVariable ["ITW_CLASH_ThunderRunActive",false];
        _group setVariable ["Busy" + str _group,false];
        _group setSpeedMode "NORMAL";
    };

    [_state] call ITW_CLASH_ThunderRun_fnc_ClearAmmoPoint;

    private _virtualized = false;
    if (
        _atHome
        && {_poolId isNotEqualTo ""}
        && {!isNil "ITW_CLASH_Service_fnc_FindEntry"}
        && {!isNil "ITW_CLASH_Service_fnc_Retire"}
    ) then {
        private _index = [_poolId] call ITW_CLASH_Service_fnc_FindEntry;
        if (_index >= 0) then {
            _virtualized = [
                _index,"thunder-run-" + toLowerANSI _outcome
            ] call ITW_CLASH_Service_fnc_Retire;
        };
    };

    if (_poolId isNotEqualTo "") then {
        ITW_CLASH_ThunderRuns deleteAt _poolId
    };
    ["finalized",[
        _poolId,_outcome,_atHome,_virtualized
    ]] call ITW_CLASH_ThunderRun_fnc_Log;
    true
};

ITW_CLASH_ThunderRun_fnc_Abort = {
    params ["_state","_reason"];
    [_state,"ABORT"] call ITW_CLASH_ThunderRun_fnc_SetPhase;

    if !(_state getOrDefault ["released",false]) then {
        [_state,_reason] call ITW_CLASH_ThunderRun_fnc_ReconcileAbort;
    } else {
        // Release wrote Boxed/OrdnanceDrops; package monitor owns delivery/loss.
        [_state] call ITW_CLASH_ThunderRun_fnc_ClearAmmoPoint;
    };

    private _home = [_state] call ITW_CLASH_ThunderRun_fnc_ReturnHome;
    [_state,_reason,_home] call ITW_CLASH_ThunderRun_fnc_Finalize;
    true
};

ITW_CLASH_ThunderRun_fnc_PackageMonitor = {
    params ["_state"];
    private _box = _state getOrDefault ["box",objNull];
    private _target = _state getOrDefault ["target",objNull];
    private _hq = _state getOrDefault ["hq",grpNull];
    private _targetGroup = [_target] call ITW_CLASH_ThunderRun_fnc_TargetGroup;

    private _deadline = time + 180;
    waitUntil {
        sleep 0.5;
        isNull _box || {!alive _box} || {isNull _targetGroup}
        || {(_targetGroup getVariable ["isBoxed",objNull]) isEqualTo _box}
        || {time >= _deadline}
    };

    if (isNull _box) exitWith {};
    _box allowDamage true;

    if (
        alive _box
        && {!isNull _targetGroup}
        && {(_targetGroup getVariable ["isBoxed",objNull]) isEqualTo _box}
    ) exitWith {
        if (!isNil "ITW_CLASH_PlayerTasks_fnc_PackageDelivered") then {
            [_box,_target,_hq,"thunder-run-delivered"] call
                ITW_CLASH_PlayerTasks_fnc_PackageDelivered;
        };
        ["package-delivered",[
            _state getOrDefault ["poolId","?"],typeOf _box,getPosATL _box
        ]] call ITW_CLASH_ThunderRun_fnc_Log;
    };

    if (!isNull _targetGroup) then {
        private _boxed = +(_hq getVariable ["RydHQ_Boxed",[]]);
        _hq setVariable ["RydHQ_Boxed",_boxed - [_targetGroup]];
    };
    private _drops = +(_hq getVariable ["RydHQ_OrdnanceDrops",[]]);
    _hq setVariable ["RydHQ_OrdnanceDrops",_drops - [_box]];

    if (
        !alive _box
        && {_box getVariable ["ITW_CLASH_LogisticsPackage",false]}
        && {!isNil "ITW_CLASH_PlayerTasks_fnc_ReleasePackage"}
    ) then {
        [_box,_hq,false,"thunder-run-package-lost"] call
            ITW_CLASH_PlayerTasks_fnc_ReleasePackage;
    };

    ["package-failed",[
        _state getOrDefault ["poolId","?"],typeOf _box
    ]] call ITW_CLASH_ThunderRun_fnc_Log;
};

ITW_CLASH_ThunderRun_fnc_Run = {
    params ["_state"];

    private _veh = _state getOrDefault ["vehicle",objNull];
    private _target = _state getOrDefault ["target",objNull];
    private _box = _state getOrDefault ["box",objNull];
    private _hq = _state getOrDefault ["hq",grpNull];
    private _group = _state getOrDefault ["group",grpNull];
    private _driver = if (isNull _veh) then {objNull} else {driver _veh};

    if (
        isNull _veh || {isNull _target} || {isNull _box}
        || {isNull _hq} || {isNull _group} || {isNull _driver}
    ) exitWith {
        [_state,"INVALID_START"] call ITW_CLASH_ThunderRun_fnc_Abort
    };

    // Reproduce only the native GoAmmoSupp staging state needed for an air drop.
    private _points = +(_hq getVariable ["RydHQ_AmmoPoints",[]]);
    _points pushBackUnique _target;
    _hq setVariable ["RydHQ_AmmoPoints",_points];

    _group setVariable ["Deployed" + str _group,false];
    _group setVariable ["Busy" + str _group,true];
    _group setVariable ["ITW_CLASH_ThunderRunActive",true];
    _veh setVariable ["ITW_CLASH_ThunderRunActive",true,true];

    _veh disableAI "TARGET";
    _veh disableAI "AUTOTARGET";
    [_group] call RYD_WPdel;

    private _targetGroup = [_target] call ITW_CLASH_ThunderRun_fnc_TargetGroup;
    if (!isNull _targetGroup) then {
        _targetGroup setVariable ["ForBoxing",_target]
    };

    _box hideObjectGlobal true;
    _box enableSimulationGlobal false;
    _box setPos [0,0,2000];

    if (
        _box getVariable ["ITW_CLASH_LogisticsPackage",false]
        && {!isNil "ITW_CLASH_PlayerTasks_fnc_SetPackageState"}
    ) then {
        [_box,"RESERVED","thunder-run-staged"] call
            ITW_CLASH_PlayerTasks_fnc_SetPackageState;
    };

    private _dz = getPosATL _target;
    [_state,"TRANSIT"] call ITW_CLASH_ThunderRun_fnc_SetPhase;
    [
        _group,_dz,"MOVE","CARELESS","BLUE","FULL",
        ["true","deletewaypoint [(group this), 0]"]
    ] call RYD_WPadd;
    _veh flyInHeight ITW_CLASH_ThunderRunTransitHeight;

    private _transitDeadline = time + 360;
    private _nextThreatCheck = 0;
    private _abortReason = "";

    waitUntil {
        sleep 1;
        if (isNull _veh || {!alive _veh} || {!canMove _veh}) exitWith {
            _abortReason = "AIRFRAME_LOST";
            true
        };
        if (isNull _driver || {!alive _driver}) exitWith {
            _abortReason = "PILOT_LOST";
            true
        };
        if (isNull _target || {!alive _target}) exitWith {
            _abortReason = "TARGET_LOST";
            true
        };

        if (time >= _nextThreatCheck) then {
            _nextThreatCheck = time + 5;
            private _recheck = [_veh,_target,_hq] call
                ITW_CLASH_ThunderRun_fnc_Classify;
            if ((_recheck getOrDefault ["state",""]) == "AIR_DENIED") then {
                _abortReason = "AIR_DENIED_TRANSIT"
            };
        };

        (_abortReason isNotEqualTo "")
        || {_veh distance2D _target <= ITW_CLASH_ThunderRunTakeoverRadius}
        || {time >= _transitDeadline}
    };

    if (_abortReason isNotEqualTo "") exitWith {
        [_state,_abortReason] call ITW_CLASH_ThunderRun_fnc_Abort
    };
    if (time >= _transitDeadline) exitWith {
        [_state,"TRANSIT_TIMEOUT"] call ITW_CLASH_ThunderRun_fnc_Abort
    };

    [_group] call RYD_WPdel;
    [_state,"TAKEOVER"] call ITW_CLASH_ThunderRun_fnc_SetPhase;

    private _bearing = [getPosATL _veh,_dz,5] call RYD_AngTowards;
    private _through = [_dz,_bearing,1200] call RYD_PosTowards2D;

    _group setBehaviour "CARELESS";
    _group setCombatMode "BLUE";
    _group setSpeedMode "FULL";
    _veh flyInHeight ITW_CLASH_ThunderRunIngressHeight;
    _driver doMove _through;

    [_state,"INGRESS"] call ITW_CLASH_ThunderRun_fnc_SetPhase;
    private _ingressDeadline = time + 120;
    _nextThreatCheck = 0;
    _abortReason = "";

    waitUntil {
        sleep 0.25;
        if (isNull _veh || {!alive _veh} || {!canMove _veh}) exitWith {
            _abortReason = "AIRFRAME_LOST";
            true
        };
        if (isNull _driver || {!alive _driver}) exitWith {
            _abortReason = "PILOT_LOST";
            true
        };
        if (isNull _target || {!alive _target}) exitWith {
            _abortReason = "TARGET_LOST";
            true
        };

        private _distance = _veh distance2D _target;
        if (_distance <= ITW_CLASH_ThunderRunFlareStart) then {
            [_state,"INGRESS"] call ITW_CLASH_ThunderRun_fnc_MaybeFlare;
        };

        if (time >= _nextThreatCheck) then {
            _nextThreatCheck = time + 5;
            private _recheck = [_veh,_target,_hq] call
                ITW_CLASH_ThunderRun_fnc_Classify;
            if ((_recheck getOrDefault ["state",""]) == "AIR_DENIED") then {
                _abortReason = "AIR_DENIED_INGRESS"
            };
        };

        (_abortReason isNotEqualTo "")
        || {_distance <= ITW_CLASH_ThunderRunPopupRadius}
        || {time >= _ingressDeadline}
    };

    if (_abortReason isNotEqualTo "") exitWith {
        [_state,_abortReason] call ITW_CLASH_ThunderRun_fnc_Abort
    };
    if (time >= _ingressDeadline) exitWith {
        [_state,"INGRESS_TIMEOUT"] call ITW_CLASH_ThunderRun_fnc_Abort
    };

    [_state,"POPUP"] call ITW_CLASH_ThunderRun_fnc_SetPhase;
    _veh flyInHeight ITW_CLASH_ThunderRunDropHeight;
    _driver doMove _through;

    private _releasePoint = [
        _dz,(_bearing + 180) mod 360,ITW_CLASH_ThunderRunReleaseLead
    ] call RYD_PosTowards2D;

    private _popupDeadline = time + 45;
    waitUntil {
        sleep 0.15;
        [_state,"POPUP"] call ITW_CLASH_ThunderRun_fnc_MaybeFlare;
        isNull _veh || {!alive _veh} || {!canMove _veh}
        || {isNull _driver} || {!alive _driver}
        || {_veh distance2D _releasePoint < 80}
        || {_veh distance2D _target <= (ITW_CLASH_ThunderRunReleaseLead + 40)}
        || {time >= _popupDeadline}
    };

    if (
        isNull _veh || {!alive _veh} || {!canMove _veh}
        || {isNull _driver} || {!alive _driver}
        || {time >= _popupDeadline}
    ) exitWith {
        [_state,"POPUP_ABORT"] call ITW_CLASH_ThunderRun_fnc_Abort
    };

    [_state,"RELEASE"] call ITW_CLASH_ThunderRun_fnc_SetPhase;
    [_state,"RELEASE"] call ITW_CLASH_ThunderRun_fnc_MaybeFlare;

    _box allowDamage false;
    [[_veh,_box,_targetGroup],RYD_AmmoDrop] call RYD_Spawn;
    _state set ["released",true];

    private _boxed = +(_hq getVariable ["RydHQ_Boxed",[]]);
    if (!isNull _targetGroup) then {
        _boxed pushBackUnique _targetGroup
    };
    _hq setVariable ["RydHQ_Boxed",_boxed];

    private _drops = +(_hq getVariable ["RydHQ_OrdnanceDrops",[]]);
    _drops pushBackUnique _box;
    _hq setVariable ["RydHQ_OrdnanceDrops",_drops];

    if (
        _box getVariable ["ITW_CLASH_LogisticsPackage",false]
        && {!isNil "ITW_CLASH_PlayerTasks_fnc_SetPackageState"}
    ) then {
        [_box,"IN_TRANSIT","thunder-run-released"] call
            ITW_CLASH_PlayerTasks_fnc_SetPackageState;
    };

    [_state] call ITW_CLASH_ThunderRun_fnc_ClearAmmoPoint;
    [_state] call ITW_CLASH_ThunderRun_fnc_ClearASupported;
    [_state] spawn ITW_CLASH_ThunderRun_fnc_PackageMonitor;

    ["crate-release",[
        _state getOrDefault ["poolId","?"],getPosATL _veh,
        ITW_CLASH_ThunderRunReleaseLead,ITW_CLASH_ThunderRunDropHeight
    ]] call ITW_CLASH_ThunderRun_fnc_Log;

    private _leftBearing = (_bearing - 135 + 360) mod 360;
    private _rightBearing = (_bearing + 135) mod 360;
    private _left = [
        getPosATL _veh,_leftBearing,ITW_CLASH_ThunderRunEgressDistance
    ] call RYD_PosTowards2D;
    private _right = [
        getPosATL _veh,_rightBearing,ITW_CLASH_ThunderRunEgressDistance
    ] call RYD_PosTowards2D;

    private _leftThreat = [
        _hq,_left
    ] call ITW_CLASH_ThunderRun_fnc_EgressThreatCount;
    private _rightThreat = [
        _hq,_right
    ] call ITW_CLASH_ThunderRun_fnc_EgressThreatCount;
    private _egress = if (_leftThreat <= _rightThreat) then {_left} else {_right};

    [_state,"EGRESS"] call ITW_CLASH_ThunderRun_fnc_SetPhase;
    _veh flyInHeight ITW_CLASH_ThunderRunIngressHeight;
    _driver doMove _egress;

    ["jhook",[
        _state getOrDefault ["poolId","?"],
        if (_leftThreat <= _rightThreat) then {_leftBearing} else {_rightBearing},
        _leftThreat,_rightThreat
    ]] call ITW_CLASH_ThunderRun_fnc_Log;

    private _egressDeadline = time + 120;
    waitUntil {
        sleep 0.25;
        [_state,"EGRESS"] call ITW_CLASH_ThunderRun_fnc_MaybeFlare;
        isNull _veh || {!alive _veh} || {!canMove _veh}
        || {isNull _driver} || {!alive _driver}
        || {_veh distance2D _target >= ITW_CLASH_ThunderRunColdRadius}
        || {time >= _egressDeadline}
    };

    if (
        isNull _veh || {!alive _veh} || {!canMove _veh}
        || {isNull _driver} || {!alive _driver}
    ) exitWith {
        [_state,"AIRFRAME_LOST_AFTER_RELEASE",false] call
            ITW_CLASH_ThunderRun_fnc_Finalize
    };

    [_state,"COLD"] call ITW_CLASH_ThunderRun_fnc_SetPhase;
    ["egress-clear",[
        _state getOrDefault ["poolId","?"],getPosATL _veh,
        _veh distance2D _target
    ]] call ITW_CLASH_ThunderRun_fnc_Log;

    private _home = [_state] call ITW_CLASH_ThunderRun_fnc_ReturnHome;
    [_state,"DELIVERED",_home] call ITW_CLASH_ThunderRun_fnc_Finalize;
};

ITW_CLASH_ThunderRun_fnc_Start = {
    params ["_args","_context","_classification"];

    private _veh = _args param [0,objNull];
    private _target = _args param [1,objNull];
    private _box = _args param [5,objNull];
    private _hq = _args param [6,grpNull];
    private _driver = if (isNull _veh) then {objNull} else {driver _veh};
    private _group = if (isNull _driver) then {grpNull} else {group _driver};

    if (
        isNull _veh || {isNull _target} || {isNull _box}
        || {isNull _hq} || {isNull _group}
    ) exitWith {false};

    private _poolId = _veh getVariable ["ITW_CLASH_ServicePoolId",""];
    if (_poolId isEqualTo "") exitWith {false};

    private _index = [_poolId] call ITW_CLASH_Service_fnc_FindEntry;
    if (_index < 0) exitWith {false};
    if (_veh getVariable ["ITW_CLASH_ThunderRunActive",false]) exitWith {false};

    private _resolved = [_index,"thunder-run-dispatch"] call
        ITW_CLASH_ServiceHome_fnc_ResolveAndStore;
    if ((_resolved getOrDefault ["status",""]) != "RESOLVED") exitWith {false};

    private _home = +(_resolved getOrDefault ["position",[]]);
    if (_home isEqualTo []) exitWith {false};

    private _state = createHashMapFromArray [
        ["poolId",_poolId],["vehicle",_veh],["group",_group],
        ["target",_target],["hq",_hq],["box",_box],
        ["boxOrigin",getPosATL _box],["home",_home],
        ["context",_context],
        ["classification",_classification getOrDefault ["state",""]],
        ["classificationReason",_classification getOrDefault ["reason",""]],
        ["committedAt",time],["phase","INTERCEPTED"],
        ["released",false],["reservationReconciled",false],
        ["finalized",false],["etaAvailable",time + 420],
        ["countermeasureEmitter",[
            _veh
        ] call ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter]
    ];

    [_state] call ITW_CLASH_ThunderRun_fnc_InitFlareBudget;
    ITW_CLASH_ThunderRuns set [_poolId,_state];

    _veh setVariable ["ITW_CLASH_ThunderRunActive",true,true];
    _veh setVariable ["ITW_CLASH_ThunderRun",_state];
    _group setVariable ["ITW_CLASH_ThunderRunActive",true];

    diag_log "THUNDER RUN INITIATED";
    "THUNDER RUN INITIATED" remoteExecCall ["systemChat",0];

    ["initiated",[
        _poolId,typeOf _veh,
        _classification getOrDefault ["state",""],
        _classification getOrDefault ["reason",""],
        _classification getOrDefault ["missionDistance",0],
        _classification getOrDefault ["aaDistance",1e12],
        _classification getOrDefault ["airDistance",1e12],
        _classification getOrDefault ["groundDistance",1e12]
    ]] call ITW_CLASH_ThunderRun_fnc_Log;

    private _script = [_state] spawn ITW_CLASH_ThunderRun_fnc_Run;
    _state set ["script",_script];
    ITW_CLASH_ThunderRuns set [_poolId,_state];
    true
};

[] spawn {
    scriptName "ITW_CLASH_ThunderRunReaper";
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 10;
        {
            private _poolId = _x;
            private _state = ITW_CLASH_ThunderRuns getOrDefault [
                _poolId,createHashMap
            ];
            if (
                count _state == 0
                || {_state getOrDefault ["finalized",false]}
            ) then {continue};

            private _script = _state getOrDefault ["script",scriptNull];
            private _veh = _state getOrDefault ["vehicle",objNull];
            private _orphaned = (
                isNull _veh
                || {!alive _veh}
                || {_script isEqualTo scriptNull}
                || {scriptDone _script}
            );

            if (_orphaned) then {
                ["reaper",[
                    _poolId,isNull _veh,
                    if (_script isEqualTo scriptNull) then {true} else {
                        scriptDone _script
                    }
                ]] call ITW_CLASH_ThunderRun_fnc_Log;
                [_state,"ORPHANED"] spawn ITW_CLASH_ThunderRun_fnc_Abort;
            };
        } forEach (keys ITW_CLASH_ThunderRuns);
    };
};

ITW_CLASH_ThunderRunReady = true;
diag_log format [
    "CLASH BOOT | thunder-run-ready | version=%1 aiOnly=true nativeAmmoDrop=true corridorThreat=true downgradeOnly=true fullSortieOwnership=true",
    ITW_CLASH_ThunderRunVersion
];

true
