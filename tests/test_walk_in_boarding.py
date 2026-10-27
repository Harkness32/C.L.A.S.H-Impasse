"""Able men walk aboard (2026-10-27, Hark).

"moved closer and they magically teleported in" / "lets have them physically
walk in and board, like medevac". A downed crew, a squad evac and a requested
lift were put straight into their seats with moveInCargo. They now board the
way AI CASEVAC boards its survivors: a cargo seat each and orderGetIn, repeated
until all are inside. A severe casualty keeps the assisted load.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code_text(text: str) -> str:
    return re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


def body_of(source: str, name: str) -> str:
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
    raise AssertionError(name)


def code(name: str) -> str:
    return code_text((MISSION / name).read_text(encoding="utf-8"))


DISPATCH = code("ITW_CLASH_PlayerDemandDispatch.sqf")
BOARD = body_of(DISPATCH, "ITW_CLASH_PlayerDemand_fnc_BoardOnFoot")


def test_boarding_is_casevacs_seat_and_get_in_order():
    casevac = code("ITW_CLASH_CASEVAC.sqf")
    assert "_x assignAsCargo _heli;" in casevac
    assert "_survivors orderGetIn true;" in casevac
    assert "_x assignAsCargo _vehicle;" in BOARD
    assert "_outside orderGetIn true;" in BOARD
    assert "_outside allowGetIn true;" in BOARD
    # The order is repeated on an interval, and a man already given this seat
    # is not unassigned and reassigned every pass.
    assert '"boardOrderAt",time + ITW_CLASH_PlayerBoardOrderInterval' in BOARD
    assert "if !((assignedVehicle _x) isEqualTo _vehicle) then {" in BOARD


def test_a_man_who_cannot_find_the_door_is_put_in_only_at_the_door():
    close = BOARD.index("> ITW_CLASH_PlayerBoardCloseRadius")
    timeout = BOARD.index("time - _since < ITW_CLASH_PlayerBoardTimeout")
    put_in = BOARD.index("{_x moveInCargo _vehicle} forEach _outside;")
    assert close < timeout < put_in
    assert 'getVariable ["ITW_CLASH_PlayerBoardCloseRadius",20]' in DISPATCH
    assert 'getVariable ["ITW_CLASH_PlayerBoardTimeout",30]' in DISPATCH


def test_a_carrier_that_leaves_releases_the_men_still_outside():
    cancel = body_of(DISPATCH, "ITW_CLASH_PlayerDemand_fnc_CancelBoarding")
    assert "_outside orderGetIn false;" in cancel
    assert "unassignVehicle _x" in cancel
    assert '_job set ["boardCloseSince",-1];' in cancel


def test_every_able_bodied_pickup_walks_in():
    for name, function in [
        ("ITW_CLASH_CSAR.sqf", "ITW_CLASH_CSAR_fnc_StartExecution"),
        ("ITW_CLASH_PlayerSquadEvac.sqf", "ITW_CLASH_PlayerSquadEvac_fnc_Prepare"),
        ("ITW_CLASH_PlayerTaskRequestTransport.sqf", "ITW_CLASH_PlayerTaskRequestTransport_fnc_Pickup"),
    ]:
        body = body_of(code(name), function)
        assert "ITW_CLASH_PlayerDemand_fnc_BoardOnFoot" in body, name
        assert "ITW_CLASH_PlayerDemand_fnc_CancelBoarding" in body, name
        assert "moveInCargo" not in body, name


def test_a_severe_casualty_keeps_the_assisted_load():
    medevac = body_of(DISPATCH, "ITW_CLASH_PlayerDemand_fnc_StartMedevacExecution")
    assert "_x moveInCargo _vehicle;" in medevac
    assert "BoardOnFoot" not in medevac
