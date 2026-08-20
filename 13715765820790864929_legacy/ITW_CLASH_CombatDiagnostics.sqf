if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_CombatDiagnosticsStarted",false]) exitWith {true};

ITW_CLASH_CombatDiagnosticsStarted = true;
ITW_CLASH_CombatDiagnosticsVersion = 1;
ITW_CLASH_CombatDiagnosticsEnabled = true;
ITW_CLASH_CombatDiagnosticsPollInterval = 1.5;
ITW_CLASH_CombatDiagnosticsContactRadius = 200;
ITW_CLASH_CombatDiagnosticsPairCooldown = 5;
ITW_CLASH_CombatDiagnosticsHQInterval = 15;
ITW_CLASH_CombatDiagnosticsGroupSignatures = createHashMap;
ITW_CLASH_CombatDiagnosticsPairLastLog = createHashMap;

/*
    Temporary C.L.A.S.H. / HAL combat diagnostics.

    OBSERVER ONLY. This file deliberately does not issue waypoints, alter combat
    mode, toggle AI features, change enableAttack, mutate HAL candidate lists,
    spawn assets, spend tickets, or change C.L.A.S.H. ownership.

    Goal: explain close-range enemy pass-through / non-engagement incidents.

    The proximity observer is intentionally detection-independent. It finds
    physically hostile groups first and only then records what Arma/HAL believe:
      - side friendliness / captive state
      - attackEnabled
      - TARGET / AUTOTARGET / MOVE / FSM AI features
      - behaviour / combat behaviour / unit combat mode
      - knowsAbout / targetKnowledge / targets / findNearestEnemy
      - HAL list membership and recon counters
      - Defending / Busy / Unable
      - C.L.A.S.H. withdrawal, recovery, anchor, and Recon Phase 0 state
      - current waypoint type / behaviour / combat mode / speed / position

    This is a hosted-test instrument, not release doctrine.
*/

ITW_CLASH_Diag_fnc_Log = {
    params ["_event",["_payload",[]]];
    diag_log format ["CLASH DIAG | %1 | %2",_event,_payload];
};

ITW_CLASH_Diag_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_fnc_GroupId
    };
    str _group
};

ITW_CLASH_Diag_fnc_HQ = {
    if (!isNil "ITW_CLASH_HALHQ" && {!isNull ITW_CLASH_HALHQ}) exitWith {
        ITW_CLASH_HALHQ
    };
    grpNull
};

ITW_CLASH_Diag_fnc_InHQList = {
    params ["_hq","_name","_group"];
    if (isNull _hq || {isNull _group}) exitWith {false};
    _group in (_hq getVariable [_name,[]])
};

ITW_CLASH_Diag_fnc_GroupIds = {
    params [["_groups",[]]];
    (_groups select {!isNull _x}) apply {[_x] call ITW_CLASH_Diag_fnc_GroupId}
};

ITW_CLASH_Diag_fnc_Waypoint = {
    params ["_group"];
    if (isNull _group) exitWith {[-1,"NULL","","","",[]]};

    private _wps = waypoints _group;
    private _idx = currentWaypoint _group;
    if (_wps isEqualTo [] || {_idx < 0} || {_idx >= count _wps}) exitWith {
        [_idx,"NONE","","","",[]]
    };

    private _wp = [_group,_idx];
    [
        _idx,
        waypointType _wp,
        waypointBehaviour _wp,
        waypointCombatMode _wp,
        waypointSpeed _wp,
        waypointPosition _wp
    ]
};

ITW_CLASH_Diag_fnc_AnchorObjectives = {
    params ["_group"];
    private _result = [];
    if (isNull _group || {isNil "ITW_CLASH_AnchorGroups"}) exitWith {_result};

    {
        private _key = _x;
        private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
        if (_entry isNotEqualTo [] && {count _entry > 0} && {
            (_entry#0) isEqualTo _group
        }) then {
            _result pushBack _key;
        };
    } forEach +(keys ITW_CLASH_AnchorGroups);
    _result
};

ITW_CLASH_Diag_fnc_Unit = {
    params ["_unit",["_other",objNull]];
    if (isNull _unit) exitWith {["<null>"]};

    private _assigned = assignedVehicle _unit;
    private _veh = vehicle _unit;
    private _knowledge = if (isNull _other) then {-1} else {_unit knowsAbout _other};
    private _targetKnowledge = [];
    if (!isNull _other && {_knowledge > 0}) then {
        _targetKnowledge = _unit targetKnowledge _other;
    };
    private _nearest = _unit findNearestEnemy _unit;

    [
        typeOf _unit,
        alive _unit,
        str (side _unit),
        captive _unit,
        captiveNum _unit,
        attackEnabled _unit,
        behaviour _unit,
        combatBehaviour _unit,
        unitCombatMode _unit,
        _unit checkAIFeature "TARGET",
        _unit checkAIFeature "AUTOTARGET",
        _unit checkAIFeature "MOVE",
        _unit checkAIFeature "FSM",
        _unit checkAIFeature "COVER",
        _unit checkAIFeature "SUPPRESSION",
        currentCommand _unit,
        getSuppression _unit,
        unitReady _unit,
        expectedDestination _unit,
        if (_veh isEqualTo _unit) then {"on-foot"} else {typeOf _veh},
        if (isNull _assigned) then {""} else {typeOf _assigned},
        _knowledge,
        _targetKnowledge,
        if (isNull _nearest) then {[]} else {
            [typeOf _nearest,[_nearest] call {
                params ["_n"];
                private _g = group _n;
                if (isNull _g) then {"<no-group>"} else {[_g] call ITW_CLASH_Diag_fnc_GroupId}
            },round (_unit distance2D _nearest)]
        }
    ]
};

ITW_CLASH_Diag_fnc_Group = {
    params ["_group"];
    if (isNull _group) exitWith {["<null>"]};

    private _hq = call ITW_CLASH_Diag_fnc_HQ;
    private _leader = leader _group;
    private _busyName = "Busy" + str _group;
    private _wp = [_group] call ITW_CLASH_Diag_fnc_Waypoint;

    private _memberships = [];
    {
        _memberships pushBack [
            _x,
            [_hq,_x,_group] call ITW_CLASH_Diag_fnc_InHQList
        ];
    } forEach [
        "RydHQ_Friends",
        "RydHQ_Included",
        "RydHQ_AttackAv",
        "RydHQ_FlankAv",
        "RydHQ_CombatAv",
        "RydHQ_ReconAv",
        "RydHQ_ReconG",
        "RydHQ_FOG",
        "RydHQ_SnipersG",
        "RydHQ_SpecForG",
        "RydHQ_NoRecon",
        "RydHQ_NoAttack",
        "RydHQ_NoDef",
        "RydHQ_ROnly",
        "RydHQ_AOnly",
        "RydHQ_Garrison",
        "RydHQ_DefSpot",
        "RydHQ_RecDefSpot",
        "RydHQ_DefRes",
        "RydHQ_Exhausted"
    ];

    [
        [_group] call ITW_CLASH_Diag_fnc_GroupId,
        str (side _group),
        groupOwner _group,
        {alive _x} count units _group,
        count units _group,
        _group getVariable ["ITW_CLASH_Managed",false],
        _group getVariable ["ITW_CLASH_AssignedObjective",-1],
        _group getVariable ["ITW_ObjIdx",-1],
        [_group] call ITW_CLASH_Diag_fnc_AnchorObjectives,
        _group getVariable ["ITW_CLASH_Withdrawing",false],
        _group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""],
        _group getVariable ["ITW_CLASH_CASEVAC_State",""],
        _group getVariable ["ITW_CLASH_ReconPhase0Active",false],
        _group getVariable ["ITW_CLASH_ReconPhase0Mode",""],
        _group getVariable ["ITW_CLASH_ReconSOF",false],
        _group getVariable ["ITW_CLASH_ReconSOFFamily",""],
        _group getVariable ["ITW_CLASH_ReconSOFLatched",false],
        _group getVariable ["Defending",false],
        _group getVariable [_busyName,false],
        _group getVariable ["Unable",false],
        attackEnabled _group,
        combatMode _group,
        formation _group,
        _wp,
        if (isNull _leader) then {["<no-leader>"]} else {[_leader] call ITW_CLASH_Diag_fnc_Unit},
        _memberships
    ]
};

ITW_CLASH_Diag_fnc_HQSnapshot = {
    private _hq = call ITW_CLASH_Diag_fnc_HQ;
    if (isNull _hq) exitWith {["<no-hal-hq>"]};

    [
        [_hq] call ITW_CLASH_Diag_fnc_GroupId,
        _hq getVariable ["RydHQ_Order",""],
        _hq getVariable ["RydHQ_LastE",-1],
        _hq getVariable ["RydHQ_ReconStage",-1],
        _hq getVariable ["RydHQ_ReconStage2",-1],
        _hq getVariable ["RydHQ_ReconDone",false],
        _hq getVariable ["RydHQ_DefDone",false],
        count (_hq getVariable ["RydHQ_KnEnemies",[]]),
        [_hq getVariable ["RydHQ_KnEnemiesG",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        count (_hq getVariable ["RydHQ_KnEnPos",[]]),
        [_hq getVariable ["RydHQ_Friends",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_Included",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_AttackAv",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_FlankAv",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_CombatAv",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_ReconAv",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_ReconG",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_SpecForG",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_NoRecon",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_NoAttack",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_NoDef",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_ROnly",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_Garrison",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_DefSpot",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_RecDefSpot",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_DefRes",[]]] call ITW_CLASH_Diag_fnc_GroupIds,
        [_hq getVariable ["RydHQ_Exhausted",[]]] call ITW_CLASH_Diag_fnc_GroupIds
    ]
};

ITW_CLASH_Diag_fnc_ContactSide = {
    params ["_group","_unit","_otherUnit"];
    if (isNull _group || {isNull _unit} || {isNull _otherUnit}) exitWith {["invalid"]};

    private _hq = call ITW_CLASH_Diag_fnc_HQ;
    private _leader = leader _group;
    private _nearestLeader = if (isNull _leader) then {objNull} else {
        _leader findNearestEnemy _leader
    };
    private _otherVehicle = vehicle _otherUnit;
    private _targets = _group targets [];
    private _busyName = "Busy" + str _group;

    [
        [_group] call ITW_CLASH_Diag_fnc_GroupId,
        str (side _group),
        attackEnabled _group,
        combatMode _group,
        _group getVariable ["Defending",false],
        _group getVariable [_busyName,false],
        _group getVariable ["Unable",false],
        _group getVariable ["ITW_CLASH_Withdrawing",false],
        _group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""],
        _group getVariable ["ITW_CLASH_CASEVAC_State",""],
        _group getVariable ["ITW_CLASH_ReconPhase0Active",false],
        _group getVariable ["ITW_CLASH_ReconPhase0Mode",""],
        _group getVariable ["ITW_CLASH_ReconSOFFamily",""],
        [_group] call ITW_CLASH_Diag_fnc_AnchorObjectives,
        [_group] call ITW_CLASH_Diag_fnc_Waypoint,
        _group knowsAbout _otherUnit,
        _unit knowsAbout _otherUnit,
        count _targets,
        _otherVehicle in _targets,
        if (isNull _nearestLeader) then {[]} else {
            [
                typeOf _nearestLeader,
                [group _nearestLeader] call ITW_CLASH_Diag_fnc_GroupId,
                round (_leader distance2D _nearestLeader)
            ]
        },
        [_unit,_otherUnit] call ITW_CLASH_Diag_fnc_Unit,
        [
            [_hq,"RydHQ_AttackAv",_group] call ITW_CLASH_Diag_fnc_InHQList,
            [_hq,"RydHQ_CombatAv",_group] call ITW_CLASH_Diag_fnc_InHQList,
            [_hq,"RydHQ_ReconAv",_group] call ITW_CLASH_Diag_fnc_InHQList,
            [_hq,"RydHQ_SpecForG",_group] call ITW_CLASH_Diag_fnc_InHQList,
            [_hq,"RydHQ_NoRecon",_group] call ITW_CLASH_Diag_fnc_InHQList,
            [_hq,"RydHQ_NoAttack",_group] call ITW_CLASH_Diag_fnc_InHQList,
            [_hq,"RydHQ_DefSpot",_group] call ITW_CLASH_Diag_fnc_InHQList,
            [_hq,"RydHQ_RecDefSpot",_group] call ITW_CLASH_Diag_fnc_InHQList,
            [_hq,"RydHQ_Exhausted",_group] call ITW_CLASH_Diag_fnc_InHQList
        ]
    ]
};

ITW_CLASH_Diag_fnc_ContactReasons = {
    params ["_group","_unit","_otherUnit","_distance"];
    private _reasons = [];
    if (isNull _group || {isNull _unit} || {isNull _otherUnit}) exitWith {["invalid-contact"]};

    if !(attackEnabled _group) then {_reasons pushBack "group-attack-disabled"};
    if !(attackEnabled _unit) then {_reasons pushBack "unit-attack-disabled"};
    if !(_unit checkAIFeature "TARGET") then {_reasons pushBack "target-ai-disabled"};
    if !(_unit checkAIFeature "AUTOTARGET") then {_reasons pushBack "autotarget-ai-disabled"};
    if !(_unit checkAIFeature "MOVE") then {_reasons pushBack "move-ai-disabled"};
    if !(_unit checkAIFeature "FSM") then {_reasons pushBack "fsm-ai-disabled"};
    if ((combatMode _group) isEqualTo "BLUE") then {_reasons pushBack "combatmode-blue"};

    private _knowledge = _unit knowsAbout _otherUnit;
    if (_distance <= 75 && {_knowledge < 0.05}) then {
        _reasons pushBack "close-but-no-unit-knowledge";
    };
    if (_distance <= 75 && {(_group knowsAbout _otherUnit) < 0.05}) then {
        _reasons pushBack "close-but-no-group-knowledge";
    };
    if (_distance <= 75 && {isNull (_unit findNearestEnemy _unit)}) then {
        _reasons pushBack "close-but-findnearestenemy-null";
    };
    if (captive _unit) then {_reasons pushBack "unit-captive"};
    if (captive _otherUnit) then {_reasons pushBack "enemy-captive"};
    _reasons
};

ITW_CLASH_Diag_fnc_DumpGroup = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    ["manual-group",[_group] call ITW_CLASH_Diag_fnc_Group] call ITW_CLASH_Diag_fnc_Log;
    true
};

ITW_CLASH_Diag_fnc_DumpAll = {
    ["manual-hq",call ITW_CLASH_Diag_fnc_HQSnapshot] call ITW_CLASH_Diag_fnc_Log;
    {
        if (!isNull _x && {{alive _x} count units _x > 0}) then {
            ["manual-group",[_x] call ITW_CLASH_Diag_fnc_Group] call ITW_CLASH_Diag_fnc_Log;
        };
    } forEach allGroups;
    true
};

[] spawn {
    scriptName "ITW_CLASH_CombatDiagnostics";

    private _lastHQ = -1e10;
    waitUntil {
        sleep 0.25;
        (missionNamespace getVariable ["ITW_CLASH_HALReady",false])
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    if !(missionNamespace getVariable ["ITW_CLASH_HALReady",false]) exitWith {
        ITW_CLASH_CombatDiagnosticsStarted = false;
        diag_log "CLASH BOOT | combat-diagnostics-deferred | HAL not ready";
    };

    diag_log format [
        "CLASH BOOT | combat-diagnostics-ready | version=%1 observerOnly=true poll=%2 contactRadius=%3 pairCooldown=%4 hqInterval=%5 detectionIndependent=true",
        ITW_CLASH_CombatDiagnosticsVersion,
        ITW_CLASH_CombatDiagnosticsPollInterval,
        ITW_CLASH_CombatDiagnosticsContactRadius,
        ITW_CLASH_CombatDiagnosticsPairCooldown,
        ITW_CLASH_CombatDiagnosticsHQInterval
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_CombatDiagnosticsPollInterval;
        if (!ITW_CLASH_CombatDiagnosticsEnabled) then {continue};

        if (time - _lastHQ >= ITW_CLASH_CombatDiagnosticsHQInterval) then {
            _lastHQ = time;
            ["hq-state",call ITW_CLASH_Diag_fnc_HQSnapshot] call ITW_CLASH_Diag_fnc_Log;
        };

        private _groups = allGroups select {
            !isNull _x && {{alive _x} count units _x > 0} && {side _x != civilian}
        };
        {
            private _group = _x;
            private _snapshot = [_group] call ITW_CLASH_Diag_fnc_Group;
            private _key = str _group;
            private _signature = str _snapshot;
            private _previous = ITW_CLASH_CombatDiagnosticsGroupSignatures getOrDefault [_key,""];
            if !(_signature isEqualTo _previous) then {
                ITW_CLASH_CombatDiagnosticsGroupSignatures set [_key,_signature];
                ["group-state",_snapshot] call ITW_CLASH_Diag_fnc_Log;
            };
        } forEach _groups;

        private _countGroups = count _groups;
        for "_i" from 0 to (_countGroups - 2) do {
            private _a = _groups#_i;
            private _sideA = side _a;
            private _aUnits = (units _a) select {alive _x};
            if (_aUnits isEqualTo []) then {continue};

            for "_j" from (_i + 1) to (_countGroups - 1) do {
                private _b = _groups#_j;
                private _sideB = side _b;
                if ((_sideA getFriend _sideB) >= 0.6) then {continue};

                private _bUnits = (units _b) select {alive _x};
                if (_bUnits isEqualTo []) then {continue};

                private _bestDistance = 1e10;
                private _bestA = objNull;
                private _bestB = objNull;
                {
                    private _ua = _x;
                    {
                        private _ub = _x;
                        private _d = _ua distance2D _ub;
                        if (_d < _bestDistance) then {
                            _bestDistance = _d;
                            _bestA = _ua;
                            _bestB = _ub;
                        };
                    } forEach _bUnits;
                } forEach _aUnits;

                if (_bestDistance > ITW_CLASH_CombatDiagnosticsContactRadius) then {continue};

                private _pairNames = [str _a,str _b];
                _pairNames sort true;
                private _pairKey = _pairNames joinString "|";
                private _last = ITW_CLASH_CombatDiagnosticsPairLastLog getOrDefault [_pairKey,-1e10];
                if (time - _last < ITW_CLASH_CombatDiagnosticsPairCooldown) then {continue};
                ITW_CLASH_CombatDiagnosticsPairLastLog set [_pairKey,time];

                private _reasonsA = [_a,_bestA,_bestB,_bestDistance] call ITW_CLASH_Diag_fnc_ContactReasons;
                private _reasonsB = [_b,_bestB,_bestA,_bestDistance] call ITW_CLASH_Diag_fnc_ContactReasons;
                private _event = if (_reasonsA isNotEqualTo [] || {_reasonsB isNotEqualTo []}) then {
                    "contact-anomaly"
                } else {
                    "contact"
                };

                [_event,[
                    round _bestDistance,
                    _sideA getFriend _sideB,
                    typeOf _bestA,
                    typeOf _bestB,
                    _reasonsA,
                    _reasonsB,
                    [_a,_bestA,_bestB] call ITW_CLASH_Diag_fnc_ContactSide,
                    [_b,_bestB,_bestA] call ITW_CLASH_Diag_fnc_ContactSide,
                    [
                        (call ITW_CLASH_Diag_fnc_HQ) getVariable ["RydHQ_ReconStage",-1],
                        (call ITW_CLASH_Diag_fnc_HQ) getVariable ["RydHQ_ReconStage2",-1],
                        (call ITW_CLASH_Diag_fnc_HQ) getVariable ["RydHQ_ReconDone",false],
                        (call ITW_CLASH_Diag_fnc_HQ) getVariable ["RydHQ_LastE",-1]
                    ]
                ]] call ITW_CLASH_Diag_fnc_Log;
            };
        };
    };

    ITW_CLASH_CombatDiagnosticsStarted = false;
    diag_log "CLASH BOOT | combat-diagnostics-stopped";
};

true
