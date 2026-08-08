#include "defines.inc"
//DEBUG_LOG("Main",_this);

params [["_unit",objNull],["_threatsNew",[]]];

private _unitPos = getPosATL _unit;
private _unitID = _unit getVariable ["#id",str _unit];

//private _core = _unit getVariable ["#core",objNull];
//private _debug = _core getVariable ["#debug",false];

//get time elapsed from previous processing and store it for future runs
private _timePrev = _unit getVariable ["#timePrev",time]; _unit setVariable ["#timePrev",time];
private _timeDecay = (time - _timePrev) * THREAT_DECAY_PER_SECOND;

//get existing threats & decay them
private _threats = _unit getVariable ["#threats",[]];

//decay existing threats
{
	//["[ ][%1] threat from %2 lowered from %3 to %4",_unitID,_x,_x getVariable [_unitID,0],((_x getVariable [_unitID,0]) - _timeDecay) max 0] call bis_fnc_logFormat;

	_x setVariable [_unitID,((_x getVariable [_unitID,0]) - _timeDecay) max 0];
}
forEach _threats;

//merge existing threats with new threats
_threats append _threatsNew;
_threats = _threats arrayIntersect _threats;

//refresh or set threat value to 1 on new threats
{_x setVariable [_unitID,1]} forEach _threatsNew;

//remove low or expired threats
_threats = _threats select {(_x getVariable [_unitID,0]) > 0.1};

//store valid threats
_unit setVariable ["#threats",_threats];

//exit if there are no threats
if (count _threats == 0) exitWith
{
	_unit setVariable ["#threatValue",0];
	0
};

//get aggregated threat
private ["_xPos","_xValue"];

private _threatValue = 0;
private _threatPos = [0,0,0];
private _markerThreats = [];

{
	_xPos = getPosATL _x;
	_xValue = _x getVariable [_unitID,0];

	//factor distance
	_xValue = GET_THREAT_BY_DISTANCE(_xValue,_xPos,_unitPos);

	if (_xValue > 0) then
	{
		_threatPos = [_threatValue,_threatPos,_xValue,_xPos] call CivBeh_fnc_addThreat;
		_threatValue = _threatValue + _xValue;
	};
}
forEach _threats;

if (_threatValue == 0) exitWith
{
	_unit setVariable ["#threatValue",0];
	0
};

//calculate fleeing point
private _vectorDir = vectorNormalized (_unitPos vectorDiff _threatPos);
_vectorDir set [2,0];

//store fleeing info
_unit setVariable ["#threatVector",_vectorDir];
_unit setVariable ["#threatPos",_threatPos];
_unit setVariable ["#threatValue",_threatValue];

private _fleeVector = _vectorDir vectorMultiply ((_threatValue * 100) max 50 min 150);
private _fleeDestination = _unitPos vectorAdd _fleeVector;
_fleeDestination = _fleeDestination findEmptyPosition [0, 25, "Land_VR_Block_02_F"];

if (count _fleeDestination == 0) then
{
	//["[ ] Unit %1 is planning into obstacle!",_unit] call bis_fnc_logFormat;

	for "_i" from 2 to 10 do
	{
		_fleeDestination = _unitPos vectorAdd (_fleeVector vectorMultiply _i);
		_fleeDestination = _fleeDestination findEmptyPosition [0, 25, "Land_VR_Block_02_F"];

		if (count _fleeDestination != 0) exitWith {};
	};

	if (count _fleeDestination == 0) then
	{
		_fleeDestination = _unitPos vectorAdd _fleeVector;

		//["[x] Proper flee destination for unit %1 was not found!",_unit] call bis_fnc_logFormat;
	}
	else
	{
		//["[i] Proper flee destination for unit %1 was found.",_unit] call bis_fnc_logFormat;
	};
};

_unit setVariable ["#fleeDestination",_fleeDestination];

_threatValue 