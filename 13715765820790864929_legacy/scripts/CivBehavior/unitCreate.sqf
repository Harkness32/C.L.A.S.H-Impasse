#include "defines.inc"
DEBUG_LOG("UnitCreate",_this);

if (!isServer) exitWith {};

params ["_module"];

private _pos = [];
private _cnt = 20;
private _center = _module getVariable ["#center",[]];
private _radius = _module getVariable ["#radius",0];

//randomize position
if (count _pos == 0 && _cnt > 0) then
{
    _cnt = _cnt - 1;
    _pos = [[[_center,_radius]]] call BIS_fnc_randomPos;

    private _posASL = (AGLToASL _pos) vectorAdd [0,0,1.5];

    //check if any player can see the point of creation
    private _seenBy = allPlayers select {_x distance _pos < 50 || {(_x distance _pos < 150 && {([_x,"VIEW"] checkVisibility [eyePos _x, _posASL]) > 0.5})}};

    if (count _seenBy > 0) then {_pos = []};

};
if (_pos isEqualTo []) exitWith {objNull};

private _class = selectRandom (_module getVariable ["#unitTypes",[]]);

private _unit = if (_module getVariable ["#useAgents",false]) then {
                    createAgent [_class, _pos, [], 0, "NONE"];
                } else {
                    _civunit = nil;
                    _class createUnit [_pos, createGroup [civilian,true], "_civunit = this"];
                    waitUntil {!isNil "_civunit"};
                    _civunit
                };

//make backlink to the core module
_unit setVariable ["#core",_module];

_unit setBehaviour "CARELESS";
_unit spawn (_module getVariable ["#onCreated",{}]);
_unit execFSM format ["%1behavior.fsm",_module getVariable ["#path",""]];
{ _x addCuratorEditableObjects [[_unit],true] } forEach allCurators;

_unit addEventHandler ["FiredNear",{["FiredNear",_this] call CivBeh_fnc_EventHandlers}];
_unit addEventHandler ["Dammaged",{["Dammaged",_this] call CivBeh_fnc_EventHandlers}];

_unit 