#include "defines.inc"
DEBUG_LOG("ThreatQueue",_this);

params ["_unit","_threat"];

if (_unit getVariable ["#threatsActive",false]) exitWith {
    private _queue = _unit getVariable ["#threatQueue",[]];
    _queue pushBack _threat;
    _unit setVariable ["#threatQueue",_queue];
};
_unit setVariable ["#threatsActive",true];
_unit setVariable ["#threatQueue",[_threat]]; 

[_unit] spawn {  
    params ["_unit"];
    //agregated threat value
    private _threat = 0;
    
    //create unit id
    _unit setVariable ["#id",str _unit];
    private _queue = _unit getVariable ["#threatQueue",[]];

    while {(count _queue > 0 || {_threat > 0.05}) && {alive _unit}} do {
        _unit setVariable ["#threatQueue",[]];

        _threat = [_unit,_queue] call CivBeh_fnc_main;

        //lod the danger processing according to player distance        
        sleep (_unit call CivBeh_fnc_getQueueDelay);
        _queue = _unit getVariable ["#threatQueue",[]];
    };
    _unit setVariable ["#threatValue",0]; 
    _unit setVariable ["#threatsActive",false];        
};
