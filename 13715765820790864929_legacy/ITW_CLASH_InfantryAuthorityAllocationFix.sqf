#include "defines.hpp"

if (!isServer) exitWith {false};

ITW_CLASH_InfantryAuthorityAllocationFixVersion = 2;
ITW_CLASH_AllocationDriftMargin = 150;
ITW_CLASH_AllocationDriftCooldown = 0;

/*
    Persistent allocation authority correction.

    Objective allocation is affinity metadata for HAL-managed field infantry.
    The canonical V6 allocation audit used large waypoint drift as a reason to
    release a group from HAL. That contradicts persistent infantry authority and
    also misfires when ITW_CLASH_AssignedObjective is -1 because the canonical
    "no assigned flag" distance sentinel is 1e10.

    This replacement preserves allocation/coverage telemetry but changes the
    mutation:
      - missing/invalid affinity adopts Impasse's live objective when valid,
        otherwise the nearest active objective;
      - genuine defending waypoint drift updates affinity metadata;
      - no allocation drift path calls ReleaseGroup or sets re-eligibility.
*/

if (isNil "ITW_CLASH_fnc_AuditAllocations" || {
    isNil "ITW_CLASH_InfantryAuthority_fnc_IsManagedFielded"
}) exitWith {
    diag_log "CLASH BOOT | FAILED | infantry-allocation-authority-source-missing";
    false
};

ITW_CLASH_InfantryAuthorityAllocationFix_fnc_SetAffinity = {
    params [
        "_group",
        ["_newObjective",-1],
        ["_reason","unspecified"],
        ["_details",[]]
    ];

    if (isNull _group || {_newObjective < 0}) exitWith {false};

    private _oldObjective = _group getVariable [
        "ITW_CLASH_AssignedObjective",
        VAR_GET_OBJ_IDX(_group)
    ];
    if (_oldObjective == _newObjective && {
        VAR_GET_OBJ_IDX(_group) == _newObjective
    }) exitWith {false};

    _group setVariable ["ITW_CLASH_AssignedObjective",_newObjective];
    if (_group getVariable ["ITW_CLASH_DualHALManaged",false]) then {
        _group setVariable ["ITW_CLASH_DualHALObjectiveAffinity",_newObjective];
    };
    VAR_SET_OBJ_IDX(_group,_newObjective);

    if (!isNil "ITW_CLASH_InfantryAuthority_fnc_Log") then {
        ["affinity-updated",[
            [_group] call ITW_CLASH_fnc_GroupId,
            _oldObjective,
            _newObjective,
            _reason,
            _details
        ]] call ITW_CLASH_InfantryAuthority_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_AuditAllocations = {
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            !ITW_CLASH_HALReady || {
                ITW_CLASH_Transitioning
            }
        }
    }) exitWith {[]};

    private _activeObjectives = call ITW_CLASH_fnc_GetActiveObjectives;
    private _activeIndices = _activeObjectives apply {_x#0};
    private _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    private _heldIndices = _heldObjectives apply {_x#0};
    private _allocations = [];
    private _managedGroups = +ITW_CLASH_ManagedGroups;
    if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
        {_managedGroups pushBackUnique _x} forEach +ITW_CLASH_DualHALBLUFORGroups;
    };
    if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
        {_managedGroups pushBackUnique _x} forEach +ITW_CLASH_DualHALOPFORExtraGroups;
    };

    {
        private _group = _x;
        private _managed = !isNull _group && {
            _group getVariable ["ITW_CLASH_Managed",false] || {
                _group getVariable ["ITW_CLASH_DualHALManaged",false]
            }
        };
        if (_managed) then {
            private _id = [_group] call ITW_CLASH_fnc_GroupId;
            private _assignedObjective = if (
                _group getVariable ["ITW_CLASH_DualHALManaged",false]
            ) then {
                _group getVariable [
                    "ITW_CLASH_DualHALObjectiveAffinity",
                    _group getVariable [
                        "ITW_CLASH_AssignedObjective",
                        VAR_GET_OBJ_IDX(_group)
                    ]
                ]
            } else {
                _group getVariable [
                    "ITW_CLASH_AssignedObjective",
                    VAR_GET_OBJ_IDX(_group)
                ]
            };
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

            private _assignedFlag = [_assignedObjective] call ITW_CLASH_fnc_GetObjectiveFlag;
            private _assignedValid = _assignedObjective in _activeIndices && {
                !isNull _assignedFlag
            };
            private _legacyFielded = (
                [_group] call ITW_CLASH_InfantryAuthority_fnc_IsManagedFielded
            );
            private _dualFielded = (
                _group getVariable ["ITW_CLASH_DualHALManaged",false]
            ) && {
                ((units _group) findIf {isPlayer _x}) < 0
            } && {
                isNil "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" || {
                    !([_group] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved)
                }
            };
            private _affinityMutable = (_legacyFielded || {_dualFielded}) && {
                !(_group getVariable ["ITW_CLASH_Withdrawing",false]) && {
                    (_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isEqualTo "" && {
                        (_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isEqualTo ""
                    }
                }
            };

            // Repair the exact field failure seen in the long test: a managed
            // formation with affinity -1 must never fall into the canonical
            // 1e10 sentinel and become a release candidate.
            if (!_assignedValid && {_affinityMutable}) then {
                private _impasseObjective = VAR_GET_OBJ_IDX(_group);
                private _adoptObjective = if (_impasseObjective in _activeIndices) then {
                    _impasseObjective
                } else {
                    _nearestObjective
                };
                if (_adoptObjective >= 0) then {
                    [
                        _group,
                        _adoptObjective,
                        if (_assignedObjective < 0) then {
                            "unassigned-adopted"
                        } else {
                            "invalid-affinity-repaired"
                        },
                        [
                            _impasseObjective,
                            _nearestObjective,
                            round _nearestDistance,
                            _waypointType
                        ]
                    ] call ITW_CLASH_InfantryAuthorityAllocationFix_fnc_SetAffinity;
                    _assignedObjective = _adoptObjective;
                    _assignedFlag = [_assignedObjective] call ITW_CLASH_fnc_GetObjectiveFlag;
                    _assignedValid = !isNull _assignedFlag;
                };
            };

            private _assignedDistance = if (!_assignedValid) then {
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
                private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
                    [_group] call ITW_CLASH_fnc_GetCommanderForGroup
                } else {
                    grpNull
                };
                if (!isNull _hq && {
                    _group in (_hq getVariable ["RydHQ_DefRes",[]])
                }) then {
                    "reserve"
                } else {
                    "main"
                }
            };

            // Waypoint drift changes strategic affinity only. Anchors deliberately
            // retain their objective identity; anchor audit owns their replacement
            // or repositioning if HAL moves them away from the capture point.
            private _drifted = _state isEqualTo "defending" && {
                _hasWaypoint && {
                    _nearestObjective >= 0 && {
                        _nearestObjective != _assignedObjective && {
                            _nearestDistance + ITW_CLASH_AllocationDriftMargin < _assignedDistance
                        }
                    }
                }
            };
            if (_drifted && {_role isNotEqualTo "anchor"} && {_affinityMutable}) then {
                [
                    _group,
                    _nearestObjective,
                    "waypoint-drift",
                    [
                        _assignedObjective,
                        round _assignedDistance,
                        round _nearestDistance,
                        _waypointType
                    ]
                ] call ITW_CLASH_InfantryAuthorityAllocationFix_fnc_SetAffinity;
                _assignedObjective = _nearestObjective;
                _assignedFlag = [_assignedObjective] call ITW_CLASH_fnc_GetObjectiveFlag;
                _assignedDistance = if (isNull _assignedFlag) then {
                    1e10
                } else {
                    _waypointPosition distance2D _assignedFlag
                };
                _role = if (
                    (_group getVariable ["ITW_CLASH_AnchorObjective",-1]) == _assignedObjective
                ) then {
                    "anchor"
                } else {
                    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
                    [_group] call ITW_CLASH_fnc_GetCommanderForGroup
                } else {
                    grpNull
                };
                if (!isNull _hq && {
                    _group in (_hq getVariable ["RydHQ_DefRes",[]])
                }) then {
                    "reserve"
                } else {
                        "main"
                    }
                };
            };

            _allocations pushBack [
                _id,
                _assignedObjective,
                _state,
                _nearestObjective,
                _waypointType,
                round _assignedDistance,
                round _nearestDistance,
                _role
            ];
        };
    } forEach _managedGroups;

    private _coverage = [];
    {
        private _objectiveIndex = _x#0;
        _coverage pushBack [
            _objectiveIndex,
            if (_objectiveIndex in _heldIndices) then {"held"} else {"recovery"},
            {
                !isNull _x && {
                    private _affinity = if (
                        _x getVariable ["ITW_CLASH_DualHALManaged",false]
                    ) then {
                        _x getVariable [
                            "ITW_CLASH_DualHALObjectiveAffinity",
                            _x getVariable ["ITW_CLASH_AssignedObjective",-1]
                        ]
                    } else {
                        _x getVariable ["ITW_CLASH_AssignedObjective",-1]
                    };
                    _affinity == _objectiveIndex
                }
            } count _managedGroups,
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

    _allocations
};

diag_log format [
    "CLASH BOOT | infantry-allocation-authority-ready | version=%1 driftRelease=false unassignedAdoption=true waypointDriftAffinity=true anchorAffinityStable=true dualHAL=true",
    ITW_CLASH_InfantryAuthorityAllocationFixVersion
];

true
