if (!isServer) exitWith {false};

/*
    Narrow bootstrap wrapper for post-V6 doctrine.

    The canonical V6 runtime + GTFO corrections must land first, but seven public
    authority surfaces remain mutable for one additional synchronous pass:
      - SOF anchor policy wraps SelectAnchorGroup/AuditAnchors.
      - persistent HAL infantry ownership wraps ClassifyGroup/ApplyObjectiveDoctrine.
      - persistent tactical authority wraps ObserveWriter/ObserveLifecycle.
      - allocation audit is replaced with affinity-only reconciliation; it never
        releases fielded HAL infantry for waypoint drift.

    The window closes before scheduled C.L.A.S.H./HAL startup receives execution.
*/

ITW_CLASH_LateDoctrineFinalizers = [
    "ITW_CLASH_fnc_SelectAnchorGroup",
    "ITW_CLASH_fnc_AuditAnchors",
    "ITW_CLASH_fnc_ClassifyGroup",
    "ITW_CLASH_fnc_ApplyObjectiveDoctrine",
    "ITW_CLASH_fnc_ObserveWriter",
    "ITW_CLASH_fnc_ObserveLifecycle",
    "ITW_CLASH_fnc_AuditAllocations"
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
        (missionNamespace getVariable ["ITW_CLASH_SOFDoctrineVersion",-1]) == 2 && {
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
private _infPreInitReady = missionNamespace getVariable [
    "ITW_CLASH_InfantryAuthorityPreInitReady",
    false
];
diag_log format [
    "CLASH BOOT | infantry-authority | exists=%1 chars=%2 preInit=%3 path=%4",
    _infExists,_infChars,_infPreInitReady,_infPath
];

private _infLoaded = false;
if (_infPreInitReady && {_infExists && {_infChars > 0}}) then {
    private _result = call compile _infSource;
    _infLoaded = _result isEqualTo true && {
        (missionNamespace getVariable ["ITW_CLASH_InfantryAuthorityVersion",-1]) == 4 && {
            !isNil "ITW_CLASH_InfantryAuthority_fnc_IsHardHandoff" && {
                !isNil "ITW_CLASH_InfantryAuthority_fnc_IsManagedFielded" && {
                    !isNil "ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints" && {
                        !isNil "ITW_CLASH_fnc_ClassifyGroup_InfantryAuthorityBase" && {
                            !isNil "ITW_CLASH_fnc_ApplyObjectiveDoctrine_InfantryAuthorityBase" && {
                                !isNil "ITW_CLASH_fnc_ObserveWriter_InfantryAuthorityBase" && {
                                    !isNil "ITW_CLASH_fnc_ObserveLifecycle_InfantryAuthorityBase"
                                }
                            }
                        }
                    }
                }
            }
        }
    };
};

private _allocationFixLoaded = false;
if (_infLoaded) then {
    private _allocationPath = "ITW_CLASH_InfantryAuthorityAllocationFix.sqf";
    private _allocationExists = fileExists _allocationPath;
    private _allocationSource = if (_allocationExists) then {
        preprocessFileLineNumbers _allocationPath
    } else {
        ""
    };
    private _allocationChars = count toArray _allocationSource;
    diag_log format [
        "CLASH BOOT | infantry-allocation-authority | exists=%1 chars=%2 path=%3",
        _allocationExists,_allocationChars,_allocationPath
    ];

    if (_allocationExists && {_allocationChars > 0}) then {
        private _result = call compile _allocationSource;
        _allocationFixLoaded = _result isEqualTo true && {
            (missionNamespace getVariable [
                "ITW_CLASH_InfantryAuthorityAllocationFixVersion",
                -1
            ]) == 2 && {
                !isNil "ITW_CLASH_InfantryAuthorityAllocationFix_fnc_SetAffinity"
            }
        };
    };
};

// Keep the core authority status separate from the allocation hardening gate.
// If the allocation replacement fails, finalize the already-loaded authority
// surfaces but report the build incomplete rather than pretending the old drift
// release path is acceptable.
private _fullInfantryAuthorityReady = _infLoaded && _allocationFixLoaded;

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
            "ITW_CLASH_InfantryAuthority_fnc_IsManagedFielded",
            "ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints",
            "ITW_CLASH_fnc_ClassifyGroup_InfantryAuthorityBase",
            "ITW_CLASH_fnc_ApplyObjectiveDoctrine_InfantryAuthorityBase",
            "ITW_CLASH_fnc_ObserveWriter_InfantryAuthorityBase",
            "ITW_CLASH_fnc_ObserveLifecycle_InfantryAuthorityBase"
        ];
    };
    if (_allocationFixLoaded) then {
        _finalizers pushBack "ITW_CLASH_InfantryAuthorityAllocationFix_fnc_SetAffinity";
    };
    _finalizers append [
        "ITW_CLASH_fnc_SelectAnchorGroup",
        "ITW_CLASH_fnc_AuditAnchors",
        "ITW_CLASH_fnc_ClassifyGroup",
        "ITW_CLASH_fnc_ApplyObjectiveDoctrine",
        "ITW_CLASH_fnc_ObserveWriter",
        "ITW_CLASH_fnc_ObserveLifecycle",
        "ITW_CLASH_fnc_AuditAllocations"
    ];
    {[_x] call SKL_fnc_CompileFinal} forEach _finalizers;
};

if (!_sofLoaded) then {
    diag_log "CLASH BOOT | WARNING | sof-doctrine-load-failed | corrected V6 anchor policy retained";
} else {
    diag_log "CLASH BOOT | sof-doctrine-loaded | version=1 anchorsSOF=false";
};
if (!_infLoaded) then {
    diag_log format [
        "CLASH BOOT | WARNING | infantry-authority-load-failed | preInit=%1 source=%2 previous pilot admission policy retained",
        _infPreInitReady,
        _infExists && {_infChars > 0}
    ];
} else {
    if (!_allocationFixLoaded) then {
        diag_log "CLASH BOOT | WARNING | infantry-allocation-authority-load-failed | persistent HAL authority loaded but legacy allocation drift release remains";
    } else {
        diag_log "CLASH BOOT | infantry-authority-loaded | version=2 allFieldedInfantry=true persistentTacticalAuthority=true allocationDriftReleases=false";
    };
};

// Native HAL SF correction is independent of C.L.A.S.H. tactical ownership. It
// waits for NR6 VarInit to bind the real HAL globals, verifies the exact audited
// source signatures, then recompiles only those two corrected functions.
if (fileExists "ITW_CLASH_HALNativeSFFix.sqf") then {
    [] execVM "ITW_CLASH_HALNativeSFFix.sqf";
    diag_log "CLASH BOOT | native-sf-fix-scheduled";
} else {
    diag_log "CLASH BOOT | WARNING | native-sf-fix-missing | upstream HAL SF defects remain";
};

// Field hardening is intentionally post-finalization and runtime-scoped. It does
// not replace HAL movement doctrine: it fixes failed recovery cleanup, repairs
// stale reconstitution vehicle assignments, filters ACE-invalid contact pairs,
// guards nil-returning HAL recon handles, and observes stalled HAL withdrawals.
if (fileExists "ITW_CLASH_FieldHardening.sqf") then {
    [] execVM "ITW_CLASH_FieldHardening.sqf";
    diag_log "CLASH BOOT | field-hardening-scheduled";
} else {
    diag_log "CLASH BOOT | WARNING | field-hardening-missing";
};

_sofLoaded && _fullInfantryAuthorityReady
