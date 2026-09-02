from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def mission(name: str) -> str:
    return text(MISSION / name)


def test_impasse_reconstitution_queue_is_side_tagged_and_consumed_per_side():
    source = mission("ITW_Attack.sqf")

    assert '["_side",sideUnknown]' in source
    assert "ITW_AtkReconstitutionTransportContexts = createHashMap" in source
    assert "toUpperANSI str _side,_reconstitutionContext" in source
    assert 'private _requestSide = _x param [6,_enemySide];' in source
    assert 'private _request = [_side] call ITW_AtkNextReconstitution;' in source
    assert "private _activeFrontObjective = !(" in source
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in source
    assert '"no-active-front-objective"' in source
    assert '"no-side-forward-fob"' in source

    # A credit on the other commander must not suppress this side's normal spawn.
    spawn_gate = source[source.index("//// Infantry AI Spawner ////"):]
    assert 'private _requestSide = _x param [' in spawn_gate
    assert '_requestSide == _side' in spawn_gate


def test_blufor_hal_groups_capture_original_archetype_and_pause_only_during_recovery():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    assert 'getVariable ["ITW_CLASH_Archetype",[]]' in dual
    assert '(units _group) apply {toLowerANSI typeOf _x}' in dual
    assert '"ITW_CLASH_Lineage"' in dual
    assert '[_group] call ITW_CLASH_DualHAL_fnc_GroupId' in dual

    sync = dual[dual.index("ITW_CLASH_DualHAL_fnc_SyncIncluded = {"):
                dual.index("ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives = {")]
    assert "ITW_CLASH_DualHALBLUFORGroups select" in sync
    assert "ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup" in sync
    assert 'RydHQB_Included = +_blu;' in sync


def test_blufor_exhaustion_enters_same_withdrawal_and_reconstitution_ledger():
    clash = mission("ITW_CLASH.sqf")

    audit = clash[clash.index("ITW_CLASH_fnc_AuditWithdrawals = {"):
                  clash.index("ITW_CLASH_fnc_CancelWithdrawals = {")]
    assert "ITW_CLASH_DualHALBLUFORGroups" in audit
    assert 'getVariable ["ITW_CLASH_DualHALManaged",false]' in audit
    assert '(_alive findIf {isPlayer _x}) >= 0' in audit
    assert 'vehicle _x != _x' in audit
    assert 'side _group' in audit
    assert 'call ITW_AtkQueueReconstitution;' in audit

    # Vehicle crews are explicitly not converted into infantry reconstitution credits.
    assert 'vehicle _x != _x || {!(_x isKindOf "CAManBase")}' in audit


def test_gtfo_uses_forward_fob_and_persists_commander_b_constraints():
    gtfo = mission("ITW_CLASH_GTFO.sqf")
    native_rest = text(HAL / "GoRest.sqf")

    assert 'getVariable ["ITW_CLASH_DualHALManaged",false]' in gtfo
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in gtfo
    assert '"ITW_CLASH_GTFO_GroupRestDecoy"' in gtfo
    assert "ITW_CLASH_GTFO_fnc_SetPersistentConstraints" in gtfo
    assert "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership" in gtfo
    assert "RydHQB_" not in gtfo
    parity = mission("ITW_CLASH_CommanderParity.sqf")
    assert "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership" in parity
    for token in ['"NoDef"', '"NoAttack"', '"NoRecon"', '"Exhausted"']:
        assert token in gtfo

    assert 'getVariable ["ITW_CLASH_GTFO_GroupRestDecoy",objNull]' in native_rest
    assert '_HQ getVariable ["RydHQ_RestDecoy",objNull]' in native_rest


def test_gtfo_bookkeeping_and_runtime_are_commander_aware_for_blufor():
    bookkeeping = mission("ITW_CLASH_GTFO_Bookkeeping.sqf")
    runtime = mission("ITW_CLASH_GTFO_Runtime.sqf")

    assert "ITW_CLASH_GTFOBookkeepingVersion = 3;" in bookkeeping
    assert "ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup" in bookkeeping
    assert "ITW_CLASH_GTFO_fnc_SetPersistentConstraints" in bookkeeping

    assert "ITW_CLASH_GTFORuntimeVersion = 4;" in runtime
    assert "ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal" in runtime
    assert 'getVariable ["ITW_CLASH_DualHALManaged",false]' in runtime
    assert "ITW_CLASH_GTFO_fnc_GetCommander" in runtime
    assert "ITW_CLASH_Withdrawals getOrDefault" in runtime
    assert "} forEach _watchGroups;" in runtime
    assert "[[_group,_hq,true],HAL_GoRest] call RYD_Spawn;" in runtime


def test_casevac_and_ground_medevac_use_casualty_side_context_and_enemy_relationship():
    casevac = mission("ITW_CLASH_CASEVAC.sqf")
    ground = mission("ITW_CLASH_GroundMEDEVAC.sqf")
    manager = mission("ITW_CLASH_GroundMEDEVAC_Manager.sqf")

    assert "ITW_CLASH_CASEVAC_Version = 2;" in casevac
    assert "ITW_AtkReconstitutionTransportContexts" in casevac
    assert 'toUpperANSI str _recoverySide' in casevac
    assert '(_groupSide getFriend (side _x)) < 0.6' in casevac
    assert '"FORWARD_AIR"' in casevac
    assert "ITW_ATTACK_AIR_F" in casevac
    assert "ITW_ATTACK_AIR_E" in casevac

    assert "ITW_CLASH_GroundMEDEVAC_Version = 2;" in ground
    assert "ITW_AtkReconstitutionTransportContexts" in ground
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in ground
    assert '(_groupSide getFriend (side _x)) < 0.6' in ground
    assert '_originalObjective,side _group' in manager
    assert 'count _survivors,_spawnInfo,side _group' in manager


def test_blufor_reconstitution_handoff_returns_to_commander_b_not_enemy_callback():
    runtime = mission("ITW_CLASH_RuntimePatch.sqf")
    transit = mission("ITW_CLASH_ReconstitutionTransitFix.sqf")

    assert "ITW_CLASH_RuntimePatchVersion = 5;" in runtime
    assert 'side _group == ITW_PlayerSide' in runtime
    assert "ITW_CLASH_DualHAL_fnc_RegisterGroup" in runtime
    assert '"reconstitution-handoff-blufor"' in runtime

    callback = transit[transit.index("ITW_CLASH_fnc_AcknowledgeReconstitution"):]
    assert 'side _group == ITW_EnemySide' in callback
    assert "ITW_EnemyGroupCallback" in callback


def test_bootstrap_accepts_the_symmetric_runtime_versions():
    bootstrap = mission("ITW_CLASH_Bootstrap.sqf")
    assert "if (_patchVersion != 5" in bootstrap
    assert "if (_gtfoVersion != 4" in bootstrap
    assert "if (_gtfoBookkeepingVersion != 3" in bootstrap


def test_field_vehicle_staging_obeys_shared_echelon_policy():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    assert "ITW_CLASH_DualHALCheckbookVersion = 5;" in dual
    assert "ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn" in dual

    echelon = dual[
        dual.index("ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn = {"):
        dual.index("ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {")
    ]
    assert '"INTERSTITIAL"' in echelon
    assert 'ITW_TYPE_VEH_TANK,ITW_TYPE_VEH_APC' in echelon
    assert '"REAR"' in echelon
    assert '"FORWARD"' in echelon
    assert "ITW_CLASH_Generation_fnc_Resolve" in echelon
    assert '"field-interstitial-unresolved-native-origin"' in echelon
    assert '"field-rear-unresolved-native-origin"' in echelon

    staging = dual[
        dual.index("ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {"):
        dual.index("ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles = {")
    ]
    assert "ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn" in staging
    assert 'side _crewGroup,_mode,getPosATL _veh' not in staging


def test_armored_recovery_uses_forward_fob_but_native_hal_gorest_executes_movement():
    policy = mission("ITW_CLASH_VehicleEchelonPolicy.sqf")
    init = mission("init.sqf")

    assert "ITW_CLASH_VehicleEchelonPolicyVersion = 2;" in policy
    assert "ITW_CLASH_VehicleEchelon_fnc_IsArmoredCombatGroup" in policy
    assert 'ITW_TYPE_VEH_TANK' in policy
    assert 'ITW_TYPE_VEH_APC' in policy
    assert 'isKindOf "Tank"' in policy
    assert 'isPlayer _x' in policy
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in policy
    assert '"ITW_CLASH_GTFO_GroupRestDecoy"' in policy

    # C.L.A.S.H. supplies only the rally geography. Native HAL still owns the
    # actual withdrawal/rest movement and recovery lifecycle.
    assert "ITW_CLASH_VehicleEchelon_fnc_NativeGoRest = HAL_GoRest;" in policy
    assert "_this call ITW_CLASH_VehicleEchelon_fnc_NativeGoRest" in policy
    assert "addWaypoint" not in policy
    assert "doMove" not in policy
    assert "moveTo" not in policy
    assert "armorRecovery=forward" in policy
    assert "bothSides=true" in policy

    load = 'call compile preprocessFileLineNumbers\n                    "ITW_CLASH_VehicleEchelonPolicy.sqf"'
    force = 'call compile preprocessFileLineNumbers "ITW_CLASH_ForceGeneration.sqf"'
    start = '[] execVM "ITW_Start.sqf"'
    assert "ITW_CLASH_VehicleEchelonPolicy.sqf" in init
    assert load in init
    assert init.index(force) < init.index("ITW_CLASH_VehicleEchelonPolicy.sqf") < init.index(start)


def test_late_recovery_overrides_preserve_side_symmetric_contexts():
    air = mission("ITW_CLASH_CASEVAC_AirOpsFix.sqf")
    ground_policy = mission("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf")

    assert "ITW_CLASH_CASEVAC_AirOpsFixVersion = 3;" in air
    assert '["_recoverySide",sideUnknown]' in air
    assert "ITW_AtkReconstitutionTransportContexts" in air
    assert "toUpperANSI str _recoverySide" in air
    assert "_side != _recoverySide" in air
    assert "_side != ITW_EnemySide" not in air
    assert "symmetricSides=true" in air

    assert "ITW_CLASH_GroundMEDEVAC_VehiclePolicyVersion = 2;" in ground_policy
    assert '["_recoverySide",sideUnknown]' in ground_policy
    assert "ITW_AtkReconstitutionTransportContexts" in ground_policy
    assert "toUpperANSI str _recoverySide" in ground_policy
    assert "_side != _recoverySide" in ground_policy
    assert "_side != ITW_EnemySide" not in ground_policy
    assert "symmetricSides=true" in ground_policy


def test_shared_infantry_hardening_covers_both_hal_registries():
    authority = mission("ITW_CLASH_InfantryAuthority.sqf")
    allocation = mission("ITW_CLASH_InfantryAuthorityAllocationFix.sqf")
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    assert "ITW_CLASH_InfantryAuthorityVersion = 4;" in authority
    assert "ITW_CLASH_DualHALBLUFORGroups" in authority
    assert "ITW_CLASH_DualHALOPFORExtraGroups" in authority
    assert "ITW_CLASH_InfantryAuthorityGarrisonsBySide" in authority
    assert "ITW_CLASH_CommanderParity_fnc_ReconcileConstraintMembership" in authority
    assert "RydHQB_" not in authority
    assert "garrisonConstraintsBothSides=true" in authority

    assert "ITW_CLASH_InfantryAuthorityAllocationFixVersion = 2;" in allocation
    assert "ITW_CLASH_DualHALBLUFORGroups" in allocation
    assert "ITW_CLASH_DualHALOPFORExtraGroups" in allocation
    assert "ITW_CLASH_DualHALObjectiveAffinity" in allocation
    assert "dualHAL=true" in allocation

    assert "ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints" in dual
    assert "symmetricInfantryRoles=true" in dual


def test_transport_settle_blocks_same_frame_hal_adoption_on_both_sides():
    guard = mission("ITW_CLASH_LogisticsGuard.sqf")
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    assert "ITW_CLASH_LogisticsHandoffVersion = 4;" in guard
    assert "ITW_PlayerSide" in guard
    assert "ITW_EnemySide" in guard
    assert "side _grp != ITW_EnemySide" not in guard
    assert 'findIf {isPlayer _x}' in guard
    assert "symmetricTransportSettle=true" in guard

    should_own = dual[
        dual.index("ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup = {"):
        dual.index("ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter = {")
    ]
    assert 'ITW_CLASH_ReeligibleAt' in should_own


def test_commander_ab_compatibility_is_centralized_in_master_parity_layer():
    gtfo = mission("ITW_CLASH_GTFO.sqf")
    runtime = mission("ITW_CLASH_GTFO_Runtime.sqf")
    bookkeeping = mission("ITW_CLASH_GTFO_Bookkeeping.sqf")
    recon = mission("ITW_CLASH_ReconObserver.sqf")
    field = mission("ITW_CLASH_FieldHardening.sqf")

    for source in [gtfo, runtime, bookkeeping, recon, field]:
        assert "ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup" in source
        assert "ITW_CLASH_BLUFORHQ" not in source

    for source in [runtime, recon, field]:
        assert "ITW_CLASH_HALHQ" not in source

    cancel = gtfo[
        gtfo.index("ITW_CLASH_fnc_CancelWithdrawals = {"):
        gtfo.index("diag_log format [", gtfo.index("ITW_CLASH_fnc_CancelWithdrawals = {"))
    ]
    assert "ITW_CLASH_GTFO_fnc_SetPersistentConstraints" in cancel
    assert 'ITW_CLASH_HALHQ getVariable ["RydHQ_Exhausted"' not in cancel


def test_commander_parity_is_one_master_layer_not_behavior_specific_blufor_patches():
    parity = mission("ITW_CLASH_CommanderParity.sqf")
    init = mission("init.sqf")
    attack = mission("ITW_Attack.sqf")

    assert "ITW_CLASH_CommanderParityVersion = 2;" in parity
    assert "Single authority layer" in parity
    assert "ITW_CLASH_CommanderParity_fnc_GetCommanderForSide" in parity
    assert "ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup" in parity
    assert "ITW_CLASH_CommanderParity_fnc_GlobalPrefixForSide" in parity
    assert "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership" in parity
    assert "ITW_CLASH_CommanderParity_fnc_ReconcileConstraintMembership" in parity
    assert "ITW_CLASH_CommanderParity_fnc_IsPlayerGroup" in parity
    assert "sections=projection,anchor" in parity
    assert "playerExcluded=true" in parity

    assert not (MISSION / "ITW_CLASH_FriendlyAnchorParity.sqf").exists()
    forbidden = [
        path.name
        for path in MISSION.glob("ITW_CLASH_*.sqf")
        if "fix" in path.name.lower() and any(
            marker in path.name.lower()
            for marker in ["bluefor", "commanderb", "commander_b", "commander-b"]
        )
    ]
    assert forbidden == []

    assert "ITW_CLASH_CommanderParity.sqf" in init
    assert "ITW_CLASH_FriendlyAnchorParity.sqf" not in init
    assert init.index("ITW_CLASH_DualHALCheckbookHardening.sqf") < init.index(
        "ITW_CLASH_CommanderParity.sqf"
    )

    assert "ITW_CLASH_CommanderParity_fnc_NextAnchorRefill" in attack
    assert "ITW_CLASH_CommanderParity_fnc_AcknowledgeAnchorRefill" in attack
    assert "ITW_CLASH_FriendlyAnchor" not in attack


def test_commander_parity_anchor_section_mirrors_six_man_ai_doctrine_only():
    parity = mission("ITW_CLASH_CommanderParity.sqf")

    assert "ITW_CLASH_CommanderParity_AnchorGroups = createHashMap;" in parity
    assert "ITW_CLASH_CommanderParity_AnchorRefills = createHashMap;" in parity
    assert 'missionNamespace getVariable ["ITW_CLASH_MinAnchorSoldiers",6]' in parity
    assert "ITW_CLASH_DualHALBLUFORGroups" in parity
    assert "ITW_CLASH_CommanderParity_fnc_IsPlayerGroup" in parity
    assert "ITW_CLASH_SOF_fnc_IsSOF" in parity
    assert "HAL_GoDef" in parity
    assert "RYD_Spawn" in parity
    assert "ITW_CLASH_CommanderParity_Anchor_fnc_RequestRefill" in parity
    assert "ITW_CLASH_CommanderParity_fnc_NextAnchorRefill" in parity
    assert "ITW_CLASH_CommanderParity_fnc_AcknowledgeAnchorRefill" in parity



def test_reconstitution_physical_dismount_is_direct_hal_handoff_boundary():
    transit = mission("ITW_CLASH_ReconstitutionTransitFix.sqf")

    assert "ITW_CLASH_ReconstitutionTransitFixVersion = 5;" in transit
    assert '"ITW_CLASH_ReconstitutionTransitPoll",2' in transit
    assert "ITW_CLASH_Reconstitution_fnc_ReconcileDismountOwnership" in transit
    assert "_aliveUnits orderGetIn false;" in transit
    assert "_aliveUnits allowGetIn false;" in transit
    assert "VEHINFO_CARGO_GRPS" in transit
    assert "private _dismountHandoff = _physicalDismount" in transit
    assert "private _shouldHandoff = _nearHandoff || {_dismountHandoff};" in transit
    assert "(units _group select {alive _x}) allowGetIn true;" in transit
    assert "physicalDismountHandoff=true" in transit


def test_reconstitution_transport_dismount_does_not_fall_into_generic_walking_limbo():
    transit = mission("ITW_CLASH_ReconstitutionTransitFix.sqf")

    # Walking is now only the no-transport fallback. A real transport unload
    # remains in the transport lifecycle until direct HAL handoff succeeds.
    transport_dismount = transit.split(
        'private _physicalDismount = _state isEqualTo "transport"', 1
    )[1].split(
        'if (_state isEqualTo "waiting-transport"', 1
    )[0]
    assert 'ITW_CLASH_TransitState",_state' not in transport_dismount
    assert '"reconstitution-transport-interrupted"' not in transit
    assert "ITW_CLASH_Reconstitution_fnc_OrderWalkingTransit" in transit
    assert '[_group,_objectiveIndex,"transport-unavailable"] call' in transit
    assert "[_group,false] spawn ITW_AtkEngageInfantry;" not in transit


def test_reconstitution_guard_repairs_stale_assignment_without_per_second_log_spam():
    guard = mission("ITW_CLASH_LogisticsGuard.sqf")

    assert "ITW_CLASH_LogisticsHandoffVersion = 4;" in guard
    assert "ITW_CLASH_Reconstitution_fnc_ReconcileDismountOwnership" in guard
    assert '"ITW_CLASH_ReconstitutionUnassignLogAt",time + 15' in guard
    assert "reconstitutionDismountReconcile=true" in guard


def test_reconstitution_dispatch_prefers_cheaper_valid_lift_within_route_mode():
    dispatch = mission("ITW_CLASH_ReconstitutionDispatchFix.sqf")

    assert "ITW_CLASH_ReconstitutionDispatchFixVersion = 6;" in dispatch
    assert "private _fallback = _candidates - _preferred;" in dispatch
    assert dispatch.count("_x#ITW_VEH_REQD_TICKETS") >= 2
    assert "costEfficientLiftOrder=true" in dispatch


def test_reconstitution_transit_failure_distinguishes_combat_loss_from_lifecycle_loss():
    transit = mission("ITW_CLASH_ReconstitutionTransitFix.sqf")

    assert '"combat-loss-after-dismount"' in transit
    assert '"combat-loss-in-transit"' in transit
    assert '"transport-loss-with-cargo"' in transit
    assert '"group-object-lost-in-transit"' in transit


def test_vehicle_echelon_wrapper_is_nil_safe_for_native_gorest():
    policy = mission("ITW_CLASH_VehicleEchelonPolicy.sqf")
    block = policy.split("HAL_GoRest = {", 1)[1].split(
        "ITW_CLASH_VehicleEchelonPolicyReady = true;", 1
    )[0]

    assert "ITW_CLASH_VehicleEchelonPolicyVersion = 2;" in policy
    assert 'if (isNil "_result") exitWith {};' in block
