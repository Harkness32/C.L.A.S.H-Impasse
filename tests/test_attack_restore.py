import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def restore() -> str:
    return text("ITW_CLASH_AttackRestore.sqf")


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


def test_the_imbalance_this_answers_is_real():
    # Far more disables than restores, and neither restore covers medevac.
    disables = sum(
        len(re.findall(r"enableAttack false", p.read_text(encoding="utf-8", errors="replace")))
        for p in MISSION.glob("ITW_CLASH*.sqf")
        if p.name != "ITW_CLASH_AttackRestore.sqf"
    )
    enables = sum(
        len(re.findall(r"enableAttack true", p.read_text(encoding="utf-8", errors="replace")))
        for p in MISSION.glob("ITW_CLASH*.sqf")
        if p.name != "ITW_CLASH_AttackRestore.sqf"
    )
    assert disables > enables, (disables, enables)


def test_the_casualty_squad_is_what_gets_disarmed():
    # Both calls take the squad, not the service crew.
    casevac = text("ITW_CLASH_CASEVAC.sqf")
    assert "[_group,_lz] call ITW_CLASH_CASEVAC_fnc_OrderLZ;" in casevac
    assert "_group enableAttack false;" in function_body(
        casevac, "ITW_CLASH_CASEVAC_fnc_OrderLZ"
    )
    manager = text("ITW_CLASH_GroundMEDEVAC_Manager.sqf")
    assert "[_group,_rally] call ITW_CLASH_GroundMEDEVAC_fnc_OrderRally;" in manager
    assert "_group enableAttack false;" in function_body(
        text("ITW_CLASH_GroundMEDEVAC.sqf"), "ITW_CLASH_GroundMEDEVAC_fnc_OrderRally"
    )


def test_a_dedicated_service_crew_is_left_disarmed():
    body = function_body(restore(), "ITW_CLASH_AttackRestore_fnc_Owned")
    assert 'getVariable ["ITW_CLASH_CASEVAC",false]' in body
    assert 'getVariable ["ITW_CLASH_GroundMEDEVAC",false]' in body


def test_it_never_fights_hal_for_a_group_hal_is_using():
    # GoRest and GoDefRecon disable attack for the length of an order and
    # restore it themselves; restoring mid-rest would break that.
    body = function_body(restore(), "ITW_CLASH_AttackRestore_fnc_Owned")
    assert '"Busy" + _var' in body
    assert '"Resting" + _var' in body


def test_a_group_still_in_a_service_or_withdrawing_is_left_alone():
    body = function_body(restore(), "ITW_CLASH_AttackRestore_fnc_Owned")
    for marker in [
        "ITW_CLASH_CASEVAC_State",
        "ITW_CLASH_GroundMEDEVAC_State",
        "ITW_CLASH_Withdrawing",
        "ITW_CLASH_ResupplyClaimed",
    ]:
        assert marker in body, marker


def test_a_handover_in_progress_is_never_raced():
    source = restore()
    body = function_body(source, "ITW_CLASH_AttackRestore_fnc_Sweep")
    assert 'setVariable ["ITW_CLASH_AttackDisabledSince",time]' in body
    assert "(time - _since) < ITW_CLASH_AttackRestoreGrace" in body
    assert 'ITW_CLASH_AttackRestoreGrace",30' in source


def test_players_are_never_touched():
    body = function_body(restore(), "ITW_CLASH_AttackRestore_fnc_Sweep")
    assert "findIf {isPlayer _x}) >= 0) then {continue}" in body


def test_it_restores_the_units_as_well_as_the_group():
    # The diagnostic reported unit-attack-disabled alongside the group flag.
    body = function_body(restore(), "ITW_CLASH_AttackRestore_fnc_Sweep")
    assert "_group enableAttack true;" in body
    assert "forEach units _group" in body


def test_the_clock_clears_when_a_group_recovers():
    body = function_body(restore(), "ITW_CLASH_AttackRestore_fnc_Sweep")
    assert body.count('setVariable ["ITW_CLASH_AttackDisabledSince",nil]') >= 3


def test_it_loads_and_warns_when_it_cannot():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_AttackRestore.sqf"' in init
    assert "attack-restore-missing" in init
    assert '["ITW_CLASH_AttackRestore","attack restore"' in text("ITW_CLASH_DebugPreflight.sqf")


def test_no_exit_with_inside_a_then_block():
    source = re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", restore(), flags=re.S))
    for match in re.finditer(r"then\s*\{", source):
        segment = source[match.end():]
        depth, i = 1, 0
        while i < len(segment) and depth > 0:
            if segment[i] == "{":
                depth += 1
            elif segment[i] == "}":
                depth -= 1
            i += 1
        assert "exitWith" not in segment[:i]
