/*
    C.L.A.S.H. deterministic server bootstrap.

    The controller is deliberately not loaded from preInit. This wrapper runs
    after mission parameters are ready, validates the controller source, then
    compiles it exactly once. If Arma's preprocessor rejects the canonical V6
    controller, a preprocessor-safe segmented mirror is assembled instead.
    Baseline Impasse remains fail-open if either path cannot validate.
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

private _rawSource = if (_exists) then {loadFile _path} else {""};
private _rawChars = count toArray _rawSource;
diag_log format ["CLASH BOOT | raw | chars=%1",_rawChars];

private _plainSource = if (_exists) then {preprocessFile _path} else {""};
private _plainChars = count toArray _plainSource;
diag_log format ["CLASH BOOT | preprocess | chars=%1",_plainChars];

private _source = if (_exists) then {preprocessFileLineNumbers _path} else {""};
private _sourceChars = count toArray _source;
diag_log format ["CLASH BOOT | preprocess-lines | chars=%1",_sourceChars];

if (_sourceChars <= 0) then {
    diag_log "CLASH BOOT | canonical-preprocess-failed | trying segmented-source";

    private _segments = [
        ["01A","ITW_CLASH_SEG_01A.sqf"],
        ["01B","ITW_CLASH_SEG_01B.sqf"],
        ["01C","ITW_CLASH_SEG_01C.sqf"],
        ["02","ITW_CLASH_PP_02.sqf"],
        ["03","ITW_CLASH_PP_03.sqf"],
        ["04","ITW_CLASH_PP_04.sqf"],
        ["05","ITW_CLASH_PP_05.sqf"],
        ["06","ITW_CLASH_PP_06.sqf"],
        ["07","ITW_CLASH_PP_07.sqf"],
        ["08","ITW_CLASH_PP_08.sqf"]
    ];
    private _parts = [];
    private _failedSegments = [];

    {
        _x params ["_label","_segmentPath"];
        private _segmentExists = fileExists _segmentPath;
        private _segmentSource = if (_segmentExists) then {
            preprocessFileLineNumbers _segmentPath
        } else {
            ""
        };
        private _segmentChars = count toArray _segmentSource;
        diag_log format [
            "CLASH BOOT | segment | id=%1 exists=%2 chars=%3 path=%4",
            _label,
            _segmentExists,
            _segmentChars,
            _segmentPath
        ];

        if (!_segmentExists || {_segmentChars <= 0}) then {
            _failedSegments pushBack [_label,_segmentExists,_segmentChars,_segmentPath];
        } else {
            _parts pushBack _segmentSource;
        };
    } forEach _segments;

    if (_failedSegments isEqualTo []) then {
        _source = _parts joinString "\n";
        _sourceChars = count toArray _source;
        diag_log format [
            "CLASH BOOT | source-selected | segmented | chars=%1 segments=%2",
            _sourceChars,
            count _parts
        ];
    } else {
        ITW_CLASH_BootstrapFailure = format [
            "controller-preprocess-failed raw=%1 preprocess=%2 lineNumbers=%3 segmentFailures=%4",
            _rawChars,
            _plainChars,
            _sourceChars,
            _failedSegments
        ];
    };
} else {
    diag_log format ["CLASH BOOT | source-selected | canonical | chars=%1",_sourceChars];
};

if (_sourceChars <= 0 || {ITW_CLASH_BootstrapFailure isNotEqualTo ""}) exitWith {
    if (ITW_CLASH_BootstrapFailure isEqualTo "") then {
        ITW_CLASH_BootstrapFailure = format [
            "controller-source-empty raw=%1 preprocess=%2 lineNumbers=%3",
            _rawChars,
            _plainChars,
            _sourceChars
        ];
    };
    diag_log format ["CLASH BOOT | FAILED | %1",ITW_CLASH_BootstrapFailure];
    call _installFallbacks;
};

// Sole runtime compile. The existing controller scheduled startup is retained;
// because params are already complete, it can start only after this synchronous
// definition pass returns to the scheduler.
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