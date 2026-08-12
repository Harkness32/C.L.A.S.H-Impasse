diag_log "ITW: init start";

if (!isDedicated) then {waitUntil {player == player};};
if ((!isServer) && (player != player)) then {waitUntil {player == player};};
isNil {call compile preprocessFileLineNumbers "params.sqf";}; 
waitUntil {! isNil "ITW_PreInitComplete"}; // wait for the server to catch up


//execVM "params.sqf";
if (!isServer && !hasInterface) exitWith {}; // headless clients don't need to proceed any further
waitUntil {!isNil "ITW_Params_complete"};
waitUntil {!isNil "ITW_ParamRadioVolume"}; // jip can sometimes not have this set yet
0 fadeRadio ITW_ParamRadioVolume/10; // allow diable all AI/supports radio chatter, text will still appear though

waitUntil {!isNil "ITW_ParamStamina"}; // jip can sometimes not have this set yet
if (hasInterface && {ITW_ParamStamina < 2}) then {
    player enableStamina (ITW_ParamStamina == 1);
};

execVM "scripts\SKULL\SKL_RatingMinimum.sqf"; // Reset player rating if it gets too low

waitUntil {! isNil "ITW_ParamHeadlessClient"};
HeadlessClients = []; 
if (isServer && ITW_ParamHeadlessClient == 1) then {execVM "scripts\SKULL\SKL_HeadlessClient.sqf"}; // setup the HC handler

// Change arsenal to view the character from behind by default
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

    // #24's reconstitution transport functions live in ITW_Attack.sqf and are
    // normally compileFinal'd at the end of that file. Defer only the functions
    // whose repair payloads are actually present, so missing optional patches
    // leave baseline finalization intact.
    private _deferredFinalizers = missionNamespace getVariable [
        "ITW_CLASH_DeferredFinalizers",
        []
    ];

    if (fileExists "ITW_CLASH_ReconstitutionDispatchFix.sqf") then {
        _deferredFinalizers pushBackUnique "ITW_AtkDispatchReconstitutionTransport";
    } else {
        diag_log "CLASH BOOT | reconstitution-dispatch-fix-missing | baseline finalization retained";
    };
    if (fileExists "ITW_CLASH_ReconstitutionTransitFix.sqf") then {
        _deferredFinalizers pushBackUnique "ITW_AtkReconstitutionTransitManager";
    } else {
        diag_log "CLASH BOOT | reconstitution-transit-fix-missing | baseline finalization retained";
    };
    missionNamespace setVariable [
        "ITW_CLASH_DeferredFinalizers",
        _deferredFinalizers
    ];

    if (fileExists "ITW_CLASH_ReconstitutionDispatchFix.sqf") then {
        [] execVM "ITW_CLASH_ReconstitutionDispatchFix.sqf";
    };
    if (fileExists "ITW_CLASH_ReconstitutionTransitFix.sqf") then {
        [] execVM "ITW_CLASH_ReconstitutionTransitFix.sqf";
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