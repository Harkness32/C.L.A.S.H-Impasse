from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "13715765820790864929_legacy"


def source(name: str) -> str:
    return (LEGACY / name).read_text(encoding="utf-8")


def test_authoritative_job_gate_is_channel_specific_and_busy_aware() -> None:
    hardening = source("ITW_CLASH_PlayerTaskStateHardening.sqf")

    assert "ITW_CLASH_PlayerTasks_fnc_CanAcceptJob" in hardening
    assert "ITW_CLASH_PlayerTasks_fnc_HasActiveJob" in hardening
    assert '"Busy" + str _group' in hardening
    assert "ITW_CLASH_PlayerAmmoJobId" in hardening
    assert "ITW_CLASH_PlayerArtilleryJobId" in hardening
    assert "ITW_CLASH_PlayerNativeJobId" in hardening
    for job_type in (
        "COMBAT",
        "TRANSPORT",
        "MEDEVAC",
        "LOGISTICS",
        "ARTILLERY",
    ):
        assert f'case "{job_type}"' in hardening or f'"{job_type}"' in hardening


def test_availability_means_free_not_merely_capable() -> None:
    hardening = source("ITW_CLASH_PlayerTaskStateHardening.sqf")

    assert "private _occupied = [_group] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob" in hardening
    assert "private _available = _capable && {!_occupied};" in hardening
    assert '"ITW_CLASH_PlayerTaskAvailable",_available,true' in hardening
    assert '"ITW_CLASH_PlayerHasActiveHALJob",_occupied,true' in hardening
    assert '"Unable",!_available,true' in hardening
    assert '"BUnable",!_available,true' in hardening


def test_combat_subscription_controls_native_tactical_pools() -> None:
    hardening = source("ITW_CLASH_PlayerTaskStateHardening.sqf")
    recon = source("ITW_CLASH_ReconObserver.sqf")

    assert "ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission" in hardening
    assert '[_group,"COMBAT"] call' in hardening
    assert "RydHQ_NoRecon" in hardening
    assert "RydHQ_CargoOnly" in hardening
    assert "ITW_CLASH_PlayerCombatGateOwnsNoRecon" in hardening
    assert "ITW_CLASH_PlayerCombatGateOwnsCargoOnly" in hardening

    assert "ITW_CLASH_Recon_fnc_PlayerCombatAllowed" in recon
    assert '[_group,"COMBAT",true] call' in recon
    assert "combat-channel-disabled" in recon
    assert "tasking-rejected" in recon


def test_native_cancel_path_is_restored_and_server_authorized() -> None:
    hardening = source("ITW_CLASH_PlayerTaskStateHardening.sqf")

    assert "ITW_CLASH_PlayerTaskState_fnc_CancelGroupJobBase" in hardening
    assert "ITW_CLASH_PlayerTasks_fnc_NativeAction1" in hardening
    assert '"cancel-request"' in hardening
    assert '"cancel-accepted"' in hardening
    assert '"cancel-settled"' in hardening
    assert "ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid" in hardening
    assert "[_player,true] call" in hardening


def test_transport_checkbook_reuses_truthful_hal_availability() -> None:
    hardening = source("ITW_CLASH_PlayerTaskStateHardening.sqf")
    checkbook = source("ITW_CLASH_DualHALCheckbook.sqf")

    assert '"Unable",!_available,true' in hardening
    assert "ITW_CLASH_Checkbook_fnc_HasCargoCapacity" in checkbook
    assert 'getVariable ["Busy" + str _group,false]' in checkbook
    assert 'getVariable ["Unable",false]' in checkbook
    assert "if (!_has) then" in checkbook
    assert 'ITW_CLASH_fnc_RequestCapability' in checkbook


def test_employment_menu_uses_generic_active_job_state() -> None:
    menu = source("ITW_CLASH_PlayerEmploymentMenu.sqf")

    assert "ITW_CLASH_PlayerHasActiveHALJob" in menu
    assert "[ACTIVE] Cancel Current HAL Job" in menu
    assert '"ITW_CLASH_PlayerTasks_fnc_CancelRemote",2' in menu


def test_admission_watcher_starts_before_player_task_support_binder() -> None:
    transport = source("ITW_CLASH_PlayerTransportAuthority.sqf")
    hardening = source("ITW_CLASH_PlayerTaskStateHardening.sqf")

    assert 'execVM "ITW_CLASH_PlayerTaskStateHardening.sqf"' in transport
    admission = hardening[
        hardening.index('scriptName "ITW_CLASH_PlayerTaskStateAdmission"') :
        hardening.index('scriptName "ITW_CLASH_PlayerTaskStateCancelBinder"')
    ]
    assert "ITW_CLASH_PlayerTaskSupportReady" not in admission
    assert "ITW_CLASH_PlayerTasks_fnc_GetSubscriptions" in admission
    assert "ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle" in admission


def test_transport_authority_keeps_original_null_hq_fail_open_shape() -> None:
    transport = source("ITW_CLASH_PlayerTransportAuthority.sqf")
    remove = transport[
        transport.index("ITW_CLASH_PlayerTransport_fnc_RemoveFromHAL = {") :
        transport.index("ITW_CLASH_PlayerTransport_fnc_Acquire = {")
    ]

    assert 'if (!isNull _hq) then {' in remove
    assert 'if (isNull _hq) exitWith {false};' not in remove
    assert '_group setVariable ["ITW_CLASH_AuthorityHold",true];' in remove


def test_recon_loads_state_hardening_before_installing_wrappers() -> None:
    recon = source("ITW_CLASH_ReconObserver.sqf")

    load_index = recon.index("ITW_CLASH_PlayerTaskStateHardening.sqf")
    wrapper_index = recon.index("ITW_CLASH_Recon_fnc_NativeGoRecon = HAL_GoRecon")
    assert load_index < wrapper_index
