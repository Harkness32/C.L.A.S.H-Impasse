#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerDemandAmmoValidityHardeningStarted",false]) exitWith {true};

ITW_CLASH_PlayerDemandAmmoValidityHardeningStarted = true;
ITW_CLASH_PlayerDemandAmmoValidityHardeningReady = false;
ITW_CLASH_PlayerDemandAmmoValidityHardeningVersion = 1;

ITW_CLASH_PlayerDemandAmmoValidity_fnc_GroupNeedsAmmo = {
    params ["_hq","_group"];
    if (isNull _hq || {isNull _group}) exitWith {false};
    private _units = units _group select {alive _x};
    if (_units isEqualTo []) exitWith {false};

    private _ammoN = 0;
    {_ammoN = _ammoN + count magazines _x} forEach _units;
    private _recklessness = _hq getVariable ["RydHQ_Recklessness",0.5];
    private _averageLow = (
        _ammoN / ((count _units) + 0.1)
    ) < (6 / ((_recklessness * 2) + 1));
    private _nonCombatVehicleTypes = _hq getVariable ["RydHQ_NCVeh",[]];
    private _need = false;

    {
        private _unit = _x;
        private _assigned = assignedVehicle _unit;
        if (!isNull _assigned && {alive _assigned} && {!someAmmo _assigned}) then {
            if !((toLower typeOf _assigned) in _nonCombatVehicleTypes) then {
                if ((getPosATL _unit)#2 < 5) exitWith {_need = true};
            };
        };
        if (_need) exitWith {};

        if (vehicle _unit == _unit) then {
            private _weapons = weapons _unit;
            private _primaryEmpty = false;
            if (_weapons isNotEqualTo []) then {
                _primaryEmpty = (_unit ammo (_weapons#0)) == 0;
            };
            if (_primaryEmpty || {count magazines _unit < 2} || {_averageLow}) exitWith {
                _need = true;
            };
        };
    } forEach _units;
    _need
};

[] spawn {
    scriptName "ITW_CLASH_PlayerDemandAmmoValidityHardeningBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerDemandReservationHardeningReady",false]
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_StillValid"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-demand-ammo-validity-hardening-bind-timeout | base Hollow validity retained";
    };

    ITW_CLASH_PlayerDemandAmmoValidity_fnc_StillValidBase =
        ITW_CLASH_PlayerDemand_fnc_StillValid;
    ITW_CLASH_PlayerDemand_fnc_StillValid = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {false};
        if ((_demand getOrDefault ["kind",""]) != "LOGISTICS_AMMO") exitWith {
            _this call ITW_CLASH_PlayerDemandAmmoValidity_fnc_StillValidBase
        };

        private _state = _demand getOrDefault ["state",""];
        if (_state in ["COMPLETED","INVALID","FAILED"]) exitWith {false};
        private _hq = _demand getOrDefault ["hq",grpNull];
        private _target = _demand getOrDefault ["target",objNull];
        private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
        if (isNull _hq || {isNull _target} || {isNull _targetGroup}) exitWith {false};
        if (!alive _target) exitWith {false};

        // OPEN demand yields to an already-native-owned assignment. During a
        // player reservation, ASupportedG is intentionally not authority and
        // may be rewritten by SitRep or touched by a same-cycle native scan.
        if (_state == "OPEN" && {
            _targetGroup in (_hq getVariable ["RydHQ_ASupportedG",[]])
        }) exitWith {false};

        [_hq,_targetGroup] call
            ITW_CLASH_PlayerDemandAmmoValidity_fnc_GroupNeedsAmmo
    };

    ITW_CLASH_PlayerDemandAmmoValidityHardeningReady = true;
    diag_log format [
        "CLASH BOOT | player-demand-ammo-validity-hardening-ready | version=%1 reservedValidity=direct-native-equivalent hollowNotRequired=true",
        ITW_CLASH_PlayerDemandAmmoValidityHardeningVersion
    ];
};

true