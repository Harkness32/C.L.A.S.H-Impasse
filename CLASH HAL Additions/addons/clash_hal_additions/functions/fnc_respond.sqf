/*
	CLASH_fnc_HALAdd_Respond

	Standalone response engine for enemy threat categories NR6 HAL tallies
	but never dispatches a counter-response for (AAInf, StaticAA, StaticAT,
	Support, Cargo). Mirrors the mechanics of NR6 HAL's own RYD_Dispatcher
	(candidate scoring, terrain preference, AT/AA risk resignation, commit
	via RYD_GoLaunch/RYD_Spawn) but is independent code that only *calls*
	HAL's existing public helper functions - it does not modify, wrap, or
	copy any nr6_hal file.

	Params:
		0: ARRAY   _threatGroups - enemy groups of this category (already
		           deduplicated by the caller against CLASHHALADD_Handled)
		1: STRING  _kind         - label, used only for diag_log
		2: OBJECT  _HQ           - the HAL HQ group object
		3: ARRAY   _pool         - [[_forceArray,_rangeWeight,_pattern], ...]
		4: NUMBER  _ATRR1        - AT risk-resignation base (armour-pattern candidates)
		5: NUMBER  _ATRR2        - AT risk-resignation base (fallback tier)
		6: NUMBER  _AArisk       - AA risk-resignation base (air-pattern candidates)

	Returns: NUMBER of groups actually committed this call.
*/

params ["_threatGroups", "_kind", "_HQ", "_pool", "_ATRR1", "_ATRR2", "_AArisk"];

private _reck      = _HQ getVariable ["RydHQ_Recklessness", 0.5];
private _attackAv  = _HQ getVariable ["RydHQ_AttackAv", []];
private _garrison  = _HQ getVariable ["RydHQ_Garrison", []];
private _garrR     = _HQ getVariable ["RydHQ_GarrR", 500];
private _flankAv   = _HQ getVariable ["RydHQ_FlankAv", []];
private _NCVeh     = _HQ getVariable ["RydHQ_NCVeh", []];
private _AAthreat  = _HQ getVariable ["RydHQ_AAthreat", []];
private _ATthreat  = _HQ getVariable ["RydHQ_ATthreat", []];
private _committed = 0;
private _perPatternLimit = 2; // simplified pacing - see docs/CLASH_HAL_ADDITIONS.md

{
	private _enemyGrp = _x;

	if (alive (leader _enemyGrp) && {!isNull (leader _enemyGrp)}) then
	{
		private _trg  = vehicle (leader _enemyGrp);
		private _tPos = getPosATL _trg;

		private _topo    = [_trg, 5] call RYD_TerraCognita;
		private _sCity   = 100 * (_topo select 0);
		private _sForest = 100 * (_topo select 1);
		private _sHills  = 100 * (_topo select 2);
		private _sMeadow = 100 * (_topo select 3);
		private _sGr     = _topo select 5;

		{
			private _force   = _x select 0;
			private _range   = _x select 1;
			private _pattern = _x select 2;
			private _limit   = _perPatternLimit;

			private _sortedForce = [_force, _tPos, 10000 * _range] call RYD_DistOrd;
			private _avF = _sortedForce;
			private _ix  = 0;

			while {(_limit > 0) && {(count _avF) > 0} && {_ix < (count _sortedForce)}} do
			{
				private _chosen = _sortedForce select _ix;
				private _chVP   = getPosATL (vehicle (leader _chosen));
				_ix = _ix + 1;

				private _positive = true;
				private _ammo = [_chosen, _NCVeh] call RYD_AmmoCount;

				private _sVal = 0;
				private _mpl  = 1 + _reck;
				switch (true) do
				{
					case (_pattern in ["SNP"]) : {_sVal = ((((2 * _sHills) + (2 * _sMeadow) + (_sGr / 5)) * _mpl) - (((_sCity / 2) + _sForest) / _mpl))};
					case (_pattern in ["ARM"]) : {_sVal = ((((5 * _sMeadow) + _sHills) * _mpl) - (((_sCity / 2) + (3 * _sForest) + _sGr) / _mpl))};
					case (_pattern in ["AIR", "AIRCAP"]) : {_sVal = ((((4 * _sMeadow) + _sHills) * _mpl) - ((_sCity + (2 * _sForest) + (_sGr / 5)) / _mpl))};
					default {_sVal = (0.5 + _sCity + (2 * _sForest) + (_sGr / 10)) * (0.5 * _mpl) - ((0.05 + (2 * _sMeadow)) * (0.5 / _mpl))};
				};
				if (_sVal < (5 + (10 * _reck))) then {_sVal = (5 + (10 * _reck))};

				private _busy   = _chosen getVariable [("Busy" + str _chosen), false];
				private _unable = _chosen getVariable ["Unable", false];

				if (_busy || _unable || {_ammo == 0} || {(random 100) > _sVal}) then
				{
					_positive = false;
				};
				if (_positive && {_chosen in _garrison} && {(vehicle (leader _chosen)) distance _tPos > _garrR}) then
				{
					_positive = false;
				};
				if (_positive && {!(_chosen in _attackAv)}) then {_positive = false};
				if (_positive && {_chosen in _flankAv}) then {_positive = false};

				if (_positive && {_pattern in ["AIR", "AIRCAP"]}) then
				{
					private _airMpl = 0;
					if ([] call RYD_IsNight) then {_airMpl = 3};
					if ((((random 100) * (1 + _reck)) < ((_airMpl + overcast) * 30)) && {!((random 100) > 95)}) then
					{
						_positive = false;
					};
				};

				// AT/AA proximity risk resignation, same shape as RYD_Dispatcher
				if (_positive && {_pattern in ["ARM"]} && {count _ATthreat > 0}) then
				{
					private _thRep = [_chVP, _ATthreat, 25000] call RYD_CloseEnemyB;
					if (_thRep select 0) then
					{
						private _clstE = getPosATL (vehicle (leader (_thRep select 2)));
						private _enDst = [_chVP, _tPos, _clstE] call RYD_PointToSecDst;
						if (_enDst > 0 && {_enDst < 1500}) then
						{
							private _thFct = ((_ATRR1 * 40) / (sqrt _enDst)) / (0.5 + (2 * _reck));
							if (((random 100) < _thFct) && {!(((random 100) > (95 - (_reck * 10))) && {_thFct >= (95 - (_reck * 10))})}) then
							{
								_positive = false;
							};
						};
					};
				};
				if (_positive && {_pattern in ["AIR", "AIRCAP"]} && {count _AAthreat > 0}) then
				{
					private _thRep = [_chVP, _AAthreat, 25000] call RYD_CloseEnemyB;
					if (_thRep select 0) then
					{
						private _clstE = getPosATL (vehicle (leader (_thRep select 2)));
						private _enDst = [_chVP, _tPos, _clstE] call RYD_PointToSecDst;
						if (_enDst > 0 && {_enDst < 1500}) then
						{
							private _thFct = ((_AArisk * 40) / (sqrt _enDst)) / (0.5 + (2 * _reck));
							if (((random 100) < _thFct) && {!(((random 100) > (95 - (_reck * 10))) && {_thFct >= (95 - (_reck * 10))})}) then
							{
								_positive = false;
							};
						};
					};
				};

				if (_positive) then
				{
					_chosen setVariable [("Busy" + str _chosen), true];
					_HQ setVariable ["RydHQ_AttackAv", (_HQ getVariable ["RydHQ_AttackAv", []]) - [_chosen]];
					[[_chosen, _trg, _HQ], ([_pattern] call RYD_GoLaunch)] call RYD_Spawn;
					diag_log format ["CLASHHALADD | dispatch | kind=%1 pattern=%2 unit=%3", _kind, _pattern, _chosen];
					_limit = _limit - 1;
					_committed = _committed + 1;
				};

				_avF = _avF - [_chosen];
			};
		} forEach _pool;
	};
} forEach _threatGroups;

_committed
