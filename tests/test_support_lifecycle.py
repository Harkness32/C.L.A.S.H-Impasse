from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_service_crews_are_exempt_without_replacing_native_impasse_cap_math():
    preinit = mission("preInit.sqf")
    assert '"ITW_AtkAiCount"' in preinit
    assert "ITW_CLASH_Cap_fnc_NativeAtkAiCount = ITW_AtkAiCount;" in preinit
    assert "_native + ([_side] call ITW_CLASH_Cap_fnc_ExemptUnits)" in preinit
    assert 'getVariable ["ITW_CLASH_CapExempt",false]' in preinit


def test_service_lifecycle_virtualizes_only_after_observed_hal_return():
    service = mission("ITW_CLASH_ServiceLifecycle.sqf")
    assert "ITW_CLASH_ServicePassiveReturnMonitor" in service
    assert '"hal-return-zone-entered"' in service
    assert '[_i,"hal-returned-home"] call ITW_CLASH_Service_fnc_Retire;' in service
    assert "passiveHALReturn=true" in service
    assert "clashOrdersRTB=false" in service
    assert "halOwnsLiveDisposition=true" in service
    assert "ITW_CLASH_Service_fnc_OrderRTB" not in service
    assert "ITW_CLASH_Service_fnc_ReissueRTB" not in service
    assert 'set ["state","RTB"]' not in service
    assert 'setWaypointType "MOVE"' not in service


def test_virtual_reactivation_is_capacity_safe_and_free_for_paid_entitlement():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    assert "ITW_CLASH_ServiceStabilityVersion = 5;" in stability
    assert 'set ["state","AVAILABLE"]' in stability
    assert "(_vehDef#ITW_VEH_COUNT) >= (_vehDef#ITW_VEH_MAX)" in stability
    assert "ITW_VEH_COUNT_INCR(_vehDef);" in stability
    assert '["ticketCost",0]' in stability
    assert '["reused",true]' in stability
    assert "ITW_TICKET_REDUCE(_vehDef)" not in stability
    assert "tacticalQuarantine=false" in stability
    assert "halOwnsLiveDisposition=true" in stability


def test_latest_air_quarantine_patch_is_unwound():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    authority = mission("ITW_CLASH_ServiceAuthority.sqf")
    assert "ITW_CLASH_ServiceAuthorityVersion = 3;" in authority
    assert "impasse-handoff-immediate" not in authority
    assert "immediateTransportQuarantine=true" not in authority
    quarantine = stability.split(
        "ITW_CLASH_ServiceStability_fnc_EnsureQuarantine = {", 1
    )[1].split("ITW_CLASH_ServiceStability_fnc_RetireBase", 1)[0]
    for tactical_array in [
        "RydHQ_NoAttack", "RydHQ_NoRecon", "RydHQ_NoDef",
        "RydHQ_AttackAv", "RydHQ_FlankAv", "RydHQ_CombatAv",
        "RydHQ_CargoG", "RydHQ_CargoOnly", "RydHQ_AirG",
    ]:
        assert tactical_array not in quarantine
    assert 'scriptName "ITW_CLASH_ServiceQuarantineWatch"' not in stability


def test_virtual_transport_reactivation_chooses_best_capacity_fit_not_first_pool_entry():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    assert "ITW_CLASH_ServiceStabilityVersion = 5;" in stability
    assert "ITW_CLASH_ServiceCapacity_fnc_ScoreClass" in stability
    assert '"TRANSPORT_POOL"' in stability
    assert "private _eligibleIndices = [];" in stability
    assert "transportBestFit=true" in stability


def test_service_storage_is_any_friendly_base_area_not_exact_home_point():
    service = mission("ITW_CLASH_ServiceLifecycle.sqf")
    assert "ITW_CLASH_ServiceLifecycleVersion = 4;" in service
    assert "ITW_CLASH_Service_fnc_StorageZone" in service
    assert "ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices" in service
    assert "nearest-friendly-base-zone" in service
    assert '"ITW_CLASH_ServiceRTBLandRadius",150' in service
    assert '"ITW_CLASH_ServiceRTBAirRadius",300' in service
    assert '"ITW_CLASH_ServiceIdleGrace",10' in service
    assert '"ITW_CLASH_ServiceInitialStorageGrace",45' in service
    assert '"ITW_CLASH_ServiceIdleSpeedMax",3' in service
    assert "private _settled = (abs speed _veh) <= ITW_CLASH_ServiceIdleSpeedMax;" in service
    assert 'time - _spawnedAt < ITW_CLASH_ServiceInitialStorageGrace' in service
    assert "anyFriendlyBaseStorage=true" in service
    assert "areaTrigger=true" in service


def test_logistics_capabilities_are_virtualized_and_reused():
    service = mission("ITW_CLASH_ServiceLifecycle.sqf")
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    authority = mission("ITW_CLASH_ServiceAuthority.sqf")
    wrappers = service.split("ITW_CLASH_Service_fnc_InstallProviderWrappers = {",1)[1].split(
        "call ITW_CLASH_Service_fnc_InstallProviderWrappers;",1
    )[0]
    for capability in ["LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"]:
        assert f'"{capability}"' in wrappers
    assert "logisticsVirtualization=true" in authority
    assert "logisticsReuse=true" in stability
