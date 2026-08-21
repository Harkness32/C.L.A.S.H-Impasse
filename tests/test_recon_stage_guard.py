from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def test_semantic_sof_is_protected_before_native_hal_planning_without_recon_stage_hacks():
    source = (MISSION / "ITW_CLASH_ReconPlanningBridge.sqf").read_text(encoding="utf-8")

    # The only pre-planning compatibility mutation is SpecFor identity. Native
    # HAL then excludes those groups from ordinary recon/conventional task pools.
    assert '[_hq,"offensive"] call ITW_CLASH_ReconPlanning_fnc_SyncSpecFor;' in source
    assert '[_hq,"defensive"] call ITW_CLASH_ReconPlanning_fnc_SyncSpecFor;' in source
    assert 'setVariable ["RydHQ_SpecForG",_specFor]' in source

    # Broad native reconnaissance remains untouched: no conventional NoRecon
    # filter and no asynchronous native stage rewind are allowed.
    assert 'setVariable ["RydHQ_NoRecon"' not in source
    assert "private _blockedManaged" not in source
    lower = source.lower()
    assert 'setvariable ["rydhq_reconstage"' not in lower
    assert 'setvariable ["rydhq_reconstage2"' not in lower
