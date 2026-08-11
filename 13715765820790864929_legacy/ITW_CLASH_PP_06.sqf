#include "defines.hpp"

// C.L.A.S.H. V6 preprocessor bisect chunk 6/8.
// Original ITW_CLASH.sqf lines 1597-1980. Diagnostic only; never executed.

ITW_CLASH_fnc_AuditAllocations = {
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            !ITW_CLASH_HALReady || {
                ITW_CLASH_Transitioning
            }
        }
    }) exitWith {[]};

    private _activeObjectives = call ITW_CLASH_fnc_GetActiveObjectives;
    private _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    private _heldIndices = _heldObjectives apply {_x#0};
    private _allocations = [];
    private _drifted = [];

    {
        private _group = _x;
        if (!isNull _group && {
            _group getVariable ["ITW_CLASH_Managed",false]
        }) then {
            private _id = [_group] call ITW_CLASH_fnc_GroupId;
            private _assignedObjective = _group getVariable [
                "ITW_CLASH_AssignedObjective",
                VAR_GET_OBJ_IDX(_group)
            ];
            private _assignedFlag = [_assignedObjective] call ITW_CLASH_fnc_GetObjectiveFlag;
            private _waypointIndex = currentWaypoint _group;
            private _waypointCount = count waypoints _group;
            private _hasWaypoint = _waypointCount > 0 && {
                _waypointIndex >= 0 && {_waypointIndex < _waypointCount}
            };
            private _waypointPosition = getPosATL (leader _group);
            private _waypointType = "";
            if (_hasWaypoint) then {
                _waypointPosition = waypointPosition [_group,_waypointIndex];
                _waypointType = waypointType [_group,_waypointIndex];
            };

            private _nearestObjective = -1;
            private _nearestDistance = 1e10;
            {
                _x params ["_objectiveIndex","_flag"];
                private _distance = _waypointPosition distance2D _flag;
                if (_distance < _nearestDistance) then {
                    _nearestObjective = _objectiveIndex;
                    _nearestDistance = _distance;
                };
            } forEach _activeObjectives;

            private _assignedDistance = if (isNull _assignedFlag) then {
                1e10
            } else {
                _waypointPosition distance2D _assignedFlag
            };
            private _state = if (_group getVariable ["Defending",false]) then {
                "defending"
            } else {
                if (_group getVariable ["Busy" + str _group,false]) then {
                    "busy"
                } else {
                    "awaiting-order"
                }
            };

            private _role = if (
                (_group getVariable ["ITW_CLASH_AnchorObjective",-1]) == _assignedObjective
            ) then {
                "anchor"
            } else {
                if (!isNull ITW_CLASH_HALHQ && {
                    _group in (ITW_CLASH_HALHQ getVariable ["RydHQ_DefRes",[]])
                }) then {
                    "reserve"
                } else {
                    "main"
                }
            };

            private _entry = [
                _id,
                _assignedObjective,
                _state,
                _nearestObjective,
                _waypointType,
                round _assignedDistance,
                round _nearestDistance,
                _role
            ];
            _allocations pushBack _entry;

            if (_state isEqualTo "defending" && {
                _hasWaypoint && {
                    _nearestObjective >= 0 && {
                        _nearestObjective != _assignedObjective && {
                            _nearestDistance + ITW_CLASH_AllocationDriftMargin < _assignedDistance
                        }
                    }
                }
            }) then {
                _drifted pushBack [_group,_entry];
            };
        };
    } forEach +ITW_CLASH_ManagedGroups;

    private _coverage = [];
    {
        private _objectiveIndex = _x#0;
        _coverage pushBack [
            _objectiveIndex,
            if (_objectiveIndex in _heldIndices) then {"held"} else {"recovery"},
            {
                !isNull _x && {
                    (_x getVariable ["ITW_CLASH_AssignedObjective",-1]) == _objectiveIndex
                }
            } count ITW_CLASH_ManagedGroups,
            {
                (_x#3) == _objectiveIndex
            } count _allocations
        ];
    } forEach _activeObjectives;

    private _signature = str [
        ITW_ZoneIndex,
        _coverage,
        _allocations apply {[_x#0,_x#1,_x#2,_x#3,_x#4,_x#7]}
    ];
    if (_signature != ITW_CLASH_LastAllocationSignature) then {
        ITW_CLASH_LastAllocationSignature = _signature;
        ["objective-allocation",[ITW_ZoneIndex,_coverage,_allocations]] call ITW_CLASH_fnc_Log;
    };

    {
        _x params ["_group","_entry"];
        _group setVariable [
            "ITW_CLASH_ReeligibleAt",
            time + ITW_CLASH_AllocationDriftCooldown
        ];
        ["allocation-drift",_entry] call ITW_CLASH_fnc_Log;
        [_group,"objective-allocation-drift"] call ITW_CLASH_fnc_ReleaseGroup;
    } forEach _drifted;

    _allocations
};

ITW_CLASH_fnc_RegisterGroup = {
    params ["_group",["_source","reconcile"],["_allowBeforeReady",false]];
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {false};
    if (!ITW_CLASH_HALReady && {!_allowBeforeReady}) exitWith {false};
    if (isNull _group || {!local _group}) exitWith {false};
    if ([_group] call ITW_CLASH_fnc_IsCommanderGroup) exitWith {false};
    if (_group getVariable ["ITW_CLASH_Managed",false]) exitWith {true};

    private _result = [_group] call ITW_CLASH_fnc_ClassifyGroup;
    if !(_result#0) exitWith {false};

    private _objectiveIndex = VAR_GET_OBJ_IDX(_group);
    private _sameObjectiveCount = {
        !isNull _x && {
            (_x getVariable ["ITW_CLASH_Managed",false]) && {
                VAR_GET_OBJ_IDX(_x) == _objectiveIndex
            }
        }
    } count ITW_CLASH_ManagedGroups;

    private _isAnchorRefill = (
        _group getVariable ["ITW_CLASH_RefillObjective",-1]
    ) == _objectiveIndex;
    private _isReconstitution = (
        _group getVariable ["ITW_CLASH_ReconstitutionRequest",""]
    ) isNotEqualTo "";
    private _isPriorityReplacement = _isAnchorRefill || _isReconstitution;
    if (_isPriorityReplacement && {
        count ITW_CLASH_ManagedGroups >= ITW_CLASH_MaxManagedGroups || {
            _sameObjectiveCount >= ITW_CLASH_MaxManagedPerObjective
        }
    }) then {
        private _victim = grpNull;
        private _victimSize = 1e10;

        {
            private _candidate = _x;
            if (!isNull _candidate && {
                (_candidate getVariable ["ITW_CLASH_AssignedObjective",-1]) == _objectiveIndex && {
                    (_candidate getVariable ["ITW_CLASH_AnchorObjective",-1]) < 0 && {
                        (_candidate getVariable ["ITW_CLASH_RefillObjective",-1]) < 0 && {
                            (_candidate getVariable ["ITW_CLASH_ReconstitutionRequest",""]) isEqualTo "" && {
                                !(_candidate getVariable ["ITW_CLASH_Releasing",false])
                            }
                        }
                    }
                }
            }) then {
                private _candidateSize = [
                    units _candidate
                ] call ITW_CLASH_fnc_CountConscious;
                if (_candidateSize < _victimSize) then {
                    _victim = _candidate;
                    _victimSize = _candidateSize;
                };
            };
        } forEach +ITW_CLASH_ManagedGroups;

        if (isNull _victim && {
            count ITW_CLASH_ManagedGroups >= ITW_CLASH_MaxManagedGroups
        }) then {
            {
                private _candidate = _x;
                private _candidateObjective = _candidate getVariable [
                    "ITW_CLASH_AssignedObjective",
                    -1
                ];
                private _objectiveCount = {
                    !isNull _x && {
                        (_x getVariable ["ITW_CLASH_AssignedObjective",-1]) == _candidateObjective
                    }
                } count ITW_CLASH_ManagedGroups;
                if (!isNull _candidate && {
                    _objectiveCount > 1 && {
                        (_candidate getVariable ["ITW_CLASH_AnchorObjective",-1]) < 0 && {
                            (_candidate getVariable ["ITW_CLASH_RefillObjective",-1]) < 0 && {
                                (_candidate getVariable ["ITW_CLASH_ReconstitutionRequest",""]) isEqualTo "" && {
                                    !(_candidate getVariable ["ITW_CLASH_Releasing",false])
                                }
                            }
                        }
                    }
                }) then {
                    private _candidateSize = [
                        units _candidate
                    ] call ITW_CLASH_fnc_CountConscious;
                    if (_candidateSize < _victimSize) then {
                        _victim = _candidate;
                        _victimSize = _candidateSize;
                    };
                };
            } forEach +ITW_CLASH_ManagedGroups;
        };

        if (!isNull _victim) then {
            private _capacityEvent = if (_isReconstitution) then {
                "reconstitution-capacity-reclaim"
            } else {
                "anchor-capacity-reclaim"
            };
            private _capacityReason = if (_isReconstitution) then {
                "reconstitution-capacity"
            } else {
                "anchor-refill-capacity"
            };
            [_capacityEvent,[
                _objectiveIndex,
                [_victim] call ITW_CLASH_fnc_GroupId,
                _victimSize,
                [_group] call ITW_CLASH_fnc_GroupId
            ]] call ITW_CLASH_fnc_Log;
            [_victim,_capacityReason] call ITW_CLASH_fnc_ReleaseGroup;
            _sameObjectiveCount = {
                !isNull _x && {
                    (_x getVariable ["ITW_CLASH_Managed",false]) && {
                        VAR_GET_OBJ_IDX(_x) == _objectiveIndex
                    }
                }
            } count ITW_CLASH_ManagedGroups;
        };
    };

    if (count ITW_CLASH_ManagedGroups >= ITW_CLASH_MaxManagedGroups || {
        _sameObjectiveCount >= ITW_CLASH_MaxManagedPerObjective
    }) exitWith {
        if !(_group getVariable ["ITW_CLASH_CapacityLogged",false]) then {
            _group setVariable ["ITW_CLASH_CapacityLogged",true];
            ["pilot-capacity",[
                [_group] call ITW_CLASH_fnc_GroupId,
                _objectiveIndex,
                count ITW_CLASH_ManagedGroups,
                _sameObjectiveCount
            ]] call ITW_CLASH_fnc_Log;
        };
        false
    };

    _group setVariable ["ITW_CLASH_CapacityLogged",nil];
    _group setVariable ["RydHQ_MIA",nil];
    [_group] call ITW_CLASH_fnc_GetArchetype;
    if ((_group getVariable ["ITW_CLASH_Lineage",""]) isEqualTo "") then {
        _group setVariable [
            "ITW_CLASH_Lineage",
            [_group] call ITW_CLASH_fnc_GroupId
        ];
    };
    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group setVariable ["ITW_CLASH_Managed",true];
    _group setVariable ["ITW_CLASH_AssignedObjective",_objectiveIndex];
    ITW_CLASH_ManagedGroups pushBackUnique _group;
    call ITW_CLASH_fnc_SyncHALIncluded;

    ["register",[
        _source,
        [_group] call ITW_CLASH_fnc_GroupId,
        str _group,
        _objectiveIndex,
        count units _group
    ]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_BeginRelease = {
    params ["_group",["_reason","unspecified"]];
    if (!isServer || {!ITW_CLASH_LiveEnabled} || {isNull _group}) exitWith {false};

    private _managed = _group getVariable ["ITW_CLASH_Managed",false] || {
        _group in ITW_CLASH_ManagedGroups
    };
    if (!_managed || {_group getVariable ["ITW_CLASH_Releasing",false]}) exitWith {false};

    _group setVariable ["ITW_CLASH_ReleaseReason",_reason];
    _group setVariable ["ITW_CLASH_ReleaseStarted",diag_tickTime];
    _group setVariable ["ITW_CLASH_Releasing",true];
    _group setVariable ["RydHQ_MIA",true];
    private _anchorObjective = _group getVariable ["ITW_CLASH_AnchorObjective",-1];
    if (_anchorObjective >= 0) then {
        private _key = [_anchorObjective] call ITW_CLASH_fnc_AnchorKey;
        private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
        if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo _group}) then {
            [
                _anchorObjective,
                format ["release:%1",_reason]
            ] call ITW_CLASH_fnc_ClearAnchorSlot;
        };
    };
    ITW_CLASH_ManagedGroups = ITW_CLASH_ManagedGroups - [_group];
    call ITW_CLASH_fnc_SyncHALIncluded;

    if (!isNull ITW_CLASH_HALHQ) then {
        {
            private _varName = _x;
            if ((_varName select [0,6]) isEqualTo "RydHQ_") then {
                private _value = ITW_CLASH_HALHQ getVariable _varName;
                if (_value isEqualType [] && {_group in _value}) then {
                    ITW_CLASH_HALHQ setVariable [_varName,_value - [_group]];
                };
            };
        } forEach allVariables ITW_CLASH_HALHQ;
    };
    true
};

ITW_CLASH_fnc_ReleaseAcknowledged = {
    params ["_group"];
    if (isNull _group) exitWith {true};

    private _releaseStarted = _group getVariable ["ITW_CLASH_ReleaseStarted",diag_tickTime];
    if (diag_tickTime - _releaseStarted < 6.5) exitWith {false};

    private _busyName = "Busy" + str _group;
    !(_group getVariable [_busyName,false]) || {
        !(_group getVariable ["RydHQ_MIA",false])
    }
};

ITW_CLASH_fnc_FinishRelease = {
    params ["_group",["_timedOut",false]];
    if (isNull _group) exitWith {false};

    private _reason = _group getVariable ["ITW_CLASH_ReleaseReason","unspecified"];
    private _id = [_group] call ITW_CLASH_fnc_GroupId;
    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group setVariable ["ITW_CLASH_Managed",false];
    _group setVariable ["ITW_CLASH_AssignedObjective",nil];
    _group setVariable ["ITW_CLASH_AnchorObjective",nil];
    _group setVariable ["ITW_CLASH_AnchorAssignedAt",nil];
    _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
    _group setVariable ["ITW_CLASH_RefillObjective",nil];
    _group setVariable ["ITW_CLASH_Releasing",false];
    _group setVariable ["ITW_CLASH_ReleaseReason",nil];
    _group setVariable ["ITW_CLASH_ReleaseStarted",nil];

    if (_timedOut) then {
        ["release-timeout",[_reason,_id,str _group]] call ITW_CLASH_fnc_Log;
    };
    ["release",[_reason,_id,str _group,count units _group]] call ITW_CLASH_fnc_Log;
    true
};
