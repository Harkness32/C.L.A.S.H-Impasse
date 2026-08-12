from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_transit_manager_finalizer_is_deferred_before_attack_startup():
    init = text("init.sqf")
    assert 'pushBackUnique "ITW_AtkReconstitutionTransitManager"' in init
    assert 'execVM "ITW_CLASH_ReconstitutionTransitFix.sqf"' in init
    assert init.index('pushBackUnique "ITW_AtkReconstitutionTransitManager"') < init.index('execVM "ITW_Start.sqf"')


def test_transit_fix_uses_tighter_near_ao_handoff_buffer():
    source = text("ITW_CLASH_ReconstitutionTransitFix.sqf")
    assert "ITW_CLASH_ReconstitutionHandoffBuffer = 250;" in source
    assert "ITW_ParamTransportUnloadDist +" in source
    assert "ITW_CLASH_ReconstitutionHandoffBuffer" in source
    assert "+ 850" not in source
    assert "_distance <= _handoffRadius" in source


def test_transit_fix_preserves_physical_transit_and_fallbacks():
    source = text("ITW_CLASH_ReconstitutionTransitFix.sqf")
    assert '"ITW_CLASH_ReconstitutionTransit",nil' in source
    assert '"ITW_CLASH_TransitVehicle",nil' in source
    assert "ITW_CLASH_fnc_AcknowledgeReconstitution" in source
    assert "ITW_EnemyGroupCallback" in source
    assert '"reconstitution-transit-arrived"' in source
    assert '"reconstitution-transport-interrupted"' in source
    assert '"reconstitution-transport-fallback-walk"' in source


def test_transit_fix_finalizes_before_any_manager_can_start():
    source = text("ITW_CLASH_ReconstitutionTransitFix.sqf")
    assert '"ITW_AtkReconstitutionTransitManagerStarted",false' in source
    assert "reconstitution-transit-fix-manager-already-running" in source
    remove_at = source.index('_deferred = _deferred - ["ITW_AtkReconstitutionTransitManager"]')
    finalize_at = source.index('["ITW_AtkReconstitutionTransitManager"] call SKL_fnc_CompileFinal;')
    assert remove_at < finalize_at
    assert "reconstitution-transit-fix-ready" in source
