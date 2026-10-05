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

            // All unavoidable Commander A/B adaptation lives in one parity
            // layer. Shared systems remain symmetric in their own source; we
            // never bolt on behavior-specific BLUFOR fix files.
            private _commanderParityLoaded = false;
            if (_dualHALHardened isEqualTo true && {
                fileExists "ITW_CLASH_CommanderParity.sqf"
            }) then {
                _commanderParityLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_CommanderParity.sqf";
            } else {
                diag_log "CLASH BOOT | commander-parity-missing-or-prereq-failed | Commander B parity extensions unavailable";
            };

            private _crewRemnantCleanupLoaded = false;
            if (_commanderParityLoaded isEqualTo true && {
                fileExists "ITW_CLASH_CrewRemnantCleanup.sqf"
            }) then {
                _crewRemnantCleanupLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_CrewRemnantCleanup.sqf";
            } else {
                diag_log "CLASH BOOT | crew-remnant-cleanup-missing-or-prereq-failed | orphan vehicle crews remain native";
            };

            private _checkbookAPIReady = false;
            if (_dualHALHardened isEqualTo true && {fileExists "ITW_CLASH_CheckbookAPI.sqf"}) then {
                _checkbookAPIReady = call compile preprocessFileLineNumbers "ITW_CLASH_CheckbookAPI.sqf";
            };

            private _forceGenerationReady = false;
            if (_checkbookAPIReady isEqualTo true && {fileExists "ITW_CLASH_ForceGeneration.sqf"}) then {
                _forceGenerationReady = call compile preprocessFileLineNumbers "ITW_CLASH_ForceGeneration.sqf";
            };
            // Phase-0 front routing is intentionally shadow-only. It derives
            // side-symmetric primary/alternate FOB lanes from the live Impasse
            // graph and publishes the commander's current selection without
            // changing any spawn or tactical movement authority.
            private _frontRoutingLoaded = false;
            if (
                _forceGenerationReady isEqualTo true
                && {_commanderParityLoaded isEqualTo true}
                && {fileExists "ITW_CLASH_FrontRouting.sqf"}
            ) then {
                _frontRoutingLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_FrontRouting.sqf";
            } else {
                diag_log "CLASH BOOT | front-routing-missing-or-prereq-failed | fixed Impasse generation graph retained";
            };

            private _vehicleEchelonLoaded = false;
            if (_forceGenerationReady isEqualTo true && {
                fileExists "ITW_CLASH_VehicleEchelonPolicy.sqf"
            }) then {
                _vehicleEchelonLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_VehicleEchelonPolicy.sqf";
            } else {
                diag_log "CLASH BOOT | vehicle-echelon-policy-missing-or-prereq-failed | native field staging/recovery retained";
            };

            private _roadDistanceLoaded = false;
            if (fileExists "ITW_CLASH_RoadDistance.sqf") then {
                _roadDistanceLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_RoadDistance.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | road-distance-missing | dispatch distance checks fall back to straight-line";
            };
            private _halLogisticsLoaded = false;
            if (_forceGenerationReady isEqualTo true && {fileExists "ITW_CLASH_HALLogistics.sqf"}) then {
                _halLogisticsLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_HALLogistics.sqf";
            };
            // The loud debugger: mirrors air and budget decisions to in-game
            // chat in plain language. Off by default, and loaded before the
            // modules that feed it so none of them misses an event.
            if (fileExists "ITW_CLASH_LoudDebug.sqf") then {
                call compile preprocessFileLineNumbers "ITW_CLASH_LoudDebug.sqf";
            } else {
                diag_log "CLASH BOOT | loud-debug-missing | air and budget decisions stay in the RPT only";
            };
            // The air picture: observation only, on a 5-second clock, plus the
            // classification every later reader asks it for. HAL's own cycle is
            // far too slow for a jet over the rear.
            private _airPictureLoaded = false;
            if (fileExists "ITW_CLASH_AirPicture.sqf") then {
                _airPictureLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_AirPicture.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | air-picture-missing | enemy air is seen only at HAL's own cycle rate";
            };
            // Who gets to be the enemy's air defence. VehicleArrays.sqf:723
            // hand-whitelists B_APC_Tracked_01_AA_F into the ENEMY AA list, so
            // on a mission whose enemy order of battle is NATO - GUER here -
            // every SPAA spawn and respawn was a BLUFOR vehicle. Reranks the
            // enemy's own lists on real anti-air capability, preferring a hull
            // of their own side. Loaded before the two readers below, though it
            // waits on VehicleArrays either way.
            if (_airPictureLoaded isEqualTo true && {fileExists "ITW_CLASH_AirDefenceRoster.sqf"}) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_AirDefenceRoster.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | air-defence-roster-missing-or-prereq-failed | enemy AA classes stay as Impasse composed them, cross-side hulls included";
            };
            // The Emerging Threats Budget: a separate wallet per commander on
            // top of Impasse, so a threat counter no longer competes with
            // Impasse's own spawner for the same row tickets.
            private _etbLoaded = false;
            if (_forceGenerationReady isEqualTo true && {fileExists "ITW_CLASH_EmergingThreatsBudget.sqf"}) then {
                _etbLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_EmergingThreatsBudget.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | etb-missing-or-prereq-failed | threat counters keep competing for Impasse tickets";
            };
            private _halThreatCoverageLoaded = false;
            if (_forceGenerationReady isEqualTo true && {fileExists "ITW_CLASH_HALThreatCoverage.sqf"}) then {
                _halThreatCoverageLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_HALThreatCoverage.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | hal-threat-coverage-missing-or-prereq-failed | AAInf/StaticAA/StaticAT/Support/Cargo threats remain unrequested";
            };
            // COLOSSUS: the strategy layer. v0 builds the ground picture and
            // logs the push it would commit; it issues no orders at all.
            if (
                _forceGenerationReady isEqualTo true
                && {fileExists "ITW_CLASH_Colossus.sqf"}
            ) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_Colossus.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | colossus-missing-or-prereq-failed | no ground picture, no strategy layer";
            };
            // Shoot and scoot, and counter-battery acquisition. Each is the
            // other's counterplay: a fix is taken on where a gun was, and a gun
            // that displaces leaves that fix stale.
            if (fileExists "ITW_CLASH_CounterBattery.sqf") then {
                call compile preprocessFileLineNumbers "ITW_CLASH_CounterBattery.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | counter-battery-missing | shelling never reveals a firing position";
            };
            if (fileExists "ITW_CLASH_ArtilleryScoot.sqf") then {
                call compile preprocessFileLineNumbers "ITW_CLASH_ArtilleryScoot.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | artillery-scoot-missing | gun lines fire from one grid square all mission";
            };
            // SPAA overwatch: every air defence vehicle on a side, the ETB's
            // and Impasse's alike, stays behind the front instead of being
            // dispatched forward as another armored group.
            private _spaaOverwatchLoaded = false;
            if (_airPictureLoaded isEqualTo true && {fileExists "ITW_CLASH_SPAAOverwatch.sqf"}) then {
                _spaaOverwatchLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_SPAAOverwatch.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | spaa-overwatch-missing-or-prereq-failed | HAL keeps dispatching SPAA forward";
            };
            // HAL taxonomy: what HAL thinks each class IS. The curated
            // RYD_WS_* lists missed 15 of the 61 classes run4 fielded, the
            // Rooikat among them; CLASH seeds the buckets it already decides
            // for itself, which also suppresses the autofill for those.
            if (_airPictureLoaded isEqualTo true && {fileExists "ITW_CLASH_HALTaxonomy.sqf"}) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_HALTaxonomy.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | hal-taxonomy-missing-or-prereq-failed | HAL classifies vehicles from its own config heuristics alone";
            };
            // Rear-base C-RAM: a fixed, learnable no-go zone for air about 3 km
            // around each side's rear base, so a jet loitering over the rear is
            // covered instead of buying a fighter.
            if (_airPictureLoaded isEqualTo true && {fileExists "ITW_CLASH_RearBaseCRAM.sqf"}) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_RearBaseCRAM.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | rear-base-cram-missing-or-prereq-failed | rear bases have no air defence";
            };
            // AA teams garrison FOBs: HAL's garrison routine digs a group in
            // where it already stands, so nothing ever sent one to a FOB.
            if (_halThreatCoverageLoaded isEqualTo true && {fileExists "ITW_CLASH_FOBAirDefence.sqf"}) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_FOBAirDefence.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | fob-air-defence-missing-or-prereq-failed | AA squads stay where they spawned";
            };
            // HAL front: each commander's dispatcher answers threats only where
            // that side has something in play; SF raids ignore it.
            private _halFrontLoaded = false;
            if (_forceGenerationReady isEqualTo true && {fileExists "ITW_CLASH_HALFront.sqf"}) then {
                _halFrontLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_HALFront.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | hal-front-missing-or-prereq-failed | HAL answers threats anywhere on the map";
            };
            // HAL's dispatcher measures an aircraft's AA risk against the
            // nearest AT threat. Patched in the compiled function's own text,
            // so it has to wait for HAL's runtime bind: scheduled, like the
            // native SF fix, and logs a warning if the anchor no longer matches.
            if (fileExists "ITW_CLASH_HALDispatcherAAFix.sqf") then {
                [] execVM "ITW_CLASH_HALDispatcherAAFix.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | hal-dispatcher-aa-fix-missing | HAL keeps measuring air risk against AT threats";
            };
            // HAL rejects an air lift on a coin flip whenever it knows of any
            // air or AA threat anywhere on the map. Patched in SCargo's own
            // source to ask about the route instead; scheduled, because it has
            // to wait for HAL's bind and for the Checkbook's cargo hook.
            // HAL drops a capture waypoint when _wp0 is undefined, so the
            // group silently never goes. Stock HAL, but only hit now that the
            // recon latch has capture orders being issued at all. Scheduled,
            // like the other runtime patches.
            if (fileExists "ITW_CLASH_HALWaypointGuardFix.sqf") then {
                [] execVM "ITW_CLASH_HALWaypointGuardFix.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | hal-waypoint-guard-missing | HAL may drop capture waypoints on an undefined _wp0";
            };
            // HAL's AT-risk resignation only ever runs for armour groups, so a
            // soft-skinned vehicle is dispatched at a known tank with no risk
            // check at all. Appends a CLASH-maintained list of soft-mounted
            // groups to that one test; scheduled, like the other runtime patch.
            if (fileExists "ITW_CLASH_HALDispatcherSoftArmorFix.sqf") then {
                [] execVM "ITW_CLASH_HALDispatcherSoftArmorFix.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | hal-soft-armor-fix-missing | soft vehicles keep driving at armor";
            };
            if (fileExists "ITW_CLASH_HALCargoDiceFix.sqf") then {
                [] execVM "ITW_CLASH_HALCargoDiceFix.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | hal-cargo-dice-fix-missing | troop lifts stay a map-wide dice roll";
            };
            private _infantryDemandLoaded = false;
            if (fileExists "ITW_CLASH_InfantryDemand.sqf") then {
                _infantryDemandLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_InfantryDemand.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | infantry-demand-missing | native random squad-template selection retained";
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
            private _ammoDispatchLoaded = false;
            if (_playerTasksLoaded isEqualTo true && {
                fileExists "ITW_CLASH_AmmoDispatch.sqf"
            }) then {
                _ammoDispatchLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_AmmoDispatch.sqf";
            } else {
                diag_log "CLASH BOOT | ammo-dispatch-missing-or-prereq-failed | native ammo dispatch retained";
            };

            private _thunderRunLoaded = false;
            if (_ammoDispatchLoaded isEqualTo true && {
                fileExists "ITW_CLASH_ThunderRun.sqf"
            }) then {
                _thunderRunLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_ThunderRun.sqf";
            } else {
                diag_log "CLASH BOOT | thunder-run-missing-or-prereq-failed | native ammo air delivery retained";
            };

            // HotDrop: the troop-insertion profile. Separate from the
            // logistics Thunder Run - it borrows the flare machinery and the
            // corridor, and owns its own entry, phases and release.
            if (
                _airPictureLoaded isEqualTo true
                && {fileExists "ITW_CLASH_HotDrop.sqf"}
            ) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_HotDrop.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | hot-drop-missing-or-prereq-failed | troop lifts fly HAL's own profile into hot LZs";
            };

            // Helicopter threat tiers over Thunder Run's air denial: only a
            // system built to kill aircraft closes a route. Loads last so it
            // wraps the enhancement layer's classifier, and only ever relaxes.
            if (
                _thunderRunLoaded isEqualTo true
                && {_airPictureLoaded isEqualTo true}
                && {fileExists "ITW_CLASH_ThunderRunAirTiers.sqf"}
            ) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_ThunderRunAirTiers.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | thunder-run-air-tiers-missing-or-prereq-failed | an unarmed enemy transport still grounds a resupply run";
            };

            private _playerGarageLoaded = false;
            if (_forceGenerationReady isEqualTo true && {fileExists "ITW_CLASH_PlayerGarageDeployment.sqf"}) then {
                _playerGarageLoaded = call compile preprocessFileLineNumbers "ITW_CLASH_PlayerGarageDeployment.sqf";
            };
            private _playerArtilleryLoaded = false;
            if (
                _playerTasksLoaded isEqualTo true
                && {_playerGarageLoaded isEqualTo true}
                && {fileExists "ITW_CLASH_PlayerArtilleryTasks.sqf"}
            ) then {
                _playerArtilleryLoaded = call compile preprocessFileLineNumbers
                    "ITW_CLASH_PlayerArtilleryTasks.sqf";
            };

            // Demand-first employment is a post-hardening policy layer. It
            // installs asynchronously after PlayerTaskStateHardening has bound
            // its admission/cancel/artillery surfaces, so this synchronous load
            // cannot race those existing guards. Native interceptors then wait
            // for both the demand layer and PlayerTaskSupport's HAL binder.
            if (_playerTasksLoaded isEqualTo true && {
                _ammoDispatchLoaded isEqualTo true
            } && {
                _playerArtilleryLoaded isEqualTo true
            } && {fileExists "ITW_CLASH_PlayerDemandDispatch.sqf"}) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_PlayerDemandDispatch.sqf";
                if (fileExists "ITW_CLASH_PlayerDemandNativeInterceptors.sqf") then {
                    call compile preprocessFileLineNumbers "ITW_CLASH_PlayerDemandNativeInterceptors.sqf";
                } else {
                    diag_log "CLASH BOOT | player-demand-native-interceptors-missing | demand ledger remains fail-open";
                };
            } else {
                diag_log "CLASH BOOT | player-demand-dispatch-missing-or-prereq-failed | legacy player admission retained";
            };

            if (_halLogisticsLoaded isEqualTo true && {fileExists "ITW_CLASH_Resupply.sqf"}) then {
                call compile preprocessFileLineNumbers "ITW_CLASH_Resupply.sqf";
            } else {
                diag_log "CLASH BOOT | resupply-missing-or-prereq-failed | dry HAL units rely on native resupply only";
            };

            // RydHQ_ReconDone decides whether HAL issues capture orders at all.
            // HAL only scouts while blind, HQReset clears the flag anyway, and
            // CLASH runs that reset every 30s - so once a commander makes
            // contact the flag never comes back and nothing attacks. Held up
            // while the commander has contact; never written false.
            if (fileExists "ITW_CLASH_HALReconLatch.sqf") then {
                call compile preprocessFileLineNumbers "ITW_CLASH_HALReconLatch.sqf";
            } else {
                diag_log "CLASH BOOT | hal-recon-latch-missing | capture orders stay on HAL's RapidCapt dice";
            };

            // Eight files disable attack, two restore it, and neither of those
            // two covers a medevac'd squad - so a group that gets picked up is
            // unable to shoot for the rest of the mission. Restores the
            // invariant for any group nothing currently owns.
            if (fileExists "ITW_CLASH_AttackRestore.sqf") then {
                call compile preprocessFileLineNumbers "ITW_CLASH_AttackRestore.sqf";
            } else {
                diag_log "CLASH BOOT | WARNING | attack-restore-missing | medevac'd squads stay unable to attack";
            };

            // The preflight report: one greppable block saying which modules
            // came up and what each commander's state is. Read-only, and loaded
            // last so every other module has published its flag.
            if (fileExists "ITW_CLASH_DebugPreflight.sqf") then {
                call compile preprocessFileLineNumbers "ITW_CLASH_DebugPreflight.sqf";
            } else {
                diag_log "CLASH BOOT | debug-preflight-missing | module readiness has to be read out of the full boot log";
            };

            if (missionNamespace getVariable ["ITW_CLASH_CertificationMode",false] && {
                fileExists "ITW_CLASH_ArtilleryCertification.sqf"
            }) then {
                [] execVM "ITW_CLASH_ArtilleryCertification.sqf";
            };

            if (
                _dualHALHardened isEqualTo true
                && {_commanderParityLoaded isEqualTo true}
                && {_crewRemnantCleanupLoaded isEqualTo true}
                && {_checkbookAPIReady isEqualTo true}
                && {_forceGenerationReady isEqualTo true}
                && {_halLogisticsLoaded isEqualTo true}
                && {_playerTransportLoaded isEqualTo true}
                && {_playerTasksLoaded isEqualTo true}
                && {_playerGarageLoaded isEqualTo true}
                && {_playerArtilleryLoaded isEqualTo true}
            ) then {
                diag_log format [
                    "CLASH BOOT | dual-hal-checkbook-deferred-ready | hardening=true capabilityAPI=v2 forceGeneration=%1 halLogistics=%2 playerTransport=%3 playerTasks=%4 playerGarage=%5 playerArtillery=%6 sideBinderOwnsCommanderB=true nativeCoreLaunch=live-mode-only configuredMode=%7 commanderParity=%8 crewRemnantCleanup=%9",
                    _forceGenerationReady,
                    _halLogisticsLoaded,
                    _playerTransportLoaded,
                    _playerTasksLoaded,
                    _playerGarageLoaded,
                    _playerArtilleryLoaded,
                    missionNamespace getVariable ["ITW_ParamCLASHObserver",-1],
                    _commanderParityLoaded,
                    _crewRemnantCleanupLoaded
                ];
            } else {
                diag_log format [
                    "CLASH BOOT | WARNING | dual-hal-checkbook-incomplete | hardening=%1 capabilityAPI=%2 forceGeneration=%3 halLogistics=%4 playerTransport=%5 playerTasks=%6 playerGarage=%7 playerArtillery=%8 commanderParity=%9 crewRemnantCleanup=%10 runtime candidate blocked",
                    _dualHALHardened,_checkbookAPIReady,_forceGenerationReady,_halLogisticsLoaded,_playerTransportLoaded,_playerTasksLoaded,_playerGarageLoaded,_playerArtilleryLoaded,_commanderParityLoaded,_crewRemnantCleanupLoaded
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

    if (fileExists "ITW_CLASH_HALParadrop.sqf") then {
        private _halParadropLoaded = call compile preprocessFileLineNumbers
            "ITW_CLASH_HALParadrop.sqf";
        if !(_halParadropLoaded isEqualTo true) then {
            diag_log "CLASH BOOT | hal-paradrop-load-failed | native HAL landing retained";
        };
    } else {
        diag_log "CLASH BOOT | hal-paradrop-missing | native HAL landing retained";
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

        if (fileExists "ITW_CLASH_RemnantEvac.sqf") then {
            [] execVM "ITW_CLASH_RemnantEvac.sqf";
        } else {
            diag_log "CLASH BOOT | remnant-evac-missing | shattered infantry remains HAL-native";
        };
    };
};

[] execVM "ITW_Start.sqf";

diag_log "ITW: init complete";
