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


def test_recon_bridge_removes_only_prior_semantic_specfor_memberships():
    bridge = mission("ITW_CLASH_ReconPlanningBridge.sqf")

    assert "ITW_CLASH_ReconPlanningBridgeVersion = 3;" in bridge
    assert '"ITW_CLASH_ReconPlanningSemanticSpecFor"' in bridge
    assert '_specFor = _specFor - _previousSemantic;' in bridge
    assert 'getVariable ["ITW_CLASH_SOFNativeProtected",false]' in bridge
    assert '_hq setVariable ["RydHQ_SpecForG",_specFor];' in bridge
    assert "staleSemanticRemoval=true" in bridge

    # Native HAL SpecFor is the base; C.L.A.S.H. removes only its own previous
    # injections before recalculating semantic identity.
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


def test_sof_standby_uses_hq_side_attack_slots_without_changing_shared_corridor():
    sf = mission("ITW_CLASH_HALNativeSFFix.sqf")

    assert "ITW_CLASH_HALNativeSFFixVersion = 3;" in sf
    assert "ITW_CLASH_HALNativeSF_fnc_GetSupportCorridorSpawn" in sf
    assert "ITW_ATTACK_LAND_F" in sf
    assert "ITW_ATTACK_AIR_F" in sf
    assert "ITW_ATTACK_LAND_E" in sf
    assert "ITW_ATTACK_AIR_E" in sf
    assert "ITW_PlayerSide" in sf
    assert "ITW_EnemySide" in sf
    assert 'if (_baseIndex < 0 && {count _attacks > _airSlot}) then {' in sf
    assert '] call ITW_CLASH_HALNativeSF_fnc_GetSupportCorridorSpawn;' in sf
    assert 'call ITW_CLASH_fnc_GetSupportCorridorSpawn' not in sf
    assert 'call ITW_CLASH_fnc_GetHomeBaseSpawn' not in sf
    assert "sideAwareStandby=true" in sf


def test_sof_direct_action_wrapper_is_observer_only_and_preserves_native_executor():
    sf = mission("ITW_CLASH_HALNativeSFFix.sqf")

    assert "ITW_CLASH_HALNativeSF_fnc_GoSFAttackPatched = compile _attackSource;" in sf
    assert '"sof-direct-action-dispatched"' in sf
    assert '"sof-direct-action-returned"' in sf
    assert "_this call ITW_CLASH_HALNativeSF_fnc_GoSFAttackPatched" in sf
    assert "RydHQ_EnArtG" in sf
    assert "RydHQ_EnStaticG" in sf
    assert "RydxHQ_AllLeaders" in sf
    assert "nativeExecutorPreserved=true" in sf

    wrapper_start = sf.index("HAL_GoSFAttack = {")
    wrapper_end = sf.index(
        "ITW_CLASH_HALNativeSF_fnc_GetSupportCorridorSpawn = {",
        wrapper_start,
    )
    wrapper = sf[wrapper_start:wrapper_end]

    # This layer is telemetry only. Native HAL remains solely responsible for
    # direct-action movement and its Busy/Resting lifecycle.
    assert "addWaypoint" not in wrapper
    assert "RYD_WPadd" not in wrapper
    assert 'setVariable ["Busy"' not in wrapper
    assert 'setVariable ["Resting"' not in wrapper
