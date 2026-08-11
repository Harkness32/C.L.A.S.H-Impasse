
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
        //recompile myCode to final
        ["myCode"] call BIS_fnc_compileFinal;
    
    Example 2:
        with uiNamespace do {
            myCode2 = {
                hint "This is my code too!"
            }
        };
        //recompile myCode2 to final and alert on success
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

// C.L.A.S.H. may defer a very small named set of finalizers while its
// controller is synchronously compiled. The bootstrap clears this list before
// normal mission startup, so the default behavior remains compileFinal.
private _deferredFinalizers = missionNamespace getVariable [
    "ITW_CLASH_DeferredFinalizers",
    []
];
if (_var in _deferredFinalizers) exitWith {
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
        // this code with the end announce doens't work since arma will crash if a function returns with an assignment
        // ex: _r = 0 call {x = 5}
        //_codestr = "if (true) then {" + endl
        //            + "  private _ts = systemTime apply {if (_x < 10) then {'0' + str _x} else {str _x}};" + endl
        //            + "  private _args = if (isNil '_this') then {'[]'} else {_this};"
        //            + format ["  if (SKL_CF_DEBUG) then {diag_log format ['SKL_CF %1: %%1',_args]};",_var]  + endl
        //            + "  private _fn = {" + endl
        //            + _codestr
        //            + "  };" + endl
        //            + format ["_rxxx = %1;",_var]
        //            + "  private _return = _this call _fn;" + endl
        //            + format ["  if (SKL_CF_DEBUG) then {diag_log format ['SKL_CF %1: END : %%1:%%2:%%3',_ts#3,_ts#4,_ts#5]};",_var] + endl
        //            + "  if (!isNil '_return') then {_return};"+ endl
        //            + "};";
    };
#endif
_code = compileFinal _codestr;
_ns setVariable [_var, _code];
true