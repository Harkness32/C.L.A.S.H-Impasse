#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_CASEVAC_Started",false]) exitWith {};

ITW_CLASH_CASEVAC_Started = true;
ITW_CLASH_CASEVAC_Version = 5;
ITW_CLASH_CASEVAC_MaxConcurrent = 2;
ITW_CLASH_CASEVAC_MinWithdrawalTime = 60;
ITW_CLASH_CASEVAC_MinDisengageDistance = 500;
ITW_CLASH_CASEVAC_EnemyClearance = 650;
ITW_CLASH_CASEVAC_InboundAbortClearance = 450;
ITW_CLASH_CASEVAC_ObjectiveClearance = 500;
ITW_CLASH_CASEVAC_MinEgressDistance = 400;
ITW_CLASH_CASEVAC_LZLeadDistance = 175;
ITW_CLASH_CASEVAC_SmokeDistance = 700;
ITW_CLASH_CASEVAC_BoardingTimeout = 90;
ITW_CLASH_CASEVAC_InboundTimeout = 240;
ITW_CLASH_CASEVAC_RetryCooldown = 120;
ITW_CLASH_CASEVAC_SmokeClass = "SmokeShell";
ITW_CLASH_CASEVAC_Active = createHashMap;

diag_log format [
    "CLASH BOOT | casevac-ready | version=%1 max=%2 disengage=%3 enemyClear=%4 objectiveClear=%5 minEgress=%6 symmetricSides=true remnantFastTrack=true",
    ITW_CLASH_CASEVAC_Version,
    ITW_CLASH_CASEVAC_MaxConcurrent,
    ITW_CLASH_CASEVAC_MinDisengageDistance,
    ITW_CLASH_CASEVAC_EnemyClearance,
    ITW_CLASH_CASEVAC_ObjectiveClearance,
    ITW_CLASH_CASEVAC_MinEgressDistance
];

ITW_CLASH_CASEVAC_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["casevac-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance = {
    params ["_group"];
    if (isNull _group) exitWith {1e10};
    private _members = (units _group) select {alive _x};
    if (_members isEqualTo []) exitWith {0};

    private _groupSide = side _group;
    private _enemyUnits = allUnits select {
        alive _x && {(_groupSide getFriend (side _x)) < 0.6}
    };
    if (_enemyUnits isEqualTo []) exitWith {1e10};

    private _best = 1e10;
    {
        private _member = _x;
        {
            private _distance = _member distance2D _x;
            if (_distance < _best) then {_best = _distance};
        } forEach _enemyUnits;
    } forEach _members;
    _best
};

ITW_CLASH_CASEVAC_fnc_GetObjectiveClearance = {
    params ["_group",["_objectiveIndex",-1]];
    if (isNull _group || {
        isNil "ITW_Objectives" || {
            _objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}
        }
    }) exitWith {1e10};

    private _objective = ITW_Objectives#_objectiveIndex;
    private _center = _objective#ITW_OBJ_POS;
    private _radius = _objective#ITW_OBJ_SIZE;
    (leader _group distance2D _center) - _radius
};

ITW_CLASH_CASEVAC_fnc_FindLZ = {
    params ["_group","_destination"];
    if (isNull _group || {_destination isEqualTo []}) exitWith {[]};

    private _origin = getPosATL leader _group;
    private _direction = _origin getDir _destination;
    private _candidate = _origin getPos [
        ITW_CLASH_CASEVAC_LZLeadDistance,
        _direction - 20 + random 40
    ];
    private _lz = [
        _candidate,
        0,
        120,
        12,
        0,
        0.12,
        0,
        [],
        [_candidate,_candidate]
    ] call BIS_fnc_findSafePos;
    if (_lz isEqualTo [] || {surfaceIsWater _lz}) exitWith {[]};
    if (count _lz < 3) then {_lz pushBack 0};
    _lz set [2,0];

    private _groupSide = side _group;
    private _hostileNearLz = allUnits findIf {
        alive _x && {
            (_groupSide getFriend (side _x)) < 0.6 && {
                _x distance2D _lz < (ITW_CLASH_CASEVAC_EnemyClearance - 100)
            }
        }
    };
    if (_hostileNearLz >= 0) exitWith {[]};
    _lz
};

ITW_CLASH_CASEVAC_fnc_GetAirSpawn = {
    params [["_objectiveIndex",-1],["_side",sideUnknown]];
    if (isNil "ITW_Objectives" || {isNil "ITW_Bases"}) exitWith {[]};
    if (_objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}) exitWith {[]};
    if (_side == sideUnknown) then {
        _side = missionNamespace getVariable ["ITW_EnemySide",east];
    };

    private _objective = ITW_Objectives#_objectiveIndex;
    private _reference = +(_objective#ITW_OBJ_POS);
    if (!isNil "ITW_CLASH_Generation_fnc_Resolve") then {
        private _resolved = [
            _side,"CASEVAC","FORWARD_AIR",_reference
        ] call ITW_CLASH_Generation_fnc_Resolve;
        if (_resolved isEqualType createHashMap && {
            (_resolved getOrDefault ["status",""]) == "RESOLVED"
        }) exitWith {
            [
                +(_resolved getOrDefault ["origin",[]]),
                _resolved getOrDefault ["forwardBase",-1],
                "casevac-" + (_resolved getOrDefault ["source","generation-node"])
            ]
        };
    };

    private _attacks = _objective#ITW_OBJ_ATTACKS;
    private _baseIndex = BASE_INDEX_NONE;
    private _source = "casevac-air-support";
    private _slot = if (
        !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}
    ) then {ITW_ATTACK_AIR_F} else {ITW_ATTACK_AIR_E};

    if (count _attacks > _slot) then {
        _baseIndex = _attacks#_slot;
    };
    if (_baseIndex < 0 || {_baseIndex >= count ITW_Bases}) exitWith {[]};

    private _spawn = +(ITW_Bases#_baseIndex#ITW_BASE_A_SPAWN);
    if (_baseIndex < count ITW_Objectives) then {
        private _vehicleSpawn = +(ITW_Objectives#_baseIndex#ITW_OBJ_V_SPAWN);
        if (_vehicleSpawn isNotEqualTo []) then {
            _spawn = _vehicleSpawn;
            _source = _source + "-vehicle-staging";
        };
    };
    if (_spawn isEqualTo []) then {
        _spawn = +(ITW_Bases#_baseIndex#ITW_BASE_POS);
        _source = _source + "-base-position";
    };
    if (_spawn isEqualTo []) exitWith {[]};
    if (count _spawn < 3) then {_spawn pushBack 0};
    [_spawn,_baseIndex,_source]
};

ITW_CLASH_CASEVAC_fnc_SpawnHeli = {
    params ["_seatCount","_spawnInfo",["_recoverySide",sideUnknown]];
    if (_spawnInfo isEqualTo []) exitWith {[]};
    if (_recoverySide == sideUnknown) then {
        _recoverySide = missionNamespace getVariable ["ITW_EnemySide",east];
    };

    private _context = [];
    if (!isNil "ITW_AtkReconstitutionTransportContexts") then {
        _context = ITW_AtkReconstitutionTransportContexts getOrDefault [
            toUpperANSI str _recoverySide,[]
        ];
    };
    if (_context isEqualTo []) then {
        _context = missionNamespace getVariable [
            "ITW_AtkReconstitutionTransportContext",[]
        ];
    };
    if (_context isEqualTo []) exitWith {[]};

    _context params [
        "_transport","_dualVeh","_crewTypes","_unitTypes","_side"
    ];
    if (_side != _recoverySide) exitWith {[]};

    private _candidates = (_transport + _dualVeh) select {
        (_x#ITW_VEH_TYPE) == ITW_TYPE_VEH_HELI && {
            (_x#ITW_VEH_REQD_TICKETS) <= (_x#ITW_VEH_CURR_TICKETS) && {
                (_x#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT || {
                    (_x#ITW_VEH_COUNT) < (_x#ITW_VEH_MAX)
                }
            }
        }
    };
    if (_candidates isEqualTo []) exitWith {[]};

    private _ordered = if (
        missionNamespace getVariable ["ITW_CLASH_ServiceCapacityPolicyReady",false]
        && {!isNil "ITW_CLASH_ServiceCapacity_fnc_RankVariants"}
    ) then {
        [_seatCount,_candidates,"AIR","CASEVAC"] call
            ITW_CLASH_ServiceCapacity_fnc_RankVariants
    } else {
        private _pureTransport = _candidates select {
            (_x#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT
        };
        private _legacy = [];
        {
            private _vehDef = _x;
            {
                private _class = if (_x isEqualType []) then {
                    if (_x isEqualTo []) then {""} else {_x#0}
                } else {_x};
                if (_class isEqualTo "") then {continue};
                _legacy pushBack [0,_vehDef,_x,_class,-1,false,0,0];
            } forEach (_vehDef#ITW_VEH_CLASSES);
        } forEach (_pureTransport + (_candidates - _pureTransport));
        _legacy
    };
    _spawnInfo params ["_spawnPos","_baseIndex","_spawnSource"];

    private _result = [];
    scopeName "ITW_CLASH_CASEVAC_SPAWN";
    {
        _x params [
            "_capacityScore","_vehDef","_variant","_class",
            "_estimatedCapacity","_capacityKnown","_ticketCost","_maxSpeed"
        ];
        private _spawnDef = +_vehDef;
        _spawnDef set [ITW_VEH_CLASSES,[_variant]];
        private _heli = [
            _spawnDef,_crewTypes,_unitTypes,_side,_spawnPos
        ] call ITW_AtkSpawnVeh;
        if (isNull _heli) then {continue};

        private _crewGroup = group driver _heli;
        if !(_heli isKindOf "Helicopter") then {
            deleteVehicleCrew _heli;
            deleteVehicle _heli;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {
                deleteGroup _crewGroup;
            };
            continue;
        };

        if ((_heli emptyPositions "cargo") < _seatCount) then {
            deleteVehicleCrew _heli;
            deleteVehicle _heli;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {
                deleteGroup _crewGroup;
            };
            continue;
        };

        ITW_TICKET_SEM_CHECK;
        ITW_VEH_COUNT_INCR(_vehDef);
        _heli setVariable ["ITW_VehDef",_vehDef];
        ITW_TICKET_SEM_CHECK;
        ITW_TICKET_REDUCE(_vehDef);

        _heli setVariable ["ITW_CLASH_CASEVAC",true,true];
        _crewGroup setVariable ["ITW_CLASH_CASEVAC",true];
        _crewGroup setVariable ["noHeadless",true];
        _crewGroup allowFleeing 0;
        _crewGroup enableAttack false;
        _crewGroup setBehaviourStrong "CARELESS";
        _crewGroup setCombatMode "BLUE";
        _crewGroup setSpeedMode "FULL";
        _heli flyInHeight 50;
        _heli limitSpeed 250;

        if (!isNil "ITW_AtkVehRemoveMagazines") then {
            [_heli] remoteExec ["ITW_AtkVehRemoveMagazines",_heli];
        };
        ALLOW_DAMAGE(_heli,true);
        {ALLOW_DAMAGE(_x,true)} forEach crew _heli;
        {_x addCuratorEditableObjects [[_heli] + units _crewGroup,true]} forEach allCurators;

        ["aircraft-selected",[
            typeOf _heli,_seatCount,_heli emptyPositions "cargo",
            _estimatedCapacity,round _capacityScore,_ticketCost,_maxSpeed
        ]] call ITW_CLASH_CASEVAC_fnc_Log;

        _result = [_heli,_crewGroup,_vehDef,_baseIndex,_spawnSource,+_spawnPos];
        breakOut "ITW_CLASH_CASEVAC_SPAWN";
    } forEach _ordered;
    _result
};

ITW_CLASH_CASEVAC_fnc_OrderLZ = {
    params ["_group","_lz"];
    if (isNull _group || {_lz isEqualTo []}) exitWith {false};

    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group enableAttack false;
    _group setCombatMode "BLUE";
    _group setBehaviourStrong "AWARE";
    _group setSpeedMode "FULL";

    private _wp = _group addWaypoint [_lz,20];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 30;
    true
};

ITW_CLASH_CASEVAC_fnc_SendHeliHome = {
    params ["_heli","_crewGroup","_returnPos"];
    if (isNull _heli || {!alive _heli} || {isNull _crewGroup}) exitWith {};

    {deleteWaypoint _x} forEachReversed waypoints _crewGroup;
    _crewGroup enableAttack false;
    _crewGroup setBehaviourStrong "CARELESS";
    _crewGroup setCombatMode "BLUE";
    _crewGroup setSpeedMode "FULL";
    _heli land "NONE";
    _heli flyInHeight 50;
    _heli limitSpeed 250;

    private _wp = _crewGroup addWaypoint [_returnPos,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 150;
};

ITW_CLASH_CASEVAC_fnc_CleanupHeli = {
    params ["_heli","_crewGroup",["_delay",10]];
    [_heli,_crewGroup,_delay] spawn {
        params ["_heli","_crewGroup","_delay"];
        sleep _delay;
        if (!isNull _heli) then {
            deleteVehicleCrew _heli;
            deleteVehicle _heli;
        };
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {
            deleteGroup _crewGroup;
        };
    };
};

ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal = {
    params ["_id","_group","_reason",["_heli",objNull],["_crewGroup",grpNull],["_returnPos",[]]];

    ITW_CLASH_CASEVAC_Active deleteAt _id;
    if (!isNull _group) then {
        _group setVariable ["ITW_CLASH_CASEVAC_State",nil];
        _group setVariable ["ITW_CLASH_CASEVAC_Heli",nil];
        _group setVariable ["ITW_CLASH_CASEVAC_LZ",nil];
        _group setVariable ["ITW_CLASH_CASEVAC_RetryAt",time + ITW_CLASH_CASEVAC_RetryCooldown];
        {
            if (vehicle _x != _x && {
                isNull _heli || {vehicle _x == _heli}
            }) then {
                private _veh = vehicle _x;
                if (isNull _heli || {
                    !alive _heli || {
                        isTouchingGround _heli || {(getPosATL _heli)#2 < 5}
                    }
                }) then {
                    unassignVehicle _x;
                    _x action ["GetOut",_veh];
                };
            };
        } forEach (units _group select {alive _x});
    };

    private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
    if (_entry isNotEqualTo [] && {!isNull _group}) then {
        _entry set [8,-1000];
        ITW_CLASH_Withdrawals set [_id,_entry];
        [
            _group,
            _entry#5,
            _entry#6,
            _entry#7
        ] call ITW_CLASH_fnc_OrderWithdrawal;
        _entry = ITW_CLASH_Withdrawals getOrDefault [_id,_entry];
        _entry set [8,time];
        ITW_CLASH_Withdrawals set [_id,_entry];
    };

    ["failed",[
        _id,
        if (isNull _group) then {""} else {
            _group getVariable ["ITW_CLASH_Lineage",_id]
        },
        _reason
    ]] call ITW_CLASH_CASEVAC_fnc_Log;

    if (!isNull _heli && {alive _heli} && {
        _returnPos isNotEqualTo [] && {!isNull _crewGroup}
    }) then {
        [_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_SendHeliHome;
        [_heli,_crewGroup,_returnPos,180] spawn {
            params ["_heli","_crewGroup","_returnPos","_timeout"];
            private _end = time + _timeout;
            waitUntil {
                sleep 2;
                isNull _heli || {
                    !alive _heli || {
                        time > _end || {
                            isNull _crewGroup || {
                                _heli distance2D _returnPos <= 200
                            }
                        }
                    }
                }
            };
            [_heli,_crewGroup,0] call ITW_CLASH_CASEVAC_fnc_CleanupHeli;
        };
    } else {
        [_heli,_crewGroup,5] call ITW_CLASH_CASEVAC_fnc_CleanupHeli;
    };
};

ITW_CLASH_CASEVAC_fnc_RunExtraction = {
    params [
        "_id","_group","_heli","_crewGroup","_lz","_returnPos",
        "_originalObjective","_egressObjective","_archetype","_lineage","_startedAt"
    ];
    scriptName "ITW_CLASH_CASEVAC_fnc_RunExtraction";

    private _inboundDeadline = time + ITW_CLASH_CASEVAC_InboundTimeout;
    private _smokeThrown = false;
    private _landed = false;
    private _nextContactCheck = 0;

    scopeName "ITW_CLASH_CASEVAC_InboundScope";
    while {!_landed} do {
        sleep 1;
        if (isNull _group || {{alive _x} count units _group == 0}) exitWith {
            [
                _id,_group,"squad-lost-before-pickup",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if (isNull _heli || {!alive _heli} || {!canMove _heli} || {isNull driver _heli}) exitWith {
            [
                _id,_group,"aircraft-lost-inbound",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if ((ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo []) exitWith {
            ITW_CLASH_CASEVAC_Active deleteAt _id;
            [_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_SendHeliHome;
            [_heli,_crewGroup,30] call ITW_CLASH_CASEVAC_fnc_CleanupHeli;
        };
        if (time > _inboundDeadline) exitWith {
            [
                _id,_group,"inbound-timeout",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };

        if (time >= _nextContactCheck) then {
            _nextContactCheck = time + 5;
            private _contactDistance = [
                _group
            ] call ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance;
            if (_contactDistance < ITW_CLASH_CASEVAC_InboundAbortClearance) then {
                ["abort-contact",[
                    _id,_lineage,round _contactDistance,
                    ITW_CLASH_CASEVAC_InboundAbortClearance
                ]] call ITW_CLASH_CASEVAC_fnc_Log;
                [
                    _id,_group,"contact-reestablished",_heli,_crewGroup,_returnPos
                ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
                breakOut "ITW_CLASH_CASEVAC_InboundScope";
            };
        };

        private _distance = _heli distance2D _lz;
        if (!_smokeThrown && {_distance <= ITW_CLASH_CASEVAC_SmokeDistance}) then {
            private _smoke = createVehicle [
                ITW_CLASH_CASEVAC_SmokeClass,
                _lz,
                [],
                0,
                "CAN_COLLIDE"
            ];
            if (!isNull _smoke) then {_smoke setPosATL _lz};
            _smokeThrown = true;
            ["smoke",[_id,_lineage,_lz,round _distance]] call ITW_CLASH_CASEVAC_fnc_Log;
        };

        if (_distance <= 350) then {
            _heli limitSpeed 90;
            _heli flyInHeight 10;
        };
        if (_distance <= 150) then {
            _heli land "GET IN";
        };

        if (_distance <= 120 && {
            isTouchingGround _heli || {
                (getPosATL _heli)#2 < 2.5 && {abs speed _heli < 8}
            }
        }) then {
            _landed = true;
        };
    };

    if (!_landed || {isNull _group} || {isNull _heli} || {!alive _heli}) exitWith {};
    ["landed",[_id,_lineage,_lz]] call ITW_CLASH_CASEVAC_fnc_Log;

    private _boardDeadline = time + ITW_CLASH_CASEVAC_BoardingTimeout;
    private _loaded = false;
    while {!_loaded} do {
        sleep 2;
        if (isNull _group || {{alive _x} count units _group == 0}) exitWith {
            [
                _id,_group,"squad-lost-boarding",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if (isNull _heli || {!alive _heli} || {!canMove _heli} || {isNull driver _heli}) exitWith {
            [
                _id,_group,"aircraft-lost-boarding",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if (time > _boardDeadline) exitWith {
            [
                _id,_group,"boarding-timeout",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };

        private _survivors = units _group select {alive _x};
        {
            if (vehicle _x != _heli) then {
                unassignVehicle _x;
                _x assignAsCargo _heli;
                _x doMove getPosATL _heli;
            };
        } forEach _survivors;
        _survivors orderGetIn true;

        _loaded = (_survivors findIf {vehicle _x != _heli}) < 0;
    };

    if (!_loaded || {isNull _group} || {isNull _heli} || {!alive _heli}) exitWith {};
    ["loaded",[
        _id,_lineage,{alive _x} count units _group,typeOf _heli
    ]] call ITW_CLASH_CASEVAC_fnc_Log;

    _group setVariable ["ITW_CLASH_CASEVAC_State","rtb"];
    private _latestEntry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
    if (_latestEntry isNotEqualTo [] && {
        (_latestEntry#5) isNotEqualTo []
    }) then {
        _returnPos = +(_latestEntry#5);
    };
    [_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_SendHeliHome;
    ["rtb",[
        _id,_lineage,_egressObjective,round (_heli distance2D _returnPos)
    ]] call ITW_CLASH_CASEVAC_fnc_Log;

    private _returnDeadline = time + 300;
    private _returned = false;
    while {!_returned} do {
        sleep 2;
        if ((ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo []) then {
            _returned = true;
            continue;
        };
        if (isNull _heli || {!alive _heli} || {!canMove _heli} || {isNull driver _heli}) exitWith {
            [
                _id,_group,"aircraft-lost-rtb",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if (time > _returnDeadline) exitWith {
            [
                _id,_group,"rtb-timeout",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if (_heli distance2D _returnPos <= 140) then {
            // Canonical V6 withdrawal audit owns the actual absorption and
            // reconstitution credit. Entering the 150 m rear-area bubble is
            // enough; do not create a second credit path here.
            _returned = true;
        };
    };

    if (_returned) then {
        private _waitForCanonical = time + 30;
        waitUntil {
            sleep 1;
            (ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo [] || {
                time > _waitForCanonical
            }
        };
        private _absorbed = (ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo [];

        if (!_absorbed && {!isNull _group} && {!isNull _heli} && {alive _heli}) then {
            ["rear-handoff-fallback",[
                _id,_lineage,_egressObjective,
                round (_heli distance2D _returnPos)
            ]] call ITW_CLASH_CASEVAC_fnc_Log;

            _heli land "GET OUT";
            private _landDeadline = time + 20;
            waitUntil {
                sleep 1;
                isNull _heli || {!alive _heli} || {
                    isTouchingGround _heli || {
                        (getPosATL _heli)#2 < 2.5 || {time > _landDeadline}
                    }
                }
            };

            if (!isNull _group && {!isNull _heli} && {alive _heli}) then {
                private _survivors = units _group select {alive _x};
                {
                    if (vehicle _x == _heli) then {
                        unassignVehicle _x;
                        _x action ["GetOut",_heli];
                    };
                } forEach _survivors;
                private _getOutDeadline = time + 15;
                waitUntil {
                    sleep 1;
                    isNull _group || {
                        (_survivors findIf {alive _x && {vehicle _x == _heli}}) < 0 || {
                            time > _getOutDeadline
                        }
                    }
                };
            };

            [
                _id,_group,"rear-absorption-timeout",_heli,_crewGroup,_returnPos
            ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        } else {
            ["returned",[
                _id,_lineage,_egressObjective,_absorbed,
                if (isNull _heli) then {-1} else {round (_heli distance2D _returnPos)}
            ]] call ITW_CLASH_CASEVAC_fnc_Log;
            ITW_CLASH_CASEVAC_Active deleteAt _id;
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_CASEVAC_State",nil];
                _group setVariable ["ITW_CLASH_CASEVAC_Heli",nil];
                _group setVariable ["ITW_CLASH_CASEVAC_LZ",nil];
            };
            [_heli,_crewGroup,15] call ITW_CLASH_CASEVAC_fnc_CleanupHeli;
        };
    };
};

ITW_CLASH_CASEVAC_fnc_Eligible = {
    params ["_id","_entry"];
    if (_entry isEqualTo [] || {count _entry < 9}) exitWith {[false,[]]};
    _entry params [
        "_group","_originalObjective","_archetype","_lineage","_startedAt",
        "_destination","_egressObjective","_source","_lastOrder"
    ];
    if (isNull _group || {{alive _x} count units _group == 0}) exitWith {[false,[]]};
    if !(_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {[false,[]]};
    if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") exitWith {[false,[]]};
    if (time < (_group getVariable ["ITW_CLASH_CASEVAC_RetryAt",0])) exitWith {[false,[]]};
    private _remnantEvac = _group getVariable ["ITW_CLASH_RemnantEvac",false];
    private _minWithdrawalTime = if (_remnantEvac) then {
        missionNamespace getVariable [
            "ITW_CLASH_RemnantEvacMinWithdrawalTime",
            ITW_CLASH_CASEVAC_MinWithdrawalTime
        ]
    } else {
        ITW_CLASH_CASEVAC_MinWithdrawalTime
    };
    if (time - _startedAt < _minWithdrawalTime) exitWith {[false,[]]};
    if (_destination isEqualTo []) exitWith {[false,[]]};

    private _origin = _group getVariable ["ITW_CLASH_CASEVAC_Origin",[]];
    if (_origin isEqualTo []) then {
        _origin = getPosATL leader _group;
        _group setVariable ["ITW_CLASH_CASEVAC_Origin",+_origin];
    };

    private _moved = leader _group distance2D _origin;
    if (!_remnantEvac && {
        _moved < ITW_CLASH_CASEVAC_MinDisengageDistance
    }) exitWith {[false,[]]};

    private _egressDistance = leader _group distance2D _destination;
    if (_egressDistance < ITW_CLASH_CASEVAC_MinEgressDistance) exitWith {[false,[]]};

    private _objectiveClearance = [
        _group,_originalObjective
    ] call ITW_CLASH_CASEVAC_fnc_GetObjectiveClearance;
    if (_objectiveClearance < ITW_CLASH_CASEVAC_ObjectiveClearance) exitWith {[false,[]]};

    private _enemyDistance = [
        _group
    ] call ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance;
    if (_enemyDistance < ITW_CLASH_CASEVAC_EnemyClearance) exitWith {[false,[]]};

    private _aliveUnits = units _group select {alive _x};
    if (_aliveUnits findIf {vehicle _x != _x} >= 0) exitWith {[false,[]]};

    private _lz = [_group,_destination] call ITW_CLASH_CASEVAC_fnc_FindLZ;
    if (_lz isEqualTo []) exitWith {[false,[]]};

    [true,[
        _group,_originalObjective,+_archetype,_lineage,_startedAt,
        +_destination,_egressObjective,_source,_moved,_enemyDistance,
        _objectiveClearance,_egressDistance,+_lz
    ]]
};

ITW_CLASH_CASEVAC_fnc_Dispatch = {
    params ["_id","_data"];
    _data params [
        "_group","_originalObjective","_archetype","_lineage","_startedAt",
        "_destination","_egressObjective","_source","_moved","_enemyDistance",
        "_objectiveClearance","_egressDistance","_lz"
    ];
    if (isNull _group) exitWith {false};
    if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") exitWith {false};

    // Claim before spawning; vehicle/crew creation can yield.
    _group setVariable ["ITW_CLASH_CASEVAC_State","air-spawning"];

    private _spawnInfo = [
        _originalObjective,side _group
    ] call ITW_CLASH_CASEVAC_fnc_GetAirSpawn;
    if (_spawnInfo isEqualTo []) exitWith {
        _group setVariable ["ITW_CLASH_CASEVAC_State",nil];
        _group setVariable ["ITW_CLASH_CASEVAC_RetryAt",time + 15];
        false
    };

    private _survivors = units _group select {alive _x};
    private _heliInfo = [
        count _survivors,_spawnInfo,side _group
    ] call ITW_CLASH_CASEVAC_fnc_SpawnHeli;
    if (_heliInfo isEqualTo []) exitWith {
        _group setVariable ["ITW_CLASH_CASEVAC_State",nil];
        _group setVariable ["ITW_CLASH_CASEVAC_RetryAt",time + 15];
        false
    };

    _heliInfo params [
        "_heli","_crewGroup","_vehDef","_baseIndex","_spawnSource","_spawnPos"
    ];

    _group setVariable ["ITW_CLASH_CASEVAC_State","inbound"];
    _group setVariable ["ITW_CLASH_CASEVAC_Heli",_heli];
    _group setVariable ["ITW_CLASH_CASEVAC_LZ",+_lz];

    private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
    if (_entry isNotEqualTo []) then {
        // Suppress V6's 30-second foot-egress waypoint refresh while CASEVAC
        // owns the squad. Keep the original egress destination intact so the
        // canonical 150 m absorption check can still complete on RTB.
        _entry set [8,time + 1e6];
        ITW_CLASH_Withdrawals set [_id,_entry];
    };

    [_group,_lz] call ITW_CLASH_CASEVAC_fnc_OrderLZ;
    ITW_CLASH_CASEVAC_Active set [
        _id,[_group,_heli,_crewGroup,+_lz,+_destination,time]
    ];

    ["dispatched",[
        _id,_lineage,_originalObjective,_egressObjective,typeOf _heli,
        _baseIndex,_spawnSource,round _moved,round _enemyDistance,
        round _objectiveClearance,round _egressDistance,_lz
    ]] call ITW_CLASH_CASEVAC_fnc_Log;

    [
        _id,_group,_heli,_crewGroup,_lz,_destination,
        _originalObjective,_egressObjective,_archetype,_lineage,_startedAt
    ] spawn ITW_CLASH_CASEVAC_fnc_RunExtraction;
    true
};

[] spawn {
    scriptName "ITW_CLASH_CASEVAC_Manager";
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 3;

        if (isNil "ITW_CLASH_LiveEnabled" || {
            !ITW_CLASH_LiveEnabled || {
                isNil "ITW_CLASH_HALReady" || {
                    !ITW_CLASH_HALReady || {
                        isNil "ITW_CLASH_Withdrawals"
                    }
                }
            }
        }) then {continue};

        // Record a physical retreat origin as soon as a withdrawal appears, not
        // only after it is already eligible. This makes the 500 m disengagement
        // test measure actual post-break-contact movement.
        {
            private _entry = ITW_CLASH_Withdrawals getOrDefault [_x,[]];
            if (_entry isEqualTo [] || {count _entry < 9}) then {continue};
            private _group = _entry#0;
            if (isNull _group) then {continue};
            if ((_group getVariable ["ITW_CLASH_CASEVAC_Origin",[]]) isEqualTo []) then {
                _group setVariable ["ITW_CLASH_CASEVAC_Origin",getPosATL leader _group];
                ["observed",[
                    _x,_entry#3,_entry#1,getPosATL leader _group
                ]] call ITW_CLASH_CASEVAC_fnc_Log;
            };
        } forEach +(keys ITW_CLASH_Withdrawals);

        if (count ITW_CLASH_CASEVAC_Active >= ITW_CLASH_CASEVAC_MaxConcurrent) then {
            continue;
        };

        {
            if (count ITW_CLASH_CASEVAC_Active >= ITW_CLASH_CASEVAC_MaxConcurrent) exitWith {};
            private _id = _x;
            if (_id in (keys ITW_CLASH_CASEVAC_Active)) then {continue};
            private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
            private _eligibility = [_id,_entry] call ITW_CLASH_CASEVAC_fnc_Eligible;
            if !(_eligibility#0) then {continue};

            ["eligible",[
                _id,
                (_eligibility#1)#3,
                round ((_eligibility#1)#8),
                round ((_eligibility#1)#9),
                round ((_eligibility#1)#10),
                round ((_eligibility#1)#11)
            ]] call ITW_CLASH_CASEVAC_fnc_Log;

            [_id,_eligibility#1] call ITW_CLASH_CASEVAC_fnc_Dispatch;
        } forEach +(keys ITW_CLASH_Withdrawals);
    };

    ITW_CLASH_CASEVAC_Started = false;
    diag_log "CLASH BOOT | casevac-stopped";
};
