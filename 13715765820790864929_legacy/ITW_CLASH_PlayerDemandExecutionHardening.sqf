#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerDemandExecutionHardeningStarted",false]) exitWith {true};

ITW_CLASH_PlayerDemandExecutionHardeningStarted = true;
ITW_CLASH_PlayerDemandExecutionHardeningReady = false;
ITW_CLASH_PlayerDemandExecutionHardeningVersion = 1;

[] spawn {
    scriptName "ITW_CLASH_PlayerDemandExecutionHardeningBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerDemandDispatchReady",false]
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_UpdateReserved"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_StillValid"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_Release"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_StartAmmoExecution"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_StartMedevacExecution"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-demand-execution-hardening-bind-timeout | base demand lifecycle retained";
    };

    // PREPARING/RESERVED still belongs to the demand layer: if the underlying
    // HAL requirement disappears before physical execution begins, release or
    // invalidate it normally. Once EXECUTING begins, the specialist executor
    // owns terminalization. A changing HAL array or recovering casualty must
    // not orphan an already-running sling or evacuation lifecycle.
    ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {};
        private _state = _demand getOrDefault ["state",""];
        if !(_state in ["RESERVED","EXECUTING"]) exitWith {};

        private _group = _demand getOrDefault ["reservedGroup",grpNull];

        if (_state == "RESERVED") exitWith {
            if !([_demandId] call ITW_CLASH_PlayerDemand_fnc_StillValid) exitWith {
                [_demandId,"underlying-demand-invalidated-before-execution",false] call
                    ITW_CLASH_PlayerDemand_fnc_Release;
            };
            if !([_group] call ITW_CLASH_PlayerDemand_fnc_HumanGroupAlive) exitWith {
                [_demandId,"player-group-unavailable-before-execution",false] call
                    ITW_CLASH_PlayerDemand_fnc_Release;
            };

            private _nextLog = _demand getOrDefault ["lastPreparingLogAt",0];
            if (time >= _nextLog) then {
                _demand set ["lastPreparingLogAt",time + 30];
                ITW_CLASH_PlayerDemands set [_demandId,_demand];
                ["player-demand-preparing",[
                    _demandId,
                    [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId,
                    _demand getOrDefault ["requirement",""]
                ]] call ITW_CLASH_PlayerDemand_fnc_Log;
            };

            switch (_demand getOrDefault ["kind",""]) do {
                case "LOGISTICS_AMMO": {
                    [_demandId] call ITW_CLASH_PlayerDemand_fnc_StartAmmoExecution;
                };
                case "MEDEVAC_SEVERE": {
                    [_demandId] call ITW_CLASH_PlayerDemand_fnc_StartMedevacExecution;
                };
            };
        };

        // EXECUTING is deliberately not revalidated against HAL demand arrays.
        // The specialist execution loop now owns success/failure/cancel. If the
        // human disappears, request a specialist-safe cancel rather than
        // deleting reservation state underneath the executor.
        if !([_group] call ITW_CLASH_PlayerDemand_fnc_HumanGroupAlive) then {
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_PlayerDemandCancel",true,true];
                switch (_demand getOrDefault ["kind",""]) do {
                    case "LOGISTICS_AMMO": {
                        if ((_group getVariable ["ITW_CLASH_PlayerAmmoJobId",""]) isNotEqualTo "") then {
                            _group setVariable ["ITW_CLASH_PlayerAmmoJobCancel",true,true];
                        };
                    };
                    case "MEDEVAC_SEVERE": {
                        // The MEDEVAC executor will wait for a safe grounded
                        // transfer state, unload surviving evacuees, then release.
                    };
                };
            };
            private _nextLog = _demand getOrDefault ["executionOwnerLossLogAt",0];
            if (time >= _nextLog) then {
                _demand set ["executionOwnerLossLogAt",time + 30];
                ITW_CLASH_PlayerDemands set [_demandId,_demand];
                ["player-demand-execution-owner-lost",[
                    _demandId,_demand getOrDefault ["kind",""],
                    if (isNull _group) then {"<null>"} else {
                        [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId
                    }
                ]] call ITW_CLASH_PlayerDemand_fnc_Log;
            };
        };
    };

    ITW_CLASH_PlayerDemandExecutionHardeningReady = true;
    diag_log format [
        "CLASH BOOT | player-demand-execution-hardening-ready | version=%1 preparingValidityOwnedByDemand=true executingTerminalOwnedBySpecialist=true safeOwnerLossCancel=true",
        ITW_CLASH_PlayerDemandExecutionHardeningVersion
    ];
};

true