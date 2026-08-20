if (!isServer) exitWith {false};

/*
    Narrow bootstrap wrapper for post-V6 SOF anchor doctrine.

    SelectAnchorGroup/AuditAnchors must first receive the canonical V6 runtime
    corrections, but must remain mutable for one additional synchronous pass so
    SOF hard-exclusion can wrap those corrected functions. The window closes
    before scheduled C.L.A.S.H./HAL startup receives execution time.
*/

ITW_CLASH_LateDoctrineFinalizers = [
    "ITW_CLASH_fnc_SelectAnchorGroup",
    "ITW_CLASH_fnc_AuditAnchors"
];

diag_log format [
    "CLASH BOOT | sof-doctrine-finalization-window | deferred=%1",
    ITW_CLASH_LateDoctrineFinalizers
];

private _bootstrapResult = call compile preprocessFileLineNumbers "ITW_CLASH_Bootstrap.sqf";
if !(_bootstrapResult isEqualTo true && {
    missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]
}) exitWith {
    ITW_CLASH_LateDoctrineFinalizers = [];
    diag_log "CLASH BOOT | sof-doctrine-skipped | canonical bootstrap not ready";
    false
};

private _path = "ITW_CLASH_SOFDoctrine.sqf";
private _exists = fileExists _path;
private _source = if (_exists) then {preprocessFileLineNumbers _path} else {""};
private _chars = count toArray _source;
diag_log format [
    "CLASH BOOT | sof-doctrine | exists=%1 chars=%2 path=%3",
    _exists,_chars,_path
];

private _loaded = false;
if (_exists && {_chars > 0}) then {
    private _result = call compile _source;
    _loaded = _result isEqualTo true && {
        (missionNamespace getVariable ["ITW_CLASH_SOFDoctrineVersion",-1]) == 1 && {
            !isNil "ITW_CLASH_SOF_fnc_Classify" && {
                !isNil "ITW_CLASH_SOF_fnc_IsSOF" && {
                    !isNil "ITW_CLASH_fnc_SelectAnchorGroup_SOFBase" && {
                        !isNil "ITW_CLASH_fnc_AuditAnchors_SOFBase"
                    }
                }
            }
        }
    };
};

// Always close the window. If doctrine failed, the corrected V6 anchor
// functions are still present and are finalized unchanged (fail-open).
ITW_CLASH_LateDoctrineFinalizers = [];
if (!isNil "SKL_fnc_CompileFinal") then {
    private _finalizers = if (_loaded) then {
        [
            "ITW_CLASH_SOF_fnc_Classify",
            "ITW_CLASH_SOF_fnc_IsSOF",
            "ITW_CLASH_fnc_SelectAnchorGroup_SOFBase",
            "ITW_CLASH_fnc_AuditAnchors_SOFBase",
            "ITW_CLASH_fnc_SelectAnchorGroup",
            "ITW_CLASH_fnc_AuditAnchors"
        ]
    } else {
        [
            "ITW_CLASH_fnc_SelectAnchorGroup",
            "ITW_CLASH_fnc_AuditAnchors"
        ]
    };
    {[_x] call SKL_fnc_CompileFinal} forEach _finalizers;
};

if (!_loaded) then {
    diag_log "CLASH BOOT | WARNING | sof-doctrine-load-failed | corrected V6 anchor policy retained";
} else {
    diag_log "CLASH BOOT | sof-doctrine-loaded | version=1 anchorsSOF=false";
};

_loaded
