import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def colossus() -> str:
    return text("ITW_CLASH_Colossus.sqf")


def code_only(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def function_body(source: str, name: str) -> str:
    start = source.index(f"{name} = {{")
    depth = 0
    i = source.index("{", start)
    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1
    raise AssertionError(f"unterminated {name}")


def test_v0_issues_no_orders_at_all():
    # The kill criterion, as a test: if COLOSSUS ever commands a group or
    # duplicates the dispatcher, it has failed.
    source = code_only(colossus())
    for forbidden in [
        "doMove", "commandMove", "addWaypoint", "deleteWaypoint",
        "RYD_Dispatcher", "RYD_WPadd", "setBehaviour", "setCombatMode",
        "ITW_CLASH_ETB_fnc_Authorize", "createVehicle", "deleteVehicle",
        "HAL_GoSFAttack", "HAL_SCargo",
    ]:
        assert forbidden not in source, forbidden


# v3 issues the ATTACK/DEFEND order, so RydHQ_Order is now a legitimate write.
# Nothing else under RydHQ_ is: the pools are group membership, and writing one
# would mean COLOSSUS was taking or tasking groups rather than advising.
COLOSSUS_PERMITTED_HAL_WRITES = {"RydHQ_Order"}


def test_it_never_writes_a_hal_pool():
    source = code_only(colossus())
    for write in re.findall(r'setVariable\s*\[\s*"(RydHQ_\w+)"', source):
        if write in COLOSSUS_PERMITTED_HAL_WRITES:
            continue
        raise AssertionError(f"writes HAL pool {write}")
    assert 'getVariable ["RydHQ_KnEnemies' in source
    assert 'getVariable ["RydHQ_Friends' in source


def test_the_picture_is_built_from_what_the_commander_knows():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_EnemyStrength")
    # Not the enemy's real order of battle: HAL's knowledge only.
    assert 'RydHQ_KnEnemies' in body
    for omniscient in ["allUnits", "allGroups", "vehicles"]:
        assert omniscient not in body, omniscient


def test_strength_is_priced_from_the_vehicle():
    source = colossus()
    body = function_body(source, "ITW_CLASH_Colossus_fnc_Worth")
    assert "ITW_CLASH_AirPicture_fnc_IsArmoredThreat" in body
    assert 'isKindOf "StaticWeapon"' in body
    assert "ITW_CLASH_ColossusWeightArmor" in body
    assert 'ITW_CLASH_ColossusWeightInfantry",1' in source
    assert 'ITW_CLASH_ColossusWeightArmor",3' in source
    assert 'ITW_CLASH_ColossusWeightStatic",0.5' in source


def test_available_force_excludes_what_the_commander_would_never_send():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_FriendlyStrength")
    for pool in [
        "RydHQ_Exhausted", "RydHQ_SupportG", "RydHQ_SpecForG",
        "RydHQ_ArtG", "RydHQ_NavalG", "RydHQ_CargoOnly", "RydHQ_StaticG",
    ]:
        assert pool in body, pool
    # Busy groups are not available either.
    assert 'getVariable ["Busy" + str _group,false]' in body


def test_a_push_is_planned_at_a_ratio_not_at_parity():
    source = colossus()
    body = function_body(source, "ITW_CLASH_Colossus_fnc_Picture")
    assert "ITW_CLASH_ColossusPushRatio" in body
    assert 'ITW_CLASH_ColossusPushRatio",2' in source
    assert '["wanted",_wanted]' in body
    assert '["sufficient",_available >= _wanted]' in body


def test_the_recommendation_prefers_a_push_it_can_actually_mass_for():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_Recommend")
    # An objective it cannot mass against is pushed down the ranking, not up.
    assert 'if !(_entry get "sufficient") then {_score = _score + 1000};' in body
    assert '"would-push"' in body


def test_verdicts_are_thresholds_on_a_ratio():
    source = colossus()
    body = function_body(source, "ITW_CLASH_Colossus_fnc_Verdict")
    for verdict in ["VULNERABLE", "CONTESTED", "HELD", "OPEN", "EMPTY"]:
        assert f'"{verdict}"' in body, verdict
    assert 'ITW_CLASH_ColossusVulnerable",2' in source
    assert 'ITW_CLASH_ColossusContested",0.8' in source


def test_the_v1_levers_are_recorded_and_still_true():
    source = colossus()
    # The capture pool subtracts Garrison but NOT NoAttack, so Garrison is the
    # hold lever. If HAL changes that, this test fails before v1 is built on it.
    orders = (HAL / "HAL" / "HQOrders.sqf").read_text(encoding="utf-8", errors="replace")
    capture = orders[orders.index("_forCapt = "):orders.index("_forCapt = [_forCapt] call RYD_SizeOrd;")]
    assert "RydHQ_Garrison" in capture
    assert "RydHQ_NoAttack" not in capture
    # And the wide-attack pool subtracts both.
    wide = orders[orders.index("_LMCU = "):orders.index("_WAAv = [];")]
    assert "RydHQ_NoAttack" in wide
    assert "RydHQ_Garrison" in wide
    # Recorded in the file so v1 does not re-derive it.
    assert "RydHQ_Garrison is the lever, NOT RydHQ_NoAttack" in source
    assert "HQOrders.sqf:778" in source
    assert "HQOrders.sqf:1038" in source
    # Garrison digs a group in where it stands, which is what staging needs.
    garrison = (HAL / "HAL" / "Garrison.sqf").read_text(encoding="utf-8", errors="replace")
    assert "_pos = getPosATL (vehicle (leader _unitG));" in garrison


def test_it_publishes_a_picture_for_something_else_to_read():
    source = colossus()
    assert "ITW_CLASH_Colossus_fnc_Read" in source
    assert "ITW_CLASH_ColossusPictures" in source


def test_it_loads_and_warns_when_it_cannot():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_Colossus.sqf"' in init
    assert "colossus-missing-or-prereq-failed" in init


# ------------------------------------------------- v2: consolidate posture

def test_it_orders_but_never_moves_a_group():
    """v3 names the order; it still never touches a group.

    This is the line that keeps COLOSSUS a planning layer. It may tell a
    commander to attack, which HAL then carries out with its own dispatchers,
    group selection and Busy locks. The moment it moves a group itself there
    are two commanders issuing orders against the same units and neither run
    is diagnosable.
    """
    source = code_only(colossus())
    for forbidden in [
        "doMove", "commandMove", "addWaypoint", "deleteWaypoint",
        "RYD_Dispatcher", "setBehaviour", "setCombatMode", "HAL_GoSFAttack",
    ]:
        assert forbidden not in source, forbidden
    for write in re.findall(r'setVariable\s*\[\s*"(\w+)"', source):
        if not write.startswith("RydHQ_"):
            continue
        assert write in COLOSSUS_PERMITTED_HAL_WRITES, write


def test_the_ratio_is_measured_across_the_theatre_not_an_objective():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_Theatre")
    # No radius filter: that is what makes it a theatre number.
    assert "ITW_CLASH_ColossusObjectiveRadius" not in body
    assert "ITW_CLASH_ColossusCommittedRadius" not in body
    assert "RydHQ_KnEnemies" in body
    assert "RydHQ_Friends" in body
    # Counted once per vehicle, or an infantry squad in a truck inflates it.
    assert "if (_veh in _counted) then {continue};" in body


def test_the_same_groups_are_excluded_as_from_a_push():
    push = function_body(colossus(), "ITW_CLASH_Colossus_fnc_FriendlyStrength")
    theatre = function_body(colossus(), "ITW_CLASH_Colossus_fnc_Theatre")
    for pool in [
        "RydHQ_Exhausted", "RydHQ_SupportG", "RydHQ_SpecForG",
        "RydHQ_ArtG", "RydHQ_NavalG", "RydHQ_CargoOnly", "RydHQ_StaticG",
    ]:
        assert pool in push and pool in theatre, pool


def test_the_posture_has_hysteresis():
    source = colossus()
    body = function_body(source, "ITW_CLASH_Colossus_fnc_Posture")
    assert "ITW_CLASH_ColossusConsolidateAt" in body
    assert "ITW_CLASH_ColossusReleaseAt" in body
    assert 'ITW_CLASH_ColossusConsolidateAt",1.5' in source
    assert 'ITW_CLASH_ColossusReleaseAt",1.1' in source
    # Entering is harder than leaving, or it would flap on the threshold.
    enter = float(re.search(r'ITW_CLASH_ColossusConsolidateAt",([\d.]+)', source).group(1))
    leave = float(re.search(r'ITW_CLASH_ColossusReleaseAt",([\d.]+)', source).group(1))
    assert enter > leave, (enter, leave)
    assert 'getVariable ["ITW_CLASH_ColossusPosture","PUSH"]' in body


def test_knowing_nothing_is_not_a_reason_to_consolidate():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_Posture")
    assert 'if (_enemy <= 0 || {_friendly <= 0}) exitWith {["PUSH",0]};' in body


def test_it_masses_where_it_is_already_strongest():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_RallyPoint")
    # Descending on committed: thicken a position rather than start a new one.
    assert '{-(_x get "committed")},"ASCEND"' in body


def test_the_recommendation_branches_on_posture():
    source = colossus()
    body = function_body(source, "ITW_CLASH_Colossus_fnc_Recommend")
    assert '["_posture","PUSH"]' in body
    assert 'if (_posture isEqualTo "CONSOLIDATE") exitWith {' in body
    assert '"would-consolidate"' in body
    assert '"would-push"' in body
    assert '["posture","CONSOLIDATE"]' in body
    assert '["posture","PUSH"]' in body


def test_a_posture_change_is_reported_once():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_Assess")
    assert '_hq setVariable ["ITW_CLASH_ColossusPosture",_posture]' in body
    assert "if !(_posture isEqualTo _was) then {" in body
    assert '"posture"' in body


def test_the_version_and_boot_line_moved():
    source = colossus()
    assert "ITW_CLASH_ColossusVersion = 3;" in source
    assert "postures=PUSH,CONSOLIDATE" in source
    # v3 reports which it is doing rather than claiming it issues nothing, and
    # still says "none-advisory" when the kill switch is on.
    assert "ordersIssued=%12" in source
    assert '"none-advisory"' in source
    assert '"attack-defend"' in source
