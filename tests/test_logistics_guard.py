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
    assert "ITW_CLASH_WithdrawalArrivalRadius = 150;" in guard
    assert "logistics-guard-ready" in guard


def test_reconstitution_queue_tracks_live_group_state():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert '"ITW_CLASH_TransitState"' in guard
    assert '"ITW_CLASH_TransitVehicle"' in guard
    assert "_entry set [8,_liveState];" in guard
    assert "reconstitution-transit-state-synced" in guard


def test_normal_transport_dismount_gets_settling_window():
    guard = text("ITW_CLASH_LogisticsGuard.sqf")
    assert "ITW_CLASH_PostTransportSettle = 30;" in guard
    assert '"ITW_CLASH_TransportSeen",true' in guard
    assert '"ITW_CLASH_PostTransportUntil"' in guard
    assert '"itwInitGrp",true,true' in guard
    assert '"itwInitGrp",nil,true' in guard
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
