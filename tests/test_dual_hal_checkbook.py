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
    prepare = 'call ITW_CLASH_DualHAL_fnc_Prepare;'
    start = '[] execVM "ITW_Start.sqf"'

    assert core in init
    assert hardened in init
    assert api in init
    assert prepare in init
    assert init.index(core) < init.index(hardened) < init.index(api) < init.index(prepare) < init.index(start)
    assert "runtime candidate blocked" in init

    # OneZero hardening has one owner: ReconPlanningBridge. Do not create a
    # second competing scheduler in init.sqf.
    assert 'execVM "ITW_CLASH_OneZeroHardening.sqf"' not in init


def test_commander_b_prepare_is_explicit_and_not_dependent_on_halcore_wrapper_survival():
    init = mission("init.sqf")
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    ryd_init = hal("RydHQInit.sqf")

    prepare = 'call ITW_CLASH_DualHAL_fnc_Prepare;'
    start = '[] execVM "ITW_Start.sqf"'

    # Burn-in smoke 2026-08-21 proved the early NR6_fnc_HALcore wrapper can be
    # rebound by native HAL initialization. Commander B therefore has an
    # explicit C.L.A.S.H.-owned prepare point before Impasse can launch HAL.
    assert prepare in init
    assert init.index(prepare) < init.index(start)
    assert "dual-hal-checkbook-prepared" in init
    assert "nativeCoreLaunchPending=true" in init
    assert 'missionNamespace getVariable ["ITW_CLASH_BLUFORHQ",grpNull]' in init
    assert 'missionNamespace getVariable ["ITW_CLASH_BLUFORLeader",objNull]' in init

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

    assert "ITW_CLASH_DualHALCheckbookHardeningVersion = 4;" in hardening
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


def test_checkbook_serializes_transport_purchases_and_throttles_retries():
    hardening = mission("ITW_CLASH_DualHALCheckbookHardening.sqf")

    assert "ITW_CLASH_CheckbookTransportBusyUntil" in hardening
    assert "ITW_CLASH_CheckbookTransportRetryAt" in hardening
    assert "time + 15" in hardening
    assert "time + (if (isNull _result) then {20} else {60})" in hardening


def test_generic_checkbook_api_is_thin_and_transport_is_v1_provider():
    api = mission("ITW_CLASH_CheckbookAPI.sqf")

    assert "ITW_CLASH_CheckbookAPIVersion = 1;" in api
    assert "ITW_CLASH_fnc_RequestCapability =" in api
    assert 'case "TRANSPORT"' in api
    assert "ITW_CLASH_Checkbook_fnc_RequestTransport" in api
    assert '"provider-not-implemented"' in api
    assert "CASEVAC" in api
    assert "ARTILLERY" in api
    assert "SEAD" in api
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
