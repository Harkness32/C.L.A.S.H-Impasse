// tries to move a unit to a position with a lot of help
// this function should be 'call' not 'spawn' as it spawns a task if necessary

params ["_unit","_toPos",["_building",objNull],["_adjustSpeed",false]];

#define DEBUG //diag_log
#define STATE_INIT    0
#define STATE_MOVING  1
#define STATE_STOPPED 2
#define STATE_DONE    3

#if __has_include("\z\ace\addons\main\script_component.hpp")
#define ALIVE(unit) (lifeState unit in ["HEALTHY","INJURED"])
#define CONSCIOUS(unit) (!(unit getVariable ["ACE_isUnconscious", false]))
#else
#define ALIVE(unit) (alive unit)
#define CONSCIOUS(unit) (lifeState unit in ["HEALTHY","INJURED"])
#endif

if (isNil "BetterMoveToHandlerRunning" || {!BetterMoveToHandlerRunning}) then {
    BetterMoveToUnits = [];
    BetterMoveToHandlerRunning = true;
    [] spawn {
        scriptName "ITW_BetterMoveTo";
        
        if (isNil "LV_PAUSE") then {LV_PAUSE = false};
        private _stuckLimit = 8; 
        private _bmtUnitData = [];
        while {true} do {
            sleep 3;
            while {LV_PAUSE} do {sleep 5};
            
            isNil {
                isNil {
                    {_bmtUnitData pushBack _x} forEach BetterMoveToUnits;
                    BetterMoveToUnits = [];
                };
            };
            
            {
                private _uInfo = _x;
                _uInfo params ["_unit","_toPos","_state","_building","_adjustSpeed","_moveToPos","_timeout","_prevPos","_stuck","_engaging"];
#define PARAM_Unit    0
#define PARAM_ToPos   1
#define PARAM_State   2
#define PARAM_InBldg  3
#define PARAM_AdjSp   4
#define PARAM_MoveTo  5
#define PARAM_TimeOut 6
#define PARAM_PrevPos 7
#define PARAM_Stuck   8
#define PARAM_Engage  9 
                
                switch (_state) do {
                    case STATE_INIT: {          
                        if (_adjustSpeed) then {
                            if (isNull(_unit findNearestEnemy _unit)) then {
                                _unit forceSpeed 1;
                            } else {
                                _unit forceSpeed 10;
                            };
                        };

                        _unit setVariable ["BBI_Pos",_toPos];
                        _unit doMove _toPos;

                        private _moveToPos = +_toPos;
                        if (_moveToPos#2 < 0.1) then { _moveToPos set [2,0.1] };
                        _moveToPos set [2,(_moveToPos#2)+0.2];
                        DEBUG ["BMT: move",_unit,_moveToPos];
                         
                        private _timeout = time + 180;
                        private _prevPos = getPosATL _unit;
                        private _stuck = 0; // if unit not moving or falling for a couple seconds then they are stuck
                        private _engaging = false;
                        _uInfo set [PARAM_MoveTo ,_moveToPos];
                        _uInfo set [PARAM_TimeOut,_timeout];
                        _uInfo set [PARAM_PrevPos,_prevPos];
                        _uInfo set [PARAM_Stuck  ,_stuck];
                        _uInfo set [PARAM_Engage ,_engaging];
                        if (!(_unit getVariable ["BBI_Pos",[]] isEqualTo _toPos) || {!(CONSCIOUS(_unit)) ||{(unitReady _unit) || {(_unit distance _moveToPos < 2) || {(time > _timeout) || {(_stuck > _stuckLimit)}}}}}) then {
                            _uInfo set [PARAM_State,STATE_STOPPED];
                        } else {
                            _uInfo set [PARAM_State,STATE_MOVING];
                        };                    
                    };

                    case STATE_MOVING: {
                        if (!(_unit getVariable ["BBI_Pos",[]] isEqualTo _toPos) || {!(CONSCIOUS(_unit)) ||{(unitReady _unit) || {(_unit distance _moveToPos < 2) || {(time > _timeout) || {(_stuck > _stuckLimit)}}}}}) exitWith {
                            _uInfo set [PARAM_State,STATE_STOPPED];
                        };
                        private _unitSide = side _unit;
                        private _pos = getPosATL _unit;
                        _engaging = allUnits findIf {side _x getFriend _unitSide < 0.6 && {_unit knowsAbout _x > 1 && {!(_x isKindOf "LOGIC")}}} >= 0;
                        if (animationState _unit find "afal" == 0) then { // falling animation - done often when stuck in a building
                            _stuck = _stuck + 1; 
                            DEBUG (if(_stuck > _stuckLimit) then {["BMT: stuck failing",_unit,_stuck]} else {});
                        } else {
                            if (_unitSide != civilian && {!_engaging && {(_pos distance _prevPos < 0.5)}}) then {
                                _stuck = _stuck + 1; 
                                if (_stuck == 1) then {
                                    _unit move getPosATL _unit;
                                    sleep 0.5;
                                    _unit move _moveToPos;
                                };
                                if (_stuck >= floor (_stuckLimit / 4)) then {
                                    DEBUG ["BMT: stuck command to move part way",_unit,_stuck, _pos distance _prevPos, _pos distance2D _moveToPos];
                                    _unit move (_unit getPos [(_unit distance _moveToPos) * (1 - (0.1 * + _stuck)),(_unit getDir _moveToPos) + 20 - random 40]);
                                    _pos = _unit getPos [0.5,_unit getDir _moveToPos];
                                    _pos set [2,(getPosATL _unit)#2 + 0.2];
                                    _unit setPosATL _pos;
                                };
                                DEBUG (if(_stuck > _stuckLimit) then {["BMT: really stuck",_unit,_stuck, getPosATL _unit distance2D _prevPos, getPosATL _unit distance _moveToPos]} else {});
                            } else { 
                                _stuck = 0; 
                            };
                        };
                        if ((_pos distance _prevpos) > 2) then {
                            _timeout = time + 180;
                            _uInfo set [PARAM_TimeOut,_timeout];
                        }; // reset time if he's still walking
                        _prevPos = _pos;
                        _uInfo set [PARAM_PrevPos,_prevPos];
                        _uInfo set [PARAM_Stuck  ,_stuck];
                        _uInfo set [PARAM_Engage ,_engaging];
                    };

                    case STATE_STOPPED: {
                        // Deal with AI getting stuck in buildings (problematic on weferlingen map)
                        if (! CONSCIOUS(_unit)) exitWith {_uInfo set [PARAM_State,STATE_DONE]};
                        if (!_engaging && {(time > _timeout)}) then { 
                            _stuck = _stuckLimit + 1; 
                            DEBUG ["BMT:timeout",_unit];
                        };
                        if (!isNull _building && {(_unit distance _moveToPos < 2)}) then {
                            private _elevUnitASL = (getPosASL _unit) #2;
                            private _elevMoveASL = (ATLToASL _moveToPos) #2;
                            if ((_elevUnitASL + 0.4) < _elevMoveASL) then {
                                _pos = getPosATL _unit;
                                DEBUG ["BMT: lifted",_unit, _elevMoveASL - _elevUnitASL];
                                _pos set [2, _elevMoveASL];
                                _unit setPosATL (ASLToATL _pos);
                            };
                        };
                        if (animationState _unit find "afal" == 0) then {
                            [_unit,false] remoteExec ["allowDamage",_unit];
                            sleep 0.1;
                            private _cnt = 0;
                            while {CONSCIOUS(_unit) and animationState _unit find "afal" == 0 and _cnt < 20} do { 
                                private _pos = getPosATL _unit;
                                private _newPos = _pos getPos [0.2, random 360];
                                _newPos set [2, _pos select 2 + 0.2];
                                _unit setPosATL _newPos; 
                                _cnt = _cnt + 1;
                                sleep 0.1;
                            };
                            if (_cnt < 20) then {_stuck=0;};
                            DEBUG ["BMT:animation state reset",_unit, _cnt];
                            [_unit,true] remoteExec ["allowDamage",_unit];
                        };
                        if (_stuck > _stuckLimit && {{_x distance _unit < 20} count playableUnits == 0}) then {
                            private _timeout = _unit getVariable ["moveTimeout",0];
                            private _newPos = (_unit getPos [10 * _timeout, random 360]);
                            private _cnt = 0;
                            _timeout = _timeout + 1;
                            while {{_x distance _newPos < 20} count playableUnits == 0 && {_cnt < 10}} do {_cnt = _cnt + 1;_newPos = (_unit getPos [10 * _timeout, random 360]);sleep 0.1;};
                            if (_cnt < 10) then {
                                _unit setPosATL _newPos;
                                DEBUG ["BMT:stalled out: moving...",_unit,_timeout];
                            };
                            _unit setVariable ["moveTimeout",_timeout];
                        } else {_unit setVariable ["moveTimeout",0];};
                        
                        doStop _unit;
                        private _enemy = _unit findNearestEnemy _unit;
                        if (isNull(_enemy)) then {
                            _unit doWatch (_unit getRelPos [10, random 360]);
                        } else {
                            //_unit findCover [_moveToPos, getPosATL _enemy, 15];
                            _unit doWatch _enemy;
                        };
                        _uInfo set [PARAM_State,STATE_DONE];
                    };
                    
                    case STATE_DONE: {
                        if (!isNull _building && {{_x distance _building < 120} count playableUnits == 0}) then {
                            // close doors in the house	
                            if (isNil "BMT_DoorMap") then {BMT_DoorMap = createHashMap};
                            private _className = typeOf _building;
                            private _doorAnims = BMT_DoorMap getOrDefault [_className,[]];
                            if (_doorAnims isEqualTo []) then {
                                private _animCfg = configFile >> "cfgVehicles" >> _className >> "AnimationSources";
                                for "_i" from 0 to count (_animCfg) - 1 do {
                                    private _animSource = (_animCfg) select _i;
                                    private _sourceType = getText (_animSource >> "source");
                                    if (toLowerANSI _sourceType == "user") then {
                                        private _source = toLowerANSI configName _animSource;
                                        if ((_source select [0,4]) isEqualto "door") then {
                                            if ("_sound_source" in _source) exitWith {_doorAnims pushBack _source};
                                            private _len = count _source;
                                            if (_len < 8) exitWith {_doorAnims pushBack _source};
                                            if (_len < 16 && {"_source" in _source}) exitWith {_doorAnims pushBack _source};
                                        };
                                    };
                                };                         
                                BMT_DoorMap set [_className,_doorAnims];
                            };
                            {
                                private _source = _x;
                                if (_building animationSourcePhase _source == 1) then {_building animateSource [_source,0]};
                            } forEach _doorAnims;
                        };
                        _bmtUnitData deleteAt _forEachIndex;
                        _unit setVariable ["BMT_moving",nil];
                    };
                };
                if (_uInfo#PARAM_State != _state) then {
                    DEBUG ["BMT: state change",_unit,["INIT","MOVING","STOPPED","DONE"]#_state,">>",["INIT","MOVING","STOPPED","DONE"]#(_uInfo#PARAM_State)];
                };
            } forEachReversed _bmtUnitData;
        };
        BetterMoveToHandlerRunning = false;
    };
    
    // script to check door sources of all buildings loaded in arma
    BMT_DoorCheck = {
        diag_log "Door Sources";
        private _knownDoors = ["door_%1_sound_source","door_0%1_sound_source","door%1_sound_source", "door_%1_source","door_0%1_source","door_0%1","door_ext_%1_source"];
        _knownDoors apply {diag_log _x};
        toString ({
          private _className = configName _x;
          if (_className isKindOf "Building") then {
           private  _doors = [];
            for "_i" from 0 to count (_x >> "AnimationSources") - 1 do {
                private _animSource = (_x >> "AnimationSources") select _i;
                private _sourceType = getText (_animSource >> "source");
                if (toLowerANSI _sourceType == "user") then {
                    private _source = configName _animSource;
                    if (toLowerANSI (_source select [0,4]) isEqualto "door") then {
                        _doors pushBack _source;
                    };
                };
            };
            if !(_doors isEqualTo []) then {
                private _lowerDoors = _doors apply {toLowerANSI _x};
                private _cnt = 0;
                {
                    _known = _x;
                    for "_d" from 1 to 9 do {
                        if (format [_known,_d] in _lowerDoors) exitWith {_cnt = _cnt+1};
                    };
                } forEach _knownDoors;
                if (_cnt == 0) then {_knownDoors pushBack (_lowerDoors#0); diag_log (_lowerDoors)};
            };
          }; 
        }) configClasses (configFile >> "CfgVehicles");
        diag_log "DONE";
    };
};

_unit setVariable ["BMT_moving",true];
isNil {BetterMoveToUnits pushBack [_unit,_toPos,STATE_INIT,_building,_adjustSpeed,[]]};
