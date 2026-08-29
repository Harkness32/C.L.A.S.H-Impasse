#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_CommanderParityStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_CommanderParityReady",false]
};

ITW_CLASH_CommanderParityStarted = true;
ITW_CLASH_CommanderParityReady = false;
ITW_CLASH_CommanderParityVersion = 1;
ITW_CLASH_CommanderParity_AnchorReady = false;

/*
    C.L.A.S.H. Commander Parity

    Single authority layer for doctrine that cannot be made naturally symmetric
    inside the shared source because HAL exposes Commander A and Commander B
    through separate global projections.

    Rule:
      - shared behavior belongs in the shared behavior file;
      - unavoidable A/B adaptation belongs here;
      - never create behavior-specific BLUFOR patch files;
      - player groups are the intentional exclusion where AI-only doctrine is
        being mirrored.

    Current parity sections:
      1. Objective anchors / six-man point defense for Commander B.

    Future parity corrections must extend this file rather than introducing
    GTFO_BlueforFix, Recon_BlueforFix, Anchor_BlueforFix, etc.
*/

ITW_CLASH_CommanderParity_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["commander-parity-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH COMMANDER PARITY | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_CommanderParity_fnc_IsPlayerGroup = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    ((units _group) findIf {isPlayer _x}) >= 0
};

ITW_CLASH_CommanderParity_fnc_GetCommanderForSide = {
    params ["_side"];
    private _hq = grpNull;
    if (!isNil "ITW_CLASH_fnc_GetCommanderForSide") then {
        _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;
    };
    if (isNull _hq && {!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}}) then {
        _hq = missionNamespace getVariable ["ITW_CLASH_BLUFORHQ",grpNull];
    };
    if (isNull _hq && {!isNil "ITW_EnemySide" && {_side == ITW_EnemySide}}) then {
        _hq = missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull];
    };
    _hq
};

ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup = {
    params ["_group"];
    if (isNull _group) exitWith {grpNull};
    [side _group] call ITW_CLASH_CommanderParity_fnc_GetCommanderForSide
};

ITW_CLASH_CommanderParity_fnc_GlobalPrefixForSide = {
    params ["_side"];
    if (!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}) exitWith {"RydHQB_"};
    if (!isNil "ITW_EnemySide" && {_side == ITW_EnemySide}) exitWith {"RydHQ_"};
    ""
};
ITW_CLASH_CommanderParity_AnchorGroups = createHashMap;
ITW_CLASH_CommanderParity_AnchorRefills = createHashMap;
ITW_CLASH_CommanderParity_AnchorPreviousConstraints = [];
ITW_CLASH_CommanderParity_AnchorLastSignature = "";

ITW_CLASH_CommanderParity_Anchor_fnc_Log = {
    params ["_event",["_payload",[]]];
    ["anchor-" + _event,_payload] call ITW_CLASH_CommanderParity_fnc_Log;
};

ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives = {
    if (
        isNil "ITW_PlayerSide"
        || {isNil "ITW_ObjContestedOwnerIsFriendly"}
        || {isNil "ITW_CLASH_fnc_GetActiveObjectives"}
    ) exitWith {[]};

    (call ITW_CLASH_fnc_GetActiveObjectives) select {
        [_x#0] call ITW_ObjContestedOwnerIsFriendly
    }
};

ITW_CLASH_CommanderParity_Anchor_fnc_IsEligible = {
    params ["_group","_objectiveIndex"];
    if (isNull _group || {isNil "ITW_PlayerSide"}) exitWith {false};
    if (side _group != ITW_PlayerSide) exitWith {false};
    if !(_group getVariable ["ITW_CLASH_DualHALManaged",false]) exitWith {false};
    if ([_group] call ITW_CLASH_CommanderParity_fnc_IsPlayerGroup) exitWith {false};
    if (_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {false};
    if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") exitWith {false};
    if ((_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" && {
        [_group] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved
    }) exitWith {false};
    if (!isNil "ITW_CLASH_SOF_fnc_IsSOF" && {
        [_group] call ITW_CLASH_SOF_fnc_IsSOF
    }) exitWith {false};
    if (!isNil "ITW_CLASH_fnc_IsHALExhausted" && {
        [_group] call ITW_CLASH_fnc_IsHALExhausted
    }) exitWith {false};

    private _alive = (units _group) select {alive _x};
    if (_alive isEqualTo []) exitWith {false};
    // Point anchors are infantry formations, never vehicle crews.
    if ((_alive findIf {vehicle _x != _x}) >= 0) exitWith {false};
    if ((_alive findIf {!(_x isKindOf "CAManBase")}) >= 0) exitWith {false};

    private _affinity = _group getVariable [
        "ITW_CLASH_DualHALObjectiveAffinity",
        _group getVariable [
            "ITW_CLASH_AssignedObjective",
            VAR_GET_OBJ_IDX(_group)
        ]
    ];
    if (_affinity != _objectiveIndex) exitWith {false};

    private _otherAnchor = _group getVariable ["ITW_CLASH_AnchorObjective",-1];
    _otherAnchor in [-1,_objectiveIndex]
};

ITW_CLASH_CommanderParity_Anchor_fnc_Select = {
    params ["_objectiveIndex","_flag","_radius"];
    if (isNull _flag) exitWith {grpNull};

    private _groups = missionNamespace getVariable [
        "ITW_CLASH_DualHALBLUFORGroups",[]
    ];
    private _center = [
        _objectiveIndex,_flag
    ] call ITW_CLASH_fnc_GetObjectiveCenter;
    private _bestStrong = grpNull;
    private _bestStrongScore = 1e10;
    private _bestWeak = grpNull;
    private _bestWeakScore = 1e10;
    private _minimum = missionNamespace getVariable [
        "ITW_CLASH_MinAnchorSoldiers",6
    ];

    {
        private _group = _x;
        if !([_group,_objectiveIndex] call ITW_CLASH_CommanderParity_Anchor_fnc_IsEligible) then {
            continue
        };

        private _aliveCount = [
            units _group
        ] call ITW_CLASH_fnc_CountConscious;
        if (_aliveCount <= 0) then {continue};

        private _insideCount = [
            units _group,_center,_radius
        ] call ITW_CLASH_fnc_CountConscious;
        private _distance = leader _group distance2D _flag;

        if (_aliveCount >= _minimum) then {
            private _score = if (_insideCount >= _minimum) then {
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
                (_minimum - _aliveCount) * 100000
            ) + _distance - (_insideCount * 1000);
            if (_score < _bestWeakScore) then {
                _bestWeakScore = _score;
                _bestWeak = _group;
            };
        };
    } forEach +_groups;

    if (!isNull _bestStrong) exitWith {_bestStrong};
    _bestWeak
};

ITW_CLASH_CommanderParity_Anchor_fnc_Clear = {
    params ["_objectiveIndex",["_reason","cleared"]];
    private _key = str _objectiveIndex;
    private _entry = ITW_CLASH_CommanderParity_AnchorGroups getOrDefault [_key,[]];

    if (_entry isNotEqualTo []) then {
        private _group = _entry#0;
        if (!isNull _group) then {
            if (
                (_group getVariable ["ITW_CLASH_AnchorObjective",-1])
                == _objectiveIndex
            ) then {
                _group setVariable ["ITW_CLASH_AnchorObjective",nil];
            };
            _group setVariable ["ITW_CLASH_CommanderParity_AnchorObjective",nil];
            _group setVariable ["ITW_CLASH_CommanderParity_AnchorAssignedAt",nil];
            _group setVariable ["ITW_CLASH_CommanderParity_AnchorOrderPending",nil];
            _group setVariable ["Defending",false];
            _group setVariable ["Break",false];

            if (!isNil "RYD_WPdel") then {
                [_group] call RYD_WPdel;
            } else {
                {deleteWaypoint _x} forEachReversed waypoints _group;
            };
        };

        ["vacant",[
            _objectiveIndex,
            if (isNull _group) then {"<null>"} else {
                [_group] call ITW_CLASH_fnc_GroupId
            },
            _reason
        ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;
    };

    ITW_CLASH_CommanderParity_AnchorGroups deleteAt _key;
    true
};

ITW_CLASH_CommanderParity_Anchor_fnc_ApplyConstraints = {
    if (isNil "ITW_PlayerSide") exitWith {false};

    private _hq = [ITW_PlayerSide] call
        ITW_CLASH_CommanderParity_fnc_GetCommanderForSide;
    if (isNull _hq) exitWith {false};

    private _anchors = [];
    {
        private _entry = ITW_CLASH_CommanderParity_AnchorGroups getOrDefault [_x,[]];
        if (_entry isNotEqualTo []) then {
            private _group = _entry#0;
            if (!isNull _group) then {_anchors pushBackUnique _group};
        };
    } forEach +(keys ITW_CLASH_CommanderParity_AnchorGroups);

    private _previous = +ITW_CLASH_CommanderParity_AnchorPreviousConstraints;
    private _noAttack = +(_hq getVariable ["RydHQ_NoAttack",[]]);
    private _noRecon = +(_hq getVariable ["RydHQ_NoRecon",[]]);
    _noAttack = _noAttack - _previous;
    _noRecon = _noRecon - _previous;
    {_noAttack pushBackUnique _x} forEach _anchors;
    {_noRecon pushBackUnique _x} forEach _anchors;

    _hq setVariable ["RydHQ_NoAttack",_noAttack];
    _hq setVariable ["RydHQ_NoRecon",_noRecon];
    RydHQB_NoAttack = +_noAttack;
    RydHQB_NoRecon = +_noRecon;
    ITW_CLASH_CommanderParity_AnchorPreviousConstraints = +_anchors;
    true
};

ITW_CLASH_CommanderParity_Anchor_fnc_Order = {
    params ["_group","_objectiveIndex","_flag","_radius"];
    if (
        isNull _group || {isNull _flag}
        || {isNil "HAL_GoDef"} || {isNil "RYD_Spawn"}
    ) exitWith {false};
    if (_group getVariable ["ITW_CLASH_CommanderParity_AnchorOrderPending",false]) exitWith {
        false
    };

    private _key = str _objectiveIndex;
    private _entry = ITW_CLASH_CommanderParity_AnchorGroups getOrDefault [_key,[]];
    if (_entry isEqualTo [] || {!((_entry#0) isEqualTo _group)}) exitWith {
        false
    };

    private _hq = [_group] call
        ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup;
    if (isNull _hq) exitWith {false};

    private _center = [
        _objectiveIndex,_flag
    ] call ITW_CLASH_fnc_GetObjectiveCenter;
    private _safeRadius = 20 max (_radius - 35);
    private _target = [
        _center,10,_safeRadius,2,0,0.4,0,[],[_center,_center]
    ] call BIS_fnc_findSafePos;
    if (_target isEqualTo [] || {surfaceIsWater _target}) then {
        _target = +_center;
    };

    _entry set [3,time];
    ITW_CLASH_CommanderParity_AnchorGroups set [_key,_entry];
    _group setVariable ["ITW_CLASH_CommanderParity_AnchorOrderPending",true];

    ["order-requested",[
        _objectiveIndex,_entry#1,
        round (leader _group distance2D _flag),_target
    ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;

    [_group,_objectiveIndex,_target,_hq] spawn {
        params ["_group","_objectiveIndex","_target","_hq"];
        if (isNull _group || {isNull _hq}) exitWith {};

        _group setVariable ["Break",true];
        _group setVariable ["Defending",false];
        {
            _hq setVariable [
                _x,(_hq getVariable [_x,[]]) - [_group]
            ];
        } forEach ["RydHQ_DefSpot","RydHQ_Def"];

        sleep 6;
        if (
            isNull _group || {isNull _hq}
            || {!(_group getVariable ["ITW_CLASH_DualHALManaged",false])}
            || {
                (_group getVariable [
                    "ITW_CLASH_CommanderParity_AnchorObjective",-1
                ]) != _objectiveIndex
            }
            || {[_group] call ITW_CLASH_fnc_IsHALExhausted}
        ) exitWith {
            if (!isNull _group) then {
                _group setVariable [
                    "ITW_CLASH_CommanderParity_AnchorOrderPending",nil
                ];
            };
        };

        _group setVariable ["Break",false];
        _group setVariable ["Defending",false];

        private _defSpot = +(_hq getVariable ["RydHQ_DefSpot",[]]);
        _defSpot pushBackUnique _group;
        _hq setVariable ["RydHQ_DefSpot",_defSpot];

        private _angle = _hq getVariable ["RydHQ_Angle",0];
        [[
            _group,_target,0,0,false,_angle,_hq
        ],HAL_GoDef] call RYD_Spawn;

        _group setVariable ["ITW_CLASH_CommanderParity_AnchorOrderPending",nil];
        ["order-issued",[
            _objectiveIndex,
            [_group] call ITW_CLASH_fnc_GroupId,
            _target
        ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;
    };
    true
};

ITW_CLASH_CommanderParity_Anchor_fnc_RequestRefill = {
    params ["_objectiveIndex",["_reason","anchor-deficit"],["_deficit",1]];
    private _key = str _objectiveIndex;
    private _entry = ITW_CLASH_CommanderParity_AnchorRefills getOrDefault [_key,[]];
    private _grace = missionNamespace getVariable [
        "ITW_CLASH_AnchorRefillGrace",120
    ];

    if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "assigned"}) then {
        private _group = _entry#1;
        if (
            !isNull _group
            && {([units _group] call ITW_CLASH_fnc_CountConscious) > 0}
            && {time - (_entry#2) < _grace}
        ) exitWith {false};

        ["refill-retry",[
            _objectiveIndex,
            if (isNull _group) then {"<null>"} else {
                [_group] call ITW_CLASH_fnc_GroupId
            },
            time - (_entry#2)
        ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;
        _entry = [];
    };
    if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "pending"}) exitWith {
        false
    };

    ITW_CLASH_CommanderParity_AnchorRefills set [
        _key,["pending",grpNull,time,_reason,_deficit]
    ];
    ["deficit",[
        _objectiveIndex,_reason,_deficit,
        missionNamespace getVariable ["ITW_CLASH_MinAnchorSoldiers",6]
    ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;
    true
};

ITW_CLASH_CommanderParity_Anchor_fnc_NextRefill = {
    if (!isServer || {isNil "ITW_PlayerSide"}) exitWith {-1};
    private _nextObjective = -1;
    {
        private _objectiveIndex = _x#0;
        private _entry = ITW_CLASH_CommanderParity_AnchorRefills getOrDefault [
            str _objectiveIndex,[]
        ];
        if (_entry isNotEqualTo [] && {(_entry#0) isEqualTo "pending"}) exitWith {
            _nextObjective = _objectiveIndex;
        };
    } forEach (call ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives);
    _nextObjective
};

ITW_CLASH_CommanderParity_Anchor_fnc_AcknowledgeRefill = {
    params ["_group","_objectiveIndex"];
    if (isNull _group || {_objectiveIndex < 0}) exitWith {false};
    if (((units _group) findIf {isPlayer _x}) >= 0) exitWith {false};

    private _held = call ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives;
    if ((_held findIf {(_x#0) == _objectiveIndex}) < 0) exitWith {false};

    private _key = str _objectiveIndex;
    private _entry = ITW_CLASH_CommanderParity_AnchorRefills getOrDefault [_key,[]];
    if (_entry isEqualTo [] || {!((_entry#0) isEqualTo "pending")}) exitWith {
        false
    };

    _group setVariable [
        "ITW_CLASH_CommanderParity_AnchorRefillObjective",_objectiveIndex
    ];
    _group setVariable [
        "ITW_CLASH_DualHALObjectiveAffinity",_objectiveIndex
    ];
    _group setVariable ["ITW_CLASH_AssignedObjective",_objectiveIndex];
    VAR_SET_OBJ_IDX(_group,_objectiveIndex);
    ITW_CLASH_CommanderParity_AnchorRefills set [
        _key,["assigned",_group,time,_entry#3,_entry#4]
    ];

    ["refill-assigned",[
        _objectiveIndex,
        [_group] call ITW_CLASH_fnc_GroupId,
        count units _group
    ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;
    true
};

ITW_CLASH_CommanderParity_Anchor_fnc_ApplyCommanderDoctrine = {
    if (isNil "ITW_PlayerSide") exitWith {false};
    private _hq = [ITW_PlayerSide] call
        ITW_CLASH_CommanderParity_fnc_GetCommanderForSide;
    if (isNull _hq) exitWith {false};

    private _active = call ITW_CLASH_fnc_GetActiveObjectives;
    private _held = call ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives;
    private _order = if ((count _held) < (count _active)) then {
        "ATTACK"
    } else {
        "DEFEND"
    };

    RydHQB_Order = _order;
    _hq setVariable ["RydHQ_Order",_order];
    _hq setVariable ["RydHQ_Berserk",false];
    _hq setVariable ["RydHQ_AttackAlways",false];
    _hq setVariable ["RydHQ_IdleDef",true];
    _hq setVariable ["RydHQ_DefendObjectives",1];
    _hq setVariable [
        "RydHQ_CRDefRes",
        missionNamespace getVariable ["ITW_CLASH_ReserveRatio",0.20]
    ];
    true
};

ITW_CLASH_CommanderParity_Anchor_fnc_Audit = {
    if (
        !isServer
        || {isNil "ITW_PlayerSide"}
        || {!(missionNamespace getVariable ["ITW_CLASH_DualHALReady",false])}
    ) exitWith {[]};

    private _held = call ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives;
    private _heldKeys = _held apply {str (_x#0)};
    private _minimum = missionNamespace getVariable [
        "ITW_CLASH_MinAnchorSoldiers",6
    ];
    private _auditGrace = missionNamespace getVariable [
        "ITW_CLASH_AnchorAuditGrace",75
    ];
    private _orderCooldown = missionNamespace getVariable [
        "ITW_CLASH_AnchorOrderCooldown",60
    ];

    {
        if !(_x in _heldKeys) then {
            [parseNumber _x,"objective-not-held"] call
                ITW_CLASH_CommanderParity_Anchor_fnc_Clear;
        };
    } forEach +(keys ITW_CLASH_CommanderParity_AnchorGroups);
    {
        if !(_x in _heldKeys) then {
            ITW_CLASH_CommanderParity_AnchorRefills deleteAt _x;
        };
    } forEach +(keys ITW_CLASH_CommanderParity_AnchorRefills);

    private _coverage = [];
    {
        _x params ["_objectiveIndex","_flag"];
        private _key = str _objectiveIndex;
        private _radius = [
            _objectiveIndex
        ] call ITW_CLASH_fnc_GetObjectiveRadius;
        private _center = [
            _objectiveIndex,_flag
        ] call ITW_CLASH_fnc_GetObjectiveCenter;
        private _entry = ITW_CLASH_CommanderParity_AnchorGroups getOrDefault [_key,[]];
        private _anchor = if (_entry isEqualTo []) then {
            grpNull
        } else {
            _entry#0
        };

        private _valid = !isNull _anchor && {
            [_anchor,_objectiveIndex] call
                ITW_CLASH_CommanderParity_Anchor_fnc_IsEligible
        };
        if (!_valid && {_entry isNotEqualTo []}) then {
            [_objectiveIndex,"dead-or-ineligible"] call
                ITW_CLASH_CommanderParity_Anchor_fnc_Clear;
            _entry = [];
            _anchor = grpNull;
        };

        private _alive = if (isNull _anchor) then {0} else {
            [units _anchor] call ITW_CLASH_fnc_CountConscious
        };
        private _inside = if (isNull _anchor) then {0} else {
            [units _anchor,_center,_radius] call
                ITW_CLASH_fnc_CountConscious
        };

        if (
            isNull _anchor || {
                _alive < _minimum || {_inside < _minimum}
            }
        ) then {
            private _candidate = [
                _objectiveIndex,_flag,_radius
            ] call ITW_CLASH_CommanderParity_Anchor_fnc_Select;
            private _candidateAlive = if (isNull _candidate) then {
                0
            } else {
                [units _candidate] call ITW_CLASH_fnc_CountConscious
            };
            private _candidateInside = if (isNull _candidate) then {
                0
            } else {
                [units _candidate,_center,_radius] call
                    ITW_CLASH_fnc_CountConscious
            };

            if (
                !isNull _candidate
                && {!(_candidate isEqualTo _anchor)}
                && {
                    isNull _anchor || {
                        _candidateAlive >= _minimum
                        && {
                            _alive < _minimum || {
                                _candidateInside >= _minimum
                                && {_inside < _minimum}
                            }
                        }
                    }
                }
            ) then {
                if (!isNull _anchor) then {
                    [_objectiveIndex,"promoted-replacement"] call
                        ITW_CLASH_CommanderParity_Anchor_fnc_Clear;
                };

                private _id = [
                    _candidate
                ] call ITW_CLASH_fnc_GroupId;
                _candidate setVariable [
                    "ITW_CLASH_AnchorObjective",_objectiveIndex
                ];
                _candidate setVariable [
                    "ITW_CLASH_CommanderParity_AnchorObjective",_objectiveIndex
                ];
                _candidate setVariable [
                    "ITW_CLASH_CommanderParity_AnchorAssignedAt",time
                ];
                ITW_CLASH_CommanderParity_AnchorGroups set [
                    _key,[_candidate,_id,time,-1000]
                ];
                ["promoted",[
                    _objectiveIndex,_id,_candidateAlive,
                    _candidateInside,
                    round (leader _candidate distance2D _flag)
                ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;

                _entry = ITW_CLASH_CommanderParity_AnchorGroups get _key;
                _anchor = _candidate;
                _alive = _candidateAlive;
                _inside = _candidateInside;
            };
        };

        if (!isNull _anchor && {_inside < _minimum}) then {
            private _lastOrder = _entry#3;
            if (time - _lastOrder >= _orderCooldown) then {
                [
                    _anchor,_objectiveIndex,_flag,_radius
                ] call ITW_CLASH_CommanderParity_Anchor_fnc_Order;
                _entry = ITW_CLASH_CommanderParity_AnchorGroups getOrDefault [
                    _key,_entry
                ];
            };
        };

        private _state = if (_inside >= _minimum) then {
            "COVERED"
        } else {
            if (isNull _anchor) then {
                "VACANT"
            } else {
                if (_alive < _minimum) then {
                    "DEGRADED"
                } else {
                    "MOVING"
                }
            }
        };

        if (_state isEqualTo "COVERED") then {
            if (
                ITW_CLASH_CommanderParity_AnchorRefills getOrDefault [_key,[]]
                isNotEqualTo []
            ) then {
                ITW_CLASH_CommanderParity_AnchorRefills deleteAt _key;
                ["refill-satisfied",[
                    _objectiveIndex,_inside
                ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;
            };
        } else {
            private _assignedAt = if (_entry isEqualTo []) then {
                0
            } else {
                _entry#2
            };
            if (
                isNull _anchor
                || {_alive < _minimum}
                || {time - _assignedAt >= _auditGrace}
            ) then {
                [
                    _objectiveIndex,
                    toLowerANSI _state,
                    _minimum - _inside
                ] call ITW_CLASH_CommanderParity_Anchor_fnc_RequestRefill;
            };
        };

        private _refill = ITW_CLASH_CommanderParity_AnchorRefills getOrDefault [
            _key,[]
        ];
        _coverage pushBack [
            _objectiveIndex,
            if (_entry isEqualTo []) then {"<none>"} else {_entry#1},
            _alive,_inside,_state,
            if (_refill isEqualTo []) then {"none"} else {_refill#0}
        ];
    } forEach _held;

    call ITW_CLASH_CommanderParity_Anchor_fnc_ApplyConstraints;
    call ITW_CLASH_CommanderParity_Anchor_fnc_ApplyCommanderDoctrine;

    private _signature = str [
        missionNamespace getVariable ["ITW_ZoneIndex",-1],
        _coverage
    ];
    if (_signature != ITW_CLASH_CommanderParity_AnchorLastSignature) then {
        ITW_CLASH_CommanderParity_AnchorLastSignature = _signature;
        ["coverage",[
            missionNamespace getVariable ["ITW_ZoneIndex",-1],
            _coverage
        ]] call ITW_CLASH_CommanderParity_Anchor_fnc_Log;
    };
    _coverage
};

[] spawn {
    scriptName "ITW_CLASH_CommanderParity";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.25;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]
            && {!isNil "ITW_PlayerSide"}
            && {!isNil "HAL_GoDef"}
            && {!isNil "RYD_Spawn"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | commander-parity-timeout | native HAL defense retained";
    };

    ITW_CLASH_CommanderParity_AnchorReady = true;
    ITW_CLASH_CommanderParityReady = true;
    diag_log format [
        "CLASH BOOT | commander-parity-ready | version=%1 sections=anchor minimum=%2 playerExcluded=true sofExcluded=true refill=impasse-friendly nativeHALDefense=true",
        ITW_CLASH_CommanderParityVersion,
        missionNamespace getVariable ["ITW_CLASH_MinAnchorSoldiers",6]
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        call ITW_CLASH_CommanderParity_Anchor_fnc_Audit;
        sleep 2;
    };
};

true
