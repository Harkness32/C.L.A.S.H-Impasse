/*
	CLASH_fnc_HALAdd_Start

	preInit=1 entry point (see config.cpp). Self-starting: requires no
	mission-side hook, no init.sqf edit, no NR6 HAL file changes. Waits for
	each possible HQ slot (LeaderHQ..LeaderHQH) to exist, then spawns one
	CLASH_fnc_HALAdd_Watch loop per HQ that actually gets used.
*/

if (!isServer) exitWith {};

[] spawn
{
	private _names = ["LeaderHQ","LeaderHQB","LeaderHQC","LeaderHQD","LeaderHQE","LeaderHQF","LeaderHQG","LeaderHQH"];

	{
		private _HQname = _x;
		[_HQname] spawn
		{
			params ["_HQname"];
			waitUntil
			{
				sleep 2;
				!(isNil _HQname) && {!(isNull (missionNamespace getVariable [_HQname, objNull]))}
			};
			[_HQname] call CLASH_fnc_HALAdd_Watch;
		};
	} forEach _names;
};
