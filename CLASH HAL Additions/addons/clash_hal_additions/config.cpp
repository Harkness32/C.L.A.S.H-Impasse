class CfgPatches
{
	class CLASH_HAL_Additions
	{
		author = "CLASH";
		name = "CLASH HAL Additions";
		units[] = {};
		weapons[] = {};
		requiredVersion = 0.1;
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
	class CLASH
	{
		tag = "CLASH";
		class HALAdd
		{
			// A function-level file= is a full path; it does not inherit a category folder.
			class HALAdd_Respond { file = "\clash_hal_additions\functions\fnc_respond.sqf"; };
			class HALAdd_Watch { file = "\clash_hal_additions\functions\fnc_watch.sqf"; };
			class HALAdd_Start { file = "\clash_hal_additions\functions\fnc_start.sqf"; preInit = 1; };
		};
	};
};
