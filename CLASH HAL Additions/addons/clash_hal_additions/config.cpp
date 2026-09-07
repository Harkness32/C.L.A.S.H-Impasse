class CfgPatches
{
	class CLASH_HAL_Additions
	{
		author = "CLASH";
		name = "CLASH HAL Additions";
		units[] = {};
		weapons[] = {};
		requiredVersion = 4.11;
		requiredAddons[] = { "NR6_HAL" };
		version = "0.1";
	};
};

// Standalone addon. Depends on NR6_HAL for its helper functions (RYD_TerraCognita,
// RYD_DistOrd, RYD_CloseEnemyB, RYD_AmmoCount, RYD_PointToSecDst, RYD_IsNight,
// RYD_GoLaunch, RYD_Spawn) and public HQ-object state (RydHQ_* getVariable calls).
// Does not modify, wrap, or duplicate any nr6_hal file.
class CfgFunctions
{
	class CLASHHALADD
	{
		class Main
		{
			file = "\CLASH_HAL_Additions\functions";
			class respond { file = "fnc_respond.sqf"; };
			class watch { file = "fnc_watch.sqf"; };
			class start { file = "fnc_start.sqf"; preInit = 1; };
		};
	};
};
