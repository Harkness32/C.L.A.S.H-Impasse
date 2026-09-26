from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def diag() -> str:
    return text("ITW_CLASH_CombatDiagnostics.sqf")


def test_combat_diagnostics_is_server_wired_and_waits_for_hal():
    init = text("init.sqf")
    source = diag()
    assert 'fileExists "ITW_CLASH_CombatDiagnostics.sqf"' in init
    assert 'execVM "ITW_CLASH_CombatDiagnostics.sqf"' in init
    assert "if (!isServer) exitWith {false};" in source
    assert 'missionNamespace getVariable ["ITW_CLASH_HALReady",false]' in source
    assert "combat-diagnostics-ready" in source


def test_combat_diagnostics_is_observer_only():
    source = diag()
    # Read-only inspection is allowed; authority-changing forms are not.
    forbidden = [
        " enableAttack ",
        " disableAI ",
        " enableAI ",
        " setCombatMode ",
        " setBehaviour ",
        " setCombatBehaviour ",
        " addWaypoint ",
        " setWaypoint",
        " createVehicle ",
        " createUnit ",
        " deleteWaypoint ",
        " doMove ",
        " moveIn",
        " orderGetIn ",
        " setCaptive ",
        " setFriend ",
    ]
    body = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("//")
    )
    for token in forbidden:
        assert token not in body


def test_contact_scan_is_detection_independent_and_physical():
    source = diag()
    assert "allGroups select" in source
    assert "distance2D" in source
    assert "getFriend" in source
    assert "CombatDiagnosticsContactRadius = 200" in source
    # Knowledge is measured after physical pairing rather than used to discover it.
    assert "knowsAbout _otherUnit" in source
    assert "findNearestEnemy" in source
    assert '"contact-anomaly"' in source
    assert '"close-but-no-unit-knowledge"' in source
    assert '"close-but-findnearestenemy-null"' in source


def test_diagnostics_capture_attack_and_ai_feature_state():
    source = diag()
    assert "attackEnabled _group" in source
    assert "attackEnabled _unit" in source
    assert 'checkAIFeature "TARGET"' in source
    assert 'checkAIFeature "AUTOTARGET"' in source
    assert 'checkAIFeature "MOVE"' in source
    assert 'checkAIFeature "FSM"' in source
    assert "unitCombatMode _unit" in source
    assert "combatMode _group" in source
    assert "behaviour _unit" in source
    assert "combatBehaviour _unit" in source
    assert "captive _unit" in source
    assert "targetKnowledge _other" in source
    assert "targets _group" in source


def test_diagnostics_capture_hal_recon_and_defensive_bookkeeping():
    source = diag()
    for token in [
        '"RydHQ_ReconStage"',
        '"RydHQ_ReconStage2"',
        '"RydHQ_ReconDone"',
        '"RydHQ_LastE"',
        '"RydHQ_AttackAv"',
        '"RydHQ_CombatAv"',
        '"RydHQ_ReconAv"',
        '"RydHQ_ReconG"',
        '"RydHQ_SpecForG"',
        '"RydHQ_NoRecon"',
        '"RydHQ_NoAttack"',
        '"RydHQ_DefSpot"',
        '"RydHQ_RecDefSpot"',
        '"RydHQ_Exhausted"',
        '"Defending"',
        '"Unable"',
    ]:
        assert token in source
    assert 'private _busyName = "Busy" + str _group;' in source


def test_diagnostics_correlate_clash_recovery_anchor_and_recon_state():
    source = diag()
    for token in [
        '"ITW_CLASH_Managed"',
        '"ITW_CLASH_AssignedObjective"',
        "ITW_CLASH_AnchorGroups",
        '"ITW_CLASH_Withdrawing"',
        '"ITW_CLASH_GroundMEDEVAC_State"',
        '"ITW_CLASH_CASEVAC_State"',
        '"ITW_CLASH_ReconPhase0Active"',
        '"ITW_CLASH_ReconPhase0Mode"',
        '"ITW_CLASH_ReconSOFFamily"',
        '"ITW_CLASH_ReconSOFLatched"',
    ]:
        assert token in source


def test_diagnostics_capture_waypoint_and_manual_dump_surfaces():
    source = diag()
    for token in [
        "currentWaypoint _group",
        "waypointType _wp",
        "waypointBehaviour _wp",
        "waypointCombatMode _wp",
        "waypointSpeed _wp",
        "waypointPosition _wp",
        "ITW_CLASH_Diag_fnc_DumpGroup",
        "ITW_CLASH_Diag_fnc_DumpAll",
        '"manual-hq"',
        '"manual-group"',
    ]:
        assert token in source


def test_every_hal_cycle_is_logged_for_both_commanders():
    # Commander B had no HQ logging, and HAL's delay between cycles grows with
    # army size; the measured gap is what bounds how fast a commander reacts.
    source = diag()
    cycle = source[source.index("ITW_CLASH_Diag_fnc_HQCycle = {"):]
    cycle = cycle[:cycle.index("\n};")]
    assert '"RydHQ_Cyclecount"' in cycle
    assert '"RydHQ_myDelay"' in cycle
    assert 'count (_hq getVariable ["RydHQ_Friends",[]])' in cycle
    assert "round (time - _lastAt)" in cycle
    assert '"hq-cycle"' in cycle
    assert '} forEach ["ITW_CLASH_HALHQ","ITW_CLASH_BLUFORHQ"];' in source


def test_groups_are_checked_against_their_own_commander():
    # 2026-09-26 run: all 47 WEST groups logged RydHQ_Friends false because
    # exitWith inside `then` fell through to ITW_CLASH_HALHQ (the GUER commander).
    source = diag()
    assert "ITW_CLASH_CombatDiagnosticsVersion = 4;" in source
    hq = source[source.index("ITW_CLASH_Diag_fnc_HQ = {"):]
    hq = hq[:hq.index("\n};")]
    assert "exitWith" not in hq
    assert '} forEach ["ITW_CLASH_BLUFORHQ","ITW_CLASH_HALHQ"];' in hq
    assert "side _group == side _candidate" in hq
    assert hq.rstrip().endswith("_hq")


def test_boot_banner_exposes_forensic_scope():
    source = diag()
    assert "observerOnly=true" in source
    assert "detectionIndependent=true" in source
    assert "contactRadius=%3" in source
    assert "pairCooldown=%4" in source
    assert "hqInterval=%5" in source
