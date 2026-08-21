#include "defines.hpp"

if (!isServer) exitWith {false};

ITW_CLASH_GTFOVersion = 1;
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
    if (isNull ITW_CLASH_HALHQ) exitWith {false};

    private _gtfo = ITW_CLASH_ManagedGroups select {
        !isNull _x && {
            _x getVariable ["ITW_CLASH_GTFO",false]
        }
    };

    private _noDef = +(ITW_CLASH_HALHQ getVariable ["RydHQ_NoDef",[]]);
    private _noAttack = +(ITW_CLASH_HALHQ getVariable ["RydHQ_NoAttack",[]]);
    private _noRecon = +(ITW_CLASH_HALHQ getVariable ["RydHQ_NoRecon",[]]);
    private _exhausted = +(ITW_CLASH_HALHQ getVariable ["RydHQ_Exhausted",[]]);

    {
        _noDef pushBackUnique _x;
        _noAttack pushBackUnique _x;
        _noRecon pushBackUnique _x;
        _exhausted pushBackUnique _x;
    } forEach _gtfo;

    ITW_CLASH_HALHQ setVariable ["RydHQ_NoDef",_noDef];
    ITW_CLASH_HALHQ setVariable ["RydHQ_NoAttack",_noAttack];
    ITW_CLASH_HALHQ setVariable ["RydHQ_NoRecon",_noRecon];
    ITW_CLASH_HALHQ setVariable ["RydHQ_Exhausted",_exhausted];
    RydHQ_NoDef = +_noDef;
    RydHQ_NoAttack = +_noAttack;
    RydHQ_NoRecon = +_noRecon;

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

    // A failed recovery returns tactical authority to HAL. This is a direct
    // bridge handback, not a fresh Impasse spawn/registration decision.
    if (_group getVariable ["ITW_CLASH_GTFO",false] && {
        !(_group getVariable ["ITW_CLASH_Managed",false])
    }) then {
        [_group] call ITW_CLASH_GTFO_fnc_ResumeHAL;
    };

    if (_destination isNotEqualTo []) then {
        _group setVariable ["ITW_CLASH_GTFO_Destination",+_destination];
        _group setVariable ["ITW_CLASH_GTFO_EgressObjective",_egressObjective];
        _group setVariable ["ITW_CLASH_GTFO_Source",_source];
    };

    if (!isNull ITW_CLASH_HALHQ) then {
        private _exhausted = +(ITW_CLASH_HALHQ getVariable ["RydHQ_Exhausted",[]]);
        private _wasMissing = !(_group in _exhausted);
        _exhausted pushBackUnique _group;
        ITW_CLASH_HALHQ setVariable ["RydHQ_Exhausted",_exhausted];
        call ITW_CLASH_GTFO_fnc_ApplyConstraints;

        if (_wasMissing) then {
            ["hal-exhaustion-reasserted",[
                [_group] call ITW_CLASH_fnc_GroupId,
                _egressObjective,
                _source
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
    if !(_group getVariable ["ITW_CLASH_Managed",false]) exitWith {false};

    private _objectiveIndex = _group getVariable [
        "ITW_CLASH_AssignedObjective",
        VAR_GET_OBJ_IDX(_group)
    ];
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
    private _corridor = call ITW_CLASH_GTFO_fnc_RefreshCorridor;
    private _destination = [];
    private _egressObjective = -1;
    private _source = "unresolved";
    if (_corridor isNotEqualTo []) then {
        _destination = +(_corridor#0);
        _egressObjective = _corridor#1;
        _source = "gtfo-" + (_corridor#2);
    } else {
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
        _x setVariable ["ITW_CLASH_GTFO",nil];
        _x setVariable ["ITW_CLASH_GTFO_State",nil];
        _x setVariable ["ITW_CLASH_GTFO_Reason",nil];
        _x setVariable ["ITW_CLASH_GTFO_OriginalObjective",nil];
        _x setVariable ["ITW_CLASH_GTFO_Destination",nil];
        _x setVariable ["ITW_CLASH_GTFO_EgressObjective",nil];
        _x setVariable ["ITW_CLASH_GTFO_Source",nil];
        _x setVariable ["ITW_CLASH_GTFO_OrderLogAt",nil];
    } forEach _groups;

    if (!isNull ITW_CLASH_HALHQ) then {
        private _exhausted = +(ITW_CLASH_HALHQ getVariable ["RydHQ_Exhausted",[]]);
        _exhausted = _exhausted - _groups;
        ITW_CLASH_HALHQ setVariable ["RydHQ_Exhausted",_exhausted];
        call ITW_CLASH_fnc_ApplyObjectiveDoctrine;
    };
    ["cancelled",[_reason,_count]] call ITW_CLASH_GTFO_fnc_Log;
    _count
};

diag_log format [
    "CLASH BOOT | gtfo-hal-withdrawal-ready | version=%1 bridgeOnly=true nativeGoRest=true restDecoy=true directMove=false directBlue=false directAttackDisable=false recoveryOwnership=postBoarding",
    ITW_CLASH_GTFOVersion
];

true