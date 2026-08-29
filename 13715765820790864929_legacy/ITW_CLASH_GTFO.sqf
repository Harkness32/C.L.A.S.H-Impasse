#include "defines.hpp"

if (!isServer) exitWith {false};

ITW_CLASH_GTFOVersion = 4;
if (isNil "ITW_CLASH_GTFO_Corridor") then {ITW_CLASH_GTFO_Corridor = []};
if (isNil "ITW_CLASH_GTFO_CorridorSignature") then {ITW_CLASH_GTFO_CorridorSignature = ""};
if (isNil "ITW_CLASH_GTFO_ConstraintSignature") then {ITW_CLASH_GTFO_ConstraintSignature = ""};
if (isNil "ITW_CLASH_GTFO_RestDecoy") then {ITW_CLASH_GTFO_RestDecoy = objNull};

/*
    GTFO authority doctrine

    HAL      = tactical commander. HAL owns GoRest, route execution, movement,
               smoke, local enemy avoidance, speed/behaviour and withdrawal radio.
    Impasse  = strategic/logistics authority. Impasse supplies the support corridor,
               recovery hardware, tickets and rear reconstitution.
    C.L.A.S.H.= bridge. It marks a formation combat-ineffective, translates the
               Impasse rear corridor into HAL's native Withdrawal Rally Point,
               blocks offensive/recon/defensive recommitment, observes arrival,
               and hands authority to recovery only after physical boarding.

    C.L.A.S.H. deliberately does NOT create a withdrawal MOVE waypoint, force
    BLUE, or call enableAttack false. HAL_GoRest retains those tactical choices.
*/

ITW_CLASH_GTFO_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["gtfo-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_GTFO_fnc_SetPersistentConstraints = {
    params ["_group",["_enabled",true]];
    if (isNull _group) exitWith {false};

    private _hq = grpNull;
    if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
    };
    private _isPlayerCommander = (
        !isNil "ITW_PlayerSide" && {side _group == ITW_PlayerSide}
    );
    if (isNull _hq && {_isPlayerCommander}) then {
        _hq = missionNamespace getVariable ["ITW_CLASH_BLUFORHQ",grpNull];
    };
    if (isNull _hq && {
        !isNil "ITW_EnemySide" && {side _group == ITW_EnemySide}
    }) then {
        _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
    };
    if (isNull _hq) exitWith {false};

    private _prefix = if (_isPlayerCommander) then {"RydHQB_"} else {"RydHQ_"};
    {
        _x params ["_suffix","_hqName"];
        private _globalName = _prefix + _suffix;
        private _global = +(missionNamespace getVariable [_globalName,[]]);
        if (_enabled) then {
            _global pushBackUnique _group;
        } else {
            _global = _global - [_group];
        };
        missionNamespace setVariable [_globalName,_global];

        private _hqList = +(_hq getVariable [_hqName,[]]);
        if (_enabled) then {
            _hqList pushBackUnique _group;
        } else {
            _hqList = _hqList - [_group];
        };
        _hq setVariable [_hqName,_hqList];
    } forEach [
        ["NoDef","RydHQ_NoDef"],
        ["NoAttack","RydHQ_NoAttack"],
        ["NoRecon","RydHQ_NoRecon"],
        ["Exhausted","RydHQ_Exhausted"]
    ];
    true
};

ITW_CLASH_GTFO_fnc_RefreshCorridor = {
    if (isNil "ITW_CLASH_fnc_GetActiveObjectives" || {
        isNil "ITW_CLASH_fnc_GetSupportCorridorSpawn"
    }) exitWith {[]};

    private _corridors = [];
    {
        private _objectiveIndex = _x#0;
        private _corridor = [_objectiveIndex] call ITW_CLASH_fnc_GetSupportCorridorSpawn;
        if (_corridor isEqualTo [] || {(_corridor#0) isEqualTo []}) then {continue};
        _corridors pushBack [
            _objectiveIndex,
            +(_corridor#0),
            _corridor#2,
            _corridor#3
        ];
    } forEach (call ITW_CLASH_fnc_GetActiveObjectives);

    if (_corridors isEqualTo []) exitWith {ITW_CLASH_GTFO_Corridor};

    // HAL exposes one native Withdrawal Rally Point per commander. The current
    // one-way Impasse pilot therefore publishes one canonical rear corridor to
    // HAL. Prefer the commander's current objective corridor; otherwise use the
    // first active objective. Telemetry explicitly reports divergent base routes.
    private _preferredObjective = missionNamespace getVariable [
        "ITW_CLASH_CommanderObjective",
        -1
    ];
    private _selectedIndex = _corridors findIf {(_x#0) == _preferredObjective};
    if (_selectedIndex < 0) then {_selectedIndex = 0};
    private _selected = _corridors#_selectedIndex;
    _selected params ["_objectiveIndex","_position","_source","_baseIndex"];

    ITW_CLASH_GTFO_Corridor = [+_position,_objectiveIndex,_source,_baseIndex];

    if (isNull ITW_CLASH_GTFO_RestDecoy) then {
        ITW_CLASH_GTFO_RestDecoy = createVehicle [
            "Land_HelipadEmpty_F",
            _position,
            [],
            0,
            "CAN_COLLIDE"
        ];
    };
    if (!isNull ITW_CLASH_GTFO_RestDecoy) then {
        ITW_CLASH_GTFO_RestDecoy setPosATL _position;
    };

    // This is HAL's documented native Withdrawal Rally Point interface. C.L.A.S.H.
    // provides the strategic rear point; GoRest remains untouched and owns the
    // tactical withdrawal around that point.
    if (!isNull ITW_CLASH_HALHQ && {!isNull ITW_CLASH_GTFO_RestDecoy}) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_RestDecoy",ITW_CLASH_GTFO_RestDecoy];
        ITW_CLASH_HALHQ setVariable ["RydHQ_RDChance",100];
    };

    private _baseIndices = [];
    {
        _baseIndices pushBackUnique (_x#3);
    } forEach _corridors;

    private _signature = str [
        _objectiveIndex,
        _baseIndex,
        _source,
        _corridors apply {[_x#0,_x#2,_x#3]}
    ];
    if (_signature != ITW_CLASH_GTFO_CorridorSignature) then {
        ITW_CLASH_GTFO_CorridorSignature = _signature;
        ["corridor",[
            _objectiveIndex,
            _baseIndex,
            _source,
            _position,
            _corridors apply {[_x#0,_x#2,_x#3]}
        ]] call ITW_CLASH_GTFO_fnc_Log;
        if ((count _baseIndices) > 1) then {
            ["corridor-divergence",[
                _objectiveIndex,
                _baseIndex,
                _corridors
            ]] call ITW_CLASH_GTFO_fnc_Log;
        };
    };

    ITW_CLASH_GTFO_Corridor
};

ITW_CLASH_GTFO_fnc_ApplyConstraints = {
    private _gtfo = ITW_CLASH_ManagedGroups select {
        !isNull _x && {
            _x getVariable ["ITW_CLASH_GTFO",false]
        }
    };

    {
        [_x,true] call ITW_CLASH_GTFO_fnc_SetPersistentConstraints;
    } forEach _gtfo;

    private _signature = str (_gtfo apply {
        [
            [_x] call ITW_CLASH_fnc_GroupId,
            _x getVariable ["ITW_CLASH_GTFO_State",""],
            _x getVariable ["ITW_CLASH_GTFO_EgressObjective",-1]
        ]
    });
    if (_signature != ITW_CLASH_GTFO_ConstraintSignature) then {
        ITW_CLASH_GTFO_ConstraintSignature = _signature;
        ["constraints",[
            count _gtfo,
            _gtfo apply {[_x] call ITW_CLASH_fnc_GroupId}
        ]] call ITW_CLASH_GTFO_fnc_Log;
    };
    true
};

ITW_CLASH_GTFO_fnc_ResumeHAL = {
    params ["_group"];
    if (isNull _group || {!(_group getVariable ["ITW_CLASH_GTFO",false])}) exitWith {false};
    if (_group getVariable ["ITW_CLASH_Managed",false]) exitWith {true};

    private _objectiveIndex = _group getVariable [
        "ITW_CLASH_WithdrawalObjective",
        _group getVariable ["ITW_CLASH_GTFO_OriginalObjective",-1]
    ];
    _group setVariable ["ITW_CLASH_Managed",true];
    _group setVariable ["ITW_CLASH_AssignedObjective",_objectiveIndex];
    _group setVariable ["ITW_CLASH_Releasing",false];
    _group setVariable ["ITW_CLASH_ReleaseReason",nil];
    _group setVariable ["ITW_CLASH_ReleaseStarted",nil];
    _group setVariable ["RydHQ_MIA",nil];
    _group setVariable ["ITW_CLASH_GTFO_State","HAL_WITHDRAWAL"];
    ITW_CLASH_ManagedGroups pushBackUnique _group;
    call ITW_CLASH_fnc_SyncHALIncluded;

    ["hal-resumed",[
        [_group] call ITW_CLASH_fnc_GroupId,
        _objectiveIndex,
        {alive _x} count units _group
    ]] call ITW_CLASH_GTFO_fnc_Log;
    true
};

ITW_CLASH_GTFO_fnc_RecoveryOwned = {
    params ["_group",["_mode","recovery"]];
    if (isNull _group || {!(_group getVariable ["ITW_CLASH_GTFO",false])}) exitWith {false};

    _group setVariable ["ITW_CLASH_GTFO_State","RECOVERY_OWNED"];
    private _released = false;
    if (_group getVariable ["ITW_CLASH_Managed",false]) then {
        if ([_group,format ["gtfo-recovery-owned:%1",_mode]] call ITW_CLASH_fnc_BeginRelease) then {
            [_group,false] call ITW_CLASH_fnc_FinishRelease;
            _released = true;
        };
    };

    ["recovery-owned",[
        [_group] call ITW_CLASH_fnc_GroupId,
        _mode,
        _released,
        {alive _x} count units _group
    ]] call ITW_CLASH_GTFO_fnc_Log;
    true
};

// Preserve the corrected V6 implementations beneath the GTFO bridge.
ITW_CLASH_fnc_ClassifyGroup_GTFOBase = ITW_CLASH_fnc_ClassifyGroup;
ITW_CLASH_fnc_ApplyObjectiveDoctrine_GTFOBase = ITW_CLASH_fnc_ApplyObjectiveDoctrine;
ITW_CLASH_fnc_GetEgressPoint_GTFOBase = ITW_CLASH_fnc_GetEgressPoint;
ITW_CLASH_fnc_CancelWithdrawals_GTFOBase = ITW_CLASH_fnc_CancelWithdrawals;

ITW_CLASH_fnc_ClassifyGroup = {
    params ["_group"];

    // GTFO remains a HAL-owned formation until recovery has physically boarded
    // it. Without this bridge exception the canonical classifier would release
    // every ITW_CLASH_Withdrawing group back to baseline Impasse immediately.
    if (!isNull _group && {
        _group getVariable ["ITW_CLASH_GTFO",false] && {
            _group getVariable ["ITW_CLASH_Managed",false]
        }
    }) exitWith {
        [true,"gtfo-hal-managed",[
            {alive _x} count units _group,
            _group getVariable ["ITW_CLASH_WithdrawalObjective",-1],
            groupOwner _group
        ]]
    };

    [_group] call ITW_CLASH_fnc_ClassifyGroup_GTFOBase
};

ITW_CLASH_fnc_ApplyObjectiveDoctrine = {
    private _result = call ITW_CLASH_fnc_ApplyObjectiveDoctrine_GTFOBase;
    call ITW_CLASH_GTFO_fnc_RefreshCorridor;
    call ITW_CLASH_GTFO_fnc_ApplyConstraints;
    _result
};

ITW_CLASH_fnc_GetEgressPoint = {
    params ["_group",["_preferredObjective",-1]];
    if (isNull _group) exitWith {[]};

    // Recovery's existing V6 egress lock remains authoritative while an asset
    // is active. Outside recovery, each GTFO squad keeps the immutable support
    // corridor captured when its withdrawal began.
    private _casevacState = _group getVariable ["ITW_CLASH_CASEVAC_State",""];
    private _groundState = _group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""];
    if (_casevacState isNotEqualTo "" || {_groundState isNotEqualTo ""}) exitWith {
        [_group,_preferredObjective] call ITW_CLASH_fnc_GetEgressPoint_GTFOBase
    };

    private _gtfoDestination = _group getVariable ["ITW_CLASH_GTFO_Destination",[]];
    if (_group getVariable ["ITW_CLASH_GTFO",false] && {
        _gtfoDestination isNotEqualTo []
    }) exitWith {
        [
            +_gtfoDestination,
            _group getVariable ["ITW_CLASH_GTFO_EgressObjective",-1],
            _group getVariable ["ITW_CLASH_GTFO_Source","gtfo-support-corridor"]
        ]
    };

    [_group,_preferredObjective] call ITW_CLASH_fnc_GetEgressPoint_GTFOBase
};

ITW_CLASH_fnc_OrderWithdrawal = {
    params ["_group","_destination","_egressObjective","_source"];
    if (!isServer || {isNull _group}) exitWith {false};

    private _isEnemyManaged = _group getVariable ["ITW_CLASH_Managed",false];
    private _isEnemySide = !isNil "ITW_EnemySide" && {
        side _group == ITW_EnemySide
    };

    // A failed OPFOR recovery returns tactical authority to the original HAL
    // pilot. BLUFOR groups remain under Commander B throughout recovery, so
    // never convert them into the enemy managed-group ledger here.
    if (_isEnemySide && {
        _group getVariable ["ITW_CLASH_GTFO",false] && {
            !(_group getVariable ["ITW_CLASH_Managed",false])
        }
    }) then {
        [_group] call ITW_CLASH_GTFO_fnc_ResumeHAL;
        _isEnemyManaged = true;
    };

    if (_destination isNotEqualTo []) then {
        _group setVariable ["ITW_CLASH_GTFO_Destination",+_destination];
        _group setVariable ["ITW_CLASH_GTFO_EgressObjective",_egressObjective];
        _group setVariable ["ITW_CLASH_GTFO_Source",_source];
    _group setVariable ["ITW_CLASH_WithdrawalSide",side _group];

        private _restDecoy = _group getVariable [
            "ITW_CLASH_GTFO_GroupRestDecoy",objNull
        ];
        if (isNull _restDecoy) then {
            _restDecoy = createVehicle [
                "Land_HelipadEmpty_F",_destination,[],0,"CAN_COLLIDE"
            ];
            _restDecoy hideObjectGlobal true;
            _restDecoy enableSimulationGlobal false;
            _restDecoy allowDamage false;
            _group setVariable [
                "ITW_CLASH_GTFO_GroupRestDecoy",_restDecoy
            ];
        } else {
            _restDecoy setPosATL _destination;
        };
    };

    private _hq = grpNull;
    if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
    };
    if (isNull _hq && {
        !isNil "ITW_PlayerSide" && {side _group == ITW_PlayerSide}
    }) then {
        _hq = missionNamespace getVariable ["ITW_CLASH_BLUFORHQ",grpNull];
    };
    if (isNull _hq && {_isEnemySide}) then {
        _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
    };

    if (!isNull _hq) then {
        private _wasMissing = !(
            _group in (_hq getVariable ["RydHQ_Exhausted",[]])
        );
        [_group,true] call ITW_CLASH_GTFO_fnc_SetPersistentConstraints;

        if (_isEnemyManaged) then {
            call ITW_CLASH_GTFO_fnc_ApplyConstraints;
        };

        if (_wasMissing) then {
            ["hal-exhaustion-reasserted",[
                [_group] call ITW_CLASH_fnc_GroupId,
                _egressObjective,
                _source,
                side _group
            ]] call ITW_CLASH_GTFO_fnc_Log;
        };
    };

    private _nextLog = _group getVariable ["ITW_CLASH_GTFO_OrderLogAt",0];
    if (time >= _nextLog) then {
        _group setVariable ["ITW_CLASH_GTFO_OrderLogAt",time + 60];
        ["hal-withdrawal",[
            [_group] call ITW_CLASH_fnc_GroupId,
            _egressObjective,
            _source,
            if (_destination isEqualTo []) then {-1} else {
                round (leader _group distance2D _destination)
            },
            {alive _x} count units _group,
            _group getVariable ["Resting" + str _group,false],
            _group getVariable ["Busy" + str _group,false],
            attackEnabled _group,
            combatMode _group
        ]] call ITW_CLASH_GTFO_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_StartWithdrawal = {
    params ["_group",["_reason","hal-exhausted"]];
    if (!isServer || {
        isNull _group || {
            _group getVariable ["ITW_CLASH_Withdrawing",false]
        }
    }) exitWith {false};
    private _enemyManaged = _group getVariable ["ITW_CLASH_Managed",false];
    private _friendlyManaged = (
        !isNil "ITW_PlayerSide"
        && {side _group == ITW_PlayerSide}
        && {_group getVariable ["ITW_CLASH_DualHALManaged",false]}
        && {((units _group) findIf {isPlayer _x}) < 0}
    );
    if (!_enemyManaged && {!_friendlyManaged}) exitWith {false};

    private _objectiveIndex = if (_friendlyManaged) then {
        _group getVariable [
            "ITW_CLASH_DualHALObjectiveAffinity",
            VAR_GET_OBJ_IDX(_group)
        ]
    } else {
        _group getVariable [
            "ITW_CLASH_AssignedObjective",
            VAR_GET_OBJ_IDX(_group)
        ]
    };
    private _archetype = [_group] call ITW_CLASH_fnc_GetArchetype;
    if (_archetype isEqualTo []) exitWith {
        ["withdrawal-rejected",[
            [_group] call ITW_CLASH_fnc_GroupId,
            _objectiveIndex,
            "missing-archetype"
        ]] call ITW_CLASH_fnc_Log;
        false
    };

    private _id = [_group] call ITW_CLASH_fnc_GroupId;
    private _lineage = _group getVariable ["ITW_CLASH_Lineage",_id];
    private _destination = [];
    private _egressObjective = -1;
    private _source = "unresolved";

    if (_friendlyManaged && {
        !isNil "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn"
    }) then {
        private _forward = [
            _objectiveIndex,side _group
        ] call ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn;
        if (_forward isNotEqualTo []) then {
            _destination = +(_forward#0);
            _egressObjective = _forward#1;
            _source = "gtfo-blufor-" + (_forward#2);
        };
    } else {
        private _corridor = call ITW_CLASH_GTFO_fnc_RefreshCorridor;
        if (_corridor isNotEqualTo []) then {
            _destination = +(_corridor#0);
            _egressObjective = _corridor#1;
            _source = "gtfo-" + (_corridor#2);
        };
    };

    if (_destination isEqualTo []) then {
        private _fallback = [
            _group,
            _objectiveIndex
        ] call ITW_CLASH_fnc_GetEgressPoint_GTFOBase;
        if (_fallback isNotEqualTo []) then {
            _destination = +(_fallback#0);
            _egressObjective = _fallback#1;
            _source = "gtfo-" + (_fallback#2);
        };
    };

    _group setVariable ["ITW_CLASH_Lineage",_lineage];
    _group setVariable ["ITW_CLASH_Withdrawing",true];
    _group setVariable ["ITW_CLASH_WithdrawalObjective",_objectiveIndex];
    _group setVariable ["ITW_CLASH_ExhaustedSince",nil];
    _group setVariable ["ITW_CLASH_GTFO",true];
    _group setVariable ["ITW_CLASH_GTFO_State","HAL_WITHDRAWAL"];
    _group setVariable ["ITW_CLASH_GTFO_Reason",_reason];
    _group setVariable ["ITW_CLASH_GTFO_OriginalObjective",_objectiveIndex];
    _group setVariable ["ITW_CLASH_GTFO_Destination",+_destination];
    _group setVariable ["ITW_CLASH_GTFO_EgressObjective",_egressObjective];
    _group setVariable ["ITW_CLASH_GTFO_Source",_source];

    // GTFO is incompatible with holding a capture-point anchor, but the group
    // remains HAL-managed. Do not call BeginRelease/FinishRelease here.
    private _anchorObjective = _group getVariable ["ITW_CLASH_AnchorObjective",-1];
    if (_anchorObjective >= 0) then {
        [_anchorObjective,"gtfo"] call ITW_CLASH_fnc_ClearAnchorSlot;
    };

    ITW_CLASH_Withdrawals set [
        _id,
        [
            _group,
            _objectiveIndex,
            +_archetype,
            _lineage,
            time,
            +_destination,
            _egressObjective,
            _source,
            -1000
        ]
    ];

    [
        _group,
        _destination,
        _egressObjective,
        _source
    ] call ITW_CLASH_fnc_OrderWithdrawal;
    private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
    if (_entry isNotEqualTo []) then {
        _entry set [8,time];
        ITW_CLASH_Withdrawals set [_id,_entry];
    };

    ["start",[
        _id,
        _lineage,
        _objectiveIndex,
        count _archetype,
        {alive _x} count units _group,
        _egressObjective,
        _source,
        _destination,
        _group getVariable ["Resting" + str _group,false]
    ]] call ITW_CLASH_GTFO_fnc_Log;

    // Keep the established telemetry contract for CASEVAC/MEDEVAC observers.
    ["withdrawal-start",[
        _id,
        _lineage,
        _objectiveIndex,
        count _archetype,
        {alive _x} count units _group,
        _egressObjective,
        _source
    ]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_CancelWithdrawals = {
    params [["_reason","cancelled"]];
    private _groups = [];
    {
        private _entry = ITW_CLASH_Withdrawals getOrDefault [_x,[]];
        if (_entry isNotEqualTo [] && {!isNull (_entry#0)}) then {
            _groups pushBackUnique (_entry#0);
        };
    } forEach +(keys ITW_CLASH_Withdrawals);

    private _count = [_reason] call ITW_CLASH_fnc_CancelWithdrawals_GTFOBase;
    {
        if (!isNil "ITW_CLASH_GTFO_fnc_SetPersistentConstraints") then {
            [_x,false] call ITW_CLASH_GTFO_fnc_SetPersistentConstraints;
        };
        private _restDecoy = _x getVariable [
            "ITW_CLASH_GTFO_GroupRestDecoy",objNull
        ];
        if (!isNull _restDecoy) then {deleteVehicle _restDecoy};
        _x setVariable ["ITW_CLASH_GTFO_GroupRestDecoy",nil];
        _x setVariable ["ITW_CLASH_GTFO",nil];
        _x setVariable ["ITW_CLASH_GTFO_State",nil];
        _x setVariable ["ITW_CLASH_GTFO_Reason",nil];
        _x setVariable ["ITW_CLASH_GTFO_OriginalObjective",nil];
        _x setVariable ["ITW_CLASH_GTFO_Destination",nil];
        _x setVariable ["ITW_CLASH_GTFO_EgressObjective",nil];
        _x setVariable ["ITW_CLASH_GTFO_Source",nil];
        _x setVariable ["ITW_CLASH_GTFO_OrderLogAt",nil];
    } forEach _groups;

    // Rebuild A's legacy doctrine after removing its withdrawal constraints.
    // Commander B's durable RydHQB_* arrays were already cleaned per-group by
    // SetPersistentConstraints and will survive its next SitRep projection.
    call ITW_CLASH_fnc_ApplyObjectiveDoctrine;
    ["cancelled",[_reason,_count]] call ITW_CLASH_GTFO_fnc_Log;
    _count
};

diag_log format [
    "CLASH BOOT | gtfo-hal-withdrawal-ready | version=%1 bridgeOnly=true nativeGoRest=true groupRestDecoy=true bluforReconstitution=true symmetricCancel=true symmetricCommanderFallback=true directMove=false directBlue=false directAttackDisable=false recoveryOwnership=postBoarding",
    ITW_CLASH_GTFOVersion
];

true