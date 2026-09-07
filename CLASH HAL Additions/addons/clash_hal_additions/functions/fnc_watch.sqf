/*
	CLASH_fnc_HALAdd_Watch

	Server-side loop, one per live HQ (LeaderHQ..LeaderHQH). Reads the raw
	enemy-classification lists NR6 HAL already publishes on the HQ object
	(RydHQ_EnAAinf, RydHQ_EnStaticAA, RydHQ_EnStaticAT, RydHQ_EnSupport,
	RydHQ_EnCargo - all populated by HAL's own scanner, all public
	getVariable state) and, for each non-empty category, calls
	CLASH_fnc_HALAdd_Respond with a doctrine-chosen candidate pool built
	from the HQ's own force lists.

	Does not read or write anything HQOrders.sqf owns privately. Runs on
	its own independent cadence, fully decoupled from HAL's own order
	cycle.
*/

params ["_HQname"];

if (isNil _HQname) exitWith {};
private _HQobj = missionNamespace getVariable _HQname;
if (isNil "_HQobj" || {isNull _HQobj}) exitWith {};
private _HQ = group _HQobj;

diag_log format ["CLASHHALADD | watch-start | hq=%1", _HQname];

while {!isNull _HQ} do
{
	private _snipersG  = _HQ getVariable ["RydHQ_snipersG", []];
	private _NCrewInfG = (_HQ getVariable ["RydHQ_NCrewInfG", []]) - (_HQ getVariable ["RydHQ_SpecForG", []]);
	private _LArmorG   = _HQ getVariable ["RydHQ_LArmorG", []];
	private _HArmorG   = _HQ getVariable ["RydHQ_HArmorG", []];
	private _cars      = (_HQ getVariable ["RydHQ_CarsG", []]) - ((_HQ getVariable ["RydHQ_ATInfG", []]) + (_HQ getVariable ["RydHQ_AAInfG", []]) + (_HQ getVariable ["RydHQ_SupportG", []]));
	// Approximation of HAL's internal CAS pool merge (RCAS + BAirG); not
	// byte-identical to RYD_Dispatcher's private _airCAS build.
	private _airCAS = (_HQ getVariable ["RydHQ_RCAS", []]) + (_HQ getVariable ["RydHQ_BAirG", []]);

	private _categories =
	[
		["AAInf",    _HQ getVariable ["RydHQ_EnAAinf", []],    [[_snipersG,0.5,"SNP"],[_LArmorG,1,"ARM"],[_NCrewInfG,0.5,"INF"]],                 0,  0, 85],
		["StaticAA", _HQ getVariable ["RydHQ_EnStaticAA", []], [[_LArmorG,1,"ARM"],[_HArmorG,1,"ARM"],[_NCrewInfG,0.5,"INF"],[_snipersG,0.5,"SNP"]], 0,  0, 85],
		["StaticAT", _HQ getVariable ["RydHQ_EnStaticAT", []], [[_airCAS,2,"AIR"],[_NCrewInfG,0.5,"INF"],[_snipersG,0.5,"SNP"]],                    75, 80,  0],
		["Support",  _HQ getVariable ["RydHQ_EnSupport", []],  [[_cars,1,"INF"],[_airCAS,1,"AIR"],[_LArmorG,0.5,"ARM"]],                            75, 80, 85],
		["Cargo",    _HQ getVariable ["RydHQ_EnCargo", []],    [[_cars,1,"INF"],[_airCAS,1,"AIR"],[_NCrewInfG,0.5,"INF"]],                          75, 80, 85]
	];

	{
		_x params ["_kind", "_threatGroups", "_pool", "_atrr1", "_atrr2", "_aarisk"];
		if (count _threatGroups > 0) then
		{
			[_threatGroups, _kind, _HQ, _pool, _atrr1, _atrr2, _aarisk] call CLASH_fnc_HALAdd_Respond;
		};
	} forEach _categories;

	sleep 20;
};

diag_log format ["CLASHHALADD | watch-stop | hq=%1", _HQname];
