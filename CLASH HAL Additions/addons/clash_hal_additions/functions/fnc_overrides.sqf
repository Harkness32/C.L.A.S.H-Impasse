/*
	CLASH_fnc_HALAdd_Overrides

	Called by CLASH's copy of RydHQInit.sqf in the same unscheduled step as
	HAL's VarInit.sqf, so these globals never hold HAL's originals while any
	other script can run. Each file in \clash_hal_additions\hal\ is the NR6 HAL
	script with CLASH's fixes. TaskInitNR6.sqf is compiled by RydHQInit.sqf
	itself, in place of HAL's.
*/

private _swapped = [];
{
	_x params ["_global","_file"];
	missionNamespace setVariable [
		_global,
		compile preprocessFileLineNumbers ("\clash_hal_additions\hal\" + _file)
	];
	_swapped pushBack _global;
} forEach [
	["HAL_GoAmmoSupp","GoAmmoSupp.sqf"],
	["HAL_GoAttInf","GoAttInf.sqf"],
	["HAL_GoCapture","GoCapture.sqf"],
	["HAL_GoCaptureNaval","GoCaptureNaval.sqf"],
	["HAL_GoRest","GoRest.sqf"],
	["HAL_SuppAmmo","SuppAmmo.sqf"],
	["HAL_SuppFuel","SuppFuel.sqf"],
	["HAL_SuppRep","SuppRep.sqf"]
];

CLASH_HALAdd_OverridesApplied = _swapped;
diag_log format [
	"CLASHHALADD | hal-overrides-applied | halVersion=%1 swapped=%2 taskInit=clash",
	missionNamespace getVariable ["HAL_Ver","?"],
	_swapped
];
true
