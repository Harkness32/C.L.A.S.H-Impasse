#include "defines.hpp"

// C.L.A.S.H. V6 preprocessor bisect chunk 4/8.
// Original ITW_CLASH.sqf lines 1010-1360. Diagnostic only; never executed.

ITW_CLASH_fnc_OrderWithdrawal = {
    params ["_group","_destination","_egressObjective","_source"];
    if (!isServer || {
        isNull _group || {
            _destination isEqualTo []
        }
    }) exitWith {false};

    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group enableAttack false;
    _group setCombatMode "BLUE";
    _group setBehaviourStrong "AWARE";
    _group setSpeedMode "FULL";

    private _waypoint = _group addWaypoint [_destination,35];
    _waypoint setWaypointType "MOVE";
    _waypoint setWaypointSpeed "FULL";
    _waypoint setWaypointBehaviour "AWARE";
    _waypoint setWaypointCombatMode "BLUE";
    _waypoint setWaypointCompletionRadius ITW_CLASH_WithdrawalArrivalRadius;
    _group setVariable ["ITW_CLASH_WithdrawalDestination",+_destination];

    ["withdrawal-order",[
        [_group] call ITW_CLASH_fnc_GroupId,
        _egressObjective,
        _source,
        round (leader _group distance2D _destination),
        {alive _x} count units _group
    ]] call ITW_CLASH_fnc_Log;
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
    _group setVariable ["ITW_CLASH_Lineage",_lineage];
    _group setVariable ["ITW_CLASH_Withdrawing",true];
    _group setVariable ["ITW_CLASH_WithdrawalObjective",_objectiveIndex];
    _group setVariable ["ITW_CLASH_ExhaustedSince",nil];
    _group setVariable ["Break",true];

    if !([_group,format ["withdrawal:%1",_reason]] call ITW_CLASH_fnc_BeginRelease) exitWith {
        _group setVariable ["ITW_CLASH_Withdrawing",nil];
        false
    };
    [_group,false] call ITW_CLASH_fnc_FinishRelease;

    private _busyName = "Busy" + str _group;
    private _restingName = "Resting" + str _group;
    _group setVariable [_busyName,false];
    _group setVariable [_restingName,false];
    _group setVariable ["RydHQ_MIA",true];

    private _egress = [
        _group,
        _objectiveIndex
    ] call ITW_CLASH_fnc_GetEgressPoint;
    private _destination = if (_egress isEqualTo []) then {[]} else {_egress#0};
    private _egressObjective = if (_egress isEqualTo []) then {-1} else {_egress#1};
    private _source = if (_egress isEqualTo []) then {"unresolved"} else {_egress#2};

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

    if (_destination isNotEqualTo []) then {
        [
            _group,
            _destination,
            _egressObjective,
            _source
        ] call ITW_CLASH_fnc_OrderWithdrawal;
        private _entry = ITW_CLASH_Withdrawals get _id;
        _entry set [8,time];
        ITW_CLASH_Withdrawals set [_id,_entry];
    };

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

ITW_CLASH_fnc_AcknowledgeReconstitution = {
    params [
        "_group",
        "_requestId",
        "_objectiveIndex",
        "_archetype",
        "_lineage",
        ["_queuedAt",0]
    ];
    if (!isServer || {
        isNull _group || {
            !ITW_CLASH_LiveEnabled || {
                !ITW_CLASH_HALReady
            }
        }
    }) exitWith {false};

    _group setVariable ["ITW_CLASH_Archetype",+_archetype];
    _group setVariable ["ITW_CLASH_Lineage",_lineage];
    _group setVariable [
        "ITW_CLASH_ReconstitutionRequest",
        _requestId
    ];
    VAR_SET_OBJ_IDX(_group,_objectiveIndex);
    private _registered = [
        _group,
        "reconstitution",
        true
    ] call ITW_CLASH_fnc_RegisterGroup;
    _group setVariable [
        "ITW_CLASH_LastReconstitutionRequest",
        _requestId
    ];
    _group setVariable ["ITW_CLASH_ReconstitutionRequest",nil];

    ["reconstitution-acknowledged",[
        _requestId,
        _lineage,
        _objectiveIndex,
        count _archetype,
        round (time - _queuedAt),
        _registered
    ]] call ITW_CLASH_fnc_Log;
    _registered
};

ITW_CLASH_fnc_AuditWithdrawals = {
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            !ITW_CLASH_HALReady
        }
    }) exitWith {[]};

    private _exhausted = ITW_CLASH_HALHQ getVariable [
        "RydHQ_Exhausted",
        []
    ];
    {
        private _group = _x;
        if (!isNull _group && {
            _group getVariable ["ITW_CLASH_Managed",false]
        }) then {
            if (_group in _exhausted) then {
                private _since = _group getVariable [
                    "ITW_CLASH_ExhaustedSince",
                    -1
                ];
                if (_since < 0) then {
                    _group setVariable [
                        "ITW_CLASH_ExhaustedSince",
                        time
                    ];
                    ["exhaustion-observed",[
                        [_group] call ITW_CLASH_fnc_GroupId,
                        _group getVariable [
                            "ITW_CLASH_AssignedObjective",
                            -1
                        ],
                        {alive _x} count units _group
                    ]] call ITW_CLASH_fnc_Log;
                } else {
                    if (time - _since >= ITW_CLASH_ExhaustionConfirmGrace) then {
                        [
                            _group,
                            "persistent-hal-exhaustion"
                        ] call ITW_CLASH_fnc_StartWithdrawal;
                    };
                };
            } else {
                _group setVariable ["ITW_CLASH_ExhaustedSince",nil];
            };
        };
    } forEach +ITW_CLASH_ManagedGroups;

    private _telemetry = [];
    {
        private _id = _x;
        private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
        if (_entry isEqualTo []) then {continue};

        _entry params [
            "_group",
            "_originalObjective",
            "_archetype",
            "_lineage",
            "_startedAt",
            "_destination",
            "_egressObjective",
            "_source",
            "_lastOrder"
        ];

        if (isNull _group || {
            ({alive _x} count units _group) == 0
        }) then {
            ITW_CLASH_Withdrawals deleteAt _id;
            ["withdrawal-failed",[
                _id,
                _lineage,
                _originalObjective,
                "wiped-before-egress",
                round (time - _startedAt)
            ]] call ITW_CLASH_fnc_Log;
            continue;
        };

        private _resolved = [
            _group,
            _originalObjective
        ] call ITW_CLASH_fnc_GetEgressPoint;
        if (_resolved isNotEqualTo []) then {
            if (_destination isEqualTo [] || {
                (_resolved#1) != _egressObjective || {
                    (_resolved#0) distance2D _destination > 5
                }
            }) then {
                _destination = +(_resolved#0);
                _egressObjective = _resolved#1;
                _source = _resolved#2;
                _lastOrder = -1000;
            };
        };

        private _distance = if (_destination isEqualTo []) then {-1} else {
            leader _group distance2D _destination
        };
        if (_distance >= 0 && {
            _distance <= ITW_CLASH_WithdrawalArrivalRadius
        }) then {
            private _credit = "";
            if (!isNil "ITW_AtkQueueReconstitution") then {
                _credit = [
                    _archetype,
                    _egressObjective,
                    _lineage,
                    getPosATL leader _group
                ] call ITW_AtkQueueReconstitution;
            };

            if (_credit isNotEqualTo "") then {
                private _survivors = {alive _x} count units _group;
                ITW_CLASH_Withdrawals deleteAt _id;
                ["withdrawal-arrived",[
                    _id,
                    _lineage,
                    _originalObjective,
                    _egressObjective,
                    _survivors,
                    _credit,
                    round (time - _startedAt)
                ]] call ITW_CLASH_fnc_Log;
                ["reconstitution-absorbed",[
                    _credit,
                    _lineage,
                    _survivors,
                    count _archetype
                ]] call ITW_CLASH_fnc_Log;
                {deleteVehicle _x} forEach units _group;
                deleteGroup _group;
                continue;
            };
        };

        if (_destination isNotEqualTo [] && {
            time - _lastOrder >= ITW_CLASH_WithdrawalOrderCooldown
        }) then {
            [
                _group,
                _destination,
                _egressObjective,
                _source
            ] call ITW_CLASH_fnc_OrderWithdrawal;
            _lastOrder = time;
        };

        _entry set [5,+_destination];
        _entry set [6,_egressObjective];
        _entry set [7,_source];
        _entry set [8,_lastOrder];
        ITW_CLASH_Withdrawals set [_id,_entry];
        _telemetry pushBack [
            _id,
            _lineage,
            _originalObjective,
            _egressObjective,
            {alive _x} count units _group,
            if (_distance < 0) then {-1} else {round _distance},
            round (time - _startedAt),
            _source
        ];
    } forEach +(keys ITW_CLASH_Withdrawals);

    private _signature = str _telemetry;
    if (_signature != ITW_CLASH_LastWithdrawalSignature) then {
        ITW_CLASH_LastWithdrawalSignature = _signature;
        ["withdrawal-state",[
            count _telemetry,
            _telemetry,
            count (
                missionNamespace getVariable [
                    "ITW_AtkReconstitutionQueue",
                    []
                ]
            )
        ]] call ITW_CLASH_fnc_Log;
    };
    _telemetry
};
