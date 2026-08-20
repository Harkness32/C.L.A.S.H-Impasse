if (!isServer) exitWith {false};

/*
    Narrow bootstrap wrapper for post-V6 doctrine.

    The canonical V6 runtime + GTFO corrections must land first, but four public
    authority surfaces remain mutable for one additional synchronous pass:
      - SOF anchor policy wraps SelectAnchorGroup/AuditAnchors.
      - persistent HAL infantry ownership wraps ClassifyGroup/ApplyObjectiveDoctrine.

    The window closes before scheduled C.L.A.S.H./HAL startup receives execution.
*/

ITW_CLASH_LateDoctrineFinalizers = [
    "ITW_CLASH_fnc_SelectAnchorGroup",
    "ITW_CLASH_fnc_AuditAnchors",
    "ITW_CLASH_fnc_ClassifyGroup",
    "ITW_CLASH_fnc_ApplyObjectiveDoctrine"
];

diag_log format [
    "CLASH BOOT | doctrine-finalization-window | deferred=%1",
    ITW_CLASH_LateDoctrineFinalizers
];

private _bootstrapResult = call compile preprocessFileLineNumbers "ITW_CLASH_Bootstrap.sqf";
if !(_bootstrapResult isEqualTo true && {
    missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]
}) exitWith {
    ITW_CLASH_LateDoctrineFinalizers = [];
    diag_log "CLASH BOOT | doctrine-skipped | canonical bootstrap not ready";
    false
};

private _sofPath = "ITW_CLASH_SOFDoctrine.sqf";
private _sofExists = fileExists _sofPath;
private _sofSource = if (_sofExists) then {preprocessFileLineNumbers _sofPath} else {""};
private _sofChars = count toArray _sofSource;
diag_log format [
    "CLASH BOOT | sof-doctrine | exists=%1 chars=%2 path=%3",
    _sofExists,_sofChars,_sofPath
];

private _sofLoaded = false;
if (_sofExists && {_sofChars > 0}) then {
    private _result = call compile _sofSource;
    _sofLoaded = _result isEqualTo true && {
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

private _infPath = "ITW_CLASH_InfantryAuthority.sqf";
private _infExists = fileExists _infPath;
private _infSource = if (_infExists) then {preprocessFileLineNumbers _infPath} else {""};
private _infChars = count toArray _infSource;
diag_log format [
    "CLASH BOOT | infantry-authority | exists=%1 chars=%2 path=%3",
    _infExists,_infChars,_infPath
];

private _infLoaded = false;
if (_infExists && {_infChars > 0}) then {
    private _result = call compile _infSource;
    _infLoaded = _result isEqualTo true && {
        (missionNamespace getVariable ["ITW_CLASH_InfantryAuthorityVersion",-1]) == 1 && {
            !isNil "ITW_CLASH_InfantryAuthority_fnc_IsHardHandoff" && {
                !isNil "ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints" && {
                    !isNil "ITW_CLASH_fnc_ClassifyGroup_InfantryAuthorityBase" && {
                        !isNil "ITW_CLASH_fnc_ApplyObjectiveDoctrine_InfantryAuthorityBase"
                    }
                }
            }
        }
    };
};

// Always close the window. A failed doctrine component leaves the corrected
// lower layer in place and finalizes that surface unchanged (fail-open).
ITW_CLASH_LateDoctrineFinalizers = [];
if (!isNil "SKL_fnc_CompileFinal") then {
    private _finalizers = [];
    if (_sofLoaded) then {
        _finalizers append [
            "ITW_CLASH_SOF_fnc_Classify",
            "ITW_CLASH_SOF_fnc_IsSOF",
            "ITW_CLASH_fnc_SelectAnchorGroup_SOFBase",
            "ITW_CLASH_fnc_AuditAnchors_SOFBase"
        ];
    };
    if (_infLoaded) then {
        _finalizers append [
            "ITW_CLASH_InfantryAuthority_fnc_Log",
            "ITW_CLASH_InfantryAuthority_fnc_IsHardHandoff",
            "ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints",
            "ITW_CLASH_fnc_ClassifyGroup_InfantryAuthorityBase",
            "ITW_CLASH_fnc_ApplyObjectiveDoctrine_InfantryAuthorityBase"
        ];
    };
    _finalizers append [
        "ITW_CLASH_fnc_SelectAnchorGroup",
        "ITW_CLASH_fnc_AuditAnchors",
        "ITW_CLASH_fnc_ClassifyGroup",
        "ITW_CLASH_fnc_ApplyObjectiveDoctrine"
    ];
    {[_x] call SKL_fnc_CompileFinal} forEach _finalizers;
};

if (!_sofLoaded) then {
    diag_log "CLASH BOOT | WARNING | sof-doctrine-load-failed | corrected V6 anchor policy retained";
} else {
    diag_log "CLASH BOOT | sof-doctrine-loaded | version=1 anchorsSOF=false";
};
if (!_infLoaded) then {
    diag_log "CLASH BOOT | WARNING | infantry-authority-load-failed | previous pilot admission policy retained";
} else {
    diag_log "CLASH BOOT | infantry-authority-loaded | version=1 allFieldedInfantry=true";
};

_sofLoaded && _infLoaded
