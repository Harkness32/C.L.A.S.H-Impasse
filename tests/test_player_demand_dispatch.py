from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
DOCS = ROOT / "docs"


def _block(text: str, start_marker: str, end_marker: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[start:end]


def test_design_contract_makes_subscription_not_vehicle_the_dispatch_gate():
    text = (DOCS / "PLAYER_EMPLOYMENT_DEMAND_DISPATCH.md").read_text(encoding="utf-8")

    assert "Subscription gates dispatch. Capability gates execution." in text
    assert "A player's current vehicle never decides whether they are told about subscribed work." in text
    assert "Cancellation means **release**, not deletion." in text
    assert '"Tell me when this kind of work exists."' in text


def test_demand_layer_loads_after_player_task_surfaces_exist():
    init = (MISSION / "init.sqf").read_text(encoding="utf-8")
    demand = (MISSION / "ITW_CLASH_PlayerDemandDispatch.sqf").read_text(encoding="utf-8")

    assert '"ITW_CLASH_PlayerDemandDispatch.sqf"' in init
    assert '"ITW_CLASH_PlayerDemandNativeInterceptors.sqf"' in init
    assert 'ITW_CLASH_PlayerTaskStateHardeningReady' in demand
    assert 'ITW_CLASH_PlayerTaskStateCancelReady' in demand
    assert 'ITW_CLASH_PlayerTaskStateArtilleryGuardReady' in demand
    assert 'player-demand-dispatch-ready' in demand


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
    assert 'declinedGroups' in release
    assert 'ITW_CLASH_PlayerDemand_fnc_RestoreSuppression' in release
    assert '["state",if (_valid) then {"OPEN"} else {"INVALID"}]' in release
    assert 'ITW_CLASH_PlayerJobSubscriptions' not in release


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
    assert 'player-demand-completed' not in execute  # completion goes through the shared lifecycle helper


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
