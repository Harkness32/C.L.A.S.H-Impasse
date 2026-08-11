/*
    C.L.A.S.H. deterministic server bootstrap.

    The controller is deliberately not loaded from preInit. This wrapper runs
    after mission parameters are ready, compiles ITW_CLASH.sqf exactly once,
    validates the complete V6 function surface, and leaves baseline Impasse
    fail-open if anything is missing.
*/

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]) exitWith {
    diag_log format [
        "CLASH BOOT | duplicate-bootstrap-skipped | version=%1",
        missionNamespace getVariable ["ITW_CLASH_Version",-1]
    ];
    true
};

diag_log "CLASH BOOT | begin | init-server";
ITW_CLASH_BootstrapReady = false;
ITW_CLASH_BootstrapFailure = "";

private _path = "ITW_CLASH.sqf";
private _installFallbacks = {
    ITW_CLASH_BootstrapReady = false;
    ITW_CLASH_HookFallbacksActive = true;
    ITW_CLASH_ObserverEnabled = false;
    ITW_CLASH_LiveEnabled = false;

    // If a partial controller reached its scheduled self-start, these flags
    // make both startup entry points return without enabling C.L.A.S.H.
    ITW_CLASH_ObserverStarted = true;
    ITW_CLASH_LiveStarted = true;

    // Preserve baseline Impasse semantics at the only unguarded integration
    // points. ObserveWriter=false explicitly yields waypoint authority back
    // to Impasse.
    ITW_CLASH_fnc_ObserveGroup = {false};
    ITW_CLASH_fnc_ObserveWriter = {false};
    ITW_CLASH_fnc_ObserveLifecycle = {false};

    diag_log format [
        "CLASH BOOT | fallback | reason=%1 | baseline Impasse remains active",
        ITW_CLASH_BootstrapFailure
    ];
    false
};

private _exists = fileExists _path;
diag_log format ["CLASH BOOT | file | exists=%1 path=%2",_exists,_path];
if (!_exists) exitWith {
    ITW_CLASH_BootstrapFailure = "controller-file-missing";
    diag_log "CLASH BOOT | FAILED | controller-file-missing";
    call _installFallbacks;
};

// Probe the raw and both preprocessor paths separately. This is diagnostic
// only: runtime compilation still requires preprocessFileLineNumbers to pass.
private _rawSource = loadFile _path;
private _rawChars = count toArray _rawSource;
diag_log format ["CLASH BOOT | raw | chars=%1",_rawChars];

private _plainSource = preprocessFile _path;
private _plainChars = count toArray _plainSource;
diag_log format ["CLASH BOOT | preprocess | chars=%1",_plainChars];

private _source = preprocessFileLineNumbers _path;
private _sourceChars = count toArray _source;
diag_log format ["CLASH BOOT | preprocess-lines | chars=%1",_sourceChars];
if (_sourceChars <= 0) exitWith {
    ITW_CLASH_BootstrapFailure = format [
        "controller-source-empty raw=%1 preprocess=%2 lineNumbers=%3",
        _rawChars,
        _plainChars,
        _sourceChars
    ];
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};

// Sole runtime compile of ITW_CLASH.sqf. Its existing scheduled startup is
// retained; because params are already complete, it can start only after this
// synchronous definition pass returns to the scheduler.
call compile _source;

private _required = [
    "ITW_CLASH_fnc_Log",
    "ITW_CLASH_fnc_GroupId",
    "ITW_CLASH_fnc_IsCommanderGroup",
    "ITW_CLASH_fnc_IsConscious",
    "ITW_CLASH_fnc_CountConscious",
    "ITW_CLASH_fnc_IsHALExhausted",
    "ITW_CLASH_fnc_GetArchetype",
    "ITW_CLASH_fnc_AnchorKey",
    "ITW_CLASH_fnc_GetObjectiveRadius",
    "ITW_CLASH_fnc_GetObjectiveCenter",
    "ITW_CLASH_fnc_GetObjectiveFlag",
    "ITW_CLASH_fnc_GetActiveObjectives",
    "ITW_CLASH_fnc_GetHeldObjectives",
    "ITW_CLASH_fnc_GetCommanderPosition",
    "ITW_CLASH_fnc_SyncCommanderObjective",
    "ITW_CLASH_fnc_ClassifyGroup",
    "ITW_CLASH_fnc_ClearGroupWaypoints",
    "ITW_CLASH_fnc_ApplyObjectiveDoctrine",
    "ITW_CLASH_fnc_SyncHALIncluded",
    "ITW_CLASH_fnc_MirrorObjectives",
    "ITW_CLASH_fnc_ClearAnchorSlot",
    "ITW_CLASH_fnc_ResetAnchors",
    "ITW_CLASH_fnc_SelectAnchorGroup",
    "ITW_CLASH_fnc_OrderAnchor",
    "ITW_CLASH_fnc_RequestAnchorRefill",
    "ITW_CLASH_fnc_NextAnchorRefill",
    "ITW_CLASH_fnc_AcknowledgeAnchorRefill",
    "ITW_CLASH_fnc_GetEgressPoint",
    "ITW_CLASH_fnc_OrderWithdrawal",
    "ITW_CLASH_fnc_StartWithdrawal",
    "ITW_CLASH_fnc_AcknowledgeReconstitution",
    "ITW_CLASH_fnc_AuditWithdrawals",
    "ITW_CLASH_fnc_CancelWithdrawals",
    "ITW_CLASH_fnc_AuditAnchors",
    "ITW_CLASH_fnc_AuditAllocations",
    "ITW_CLASH_fnc_RegisterGroup",
    "ITW_CLASH_fnc_BeginRelease",
    "ITW_CLASH_fnc_ReleaseAcknowledged",
    "ITW_CLASH_fnc_FinishRelease",
    "ITW_CLASH_fnc_ReleaseGroup",
    "ITW_CLASH_fnc_ReleaseAll",
    "ITW_CLASH_fnc_ObserveGroup",
    "ITW_CLASH_fnc_ObserveWriter",
    "ITW_CLASH_fnc_WouldReleaseAll",
    "ITW_CLASH_fnc_ObserveLifecycle",
    "ITW_CLASH_fnc_Reconcile",
    "ITW_CLASH_fnc_DiagnosticSnapshot",
    "ITW_CLASH_fnc_ConfigureHAL",
    "ITW_CLASH_fnc_CreateCommander",
    "ITW_CLASH_fnc_CommanderHealthy",
    "ITW_CLASH_fnc_FailPilot",
    "ITW_CLASH_fnc_StartCommanderWatchdog",
    "ITW_CLASH_fnc_StartLivePilot",
    "ITW_CLASH_fnc_StartObserver"
];
private _missing = _required select {isNil _x};
private _version = missionNamespace getVariable ["ITW_CLASH_Version",-1];

if (_version != 6 || {_missing isNotEqualTo []}) exitWith {
    ITW_CLASH_BootstrapFailure = format [
        "validation-failed version=%1 missing=%2",
        _version,
        _missing
    ];
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};

ITW_CLASH_HookFallbacksActive = false;
ITW_CLASH_BootstrapReady = true;
diag_log format [
    "CLASH BOOT | READY | version=%1 sourceChars=%2 functions=%3",
    _version,
    _sourceChars,
    count _required
];
true