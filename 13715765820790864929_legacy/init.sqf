diag_log "ITW: init start";

if (!isDedicated) then {waitUntil {player == player};};
if ((!isServer) && (player != player)) then {waitUntil {player == player};};
isNil {call compile preprocessFileLineNumbers "params.sqf";}; 
waitUntil {! isNil "ITW_PreInitComplete"};

if (!isServer && !hasInterface) exitWith {};
waitUntil {!isNil "ITW_Params_complete"};
waitUntil {!isNil "ITW_ParamRadioVolume"};
0 fadeRadio ITW_ParamRadioVolume/10;

waitUntil {!isNil "ITW_ParamStamina"};
if (hasInterface && {ITW_ParamStamina < 2}) then {
    player enableStamina (ITW_ParamStamina == 1);
};

execVM "scripts\SKULL\SKL_RatingMinimum.sqf";

waitUntil {! isNil "ITW_ParamHeadlessClient"};
HeadlessClients = [];
if (isServer && ITW_ParamHeadlessClient == 1) then {execVM "scripts\SKULL\SKL_HeadlessClient.sqf"};

if (isNil "BIS_fnc_arsenal_campos_0") then {
    BIS_fnc_arsenal_campos_0 = [4,159,16.6,[0,0,0.85]];
};

if (isServer) then {
    // The SOF wrapper opens a two-function finalization window, runs the normal
    // corrected C.L.A.S.H./GTFO bootstrap, installs SOF hard anchor exclusion,
    // then closes/finalizes that window synchronously before HAL can schedule.
    if (fileExists "ITW_CLASH_SOFDoctrineBootstrap.sqf" && {
        fileExists "ITW_CLASH_Bootstrap.sqf"
    }) then {
        call compile preprocessFileLineNumbers "ITW_CLASH_SOFDoctrineBootstrap.sqf";
    } else {
        if (fileExists "ITW_CLASH_Bootstrap.sqf") then {
            call compile preprocessFileLineNumbers "ITW_CLASH_Bootstrap.sqf";
            diag_log "CLASH BOOT | WARNING | sof-doctrine-bootstrap-missing | canonical anchor behavior retained";
        } else {
            ITW_CLASH_BootstrapReady = false;
            ITW_CLASH_HookFallbacksActive = true;
            ITW_CLASH_fnc_ObserveGroup = {false};
            ITW_CLASH_fnc_ObserveWriter = {false};
            ITW_CLASH_fnc_ObserveLifecycle = {false};
            diag_log "CLASH BOOT | FAILED | bootstrap-file-missing | baseline Impasse remains active";
        };
    };

    // Dual-HAL / Checkbook loads synchronously after the canonical controller.
    // Impasse does not establish side identity until ITW_Start, so Commander B
    // preparation is intentionally deferred to Checkbook API V2's side binder.
    // Native RydHQInit later consumes leaderHQB without any HAL-core override.
    if (
        missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]
        && {missionNamespace getVariable ["ITW_CLASH_DualHALCheckbookPreInitReady",false]}
        && {fileExists "ITW_CLASH_DualHALCheckbook.sqf"}
    ) then {
        private _dualHALLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_DualHALCheckbook.sqf";
        if (_dualHALLoaded isEqualTo true) then {
            private _dualHALHardened = false;
            if (fileExists "ITW_CLASH_DualHALCheckbookHardening.sqf") then {
                _dualHALHardened = call compile preprocessFileLineNumbers "ITW_CLASH_DualHALCheckbookHardening.sqf";
            };
            private _checkbookAPIReady = false;
            if (_dualHALHardened isEqualTo true && {fileExists "ITW_CLASH_CheckbookAPI.sqf"}) then {
                _checkbookAPIReady = call compile preprocessFileLineNumbers "ITW_CLASH_CheckbookAPI.sqf";
            };

            private _forceGenerationReady = false;
            if (_checkbookAPIReady isEqualTo true && {fileExists "ITW_CLASH_ForceGeneration.sqf"}) then {
                _forceGenerationReady = call compile preprocessFileLineNumbers "ITW_CLASH_ForceGeneration.sqf";
            };
            private _halLogisticsLoaded = false;
            if (_forceGenerationReady isEqualTo true && {fileExists "ITW_CLASH_HALLogistics.sqf"}) then {
                _halLogisticsLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_HALLogistics.sqf";
            };
            private _playerTransportLoaded = false;
            if (_forceGenerationReady isEqualTo true && {
                fileExists "ITW_CLASH_PlayerTransportAuthority.sqf"
            }) then {
                _playerTransportLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_PlayerTransportAuthority.sqf";
            };
            private _playerTasksLoaded = false;
            if (_playerTransportLoaded isEqualTo true && {
                fileExists "ITW_CLASH_PlayerTaskSupport.sqf"
            }) then {
                _playerTasksLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_PlayerTaskSupport.sqf";
            };
            private _playerGarageLoaded = false;
            if (_forceGenerationReady isEqualTo true && {fileExists "ITW_CLASH_PlayerGarageDeployment.sqf"}) then {
                _playerGarageLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_PlayerGarageDeployment.sqf";
            };
            if (missionNamespace getVariable ["ITW_CLASH_CertificationMode",false] && {
                fileExists "ITW_CLASH_ArtilleryCertification.sqf"
            }) then {
                [] execVM "ITW_CLASH_ArtilleryCertification.sqf";
            };

            if (
                _dualHALHardened isEqualTo true
                && {_checkbookAPIReady isEqualTo true}
                && {_forceGenerationReady isEqualTo true}
                && {_halLogisticsLoaded isEqualTo true}
                && {_playerTransportLoaded isEqualTo true}
                && {_playerTasksLoaded isEqualTo true}
                && {_playerGarageLoaded isEqualTo true}
            ) then {
                diag_log format [
                    "CLASH BOOT | dual-hal-checkbook-deferred-ready | hardening=true capabilityAPI=v2 forceGeneration=%1 halLogistics=%2 playerTransport=%3 playerTasks=%4 playerGarage=%5 sideBinderOwnsCommanderB=true nativeCoreLaunchPending=true",
                    _forceGenerationReady,_halLogisticsLoaded,_playerTransportLoaded,_playerTasksLoaded,_playerGarageLoaded
                ];
            } else {
                diag_log format [
                    "CLASH BOOT | WARNING | dual-hal-checkbook-incomplete | hardening=%1 capabilityAPI=%2 forceGeneration=%3 halLogistics=%4 playerTransport=%5 playerTasks=%6 playerGarage=%7 runtime candidate blocked",
                    _dualHALHardened,_checkbookAPIReady,_forceGenerationReady,_halLogisticsLoaded,_playerTransportLoaded,_playerTasksLoaded,_playerGarageLoaded
                ];
            };
        } else {
            diag_log "CLASH BOOT | WARNING | dual-hal-checkbook-load-failed | preInit wrappers remain fail-open";
        };
    } else {
        diag_log format [
            "CLASH BOOT | WARNING | dual-hal-checkbook-skipped | bootstrap=%1 preInit=%2 file=%3",
            missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false],
            missionNamespace getVariable ["ITW_CLASH_DualHALCheckbookPreInitReady",false],
            fileExists "ITW_CLASH_DualHALCheckbook.sqf"
        ];
    };

    // Temporary hosted-test comms are intentionally observer-only and load
    // synchronously so recovery/recon state transitions can be mirrored without
    // wrapping any C.L.A.S.H. or HAL authority function.
    if (fileExists "ITW_CLASH_TestComms.sqf") then {
        private _testCommsLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_TestComms.sqf";
        if !(_testCommsLoaded isEqualTo true) then {
            diag_log "CLASH BOOT | test-comms-failed | continuing silently";
        };
    } else {
        diag_log "CLASH BOOT | test-comms-missing | continuing silently";
    };

    // Temporary forensic observer for HAL/Arma combat-state regressions. It is
    // behavior-neutral and waits for HAL readiness internally before sampling.
    if (fileExists "ITW_CLASH_CombatDiagnostics.sqf") then {
        [] execVM "ITW_CLASH_CombatDiagnostics.sqf";
    } else {
        diag_log "CLASH BOOT | combat-diagnostics-missing | continuing without forensic observer";
    };

    // Reconstitution and physical-movement corrections belong to preInit,
    // where ITW_Attack.sqf is actually compiled. Never retry them here after
    // those functions are final.
    if (missionNamespace getVariable ["ITW_CLASH_ReconstitutionPreInitReady",false]) then {
        diag_log "CLASH BOOT | reconstitution-preinit-authority-confirmed | late-overrides-skipped";
    } else {
        diag_log "CLASH BOOT | WARNING | reconstitution-preinit-authority-missing | baseline/fail-open functions retained";
    };
    if (missionNamespace getVariable ["ITW_CLASH_DualHALCheckbookPreInitReady",false]) then {
        diag_log "CLASH BOOT | dual-hal-checkbook-preinit-authority-confirmed | field handoff writers guarded";
    } else {
        diag_log "CLASH BOOT | WARNING | dual-hal-checkbook-preinit-authority-missing | Impasse field writers remain baseline";
    };
    if (missionNamespace getVariable ["ITW_CLASH_PhysicalMovementPreInitReady",false]) then {
        diag_log "CLASH BOOT | physical-movement-preinit-authority-confirmed | midBattleMoveUpTeleport=false initialStaging=true";
    } else {
        diag_log "CLASH BOOT | WARNING | physical-movement-preinit-authority-missing | baseline movement behavior retained";
    };
    if (missionNamespace getVariable ["ITW_CLASH_SpawnArchetypeAuthorityReady",false]) then {
        diag_log "CLASH BOOT | spawn-archetype-authority-confirmed | native enemy callback active";
    } else {
        diag_log "CLASH BOOT | WARNING | spawn-archetype-authority-missing | GetArchetype fallback remains active";
    };

    if (fileExists "ITW_CLASH_LogisticsGuard.sqf") then {
        [] execVM "ITW_CLASH_LogisticsGuard.sqf";
    } else {
        diag_log "CLASH BOOT | logistics-guard-missing | continuing without V6 handoff guard";
    };

    if (fileExists "ITW_CLASH_ReconObserver.sqf") then {
        [] spawn {
            waitUntil {
                sleep 0.25;
                missionNamespace getVariable ["ITW_CLASH_HALReady",false]
                || {missionNamespace getVariable ["ITW_GameOver",false]}
            };
            if (missionNamespace getVariable ["ITW_CLASH_HALReady",false]) then {
                [] execVM "ITW_CLASH_ReconObserver.sqf";
            };
        };
    } else {
        diag_log "CLASH BOOT | recon-phase0-missing | native HAL recon retained";
    };

    // Planning bridge does not assign reconnaissance. It temporarily exposes
    // recognized SOF to HAL's untouched native recon pools and restores SpecFor
    // identity immediately after each HQ planning call.
    if (missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]) then {
        if (fileExists "ITW_CLASH_ReconPlanningBridge.sqf") then {
            [] execVM "ITW_CLASH_ReconPlanningBridge.sqf";
        } else {
            diag_log "CLASH BOOT | recon-planning-bridge-missing | native SpecFor recon exclusion retained";
        };
    };

    if (fileExists "ITW_CLASH_CASEVAC.sqf") then {
        [] execVM "ITW_CLASH_CASEVAC.sqf";
        if (fileExists "ITW_CLASH_CASEVAC_AirOpsFix.sqf") then {
            [] execVM "ITW_CLASH_CASEVAC_AirOpsFix.sqf";
        } else {
            diag_log "CLASH BOOT | casevac-air-ops-fix-missing | CASEVAC remains fail-open";
        };
        if (fileExists "ITW_CLASH_CASEVAC_LZPadFix.sqf") then {
            [] execVM "ITW_CLASH_CASEVAC_LZPadFix.sqf";
        } else {
            diag_log "CLASH BOOT | casevac-lz-pad-fix-missing | coordinate landing remains active";
        };
        if (fileExists "ITW_CLASH_CASEVAC_HomeRTB.sqf") then {
            [] execVM "ITW_CLASH_CASEVAC_HomeRTB.sqf";
        } else {
            diag_log "CLASH BOOT | casevac-home-rtb-missing | support-corridor cleanup remains active";
        };
        if (fileExists "ITW_CLASH_GroundMEDEVAC.sqf") then {
            [] execVM "ITW_CLASH_GroundMEDEVAC.sqf";
            if (fileExists "ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf") then {
                [] execVM "ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf";
            } else {
                diag_log "CLASH BOOT | ground-medevac-vehicle-policy-missing | baseline vehicle ordering retained";
            };
        } else {
            diag_log "CLASH BOOT | ground-medevac-missing | CASEVAC/walking remain active";
        };
        if (fileExists "ITW_CLASH_EvacBoardingFix.sqf") then {
            [] execVM "ITW_CLASH_EvacBoardingFix.sqf";
        } else {
            diag_log "CLASH BOOT | evac-boarding-fix-missing | baseline physical boarding remains active";
        };
    } else {
        diag_log "CLASH BOOT | casevac-missing | walking withdrawal remains active";
    };

    // GTFO's synchronous bridge is installed by the bootstrap. Its runtime
    // adapter waits for Recon Phase 0 and the shared boarding helper so it can
    // enforce only cross-system authority boundaries once those surfaces exist.
    if (missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]) then {
        if (fileExists "ITW_CLASH_GTFO_Runtime.sqf") then {
            [] execVM "ITW_CLASH_GTFO_Runtime.sqf";
        } else {
            diag_log "CLASH BOOT | gtfo-runtime-missing | core HAL withdrawal bridge remains active without late guards";
        };
    };
};

[] execVM "ITW_Start.sqf";

diag_log "ITW: init complete";
