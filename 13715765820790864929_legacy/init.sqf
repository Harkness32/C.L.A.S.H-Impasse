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

    // The reconstitution dispatcher and transit manager are compileFinal'd
    // unconditionally at the tail of ITW_Attack.sqf. Install corrected final
    // implementations synchronously before ITW_Start launches that file. The
    // later baseline assignments are then rejected, leaving the corrected
    // implementations as the canonical runtime functions.
    if (fileExists "ITW_CLASH_ReconstitutionDispatchFix.sqf") then {
        call compile preprocessFileLineNumbers "ITW_CLASH_ReconstitutionDispatchFix.sqf";
    } else {
        diag_log "CLASH BOOT | reconstitution-dispatch-fix-missing | baseline function will load";
    };
    if (fileExists "ITW_CLASH_ReconstitutionTransitFix.sqf") then {
        call compile preprocessFileLineNumbers "ITW_CLASH_ReconstitutionTransitFix.sqf";
    } else {
        diag_log "CLASH BOOT | reconstitution-transit-fix-missing | baseline function will load";
    };

    if (fileExists "ITW_CLASH_LogisticsGuard.sqf") then {
        [] execVM "ITW_CLASH_LogisticsGuard.sqf";
    } else {
        diag_log "CLASH BOOT | logistics-guard-missing | continuing without V6 handoff guard";
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
    } else {
        diag_log "CLASH BOOT | casevac-missing | walking withdrawal remains active";
    };
};

[] execVM "ITW_Start.sqf";

diag_log "ITW: init complete";