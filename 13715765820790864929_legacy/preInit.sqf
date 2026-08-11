
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
isNil {call compile preprocessFileLineNumbers "ITW_Airfield.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_Ally.sqf";                  };
isNil {call compile preprocessFileLineNumbers "ITW_Attack.sqf";                };
isNil {call compile preprocessFileLineNumbers "ITW_Base.sqf";                  };
isNil {call compile preprocessFileLineNumbers "ITW_BaseEra.sqf";               };
isNil {call compile preprocessFileLineNumbers "ITW_Bombardment.sqf";           };
isNil {call compile preprocessFileLineNumbers "ITW_Enemy.sqf";                 };
isNil {call compile preprocessFileLineNumbers "ITW_Fortifications.sqf";        };
isNil {call compile preprocessFileLineNumbers "ITW_Functions.sqf";             };
isNil {call compile preprocessFileLineNumbers "ITW_Garage.sqf";                };
isNil {call compile preprocessFileLineNumbers "ITW_Garrison.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_SideOps.sqf";               };
isNil {call compile preprocessFileLineNumbers "ITW_Objectives.sqf";            };
isNil {call compile preprocessFileLineNumbers "ITW_RallyPoint.sqf";            };
isNil {call compile preprocessFileLineNumbers "ITW_Radio.sqf";                 };
isNil {call compile preprocessFileLineNumbers "ITW_Save.sqf";                  };
isNil {call compile preprocessFileLineNumbers "ITW_Targets.sqf";               };
isNil {call compile preprocessFileLineNumbers "ITW_Teammates.sqf";             };
isNil {call compile preprocessFileLineNumbers "ITW_Vehicles.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_VehRepair.sqf";             };
isNil {call compile preprocessFileLineNumbers "ITW_Warship.sqf";               };
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

diag_log "ITW: preInit complete";
if (isServer) then {
    ITW_PreInitComplete = true;
    publicVariable "ITW_PreInitComplete";
};

// recommended if running bCombat mod on large scale battles
bcombat_cqb_radar = false;
bcombat_allow_hearing = false;