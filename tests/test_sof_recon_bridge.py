from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def doctrine() -> str:
    return text(MISSION / "ITW_CLASH_SOFDoctrine.sqf")


def bridge() -> str:
    return text(MISSION / "ITW_CLASH_ReconPlanningBridge.sqf")


def sf_fix() -> str:
    return text(MISSION / "ITW_CLASH_HALNativeSFFix.sqf")


def test_shared_sof_identity_is_presence_based_latched_and_supports_viper_family():
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


def test_sof_is_hard_excluded_from_clash_anchor_selection_without_fallback():
    source = doctrine()
    assert "ITW_CLASH_fnc_SelectAnchorGroup_SOFBase = ITW_CLASH_fnc_SelectAnchorGroup;" in source
    assert "private _snapshot = +ITW_CLASH_ManagedGroups;" in source
    assert "ITW_CLASH_ManagedGroups = _snapshot - _sofExcluded;" in source
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


def test_planning_bridge_only_adds_semantic_sof_to_native_specfor_identity():
    source = bridge()
    assert "ITW_CLASH_ReconPlanningBridgeVersion = 2;" in source
    assert "ITW_CLASH_ReconPlanning_fnc_SyncSpecFor" in source
    assert 'getVariable ["RydHQ_SpecForG",[]]' in source
    assert 'setVariable ["RydHQ_SpecForG",_specFor]' in source
    assert '"ITW_CLASH_SOFNativeProtected",true' in source
    assert "semanticSpecForBridge=true" in source

    # C.L.A.S.H. no longer creates a temporary SOF-only reconnaissance window.
    for forbidden in [
        'setVariable ["RydHQ_ReconG"',
        'setVariable ["RydHQ_NoRecon"',
        'setVariable ["RydHQ_Friends"',
        'setVariable ["RydHQ_NoDef"',
        '"ITW_CLASH_ReconPlanningSnapshot"',
        "private _blockedManaged",
        "_specForWindow",
        "_reconWindow",
        "_noReconWindow",
    ]:
        assert forbidden not in source


def test_planning_bridge_leaves_native_hal_in_charge_of_offense_and_defense():
    source = bridge()
    assert "ITW_CLASH_ReconPlanning_fnc_NativeHQOrders = HAL_HQOrders;" in source
    assert "ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef = HAL_HQOrdersDef;" in source
    assert "HAL_HQOrders = {" in source
    assert "HAL_HQOrdersDef = {" in source
    assert "_this call ITW_CLASH_ReconPlanning_fnc_NativeHQOrders" in source
    assert "_this call ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef" in source
    assert "nativeBroadRecon=true" in source
    assert "halChooses=true" in source


def test_native_hal_orders_explicitly_protect_specfor_from_ordinary_recon():
    orders = text(HAL / "HQOrders.sqf")
    assert 'RydHQ_SpecForG' in orders
    assert '_ReconAv' in orders
    assert 'HAL_GoRecon' in orders
    assert 'not (_x in (_ReconAv + (_HQ getVariable ["RydHQ_SpecForG",[]])))' in orders


def test_idle_sof_stages_at_support_corridor_instead_of_guarding_commander():
    source = sf_fix()
    assert "ITW_CLASH_HALNativeSFFixVersion = 2;" in source
    assert "HAL_SFIdleOrd = {" in source
    assert 'call ITW_CLASH_fnc_GetSupportCorridorSpawn' in source
    assert 'call ITW_CLASH_fnc_GetHomeBaseSpawn' in source
    assert '"Special Operations Standby"' in source
    assert '"HOLD","AWARE","RED","NORMAL"' in source
    assert '"sof-standby"' in source
    assert "commanderGuard=false" in source
    assert '["Guard HQ.", "Guard", ""]' not in source
    assert "HAL_SFIdleOrd = compile _idleSource;" not in source


def test_native_go_sf_attack_is_preserved_with_verified_source_repairs():
    source = sf_fix()
    assert "HAL_GoSFAttack = compile _attackSource;" in source
    assert "GoSFAttack-objective-fallback" in source
    assert "GoSFAttack-WP4-X" in source
    assert "GoSFAttack-WP4-Y" in source
    assert "goSFAttack=native-patched" in source


def test_init_wires_sof_doctrine_before_runtime_recon_bridge():
    source = text(MISSION / "init.sqf")
    doctrine_pos = source.index('ITW_CLASH_SOFDoctrineBootstrap.sqf')
    recon_observer_pos = source.index('ITW_CLASH_ReconObserver.sqf')
    planning_pos = source.index('ITW_CLASH_ReconPlanningBridge.sqf')
    assert doctrine_pos < recon_observer_pos < planning_pos
