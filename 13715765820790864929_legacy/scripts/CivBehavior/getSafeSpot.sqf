#include "defines.inc"

params ["_unit","_mode"];

private _module = _unit getVariable ["#core",objNull]; 
if (isNull _module) exitWith {objNull};

private ["_building","_pos"];
switch (_mode) do
{
    case MODE_SAFE:
    {
        _building = ([_module getVariable ["#safeSpots",[]],[_unit],{_x distance _input0},"ASCEND"] call bis_fnc_sortBy) param [0,objNull];
        if (isNil "_building") then {
            _pos = [[_module getVariable ["#center",getPosATL _unit],[_module getVariable ["#radius",200]]],["water"]] call BIS_fnc_randomPos;
        } else {
            _pos = selectRandom (_building call BIS_fnc_buildingPositions);
            if (isNil "_pos") then {_pos = getPosATL _building};
        };
        _pos
    };
    case MODE_IDLE:
    {
        _building = selectRandom (_module getVariable ["#idleSpots",[]]);
        if (isNil "_building") then {
            _pos = [[_module getVariable ["#center",getPosATL _unit],[_module getVariable ["#radius",200]]],["water"]] call BIS_fnc_randomPos;
        } else {
            _pos = selectRandom (_building call BIS_fnc_buildingPositions);
            if (isNil "_pos") then {_pos = getPosATL _building};
        };
        _pos
    };
    default
    {
        objNull
    };
};
