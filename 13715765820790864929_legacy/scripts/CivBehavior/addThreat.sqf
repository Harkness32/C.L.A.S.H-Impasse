#include "defines.inc"

/*
	Consolidate 2 danger events into 1 and returns resulting danger position.

	Example:
	[_danger1Value,_danger1Pos,_danger2Value,_danger2Pos] call CivBeh_fnc_addThreat;
*/

params ["_value1","_pos1","_value2","_pos2"];

private _pos1offset = (_pos2 vectorDiff _pos1) vectorMultiply (_value2/(_value1 + _value2));

(_pos1 vectorAdd _pos1offset)