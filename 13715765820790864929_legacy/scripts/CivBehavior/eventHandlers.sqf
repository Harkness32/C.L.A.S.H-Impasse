#include "defines.inc"
DEBUG_LOG("EventHandlers",_this);

params [["_type","",[""]],["_input",[],[[]]]];

private _civ = objNull;
private _threat = objNull;
switch (_type) do {
    case "FiredNear": {
        _input params ["_unit", "_firer", "_distance", "_weapon", "_muzzle", "_mode", "_ammo", "_gunner"];
        _civ = _unit;
        if (_weapon != "Throw") then {        
            _threat = _firer;
//DEBUG_LOG("EventHandlers thread firedNear",_threat);
        };
    };
    case "Dammaged": {
        _intput params ["_unit", "_selection", "_damage", "_hitIndex", "_hitPoint", "_shooter", "_projectile"];
        _civ = _unit;
        _threat = _shooter;
//DEBUG_LOG("EventHandlers thread damaged",_threat); 
    };
};

if (! isNull _threat) then {
//DEBUG_LOG("EventHandlers calling threatQueue",[_civ,_threat]); 
    [_civ,_threat] call CivBeh_fnc_threatQueue;
};