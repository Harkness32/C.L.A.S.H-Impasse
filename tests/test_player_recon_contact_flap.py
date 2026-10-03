import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def recon() -> str:
    return text("ITW_CLASH_PlayerTaskRequestRecon.sqf")


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


def test_one_absent_pass_is_not_a_lost_contact():
    source = recon()
    body = function_body(source, "ITW_CLASH_PlayerTaskRequestRecon_fnc_UpdateHistory")
    assert "ITW_CLASH_PlayerReconLostGrace" in body
    assert '_record set ["missingSince",time]' in body
    assert "(time - _missing) < ITW_CLASH_PlayerReconLostGrace" in body
    assert 'ITW_CLASH_PlayerReconLostGrace",20' in source


def test_the_grace_sits_between_a_rebuild_and_a_hal_cycle():
    source = recon()
    grace = int(re.search(r'ITW_CLASH_PlayerReconLostGrace",(\d+)', source).group(1))
    stale = int(re.search(r'ITW_CLASH_PlayerReconStaleSeconds",(\d+)', source).group(1))
    # Long enough to outlast a list rebuild, short enough that a contact still
    # matures into a task well inside a HAL cycle.
    assert 5 < grace < stale, (grace, stale)


def test_an_empty_knowledge_list_is_treated_as_a_rebuild():
    body = function_body(recon(), "ITW_CLASH_PlayerTaskRequestRecon_fnc_UpdateHistory")
    assert "if (_known isEqualTo []) exitWith {true};" in body
    # And the guard runs before the sweep that would condemn every contact.
    assert body.index("_known isEqualTo []") < body.index("contact-lost-by-hal")


def test_being_seen_again_clears_the_missing_clock():
    body = function_body(recon(), "ITW_CLASH_PlayerTaskRequestRecon_fnc_RecordKnown")
    assert '_record set ["missingSince",-1]' in body
    assert '_record set ["lostAt",-1]' in body


def test_a_flap_can_no_longer_reset_the_staleness_clock():
    # lostAt is what gates a contact becoming a player recon task, and only
    # after StaleSeconds. It is now only ever set after the grace has passed,
    # so a two second flap never sets it and never has it reset.
    body = function_body(recon(), "ITW_CLASH_PlayerTaskRequestRecon_fnc_UpdateHistory")
    grace = body.index("ITW_CLASH_PlayerReconLostGrace")
    assigned = body.index('_record set ["lostAt",time]')
    assert grace < assigned


def test_the_loss_line_says_how_long_it_was_absent():
    body = function_body(recon(), "ITW_CLASH_PlayerTaskRequestRecon_fnc_UpdateHistory")
    assert "round (time - _missing)" in body
