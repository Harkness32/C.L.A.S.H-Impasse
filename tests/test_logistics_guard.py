from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_logistics_guard_is_started_by_server_init():
    init = text("init.sqf")
    assert 'fileExists "ITW_CLASH_LogisticsGuard.sqf"' in init
    assert 'execVM "ITW_CLASH_LogisticsGuard.sqf"' in init


def test_egress_completion_radius_is_150m():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert "ITW_CLASH_LogisticsHandoffVersion = 2;" in guard
    assert "ITW_CLASH_WithdrawalArrivalRadius = 150;" in guard
    assert "logistics-guard-ready" in guard


def test_foot_withdrawal_waypoint_is_tighter_than_absorption_envelope():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert "ITW_CLASH_WithdrawalWaypointRadius = 100;" in guard
    assert '"ITW_CLASH_CASEVAC_State"' in guard
    assert '"ITW_CLASH_GroundMEDEVAC_State"' in guard
    assert "_wp setWaypointPosition [_destination,0];" in guard
    assert "_wp setWaypointCompletionRadius ITW_CLASH_WithdrawalWaypointRadius;" in guard
    assert '"withdrawal-egress-waypoint-hardened"' in guard


def test_ground_medevac_rtb_driver_is_reissued_only_when_stuck():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert "ITW_CLASH_GroundMEDEVAC_Active" in guard
    assert 'isNotEqualTo "rtb"' in guard
    assert "abs speed _veh >= 2" in guard
    assert "_veh distance2D _target <= 100" in guard
    assert "_driver doMove _target;" in guard
    assert '"medevac-rtb-driver-unstick"' in guard


def test_reconstitution_queue_tracks_live_group_state():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert '"ITW_CLASH_TransitState"' in guard
    assert '"ITW_CLASH_TransitVehicle"' in guard
    assert "_entry set [8,_liveState];" in guard
    assert "reconstitution-transit-state-synced" in guard


def test_live_vehicle_only_repairs_stale_waiting_state():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert '_cachedState isEqualTo "waiting-transport"' in guard
    assert '_liveState isEqualTo "waiting-transport"' in guard
    assert '_liveState = "transport";' in guard
    assert "must not force it back to transport" in guard


def test_reconstitution_dismount_clears_stale_assigned_vehicle_before_hal():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert "assignedVehicles _grp" in guard
    assert '_liveState in ["transport","walking"]' in guard
    assert "{unassignVehicle _x} forEach _transitUnits;" in guard
    assert '"reconstitution-transport-unassigned"' in guard


def test_normal_transport_dismount_gets_clash_settling_window():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert "ITW_CLASH_PostTransportSettle = 30;" in guard
    assert '"ITW_CLASH_TransportSeen",true' in guard
    assert '"ITW_CLASH_ReeligibleAt"' in guard
    assert '"itwInitGrp",true,true' not in guard
    assert '"itwInitGrp",nil,true' not in guard
    assert "transport-handoff-settle" in guard
    assert "transport-handoff-ready" in guard


def test_impasse_land_transport_one_km_overshoot_is_pruned():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert "waypointCompletionRadius _rtbWp" in guard
    assert "waypointCompletionRadius _overshootWp" in guard
    assert "abs (_rtbRadius - 220)" in guard
    assert "abs (_overshootRadius - 210)" in guard
    assert "_legDistance < 900" in guard
    assert "_legDistance > 1100" in guard
    assert "deleteWaypoint _overshootWp;" in guard
    assert "transport-rtb-overshoot-pruned" in guard
