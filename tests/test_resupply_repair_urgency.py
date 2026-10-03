import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def resupply() -> str:
    return text("ITW_CLASH_Resupply.sqf")


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


def test_repair_is_more_urgent_than_ammo():
    source = resupply()
    assert '["ITW_CLASH_ResupplyRepairPatience",30]' in source
    assert '["ITW_CLASH_ResupplyImmobilePatience",0]' in source
    patience = int(re.search(r'\["ITW_CLASH_ResupplyPatience",(\d+)\]', source).group(1))
    repair = int(re.search(r'\["ITW_CLASH_ResupplyRepairPatience",(\d+)\]', source).group(1))
    immobile = int(re.search(r'\["ITW_CLASH_ResupplyImmobilePatience",(\d+)\]', source).group(1))
    assert immobile <= repair < patience, (immobile, repair, patience)


def test_the_shortest_need_decides():
    # A group that is both dry and broken is taken on the urgent one.
    body = function_body(resupply(), "ITW_CLASH_Resupply_fnc_Patience")
    assert '"REPAIR" in _needs' in body
    assert "min ITW_CLASH_ResupplyRepairPatience" in body
    assert "min ITW_CLASH_ResupplyImmobilePatience" in body
    assert "_patience max 0" in body


def test_immobile_shortens_it_further():
    body = function_body(resupply(), "ITW_CLASH_Resupply_fnc_Patience")
    assert "!canMove _x" in body
    assert "fuel _x <= 0" in body


def test_detection_asks_for_the_patience_rather_than_assuming_it():
    body = function_body(resupply(), "ITW_CLASH_Resupply_fnc_Detect")
    assert "[_group,_needs] call ITW_CLASH_Resupply_fnc_Patience" in body
    assert "time - (_seen#0) < ITW_CLASH_ResupplyPatience" not in body


def test_a_native_delivery_still_restarts_the_clock():
    # The shorter window must not stop native HAL getting its chance.
    body = function_body(resupply(), "ITW_CLASH_Resupply_fnc_Detect")
    assert "ITW_CLASH_Resupply_fnc_InFlight" in body
    assert 'setVariable ["ITW_CLASH_ResupplyNeedSince",[time,time]]' in body


def test_a_group_that_cannot_move_still_freezes_rather_than_withdrawing():
    # Already the behaviour; pinned so the shorter patience cannot change it.
    body = function_body(resupply(), "ITW_CLASH_Resupply_fnc_StepResolve")
    assert "fuel _x <= 0 || {!canMove _x}" in body
    assert '_claim set ["rallySource","immobile"]' in body
    assert '_claim set ["inPlace",true]' in body


def test_taking_the_group_still_stops_its_tasking():
    body = function_body(resupply(), "ITW_CLASH_Resupply_fnc_Claim")
    assert '_group setVariable ["Break",true]' in body
    assert '_group setVariable ["Busy" + _var,true]' in body
    assert "ITW_CLASH_Resupply_fnc_ClearHALRoles" in body


def test_the_windows_are_reported_at_boot():
    source = resupply()
    assert "repairPatience=%11" in source
    assert "immobilePatience=%12" in source
    assert "ITW_CLASH_ResupplyRepairPatience,\n        ITW_CLASH_ResupplyImmobilePatience" in source
