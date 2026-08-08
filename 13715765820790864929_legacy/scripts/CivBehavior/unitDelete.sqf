#include "defines.inc"
DEBUG_LOG("UnitDelete",_this);

if (!isServer) exitWith {};

params ["_module","_unit"];

if (isNull _unit) exitWith {false};

private _seenBy = allPlayers select {_x distance _unit < 50 || {(_x distance _unit < 150 && {([_x,"VIEW",_unit] checkVisibility [eyePos _x, eyePos _unit]) > 0.5})}};

private _canDelete = count _seenBy == 0;

if (_canDelete) then
{
    _unit call (_module getVariable ["#onDeleted",{}]);
    deleteVehicle _unit;
};

_canDelete 