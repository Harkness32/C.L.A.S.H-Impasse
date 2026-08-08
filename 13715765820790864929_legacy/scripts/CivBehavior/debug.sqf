#include "defines.inc"

params
[
	"_mode",
	"_arg1",
	"_arg2",
	"_arg3",
	"_arg4",
	"_arg5"
];

switch (_mode) do
{
	case "debug":
	{
		private _core = CivBeh_fnc_CivBehavior_paramsDraw3D select _thisEventHandler;
		private _units = _core getVariable ["#units",[]];

		//debug safespots
		private _idlespots = _core getVariable ["#idleSpots",[]];
		private _safespots = _core getVariable ["#safeSpots",[]];

		private ["_safespot","_inhabitants","_label"];

		{
			_safespot = _x;
			_label = "idle";

			drawIcon3D [ICON_SAFESPOT, [1,1,1,0.5], getPosATL _x, 1, 1, 0, _label, 2];
		}
		forEach _idlespots;
		{
			_safespot = _x;
			_label = "safe";

			drawIcon3D [ICON_SAFESPOT_TERMINAL, [0.7,0.7,1,0.5], getPosATL _x, 1, 1, 0, _label, 2];
		}
		forEach (_safespots - _idlespots);

		//debug units
		private ["_threat","_label","_posUnit","_posDestination","_posUnitUp","_posDestinationUp"];

		{
			_threat = _x getVariable ["#threatValue",0];
			_label = format["%1: %2 <%3>",_forEachIndex,_x getVariable ["#state","?"],ROUND_DECIMALS(_threat,0.01)];

			_posUnit = getPosVisual _x;
			_posUnitUp = _posUnit vectorAdd [0,0,3];
			_posDestination = _x getVariable ["#destination",_posUnit];
			_posDestinationUp = _posDestination vectorAdd [0,0,3];

			_labelDestination = format["%1: %2m",_forEachIndex,ROUND_DECIMALS(_posUnit distance _posDestination,1)];

			//["[ ] %1 -> %2",_posUnit,_posDestination] call bis_fnc_logFormat;
			//["[ ] %1 -> %2",_posUnitUp,_posDestinationUp] call bis_fnc_logFormat;

			drawIcon3D [ICON_UNIT, [1,0,1,0.75], _posUnitUp, 1, 1, 0, _label, 2];
			drawIcon3D [ICON_DESTINATION, [1,0,1,0.25], _posDestinationUp, 1, 1, 0, _labelDestination, 2];

			drawLine3D [_posUnitUp, _posDestinationUp, [1,0,1,0.75]];
			drawLine3D [_posUnit, _posUnitUp, [1,0,1,0.25]];
			drawLine3D [_posDestination, _posDestinationUp, [1,0,1,0.25]];
		}
		forEach _units;


	};

	//case "printDanger":
	//{
	//	private _id = _arg1;
	//	private _unit = _arg2;
    //
	//	["[ ][%1][%2] %3 <- %4 from %5",_id,_unit,GET_DC_STRING(_dangerCause),_dangerCausedBy,_dangerPos] call bis_fnc_logFormat;
	//};
	//case "printDangerQueue":
	//{
	//	//private _id = format["%1 queue",_arg1];
	//	private _id = _arg1;
	//	private _unit = _arg2;
    //
	//	if (count _queue > 0) then
	//	{
	//		{
	//			_x params ["_dangerCause","_dangerPos","","_dangerCausedBy"];
    //
	//			["printDanger",_id,_unit] call CivBeh_fnc_debug;
	//		}
	//		forEach _queue;
	//	}
	//	else
	//	{
	//		["[ ][%1][%2] No danger event in the queue.",_id,_unit] call bis_fnc_logFormat;
	//	};
	//};

	default
	{

	};
};