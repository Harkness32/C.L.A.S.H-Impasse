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
    if (fileExists "ITW_CLASH_Bootstrap.sqf") then {
        call compile preprocessFileLineNumbers "ITW_CLASH_Bootstrap.sqf";
    } else {
        ITW_CLASH_BootstrapReady = false;
        ITW_CLASH_HookFallbacksActive = true;
        ITW_CLASH_fnc_ObserveGroup = {false};
        ITW_CLASH_fnc_ObserveWriter = {false};
        ITW_CLASH_fnc_ObserveLifecycle = {false};
        diag_log "CLASH BOOT | FAILED | bootstrap-file-missing | baseline Impasse remains active";
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

    // Reconstitution and physical-movement corrections belong to preInit,
    // where ITW_Attack.sqf is actually compiled. Never retry them here after
    // those functions are final.
    if (missionNamespace getVariable ["ITW_CLASH_ReconstitutionPreInitReady",false]) then {
        diag_log "CLASH BOOT | reconstitution-preinit-authority-confirmed | late-overrides-skipped";
    } else {
        diag_log "CLASH BOOT | WARNING | reconstitution-preinit-authority-missing | baseline/fail-open functions retained";
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
};

[] execVM "ITW_Start.sqf";

diag_log "ITW: init complete";
