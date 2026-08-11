from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_casevac_is_started_by_server_init():
    init = text("init.sqf")
    assert 'fileExists "ITW_CLASH_CASEVAC.sqf"' in init
    assert 'execVM "ITW_CLASH_CASEVAC.sqf"' in init
    assert "walking withdrawal remains active" in init


def test_casevac_requires_real_disengagement_before_dispatch():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert "ITW_CLASH_CASEVAC_MinWithdrawalTime = 60;" in source
    assert "ITW_CLASH_CASEVAC_MinDisengageDistance = 500;" in source
    assert "ITW_CLASH_CASEVAC_EnemyClearance = 650;" in source
    assert "ITW_CLASH_CASEVAC_ObjectiveClearance = 500;" in source
    assert "ITW_CLASH_CASEVAC_MinEgressDistance = 1000;" in source
    assert "_moved < ITW_CLASH_CASEVAC_MinDisengageDistance" in source
    assert "_enemyDistance < ITW_CLASH_CASEVAC_EnemyClearance" in source
    assert "_objectiveClearance < ITW_CLASH_CASEVAC_ObjectiveClearance" in source
    assert "_egressDistance < ITW_CLASH_CASEVAC_MinEgressDistance" in source


def test_casevac_uses_real_boarding_and_visual_smoke():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert 'ITW_CLASH_CASEVAC_SmokeClass = "SmokeShell";' in source
    assert 'createVehicle [' in source
    assert 'assignAsCargo _heli' in source
    assert 'orderGetIn true' in source
    assert 'land "GET IN"' in source
    assert "moveInAny" not in source
    assert "moveInCargo" not in source


def test_casevac_reuses_impasse_heli_supply_and_ticket_accounting():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert "ITW_AtkReconstitutionTransportContext" in source
    assert "ITW_TYPE_VEH_HELI" in source
    assert "ITW_AtkSpawnVeh" in source
    assert "ITW_TICKET_REDUCE" in source
    assert "ITW_VEH_COUNT_INCR" in source
    assert "ITW_AtkVehRemoveMagazines" in source
    # CASEVAC owns these aircraft; the normal Impasse vehicle manager must not retask them.
    assert "ITW_AtkAddVehicle" not in source


def test_casevac_capacity_is_bounded_and_failure_returns_to_foot_egress():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert "ITW_CLASH_CASEVAC_MaxConcurrent = 2;" in source
    assert "ITW_CLASH_CASEVAC_RetryCooldown = 120;" in source
    assert "ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal" in source
    assert "ITW_CLASH_fnc_OrderWithdrawal" in source
    assert '"aircraft-lost-inbound"' in source
    assert '"boarding-timeout"' in source
    assert '"aircraft-lost-rtb"' in source


def test_casevac_cannot_create_a_second_reconstitution_credit_path():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert "ITW_AtkQueueReconstitution" not in source
    assert "canonical 150 m absorption" in source
    assert "ITW_CLASH_Withdrawals getOrDefault" in source
    assert '"returned"' in source


def test_casevac_suppresses_foot_waypoint_refresh_only_while_active():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert "_entry set [8,time + 1e6];" in source
    assert "_entry set [8,-1000];" in source
    assert "_entry set [8,time];" in source


def test_casevac_source_delimiters_balance():
    source = text("ITW_CLASH_CASEVAC.sqf")
    pairs = [("(", ")"), ("[", "]"), ("{", "}")]
    for left, right in pairs:
        assert source.count(left) == source.count(right)


def test_casevac_aborts_if_contact_reestablishes_inbound():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert "ITW_CLASH_CASEVAC_InboundAbortClearance = 450;" in source
    assert '"contact-reestablished"' in source
    assert '"abort-contact"' in source
    assert "_nextContactCheck = time + 5;" in source
    assert 'scopeName "ITW_CLASH_CASEVAC_InboundScope";' in source
    assert 'breakOut "ITW_CLASH_CASEVAC_InboundScope";' in source


def test_casevac_crew_stays_server_local():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert '_crewGroup setVariable ["noHeadless",true];' in source


def test_casevac_rear_handoff_never_deletes_loaded_survivors():
    source = text("ITW_CLASH_CASEVAC.sqf")
    assert '"rear-handoff-fallback"' in source
    assert '"rear-absorption-timeout"' in source
    assert '_heli land "GET OUT";' in source
    assert '_x action ["GetOut",_heli];' in source
