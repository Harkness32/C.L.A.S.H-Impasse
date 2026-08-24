from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def source(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_seaguard_is_projection_only_and_cannot_clobber_service_home():
    sea = source("ITW_CLASH_SeaGenerationGuard.sqf")
    resolver = source("ITW_CLASH_ServiceHomeResolver.sqf")

    assert 'ITW_CLASH_SeaGenerationGuardVersion = 3;' in sea
    assert '_entry set ["deploymentOrigin",getPosATL _veh];' in sea
    assert '"projection-only"' in sea
    assert 'projectionOnly=true serviceHomeWrites=false' in sea

    # SeaGuard may project a hull onto navigable water, but the live service-home
    # resolver is the only layer allowed to select/write home or RTB progress.
    assert '_entry set ["home",' not in sea
    assert '_entry set ["lastDistance",0]' not in sea
    assert '_group setVariable ["ITW_CLASH_ServiceHome",' not in sea
    assert 'SeaGuard is the final authority on ship home' not in sea
    assert 'seaGuardProjectionOnly=true' in resolver


def test_embarked_hal_contract_defers_unlock_until_physical_unlink():
    bridge = source("ITW_CLASH_PlayerTransportNativeBridge.sqf")

    assert 'ITW_CLASH_PlayerTransportNativeBridgeVersion = 5;' in bridge
    assert 'ITW_CLASH_PlayerTransport_fnc_CargoAboardCarrier' in bridge
    assert 'alive _x && {vehicle _x == _carrier}' in bridge
    assert '"hal-contract-end-deferred-embarked"' in bridge
    assert 'scriptName "ITW_CLASH_PlayerTransportDeferredEnd"' in bridge
    assert '"endDeferredReason"' in bridge
    assert 'contractEndUnlockSeparated=true' in bridge

    end_start = bridge.index("ITW_CLASH_PlayerTransport_fnc_EndObservedHALContract = {")
    end_stop = bridge.index("ITW_CLASH_PlayerTransport_fnc_MonitorObservedHALContract = {", end_start)
    end_body = bridge[end_start:end_stop]

    defer_index = end_body.index("if (_aboard) exitWith {")
    clear_lock_index = end_body.index("ITW_CLASH_PlayerTransport_fnc_ClearRetaskLock")
    clear_contract_index = end_body.index(
        '_group setVariable ["ITW_CLASH_PlayerTransportContract",nil]'
    )
    assert defer_index < clear_lock_index
    assert defer_index < clear_contract_index
    assert ':physical-unlink' in end_body


def test_ferry_retask_lock_is_continuously_reconciled_without_corrupting_ownership():
    bridge = source("ITW_CLASH_PlayerTransportNativeBridge.sqf")

    assert 'ITW_CLASH_PlayerTransport_fnc_EnsureRetaskLock' in bridge
    assert '"hal-retask-lock-reconciled"' in bridge
    assert 'retaskLockReconciled=true' in bridge

    ensure_start = bridge.index("ITW_CLASH_PlayerTransport_fnc_EnsureRetaskLock = {")
    ensure_stop = bridge.index("ITW_CLASH_PlayerTransport_fnc_EndObservedHALContract = {", ensure_start)
    ensure = bridge[ensure_start:ensure_stop]

    for name in ("RydHQ_NoAttack", "RydHQ_NoRecon", "RydHQ_NoDef"):
        assert f'"{name}"' in ensure
    assert 'ITW_CLASH_TransportRetaskOwned' not in ensure
    assert '_members pushBackUnique _group;' in ensure

    monitor_start = bridge.index("ITW_CLASH_PlayerTransport_fnc_MonitorObservedHALContract = {")
    monitor_stop = bridge.index("ITW_CLASH_PlayerTransport_fnc_ObserveHALDemand = {", monitor_start)
    monitor = bridge[monitor_start:monitor_stop]
    assert '"active-contract-watch"' in monitor
    assert 'ITW_CLASH_PlayerTransport_fnc_EnsureRetaskLock' in monitor

    end_start = bridge.index("ITW_CLASH_PlayerTransport_fnc_EndObservedHALContract = {")
    end_stop = bridge.index("ITW_CLASH_PlayerTransport_fnc_MonitorObservedHALContract = {", end_start)
    end_body = bridge[end_start:end_stop]
    assert '"deferred-unlink-watch"' in end_body
    assert 'ITW_CLASH_PlayerTransport_fnc_EnsureRetaskLock' in end_body


def test_player_air_transport_rtb_is_advisory_and_completes_on_return():
    rtb = source("ITW_CLASH_PlayerTransportRTB.sqf")
    logistics = source("ITW_CLASH_HALLogistics.sqf")

    assert 'ITW_CLASH_PlayerTransportRTBVersion = 1;' in rtb
    assert '"ITW_CLASH_PlayerTransportContract"' in rtb
    assert '(_contract getOrDefault ["source",""]) != "HAL_SCargo"' in rtb
    assert '_carrier isKindOf "Air"' in rtb
    assert '(units _carrierGroup findIf {isPlayer _x}) >= 0' in rtb
    assert '"HACAddedTasks"' in rtb
    assert '"return to base"' in rtb
    assert '"return to departure base."' in rtb
    assert 'taskDestination _trackedTask' in rtb
    assert 'isTouchingGround _carrier' in rtb
    assert '(_carrier distance2D _destination) <= ITW_CLASH_PlayerTransportRTBRadius' in rtb
    assert '[_trackedTask,"SUCCEEDED",true] call BIS_fnc_taskSetState;' in rtb
    assert '"player-rtb-armed"' not in rtb  # prefix is added by the logger, not duplicated by event names
    assert '["armed",[' in rtb
    assert '["completed",[' in rtb
    assert 'halRTBAdvisory=true' in rtb

    # The adapter observes the task HAL created; it must never become a second
    # aircraft movement executor.
    forbidden = (
        "RYD_WPadd",
        "addWaypoint",
        "doMove",
        "moveTo",
        "setWaypointPosition",
        "land 'LAND'",
        'land "LAND"',
    )
    for token in forbidden:
        assert token not in rtb

    assert 'fileExists "ITW_CLASH_PlayerTransportRTB.sqf"' in logistics
    assert '[] execVM "ITW_CLASH_PlayerTransportRTB.sqf";' in logistics


def test_leader_cancel_gate_survives_native_action_binder_failure():
    hardening = source("ITW_CLASH_PlayerTaskStateHardening.sqf")

    assert 'ITW_CLASH_PlayerTaskStateHardeningVersion = 3;' in hardening
    assert 'ITW_CLASH_PlayerTaskState_fnc_InstallLeaderCancelGate' in hardening
    assert 'scriptName "ITW_CLASH_PlayerTaskStateLeaderGate"' in hardening
    assert '"leaderGateRetained"' in hardening
    assert 'degradedLeaderGate=true' in hardening

    gate_start = hardening.index("ITW_CLASH_PlayerTaskState_fnc_InstallLeaderCancelGate = {")
    gate_stop = hardening.index("// Phase 1:", gate_start)
    gate = hardening[gate_start:gate_stop]

    assert "ITW_CLASH_PlayerTasks_fnc_CancelRemote = {" in gate
    assert "ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid" in gate
    assert "[_player,true] call" in gate
    assert "Only the group leader can cancel HAL employment." in gate
    assert "NativeAction1" not in gate


def test_hosted_action_cancel_cannot_issue_native_deny_twice():
    hardening = source("ITW_CLASH_PlayerTaskStateHardening.sqf")

    assert '"ITW_CLASH_PlayerNativeJobCancelRequested",false' in hardening
    assert 'if (_nativeActive && {_nativeDenyInFlight}) then {' in hardening
    assert '"cancel-native-deny-already-in-flight"' in hardening
    assert 'ITW_CLASH_PlayerTaskState_fnc_Action1CancelBase = Action1ct;' in hardening
    assert 'hostedDoubleDenyGuard=true' in hardening

    cancel_start = hardening.index("ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {")
    action_start = hardening.index("ITW_CLASH_PlayerTaskState_fnc_Action1CancelBase = Action1ct;")
    cancel = hardening[cancel_start:action_start]

    inflight_index = cancel.index("if (_nativeActive && {_nativeDenyInFlight}) then {")
    native_call_index = cancel.index("[_leader] call ITW_CLASH_PlayerTasks_fnc_NativeAction1;")
    assert inflight_index < native_call_index

    action = hardening[action_start:]
    set_index = action.index('"ITW_CLASH_PlayerNativeJobCancelRequested",true')
    base_call_index = action.index(
        "_this call ITW_CLASH_PlayerTaskState_fnc_Action1CancelBase"
    )
    clear_index = action.index('"ITW_CLASH_PlayerNativeJobCancelRequested",nil')
    assert set_index < base_call_index < clear_index
