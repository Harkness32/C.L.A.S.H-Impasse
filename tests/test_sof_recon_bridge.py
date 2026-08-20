from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def doctrine() -> str:
    return text(MISSION / "ITW_CLASH_SOFDoctrine.sqf")


def doctrine_bootstrap() -> str:
    return text(MISSION / "ITW_CLASH_SOFDoctrineBootstrap.sqf")


def bridge() -> str:
    return text(MISSION / "ITW_CLASH_ReconPlanningBridge.sqf")


def test_shared_sof_doctrine_is_presence_based_latched_and_supports_viper_family():
    source = doctrine()
    lower = source.lower()

    for token in ["ranger", "seal", "fsb", "oss", "viper"]:
        assert f'"{token}"' in lower
    assert '["viper",["o_v_"]]' in lower
    assert '"ITW_CLASH_ReconSOFManual"' in source
    assert '"ITW_CLASH_ReconSOFLatched"' in source
    assert '"ITW_CLASH_ReconSOFLatchedFamily"' in source
    assert "private _isSOF = _bestCount > 0;" in source
    assert '"mixed-sof"' in source
    assert "floor ((count _alive) / 2) + 1" not in source


def test_sof_is_hard_excluded_from_clash_anchor_selection_without_fallback():
    source = doctrine()
    assert "ITW_CLASH_fnc_SelectAnchorGroup_SOFBase = ITW_CLASH_fnc_SelectAnchorGroup;" in source
    assert "private _snapshot = +ITW_CLASH_ManagedGroups;" in source
    assert "ITW_CLASH_ManagedGroups = _snapshot - _sofExcluded;" in source
    assert "private _selected = _this call ITW_CLASH_fnc_SelectAnchorGroup_SOFBase;" in source
    assert "ITW_CLASH_ManagedGroups = _snapshot;" in source
    assert '"anchor-sof-excluded"' in source
    assert "emergencyFallback=false" in source


def test_existing_sof_anchors_are_demoted_before_canonical_anchor_audit():
    source = doctrine()
    assert "ITW_CLASH_fnc_AuditAnchors_SOFBase = ITW_CLASH_fnc_AuditAnchors;" in source
    clear_pos = source.index('[_anchorObjective,"sof-ineligible"] call ITW_CLASH_fnc_ClearAnchorSlot;')
    base_pos = source.index("call ITW_CLASH_fnc_AuditAnchors_SOFBase", clear_pos)
    assert clear_pos < base_pos
    assert '"anchor-sof-demoted"' in source


def test_sof_doctrine_bootstrap_has_narrow_fail_open_finalization_window():
    source = doctrine_bootstrap()
    assert 'ITW_CLASH_LateDoctrineFinalizers = [' in source
    assert '"ITW_CLASH_fnc_SelectAnchorGroup"' in source
    assert '"ITW_CLASH_fnc_AuditAnchors"' in source
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_Bootstrap.sqf"' in source
    assert 'private _path = "ITW_CLASH_SOFDoctrine.sqf";' in source
    assert "ITW_CLASH_LateDoctrineFinalizers = [];" in source
    assert "corrected V6 anchor policy retained" in source


def test_compile_final_honors_only_synchronous_named_doctrine_window():
    source = text(MISSION / "scripts" / "SKULL" / "SKL_CompileFinal.sqf")
    assert '"ITW_CLASH_LateDoctrineFinalizers"' in source
    assert "_lateDoctrineFinalizers" in source
    assert "_deferredFinalizers +" in source
    assert "_persistentDeferredFinalizers +" in source
    assert "_lateDoctrineFinalizers" in source


def test_init_wires_sof_doctrine_before_runtime_recon_bridge():
    source = text(MISSION / "init.sqf")
    doctrine_pos = source.index('ITW_CLASH_SOFDoctrineBootstrap.sqf')
    recon_observer_pos = source.index('ITW_CLASH_ReconObserver.sqf')
    planning_pos = source.index('ITW_CLASH_ReconPlanningBridge.sqf')
    assert doctrine_pos < recon_observer_pos < planning_pos
    assert "native SpecFor recon exclusion retained" in source


def test_recon_bridge_wraps_native_hal_planners_instead_of_assigning_missions_itself():
    source = bridge()
    assert "ITW_CLASH_ReconPlanning_fnc_NativeHQOrders = HAL_HQOrders;" in source
    assert "ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef = HAL_HQOrdersDef;" in source
    assert "HAL_HQOrders = {" in source
    assert "HAL_HQOrdersDef = {" in source
    assert "_args call _native" in source
    for forbidden in [
        "HAL_GoRecon = {",
        "HAL_GoDefRecon = {",
        "addWaypoint",
        "createUnit",
        "createVehicle",
        "ITW_TICKET_REDUCE",
        "ITW_AtkSpawnVeh",
        "RydHQ_ROnly",
    ]:
        assert forbidden not in source
    assert "halChooses=true" in source


def test_offensive_recon_window_preserves_specfor_identity_and_uses_native_recon_demand():
    source = bridge()
    assert 'private _specFor0 = +(_hq getVariable ["RydHQ_SpecForG",[]]);' in source
    assert 'private _recon0 = +(_hq getVariable ["RydHQ_ReconG",[]]);' in source
    assert 'private _noRecon0 = +(_hq getVariable ["RydHQ_NoRecon",[]]);' in source
    assert "private _specForWindow = _specFor0 - _eligible;" in source
    assert "_reconWindow pushBackUnique _x" in source
    assert '!( _hq getVariable ["RydHQ_ReconDone",false])' not in source  # spacing contract below
    assert '!(_hq getVariable ["RydHQ_ReconDone",false])' in source
    assert '"RydHQ_SpecForG",+_specFor0' in source
    assert '"RydHQ_ReconG",+_recon0' in source
    assert '"RydHQ_NoRecon",+_noRecon0' in source
    assert "specForPersistent=true" in source


def test_defensive_recon_window_keeps_sof_out_of_normal_defense_only_during_planning():
    source = bridge()
    assert 'if (_mode isEqualTo "defensive") then {' in source
    assert '"RydHQ_Friends",_friends0 - _eligible' in source
    assert '"RydHQ_NoDef",_noDef0 - _eligible' in source
    assert '"RydHQ_Friends",+_friends0' in source
    assert '"RydHQ_NoDef",+_noDef0' in source


def test_recon_bridge_rejects_gtfo_recovery_busy_and_exhausted_sof():
    source = bridge()
    for token in [
        '"ITW_CLASH_GTFO",false',
        '"ITW_CLASH_Withdrawing",false',
        '"ITW_CLASH_CASEVAC_State",""',
        '"ITW_CLASH_GroundMEDEVAC_State",""',
        '"Busy" + str _group,false',
        '"RydHQ_Exhausted",[]',
    ]:
        assert token in source


def test_recon_planning_window_has_dead_man_snapshot_restoration():
    source = bridge()
    assert '"ITW_CLASH_ReconPlanningSnapshot"' in source
    assert "ITW_CLASH_ReconPlanning_fnc_RestoreSnapshot" in source
    assert '"window-recovered"' in source
    assert "ITW_CLASH_ReconPlanningRecoveryTimeout = 5;" in source
    assert "ITW_CLASH_ReconPlanningRecoveryWatch" in source
    snapshot_pos = source.index('_hq setVariable ["ITW_CLASH_ReconPlanningSnapshot"')
    mutate_pos = source.index('_hq setVariable ["RydHQ_SpecForG",_specForWindow]', snapshot_pos)
    assert snapshot_pos < mutate_pos


def test_native_hal_sources_confirm_why_the_bridge_is_needed():
    offense = text(HAL / "HQOrders.sqf")
    defense = text(HAL / "HQOrdersDef.sqf")
    listing = [p.name for p in HAL.iterdir()]

    assert '(_HQ getVariable ["RydHQ_SpecForG",[]])' in offense
    assert '(_HQ getVariable ["RydHQ_ReconG",[]])' in offense
    assert '(_HQ getVariable ["RydHQ_SpecForG",[]])' in defense
    assert '_recDef' in defense
    assert "GoSFAttack.sqf" in listing
    assert "SFIdleOrd.sqf" in listing
