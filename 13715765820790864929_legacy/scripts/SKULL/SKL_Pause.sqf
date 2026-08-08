// call this to allow the player to freeze the game if they are the only player, and they are hosting
//
// arguments: [["_freezeCode",{}],["_unfreezeCode",{}],[_enabled,true]]
//  _freezeCode & _unfreezeCode are functions/code to call when the player freezes and unfreezes the game
//  _enabled:  sets the initial state of if the pause action is available
//
// You can disable/re-enable pausing by setting SKL_PAUSE_ENABLED false/true 
//
// calling this after the mission has started is advantageous as it will have NO OVERHEAD at all
//   if called after there are multiple players in the game.  Otherwise the first player in might get
//   a action that is always evaluating to false

if (!isServer || isDedicated || !hasInterface) exitWith {};
waitUntil {!isNull player};
if (count allPlayers > 1) exitWith {};
params [["_freezeCode",{}],["_unfreezeCode",{}],["_enabled",true]];


SKL_PAUSE_ENABLED = _enabled;
SKL_PAUSE_CODE = [_freezeCode,_unfreezeCode];
SKL_PAUSE_DBG_KEYS = [];
SKL_PAUSE_DEBUG = false;

private _addAction = {
    SKL_PAUSE_CODE params ["_freezeCode","_unfreezeCode"];
    private _title = localize "STR_SKL_PAUSE_PauseGame";
    private _found = false;
    {
        if ((player actionParams _x)#0 == _title) exitWith { _found = true };
    } forEach actionIds player;

    if (!_found) then {
        player addAction [_title,{
                params ["_target", "_caller", "_actionId", "_arguments"];
                call (_arguments#0);
                private _damageAbleUnits = [];
                private _simulatedUnits = [];
                {
                    if (simulationEnabled _x) then {
                        _simulatedUnits pushBack _x;
                        [_x,false] remoteExec ["enableSimulationGlobal",2];
                    };
                    if (isDamageAllowed _x) then {
                        _damageAbleUnits pushBack _x;
                        _x allowDamage false;
                    };
                } forEach (allUnits + vehicles);
                
                private _timeMultiplier = timeMultiplier;
                [0.1] remoteExec ["setTimeMultiplier",2]; // pause time
                
                "SKL_PAUSE" cutText [localize "STR_SKL_PAUSE_GamePaused","BLACK OUT",1,true,false];
                sleep 1;
                
                SKL_PAUSE_KEY = false;
                (findDisplay 46) displayAddEventHandler ["keyDown", {
                    params ["_ctrl", "_dikCode", "_shift", "_ctrlKey", "_alt"];
                    private _handled = false;
                    #define _DIK_RETURN       28
                    #define _DIK_NUMPADENTER  156
                    #define _DIK_ESCAPE       1
                    #define _DIK_LCTRL        29
                    #define _DIK_RCTRL        157
                    #define _DIK_S            31
                    #define _DIK_K            37
                    #define _DIK_L            38
                    if (!SKL_PAUSE_DEBUG && {_dikCode in [_DIK_RETURN,_DIK_NUMPADENTER,_DIK_ESCAPE]}) then {
                        SKL_PAUSE_KEY = true;
                        (findDisplay 46) displayRemoveEventHandler ["keyDown",_thisEventHandler];
                        _handled = true;
                    } else {
                        // debug mode that will allow debugging while paused
                        if (_ctrlKey && {_dikCode in [_DIK_S,_DIK_K,_DIK_L,_DIK_LCTRL,_DIK_RCTRL]}) then {                        
                            switch (_dikCode) do {
                                case _DIK_S: {if (SKL_PAUSE_DBG_KEYS isEqualTo [])              then {_handled = true;SKL_PAUSE_DBG_KEYS pushBack _DIK_S}};
                                case _DIK_K: {if (SKL_PAUSE_DBG_KEYS isEqualTo [_DIK_S])        then {_handled = true;SKL_PAUSE_DBG_KEYS pushBack _DIK_K}};
                                case _DIK_L: {if (SKL_PAUSE_DBG_KEYS isEqualTo [_DIK_S,_DIK_K]) then {
                                        _handled = true;    
                                        SKL_PAUSE_DBG_KEYS = [];
                                        if (SKL_PAUSE_DEBUG) then {
                                            SKL_PAUSE_DEBUG = false;
                                            SKL_PAUSE_KEY = true;
                                        } else {                  
                                            "SKL_PAUSE" cutText ["","BLACK IN",1,true,false];
                                            [player,true] remoteExec ["enableSimulationGlobal",2];
                                            SKL_PAUSE_DEBUG = true;
                                        };
                                    };
                                };
                                case _DIK_LCTRL;
                                case _DIK_RCTRL: {};
                                default {SKL_PAUSE_DBG_KEYS = []};
                            };
                        } else {SKL_PAUSE_DBG_KEYS = []};
                    };
                    _handled;
                }]; 
                waitUntil {SKL_PAUSE_KEY};
                
                "SKL_PAUSE" cutText ["","BLACK IN",1,true,false];
                
                [_timeMultiplier] remoteExec ["setTimeMultiplier",2]; 
                {[_x,true] remoteExec ["enableSimulationGlobal",2]} forEach _simulatedUnits;
                {_x allowDamage true} forEach _damageAbleUnits;
                call (_arguments#1);
            },[_freezeCode,_unfreezeCode],0,false,true,"","count allPlayers == 1 && {SKL_PAUSE_ENABLED }",-1,true 
        ];
    };
};
player addEventHandler ["Respawn", _addAction];         
[ missionNamespace, "reviveRevived", _addAction] call BIS_fnc_addScriptedEventHandler;
call _addAction;
