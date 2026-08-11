#include "defines.hpp"

// C.L.A.S.H. V6 preprocessor bisect chunk 5/8.
// Original ITW_CLASH.sqf lines 1361-1596. Diagnostic only; never executed.

ITW_CLASH_fnc_CancelWithdrawals = {
    params [["_reason","cancelled"]];
    private _count = 0;
    {
        private _entry = ITW_CLASH_Withdrawals getOrDefault [_x,[]];
        if (_entry isNotEqualTo []) then {
            private _group = _entry#0;
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_Withdrawing",nil];
                _group setVariable ["ITW_CLASH_WithdrawalDestination",nil];
                _group setVariable ["RydHQ_MIA",nil];
                _group setVariable ["Break",false];
                _group enableAttack true;
                VAR_SET_OBJ_IDX(_group,_entry#1);
                [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
                _count = _count + 1;
            };
        };
    } forEach +(keys ITW_CLASH_Withdrawals);
    ITW_CLASH_Withdrawals = createHashMap;
    ITW_CLASH_LastWithdrawalSignature = "";
    ["withdrawal-cancelled",[_reason,_count]] call ITW_CLASH_fnc_Log;
    _count
};

ITW_CLASH_fnc_AuditAnchors = {
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            !ITW_CLASH_HALReady || {
                ITW_CLASH_Transitioning || {
                    time < ITW_CLASH_AnchorAuditReadyAt || {
                        time < ITW_CLASH_RegistrationFrozenUntil
                    }
                }
            }
        }
    }) exitWith {[]};

    private _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    private _heldKeys = _heldObjectives apply {
        [_x#0] call ITW_CLASH_fnc_AnchorKey
    };

    {
        if !(_x in _heldKeys) then {
            private _objectiveIndex = parseNumber _x;
            [_objectiveIndex,"objective-not-held"] call ITW_CLASH_fnc_ClearAnchorSlot;
        };
    } forEach +(keys ITW_CLASH_AnchorGroups);
    {
        if !(_x in _heldKeys) then {
            ITW_CLASH_AnchorRefills deleteAt _x;
        };
    } forEach +(keys ITW_CLASH_AnchorRefills);

    private _coverage = [];
    private _enemyCoverageUnits = (units ITW_EnemySide) select {
        !([group _x] call ITW_CLASH_fnc_IsCommanderGroup)
    };
    {
        _x params ["_objectiveIndex","_flag"];
        private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
        private _radius = [_objectiveIndex] call ITW_CLASH_fnc_GetObjectiveRadius;
        private _center = [_objectiveIndex,_flag] call ITW_CLASH_fnc_GetObjectiveCenter;
        private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
        private _anchor = if (_entry isEqualTo []) then {grpNull} else {_entry#0};

        private _anchorValid = !isNull _anchor && {
            _anchor getVariable ["ITW_CLASH_Managed",false] && {
                !(_anchor getVariable ["ITW_CLASH_Releasing",false]) && {
                    (_anchor getVariable ["ITW_CLASH_AssignedObjective",-1]) == _objectiveIndex && {
                        !([_anchor] call ITW_CLASH_fnc_IsHALExhausted) && {
                            ([units _anchor] call ITW_CLASH_fnc_CountConscious) > 0
                        }
                    }
                }
            }
        };
        if (!_anchorValid && {_entry isNotEqualTo []}) then {
            [_objectiveIndex,"dead-or-ineligible"] call ITW_CLASH_fnc_ClearAnchorSlot;
            _entry = [];
            _anchor = grpNull;
        };

        private _anchorAlive = if (isNull _anchor) then {0} else {
            [units _anchor] call ITW_CLASH_fnc_CountConscious
        };
        private _anchorInside = if (isNull _anchor) then {0} else {
            [units _anchor,_center,_radius] call ITW_CLASH_fnc_CountConscious
        };

        if (isNull _anchor || {
            _anchorAlive < ITW_CLASH_MinAnchorSoldiers || {
                _anchorInside < ITW_CLASH_MinAnchorSoldiers
            }
        }) then {
            private _candidate = [
                _objectiveIndex,
                _flag,
                _radius
            ] call ITW_CLASH_fnc_SelectAnchorGroup;
            private _candidateAlive = if (isNull _candidate) then {0} else {
                [units _candidate] call ITW_CLASH_fnc_CountConscious
            };
            private _candidateInside = if (isNull _candidate) then {0} else {
                [units _candidate,_center,_radius] call ITW_CLASH_fnc_CountConscious
            };

            if (!isNull _candidate && {
                !(_candidate isEqualTo _anchor) && {
                    isNull _anchor || {
                        _candidateAlive >= ITW_CLASH_MinAnchorSoldiers && {
                            _anchorAlive < ITW_CLASH_MinAnchorSoldiers || {
                                _candidateInside >= ITW_CLASH_MinAnchorSoldiers && {
                                    _anchorInside < ITW_CLASH_MinAnchorSoldiers
                                }
                            }
                        }
                    }
                }
            }) then {
                if (!isNull _anchor) then {
                    [_objectiveIndex,"promoted-replacement"] call ITW_CLASH_fnc_ClearAnchorSlot;
                };

                private _id = [_candidate] call ITW_CLASH_fnc_GroupId;
                _candidate setVariable ["ITW_CLASH_AnchorObjective",_objectiveIndex];
                _candidate setVariable ["ITW_CLASH_AnchorAssignedAt",time];
                ITW_CLASH_AnchorGroups set [
                    _key,
                    [_candidate,_id,time,-1000]
                ];
                ["anchor-promoted",[
                    _objectiveIndex,
                    _id,
                    _candidateAlive,
                    _candidateInside,
                    round (leader _candidate distance2D _flag)
                ]] call ITW_CLASH_fnc_Log;

                _entry = ITW_CLASH_AnchorGroups get _key;
                _anchor = _candidate;
                _anchorAlive = _candidateAlive;
                _anchorInside = _candidateInside;
            };
        };

        if (!isNull _anchor && {
            _anchorInside < ITW_CLASH_MinAnchorSoldiers
        }) then {
            private _lastOrder = _entry#3;
            if (time - _lastOrder >= ITW_CLASH_AnchorOrderCooldown) then {
                [
                    _anchor,
                    _objectiveIndex,
                    _flag,
                    _radius
                ] call ITW_CLASH_fnc_OrderAnchor;
                _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,_entry];
            };
        };

        private _totalEnemyInside = [
            _enemyCoverageUnits,
            _center,
            _radius
        ] call ITW_CLASH_fnc_CountConscious;
        private _state = "UNCOVERED";

        if (_anchorInside >= ITW_CLASH_MinAnchorSoldiers) then {
            _state = "COVERED";
        } else {
            if (isNull _anchor) then {
                _state = "VACANT";
            } else {
                if (_anchorAlive < ITW_CLASH_MinAnchorSoldiers) then {
                    _state = "DEGRADED";
                } else {
                    _state = "MOVING";
                };
            };
        };

        if (_state isEqualTo "COVERED") then {
            private _refill = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
            if (_refill isNotEqualTo []) then {
                ITW_CLASH_AnchorRefills deleteAt _key;
                ["anchor-refill-satisfied",[
                    _objectiveIndex,
                    _state,
                    _anchorInside,
                    _totalEnemyInside
                ]] call ITW_CLASH_fnc_Log;
            };
        } else {
            private _assignedAt = if (_entry isEqualTo []) then {0} else {_entry#2};
            if (isNull _anchor || {
                _anchorAlive < ITW_CLASH_MinAnchorSoldiers || {
                    time - _assignedAt >= ITW_CLASH_AnchorAuditGrace
                }
            }) then {
                [
                    _objectiveIndex,
                    toLowerANSI _state,
                    ITW_CLASH_MinAnchorSoldiers - _anchorInside
                ] call ITW_CLASH_fnc_RequestAnchorRefill;
            };
        };

        private _refill = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
        private _refillState = if (_refill isEqualTo []) then {"none"} else {_refill#0};
        _coverage pushBack [
            _objectiveIndex,
            round _radius,
            if (_entry isEqualTo []) then {"<none>"} else {_entry#1},
            _anchorAlive,
            _anchorInside,
            _totalEnemyInside,
            _state,
            _refillState
        ];
    } forEach _heldObjectives;

    private _signature = str [
        ITW_ZoneIndex,
        _coverage apply {
            [_x#0,_x#2,_x#3,_x#4,_x#5,_x#6,_x#7]
        }
    ];
    if (_signature != ITW_CLASH_LastAnchorSignature) then {
        ITW_CLASH_LastAnchorSignature = _signature;
        ["anchor-coverage",[ITW_ZoneIndex,_coverage]] call ITW_CLASH_fnc_Log;
    };
    _coverage
};
