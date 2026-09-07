if (!isServer) exitWith {false};

// Compatibility bootstrap only. Formation-recovery policy lives in
// ITW_CLASH_FormationRecovery.sqf; keep this filename so existing missions and
// CASEVAC-era boot tests do not require a coordinated loader migration.
if (missionNamespace getVariable ["ITW_CLASH_FormationRecoveryStarted",false]) exitWith {true};
if !(fileExists "ITW_CLASH_FormationRecovery.sqf") exitWith {
    diag_log "CLASH BOOT | FAILED | formation-recovery-source-missing";
    false
};

call compile preprocessFileLineNumbers "ITW_CLASH_FormationRecovery.sqf"
