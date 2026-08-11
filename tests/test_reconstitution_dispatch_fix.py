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


def test_dispatch_fix_waits_for_attack_file_tail_before_wrapping():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    assert '!isNil "ITW_AtkDispatchReconstitutionTransport"' in source
    assert '!isNil "ITW_AtkDeliveryCntChange"' in source
    assert "sleep 0.1;" in source


def test_dispatch_fix_wraps_base_and_returns_live_transport_state():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    assert "ITW_CLASH_AtkDispatchReconstitutionTransport_V6Base" in source
    assert '_this call ITW_CLASH_AtkDispatchReconstitutionTransport_V6Base;' in source
    assert '_group getVariable ["ITW_CLASH_TransitVehicle",objNull]' in source
    assert '_group getVariable ["ITW_CLASH_TransitState",""]' in source
    assert '_state isEqualTo "transport"' in source
    assert '!isNull _vehicle && {alive _vehicle}' in source
    assert '"reconstitution-dispatch-return"' in source


def test_dispatch_fix_finalizes_after_removing_deferral():
    source = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    remove_at = source.index('_deferred = _deferred - ["ITW_AtkDispatchReconstitutionTransport"]')
    finalize_at = source.index('[\n    "ITW_AtkDispatchReconstitutionTransport"\n] call SKL_fnc_CompileFinal;')
    assert remove_at < finalize_at
    assert 'reconstitution-dispatch-fix-ready' in source


def test_logistics_guard_remains_belt_and_suspenders():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert '"reconstitution-transit-state-synced"' in guard
    assert '_cachedState isEqualTo "waiting-transport"' in guard
    assert '_liveState isEqualTo "waiting-transport"' in guard
