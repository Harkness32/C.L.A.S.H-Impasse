#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALNativeSFFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALNativeSFFixReady",false]
};

ITW_CLASH_HALNativeSFFixStarted = true;
ITW_CLASH_HALNativeSFFixReady = false;
ITW_CLASH_HALNativeSFFixFinished = false;
ITW_CLASH_HALNativeSFFixVersion = 3;
ITW_CLASH_SFStandbyMinRadius = 90;
ITW_CLASH_SFStandbyMaxRadius = 220;
scriptName "ITW_CLASH_HALNativeSFFix";

private _finishFailure = {
    params ["_reason",["_details",[]]];
    ITW_CLASH_HALNativeSFFixReady = false;
    ITW_CLASH_HALNativeSFFixFinished = true;
    diag_log format [
        "CLASH BOOT | WARNING | native-sf-fix-failed | reason=%1 details=%2",
        _reason,
        _details
    ];
    false
};

// HAL_GoSFAttack/HAL_SFIdleOrd are assigned by NR6 VarInit from readable addon
// SQF. Keep native GoSFAttack as the tactical direct-action executor and repair
// only its verified source defects. C.L.A.S.H. deliberately replaces the native
// idle "Guard HQ" order with support-corridor standby/security doctrine.
private _deadline = diag_tickTime + 120;
waitUntil {
    sleep 0.05;
    (
        !isNil "RYD_Path" && {
            !isNil "HAL_GoSFAttack" && {
                !isNil "HAL_SFIdleOrd"
            }
        }
    ) || {diag_tickTime >= _deadline}
};

if (isNil "RYD_Path" || {isNil "HAL_GoSFAttack" || {isNil "HAL_SFIdleOrd"}}) exitWith {
    ["hal-runtime-bind-timeout",[]] call _finishFailure
};

private _idlePath = RYD_Path + "HAL\SFIdleOrd.sqf";
private _attackPath = RYD_Path + "HAL\GoSFAttack.sqf";
private _idleSource = preprocessFileLineNumbers _idlePath;
private _attackSource = preprocessFileLineNumbers _attackPath;

if (_idleSource isEqualTo "" || {_attackSource isEqualTo ""}) exitWith {
    ["native-source-missing",[_idlePath,_attackPath,count _idleSource,count _attackSource]] call _finishFailure
};

// Refuse to silently replace an unknown upstream idle routine. We are changing
// doctrine here, not papering over arbitrary source revisions.
if ((_idleSource find "Guard HQ.") < 0 || {
    (_idleSource find "RydHQ_SpecForG") < 0 || {
        (_idleSource find '"HOLD","AWARE","RED","NORMAL"') < 0
    }
}) exitWith {
    ["SFIdleOrd-signature-missing",[count _idleSource]] call _finishFailure
};

private _replaceExact = {
    params ["_source","_bad","_good","_label"];

    private _badAt = _source find _bad;
    private _goodAt = _source find _good;

    if (_badAt < 0) exitWith {
        if (_goodAt >= 0) then {
            [true,_source,_label + ":already-fixed"]
        } else {
            [false,_source,_label + ":signature-missing"]
        }
    };

    private _tailAt = _badAt + count _bad;
    if (((_source select [_tailAt]) find _bad) >= 0) exitWith {
        [false,_source,_label + ":signature-duplicate"]
    };

    [
        true,
        (_source select [0,_badAt]) + _good + (_source select [_tailAt]),
        _label + ":patched"
    ]
};

private _results = ["SFIdleOrd-support-corridor:replaced"];
private _step = [
    _attackSource,
    "_obj = _HQ getVariable [""RydHQ_Obj"",_ldr];",
    "_obj = _HQ getVariable [""RydHQ_Obj"",leader _HQ];",
    "GoSFAttack-objective-fallback"
] call _replaceExact;
_results pushBack (_step#2);
if !(_step#0) exitWith {[_step#2,_results] call _finishFailure};
_attackSource = _step#1;

_step = [
    _attackSource,
    "_posXWP3 = (_posXWP4 + (_BEnemyPos select 0))/2;",
    "_posXWP4 = (_posXWP4 + (_BEnemyPos select 0))/2;",
    "GoSFAttack-WP4-X"
] call _replaceExact;
_results pushBack (_step#2);
if !(_step#0) exitWith {[_step#2,_results] call _finishFailure};
_attackSource = _step#1;

_step = [
    _attackSource,
    "_posYWP3 = (_posYWP4 + (_BEnemyPos select 1))/2;",
    "_posYWP4 = (_posYWP4 + (_BEnemyPos select 1))/2;",
    "GoSFAttack-WP4-Y"
] call _replaceExact;
_results pushBack (_step#2);
if !(_step#0) exitWith {[_step#2,_results] call _finishFailure};
_attackSource = _step#1;

// Compile the minimally repaired native executor once, then wrap it with
// observer-only telemetry. The wrapper never issues movement, mutates HAL
// Busy/Resting state, chooses a target, or changes the native return path.
ITW_CLASH_HALNativeSF_fnc_GoSFAttackPatched = compile _attackSource;
HAL_GoSFAttack = {
    private _team = _this param [0,grpNull];
    private _target = _this param [1,objNull];
    private _targetGroup = _this param [2,grpNull];
    private _hq = _this param [3,grpNull];
    private _startedAt = time;

    private _targetCategory = "OTHER";
    if (!isNull _hq && {!isNull _targetGroup}) then {
        if (_targetGroup in (_hq getVariable ["RydHQ_EnArtG",[]])) then {
            _targetCategory = "ARTILLERY";
        } else {
            if (_targetGroup in (_hq getVariable ["RydHQ_EnStaticG",[]])) then {
                _targetCategory = "STATIC";
            } else {
                private _targetLeader = leader _targetGroup;
                if (!isNull _targetLeader && {
                    _targetLeader in (missionNamespace getVariable ["RydxHQ_AllLeaders",[]])
                }) then {
                    _targetCategory = "HQ";
                };
            };
        };
    };

    private _teamId = if (isNull _team || {isNil "ITW_CLASH_fnc_GroupId"}) then {
        "<null>"
    } else {
        [_team] call ITW_CLASH_fnc_GroupId
    };
    private _targetGroupId = if (isNull _targetGroup || {isNil "ITW_CLASH_fnc_GroupId"}) then {
        "<null>"
    } else {
        [_targetGroup] call ITW_CLASH_fnc_GroupId
    };
    private _distance = -1;
    if (!isNull _team && {!isNull (leader _team) && {!isNull _target}}) then {
        _distance = round ((leader _team) distance2D _target);
    };

    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["sof-direct-action-dispatched",[
            _teamId,
            if (isNull _team) then {"UNKNOWN"} else {str (side _team)},
            if (isNull _hq) then {"<null>"} else {str _hq},
            _targetGroupId,
            _targetCategory,
            if (isNull _target) then {""} else {typeOf _target},
            _distance,
            if (isNull _targetGroup) then {0} else {{alive _x} count units _targetGroup}
        ]] call ITW_CLASH_fnc_Log;
    };

    private _result = _this call ITW_CLASH_HALNativeSF_fnc_GoSFAttackPatched;

    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["sof-direct-action-returned",[
            _teamId,
            _targetGroupId,
            _targetCategory,
            round (time - _startedAt),
            if (isNull _team) then {0} else {{alive _x} count units _team},
            if (isNull _target) then {false} else {alive _target},
            if (isNull _targetGroup) then {0} else {{alive _x} count units _targetGroup},
            if (isNull _team) then {false} else {
                _team getVariable ["Busy" + str _team,false]
            },
            if (isNull _team) then {false} else {
                _team getVariable ["Resting" + str _team,false]
            }
        ]] call ITW_CLASH_fnc_Log;
    };
    _result
};

// The generic C.L.A.S.H. support-corridor resolver is intentionally enemy-side
// because GTFO/reconstitution use the enemy attack-from route. SOF standby may
// be called for any HAL side, so resolve this idle staging path independently
// from the HQ's actual side instead of reusing the enemy-only recovery helper.
ITW_CLASH_HALNativeSF_fnc_GetSupportCorridorSpawn = {
    params [["_objectiveIndex",-1],["_hq",grpNull]];

    if (isNull _hq || {
        isNil "ITW_PlayerSide" || {
            isNil "ITW_EnemySide" || {
                isNil "ITW_Objectives" || {
                    isNil "ITW_Bases" || {
                        _objectiveIndex < 0 || {
                            _objectiveIndex >= count ITW_Objectives
                        }
                    }
                }
            }
        }
    }) exitWith {[]};

    private _hqSide = side _hq;
    private _sideLabel = "";
    private _landSlot = -1;
    private _airSlot = -1;

    if (_hqSide isEqualTo ITW_EnemySide) then {
        _sideLabel = "enemy";
        _landSlot = ITW_ATTACK_LAND_E;
        _airSlot = ITW_ATTACK_AIR_E;
    } else {
        if (_hqSide isEqualTo ITW_PlayerSide) then {
            _sideLabel = "friendly";
            _landSlot = ITW_ATTACK_LAND_F;
            _airSlot = ITW_ATTACK_AIR_F;
        };
    };
    if (_landSlot < 0 || {_airSlot < 0}) exitWith {[]};

    private _objective = ITW_Objectives#_objectiveIndex;
    private _attacks = _objective#ITW_OBJ_ATTACKS;
    private _baseIndex = BASE_INDEX_NONE;
    private _route = "land";

    if (count _attacks > _landSlot) then {
        _baseIndex = _attacks#_landSlot;
    };
    if (_baseIndex < 0 && {count _attacks > _airSlot}) then {
        _baseIndex = _attacks#_airSlot;
        _route = "air";
    };
    if (_baseIndex < 0 || {_baseIndex >= count ITW_Bases}) exitWith {[]};

    private _position = +(ITW_Bases#_baseIndex#ITW_BASE_A_SPAWN);
    private _source = format [
        "sf-support-corridor-%1-%2-ai-spawn",
        _sideLabel,
        _route
    ];

    if (_position isEqualTo [] && {_baseIndex < count ITW_Objectives}) then {
        _position = +(ITW_Objectives#_baseIndex#ITW_OBJ_V_SPAWN);
        _source = format [
            "sf-support-corridor-%1-%2-vehicle-spawn",
            _sideLabel,
            _route
        ];
    };
    if (_position isEqualTo []) then {
        _position = +(ITW_Bases#_baseIndex#ITW_BASE_POS);
        _source = format [
            "sf-support-corridor-%1-%2-base-position",
            _sideLabel,
            _route
        ];
    };
    if (_position isEqualTo []) exitWith {[]};
    if (count _position < 3) then {_position pushBack 0};

    [_position,_objectiveIndex,_source,_baseIndex,_hqSide]
};

// Native HAL parks idle SpecFor around the commander with a "Guard HQ" task.
// C.L.A.S.H. keeps the same lightweight idle HOLD model but resolves the staging
// center from the side-correct Impasse support corridor. This keeps SOF in the
// rear-security network without making them conventional point-defense troops.
HAL_SFIdleOrd = {
    private _hq = _this param [0,grpNull];
    if (isNull _hq) exitWith {};

    {
        private _group = _x;
        if (isNull _group || {{alive _x} count units _group == 0}) then {continue};

        private _unitVar = str _group;
        if (_group getVariable ["Resting" + _unitVar,false]) then {continue};
        if (_group getVariable ["Busy" + _unitVar,false]) then {continue};
        if (_group getVariable ["ITW_CLASH_GTFO",false]) then {continue};
        if (_group getVariable ["ITW_CLASH_Withdrawing",false]) then {continue};
        if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") then {continue};
        if ((_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") then {continue};

        private _objectiveIndex = _group getVariable [
            "ITW_CLASH_AssignedObjective",
            VAR_GET_OBJ_IDX(_group)
        ];
        if (_objectiveIndex < 0) then {
            _objectiveIndex = missionNamespace getVariable ["ITW_CLASH_CommanderObjective",-1];
        };

        private _center = [];
        private _source = "support-corridor-unresolved";
        private _baseIndex = -1;
        if (_objectiveIndex >= 0) then {
            private _corridor = [
                _objectiveIndex,
                _hq
            ] call ITW_CLASH_HALNativeSF_fnc_GetSupportCorridorSpawn;
            if (_corridor isNotEqualTo []) then {
                _center = +(_corridor#0);
                _source = _corridor#2;
                _baseIndex = _corridor#3;
            };
        };

        // If the correct side has no valid attack-from corridor, fail open to
        // the HQ's current rear position. Do not reuse the enemy-only home-base
        // helper for a friendly HAL and accidentally cross the battlefield.
        if (_center isEqualTo []) then {
            _center = getPosATL (vehicle leader _hq);
            _source = "sf-standby-hq-fallback";
        };
        if (count _center < 3) then {_center pushBack 0};
        _center set [2,0];

        private _standby = [
            _center,
            ITW_CLASH_SFStandbyMinRadius,
            ITW_CLASH_SFStandbyMaxRadius,
            5,
            0,
            0.4,
            0,
            [],
            [_center,_center]
        ] call BIS_fnc_findSafePos;
        if (_standby isEqualTo [] || {surfaceIsWater _standby}) then {
            _standby = +_center;
        };
        if (count _standby < 3) then {_standby pushBack 0};
        _standby set [2,0];

        [_group] call RYD_WPdel;

        private _leader = leader _group;
        if (!isNull _leader && {(count (_group getVariable ["HACAddedTasks",[]])) == 0}) then {
            private _task = [
                _leader,
                [
                    "Secure the support corridor. Stand by for special operations.",
                    "Special Operations Standby",
                    ""
                ],
                _standby
            ] call RYD_AddTask;
            private _tasks = _group getVariable ["HACAddedTasks",[]];
            _tasks pushBack _task;
            _group setVariable ["HACAddedTasks",_tasks];
        };

        [_group,_standby,"HQ_ord_SFstandby",_hq] call RYD_OrderPause;
        private _wp = [_group,_standby,"HOLD","AWARE","RED","NORMAL"] call RYD_WPadd;
        _wp setWaypointStatements ["true","deleteWaypoint [group this, 0];"];

        _group setVariable ["ITW_CLASH_SFStandbyObjective",_objectiveIndex];
        _group setVariable ["ITW_CLASH_SFStandbyBase",_baseIndex];
        _group setVariable ["ITW_CLASH_SFStandbySource",_source];

        private _signature = str [_objectiveIndex,_baseIndex,_source];
        if (_signature != _group getVariable ["ITW_CLASH_SFStandbySignature",""]) then {
            _group setVariable ["ITW_CLASH_SFStandbySignature",_signature];
            if (!isNil "ITW_CLASH_fnc_Log") then {
                ["sof-standby",[
                    [_group] call ITW_CLASH_fnc_GroupId,
                    _objectiveIndex,
                    _baseIndex,
                    _source,
                    _standby,
                    round (_standby distance2D _center),
                    str (side _hq)
                ]] call ITW_CLASH_fnc_Log;
            };
        };
    } forEach (_hq getVariable ["RydHQ_SpecForG",[]]);
};

ITW_CLASH_HALNativeSFFixReady = true;
ITW_CLASH_HALNativeSFFixFinished = true;
diag_log format [
    "CLASH BOOT | native-sf-fix-ready | version=%1 sourceMatched=true results=%2 idleDoctrine=support-corridor-standby commanderGuard=false sideAwareStandby=true goSFAttack=native-patched-observed nativeExecutorPreserved=true attackChars=%3",
    ITW_CLASH_HALNativeSFFixVersion,
    _results,
    count _attackSource
];
true
