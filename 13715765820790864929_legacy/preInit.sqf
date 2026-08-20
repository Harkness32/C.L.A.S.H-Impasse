diag_log "ITW: preInit start";
if (isNil "SKL_fnc_CompileFinal") then {SKL_fnc_CompileFinal = compileFinal preprocessFileLineNumbers "scripts\SKULL\SKL_CompileFinal.sqf"};
SKL_CF_DEBUG_ENABLE = false; // set to true to enable function debug (and run arma with -debug)

// C.L.A.S.H. hooks must never be allowed to break baseline Impasse.
// These no-op shims are replaced by the real controller after the validated
// server bootstrap runs from init.sqf.
ITW_CLASH_BootstrapReady = false;
ITW_CLASH_HookFallbacksActive = true;
ITW_CLASH_fnc_ObserveGroup = {false};
ITW_CLASH_fnc_ObserveWriter = {false};
ITW_CLASH_fnc_ObserveLifecycle = {false};
diag_log "CLASH BOOT | preInit | fail-open hooks installed; controller deferred to init";

// Attack and enemy source are compiled during preInit, before init.sqf can run.
// Keep only the functions that C.L.A.S.H. must replace mutable on the server.
// Initial SafeMove/vehicle staging remains baseline Impasse; only the explicit
// mid-battle infantry catch-up relocation is replaced.
if (isServer) then {
    ITW_CLASH_DeferredFinalizers = [
        "ITW_AtkDispatchReconstitutionTransport",
        "ITW_AtkReconstitutionTransitManager",
        "ITW_AtkInfantryMoveUp",
        "ITW_EnemyGroupCallback"
    ];
    diag_log format [
        "CLASH BOOT | preinit-finalization-window | deferred=%1",
        ITW_CLASH_DeferredFinalizers
    ];
} else {
    ITW_CLASH_DeferredFinalizers = [];
};

isNil {call compile preprocessFileLineNumbers "ITW_Airfield.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_Ally.sqf";                  };
isNil {call compile preprocessFileLineNumbers "ITW_Attack.sqf";                };

// Load the narrow physical-movement shim on every machine. Clients/HCs only
// install the locality helper; the server replaces/finalizes InfantryMoveUp
// while its explicit finalization window is still open.
private _physicalMovementFixed = false;
if (fileExists "ITW_CLASH_PhysicalMovementPreInit.sqf") then {
    _physicalMovementFixed = call compile preprocessFileLineNumbers "ITW_CLASH_PhysicalMovementPreInit.sqf";
};

// The canonical Attack definitions now exist and the selected finalizers were
// skipped. Install/finalize the corrected functions synchronously while we are
// still in preInit, before any gameplay coroutine can start.
if (isServer) then {
    private _dispatchFixed = false;
    private _transitFixed = false;
    if (fileExists "ITW_CLASH_ReconstitutionDispatchFix.sqf") then {
        _dispatchFixed = call compile preprocessFileLineNumbers "ITW_CLASH_ReconstitutionDispatchFix.sqf";
    };
    if (fileExists "ITW_CLASH_ReconstitutionTransitFix.sqf") then {
        _transitFixed = call compile preprocessFileLineNumbers "ITW_CLASH_ReconstitutionTransitFix.sqf";
    };

    if (!_dispatchFixed) then {
        ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_AtkDispatchReconstitutionTransport"];
        ["ITW_AtkDispatchReconstitutionTransport"] call SKL_fnc_CompileFinal;
        diag_log "CLASH BOOT | preinit-reconstitution-dispatch-fallback | baseline finalized";
    };
    if (!_transitFixed) then {
        ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_AtkReconstitutionTransitManager"];
        ["ITW_AtkReconstitutionTransitManager"] call SKL_fnc_CompileFinal;
        diag_log "CLASH BOOT | preinit-reconstitution-transit-fallback | baseline finalized";
    };
    if (!_physicalMovementFixed) then {
        ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_AtkInfantryMoveUp"];
        ["ITW_AtkInfantryMoveUp"] call SKL_fnc_CompileFinal;
        diag_log "CLASH BOOT | physical-movement-fallback | baseline move-up teleport finalized";
    };

    ITW_CLASH_ReconstitutionPreInitReady = _dispatchFixed && _transitFixed;
    ITW_CLASH_PhysicalMovementPreInitReady = _physicalMovementFixed;
    diag_log format [
        "CLASH BOOT | reconstitution-preinit-authority | ready=%1 dispatch=%2 transit=%3",
        ITW_CLASH_ReconstitutionPreInitReady,
        _dispatchFixed,
        _transitFixed
    ];
    diag_log format [
        "CLASH BOOT | physical-movement-preinit-authority | ready=%1",
        ITW_CLASH_PhysicalMovementPreInitReady
    ];
};

isNil {call compile preprocessFileLineNumbers "ITW_Base.sqf";                  };
isNil {call compile preprocessFileLineNumbers "ITW_BaseEra.sqf";               };
isNil {call compile preprocessFileLineNumbers "ITW_Bombardment.sqf";           };
isNil {call compile preprocessFileLineNumbers "ITW_Enemy.sqf";                 };

// Capture the true native Impasse group template at the enemy callback. This is
// intentionally after ITW_Enemy.sqf defines its callback but before gameplay.
if (isServer) then {
    private _archetypeFixed = false;
    if (fileExists "ITW_CLASH_SpawnArchetypePreInit.sqf") then {
        _archetypeFixed = call compile preprocessFileLineNumbers "ITW_CLASH_SpawnArchetypePreInit.sqf";
    };
    if (!_archetypeFixed) then {
        ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_EnemyGroupCallback"];
        ["ITW_EnemyGroupCallback"] call SKL_fnc_CompileFinal;
        diag_log "CLASH BOOT | spawn-archetype-preinit-fallback | baseline callback finalized";
    };
    ITW_CLASH_SpawnArchetypeAuthorityReady = _archetypeFixed;
};

isNil {call compile preprocessFileLineNumbers "ITW_Fortifications.sqf";         };
isNil {call compile preprocessFileLineNumbers "ITW_Functions.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_Garage.sqf";                 };
isNil {call compile preprocessFileLineNumbers "ITW_Garrison.sqf";               };
isNil {call compile preprocessFileLineNumbers "ITW_SideOps.sqf";                };
isNil {call compile preprocessFileLineNumbers "ITW_Objectives.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_RallyPoint.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_Radio.sqf";                   };
isNil {call compile preprocessFileLineNumbers "ITW_Save.sqf";                    };
isNil {call compile preprocessFileLineNumbers "ITW_Targets.sqf";                 };
isNil {call compile preprocessFileLineNumbers "ITW_Teammates.sqf";               };
isNil {call compile preprocessFileLineNumbers "ITW_Vehicles.sqf";                };
isNil {call compile preprocessFileLineNumbers "ITW_VehRepair.sqf";               };
isNil {call compile preprocessFileLineNumbers "ITW_Warship.sqf";                 };
isNil {call compile preprocessFileLineNumbers "CustomArsenal\CustomArsenal.sqf";};
isNil {call compile preprocessFileLineNumbers "scripts\Factions\Factions.sqf";  };
isNil {call compile preprocessFileLineNumbers "scripts\Dlcs\DlcSelect.sqf";     };
isNil {call compile preprocessFileLineNumbers "scripts\Skull\SKL_BoundaryLines.sqf";};
isNil {call compile preprocessFileLineNumbers "scripts\Skull\SKL_BlackFishCircle.sqf";};
isNil {call compile preprocessFileLineNumbers "scripts\Skull\SKL_HeliExtract.sqf";};
isNil {call compile preprocessFileLineNumbers "scripts\SKULL\SKL_TeamSwitch.sqf";};
isNil {call compile preprocessFileLineNumbers "scripts\Skull\SKL_TruckExtract.sqf";};
isNil {call compile preprocessFileLineNumbers "scripts\Skull\SKL_TruckService.sqf";};
isNil {call compile preprocessFileLineNumbers "scripts\VehicleChooser\VehicleChooser.sqf";};
SKL_CF_DEBUG_ENABLE = false;

if (isServer && {ITW_CLASH_DeferredFinalizers isNotEqualTo []}) then {
    diag_log format [
        "CLASH BOOT | WARNING | stale-preinit-finalizers-cleared | %1",
        ITW_CLASH_DeferredFinalizers
    ];
    ITW_CLASH_DeferredFinalizers = [];
};

diag_log "ITW: preInit complete";
if (isServer) then {
    ITW_PreInitComplete = true;
    publicVariable "ITW_PreInitComplete";
};

// recommended if running bCombat mod on large scale battles
bcombat_cqb_radar = false;
bcombat_allow_hearing = false;
