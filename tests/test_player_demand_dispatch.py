import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
DOCS = ROOT / "docs"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def _block(text: str, start_marker: str, end_marker: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[start:end]


def test_design_contract_makes_subscription_not_vehicle_the_dispatch_gate():
    text = (DOCS / "PLAYER_EMPLOYMENT_DEMAND_DISPATCH.md").read_text(encoding="utf-8")

    assert "Subscription gates dispatch. Capability gates execution." in text
    assert "A player's current vehicle never decides whether they are told about subscribed work." in text
    assert "Cancellation means **release**, not deletion" in text
    assert '"Tell me when this kind of work exists."' in text
    assert "Native HAL cycle overwrite: identified" in text
    assert "HQSitRepB.sqf" in text


def test_demand_layer_loads_all_hardening_before_native_interceptors_arm():
    init = (MISSION / "init.sqf").read_text(encoding="utf-8")
    demand = (MISSION / "ITW_CLASH_PlayerDemandDispatch.sqf").read_text(encoding="utf-8")
    interceptors = (MISSION / "ITW_CLASH_PlayerDemandNativeInterceptors.sqf").read_text(encoding="utf-8")

    assert '"ITW_CLASH_PlayerDemandDispatch.sqf"' in init
    assert '"ITW_CLASH_PlayerDemandNativeInterceptors.sqf"' in init
    assert 'ITW_CLASH_PlayerTaskStateHardeningReady' in demand
    assert 'ITW_CLASH_PlayerTaskStateCancelReady' in demand
    assert 'ITW_CLASH_PlayerTaskStateArtilleryGuardReady' in demand
    assert 'player-demand-dispatch-ready' in demand

    for filename, ready in [
        ('ITW_CLASH_PlayerDemandExecutionHardening.sqf', 'ITW_CLASH_PlayerDemandExecutionHardeningReady'),
        ('ITW_CLASH_PlayerDemandReservationHardening.sqf', 'ITW_CLASH_PlayerDemandReservationHardeningReady'),
        ('ITW_CLASH_PlayerDemandAmmoValidityHardening.sqf', 'ITW_CLASH_PlayerDemandAmmoValidityHardeningReady'),
    ]:
        assert f'"{filename}"' in interceptors
        assert ready in interceptors


def test_player_dispatch_admission_contains_no_current_vehicle_capability_gate():
    text = (MISSION / "ITW_CLASH_PlayerDemandDispatch.sqf").read_text(encoding="utf-8")
    admission = _block(
        text,
        'ITW_CLASH_PlayerTasks_fnc_CanAcceptJob = {',
        'ITW_CLASH_PlayerTasks_fnc_HasNativeExecutableSubscription = {'
    )

    assert 'ITW_CLASH_PlayerTasks_fnc_IsSubscribed' in admission
    assert 'ITW_CLASH_AuthorityHold' in admission
    assert 'ITW_CLASH_PlayerTasks_fnc_HasActiveJob' in admission
    assert 'GetEmploymentVehicle' not in admission
    assert 'GetSlingVehicle' not in admission
    assert 'HasPassengerCapacity' not in admission
    assert 'HasArtilleryCapability' not in admission
    assert 'assignedVehicle' not in admission
    assert 'vehicle _' not in admission


def test_native_hal_executability_retains_physical_capability_checks():
    text = (MISSION / "ITW_CLASH_PlayerDemandDispatch.sqf").read_text(encoding="utf-8")
    executable = _block(
        text,
        'ITW_CLASH_PlayerTasks_fnc_HasNativeExecutableSubscription = {',
        '// Preserve the legacy executable helper'
    )

    assert 'GetEmploymentVehicle' in executable
    assert 'HasPassengerCapacity' in executable
    assert 'GetSlingVehicle' in executable
    assert 'HasArtilleryCapability' in executable

    sync = _block(
        text,
        'ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState = {',
        'ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {'
    )
    assert 'ITW_CLASH_PlayerTaskDispatchable' in sync
    assert 'ITW_CLASH_PlayerNativeExecutable' in sync
    assert '_group setVariable ["Unable",!_nativeExecutable,true];' in sync
    assert '_group setVariable ["BUnable",!_nativeExecutable,true];' in sync
    assert 'dispatchable=' in sync
    assert 'nativeExecutable=' in sync


def test_demand_ledger_reserves_releases_and_requeues_without_unsubscribing():
    text = (MISSION / "ITW_CLASH_PlayerDemandDispatch.sqf").read_text(encoding="utf-8")
    hardening = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerDemands = createHashMap;' in text
    for state in ['"OPEN"', '"RESERVED"', '"EXECUTING"', '"COMPLETED"', '"INVALID"']:
        assert state in text

    reserve = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_Reserve = {',
        'ITW_CLASH_PlayerDemand_fnc_ClearGroupReservation = {'
    )
    assert 'ITW_CLASH_PlayerDemandJobId' in reserve
    assert 'ITW_CLASH_PlayerDemandCancel' in reserve
    assert 'ITW_CLASH_PlayerDemand_fnc_ApplySuppression' in reserve

    release = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_Release = {',
        'ITW_CLASH_PlayerDemand_fnc_Complete = {'
    )
    assert 'ITW_CLASH_PlayerDemand_fnc_RestoreSuppression' in release
    assert '["state",if (_valid) then {"OPEN"} else {"INVALID"}]' in release
    assert 'ITW_CLASH_PlayerJobSubscriptions' not in release

    # Timed re-entry supersedes the original permanent declinedGroups behavior.
    assert 'ITW_CLASH_PlayerDemandDeclineCooldown' in hardening
    assert 'declineCooldowns' in hardening
    assert 'ITW_CLASH_PlayerDemandReservation_fnc_ReleaseBase' in hardening
    assert '[_demandId,_reason,false] call' in hardening
    assert 'ITW_CLASH_PlayerJobSubscriptions' not in hardening


def test_reservation_authority_uses_markers_not_persistent_supported_arrays():
    text = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerAmmoDemandReservation' in text
    assert 'ITW_CLASH_PlayerMedevacDemandReservation' in text
    apply = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_ApplySuppression = {',
        'ITW_CLASH_PlayerDemand_fnc_RestoreSuppression = {'
    )
    assert 'suppressionMarker' in apply
    assert 'setVariable [_marker,_demandId]' in apply
    assert 'RydHQ_ASupportedG' not in apply
    assert 'RydHQ_SupportedG' not in apply

    ensure = _block(
        text,
        'ITW_CLASH_PlayerDemandReservation_fnc_EnsureSuppression = {',
        'ITW_CLASH_PlayerDemandReservation_fnc_ReserveBase ='
    )
    assert 'ITW_CLASH_PlayerDemand_fnc_ApplySuppression' in ensure
    assert 'player-demand-suppression-repaired' in ensure

    update = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {',
        'ITW_CLASH_PlayerDemandReservation_fnc_ReservedGroupsForHQ = {'
    )
    assert 'ITW_CLASH_PlayerDemandReservation_fnc_EnsureSuppression' in update


def test_native_support_scans_use_call_scoped_exclusions_and_restore_exact_snapshot():
    text = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(encoding="utf-8")

    ammo = _block(
        text,
        'ITW_CLASH_PlayerDemandReservation_fnc_SuppAmmoBase = HAL_SuppAmmo;',
        'ITW_CLASH_PlayerDemandReservation_fnc_SuppMedBase = HAL_SuppMed;'
    )
    assert 'HAL_SuppAmmo = {' in ammo
    assert 'RydHQ_ExReAmmo' in ammo
    assert 'private _before = +' in ammo
    assert '_hq setVariable ["RydHQ_ExReAmmo",_scoped];' in ammo
    assert '_hq setVariable ["RydHQ_ExReAmmo",_before];' in ammo
    assert 'player-demand-native-scan-excluded' in ammo
    assert 'player-demand-native-scan-restored' in ammo
    assert 'RydHQ_ASupportedG' not in ammo

    med = text[text.index('ITW_CLASH_PlayerDemandReservation_fnc_SuppMedBase = HAL_SuppMed;'):]
    assert 'HAL_SuppMed = {' in med
    assert 'RydHQ_ExMedic' in med
    assert '_hq setVariable ["RydHQ_ExMedic",_scoped];' in med
    assert '_hq setVariable ["RydHQ_ExMedic",_before];' in med
    assert 'RydHQ_SupportedG' not in med


def test_same_cycle_native_handoff_race_is_blocked_by_durable_marker():
    text = (MISSION / "ITW_CLASH_PlayerDemandNativeInterceptors.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerDemandNative_fnc_BlockReservedAmmoRace' in text
    assert 'ITW_CLASH_PlayerDemandNative_fnc_BlockReservedMedevacRace' in text
    assert 'ITW_CLASH_PlayerAmmoDemandReservation' in text
    assert 'ITW_CLASH_PlayerMedevacDemandReservation' in text
    assert 'native-reserved-race-blocked' in text

    ammo_wrapper = _block(
        text,
        'ITW_CLASH_PlayerDemandNative_fnc_GoAmmoSuppBase = HAL_GoAmmoSupp;',
        'ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase = HAL_GoMedSupp;'
    )
    assert 'BlockReservedAmmoRace' in ammo_wrapper
    assert '_this call ITW_CLASH_PlayerDemandNative_fnc_GoAmmoSuppBase' in ammo_wrapper

    med_wrapper = text[text.index('ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase = HAL_GoMedSupp;'):]
    assert 'BlockReservedMedevacRace' in med_wrapper
    assert '_this call ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase' in med_wrapper


def test_native_assignment_arrays_are_only_handoff_cleanup_not_reservation_authority():
    text = (MISSION / "ITW_CLASH_PlayerDemandNativeInterceptors.sqf").read_text(encoding="utf-8")

    take_ammo = _block(
        text,
        'ITW_CLASH_PlayerDemandNative_fnc_TakeAmmo = {',
        '// Same handoff rule for severe medical support.'
    )
    assert 'RydHQ_ASupportedG' in take_ammo
    assert 'native-ASupportedG-cleared-on-handoff' in take_ammo
    assert 'ITW_CLASH_PlayerDemand_fnc_Reserve' in take_ammo

    take_med = _block(
        text,
        'ITW_CLASH_PlayerDemandNative_fnc_TakeMedevac = {',
        'ITW_CLASH_PlayerDemandNative_fnc_BlockReservedAmmoRace = {'
    )
    assert 'RydHQ_SupportedG' in take_med
    assert 'native-SupportedG-cleared-on-handoff' in take_med
    assert 'ITW_CLASH_PlayerDemand_fnc_Reserve' in take_med

    # Durable suppression itself is marker-owned in ReservationHardening.
    hardening = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(encoding="utf-8")
    apply = _block(
        hardening,
        'ITW_CLASH_PlayerDemand_fnc_ApplySuppression = {',
        'ITW_CLASH_PlayerDemand_fnc_RestoreSuppression = {'
    )
    assert 'RydHQ_ASupportedG' not in apply
    assert 'RydHQ_SupportedG' not in apply


def test_liveness_floor_releases_abandoned_preparation_but_renews_on_progress():
    text = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerDemandLivenessWindow",600' in text
    assert 'ITW_CLASH_PlayerDemandProgressDistance",50' in text
    assert 'lastProgressAt' in text
    assert 'progressVehicle' in text
    assert 'progressCapable' in text
    assert 'player-group-unavailable' in text
    assert 'player-unsubscribed-channel' in text
    assert 'player-authority-hold' in text
    assert 'preparation-liveness-expired' in text
    assert 'player-demand-liveness-expired' in text
    assert 'player-demand-progress' in text

    update = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {',
        'ITW_CLASH_PlayerDemandReservation_fnc_ReservedGroupsForHQ = {'
    )
    assert 'if (_state == "RESERVED") then {' in update
    assert 'time - _lastProgress >= ITW_CLASH_PlayerDemandLivenessWindow' in update
    assert 'ITW_CLASH_PlayerDemandReservation_fnc_RecordProgress' in update


def test_decline_cooldown_and_bounce_control_prevent_offer_loops_and_starvation():
    text = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerDemandDeclineCooldown",120' in text
    assert 'ITW_CLASH_PlayerDemandBounceLimit",3' in text
    assert 'ITW_CLASH_PlayerDemandAIFallbackWindow",120' in text
    assert 'declineCooldowns' in text
    assert 'playerOfferSuppressedUntil' in text
    assert 'bounceCount' in text
    assert 'bounceTotal' in text
    assert 'player-demand-decline-cooldown' in text
    assert 'player-demand-bounced' in text
    assert 'player-demand-ai-fallback-window' in text

    find_group = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup = {',
        'ITW_CLASH_PlayerDemandReservation_fnc_ReleaseBase ='
    )
    assert 'playerOfferSuppressedUntil' in find_group
    assert 'declineCooldowns' in find_group


def test_ammo_reserved_validity_does_not_depend_on_hollow_after_exclusion():
    text = (MISSION / "ITW_CLASH_PlayerDemandAmmoValidityHardening.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerDemandAmmoValidity_fnc_GroupNeedsAmmo' in text
    assert 'RydHQ_Recklessness' in text
    assert 'someAmmo' in text
    assert 'count magazines _unit < 2' in text
    assert 'RydHQ_NCVeh' in text
    assert 'RydHQ_Hollow' not in text
    assert 'reservedValidity=direct-native-equivalent' in text
    assert 'hollowNotRequired=true' in text


def test_ammo_assignment_can_prepare_without_sling_asset_then_uses_existing_executor():
    text = (MISSION / "ITW_CLASH_PlayerDemandDispatch.sqf").read_text(encoding="utf-8")

    publish = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_OnAmmoDemand = {',
        'ITW_CLASH_PlayerDemand_fnc_OnMedicalDemand = {'
    )
    assert '"LOGISTICS","LOGISTICS_AMMO"' in publish
    assert 'Acquire a sling-capable helicopter' in publish
    assert 'GetSlingVehicle' not in publish

    execute = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_StartAmmoExecution = {',
        'ITW_CLASH_PlayerDemand_fnc_MedevacEvacuees = {'
    )
    assert 'ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle' in execute
    assert 'ITW_CLASH_PlayerTasks_fnc_PlayerAmmoJob' in execute
    assert 'ITW_CLASH_PlayerAmmoJobId' in execute
    assert '"DELIVERED"' in execute


def test_severe_medevac_assignment_is_vehicle_independent_and_execution_is_physical():
    text = (MISSION / "ITW_CLASH_PlayerDemandDispatch.sqf").read_text(encoding="utf-8")

    publish = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_OnMedicalDemand = {',
        '[] spawn {'
    )
    assert '"MEDEVAC","MEDEVAC_SEVERE"' in publish
    assert 'Acquire any living movable vehicle with sufficient passenger capacity' in publish
    assert 'GetEmploymentVehicle' not in publish
    assert 'HasPassengerCapacity' not in publish

    execute = _block(
        text,
        'ITW_CLASH_PlayerDemand_fnc_StartMedevacExecution = {',
        'ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {'
    )
    assert 'ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle' in execute
    assert 'ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity' in execute
    assert 'ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup' in execute
    assert 'assignAsCargo _vehicle' in execute
    assert 'moveInCargo _vehicle' in execute
    assert 'moveOut _x' in execute
    assert 'player-demand-completed' not in execute  # completion goes through shared lifecycle helper


def test_native_support_interceptors_are_fail_open_and_preserve_hal_target_selection():
    text = (MISSION / "ITW_CLASH_PlayerDemandNativeInterceptors.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerDemandNative_fnc_GoAmmoSuppBase = HAL_GoAmmoSupp;' in text
    assert 'ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase = HAL_GoMedSupp;' in text
    assert 'HAL_GoAmmoSupp = {' in text
    assert 'HAL_GoMedSupp = {' in text
    assert 'native-assignment-taken-over' in text
    assert '_this call ITW_CLASH_PlayerDemandNative_fnc_GoAmmoSuppBase' in text
    assert '_this call ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase' in text
    assert 'RydHQ_Hollow' in text
    assert 'RydHQ_Wounded' in text
    assert 'nativeFailOpen=true' in text


def test_specialist_executor_owns_terminal_state_after_execution_starts():
    text = (MISSION / "ITW_CLASH_PlayerDemandExecutionHardening.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {' in text
    reserved = _block(text, 'if (_state == "RESERVED") exitWith {', '// EXECUTING is deliberately')
    assert 'ITW_CLASH_PlayerDemand_fnc_StillValid' in reserved
    assert 'underlying-demand-invalidated-before-execution' in reserved
    assert 'ITW_CLASH_PlayerDemand_fnc_StartAmmoExecution' in reserved
    assert 'ITW_CLASH_PlayerDemand_fnc_StartMedevacExecution' in reserved

    executing = text[text.index('// EXECUTING is deliberately'):]
    assert 'ITW_CLASH_PlayerDemand_fnc_StillValid' not in executing
    assert 'ITW_CLASH_PlayerDemandCancel' in executing
    assert 'ITW_CLASH_PlayerAmmoJobCancel' in executing
    assert 'player-demand-execution-owner-lost' in executing
    assert 'executingTerminalOwnedBySpecialist=true' in executing


def test_commander_b_sitrep_is_the_identified_periodic_array_overwriter():
    text = (HAL / "HQSitRepB.sqf").read_text(encoding="utf-8")

    for global_name, object_name in [
        ("RydHQB_NoRecon", "RydHQ_NoRecon"),
        ("RydHQB_NoAttack", "RydHQ_NoAttack"),
        ("RydHQB_NoDef", "RydHQ_NoDef"),
        ("RydHQB_ASupportedG", "RydHQ_ASupportedG"),
        ("RydHQB_SupportedG", "RydHQ_SupportedG"),
    ]:
        assert global_name in text
        assert f'_HQ setVariable ["{object_name}",{global_name}]' in text


def test_native_support_source_has_the_call_scoped_exclusion_seams_we_depend_on():
    ammo = (HAL / "SuppAmmo.sqf").read_text(encoding="utf-8")
    med = (HAL / "SuppMed.sqf").read_text(encoding="utf-8")

    assert 'RydHQ_ExReAmmo' in ammo
    assert 'RydHQ_Hollow' in ammo
    assert 'RydHQ_ASupportedG' in ammo

    assert 'RydHQ_ExMedic' in med
    assert 'RydHQ_Wounded' in med
    assert 'RydHQ_SupportedG' in med


def test_demand_dispatch_parenthesizes_negated_getvariable_booleans():
    text = (MISSION / "ITW_CLASH_PlayerDemandDispatch.sqf").read_text(encoding="utf-8")

    # In SQF, ! binds before getVariable.  "!_group getVariable [...]" tries
    # to negate the Group object and aborts the caller before task finalization.
    assert '!(_group getVariable ["ITW_CLASH_AuthorityHold",false])' in text
    assert '!(missionNamespace getVariable ["ITW_CLASH_HALReady",false])' in text
    assert re.search(r"!\s*[_A-Za-z]\w*\s+getVariable", text) is None


def test_native_ammo_execution_preserves_scheduled_context():
    text = (MISSION / "ITW_CLASH_PlayerDemandNativeInterceptors.sqf").read_text(encoding="utf-8")
    wrapper = text.split("HAL_GoAmmoSupp = {", 1)[1].split(
        "ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase", 1
    )[0]

    assert "ITW_CLASH_PlayerDemandNativeInterceptorsVersion = 8;" in text
    assert "ITW_CLASH_PlayerDemandNative_fnc_GoAmmoSuppBase" in wrapper
    assert "isNil {" not in wrapper
    assert 'if (isNil "_nativeResult") exitWith {};' in wrapper
