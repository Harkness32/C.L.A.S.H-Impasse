#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_FieldHardeningStarted",false]) exitWith {};

ITW_CLASH_FieldHardeningStarted = true;
ITW_CLASH_FieldHardeningVersion = 1;
ITW_CLASH_GTFO_BusyStallGrace = 90;
ITW_CLASH_GTFO_BusyStallProgress = 25;
ITW_CLASH_GTFO_BusyStallLogCooldown = 60;

ITW_CLASH_FieldHardening_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        [_event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH FIELD | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_FieldHardening_fnc_WaitFor = {
    params ["_predicate",["_timeout",240]];
    private _deadline = diag_tickTime + _timeout;
    waitUntil {
        sleep 0.25;
        (call _predicate) || {diag_tickTime >= _deadline}
    };
    call _predicate
};

ITW_CLASH_FieldHardening_fnc_IsCombatUnit = {
    params ["_unit"];
    !isNull _unit && {
        _unit isKindOf "CAManBase" && {
            ALIVE(_unit) && {CONSCIOUS(_unit)}
        }
    }
};

// HAL's native recon planners legitimately return nil. The outer C.L.A.S.H.
// wrappers assign that result to a local, so normalize only the saved native
// handles to a defined completion value while preserving all native side effects.
[] spawn {
    scriptName "ITW_CLASH_FieldHardening_ReconNilGuard";
    private _ready = [{
        !isNil "ITW_CLASH_Recon_fnc_NativeGoRecon" &&
        {!isNil "ITW_CLASH_Recon_fnc_NativeGoDefRecon"} &&
        {!isNil "ITW_CLASH_ReconPlanning_fnc_NativeHQOrders"} &&
        {!isNil "ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef"}
    }] call ITW_CLASH_FieldHardening_fnc_WaitFor;
    if (!_ready) exitWith {
        diag_log "CLASH BOOT | WARNING | field-hardening-recon-nil-guard-timeout";
    };
    if (missionNamespace getVariable ["ITW_CLASH_FieldHardeningReconNilGuardReady",false]) exitWith {};

    ITW_CLASH_Recon_fnc_NativeGoRecon_FieldHardeningBase = ITW_CLASH_Recon_fnc_NativeGoRecon;
    ITW_CLASH_Recon_fnc_NativeGoDefRecon_FieldHardeningBase = ITW_CLASH_Recon_fnc_NativeGoDefRecon;
    ITW_CLASH_ReconPlanning_fnc_NativeHQOrders_FieldHardeningBase = ITW_CLASH_ReconPlanning_fnc_NativeHQOrders;
    ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef_FieldHardeningBase = ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef;

    ITW_CLASH_Recon_fnc_NativeGoRecon = {
        _this call ITW_CLASH_Recon_fnc_NativeGoRecon_FieldHardeningBase;
        true
    };
    ITW_CLASH_Recon_fnc_NativeGoDefRecon = {
        _this call ITW_CLASH_Recon_fnc_NativeGoDefRecon_FieldHardeningBase;
        true
    };
    ITW_CLASH_ReconPlanning_fnc_NativeHQOrders = {
        _this call ITW_CLASH_ReconPlanning_fnc_NativeHQOrders_FieldHardeningBase;
        true
    };
    ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef = {
        _this call ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef_FieldHardeningBase;
        true
    };

    ITW_CLASH_FieldHardeningReconNilGuardReady = true;
    diag_log "CLASH BOOT | field-hardening-recon-nil-guard-ready | nativeResultDiscarded=true";
};

// Failed CASEVAC must cancel an on-foot survivor's stale assignment to the exact
// failed aircraft before canonical recovery hands tactical ownership back to HAL.
[] spawn {
    scriptName "ITW_CLASH_FieldHardening_CASEVACAbortCleanup";
    private _ready = [{!isNil "ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal"}] call
        ITW_CLASH_FieldHardening_fnc_WaitFor;
    if (!_ready) exitWith {
        diag_log "CLASH BOOT | WARNING | field-hardening-casevac-cleanup-timeout";
    };
    if (missionNamespace getVariable ["ITW_CLASH_FieldHardeningCASEVACCleanupReady",false]) exitWith {};

    ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal_FieldHardeningBase =
        ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
    ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal = {
        params ["_id","_group","_reason",["_heli",objNull],["_crewGroup",grpNull],["_returnPos",[]]];
        private _cleared = [];
        if (!isNull _group && {!isNull _heli}) then {
            {
                private _unit = _x;
                if (alive _unit && {vehicle _unit == _unit}) then {
                    private _assigned = assignedVehicle _unit;
                    if (!isNull _assigned && {_assigned == _heli}) then {
                        unassignVehicle _unit;
                        [_unit] orderGetIn false;
                        _cleared pushBack [typeOf _unit,lifeState _unit,round (_unit distance2D _heli)];
                    };
                };
            } forEach units _group;
        };
        if (_cleared isNotEqualTo []) then {
            ["casevac-abort-assignment-cleared",[
                _id,
                if (isNull _group) then {""} else {_group getVariable ["ITW_CLASH_Lineage",_id]},
                _reason,
                if (isNull _heli) then {""} else {typeOf _heli},
                _cleared
            ]] call ITW_CLASH_FieldHardening_fnc_Log;
        };
        _this call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal_FieldHardeningBase
    };

    ITW_CLASH_FieldHardeningCASEVACCleanupReady = true;
    diag_log "CLASH BOOT | field-hardening-casevac-cleanup-ready | onFootAssignmentsCancelled=true";
};

// RC1/G28 proved that Arma can retain assignedVehicles after physical dismount
// and after Impasse drops cargo ownership. Clear only that stale assignment
// inside the existing handoff envelope; the canonical transit manager still
// performs the authoritative HAL acknowledgement on its next pass.
[] spawn {
    scriptName "ITW_CLASH_FieldHardening_ReconstitutionAssignments";
    private _ready = [{
        !isNil "ITW_AtkReconstitutionTransits" &&
        {!isNil "ITW_Objectives"} &&
        {!isNil "ITW_CLASH_ReconstitutionHandoffBuffer"} &&
        {!isNil "ITW_ParamTransportUnloadDist"}
    }] call ITW_CLASH_FieldHardening_fnc_WaitFor;
    if (!_ready) exitWith {
        diag_log "CLASH BOOT | WARNING | field-hardening-reconstitution-assignment-timeout";
    };
    diag_log "CLASH BOOT | field-hardening-reconstitution-assignment-ready | canonicalHandoffPreserved=true";

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 5;
        {
            private _entry = _x;
            if (count _entry < 9) then {continue};
            _entry params ["_group","_requestId","_objectiveIndex","_archetype","_lineage",
                "_queuedAt","_createdAt","_lastAttempt","_state"];
            if (isNull _group || {!(_state in ["transport","walking"])}) then {continue};
            if (_objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}) then {continue};

            private _aliveUnits = (units _group) select {alive _x};
            if (_aliveUnits isEqualTo [] || {(_aliveUnits findIf {vehicle _x != _x}) >= 0}) then {continue};

            private _objective = ITW_Objectives#_objectiveIndex;
            private _handoffRadius = (_objective#ITW_OBJ_SIZE) +
                ITW_ParamTransportUnloadDist + ITW_CLASH_ReconstitutionHandoffBuffer;
            private _distance = leader _group distance2D (_objective#ITW_OBJ_POS);
            if (_distance > _handoffRadius) then {continue};

            private _managedVehicleIndex = -1;
            if (!isNil "ITW_ManagedVehs") then {
                _managedVehicleIndex = ITW_ManagedVehs findIf {
                    count _x > VEHINFO_CARGO_GRPS && {
                        (_x#VEHINFO_CREW_GRP) isEqualTo _group ||
                        {_group in (_x#VEHINFO_CARGO_GRPS)}
                    }
                };
            };
            if (_managedVehicleIndex >= 0) then {continue};

            private _assignedBefore = assignedVehicles _group;
            if (_assignedBefore isEqualTo []) then {continue};
            private _detailsBefore = _assignedBefore apply {
                [typeOf _x,str _x,alive _x,canMove _x,round (leader _group distance2D _x)]
            };

            {_group leaveVehicle _x} forEach _assignedBefore;
            {
                private _assigned = assignedVehicle _x;
                if (!isNull _assigned) then {
                    unassignVehicle _x;
                    [_x] orderGetIn false;
                };
            } forEach units _group;

            ["reconstitution-stale-assignment-cleared",[
                _requestId,_lineage,_objectiveIndex,_state,round _distance,
                round _handoffRadius,_detailsBefore,
                (assignedVehicles _group) apply {[typeOf _x,str _x]}
            ]] call ITW_CLASH_FieldHardening_fnc_Log;
        } forEach +ITW_AtkReconstitutionTransits;
    };
};

// Keep the original diagnostic's HQ/group snapshots but disable its contaminated
// pair loop. This replacement admits only conscious ACE-valid CAManBase units.
[] spawn {
    scriptName "ITW_CLASH_FieldHardening_CombatDiagnostics";
    private _ready = [{
        missionNamespace getVariable ["ITW_CLASH_CombatDiagnosticsStarted",false] &&
        {!isNil "ITW_CLASH_Diag_fnc_Log"} &&
        {!isNil "ITW_CLASH_Diag_fnc_Unit"} &&
        {!isNil "ITW_CLASH_Diag_fnc_ContactReasons"} &&
        {!isNil "ITW_CLASH_Diag_fnc_ContactSide"}
    }] call ITW_CLASH_FieldHardening_fnc_WaitFor;
    if (!_ready) exitWith {
        diag_log "CLASH BOOT | WARNING | field-hardening-combat-diagnostics-timeout";
    };
    if (missionNamespace getVariable ["ITW_CLASH_FieldHardeningCombatDiagnosticsReady",false]) exitWith {};

    private _contactRadius = missionNamespace getVariable ["ITW_CLASH_CombatDiagnosticsContactRadius",200];
    ITW_CLASH_CombatDiagnosticsLegacyContactRadius = _contactRadius;
    ITW_CLASH_CombatDiagnosticsContactRadius = -1;
    ITW_CLASH_FieldHardeningContactPairLastLog = createHashMap;

    ITW_CLASH_Diag_fnc_Unit_FieldHardeningBase = ITW_CLASH_Diag_fnc_Unit;
    ITW_CLASH_Diag_fnc_Unit = {
        params ["_unit",["_other",objNull]];
        private _base = [_unit,_other] call ITW_CLASH_Diag_fnc_Unit_FieldHardeningBase;
        if (isNull _unit) exitWith {_base};
        _base + [
            lifeState _unit,
            _unit getVariable ["ACE_isUnconscious",false],
            [_unit] call ITW_CLASH_FieldHardening_fnc_IsCombatUnit
        ]
    };

    ITW_CLASH_FieldHardeningCombatDiagnosticsReady = true;
    diag_log format [
        "CLASH BOOT | combat-diagnostics-ace-filter-ready | radius=%1 consciousCAManBase=true legacyPairLoopDisabled=true unitLifeState=true",
        _contactRadius
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep (missionNamespace getVariable ["ITW_CLASH_CombatDiagnosticsPollInterval",1.5]);
        if !(missionNamespace getVariable ["ITW_CLASH_CombatDiagnosticsEnabled",false]) then {continue};

        private _groups = allGroups select {
            private _group = _x;
            !isNull _group && {
                side _group != civilian && {
                    ((units _group) findIf {
                        [_x] call ITW_CLASH_FieldHardening_fnc_IsCombatUnit
                    }) >= 0
                }
            }
        };

        private _countGroups = count _groups;
        for "_i" from 0 to (_countGroups - 2) do {
            private _a = _groups#_i;
            private _sideA = side _a;
            private _aUnits = (units _a) select {
                [_x] call ITW_CLASH_FieldHardening_fnc_IsCombatUnit
            };
            if (_aUnits isEqualTo []) then {continue};

            for "_j" from (_i + 1) to (_countGroups - 1) do {
                private _b = _groups#_j;
                private _sideB = side _b;
                if ((_sideA getFriend _sideB) >= 0.6) then {continue};
                private _bUnits = (units _b) select {
                    [_x] call ITW_CLASH_FieldHardening_fnc_IsCombatUnit
                };
                if (_bUnits isEqualTo []) then {continue};

                private _bestDistance = 1e10;
                private _bestA = objNull;
                private _bestB = objNull;
                {
                    private _ua = _x;
                    {
                        private _distance = _ua distance2D _x;
                        if (_distance < _bestDistance) then {
                            _bestDistance = _distance;
                            _bestA = _ua;
                            _bestB = _x;
                        };
                    } forEach _bUnits;
                } forEach _aUnits;
                if (_bestDistance > _contactRadius) then {continue};

                private _pairNames = [str _a,str _b];
                _pairNames sort true;
                private _pairKey = _pairNames joinString "|";
                private _last = ITW_CLASH_FieldHardeningContactPairLastLog getOrDefault [_pairKey,-1e10];
                private _cooldown = missionNamespace getVariable ["ITW_CLASH_CombatDiagnosticsPairCooldown",5];
                if (time - _last < _cooldown) then {continue};
                ITW_CLASH_FieldHardeningContactPairLastLog set [_pairKey,time];

                private _reasonsA = [_a,_bestA,_bestB,_bestDistance] call ITW_CLASH_Diag_fnc_ContactReasons;
                private _reasonsB = [_b,_bestB,_bestA,_bestDistance] call ITW_CLASH_Diag_fnc_ContactReasons;
                if (_a getVariable ["ITW_CLASH_Withdrawing",false] ||
                    {(_a getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo ""} ||
                    {(_a getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo ""}) then {
                    _reasonsA pushBackUnique "expected-recovery-nonengagement";
                };
                if (_b getVariable ["ITW_CLASH_Withdrawing",false] ||
                    {(_b getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo ""} ||
                    {(_b getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo ""}) then {
                    _reasonsB pushBackUnique "expected-recovery-nonengagement";
                };

                private _event = if (_reasonsA isNotEqualTo [] || {_reasonsB isNotEqualTo []}) then {
                    "contact-anomaly"
                } else {
                    "contact"
                };
                private _hq = call ITW_CLASH_Diag_fnc_HQ;
                [_event,[
                    round _bestDistance,_sideA getFriend _sideB,typeOf _bestA,typeOf _bestB,
                    _reasonsA,_reasonsB,
                    [_a,_bestA,_bestB] call ITW_CLASH_Diag_fnc_ContactSide,
                    [_b,_bestB,_bestA] call ITW_CLASH_Diag_fnc_ContactSide,
                    [
                        _hq getVariable ["RydHQ_ReconStage",-1],
                        _hq getVariable ["RydHQ_ReconStage2",-1],
                        _hq getVariable ["RydHQ_ReconDone",false],
                        _hq getVariable ["RydHQ_LastE",-1]
                    ],
                    [
                        "ace-aware",
                        lifeState _bestA,_bestA getVariable ["ACE_isUnconscious",false],
                        lifeState _bestB,_bestB getVariable ["ACE_isUnconscious",false]
                    ]
                ]] call ITW_CLASH_Diag_fnc_Log;
            };
        };
    };
};

// Observer only: do not clear Busy or issue movement. Capture the HAL state of a
// withdrawing formation that stays Busy, never enters Resting, and makes <25 m
// progress for 90 seconds.
[] spawn {
    scriptName "ITW_CLASH_FieldHardening_GTFOBusyWatch";
    private _ready = [{
        !isNil "ITW_CLASH_Withdrawals" && {!isNil "ITW_CLASH_fnc_GroupId"}
    }] call ITW_CLASH_FieldHardening_fnc_WaitFor;
    if (!_ready) exitWith {
        diag_log "CLASH BOOT | WARNING | field-hardening-gtfo-busy-watch-timeout";
    };

    ITW_CLASH_FieldHardeningGTFOProgress = createHashMap;
    diag_log format [
        "CLASH BOOT | gtfo-busy-watch-ready | grace=%1 progress=%2 observerOnly=true",
        ITW_CLASH_GTFO_BusyStallGrace,ITW_CLASH_GTFO_BusyStallProgress
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 15;
        private _activeKeys = [];
        {
            private _id = _x;
            private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
            if (count _entry < 9) then {continue};
            private _group = _entry#0;
            private _destination = _entry#5;
            if (isNull _group || {_destination isEqualTo []} ||
                {!(_group getVariable ["ITW_CLASH_GTFO",false])}) then {continue};

            private _leader = leader _group;
            if (isNull _leader) then {continue};
            _activeKeys pushBack _id;

            if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "" ||
                {(_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo ""}) then {
                ITW_CLASH_FieldHardeningGTFOProgress set [_id,[time,_leader distance2D _destination]];
                continue;
            };

            private _busy = _group getVariable ["Busy" + str _group,false];
            private _resting = _group getVariable ["Resting" + str _group,false];
            private _distance = _leader distance2D _destination;
            private _sample = ITW_CLASH_FieldHardeningGTFOProgress getOrDefault [_id,[time,_distance]];
            _sample params ["_sampleAt","_sampleDistance"];

            if (!_busy || {_resting} ||
                {abs (_sampleDistance - _distance) >= ITW_CLASH_GTFO_BusyStallProgress}) then {
                ITW_CLASH_FieldHardeningGTFOProgress set [_id,[time,_distance]];
                continue;
            };
            private _stalledFor = time - _sampleAt;
            if (_stalledFor < ITW_CLASH_GTFO_BusyStallGrace) then {continue};

            private _nextLog = _group getVariable ["ITW_CLASH_FieldHardeningGTFOBusyLogAt",0];
            if (time < _nextLog) then {continue};
            _group setVariable ["ITW_CLASH_FieldHardeningGTFOBusyLogAt",
                time + ITW_CLASH_GTFO_BusyStallLogCooldown];

            private _wpIndex = currentWaypoint _group;
            private _wps = waypoints _group;
            private _wp = if (_wps isEqualTo [] || {_wpIndex < 0} || {_wpIndex >= count _wps}) then {
                [_wpIndex,"NONE","","","",[]]
            } else {
                [
                    _wpIndex,waypointType [_group,_wpIndex],
                    waypointBehaviour [_group,_wpIndex],waypointCombatMode [_group,_wpIndex],
                    waypointSpeed [_group,_wpIndex],waypointPosition [_group,_wpIndex]
                ]
            };
            private _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
            private _membership = [];
            {
                private _name = _x;
                _membership pushBack [_name,!isNull _hq && {_group in (_hq getVariable [_name,[]])}];
            } forEach [
                "RydHQ_Exhausted","RydHQ_AttackAv","RydHQ_CombatAv","RydHQ_DefSpot",
                "RydHQ_RecDefSpot","RydHQ_NoAttack","RydHQ_NoDef","RydHQ_NoRecon","RydHQ_ROnly"
            ];
            private _assigned = assignedVehicle _leader;

            ["gtfo-hal-busy-stall",[
                _id,_group getVariable ["ITW_CLASH_Lineage",_id],
                _group getVariable ["ITW_CLASH_WithdrawalObjective",-1],
                round _stalledFor,round _distance,round (_sampleDistance - _distance),
                _busy,_resting,_group getVariable ["Break",false],
                _group getVariable ["Defending",false],_group getVariable ["Unable",false],
                _group getVariable ["RydHQ_MIA",false],attackEnabled _group,combatMode _group,
                _group getVariable ["ITW_CLASH_GTFO_State",""],_wp,currentCommand _leader,
                expectedDestination _leader,behaviour _leader,combatBehaviour _leader,
                if (isNull _assigned) then {""} else {typeOf _assigned},
                count (_group targets []),_membership
            ]] call ITW_CLASH_FieldHardening_fnc_Log;
        } forEach +(keys ITW_CLASH_Withdrawals);

        {
            if !(_x in _activeKeys) then {ITW_CLASH_FieldHardeningGTFOProgress deleteAt _x};
        } forEach +(keys ITW_CLASH_FieldHardeningGTFOProgress);
    };
};

diag_log format [
    "CLASH BOOT | field-hardening-ready | version=%1 reconNilGuard=true casevacAbortCleanup=true reconstitutionAssignmentRepair=true aceContactFilter=true gtfoBusyObserver=true",
    ITW_CLASH_FieldHardeningVersion
];
