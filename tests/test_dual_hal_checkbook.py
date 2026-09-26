from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def hal(name: str) -> str:
    return (HAL / name).read_text(encoding="utf-8")


def test_preinit_reserves_and_finalizes_dual_hal_field_handoff_writers():
    preinit = mission("preInit.sqf")
    bridge = mission("ITW_CLASH_DualHALCheckbookPreInit.sqf")

    for fn in [
        "ITW_AtkAddVehicle",
        "ITW_AtkEngageInfantry",
        "ITW_AtkEngageVehicle",
    ]:
        assert f'"{fn}"' in preinit
        assert f'["{fn}"] call SKL_fnc_CompileFinal' in bridge

    assert 'ITW_CLASH_DualHALCheckbookPreInit.sqf' in preinit
    assert "ITW_CLASH_DualHALCheckbookPreInitReady" in preinit
    assert "failOpen=true" in bridge

    # Every interception preserves an exact baseline fallback. If the runtime
    # compatibility layer is absent or declines the handoff, Impasse still runs.
    assert "ITW_CLASH_DualHAL_fnc_AtkAddVehicleBase" in bridge
    assert "ITW_CLASH_DualHAL_fnc_AtkEngageInfantryBase" in bridge
    assert "ITW_CLASH_DualHAL_fnc_AtkEngageVehicleBase" in bridge


def test_dual_hal_runtime_loads_synchronously_before_impasse_start():
    init = mission("init.sqf")

    core = 'call compile preprocessFileLineNumbers "ITW_CLASH_DualHALCheckbook.sqf"'
    hardened = 'call compile preprocessFileLineNumbers "ITW_CLASH_DualHALCheckbookHardening.sqf"'
    api = 'call compile preprocessFileLineNumbers "ITW_CLASH_CheckbookAPI.sqf"'
    force_generation = 'call compile preprocessFileLineNumbers "ITW_CLASH_ForceGeneration.sqf"'
    logistics = 'call compile preprocessFileLineNumbers "ITW_CLASH_HALLogistics.sqf"'
    garage = 'call compile preprocessFileLineNumbers "ITW_CLASH_PlayerGarageDeployment.sqf"'
    start = '[] execVM "ITW_Start.sqf"'

    assert core in init
    assert hardened in init
    assert api in init
    assert force_generation in init
    assert logistics in init
    assert garage in init
    assert 'call ITW_CLASH_DualHAL_fnc_Prepare;' not in init
    assert init.index(core) < init.index(hardened) < init.index(api) < init.index(force_generation) < init.index(start)
    assert init.index(force_generation) < init.index(logistics) < init.index(start)
    assert init.index(force_generation) < init.index(garage) < init.index(start)
    assert "dual-hal-checkbook-deferred-ready" in init
    assert "runtime candidate blocked" in init

    # OneZero hardening has one owner: ReconPlanningBridge. Do not create a
    # second competing scheduler in init.sqf.
    assert 'execVM "ITW_CLASH_OneZeroHardening.sqf"' not in init


def test_commander_b_prepare_is_explicit_and_not_dependent_on_halcore_wrapper_survival():
    init = mission("init.sqf")
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    api = mission("ITW_CLASH_CheckbookAPI.sqf")
    ryd_init = hal("RydHQInit.sqf")

    start = '[] execVM "ITW_Start.sqf"'

    # Burn-in smoke 2026-08-21 proved both that the early NR6_fnc_HALcore wrapper
    # is rebound and that mission init precedes Impasse side identity. API V2's
    # binder waits for those sides and prepares B before native HAL launches.
    assert 'call ITW_CLASH_DualHAL_fnc_Prepare;' not in init
    assert "ITW_CLASH_DualHALSideBinderStarted" in api
    assert '!isNil "ITW_PlayerSide"' in api
    assert 'call ITW_CLASH_DualHAL_fnc_PrepareCommanderB' in api
    assert "dual-hal-checkbook-deferred-ready" in init
    assert "nativeCoreLaunch=live-mode-only" in init
    assert "nativeCoreLaunchPending=true" not in init
    assert "dual-hal-core-wrapper-skipped" in dual
    assert "NR6_fnc_HALcore =" not in dual

    # Prepare creates leaderHQB; untouched native RydHQInit consumes it after
    # VarInit and registers that group as Commander B.
    assert "ITW_CLASH_DualHAL_fnc_PrepareCommanderB" in dual
    assert "leaderHQB = _leader;" in dual
    assert 'if not (isNull leaderHQB)' in ryd_init
    assert 'setVariable ["RydHQ_CodeSign","B"]' in ryd_init


def test_native_hal_commander_b_is_used_instead_of_a_cloned_commander():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    ryd_init = hal("RydHQInit.sqf")

    assert "leaderHQB = _leader;" in dual
    assert 'publicVariable "leaderHQB";' in dual
    assert "RydHQB_Included" in dual
    assert "RydHQB_SimpleMode = true;" in dual
    assert "RydHQB_SimpleObjs" in dual

    # NR6 HAL itself recognizes leaderHQB, registers HQ B and launches its own
    # sitrep / battlefield / secondary-task loops.
    assert "if not (isNull leaderHQB)" in ryd_init
    assert 'setVariable ["RydHQ_CodeSign","B"]' in ryd_init
    assert "B_HQSitRep" in ryd_init
    assert "HAL_FBFTLOOP" in ryd_init
    assert "HAL_SecTasks" in ryd_init


def test_commander_registry_and_field_authority_are_side_scoped():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    infantry = mission("ITW_CLASH_InfantryAuthorityPreInit.sqf")
    movement = mission("ITW_CLASH_PhysicalMovementPreInit.sqf")

    assert "ITW_CLASH_CommanderRegistry = createHashMap;" in dual
    assert "ITW_CLASH_fnc_GetCommanderForSide" in dual
    assert "ITW_CLASH_fnc_GetCommanderForGroup" in dual
    assert 'setVariable ["ITW_CLASH_DualHALManaged",true]' in dual

    assert "ITW_CLASH_InfantryAuthorityPreInitVersion = 2;" in infantry
    assert 'getVariable ["ITW_CLASH_DualHALManaged",false]' in infantry

    assert "ITW_CLASH_PhysicalMovementPreInitVersion = 5;" in movement
    assert 'getVariable ["ITW_CLASH_DualHALManaged",false]' in movement


def test_blufor_objectives_use_private_mirrors_and_full_hal_taken_contract():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    hardening = mission("ITW_CLASH_DualHALCheckbookHardening.sqf")

    assert 'createVehicle ["Land_HelipadEmpty_F"' in dual
    assert "ITW_CLASH_BLUFORObjectiveMirrors" in dual
    assert '_mirror setVariable ["SetTakenA",_friendlyOwned,true];' in dual

    assert "ITW_CLASH_DualHALCheckbookHardeningVersion = 5;" in hardening
    assert "RydHQB_Taken = +_taken;" in hardening
    assert 'setVariable ["RydHQ_Taken",+_taken]' in hardening
    assert "ITW_CLASH_DualHALHardeningLastBZone" in hardening
    assert "RydHQB_NObj = 1;" in hardening
    assert 'setVariable ["RydHQ_NObj",1]' in hardening
    assert '"commander-b-objective-zone-reset"' in hardening


def test_blufor_hidden_hq_is_protected_from_impasse_and_hal_subordination():
    hardening = mission("ITW_CLASH_DualHALCheckbookHardening.sqf")

    assert 'ITW_CLASH_BLUFORHQ setVariable ["ITW_CLASH_Commander",true];' in hardening
    assert 'ITW_CLASH_BLUFORHQ setVariable ["ITW_CLASH_ExcludeHAL",true];' in hardening
    assert 'ITW_CLASH_BLUFORHQ setVariable ["zbe_cacheDisabled",true];' in hardening
    assert 'ITW_CLASH_BLUFORLeader setVariable ["itw_dmgBlocked",true];' in hardening


def test_reconstitution_and_evacuation_cargo_cannot_be_stolen_by_field_handoff():
    hardening = mission("ITW_CLASH_DualHALCheckbookHardening.sqf")
    attack = mission("ITW_Attack.sqf")

    assert "VEHINFO_CARGO_GRPS" in hardening
    assert "private _reservedCargo = _cargoGroups findIf" in hardening
    assert "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" in hardening
    assert '"reserved-cargo-lifecycle"' in hardening
    assert 'getVariable ["ITW_CLASH_CASEVAC_State",""]' in hardening
    assert 'getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]' in hardening

    # Reconstitution marks the cargo before AddVehicle crosses the interception
    # seam, so the hardening predicate can fail open to the canonical transit.
    assert 'setVariable ["ITW_CLASH_ReconstitutionTransit",true]' in attack
    assert "[_vehInfo,false,false] call ITW_AtkAddVehicle;" in attack


def test_impasse_remains_vehicle_count_authority_after_checkbook_purchase():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    hardening = mission("ITW_CLASH_DualHALCheckbookHardening.sqf")
    attack = mission("ITW_Attack.sqf")

    assert "ITW_VEH_COUNT_INCR(_vehDef);" in dual
    assert "ITW_TICKET_REDUCE(_vehDef);" in dual
    assert 'setVariable ["ITW_VehDef",_vehDef]' in dual

    # The compatibility cleanup ledger intentionally drops the mutable vehDef;
    # Impasse's own vehicle manager will rebuild live counts from ITW_VehDef.
    assert "_entry set [1,[]];" in hardening
    assert 'getVariable ["ITW_VehDef",[]]' in attack


def test_checkbook_serializes_by_side_and_capability_without_global_cross_side_lock():
    hardening = mission("ITW_CLASH_DualHALCheckbookHardening.sqf")
    api = mission("ITW_CLASH_CheckbookAPI.sqf")

    assert "ITW_CLASH_CheckbookTransportBusyUntil" not in hardening
    assert "ITW_CLASH_CheckbookTransportRetryAt" not in hardening
    assert "ITW_CLASH_CheckbookLeases = createHashMap;" in api
    assert "ITW_CLASH_Checkbook_fnc_LeaseKey" in api
    assert "ITW_CLASH_Checkbook_fnc_TryLease" in api
    assert "ITW_CLASH_Checkbook_fnc_ReleaseLease" in api


def test_generic_checkbook_api_v2_has_typed_contract_and_provider_registry():
    api = mission("ITW_CLASH_CheckbookAPI.sqf")

    assert "ITW_CLASH_CheckbookAPIVersion = 2;" in api
    assert "ITW_CLASH_CHECKBOOK_REQUEST_V2" in api
    assert "ITW_CLASH_CHECKBOOK_RESULT_V2" in api
    assert "ITW_CLASH_fnc_RequestCapability =" in api
    assert "ITW_CLASH_CheckbookProviders = createHashMap;" in api
    assert "ITW_CLASH_Checkbook_fnc_RegisterProvider" in api
    assert '["TRANSPORT",ITW_CLASH_Checkbook_fnc_TransportProvider]' in api
    assert "ITW_CLASH_Checkbook_fnc_RequestTransport" in api
    assert '"provider-not-implemented"' in api
    assert "createVehicle" not in api
    assert "addWaypoint" not in api
    assert "RydHQ_AAthreat" not in api
    assert "RydHQ_Airthreat" not in api


def test_native_hal_cargo_owns_tactical_air_safety_not_impasse():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    cargo = hal("HAL/SCargo.sqf")

    assert "HAL_SCargo" in dual
    assert "ITW_CLASH_Checkbook_fnc_NativeSCargo" in dual
    assert "ITW_CLASH_Checkbook_fnc_RequestTransport" in dual

    assert 'getVariable ["RydHQ_AAthreat",[]]' in cargo
    assert 'getVariable ["RydHQ_Airthreat",[]]' in cargo
    assert "LZ" in cargo and "too hot" in cargo

    # C.L.A.S.H. may read HAL threat state to avoid provisioning obviously
    # unusable air capacity, but it never creates an Impasse air-corridor state.
    assert "AIR_CORRIDOR" not in dual.upper()
    assert "AIR_CORRIDOR" not in mission("ITW_CLASH_DualHALCheckbookHardening.sqf").upper()
    assert "AIR_CORRIDOR" not in mission("ITW_CLASH_CheckbookAPI.sqf").upper()


def test_recon_sof_bridge_is_scoped_to_the_exact_hal_commander_side():
    bridge = mission("ITW_CLASH_ReconPlanningBridge.sqf")

    assert "ITW_CLASH_ReconPlanningBridgeVersion = 4;" in bridge
    assert "ITW_CLASH_ReconPlanning_fnc_GetCommanderCandidates" in bridge
    assert "ITW_CLASH_DualHALBLUFORGroups" in bridge
    assert "ITW_CLASH_DualHALOPFORExtraGroups" in bridge
    assert "side _group == _hqSide" in bridge
    assert 'side _x == side _hq' in bridge
    assert 'setVariable ["ITW_CLASH_ReconPlanningSpecForSignature",_signature]' in bridge
    assert "commanderScoped=true" in bridge


def test_one_zero_hardening_still_has_single_runtime_scheduler():
    init = mission("init.sqf")
    bridge = mission("ITW_CLASH_ReconPlanningBridge.sqf")

    assert 'execVM "ITW_CLASH_OneZeroHardening.sqf"' not in init
    assert 'execVM "ITW_CLASH_OneZeroHardening.sqf"' in bridge


def test_transport_doctrine_is_durable_across_hal_sitrep_and_dual_is_deployment_aware():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    parity = mission("ITW_CLASH_CommanderParity.sqf")

    assert "ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine" in dual
    assert '["CargoOnly","NoAttack","NoRecon","NoDef"]' in dual
    assert "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership" in dual
    assert 'missionNamespace setVariable [_globalName,_global];' in parity

    stage = dual.split("ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {", 1)[1].split(
        "ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles = {", 1
    )[0]
    assert "VEHINFO_IS_DUAL_AS_TRANSPORT" in stage
    assert "_transportDeployment" in stage
    assert "_role == ITW_VEH_ROLE_TRANSPORT" in stage
    assert "_role == ITW_VEH_ROLE_DUAL && {_dualAsTransport}" in stage

    migrate = dual.split("ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles = {", 1)[1].split(
        "ITW_CLASH_Checkbook_fnc_GetZonesOwned = {", 1
    )[0]
    assert "ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine" in migrate
    assert "VEHINFO_IS_DUAL_AS_TRANSPORT" in migrate

    register = dual.split("ITW_CLASH_Checkbook_fnc_RegisterTransport = {", 1)[1].split(
        "ITW_CLASH_Checkbook_fnc_RequestTransport = {", 1
    )[0]
    assert "ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine" in register
    assert "ITW_CLASH_DualHAL_fnc_MarkVehicleCrew" in register


def test_generated_support_constraints_are_projected_into_hal_globals():
    force = mission("ITW_CLASH_ForceGeneration.sqf")
    register = force.split("ITW_CLASH_Generation_fnc_RegisterAsset = {", 1)[1].split(
        "ITW_CLASH_Generation_fnc_Provider = {", 1
    )[0]

    assert '["NoAttack","NoRecon","NoDef"]' in register
    assert "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership" in register
    assert "ITW_CLASH_DualHAL_fnc_MarkVehicleCrew" in register


def test_orphan_vehicle_crew_is_quarantined_then_cleaned_without_touching_infantry_remnants():
    cleanup = mission("ITW_CLASH_CrewRemnantCleanup.sqf")
    init = mission("init.sqf")

    assert "ITW_CLASH_CrewRemnantCleanupVersion = 1;" in cleanup
    assert '"ITW_CLASH_VehicleCrewGroup",false' in cleanup
    assert '"ITW_CLASH_VehicleCrewUnit",false' in cleanup
    assert "ITW_CLASH_CrewRemnantMaxSurvivors" in cleanup
    assert "ITW_CLASH_CrewRemnantMaxSurvivors,2" not in cleanup
    assert '"ITW_CLASH_CrewRemnantMaxSurvivors",4' in cleanup
    assert "isNull _veh || {!alive _veh} || {!canMove _veh}" in cleanup
    assert 'setVariable ["Unable",true,true]' in cleanup
    assert 'setVariable ["ITW_CLASH_ExcludeHAL",true]' in cleanup
    assert "ITW_CLASH_Service_fnc_RemoveHALOwnership" in cleanup
    assert "ITW_CLASH_CrewRemnantPlayerRadius" in cleanup
    assert "{deleteVehicle _x} forEach _survivors;" in cleanup

    # Generic one-man infantry is intentionally not deleted; cleanup requires
    # explicit vehicle-crew provenance.
    assert 'getVariable ["ITW_CLASH_VehicleCrewGroup",false]' in cleanup

    assert '"ITW_CLASH_CrewRemnantCleanup.sqf"' in init
    assert "crewRemnantCleanup=" in init


def test_transport_selection_is_capacity_and_ticket_aware_without_classname_doctrine():
    policy = mission("ITW_CLASH_ServiceCapacityPolicy.sqf")
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    assert "ITW_CLASH_ServiceCapacityPolicyVersion = 1;" in policy
    assert "ITW_CLASH_ServiceCapacity_fnc_ConfigCargoSeats" in policy
    assert 'getNumber (_cfg >> "transportSoldier")' in policy
    assert '"showAsCargo"' in policy
    assert "ITW_CLASH_ServiceCapacity_ClassCapacityOverrides" in policy
    assert "ITW_CLASH_ServiceCapacity_ClassScoreAdjustments" in policy
    assert "ITW_CLASH_ServiceCapacity_ContextScoreAdjustments" in policy
    assert "_excessSeats * ITW_CLASH_ServiceCapacity_ExcessSeatWeight" in policy
    assert "_ticketCost * ITW_CLASH_ServiceCapacity_TicketWeight" in policy
    assert "ITW_CLASH_ServiceCapacity_DualRolePenalty" in policy

    assert "ITW_CLASH_Checkbook_fnc_RankTransportVariants" in dual
    assert '[_seatCount,_defs,_mode,"TRANSPORT"]' in dual
    assert "private _spawnDef = +_vehDef;" in dual
    assert "_spawnDef set [ITW_VEH_CLASSES,[_variant]];" in dual

    for hardcoded in ["Polaris", "MATV", "M-ATV", "Huron", "Chinook", "LittleBird"]:
        assert hardcoded not in policy
