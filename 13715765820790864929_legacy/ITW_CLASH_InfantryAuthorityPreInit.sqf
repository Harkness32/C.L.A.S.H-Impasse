#include "defines.hpp"

if (!isServer) exitWith {true};

ITW_CLASH_InfantryAuthorityPreInitVersion = 1;
ITW_CLASH_InfantryAuthorityPreInitReady = false;

/*
    Impasse's infantry manager is strategic scaffolding once C.L.A.S.H. is live.
    HAL-managed enemy infantry must not be returned to that manager, because its
    normal loops can garrison, merge, delete or rewrite waypoints behind HAL.

    This filter is deliberately state-based rather than side-wide:
      - before C.L.A.S.H. is live, baseline Impasse behavior is untouched;
      - transport/recovery/zone-transition releases clear ITW_CLASH_Managed and
        therefore re-enter baseline Impasse lifecycle handling;
      - defend-start/defend-done do not release fielded formations, so they stay
        outside Impasse's direct infantry waypoint/deletion passes.
*/

if (isNil "ITW_AtkGetInfantryGroups") exitWith {
    diag_log "CLASH BOOT | FAILED | infantry-authority-preinit-source-missing | ITW_AtkGetInfantryGroups";
    false
};

ITW_CLASH_AtkGetInfantryGroups_Baseline = ITW_AtkGetInfantryGroups;

ITW_AtkGetInfantryGroups = {
    private _groups = call ITW_CLASH_AtkGetInfantryGroups_Baseline;

    if !(missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]) exitWith {_groups};
    if !(missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]) exitWith {_groups};
    if (isNil "ITW_EnemySide") exitWith {_groups};

    _groups select {
        private _group = _x;
        !(
            !isNull _group && {
                side _group == ITW_EnemySide && {
                    _group getVariable ["ITW_CLASH_Managed",false]
                }
            }
        )
    }
};

isNil {
    private _deferred = missionNamespace getVariable ["ITW_CLASH_DeferredFinalizers",[]];
    _deferred = _deferred - ["ITW_AtkGetInfantryGroups"];
    missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];
};

private _final = ["ITW_AtkGetInfantryGroups"] call SKL_fnc_CompileFinal;
if (!_final) then {
    // Never leave a mutable/half-installed filter behind. preInit will finalize
    // this restored baseline in its normal fallback branch.
    ITW_AtkGetInfantryGroups = ITW_CLASH_AtkGetInfantryGroups_Baseline;
};
ITW_CLASH_InfantryAuthorityPreInitReady = _final;

diag_log format [
    "CLASH BOOT | infantry-authority-preinit-ready | version=%1 managerFilter=%2 persistentHAL=true defendPhasePersistent=true zoneTransitionFailOpen=true",
    ITW_CLASH_InfantryAuthorityPreInitVersion,
    _final
];

ITW_CLASH_InfantryAuthorityPreInitReady
