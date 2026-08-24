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

    # vehDef is a shared faction/class definition. Per-deployment transport state
    # must never be written into its DUAL-as-transport field.
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

    # Recon execution is already owned by ServiceStability.
    assert "HAL_GoRecon =" in stability
    assert "HAL_GoDefRecon =" in stability
    assert '"RECON","offensive"' in stability
    assert '"RECON","defensive"' in stability

    # Every canonical HAL attack executor is guarded, with flank/SF guarded when
    # those optional functions are present in the loaded HAL build.
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
    bridge = mission("ITW_CLASH_PlayerTransportNativeBridge.sqf")

    assert '"hal-owns-physical-execution"' in bridge
    assert '"hal-scargo-owns-physical-execution"' in bridge
    assert '"hal-carrier-selected"' in bridge
    assert '"hal-contract-embarked"' in bridge
    assert '"hal-contract-ended"' in bridge
    assert "ITW_CLASH_PlayerTransport_fnc_MonitorObservedHALContract" in bridge

    # The old duplicate physical executor must stay gone. HAL SCargo already owns
    # pickup movement, boarding, transport, dismount and RTB.
    assert "ITW_CLASH_PlayerTransport_fnc_ExecuteHALContract" not in bridge
    assert (
        "ITW_AllyLoadGrpIntoVeh = "
        "ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh;"
    ) in bridge

    observer_start = bridge.index(
        "ITW_CLASH_PlayerTransport_fnc_ObserveHALDemand ="
    )
    observer_end = bridge.index(
        "ITW_CLASH_PlayerTransport_fnc_AcquireHALOwnedBase",
        observer_start,
    )
    observer = bridge[observer_start:observer_end]
    assert "ITW_CLASH_PlayerTransport_fnc_ApplyRetaskLock" in observer
    assert "ITW_CLASH_PlayerTransport_fnc_RemoveFromHAL" not in observer
    assert 'setVariable ["ITW_CLASH_PlayerTransportContract",_contract]' in observer


def test_native_proximity_ferry_is_one_way_and_never_manufactures_a_hal_job():
    bridge = mission("ITW_CLASH_PlayerTransportNativeBridge.sqf")

    assert '"native-proximity-suppressed-hal-busy-carrier"' in bridge
    assert '"native-proximity-skipped-hal-contract"' in bridge
    assert '"native-proximity-itw-ferry"' in bridge
    assert '"halJobManufactured",false' in bridge
    assert '"halContract",false' in bridge

    # HAL-contracted cargo is filtered before native ITW writes objective,
    # boarding-state or waypoint state. Those mutations remain available only to
    # a genuine native proximity ferry with no HAL contract.
    contract_filter = bridge.index('if (count _contract > 0) then {')
    native_state = bridge.index('_grp setVariable ["ITW_getInState",0];')
    native_obj = bridge.index("VAR_SET_OBJ_IDX(_grp,_closestObj#ITW_OBJ_INDEX);")
    native_wp = bridge.index("ITW_DELETE_WAYPOINTS(_grp);")
    assert contract_filter < native_state
    assert contract_filter < native_obj
    assert contract_filter < native_wp

    # Acquire is now rejection-only for ordinary HAL cargo. The legacy authority
    # path is retained solely for standing Impasse itwDelivery formations.
    acquire_start = bridge.index("ITW_CLASH_PlayerTransport_fnc_Acquire =")
    acquire_end = bridge.index("ITW_CLASH_PlayerTransport_fnc_ThrottleLog", acquire_start)
    acquire = bridge[acquire_start:acquire_end]
    assert 'getVariable ["itwDelivery",false]' in acquire
    assert '"hal-scargo-owns-physical-execution"' in acquire
    assert '"no-hal-transport-contract"' in acquire
    assert "false\n};" in acquire


def test_hal_scargo_native_source_really_owns_the_physical_transport_lifecycle():
    scargo = (
        ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "SCargo.sqf"
    ).read_text(encoding="utf-8")

    assert '_GD setVariable [("Busy" + (str _GD)), true];' in scargo
    assert '[_GD] call RYD_WPdel;' in scargo
    assert "_wp = [_GD,_Lpos" in scargo
    assert '_x assignAsCargo _ChosenOne;' in scargo
    assert '"Return to departure base."' in scargo
    assert '"Abort Pick Up, RTB"' in scargo
    assert 'setVariable ["CargoCheckPending" + (str _unitG),false]' in scargo
