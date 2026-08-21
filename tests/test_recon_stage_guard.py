from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def test_conventional_groups_are_filtered_before_native_offensive_recon_dispatch():
    source = (MISSION / "ITW_CLASH_ReconPlanningBridge.sqf").read_text(encoding="utf-8")

    # Native HQOrders increments ReconStage/ReconStage2 before spawning GoRecon.
    # The bridge must therefore prevent non-SOF managed groups from entering the
    # native candidate pool rather than trying to decrement counters afterward.
    assert "private _blockedManaged = ITW_CLASH_ManagedGroups - _eligible;" in source
    assert "{_noReconWindow pushBackUnique _x} forEach _blockedManaged;" in source
    assert "_noReconWindow = _noReconWindow - _eligible;" in source
    assert '"RydHQ_NoRecon",_noReconWindow' in source
    assert "conventionalStageGuard=true" in source

    # No asynchronous counter rewind is permitted; objective-local ReconStage2
    # can already have been reset by the time a spawned rejection runs.
    assert 'setVariable ["RydHQ_ReconStage",(_hq getVariable' not in source.lower()
    assert 'setVariable ["RydHQ_ReconStage2",(_hq getVariable' not in source.lower()
