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


def test_native_proximity_loading_cannot_manufacture_a_hal_transport_job():
    authority = mission("ITW_CLASH_PlayerTransportAuthority.sqf")
    bridge = mission("ITW_CLASH_PlayerTransportNativeBridge.sqf")

    assert '"native-proximity-rejected"' in authority
    assert '"no-hal-transport-contract"' in authority
    assert '"HAL_SCargo"' in authority
    assert '"hal-demand-observed"' in authority
    assert '"hal-contract-acquired"' in authority

    acquire = '[_grp,_veh,"player-ferry-boarding"] call\n                        ITW_CLASH_PlayerTransport_fnc_Acquire;'
    state_zero = '_grp setVariable ["ITW_getInState",0];'
    assert acquire in bridge
    assert state_zero in bridge
    assert bridge.index(acquire) < bridge.index(state_zero)

    # The HAL-contract branch must not run the native objective/waypoint rewrite;
    # those mutations belong only to the non-HAL standing-delivery branch.
    hal_start = bridge.index("if (_halContract) then {")
    native_else = bridge.index("} else {", hal_start)
    hal_block = bridge[hal_start:native_else]
    assert "_halContractSelected = true;" in hal_block
    assert "VAR_SET_OBJ_IDX" not in hal_block
    assert "ITW_DELETE_WAYPOINTS" not in hal_block

    assert "ITW_CLASH_PlayerTransport_fnc_GetContractDestination" in bridge
    assert '"player-ferry-delivered"' in bridge
