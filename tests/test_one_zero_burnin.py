from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_sof_classifier_uses_spawn_archetype_and_strict_majority():
    sof = mission("ITW_CLASH_SOFDoctrine.sqf")

    assert "ITW_CLASH_SOFClassifierVersion = 2;" in sof
    assert 'getVariable ["ITW_CLASH_SpawnArchetype",[]]' in sof
    assert "(floor (_sourceCount / 2)) + 1" in sof
    assert "private _isSOF = _qualifying isNotEqualTo [];" in sof
    assert 'getVariable ["ITW_CLASH_ReconSOFManual",nil]' in sof
    assert 'getVariable ["ITW_CLASH_ReconSOFClassifierVersion",0]' in sof

    # The burn-in false positive was caused by any single class match promoting
    # the entire mixed group and latching that identity forever.
    assert "private _isSOF = _bestCount > 0;" not in sof


def test_recon_bridge_removes_only_prior_semantic_specfor_memberships_per_commander():
    bridge = mission("ITW_CLASH_ReconPlanningBridge.sqf")

    assert "ITW_CLASH_ReconPlanningBridgeVersion = 4;" in bridge
    assert "ITW_CLASH_ReconPlanning_fnc_GetCommanderCandidates" in bridge
    assert "ITW_CLASH_DualHALBLUFORGroups" in bridge
    assert "ITW_CLASH_DualHALOPFORExtraGroups" in bridge
    assert "side _group == _hqSide" in bridge
    assert '"ITW_CLASH_ReconPlanningSemanticSpecFor"' in bridge
    assert '_specFor = _specFor - _previousSemantic;' in bridge
    assert 'getVariable ["ITW_CLASH_SOFNativeProtected",false]' in bridge
    assert '_hq setVariable ["RydHQ_SpecForG",_specFor];' in bridge
    assert '_hq setVariable ["ITW_CLASH_ReconPlanningSpecForSignature",_signature];' in bridge
    assert "staleSemanticRemoval=true" in bridge
    assert "commanderScoped=true" in bridge

    # Native HAL SpecFor is the base; C.L.A.S.H. removes only its own previous
    # injections before recalculating semantic identity for that exact HQ side.
    assert 'private _specFor = +(_hq getVariable ["RydHQ_SpecForG",[]]);' in bridge


def test_recovery_failure_unwinds_before_requesting_new_hal_rest():
    hardening = mission("ITW_CLASH_OneZeroHardening.sqf")

    air_base = '_this call ITW_CLASH_GTFO_fnc_CASEVACResumeBase'
    air_restart = '["air",_group,_reason] call ITW_CLASH_GTFO_fnc_RequestNativeRestRestart'
    ground_base = '_this call ITW_CLASH_GTFO_fnc_GroundResumeBase'
    ground_restart = '["ground",_group,_reason] call ITW_CLASH_GTFO_fnc_RequestNativeRestRestart'

    assert hardening.index(air_base) < hardening.index(air_restart)
    assert hardening.index(ground_base) < hardening.index(ground_restart)
    assert "canonicalUnwindBeforeGoRest=true" in hardening


def test_gtfo_physical_stall_watch_covers_resting_groups_without_owning_movement():
    hardening = mission("ITW_CLASH_OneZeroHardening.sqf")

    assert "ITW_CLASH_GTFO_PhysicalStallGrace = 180;" in hardening
    assert "ITW_CLASH_GTFO_PhysicalStallCloser = 50;" in hardening
    assert "ITW_CLASH_GTFO_PhysicalStallMoved = 100;" in hardening
    assert 'getVariable ["ITW_CLASH_GTFO_Destination",[]]' in hardening
    assert 'getVariable ["Resting" + str _group,false]' in hardening
    assert '"gtfo-physical-stall"' in hardening
    assert '"physical-stall",' in hardening
    assert "ITW_CLASH_GTFO_fnc_RequestNativeRestRestart" in hardening

    # The watchdog observes physical progress and asks HAL to restart its own
    # retreat. It must not issue a C.L.A.S.H. tactical movement order.
    assert "addWaypoint" not in hardening
    assert "RYD_WPadd" not in hardening
    assert 'setVariable ["Busy" + str _group,false]' not in hardening


def test_native_gocapture_missing_state_is_repaired_before_native_executor():
    hardening = mission("ITW_CLASH_OneZeroHardening.sqf")

    assert "ITW_CLASH_OneZero_fnc_NativeGoCapture = HAL_GoCapture;" in hardening
    assert 'private _key = "Capturing" + str _target + str _hq;' in hardening
    assert 'private _state = _target getVariable [_key,[]];' in hardening
    assert 'private _seed = [_slot + 1,count units _group];' in hardening
    assert '_target setVariable [_key,_seed];' in hardening
    assert '"hal-capture-state-repaired"' in hardening

    repair = hardening.index('_target setVariable [_key,_seed];')
    native = hardening.index("_this call ITW_CLASH_OneZero_fnc_NativeGoCapture")
    assert repair < native


def test_burnin_hardening_is_scheduled_by_required_recon_bridge():
    bridge = mission("ITW_CLASH_ReconPlanningBridge.sqf")

    assert 'fileExists "ITW_CLASH_OneZeroHardening.sqf"' in bridge
    assert 'execVM "ITW_CLASH_OneZeroHardening.sqf"' in bridge
