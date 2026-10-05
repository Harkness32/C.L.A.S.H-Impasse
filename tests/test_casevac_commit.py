"""A committed CASEVAC does not turn back because the enemy is nearby.

Measured, 6:16-6:17:

    casevac-dispatched    G41  B_Heli_Light_01_F  -> LZ [5602,14790]
    casevac-inbound-route 3400m out
    casevac-lz-pad-landat accepted
    casevac-smoke         649m out
    casevac-lz-pad-locked 594m out
    casevac-abort-contact [244,450]
    casevac-failed        "contact-reestablished"

A Littlebird flew 3400m, reached 594m from the patients, and turned around one
second after the pad locked because an enemy was 244m from the casualty group.

The abort is sound BEFORE commitment - nothing is lost but a sortie. Applied
flat across the whole inbound leg it is close to guaranteed to fire, because
fnc_Eligible only serves groups that are WITHDRAWING, and a group under GTFO is
by definition breaking contact. Enemies near it is their normal condition.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def casevac() -> str:
    return (MISSION / "ITW_CLASH_CASEVAC.sqf").read_text(encoding="utf-8", errors="replace")


def code_only(body: str) -> str:
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return re.sub(r"//[^\n]*", "", body)


def test_the_two_thresholds_exist_and_differ():
    source = casevac()
    assert "ITW_CLASH_CASEVAC_InboundAbortClearance = 450;" in source
    assert "ITW_CLASH_CASEVAC_CommitDistance" in source
    assert "ITW_CLASH_CASEVAC_CommittedAbortClearance" in source


def test_commitment_is_measured_to_the_lz_not_the_casualties():
    """The LZ is what the aircraft has to put wheels on."""
    source = code_only(casevac())
    assert "(_heli distance2D _lz) <= ITW_CLASH_CASEVAC_CommitDistance" in source


def test_a_committed_evac_uses_the_tighter_clearance():
    source = code_only(casevac())
    block = source[source.index("private _committed ="):]
    block = block[:block.index("if (_contactDistance < _clearance)")]
    assert "ITW_CLASH_CASEVAC_CommittedAbortClearance" in block
    assert "ITW_CLASH_CASEVAC_InboundAbortClearance" in block


def test_the_measured_case_would_no_longer_abort():
    """244m contact at 594m from the LZ: committed (594 <= 800), and 244 is
    outside the committed clearance (150), so the bird lands."""
    source = casevac()
    commit = int(re.search(r'"ITW_CLASH_CASEVAC_CommitDistance",(\d+)', source).group(1))
    tight = int(re.search(r'"ITW_CLASH_CASEVAC_CommittedAbortClearance",(\d+)', source).group(1))
    assert 594 <= commit, commit
    assert 244 >= tight, tight


def test_an_overrun_lz_still_aborts():
    """Committed is not suicidal: an enemy close enough to contest the pad is
    still a reason to leave, because landing there loses the airframe as well
    as the squad."""
    source = casevac()
    tight = int(re.search(r'"ITW_CLASH_CASEVAC_CommittedAbortClearance",(\d+)', source).group(1))
    assert tight > 0, "a committed evac must still have an abort"
    assert tight < 450


def test_the_uncommitted_leg_keeps_the_original_behaviour():
    source = casevac()
    assert "ITW_CLASH_CASEVAC_InboundAbortClearance = 450;" in source


def test_the_abort_line_says_which_regime_it_was_in():
    """So the next RPT answers this without a code read."""
    source = code_only(casevac())
    block = source[source.index('["abort-contact",['):]
    block = block[:block.index("]] call")]
    assert '"committed"' in block
    assert '"inbound"' in block
    assert "_heli distance2D _lz" in block


def test_casevac_only_ever_serves_a_withdrawing_group():
    """The premise of the whole fix: if this ever stops being true, a flat
    contact abort becomes reasonable again."""
    source = code_only(casevac())
    assert 'if !(_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith' in source
