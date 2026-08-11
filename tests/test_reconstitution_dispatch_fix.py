from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_dispatch_finalizer_is_deferred_before_attack_startup():
    init = text("init.sqf")
    assert 'pushBackUnique "ITW_AtkDispatchReconstitutionTransport"' in init
    assert 'execVM "ITW_CLASH_ReconstitutionDispatchFix.sqf"' in init
    assert init.index('pushBackUnique "ITW_AtkDispatchReconstitutionTransport"') < init.index('execVM "ITW_Start.sqf"')


def test_dispatch_fix_waits_for_attack_file_tail_before_replacing():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    assert '!isNil "ITW_AtkDispatchReconstitutionTransport"' in source
    assert '!isNil "ITW_AtkDeliveryCntChange"' in source
    assert "sleep 0.1;" in source


def test_dispatch_fix_replaces_buggy_named_scope_path_at_source():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    assert 'ITW_AtkDispatchReconstitutionTransport = {' in source
    assert 'for "_candidateIndex" from 0 to ((count _ordered) - 1) do {' in source
    assert "private _dispatched = false;" in source
    assert "_dispatched = true;" in source
    assert 'scopeName "ITW_CLASH_ReconstitutionDispatch"' not in source
    assert 'breakOut "ITW_CLASH_ReconstitutionDispatch"' not in source
    assert "ITW_CLASH_AtkDispatchReconstitutionTransport_V6Base" not in source


def test_dispatch_fix_preserves_impasse_transport_side_effects():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    assert "ITW_AtkSpawnVeh" in source
    assert "ITW_AtkAddVehicle" in source
    assert "ITW_VEH_COUNT_INCR" in source
    assert "ITW_TICKET_REDUCE" in source
    assert '"ITW_CLASH_TransitVehicle"' in source
    assert '"ITW_CLASH_TransitState","transport"' in source
    assert '"reconstitution-transport-dispatched"' in source
    assert '"reconstitution-dispatch-return"' in source


def test_dispatch_fix_finalizes_after_removing_deferral():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    remove_at = source.index('_deferred = _deferred - ["ITW_AtkDispatchReconstitutionTransport"]')
    finalize_at = source.index('["ITW_AtkDispatchReconstitutionTransport"] call SKL_fnc_CompileFinal;')
    assert remove_at < finalize_at
    assert 'reconstitution-dispatch-fix-ready | version=2 source-corrected=true' in source


def test_logistics_guard_remains_belt_and_suspenders():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert '"reconstitution-transit-state-synced"' in guard
    assert '_cachedState isEqualTo "waiting-transport"' in guard
    assert '_liveState isEqualTo "waiting-transport"' in guard
