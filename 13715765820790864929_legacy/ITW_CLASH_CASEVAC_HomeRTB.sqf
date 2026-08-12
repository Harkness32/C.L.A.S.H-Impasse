#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_CASEVAC_HomeRTBStarted",false]) exitWith {};
ITW_CLASH_CASEVAC_HomeRTBStarted = true;

// CASEVAC is loaded with execVM, so wait for its public cleanup function before
// wrapping it.  This changes only the successful-extraction cleanup signature
// (the current 15 second path); failure/abort cleanup keeps its original rules.
waitUntil {
    sleep 0.1;
    !isNil "ITW_CLASH_CASEVAC_fnc_CleanupHeli" && {
        !isNil "ITW_CLASH_CASEVAC_fnc_SendHeliHome"
    }
};

ITW_CLASH_CASEVAC_fnc_CleanupHeli_V1Base = ITW_CLASH_CASEVAC_fnc_CleanupHeli;

ITW_CLASH_CASEVAC_fnc_GetEnemyHomeSpawn = {
    if (isNil "ITW_Zones" || {
        isNil "ITW_Objectives" || {
            isNil "ITW_Bases" || {ITW_Zones isEqualTo []}
        }
    }) exitWith {[]};

    private _homeZone = ITW_Zones#-1;
    if (_homeZone isEqualTo []) exitWith {[]};
    private _homeObjectiveIndex = _homeZone#0;
    if (_homeObjectiveIndex < 0 || {
        _homeObjectiveIndex >= count ITW_Objectives
    }) exitWith {[]};

    private _homeObjective = ITW_Objectives#_homeObjectiveIndex;
    private _homeBaseIndex = _homeObjective#ITW_OBJ_INDEX;
    if (_homeBaseIndex < 0 || {_homeBaseIndex >= count ITW_Bases}) exitWith {[]};

    private _homeBase = ITW_Bases#_homeBaseIndex;
    private _homePos = +(_homeBase#ITW_BASE_A_SPAWN);
    private _source = "enemy-home-ai-spawn";

    if (_homePos isEqualTo []) then {
        _homePos = +(_homeObjective#ITW_OBJ_V_SPAWN);
        _source = "enemy-home-vehicle-spawn";
    };
    if (_homePos isEqualTo []) then {
        _homePos = +(_homeBase#ITW_BASE_POS);
        _source = "enemy-home-base";
    };
    if (_homePos isEqualTo []) exitWith {[]};
    if (count _homePos < 3) then {_homePos pushBack 0};

    [_homePos,_homeObjectiveIndex,_homeBaseIndex,_source]
};

ITW_CLASH_CASEVAC_fnc_CleanupHeli = {
    params ["_heli","_crewGroup",["_delay",10]];

    // Successful CASEVAC currently calls cleanup with 15 seconds. Instead of
    // disappearing over the support corridor, point the empty helicopter back
    // toward Impasse's canonical enemy home AI spawn, let it visibly depart for
    // ten seconds, then remove it. Other cleanup paths remain unchanged.
    if (_delay == 15 && {
        !isNull _heli && {alive _heli} && {!isNull _crewGroup}
    }) exitWith {
        private _home = call ITW_CLASH_CASEVAC_fnc_GetEnemyHomeSpawn;
        if (_home isNotEqualTo []) then {
            _home params ["_homePos","_homeObjectiveIndex","_homeBaseIndex","_source"];
            [_heli,_crewGroup,_homePos] call ITW_CLASH_CASEVAC_fnc_SendHeliHome;
            if (!isNil "ITW_CLASH_CASEVAC_fnc_Log") then {
                ["cleanup-egress",[
                    typeOf _heli,
                    _homeObjectiveIndex,
                    _homeBaseIndex,
                    _source,
                    round (_heli distance2D _homePos),
                    10
                ]] call ITW_CLASH_CASEVAC_fnc_Log;
            };
        } else {
            if (!isNil "ITW_CLASH_CASEVAC_fnc_Log") then {
                ["cleanup-egress",[typeOf _heli,-1,-1,"home-unresolved",-1,10]] call ITW_CLASH_CASEVAC_fnc_Log;
            };
        };

        [_heli,_crewGroup] spawn {
            params ["_heli","_crewGroup"];
            sleep 10;
            if (!isNull _heli) then {
                deleteVehicleCrew _heli;
                deleteVehicle _heli;
            };
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {
                deleteGroup _crewGroup;
            };
        };
    };

    _this call ITW_CLASH_CASEVAC_fnc_CleanupHeli_V1Base;
};

diag_log "CLASH BOOT | casevac-home-rtb-ready | version=1 cleanup=10";