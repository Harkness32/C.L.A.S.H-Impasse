/*
    Modifed from code by Killzone_Kid

    Description:
    Recompiles existing code to final

    Parameter(s):
    0: STRING
        - name of the variable containing code
        - variables containing no code are ignored

    2: NAMESPACE (Optional)
        - namespace of the variable containing code
        - if no namespace provided missionNamespace is assumed

    Returns: BOOL
        - true on success
        - false on failure

    Example 1:
        myCode = {
            hint "This is my code!"
        };
        ["myCode"] call BIS_fnc_compileFinal;

    Example 2:
        with uiNamespace do {
            myCode2 = {
                hint "This is my code too!"
            }
        };
        if (["myCode2",uiNamespace] call BIS_fnc_compileFinal) then {
            hint "Success!"
        };

     ---------- Debug Feature ----------
     If you place SKL_CF_DEBUG_ENABLE = true in your code before calling this function,
     it will place a diag_log at the start of each function.
     Set SKL_CF_DEBUG = true to cause those calls to be logged
*/
params [["_var","",[""]], ["_skipDebug",false,[false]],["_ns",missionNamespace,[missionNamespace]]];
private _code = _ns getVariable [_var, 0];
if (typeName _code != typeName {}) exitWith {false};

// C.L.A.S.H. uses narrowly-scoped finalization windows during synchronous
// bootstrap only. All lists are cleared before scheduled mission startup.
private _deferredFinalizers = missionNamespace getVariable [
    "ITW_CLASH_DeferredFinalizers",
    []
];
private _persistentDeferredFinalizers = missionNamespace getVariable [
    "ITW_CLASH_PersistentDeferredFinalizers",
    []
];
private _lateDoctrineFinalizers = missionNamespace getVariable [
    "ITW_CLASH_LateDoctrineFinalizers",
    []
];

// ITW_Ally.sqf is compiled in preInit, but the player-transport authority layer
// cannot bind until init after Dual-HAL/Checkbook exists. Keep only the two
// native physical ferry functions mutable until that synchronous authority
// module closes this window before ITW_Start launches ITW_AllyInit.
private _allyTransportWindow = missionNamespace getVariable [
    "ITW_CLASH_AllyTransportFinalizationWindow",
    true
];
private _allyTransportDeferred = _allyTransportWindow && {
    _var in ["ITW_AllyLoadIntoVehManager","ITW_AllyLoadGrpIntoVeh"]
};

if (_allyTransportDeferred || {_var in (
    _deferredFinalizers +
    _persistentDeferredFinalizers +
    _lateDoctrineFinalizers
)}) exitWith {
    diag_log format ["CLASH BOOT | finalization-deferred | %1",_var];
    true
};

private _codestr = str _code;
_codestr = _codestr select [1,count _codestr - 2]; // remove begin and end parenthesizes
#ifdef __A3_DEBUG__
    if (isNil "SKL_CF_DEBUG_ENABLE") then {SKL_CF_DEBUG_ENABLE = false};
    if (isNil "SKL_CF_DEBUG")        then {SKL_CF_DEBUG        = false};
    if (SKL_CF_DEBUG_ENABLE && {!_skipDebug}) then {
        _codestr = format ["if (SKL_CF_DEBUG) then {diag_log format ['SKL_CF %1: %%1',_this]};",_var] + endl + _codestr
    };
#endif
_code = compileFinal _codestr;
_ns setVariable [_var, _code];
true