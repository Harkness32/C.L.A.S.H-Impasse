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
// mid-battle infantry catch-up relocation is replaced. The dual-HAL/checkbook
// bridge also needs the three field handoff writers mutable so it can suppress
// Impasse tactical ownership only after the runtime commander layer is ready.
if (isServer) then {
    ITW_CLASH_DeferredFinalizers = [
        "ITW_AtkAiCount",
        "ITW_AtkBeginReconstitutionTransit",
        "ITW_AtkDispatchReconstitutionTransport",
        "ITW_AtkReconstitutionTransitManager",
        "ITW_AtkInfantryMoveUp",
        "ITW_AtkGetInfantryGroups",
        "ITW_AtkAddVehicle",
        "ITW_AtkEngageInfantry",
        "ITW_AtkEngageVehicle",
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

// Service crews are real battlefield entities, but they are not combat
// manpower. Impasse's native spawner compares an all-units side count against
// ITW_AtkAiCount, so increase only the cap by the number of explicitly exempt
// service crewmen. The native cap calculation itself remains authoritative.
private _capAccountingFixed = false;
if (isServer && {!isNil "ITW_AtkAiCount"}) then {
    ITW_CLASH_CapAccountingVersion = 1;
    ITW_CLASH_CapAccountingReady = false;
    ITW_CLASH_Cap_fnc_GroupIsExempt = {
        params ["_group"];
        if (isNull _group) exitWith {false};
        if (_group getVariable ["ITW_CLASH_CapExempt",false]) exitWith {true};
        if (_group getVariable ["ITW_CLASH_CASEVAC",false]) exitWith {true};
        if (_group getVariable ["ITW_CLASH_GroundMEDEVAC",false]) exitWith {true};
        private _leader = leader _group;
        if (isNull _leader) exitWith {false};
        private _veh = vehicle _leader;
        !isNull _veh && {
            _veh getVariable ["ITW_CLASH_CASEVAC",false] ||
            {_veh getVariable ["ITW_CLASH_GroundMEDEVAC",false]}
        }
    };
    ITW_CLASH_Cap_fnc_ExemptUnits = {
        params ["_side"];
        {
            alive _x && {
                side _x == _side && {
                    [group _x] call ITW_CLASH_Cap_fnc_GroupIsExempt
                }
            }
        } count allUnits
    };
    ITW_CLASH_Cap_fnc_NativeAtkAiCount = ITW_AtkAiCount;
    ITW_AtkAiCount = {
        private _isFriendly = _this;
        private _native = _isFriendly call ITW_CLASH_Cap_fnc_NativeAtkAiCount;
        if !(missionNamespace getVariable ["ITW_CLASH_CapAccountingReady",false]) exitWith {_native};
        private _side = if (_isFriendly) then {
            missionNamespace getVariable ["ITW_PlayerSide",west]
        } else {
            missionNamespace getVariable ["ITW_EnemySide",east]
        };
        _native + ([_side] call ITW_CLASH_Cap_fnc_ExemptUnits)
    };
    ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_AtkAiCount"];
    _capAccountingFixed = ["ITW_AtkAiCount"] call SKL_fnc_CompileFinal;
    ITW_CLASH_CapAccountingReady = _capAccountingFixed;
    diag_log format [
        "CLASH BOOT | cap-accounting-preinit | ready=%1 version=%2 serviceCrewsExempt=true combatManpowerNative=true",
        _capAccountingFixed,
        ITW_CLASH_CapAccountingVersion
    ];
};

// Install the fail-open field handoff wrappers while the attack writers are
// still mutable. Before the runtime dual-HAL layer is ready they delegate to
// baseline Impasse exactly; afterward they become the compatibility boundary.
private _dualHALCheckbookPreInitFixed = false;
if (isServer && {fileExists "ITW_CLASH_DualHALCheckbookPreInit.sqf"}) then {
    _dualHALCheckbookPreInitFixed = call compile preprocessFileLineNumbers "ITW_CLASH_DualHALCheckbookPreInit.sqf";
};

// Server-only persistent infantry authority filter. Baseline groups remain
// visible until C.L.A.S.H. is live; afterward HAL-managed field infantry on
// either supported side is removed from Impasse's tactical infantry-manager /
// defend-phase query surface.
private _infantryAuthorityPreInitFixed = false;
if (isServer && {fileExists "ITW_CLASH_InfantryAuthorityPreInit.sqf"}) then {
    _infantryAuthorityPreInitFixed = call compile preprocessFileLineNumbers "ITW_CLASH_InfantryAuthorityPreInit.sqf";
};

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

    if (!_capAccountingFixed) then {
        ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_AtkAiCount"];
        ["ITW_AtkAiCount"] call SKL_fnc_CompileFinal;
        diag_log "CLASH BOOT | cap-accounting-preinit-fallback | baseline AI cap finalized";
    };
    if (!_dispatchFixed) then {
        {
            ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - [_x];
            [_x] call SKL_fnc_CompileFinal;
        } forEach [
            "ITW_AtkBeginReconstitutionTransit",
            "ITW_AtkDispatchReconstitutionTransport"
        ];
        diag_log "CLASH BOOT | preinit-reconstitution-dispatch-fallback | baseline origin/dispatch finalized";
    };
    if (!_transitFixed) then {
        ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_AtkReconstitutionTransitManager"];
        ["ITW_AtkReconstitutionTransitManager"] call SKL_fnc_CompileFinal;
        diag_log "CLASH BOOT | preinit-reconstitution-transit-fallback | baseline finalized";
    };
    if (!_dualHALCheckbookPreInitFixed) then {
        {
            ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - [_x];
            [_x] call SKL_fnc_CompileFinal;
        } forEach [
            "ITW_AtkAddVehicle",
            "ITW_AtkEngageInfantry",
            "ITW_AtkEngageVehicle"
        ];
        diag_log "CLASH BOOT | dual-hal-checkbook-preinit-fallback | baseline field writers finalized";
    };
    if (!_physicalMovementFixed) then {
        ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_AtkInfantryMoveUp"];
        ["ITW_AtkInfantryMoveUp"] call SKL_fnc_CompileFinal;
        diag_log "CLASH BOOT | physical-movement-fallback | baseline move-up teleport finalized";
    };
    if (!_infantryAuthorityPreInitFixed) then {
        ITW_CLASH_DeferredFinalizers = ITW_CLASH_DeferredFinalizers - ["ITW_AtkGetInfantryGroups"];
        ["ITW_AtkGetInfantryGroups"] call SKL_fnc_CompileFinal;
        diag_log "CLASH BOOT | infantry-authority-preinit-fallback | baseline infantry manager query finalized";
    };

    ITW_CLASH_ReconstitutionPreInitReady = _dispatchFixed && _transitFixed;
    ITW_CLASH_DualHALCheckbookPreInitReady = _dualHALCheckbookPreInitFixed;
    ITW_CLASH_PhysicalMovementPreInitReady = _physicalMovementFixed;
    ITW_CLASH_InfantryAuthorityPreInitReady = _infantryAuthorityPreInitFixed;
    ITW_CLASH_CapAccountingReady = _capAccountingFixed;
    diag_log format [
        "CLASH BOOT | reconstitution-preinit-authority | ready=%1 dispatch=%2 transit=%3",
        ITW_CLASH_ReconstitutionPreInitReady,
        _dispatchFixed,
        _transitFixed
    ];
    diag_log format [
        "CLASH BOOT | dual-hal-checkbook-preinit-authority | ready=%1 fieldHandoff=%2",
        ITW_CLASH_DualHALCheckbookPreInitReady,
        _dualHALCheckbookPreInitFixed
    ];
    diag_log format [
        "CLASH BOOT | physical-movement-preinit-authority | ready=%1",
        ITW_CLASH_PhysicalMovementPreInitReady
    ];
    diag_log format [
        "CLASH BOOT | infantry-authority-preinit | ready=%1 managerFilter=%2",
        ITW_CLASH_InfantryAuthorityPreInitReady,
        _infantryAuthorityPreInitFixed
    ];
    diag_log format [
        "CLASH BOOT | cap-accounting-authority | ready=%1",
        ITW_CLASH_CapAccountingReady
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
isNil {call compile preprocessFileLineNumbers "ITW_Objectives.sqf";             };
isNil {call compile preprocessFileLineNumbers "ITW_RallyPoint.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_Radio.sqf";                  };
isNil {call compile preprocessFileLineNumbers "ITW_Save.sqf";                   };
isNil {call compile preprocessFileLineNumbers "ITW_Targets.sqf";                };
isNil {call compile preprocessFileLineNumbers "ITW_Teammates.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_Vehicles.sqf";               };
isNil {call compile preprocessFileLineNumbers "ITW_VehRepair.sqf";              };
isNil {call compile preprocessFileLineNumbers "ITW_Warship.sqf";                };
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