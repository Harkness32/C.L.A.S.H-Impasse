#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AmmoDispatchStarted",false]) exitWith {true};

ITW_CLASH_AmmoDispatchStarted = true;
ITW_CLASH_AmmoDispatchReady = false;
ITW_CLASH_AmmoDispatchVersion = 1;

ITW_CLASH_AmmoDispatch_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_HALLogistics_fnc_Log") then {
        ["ammo-dispatch-" + _event,_payload] call ITW_CLASH_HALLogistics_fnc_Log;
    } else {
        diag_log format ["CLASH AMMO DISPATCH | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_AmmoDispatch_fnc_TargetGroup = {
    params ["_target"];
    if (isNull _target) exitWith {grpNull};
    if (_target isKindOf "Man") exitWith {group _target};
    private _commander = effectiveCommander _target;
    if (isNull _commander) exitWith {grpNull};
    group _commander
};

/*
    Call-site provenance is explicit. Never infer whether this invocation wrote
    ASupportedG from the current array: TaskInit and SuppAmmo have different
    pre-dispatch side effects, and the same target may already be represented for
    another legitimate reason.
*/
ITW_CLASH_AmmoDispatch_fnc_Context = {
    params ["_args"];
    private _raw = _args param [8,[]];
    if (_raw isEqualType [] && {count _raw >= 3}) exitWith {
        createHashMapFromArray [
            ["source",_raw param [0,"UNKNOWN"]],
            ["boxReserved",_raw param [1,false]],
            ["supportedWritten",_raw param [2,false]]
        ]
    };

    // Compatibility fallback for an unannotated external caller. A non-null
    // drop box is safe to treat as reserved; ASupported provenance is not.
    createHashMapFromArray [
        ["source","UNANNOTATED"],
        ["boxReserved",!isNull (_args param [5,objNull])],
        ["supportedWritten",false]
    ]
};

ITW_CLASH_AmmoDispatch_fnc_ReturnPackage = {
    params ["_hq","_box",["_reason","pre-dispatch-abort"]];
    if (isNull _hq || {isNull _box} || {!alive _box}) exitWith {false};

    if (
        _box getVariable ["ITW_CLASH_LogisticsPackage",false]
        && {!isNil "ITW_CLASH_PlayerTasks_fnc_ReleasePackage"}
    ) exitWith {
        [_box,_hq,true,_reason] call ITW_CLASH_PlayerTasks_fnc_ReleasePackage
    };

    private _boxes = +(_hq getVariable ["RydHQ_AmmoBoxes",[]]);
    _boxes pushBackUnique _box;
    _hq setVariable ["RydHQ_AmmoBoxes",_boxes];
    true
};

ITW_CLASH_AmmoDispatch_fnc_ReconcilePreDispatch = {
    params [
        "_hq","_target",["_box",objNull],["_context",createHashMap],
        ["_reason","pre-dispatch-abort"],["_clearSupported",true]
    ];
    if (isNull _hq) exitWith {false};

    private _source = _context getOrDefault ["source","UNKNOWN"];
    private _boxReserved = _context getOrDefault ["boxReserved",false];
    private _supportedWritten = _context getOrDefault ["supportedWritten",false];

    private _boxReturned = false;
    if (_boxReserved && {!isNull _box} && {alive _box}) then {
        _boxReturned = [_hq,_box,_reason] call
            ITW_CLASH_AmmoDispatch_fnc_ReturnPackage;
    };

    private _supportedCleared = false;
    if (_clearSupported && {_supportedWritten}) then {
        private _targetGroup = [_target] call ITW_CLASH_AmmoDispatch_fnc_TargetGroup;
        if (!isNull _targetGroup) then {
            private _supported = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
            if (_targetGroup in _supported) then {
                _hq setVariable ["RydHQ_ASupportedG",_supported - [_targetGroup]];
                _supportedCleared = true;
            };
        };
    };

    ["reconciled",[
        _source,_reason,_boxReserved,_boxReturned,
        _supportedWritten,_supportedCleared
    ]] call ITW_CLASH_AmmoDispatch_fnc_Log;
    true
};

ITW_CLASH_AmmoDispatchReady = true;
diag_log format [
    "CLASH BOOT | ammo-dispatch-ready | version=%1 explicitProvenance=true reservationReconcile=true inferASupported=false",
    ITW_CLASH_AmmoDispatchVersion
];

true
