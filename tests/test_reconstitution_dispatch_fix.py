from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_dispatch_finalizer_is_deferred_during_preinit_before_attack_compile():
    pre = text("preInit.sqf")
    defer_at = pre.index('"ITW_AtkDispatchReconstitutionTransport"')
    attack_at = pre.index('preprocessFileLineNumbers "ITW_Attack.sqf"')
    fix_at = pre.index('preprocessFileLineNumbers "ITW_CLASH_ReconstitutionDispatchFix.sqf"')
    assert defer_at < attack_at < fix_at


def test_init_does_not_retry_a_final_attack_function():
    init = text("init.sqf")
    assert 'execVM "ITW_CLASH_ReconstitutionDispatchFix.sqf"' not in init
    assert "reconstitution-preinit-authority-confirmed" in init
    assert "late-overrides-skipped" in init


def test_dispatch_fix_is_synchronous_preinit_version_3():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    assert "ITW_CLASH_ReconstitutionDispatchFixVersion = 3;" in source
    assert 'ITW_AtkDispatchReconstitutionTransport = {' in source
    assert 'for "_candidateIndex" from 0 to ((count _ordered) - 1) do {' in source
    assert 'scopeName "ITW_CLASH_ReconstitutionDispatch"' not in source
    assert 'breakOut "ITW_CLASH_ReconstitutionDispatch"' not in source
    assert "waitUntil" not in source
    assert "sleep 0.1" not in source
    assert "preInit=true" in source


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


def test_dispatch_fix_finalizes_inside_preinit_window():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    remove_at = source.index('_deferred = _deferred - ["ITW_AtkDispatchReconstitutionTransport"]')
    finalize_at = source.index('["ITW_AtkDispatchReconstitutionTransport"] call SKL_fnc_CompileFinal;')
    assert remove_at < finalize_at
    assert "ITW_CLASH_ReconstitutionDispatchFixReady = _finalized;" in source


def test_logistics_guard_remains_belt_and_suspenders():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert '"reconstitution-transit-state-synced"' in guard
    assert '_cachedState isEqualTo "waiting-transport"' in guard
    assert '_liveState isEqualTo "waiting-transport"' in guard
