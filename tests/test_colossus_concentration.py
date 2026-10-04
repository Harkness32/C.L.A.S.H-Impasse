"""COLOSSUS makes a target appetising instead of commanding units.

Hark's concern, in his words: *"I'm afraid of having another state machine
poison units by adding a ton of move markers and fighting them."* So COLOSSUS
writes no waypoint, claims no group, and owns no global of its own. It supplies
an opinion that the existing candidate-list writers consult.

HAL does not score objectives. In SimpleMode - which C.L.A.S.H. sets at
ITW_CLASH.sqf - HQOrders.sqf:328 sorts the candidates by DISTANCE and
truncates to MaxSimpleObjs. So "attack this one" has exactly two honest
expressions: be in the set, and have no rivals in it. Reordering does nothing
because RYD_DistOrdD re-sorts.
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


# --- the thing Hark was afraid of ---------------------------------------

def test_colossus_still_moves_nothing():
    source = code_only(colossus())
    for forbidden in [
        "doMove", "commandMove", "addWaypoint", "deleteWaypoint", "setCurrentWaypoint",
        "RYD_Dispatcher", "setBehaviour", "setCombatMode", "doStop", "doFollow",
    ]:
        assert forbidden not in source, forbidden


def test_concentration_is_a_pure_opinion():
    """It returns a list; it does not write the globals it is advising about."""
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert "setVariable" not in body
    for owned_elsewhere in ("RydHQ_SimpleObjs", "RydHQB_SimpleObjs",
                            "RydHQ_MaxSimpleObjs", "RydHQB_MaxSimpleObjs"):
        assert owned_elsewhere not in body, owned_elsewhere


def test_each_candidate_global_still_has_exactly_one_writer():
    a = code_only(text("ITW_CLASH.sqf"))
    b = code_only(text("ITW_CLASH_DualHALCheckbook.sqf"))
    c = code_only(colossus())
    # Exactly one live writer per commander, plus one reset-to-empty in the
    # same file. COLOSSUS writes neither.
    assert "RydHQ_SimpleObjs =" not in c and "RydHQB_SimpleObjs =" not in c
    for src, var, live in ((a, "RydHQ_SimpleObjs", "+_offered"),
                           (b, "RydHQB_SimpleObjs", "+_offered")):
        writes = re.findall(rf"\b{var}\s*=\s*(\S+)", src)
        assert len(writes) == 2, (var, writes)
        assert sorted(writes) == sorted([live + ";", "[];"]), (var, writes)


# --- declining is the default -------------------------------------------

def test_no_opinion_passes_the_list_through_unchanged():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert "private _pass = [_mirrors,-1]" in body
    # Every early exit returns the pass-through, never a partial narrowing.
    for reason in ("isNull _hq", "ColossusConcentrate", "ColossusAdvisoryOnly"):
        assert reason in body, reason


def test_an_unobserved_objective_is_never_concentrated_on():
    """EMPTY means nobody looked, not undefended. Concentrating a whole side
    onto an unscouted objective is how an army gets fed into a surprise."""
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert "ITW_CLASH_AirPicture_fnc_Observed" in body
    assert "objective-unobserved" in body


def test_it_declines_when_short_of_force_or_consolidating():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert "short-of-force" in body
    assert "consolidating" in body
    assert '"CONSOLIDATE"' in body


def test_every_decline_is_logged():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert "concentrate-declined" in body
    assert "concentrate" in body


def test_an_objective_outside_this_commanders_list_declines():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert "objective-not-a-candidate" in body
    assert "ITW_CLASH_Colossus_fnc_ResolveMirror" in body


# --- resolving the objective to a mirror --------------------------------

def test_mirror_resolution_handles_both_commanders():
    """B's mirrors are CLASH objects carrying the index; A's are Impasse flags."""
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_ResolveMirror"))
    assert '"ITW_CLASH_ObjectiveIndex",-1' in body
    assert "ITW_Objectives" in body and "ITW_OBJ_FLAG" in body
    # A flag that is not in this commander's list is not a match.
    assert "_flag in _mirrors" in body


def test_mirror_resolution_is_read_only():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_ResolveMirror"))
    assert "setVariable" not in body


# --- the writers -------------------------------------------------------

def test_both_writers_consult_colossus_and_survive_its_absence():
    for name, hq in (("ITW_CLASH.sqf", "ITW_CLASH_HALHQ"),
                     ("ITW_CLASH_DualHALCheckbook.sqf", "ITW_CLASH_BLUFORHQ")):
        body = code_only(text(name))
        assert 'isNil "ITW_CLASH_Colossus_fnc_Concentrate"' in body, name
        assert f"[{hq},_offered] call ITW_CLASH_Colossus_fnc_Concentrate" in body, name


def test_a_declined_opinion_leaves_the_max_count_alone():
    # -1 must not be written as a count, or HAL pursues nothing.
    for name in ("ITW_CLASH.sqf", "ITW_CLASH_DualHALCheckbook.sqf"):
        body = code_only(text(name))
        assert re.search(r"if \(_(colossus)?[Mm]ax\w*\s*>\s*0\) then \{", body), name


def test_the_offered_list_is_what_reaches_hal():
    a = code_only(text("ITW_CLASH.sqf"))
    assert "RydHQ_SimpleObjs = +_offered" in a
    # And the group-variable mirrors agree with the global, so nothing downstream
    # reads a different candidate set than HAL's SitRep does.
    assert '"RydHQ_SimpleObjs",+_offered' in a
    assert '"RydHQ_Objectives",+_offered' in a
    b = code_only(text("ITW_CLASH_DualHALCheckbook.sqf"))
    assert "RydHQB_SimpleObjs = +_offered" in b


def test_taken_is_never_poisoned():
    """RydHQ_Taken is HAL's live record of what it owns - GoCapture and HQReset
    write it. Poisoning it to de-appetise an objective would corrupt that."""
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert "Taken" not in body


# --- plan plumbing -----------------------------------------------------

def test_the_plan_is_stored_per_side_with_its_posture():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Assess"))
    assert 'ITW_CLASH_ColossusPlans set [toUpperANSI str (side _hq),_plan]' in body
    # Concentrate reads posture off the plan, so Assess has to put it there.
    assert '_plan set ["posture",_posture]' in body


def test_version_and_boot_line_report_concentration():
    source = colossus()
    assert "ITW_CLASH_ColossusVersion = 4;" in source
    assert "concentrate=%14/%15" in source
    assert '"ITW_CLASH_ColossusConcentrateMax",1' in source


# --- holding what we took ------------------------------------------------

def test_concentration_waits_for_held_ground_to_be_anchored():
    """Hark: "how will we make sure it won't leave the other, newly captured,
    defenceless."

    Four things already prevent defenceless: HAL's defence reads RydHQ_Taken
    rather than the candidate list (HQOrdersDef.sqf:171), an anchored group is
    leashed to its position (HAC_fnc.sqf:1593), HQOrdersDef is not suppressed
    by an ATTACK order, and RydHQ_CRDefRes withholds a reserve.

    What concentration CAN do is starve the anchor refill, since the refill and
    the attack draw on the same free groups - leaving ground HAL routes
    defenders past but nothing actually holds. So the next objective waits
    until the last one is anchored.
    """
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert "ITW_CLASH_ColossusRequireAnchored" in body
    assert "ITW_CLASH_Colossus_fnc_HoldingUnanchored" in body
    assert "holding-unanchored" in body


def test_the_anchor_gate_runs_before_the_objective_is_chosen():
    # Declining for unanchored ground must not depend on which objective was
    # picked; it is a reason not to concentrate at all.
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate"))
    assert body.index("holding-unanchored") < body.index("fnc_ResolveMirror")


def test_it_reads_both_commanders_anchor_registries():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_HoldingUnanchored"))
    assert "ITW_CLASH_CommanderParity_AnchorGroups" in body
    assert "ITW_CLASH_AnchorGroups" in body
    assert "ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives" in body
    assert "ITW_CLASH_fnc_GetHeldObjectives" in body


def test_an_anchor_with_no_living_men_counts_as_unanchored():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_HoldingUnanchored"))
    assert "isNull _anchor" in body
    assert "{alive _x} count units _anchor) == 0" in body


def test_the_anchor_gate_fails_open():
    """A missing registry reader is not evidence of an undefended objective."""
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_HoldingUnanchored"))
    # Both unreadable paths exit with the empty list, i.e. nothing unanchored.
    assert body.count("exitWith {}") == 2
    assert 'isNil "ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives"' in body
    assert 'isNil "ITW_CLASH_fnc_GetHeldObjectives"' in body


def test_the_anchor_gate_is_read_only():
    body = code_only(function_body(colossus(), "ITW_CLASH_Colossus_fnc_HoldingUnanchored"))
    assert "setVariable" not in body


def test_the_relaxed_anchor_floor_is_what_makes_the_gate_releasable():
    """With a flat floor of 6 the gate could deadlock: nothing qualifies, so the
    objective stays unanchored and concentration never resumes. The relaxed
    floor means a thin team eventually qualifies and the gate clears."""
    patch = (MISSION / "ITW_CLASH_RuntimePatch.sqf").read_text(encoding="utf-8")
    assert "ITW_CLASH_fnc_AnchorFloorFor" in patch
    minimum = int(re.search(r'\["ITW_CLASH_AnchorFloorMinimum",(\d+)\]', patch).group(1))
    assert minimum < 6, minimum
