#include "defines.hpp"

// C.L.A.S.H. V6 preprocessor bisect chunk 3/8.
// Original ITW_CLASH.sqf lines 668-1009. Diagnostic only; never executed.

ITW_CLASH_fnc_ResetAnchors = {
    params [["_reason","reset"]];
    private _count = 0;
    {
        private _entry = ITW_CLASH_AnchorGroups get _x;
        if (_entry isNotEqualTo []) then {
            private _group = _entry#0;
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_AnchorObjective",nil];
                _group setVariable ["ITW_CLASH_AnchorAssignedAt",nil];
                _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
            };
            _count = _count + 1;
        };
    } forEach +(keys ITW_CLASH_AnchorGroups);

    ITW_CLASH_AnchorGroups = createHashMap;
    ITW_CLASH_AnchorRefills = createHashMap;
    RydHQ_NoAttack = [];
    RydHQ_NoRecon = [];
    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoAttack",[]];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoRecon",[]];
    };
    ITW_CLASH_LastAnchorSignature = "";
    ITW_CLASH_AnchorAuditReadyAt = time + 45;
    ["anchor-reset",[_reason,_count]] call ITW_CLASH_fnc_Log;
    _count
};

ITW_CLASH_fnc_SelectAnchorGroup = {
    params ["_objectiveIndex","_flag","_radius"];
    if (isNull _flag) exitWith {grpNull};

    private _center = [_objectiveIndex,_flag] call ITW_CLASH_fnc_GetObjectiveCenter;
    private _bestStrong = grpNull;
    private _bestStrongScore = 1e10;
    private _bestWeak = grpNull;
    private _bestWeakScore = 1e10;

    {
        private _group = _x;
        if (!isNull _group && {
            _group getVariable ["ITW_CLASH_Managed",false] && {
                !(_group getVariable ["ITW_CLASH_Releasing",false]) && {
                    !([_group] call ITW_CLASH_fnc_IsHALExhausted) && {
                        (_group getVariable ["ITW_CLASH_AssignedObjective",-1]) == _objectiveIndex
                    }
                }
            }
        }) then {
            private _otherAnchor = _group getVariable ["ITW_CLASH_AnchorObjective",-1];
            if (_otherAnchor in [-1,_objectiveIndex]) then {
                private _aliveCount = [units _group] call ITW_CLASH_fnc_CountConscious;
                if (_aliveCount > 0) then {
                    private _insideCount = [
                        units _group,
                        _center,
                        _radius
                    ] call ITW_CLASH_fnc_CountConscious;
                    private _distance = leader _group distance2D _flag;

                    if (_aliveCount >= ITW_CLASH_MinAnchorSoldiers) then {
                        private _score = if (_insideCount >= ITW_CLASH_MinAnchorSoldiers) then {
                            _distance
                        } else {
                            100000 + _distance
                        };
                        if (_score < _bestStrongScore) then {
                            _bestStrongScore = _score;
                            _bestStrong = _group;
                        };
                    } else {
                        private _score = (
                            (ITW_CLASH_MinAnchorSoldiers - _aliveCount) * 100000
                        ) + _distance - (_insideCount * 1000);
                        if (_score < _bestWeakScore) then {
                            _bestWeakScore = _score;
                            _bestWeak = _group;
                        };
                    };
                };
            };
        };
    } forEach +ITW_CLASH_ManagedGroups;

    if (!isNull _bestStrong) exitWith {_bestStrong};
    _bestWeak
};

ITW_CLASH_fnc_OrderAnchor = {
    params ["_group","_objectiveIndex","_flag","_radius"];
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            !ITW_CLASH_HALReady || {
                isNull _group || {isNull _flag}
            }
        }
    }) exitWith {false};
    if (isNil "HAL_GoDef" || {isNil "RYD_Spawn"}) exitWith {
        ["anchor-order-unavailable",[
            _objectiveIndex,
            [_group] call ITW_CLASH_fnc_GroupId
        ]] call ITW_CLASH_fnc_Log;
        false
    };
    if (_group getVariable ["ITW_CLASH_AnchorOrderPending",false]) exitWith {false};

    private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
    private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
    if (_entry isEqualTo [] || {!((_entry#0) isEqualTo _group)}) exitWith {false};

    private _center = [_objectiveIndex,_flag] call ITW_CLASH_fnc_GetObjectiveCenter;
    private _safeRadius = 20 max (_radius - 35);
    private _target = [
        _center,
        10,
        _safeRadius,
        2,
        0,
        0.4,
        0,
        [],
        [_center,_center]
    ] call BIS_fnc_findSafePos;
    if (surfaceIsWater _target) then {
        _target = +_center;
    };

    _entry set [3,time];
    ITW_CLASH_AnchorGroups set [_key,_entry];
    _group setVariable ["ITW_CLASH_AnchorOrderPending",true];
    ["anchor-order-requested",[
        _objectiveIndex,
        _entry#1,
        round (leader _group distance2D _flag),
        _target
    ]] call ITW_CLASH_fnc_Log;

    [_group,_objectiveIndex,_target] spawn {
        params ["_group","_objectiveIndex","_target"];
        if (isNull _group) exitWith {};

        _group setVariable ["Break",true];
        _group setVariable ["Defending",false];
        if (!isNull ITW_CLASH_HALHQ) then {
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_DefSpot",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_DefSpot",[]]) - [_group]
            ];
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_Def",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_Def",[]]) - [_group]
            ];
        };

        sleep 6;
        if (isNull _group || {
            !ITW_CLASH_LiveEnabled || {
                !ITW_CLASH_HALReady || {
                    !(_group getVariable ["ITW_CLASH_Managed",false]) || {
                        (_group getVariable ["ITW_CLASH_AnchorObjective",-1]) != _objectiveIndex
                    }
                }
            }
        }) exitWith {
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
            };
        };

        _group setVariable ["Break",false];
        _group setVariable ["Defending",false];
        private _defSpot = ITW_CLASH_HALHQ getVariable ["RydHQ_DefSpot",[]];
        _defSpot pushBackUnique _group;
        ITW_CLASH_HALHQ setVariable ["RydHQ_DefSpot",_defSpot];

        private _angle = ITW_CLASH_HALHQ getVariable ["RydHQ_Angle",0];
        [[
            _group,
            _target,
            0,
            0,
            false,
            _angle,
            ITW_CLASH_HALHQ
        ],HAL_GoDef] call RYD_Spawn;

        _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
        ["anchor-order-issued",[
            _objectiveIndex,
            [_group] call ITW_CLASH_fnc_GroupId,
            _target
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_RequestAnchorRefill = {
    params ["_objectiveIndex",["_reason","anchor-deficit"],["_deficit",1]];
    if (!isServer || {!ITW_CLASH_LiveEnabled} || {!ITW_CLASH_HALReady}) exitWith {false};

    private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
    private _entry = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
    if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "assigned"}) then {
        private _group = _entry#1;
        if (!isNull _group && {
            ([units _group] call ITW_CLASH_fnc_CountConscious) > 0 && {
                time - (_entry#2) < ITW_CLASH_AnchorRefillGrace
            }
        }) exitWith {false};
        ["anchor-refill-retry",[
            _objectiveIndex,
            if (isNull _group) then {"<null>"} else {
                [_group] call ITW_CLASH_fnc_GroupId
            },
            time - (_entry#2)
        ]] call ITW_CLASH_fnc_Log;
        _entry = [];
    };
    if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "pending"}) exitWith {false};

    ITW_CLASH_AnchorRefills set [
        _key,
        ["pending",grpNull,time,_reason,_deficit]
    ];
    ["anchor-deficit",[
        _objectiveIndex,
        _reason,
        _deficit,
        ITW_CLASH_MinAnchorSoldiers
    ]] call ITW_CLASH_fnc_Log;
    true
};

ITW_CLASH_fnc_NextAnchorRefill = {
    if (!isServer || {!ITW_CLASH_LiveEnabled} || {!ITW_CLASH_HALReady}) exitWith {-1};

    private _nextObjective = -1;
    {
        private _objectiveIndex = _x#0;
        private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
        private _entry = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
        if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "pending"}) exitWith {
            _nextObjective = _objectiveIndex;
        };
    } forEach (call ITW_CLASH_fnc_GetHeldObjectives);
    _nextObjective
};

ITW_CLASH_fnc_AcknowledgeAnchorRefill = {
    params ["_group","_objectiveIndex"];
    if (!isServer || {
        !ITW_CLASH_LiveEnabled || {
            isNull _group || {_objectiveIndex < 0}
        }
    }) exitWith {false};

    private _held = call ITW_CLASH_fnc_GetHeldObjectives;
    if ((_held findIf {(_x#0) == _objectiveIndex}) < 0) exitWith {false};

    private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
    private _entry = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
    if (_entry isEqualTo [] || {!((_entry#0) isEqualTo "pending")}) exitWith {false};

    _group setVariable ["ITW_CLASH_RefillObjective",_objectiveIndex];
    ITW_CLASH_AnchorRefills set [
        _key,
        ["assigned",_group,time,_entry#3,_entry#4]
    ];
    ["anchor-refill-assigned",[
        _objectiveIndex,
        [_group] call ITW_CLASH_fnc_GroupId,
        count units _group
    ]] call ITW_CLASH_fnc_Log;
    true
};


ITW_CLASH_fnc_GetEgressPoint = {
    params ["_group",["_preferredObjective",-1]];
    if (isNull _group || {
        isNil "ITW_Objectives" || {
            isNil "ITW_Zones" || {
                isNil "ITW_ZoneIndex"
            }
        }
    }) exitWith {[]};

    private _leaderPos = getPosATL leader _group;
    private _candidates = [];
    if (ITW_ZoneIndex >= 0 && {
        ITW_ZoneIndex < count ITW_Zones
    }) then {
        {
            if !([_x] call ITW_ObjContestedOwnerIsFriendly) then {
                _candidates pushBackUnique _x;
            };
        } forEach (ITW_Zones#ITW_ZoneIndex);
    };

    private _source = "nearest-active-staging";
    private _selected = -1;
    if (_preferredObjective in _candidates) then {
        _selected = _preferredObjective;
        _source = "objective-staging";
    } else {
        private _bestDistance = 1e10;
        {
            private _position = (ITW_Objectives#_x)#ITW_OBJ_POS;
            private _distance = _leaderPos distance2D _position;
            if (_distance < _bestDistance) then {
                _bestDistance = _distance;
                _selected = _x;
            };
        } forEach _candidates;
    };

    if (_selected < 0 && {
        count ITW_Zones > 0 && {
            (ITW_Zones#-1) isNotEqualTo []
        }
    }) then {
        _selected = ITW_Zones#-1#0;
        _source = "home-staging";
    };
    if (_selected < 0 || {
        _selected >= count ITW_Objectives
    }) exitWith {[]};

    private _objective = ITW_Objectives#_selected;
    private _position = +(_objective#ITW_OBJ_V_SPAWN);
    if (_position isEqualTo []) then {
        _position = +(_objective#ITW_OBJ_POS);
        _source = _source + "-objective-fallback";
    };
    if (count _position < 3) then {
        _position pushBack 0;
    };
    [_position,_selected,_source]
};
