from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def ground_text() -> str:
    return "\n".join([
        text("ITW_CLASH_GroundMEDEVAC.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_Extraction.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_Manager.sqf"),
    ])


def test_ground_medevac_is_wired_after_casevac_stack():
    init = text("init.sqf")
    assert 'execVM "ITW_CLASH_CASEVAC.sqf"' in init
    assert 'execVM "ITW_CLASH_CASEVAC_AirOpsFix.sqf"' in init
    assert 'execVM "ITW_CLASH_CASEVAC_LZPadFix.sqf"' in init
    assert 'execVM "ITW_CLASH_GroundMEDEVAC.sqf"' in init
    assert init.index('execVM "ITW_CLASH_CASEVAC.sqf"') < init.index('execVM "ITW_CLASH_GroundMEDEVAC.sqf"')
    main = text("ITW_CLASH_GroundMEDEVAC.sqf")
    assert 'ITW_CLASH_GroundMEDEVAC_Extraction.sqf' in main
    assert 'ITW_CLASH_GroundMEDEVAC_Manager.sqf' in main


def test_ground_medevac_doctrine_gates_are_explicit():
    source = ground_text()
    expected = [
        "ITW_CLASH_GroundMEDEVAC_MaxConcurrent = 2;",
        "ITW_CLASH_GroundMEDEVAC_MinWithdrawalTime = 60;",
        "ITW_CLASH_GroundMEDEVAC_MinDisengageDistance = 500;",
        "ITW_CLASH_GroundMEDEVAC_EnemyClearance = 700;",
        "ITW_CLASH_GroundMEDEVAC_InboundAbortClearance = 500;",
        "ITW_CLASH_GroundMEDEVAC_ObjectiveClearance = 500;",
        "ITW_CLASH_GroundMEDEVAC_MinEgressDistance = 900;",
        "ITW_CLASH_GroundMEDEVAC_MaxPreferredEgressDistance = 3500;",
        "ITW_CLASH_GroundMEDEVAC_RallyOffset = 30;",
    ]
    for token in expected:
        assert token in source


def test_ground_medevac_requires_local_land_corridor_and_roadside_pickup():
    source = ground_text()
    assert '(_source find "support-corridor-land") != 0' in source
    assert "nearRoads ITW_CLASH_GroundMEDEVAC_RoadSearchRadius" in source
    assert "BIS_fnc_nearestPosition" in source
    assert "ITW_CLASH_GroundMEDEVAC_RallyOffset" in source
    assert '_wp setWaypointCompletionRadius 15;' in source
    assert "forceFollowRoad true" in source


def test_ground_medevac_only_uses_car_or_apc_transport_context_and_bypasses_count_cap():
    source = ground_text()
    assert "(_transport + _dualVeh) select" in source
    assert "[ITW_TYPE_VEH_CAR,ITW_TYPE_VEH_APC]" in source
    assert "ITW_VEH_REQD_TICKETS" in source
    assert "ITW_VEH_CURR_TICKETS" in source
    candidate_block = source[source.index("private _candidates ="):source.index("if (_candidates isEqualTo [])")]
    assert "ITW_VEH_MAX" not in candidate_block
    assert "ITW_VEH_COUNT_INCR" in source
    assert "ITW_TICKET_REDUCE" in source
    assert '"cap-bypass"' in source


def test_ground_medevac_prefers_medical_then_soft_transport_then_apc():
    source = ground_text()
    assert 'find "ambulance"' in source
    assert 'find "medical"' in source
    assert 'find "medevac"' in source
    assert "_medical + _pureCars + _pureAPCs + _dualCars + _dualAPCs" in source


def test_ground_pickup_is_physical_not_teleported():
    source = ground_text()
    assert "assignAsCargo" in source
    assert "orderGetIn true" in source
    assert "moveInAny" not in source
    assert "moveInCargo" not in source
    assert "setPosATL" not in source


def test_ground_medevac_never_owns_reconstitution_credit():
    source = ground_text()
    assert "ITW_AtkQueueReconstitution" not in source
    assert "ITW_CLASH_Withdrawals getOrDefault" in source
    assert "_veh distance2D _returnPos <= 140" in source
    assert "rear-absorption-timeout" in source


def test_ground_and_air_are_mutually_exclusive_but_air_reopens_on_ground_deferral():
    source = ground_text()
    assert "ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase" in source
    assert 'ITW_CLASH_CASEVAC_State","ground-inbound"' in source
    assert 'ITW_CLASH_CASEVAC_State","ground-rtb"' in source
    assert "air-deferred-ground-preferred" in source
    assert "ITW_CLASH_GroundMEDEVAC_AirFallbackDelay = 30;" in source
    assert '"no-ground-vehicle-available"' in source


def test_ground_failure_restores_physical_foot_withdrawal():
    source = ground_text()
    assert 'call ITW_CLASH_fnc_OrderWithdrawal;' in source
    assert 'action ["GetOut",_veh]' in source
    assert "_dismountDeadline = time + 8" in source
    assert "moveOut _" not in source
    assert "ITW_CLASH_GroundMEDEVAC_RetryCooldown = 120;" in source
