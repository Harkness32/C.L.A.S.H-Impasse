from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_service_identity_is_explicit_per_deployment_lease():
    authority = mission("ITW_CLASH_ServiceAuthority.sqf")
    assert 'setVariable ["ITW_CLASH_ServiceLease",+_lease,true]' in authority
    assert 'setVariable ["ITW_CLASH_ServiceLease",+_lease]' in authority
    assert 'getVariable ["ITW_CLASH_ServiceLease",[]]' in authority
    assert '"no-explicit-service-lease"' in authority


def test_service_identity_no_longer_continuously_rewrites_hal_planning_arrays():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    quarantine = stability.split(
        "ITW_CLASH_ServiceStability_fnc_EnsureQuarantine = {", 1
    )[1].split("ITW_CLASH_ServiceStability_fnc_RetireBase", 1)[0]
    assert "Compatibility shim" in stability
    assert "HAL owns live disposition and SitRep" in stability
    assert 'scriptName "ITW_CLASH_ServiceQuarantineWatch"' not in stability
    for name in [
        "RydHQ_NoAttack", "RydHQ_NoRecon", "RydHQ_NoDef",
        "RydHQ_AttackAv", "RydHQ_FlankAv", "RydHQ_CombatAv",
        "RydHQ_ReconAv", "RydHQ_ReconG", "RydHQ_DefRes",
        "RydHQ_CargoG", "RydHQ_CargoOnly", "RydHQ_AirG",
    ]:
        assert name not in quarantine


def test_service_role_guards_still_reject_accidental_combat_recon_or_defense_execution():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    execution = mission("ITW_CLASH_ServiceExecutionGuards.sqf")
    assert "HAL_GoRecon =" in stability
    assert "HAL_GoDefRecon =" in stability
    for fn in [
        "HAL_GoAttInf", "HAL_GoAttArmor", "HAL_GoAttSniper",
        "HAL_GoAttAir", "HAL_GoAttAirCAP", "HAL_GoAttNaval",
        "HAL_GoDef", "HAL_GoDefAir", "HAL_GoDefNav", "HAL_GoDefRes",
    ]:
        assert f"{fn} =" in execution
    assert "ITW_CLASH_ServiceStability_fnc_HasLease" in execution


def test_player_priority_layers_are_not_part_of_service_lifecycle_refactor():
    dispatch = mission("ITW_CLASH_PlayerDemandDispatch.sqf")
    interceptors = mission("ITW_CLASH_PlayerDemandNativeInterceptors.sqf")
    assert "ITW_CLASH_PlayerDemand" in dispatch
    assert "ITW_CLASH_PlayerDemand" in interceptors
    assert "ITW_CLASH_ServicePassiveReturnMonitor" not in dispatch
    assert "ITW_CLASH_ServicePassiveReturnMonitor" not in interceptors
