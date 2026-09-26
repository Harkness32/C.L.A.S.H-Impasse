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

// Depends on NR6_HAL for its helper functions (RYD_TerraCognita, RYD_DistOrd,
// RYD_CloseEnemyB, RYD_AmmoCount, RYD_PointToSecDst, RYD_IsNight, RYD_GoLaunch,
// RYD_Spawn) and public HQ-object state (RydHQ_* getVariable calls).
//
// HAL fixes live here, never in the NR6 HAL mod: requiredAddons loads this
// config after HAL's, so the HALcore entry below points HAL's start at a copy
// of RydHQInit.sqf that swaps in CLASH's versions of the scripts listed in
// fnc_overrides.sqf. Every other HAL file loads unchanged from NR6 HAL.
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
			class HALAdd_Overrides { file = "\clash_hal_additions\functions\fnc_overrides.sqf"; };
		};
	};
	class NR6
	{
		class Modules
		{
			class HALcore
			{
				file = "\clash_hal_additions\hal\RydHQInit.sqf";
			};
		};
	};
};
