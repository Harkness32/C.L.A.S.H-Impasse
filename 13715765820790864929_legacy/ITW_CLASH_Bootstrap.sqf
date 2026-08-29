/*
    C.L.A.S.H. deterministic server bootstrap.

    The controller is deliberately not loaded from preInit. This wrapper runs
    after mission parameters are ready, compiles ITW_CLASH.sqf exactly once,
    defers finalization for the small V6 runtime-integrity correction surface,
    applies that correction synchronously, installs the GTFO HAL/Impasse bridge,
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
ITW_CLASH_DeferredFinalizers = [];
ITW_CLASH_PersistentDeferredFinalizers = [];

private _path = "ITW_CLASH.sqf";
private _installFallbacks = {
    ITW_CLASH_BootstrapReady = false;
    ITW_CLASH_HookFallbacksActive = true;
    ITW_CLASH_ObserverEnabled = false;
    ITW_CLASH_LiveEnabled = false;
    ITW_CLASH_DeferredFinalizers = [];
    ITW_CLASH_PersistentDeferredFinalizers = [];

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

// These six functions are corrected immediately after the canonical
// controller definition pass. SKL_fnc_CompileFinal sees this list and leaves
// only these names mutable for the V6 runtime patch.
ITW_CLASH_DeferredFinalizers = [
    "ITW_CLASH_fnc_ClassifyGroup",
    "ITW_CLASH_fnc_ObserveWriter",
    "ITW_CLASH_fnc_GetEgressPoint",
    "ITW_CLASH_fnc_AcknowledgeReconstitution",
    "ITW_CLASH_fnc_SelectAnchorGroup",
    "ITW_CLASH_fnc_AuditAnchors"
];

// GTFO sits above the corrected V6 surface, so these public authority functions
// remain mutable through the runtime-patch finalization pass and are finalized
// only after ITW_CLASH_GTFO.sqf has installed its bridge wrappers/replacements.
ITW_CLASH_PersistentDeferredFinalizers = [
    "ITW_CLASH_fnc_ClassifyGroup",
    "ITW_CLASH_fnc_ApplyObjectiveDoctrine",
    "ITW_CLASH_fnc_GetEgressPoint",
    "ITW_CLASH_fnc_OrderWithdrawal",
    "ITW_CLASH_fnc_StartWithdrawal",
    "ITW_CLASH_fnc_CancelWithdrawals"
];
diag_log format [
    "CLASH BOOT | finalization-window | deferred=%1 persistent=%2",
    ITW_CLASH_DeferredFinalizers,
    ITW_CLASH_PersistentDeferredFinalizers
];

// Sole runtime compile of ITW_CLASH.sqf. Its scheduled startup is retained;
// because params are already complete, it can start only after this synchronous
// definition/correction pass returns to the scheduler.
call compile _source;
ITW_CLASH_DeferredFinalizers = [];

// Apply the V6 runtime-integrity correction while the selected controller
// functions are still mutable. The persistent GTFO surface remains deliberately
// unfinalized until the bridge is installed below.
private _patchPath = "ITW_CLASH_RuntimePatch.sqf";
private _patchExists = fileExists _patchPath;
private _patchSource = if (_patchExists) then {
    preprocessFileLineNumbers _patchPath
} else {
    ""
};
private _patchChars = count toArray _patchSource;
diag_log format [
    "CLASH BOOT | runtime-patch | exists=%1 chars=%2 path=%3",
    _patchExists,
    _patchChars,
    _patchPath
];
if (!_patchExists || {_patchChars <= 0}) exitWith {
    ITW_CLASH_BootstrapFailure = "runtime-patch-missing-or-empty";
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};
call compile _patchSource;

private _patchVersion = missionNamespace getVariable [
    "ITW_CLASH_RuntimePatchVersion",
    -1
];
private _patchRequired = [
    "ITW_CLASH_fnc_GetHomeBaseSpawn",
    "ITW_CLASH_fnc_GetSupportCorridorSpawn",
    "ITW_CLASH_fnc_ClassifyGroup",
    "ITW_CLASH_fnc_ObserveWriter",
    "ITW_CLASH_fnc_GetEgressPoint",
    "ITW_CLASH_fnc_AcknowledgeReconstitution",
    "ITW_CLASH_fnc_SelectAnchorGroup",
    "ITW_CLASH_fnc_AuditAnchors"
];
private _patchMissing = _patchRequired select {isNil _x};
if (_patchVersion != 5 || {_patchMissing isNotEqualTo []}) exitWith {
    ITW_CLASH_BootstrapFailure = format [
        "runtime-patch-validation-failed version=%1 missing=%2",
        _patchVersion,
        _patchMissing
    ];
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};
diag_log format [
    "CLASH BOOT | runtime-patch-loaded | version=%1 functions=%2",
    _patchVersion,
    count _patchRequired
];

// Install GTFO synchronously before observer/live startup. This is the bridge
// layer that delegates tactical withdrawal to HAL's native GoRest while keeping
// Impasse as strategic rear/recovery/reconstitution authority.
private _gtfoPath = "ITW_CLASH_GTFO.sqf";
private _gtfoExists = fileExists _gtfoPath;
private _gtfoSource = if (_gtfoExists) then {
    preprocessFileLineNumbers _gtfoPath
} else {
    ""
};
private _gtfoChars = count toArray _gtfoSource;
diag_log format [
    "CLASH BOOT | gtfo-bridge | exists=%1 chars=%2 path=%3",
    _gtfoExists,
    _gtfoChars,
    _gtfoPath
];
if (!_gtfoExists || {_gtfoChars <= 0}) exitWith {
    ITW_CLASH_BootstrapFailure = "gtfo-bridge-missing-or-empty";
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};
call compile _gtfoSource;

private _gtfoVersion = missionNamespace getVariable ["ITW_CLASH_GTFOVersion",-1];
private _gtfoRequired = [
    "ITW_CLASH_GTFO_fnc_Log",
    "ITW_CLASH_GTFO_fnc_RefreshCorridor",
    "ITW_CLASH_GTFO_fnc_ApplyConstraints",
    "ITW_CLASH_GTFO_fnc_ResumeHAL",
    "ITW_CLASH_GTFO_fnc_RecoveryOwned",
    "ITW_CLASH_fnc_ClassifyGroup",
    "ITW_CLASH_fnc_ApplyObjectiveDoctrine",
    "ITW_CLASH_fnc_GetEgressPoint",
    "ITW_CLASH_fnc_OrderWithdrawal",
    "ITW_CLASH_fnc_StartWithdrawal",
    "ITW_CLASH_fnc_CancelWithdrawals"
];
private _gtfoMissing = _gtfoRequired select {isNil _x};
if (_gtfoVersion != 2 || {_gtfoMissing isNotEqualTo []}) exitWith {
    ITW_CLASH_BootstrapFailure = format [
        "gtfo-bridge-validation-failed version=%1 missing=%2",
        _gtfoVersion,
        _gtfoMissing
    ];
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};

// Retire only stale pre-GTFO HAL task bookkeeping. This must load while
// StartWithdrawal is still mutable so it can wrap the bridge transition and
// clear Defending/defensive-list state before the same reconciliation pass runs
// C.L.A.S.H.'s allocation audit. It never writes movement or combat behavior.
private _gtfoBookkeepingPath = "ITW_CLASH_GTFO_Bookkeeping.sqf";
private _gtfoBookkeepingExists = fileExists _gtfoBookkeepingPath;
private _gtfoBookkeepingSource = if (_gtfoBookkeepingExists) then {
    preprocessFileLineNumbers _gtfoBookkeepingPath
} else {
    ""
};
private _gtfoBookkeepingChars = count toArray _gtfoBookkeepingSource;
diag_log format [
    "CLASH BOOT | gtfo-bookkeeping | exists=%1 chars=%2 path=%3",
    _gtfoBookkeepingExists,
    _gtfoBookkeepingChars,
    _gtfoBookkeepingPath
];
if (!_gtfoBookkeepingExists || {_gtfoBookkeepingChars <= 0}) exitWith {
    ITW_CLASH_BootstrapFailure = "gtfo-bookkeeping-missing-or-empty";
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};
call compile _gtfoBookkeepingSource;

private _gtfoBookkeepingVersion = missionNamespace getVariable [
    "ITW_CLASH_GTFOBookkeepingVersion",
    -1
];
private _gtfoBookkeepingRequired = [
    "ITW_CLASH_GTFO_fnc_RetirePreviousTaskState",
    "ITW_CLASH_fnc_StartWithdrawal_GTFOStateBase",
    "ITW_CLASH_fnc_StartWithdrawal"
];
private _gtfoBookkeepingMissing = _gtfoBookkeepingRequired select {isNil _x};
if (_gtfoBookkeepingVersion != 2 || {_gtfoBookkeepingMissing isNotEqualTo []}) exitWith {
    ITW_CLASH_BootstrapFailure = format [
        "gtfo-bookkeeping-validation-failed version=%1 missing=%2",
        _gtfoBookkeepingVersion,
        _gtfoBookkeepingMissing
    ];
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};

// Close the persistent mutation window immediately. Finalize both bridge-facing
// public functions and their saved base implementations before any scheduled
// C.L.A.S.H./HAL startup can execute.
ITW_CLASH_PersistentDeferredFinalizers = [];
if (!isNil "SKL_fnc_CompileFinal") then {
    {
        [_x] call SKL_fnc_CompileFinal;
    } forEach [
        "ITW_CLASH_GTFO_fnc_Log",
        "ITW_CLASH_GTFO_fnc_RefreshCorridor",
        "ITW_CLASH_GTFO_fnc_ApplyConstraints",
        "ITW_CLASH_GTFO_fnc_ResumeHAL",
        "ITW_CLASH_GTFO_fnc_RecoveryOwned",
        "ITW_CLASH_GTFO_fnc_RetirePreviousTaskState",
        "ITW_CLASH_fnc_ClassifyGroup_GTFOBase",
        "ITW_CLASH_fnc_ApplyObjectiveDoctrine_GTFOBase",
        "ITW_CLASH_fnc_GetEgressPoint_GTFOBase",
        "ITW_CLASH_fnc_CancelWithdrawals_GTFOBase",
        "ITW_CLASH_fnc_StartWithdrawal_GTFOStateBase",
        "ITW_CLASH_fnc_ClassifyGroup",
        "ITW_CLASH_fnc_ApplyObjectiveDoctrine",
        "ITW_CLASH_fnc_GetEgressPoint",
        "ITW_CLASH_fnc_OrderWithdrawal",
        "ITW_CLASH_fnc_StartWithdrawal",
        "ITW_CLASH_fnc_CancelWithdrawals"
    ];
};
diag_log format [
    "CLASH BOOT | gtfo-bridge-loaded | version=%1 bookkeeping=%2 functions=%3",
    _gtfoVersion,
    _gtfoBookkeepingVersion,
    count _gtfoRequired
];

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
    "CLASH BOOT | READY | version=%1 sourceChars=%2 functions=%3 patch=%4 gtfo=%5 bookkeeping=%6",
    _version,
    _sourceChars,
    count _required,
    _patchVersion,
    _gtfoVersion,
    _gtfoBookkeepingVersion
];
true