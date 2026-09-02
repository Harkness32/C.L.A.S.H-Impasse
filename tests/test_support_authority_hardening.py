from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_service_identity_is_an_explicit_per_deployment_lease_not_shared_vehdef_state():
    authority = mission("ITW_CLASH_ServiceAuthority.sqf")

    assert 'setVariable ["ITW_CLASH_ServiceLease",+_lease,true]' in authority
    assert 'setVariable ["ITW_CLASH_ServiceLease",+_lease]' in authority
    assert 'getVariable ["ITW_CLASH_ServiceLease",[]]' in authority
    assert "VEHINFO_IS_DUAL_AS_TRANSPORT" in authority
    assert "_role == ITW_VEH_ROLE_DUAL && {_dualAsTransport}" in authority
    assert '"no-explicit-service-lease"' in authority
    assert "_vehDef set [ITW_VEH_IS_DUAL_AS_TRANSPORT" not in authority
    assert "_vehDef set [ITW_VEH_ROLE" not in authority


def test_duplicate_registration_preserves_live_lifecycle_and_home_state():
    authority = mission("ITW_CLASH_ServiceAuthority.sqf")
    assert "_sameLivePhysical" in authority
    assert "_newDeployment = _newEntry || {!_sameLivePhysical}" in authority
    assert 'if (_newDeployment || {_home isEqualTo []}) then {' in authority
    assert 'if (_newDeployment) then {' in authority
    assert '"physical-registration-refreshed"' in authority


def test_service_quarantine_is_reasserted_across_all_planning_surfaces():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    for name in ["RydHQ_NoAttack", "RydHQ_NoRecon", "RydHQ_NoDef"]:
        assert f'"{name}"' in stability
    for name in [
        "RydHQ_AttackAv", "RydHQ_FlankAv", "RydHQ_CombatAv",
        "RydHQ_ReconAv", "RydHQ_ReconG", "RydHQ_DefRes",
    ]:
        assert f'"{name}"' in stability
    assert 'scriptName "ITW_CLASH_ServiceQuarantineWatch"' in stability
    assert 'sleep 1;' in stability
    assert '[_group,"pool-watch"] call ITW_CLASH_ServiceStability_fnc_EnsureQuarantine;' in stability


def test_service_quarantine_guards_recon_attack_and_defense_execution():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    execution = mission("ITW_CLASH_ServiceExecutionGuards.sqf")
    sea = mission("ITW_CLASH_SeaGenerationGuard.sqf")
    assert "HAL_GoRecon =" in stability
    assert "HAL_GoDefRecon =" in stability
    assert '"RECON","offensive"' in stability
    assert '"RECON","defensive"' in stability
    for fn in [
        "HAL_GoAttInf", "HAL_GoAttArmor", "HAL_GoAttSniper",
        "HAL_GoAttAir", "HAL_GoAttAirCAP", "HAL_GoAttNaval",
    ]:
        assert f"{fn} =" in execution
    assert '"ATTACK","GoAttInf"' in execution
    assert '"ATTACK","GoAttNaval"' in execution
    assert 'if (!isNil "HAL_GoFlank")' in execution
    assert 'if (!isNil "HAL_GoSFAttack")' in execution
    for fn in ["HAL_GoDef", "HAL_GoDefAir", "HAL_GoDefNav", "HAL_GoDefRes"]:
        assert f"{fn} =" in execution
    assert '"DEFENSE","GoDef"' in execution
    assert '"DEFENSE","GoDefRes"' in execution
    assert 'setVariable ["Busy" + str _group,false]' in execution
    assert "ITW_CLASH_ServiceStability_fnc_HasLease" in execution
    assert "attackGuard=true defenseGuard=true reconGuard=service-stability" in execution
    assert '[] execVM "ITW_CLASH_ServiceExecutionGuards.sqf";' in sea


def test_virtual_pool_is_entitlement_while_physical_count_stays_native():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    assert 'set ["state","AVAILABLE"]' in stability
    assert '"physical-recount-authoritative"' in stability
    assert "(_vehDef#ITW_VEH_COUNT) >= (_vehDef#ITW_VEH_MAX)" in stability
    assert "ITW_VEH_COUNT_INCR(_vehDef);" in stability
    assert '["ticketCost",0]' in stability
    assert '["reused",true]' in stability
    assert "ITW_TICKET_REDUCE(_vehDef)" not in stability


def test_hal_scargo_is_the_only_physical_executor_for_hal_transport_contracts():
    authority = mission("ITW_CLASH_PlayerTransportAuthority.sqf")
    bridge = mission("ITW_CLASH_PlayerTransportNativeBridge.sqf")
    assert '"hal-owns-physical-execution"' in bridge
    assert '"hal-scargo-owns-physical-execution"' in bridge
    assert '"hal-carrier-selected"' in bridge
    assert '"hal-contract-embarked"' in bridge
    assert '"hal-contract-ended"' in bridge
    assert "ITW_CLASH_PlayerTransport_fnc_MonitorObservedHALContract" in bridge
    assert "ITW_CLASH_PlayerTransport_fnc_ExecuteHALContract" not in bridge
    assert (
        "ITW_AllyLoadGrpIntoVeh = "
        "ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh;"
    ) in bridge
    observer_start = bridge.index("ITW_CLASH_PlayerTransport_fnc_ObserveHALDemand =")
    observer_end = bridge.index("ITW_CLASH_PlayerTransport_fnc_AcquireDeliveryBase", observer_start)
    observer = bridge[observer_start:observer_end]
    assert "ITW_CLASH_PlayerTransport_fnc_ApplyRetaskLock" in observer
    assert "ITW_CLASH_PlayerTransport_fnc_RemoveFromHAL" not in observer
    assert 'setVariable ["ITW_CLASH_PlayerTransportContract",_contract]' in observer
    acquire_start = authority.index("ITW_CLASH_PlayerTransport_fnc_Acquire =")
    acquire_end = authority.index("ITW_CLASH_PlayerTransport_fnc_ReserveDelivery", acquire_start)
    acquire = authority[acquire_start:acquire_end]
    assert 'if !(_group getVariable ["itwDelivery",false]) exitWith {false};' in acquire
    assert "ITW_CLASH_PlayerTransport_fnc_RemoveFromHAL" in acquire
    assert "HAL_CONTRACT" not in authority
    assert "halSCargoSoleExecutor=true observerOnly=true" in authority


def test_native_proximity_ferry_is_disabled_and_never_manufactures_a_hal_job():
    bridge = mission("ITW_CLASH_PlayerTransportNativeBridge.sqf")
    manager_start = bridge.index("ITW_AllyLoadIntoVehManager = {")
    manager_end = bridge.index(
        "ITW_AllyLoadGrpIntoVeh = ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh;",
        manager_start,
    )
    manager = bridge[manager_start:manager_end]

    assert '"native-proximity-ferry-disabled"' in manager
    assert '"hal-scargo-sole-dispatch"' in manager
    assert '"no-unsolicited-player-pickup"' in manager
    assert "forEach vehicles" not in manager
    assert "ITW_ObjGetNearest" not in manager
    assert "ITW_reservedGroups" not in manager
    assert "spawn ITW_AllyLoadGrpIntoVeh" not in manager

    acquire_start = bridge.index("ITW_CLASH_PlayerTransport_fnc_Acquire =")
    acquire_end = bridge.index("ITW_CLASH_PlayerTransport_fnc_ThrottleLog", acquire_start)
    acquire = bridge[acquire_start:acquire_end]
    assert 'getVariable ["itwDelivery",false]' in acquire
    assert '"hal-scargo-owns-physical-execution"' in acquire
    assert '"no-hal-transport-contract"' in acquire
    assert "false\n};" in acquire


def test_hal_scargo_native_source_really_owns_the_physical_transport_lifecycle():
    scargo = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "SCargo.sqf").read_text(encoding="utf-8")
    assert '_GD setVariable [("Busy" + (str _GD)), true];' in scargo
    assert '[_GD] call RYD_WPdel;' in scargo
    assert "_wp = [_GD,_Lpos" in scargo
    assert '_x assignAsCargo _ChosenOne;' in scargo
    assert '"Return to departure base."' in scargo
    assert '"Abort Pick Up, RTB"' in scargo
    assert 'setVariable ["CargoCheckPending" + (str _unitG),false]' in scargo
