"""COLOSSUS issues the ATTACK/DEFEND order.

What this replaced, in ITW_CLASH_CommanderParity.sqf, was:

    if ((count _held) < (count _active)) then {"ATTACK"} else {"DEFEND"}

which never looked at the enemy. RydHQ_Order is not a decision HAL makes -
HQSitRep copies it from a mission global every cycle - so in run4 both active
objectives read "held", that ternary said DEFEND, and HAL obeyed it for 88
consecutive assessments while COLOSSUS logged objective 2 VULNERABLE with
force available.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


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


def code_only(body: str) -> str:
    body = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)
    return re.sub(r"//[^\n]*", " ", body)


def colossus() -> str:
    return text("ITW_CLASH_Colossus.sqf")


# --- the order decision ---------------------------------------------------

def test_consolidate_never_attacks():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_OrderFor"))
    assert '_posture isEqualTo "CONSOLIDATE") exitWith {"DEFEND"}' in body


def test_pushing_requires_the_force_to_do_it():
    # Attacking while short is what feeds groups in one at a time. This is
    # meant to stop the trickle, not cause it.
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_OrderFor"))
    assert '"feasible"' in body
    assert 'exitWith {"ATTACK"}' in body
    assert body.rstrip().rstrip("}").rstrip().endswith('"DEFEND"')


def test_no_plan_means_no_opinion():
    # An empty plan must leave the order alone rather than asserting DEFEND,
    # so a commander with no picture keeps whatever it had.
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_OrderFor"))
    assert 'if (count _plan == 0) exitWith {""}' in body
    commit = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Commit"))
    assert 'if (_order isEqualTo "") exitWith {false}' in commit


def test_the_decision_no_longer_counts_flags():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_OrderFor"))
    assert "_held" not in body and "_active" not in body


# --- writing it where HAL reads it ---------------------------------------

def test_commander_a_reads_the_unlettered_global():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_OrderGlobal"))
    assert 'if (_sign isEqualTo "A") exitWith {"RydHQ_Order"}' in body
    assert '"RydHQ" + _sign + "_Order"' in body


def test_the_global_is_written_not_just_the_group_variable():
    # HQSitRep copies the global over the group variable every cycle, so a
    # group-only write is undone on the next pass.
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Commit"))
    assert "ITW_CLASH_Colossus_fnc_OrderGlobal" in body
    assert "missionNamespace setVariable [_global,_order]" in body
    assert "publicVariable _global" in body
    assert '_hq setVariable ["RydHQ_Order",_order]' in body


def test_hal_itself_is_not_edited():
    # The order global is HAL's own sanctioned interface; the mod stays stock.
    assert not (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "HQSitRep.sqf").read_text(
        encoding="utf-8", errors="ignore"
    ).count("ITW_CLASH")


# --- stability ------------------------------------------------------------

def test_the_order_has_a_dwell():
    source = colossus()
    dwell = int(re.search(r'"ITW_CLASH_ColossusOrderDwell",(\d+)', source).group(1))
    poll = int(re.search(r'"ITW_CLASH_ColossusPoll",(\d+)', source).group(1))
    # Must outlast a single assessment or feasibility flapping leaks through.
    assert dwell > poll, (dwell, poll)
    body = code_only(function_body(source, "ITW_CLASH_Colossus_fnc_Commit"))
    assert "ITW_CLASH_ColossusOrderDwell" in body
    assert '"ITW_CLASH_ColossusOrderAt"' in body


def test_an_unchanged_order_is_not_rewritten():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Commit"))
    assert "if (_order isEqualTo _current) exitWith {false}" in body


def test_the_dwell_cannot_block_the_first_order():
    # A commander that has never been ordered must not wait out the dwell.
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Commit"))
    assert '"ITW_CLASH_ColossusOrderAt",-1e10' in body


# --- the kill switch ------------------------------------------------------

def test_advisory_mode_changes_nothing():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Commit"))
    advisory = body[body.index("ITW_CLASH_ColossusAdvisoryOnly"):]
    gated = advisory[:advisory.index("if (_order isEqualTo _current)")]
    assert "setVariable" not in gated.replace('_hq getVariable', ''), gated
    assert "would-order" in gated


def test_the_layer_is_live_by_default():
    assert '"ITW_CLASH_ColossusAdvisoryOnly",false]' in colossus()


def test_both_sides_are_assessed():
    source = colossus()
    assert "ITW_PlayerSide" in source and "ITW_EnemySide" in source
    assert "ITW_CLASH_Colossus_fnc_Commit" in function_body(
        source, "ITW_CLASH_Colossus_fnc_Assess"
    )


# --- the parity layer stands down ----------------------------------------

def test_the_old_ternary_yields_when_colossus_is_live():
    body = code_only(function_body(text("ITW_CLASH_CommanderParity.sqf"),
                                   "ITW_CLASH_CommanderParity_Anchor_fnc_ApplyCommanderDoctrine"))
    assert "_colossusOwns" in body
    assert "ITW_CLASH_ColossusAdvisoryOnly" in body
    # Readiness matters: advisory=false before the layer boots must not leave
    # the order unowned by anyone.
    assert "ITW_CLASH_ColossusReady" in body
    assert "if (!_colossusOwns) then {" in body


def test_the_ternary_still_exists_as_the_fallback():
    body = code_only(function_body(text("ITW_CLASH_CommanderParity.sqf"),
                                   "ITW_CLASH_CommanderParity_Anchor_fnc_ApplyCommanderDoctrine"))
    assert "(count _held) < (count _active)" in body
    assert "RydHQB_Order = _order" in body


def test_the_rest_of_the_doctrine_still_applies_either_way():
    # Only the order moved; Berserk, AttackAlways, IdleDef and the reserve
    # ratio must still be set on every call regardless of who owns the order.
    body = code_only(function_body(text("ITW_CLASH_CommanderParity.sqf"),
                                   "ITW_CLASH_CommanderParity_Anchor_fnc_ApplyCommanderDoctrine"))
    tail = body[body.index("if (!_colossusOwns) then {"):]
    for key in ("RydHQ_Berserk", "RydHQ_AttackAlways", "RydHQ_IdleDef", "RydHQ_CRDefRes"):
        assert key in tail, key
