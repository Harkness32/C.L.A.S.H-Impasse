from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_transit_finalizer_is_deferred_during_preinit_before_attack_compile():
    pre = text("preInit.sqf")
    defer_at = pre.index('"ITW_AtkReconstitutionTransitManager"')
    attack_at = pre.index('preprocessFileLineNumbers "ITW_Attack.sqf"')
    fix_at = pre.index('preprocessFileLineNumbers "ITW_CLASH_ReconstitutionTransitFix.sqf"')
    assert defer_at < attack_at < fix_at


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


def test_transit_fix_is_synchronous_and_final_before_gameplay():
    source = text("ITW_CLASH_ReconstitutionTransitFix.sqf")
    assert "ITW_CLASH_ReconstitutionTransitFixVersion = 4;" in source
    assert '"ITW_AtkReconstitutionTransitManagerStarted",false' in source
    remove_at = source.index('_deferred = _deferred - ["ITW_AtkReconstitutionTransitManager"]')
    finalize_at = source.index('["ITW_AtkReconstitutionTransitManager"] call SKL_fnc_CompileFinal;')
    assert remove_at < finalize_at
    assert "waitUntil" not in source
    assert "sleep 0.1" not in source
    assert "preInit=true" in source
    assert "vehicleOwnershipGate=true" in source


def test_transit_manager_uses_authoritative_live_dispatch_state():
    source = text("ITW_CLASH_ReconstitutionTransitFix.sqf")
    assert 'private _liveState = _group getVariable ["ITW_CLASH_TransitState",""];' in source
    assert 'private _liveVehicle = _group getVariable ["ITW_CLASH_TransitVehicle",objNull];' in source
    assert '_liveState isEqualTo "transport"' in source
    assert '!isNull _liveVehicle && {alive _liveVehicle}' in source
    assert '"reconstitution-dispatch-state"' in source
    assert 'private _dispatched =' not in source
    assert 'if (_dispatched)' not in source


def test_handoff_waits_for_impasse_vehicle_manager_and_arma_assignment_cleanup():
    source = text("ITW_CLASH_ReconstitutionTransitFix.sqf")
    wait_at = source.index('"reconstitution-handoff-wait"')
    acknowledge_at = source.index("ITW_CLASH_fnc_AcknowledgeReconstitution")
    assert "assignedVehicles _group" in source
    assert "{unassignVehicle _x} forEach _aliveUnits;" in source
    assert "ITW_ManagedVehs findIf" in source
    assert "VEHINFO_CARGO_GRPS" in source
    assert "VEHINFO_CREW_GRP" in source
    assert "private _handoffBlocked" in source
    assert "VAR_SET_OBJ_IDX(_group,_objectiveIndex);" in source
    assert wait_at < acknowledge_at


def test_init_never_attempts_late_transit_override():
    init = text("init.sqf")
    assert 'execVM "ITW_CLASH_ReconstitutionTransitFix.sqf"' not in init
    assert "reconstitution-preinit-authority-confirmed" in init
