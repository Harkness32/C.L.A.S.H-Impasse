from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def source(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_seaguard_is_projection_only_and_cannot_clobber_service_home():
    sea = source("ITW_CLASH_SeaGenerationGuard.sqf")
    resolver = source("ITW_CLASH_ServiceHomeResolver.sqf")

    assert 'ITW_CLASH_SeaGenerationGuardVersion = 3;' in sea
    assert '_entry set ["deploymentOrigin",getPosATL _veh];' in sea
    assert '"projection-only"' in sea
    assert 'projectionOnly=true serviceHomeWrites=false' in sea

    assert '_entry set ["home",' not in sea
    assert '_entry set ["lastDistance",0]' not in sea
    assert '_group setVariable ["ITW_CLASH_ServiceHome",' not in sea
    assert 'SeaGuard is the final authority on ship home' not in sea
    assert 'seaGuardProjectionOnly=true' in resolver


def test_embarked_hal_contract_defers_unlock_until_physical_unlink():
    bridge = source("ITW_CLASH_PlayerTransportNativeBridge.sqf")

    assert 'ITW_CLASH_PlayerTransportNativeBridgeVersion = 7;' in bridge
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


def test_player_hal_carrier_start_is_written_only_by_service_home_authority():
    home = source("ITW_CLASH_PlayerCarrierHome.sqf")
    resolver = source("ITW_CLASH_ServiceHomeResolver.sqf")
    rtb = source("ITW_CLASH_PlayerTransportRTB.sqf")

    assert 'ITW_CLASH_PlayerCarrierHomeVersion = 3;' in home
    assert 'ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup' in home
    assert 'ITW_CLASH_ServiceHomeResolverVersion = 3;' in resolver
    assert 'ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup = {' in resolver
    assert '_group setVariable ["START" + str _group,+_position];' in resolver
    assert '_group setVariable ["ITW_CLASH_ServiceHome",+_position];' in resolver
    assert 'transientGroupWriteThrough=true' in resolver

    assert '_group setVariable ["START" + str _group,+_position];' not in home
    assert 'ITW_CLASH_Service_fnc_RegisterPhysical' not in home
    assert 'ITW_CLASH_ServicePool pushBack' not in home
    assert 'random 200' not in home
    assert 'position (vehicle (leader _HQ))' not in home
    assert 'serviceHomeOwnsSTART=true' in home
    assert 'servicePoolRegistration=false' in home
    assert 'halRTBExecutor=true' in home

    assert 'fileExists "ITW_CLASH_PlayerCarrierHome.sqf"' in rtb
    assert '[] execVM "ITW_CLASH_PlayerCarrierHome.sqf";' in rtb


def test_native_scargo_has_two_player_rtb_shapes_and_no_live_completion_path():
    scargo = (HAL / "SCargo.sqf").read_text(encoding="utf-8")

    assert '"Abort Pick Up, RTB"' in scargo
    assert '"Return To Base"' in scargo
    completion = '[_task,"SUCCEEDED",true] call BIS_fnc_taskSetState'
    assert scargo.count(completion) >= 2
    live_completion_lines = [
        line.strip() for line in scargo.splitlines()
        if completion in line and not line.lstrip().startswith("//")
    ]
    assert live_completion_lines == []
    assert '/*\n\t_GD Move _LandPos;' in scargo
    assert '((_cnt < 1) and (((getpos _ChosenOne) select 2) < 1))' in scargo
    assert 'if (abs (speed _ChosenOne) < 0.5) then {_timer = _timer + 5};' in scargo


def test_player_air_transport_rtb_covers_abort_delivery_landing_and_timeout():
    rtb = source("ITW_CLASH_PlayerTransportRTB.sqf")
    home = source("ITW_CLASH_PlayerCarrierHome.sqf")
    logistics = source("ITW_CLASH_HALLogistics.sqf")

    assert 'ITW_CLASH_PlayerTransportRTBVersion = 3;' in rtb
    assert '"ITW_CLASH_PlayerTransportRTBRadius",350' in rtb
    assert '"ITW_CLASH_PlayerTransportRTBStopTimeout",120' in rtb
    assert 'if (_title == "abort pick up, rtb") exitWith {"ABORT"};' in rtb
    assert 'if (_title == "return to base") exitWith {"DELIVERY"};' in rtb
    assert '"HACAddedTasks"' in rtb
    assert 'taskDestination _trackedTask' in rtb
    assert '((getPosATL _carrier)#2) < 1' in rtb
    assert 'abs speed _carrier < 0.5' in rtb
    assert 'ITW_CLASH_PlayerTransportRTB_fnc_CargoUnlinked' in rtb
    assert 'ITW_CLASH_PlayerTransportRTBStoppedSeconds' in rtb
    assert '_stoppedSeconds >= ITW_CLASH_PlayerTransportRTBStopTimeout' in rtb
    assert '_method = "landed";' in rtb
    assert '_method = "timeout";' in rtb
    assert '[_trackedTask,"SUCCEEDED",true] call BIS_fnc_taskSetState;' in rtb
    assert '["rtb-" + _event,_payload] call ITW_CLASH_PlayerTransport_fnc_Log;' in rtb
    assert '["completed",[' in rtb
    assert '"method=" + _method' in rtb
    assert 'abortAndDelivery=true' in rtb
    assert 'altitudeLt1=true' in rtb
    assert 'speedLt0_5=true' in rtb
    assert 'cargoUnlinked=true' in rtb
    assert 'stoppedTimeout=%3' in rtb

    assert 'ITW_CLASH_PlayerTasks_fnc_SyncAll = {' in home
    assert 'ITW_CLASH_PlayerTasks_fnc_SyncEmploymentState' in home
    assert 'ITW_CLASH_DualHAL_fnc_SyncIncluded' in home
    assert 'call ITW_CLASH_PlayerTasks_fnc_SyncAll;' in rtb

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
        assert token not in home

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
