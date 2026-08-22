#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALNativeSFFixStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_HALNativeSFFixReady",false]
};

ITW_CLASH_HALNativeSFFixStarted = true;
ITW_CLASH_HALNativeSFFixReady = false;
ITW_CLASH_HALNativeSFFixFinished = false;
ITW_CLASH_HALNativeSFFixVersion = 2;
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

// Preserve native direct-action behavior, including HAL target selection,
// infiltration geometry, transport use, STEALTH approach and DESTROY execution.
HAL_GoSFAttack = compile _attackSource;

// Native HAL parks idle SpecFor around the commander with a "Guard HQ" task.
// C.L.A.S.H. keeps the same lightweight idle HOLD model but resolves the staging
// center from Impasse's support corridor. This keeps SOF in the rear-security
// network without making them conventional point-defense troops.
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
        if (!isNil "ITW_CLASH_fnc_GetSupportCorridorSpawn" && {_objectiveIndex >= 0}) then {
            private _corridor = [_objectiveIndex] call ITW_CLASH_fnc_GetSupportCorridorSpawn;
            if (_corridor isNotEqualTo []) then {
                _center = +(_corridor#0);
                _source = _corridor#2;
                _baseIndex = _corridor#3;
            };
        };

        if (_center isEqualTo [] && {!isNil "ITW_CLASH_fnc_GetHomeBaseSpawn"}) then {
            private _home = call ITW_CLASH_fnc_GetHomeBaseSpawn;
            if (_home isNotEqualTo []) then {
                _center = +(_home#0);
                _source = "sf-standby-" + (_home#2);
                _baseIndex = _home#3;
            };
        };

        // Last-resort fail-open location if the Impasse base graph is not ready.
        // Do not create the native commander-guard task; simply stage rearward
        // around the HQ until a real support corridor becomes resolvable.
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
                    round (_standby distance2D _center)
                ]] call ITW_CLASH_fnc_Log;
            };
        };
    } forEach (_hq getVariable ["RydHQ_SpecForG",[]]);
};

ITW_CLASH_HALNativeSFFixReady = true;
ITW_CLASH_HALNativeSFFixFinished = true;
diag_log format [
    "CLASH BOOT | native-sf-fix-ready | version=%1 sourceMatched=true results=%2 idleDoctrine=support-corridor-standby commanderGuard=false goSFAttack=native-patched attackChars=%3",
    ITW_CLASH_HALNativeSFFixVersion,
    _results,
    count _attackSource
];
true
