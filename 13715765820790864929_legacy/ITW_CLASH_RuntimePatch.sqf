#include "defines.hpp"

ITW_CLASH_RuntimePatchVersion = 2;

/*
    V6 runtime integrity correction, applied during the bootstrap finalization
    window before observer/live startup:
    - C.L.A.S.H. owns OPFOR point defense; Impasse garrison writes are suppressed.
    - Mixed combat squads remain eligible when they merely contain embedded support specialists.
    - Exhausted squads egress to the enemy home AI staging/base.
    - Reconstituted squads are relocated to the rear staging/base before HAL registration.
*/

ITW_CLASH_fnc_GetHomeBaseSpawn = {
    if (isNil "ITW_Objectives" || {
        isNil "ITW_Zones" || {ITW_Zones isEqualTo []}
    }) exitWith {[]};

    private _homeZone = ITW_Zones#-1;
    if (_homeZone isEqualTo []) exitWith {[]};

    private _homeObjective = _homeZone#0;
    if (_homeObjective < 0 || {
        _homeObjective >= count ITW_Objectives
    }) exitWith {[]};

    private _objective = ITW_Objectives#_homeObjective;
    private _position = [];
    private _source = "home-base-ai-spawn";
    private _baseIndex = _objective#ITW_OBJ_INDEX;

    if (!isNil "ITW_Bases" && {
        _baseIndex >= 0 && {_baseIndex < count ITW_Bases}
    }) then {
        _position = +(ITW_Bases#_baseIndex#ITW_BASE_A_SPAWN);
    };

    if (_position isEqualTo []) then {
        _position = +(_objective#ITW_OBJ_V_SPAWN);
        _source = "home-staging";
    };
    if (_position isEqualTo []) then {
        _position = +(_objective#ITW_OBJ_POS);
        _source = "home-objective-fallback";
    };
    if (count _position < 3) then {
        _position pushBack 0;
    };

    [_position,_homeObjective,_source]
};

ITW_CLASH_fnc_ClassifyGroup_V6Base = ITW_CLASH_fnc_ClassifyGroup;
ITW_CLASH_fnc_ClassifyGroup = {
    params ["_group"];

    private _result = [_group] call ITW_CLASH_fnc_ClassifyGroup_V6Base;
    if ((_result#0) || {
        (_result#1) isNotEqualTo "support-specialist"
    }) exitWith {_result};

    if (isNull _group) exitWith {_result};
    private _aliveUnits = (units _group) select {alive _x};
    if (_aliveUnits isEqualTo []) exitWith {_result};

    private _supportUnits = _aliveUnits select {
        private _cfg = configFile >> "CfgVehicles" >> typeOf _x;
        getNumber (_cfg >> "attendant") > 0 || {
            getNumber (_cfg >> "engineer") > 0 || {
                getNumber (_cfg >> "uavHacker") > 0
            }
        }
    };

    // A mixed combat squad with a medic/engineer/UAV operator is still a combat squad.
    // Preserve the original rejection only when the whole surviving group is support-specialist.
    if (_supportUnits isEqualTo [] || {
        count _supportUnits == count _aliveUnits
    }) exitWith {_result};

    private _objectiveIndex = VAR_GET_OBJ_IDX(_group);
    if (_objectiveIndex < 0) exitWith {[false,"unassigned-objective",[]]};
    if (isNil "ITW_Zones" || {
        isNil "ITW_ZoneIndex" || {
            isNil "ITW_ObjContestedOwnerIsFriendly"
        }
    }) exitWith {[false,"objective-state-not-ready",[]]};
    if (ITW_ZoneIndex < 0 || {
        ITW_ZoneIndex >= count ITW_Zones
    }) exitWith {[false,"objective-zone-invalid",[ITW_ZoneIndex]]};
    if !(_objectiveIndex in (ITW_Zones#ITW_ZoneIndex)) exitWith {
        [false,"objective-outside-active-zone",[_objectiveIndex,ITW_ZoneIndex]]
    };

    private _assignedObjective = _group getVariable [
        "ITW_CLASH_AssignedObjective",
        -1
    ];
    if (_group getVariable ["ITW_CLASH_Managed",false] && {
        _assignedObjective >= 0 && {
            _assignedObjective != _objectiveIndex
        }
    }) exitWith {
        [false,"objective-reassigned",[_assignedObjective,_objectiveIndex]]
    };

    [true,"eligible",[
        count _aliveUnits,
        _objectiveIndex,
        groupOwner _group
    ]]
};

ITW_CLASH_fnc_ObserveWriter_V6Base = ITW_CLASH_fnc_ObserveWriter;
ITW_CLASH_fnc_ObserveWriter = {
    params ["_writer","_group"];

    if (isServer && {
        ITW_CLASH_ObserverEnabled && {
            !isNull _group && {
                _writer isEqualTo "infantry-manager-garrison" && {
                    ITW_CLASH_LiveEnabled && {
                        !isNil "ITW_EnemySide" && {
                            side _group == ITW_EnemySide
                        }
                    }
                }
            }
        }
    }) exitWith {
        private _id = [_group] call ITW_CLASH_fnc_GroupId;
        private _key = format ["%1|garrison-suppressed",_id];
        private _last = ITW_CLASH_ObserverWriterLast getOrDefault [
            _key,
            -1000
        ];
        if (time - _last >= 10) then {
            ITW_CLASH_ObserverWriterLast set [_key,time];
            ["impasse-garrison-suppressed",[
                _id,
                str _group,
                count units _group
            ]] call ITW_CLASH_fnc_Log;
        };
        true
    };

    [_writer,_group] call ITW_CLASH_fnc_ObserveWriter_V6Base
};

ITW_CLASH_fnc_GetEgressPoint = {
    params ["_group",["_preferredObjective",-1]];
    if (isNull _group) exitWith {[]};

    private _home = call ITW_CLASH_fnc_GetHomeBaseSpawn;
    if (_home isEqualTo []) exitWith {[]};

    private _affinityObjective = _preferredObjective;
    if (_affinityObjective < 0) then {
        _affinityObjective = _home#1;
    };

    [
        +(_home#0),
        _affinityObjective,
        _home#2
    ]
};

ITW_CLASH_fnc_AcknowledgeReconstitution_V6Base =
    ITW_CLASH_fnc_AcknowledgeReconstitution;

ITW_CLASH_fnc_AcknowledgeReconstitution = {
    params [
        "_group",
        "_requestId",
        "_objectiveIndex",
        "_archetype",
        "_lineage",
        ["_queuedAt",0]
    ];

    if (isServer && {!isNull _group}) then {
        private _home = call ITW_CLASH_fnc_GetHomeBaseSpawn;
        if (_home isNotEqualTo []) then {
            private _homePosition = +(_home#0);
            private _members = units _group;
            private _memberCount = (count _members) max 1;

            {
                private _direction = _forEachIndex * (360 / _memberCount);
                private _radius = 3 + ((_forEachIndex mod 3) * 2);
                private _position = _homePosition getPos [
                    _radius,
                    _direction
                ];
                _position set [2,0];
                _x setPosATL _position;
            } forEach _members;

            _group setVariable [
                "ITW_CLASH_ReconstitutionHomeObjective",
                _home#1
            ];
            _group setVariable [
                "ITW_CLASH_ReconstitutionSpawnSource",
                _home#2
            ];

            ["reconstitution-relocated-home",[
                _requestId,
                _lineage,
                _objectiveIndex,
                _home#1,
                _home#2,
                round (
                    _homePosition distance2D (
                        (ITW_Objectives#_objectiveIndex)#ITW_OBJ_POS
                    )
                )
            ]] call ITW_CLASH_fnc_Log;
        };
    };

    [
        _group,
        _requestId,
        _objectiveIndex,
        _archetype,
        _lineage,
        _queuedAt
    ] call ITW_CLASH_fnc_AcknowledgeReconstitution_V6Base
};

// The four public overrides and their saved base implementations were left
// mutable only for this synchronous correction window. Finalize them now using
// the helper's required string-name contract.
if (!isNil "SKL_fnc_CompileFinal") then {
    {
        [_x] call SKL_fnc_CompileFinal;
    } forEach [
        "ITW_CLASH_fnc_GetHomeBaseSpawn",
        "ITW_CLASH_fnc_ClassifyGroup_V6Base",
        "ITW_CLASH_fnc_ClassifyGroup",
        "ITW_CLASH_fnc_ObserveWriter_V6Base",
        "ITW_CLASH_fnc_ObserveWriter",
        "ITW_CLASH_fnc_GetEgressPoint",
        "ITW_CLASH_fnc_AcknowledgeReconstitution_V6Base",
        "ITW_CLASH_fnc_AcknowledgeReconstitution"
    ];
};

diag_log format [
    "CLASH BOOT | runtime-patch-ready | version=%1",
    ITW_CLASH_RuntimePatchVersion
];
