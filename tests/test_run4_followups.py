"""The three diagnosed defects from run4, plus the stranded-group correction.

run4 showed objective 3 VACANT for 24 straight minutes, hq-state describing
only one of two commanders, and a road query failing at 2.2km. All three are
observation or arithmetic faults rather than doctrine: none of them required a
decision about how the AI should fight.
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


# --- anchor starvation -----------------------------------------------------

def test_the_anchor_floor_relaxes_while_a_refill_is_pending():
    body = code_only(function_body(text("ITW_CLASH_RuntimePatch.sqf"),
                                   "ITW_CLASH_fnc_AnchorFloorFor"))
    # Only relaxes against a pending refill: a healthy objective still wants six.
    assert '"pending"' in body
    assert "ITW_CLASH_AnchorFloorRelaxInterval" in body
    assert "ITW_CLASH_AnchorFloorMinimum" in body


def test_the_relaxed_floor_has_a_hard_bottom():
    source = text("ITW_CLASH_RuntimePatch.sqf")
    minimum = int(re.search(r'\["ITW_CLASH_AnchorFloorMinimum",(\d+)\]', source).group(1))
    full = int(re.search(r"ITW_CLASH_MinAnchorSoldiers = (\d+);",
                         text("ITW_CLASH.sqf")).group(1))
    assert 0 < minimum < full, (minimum, full)
    body = code_only(function_body(source, "ITW_CLASH_fnc_AnchorFloorFor"))
    assert "max (ITW_CLASH_AnchorFloorMinimum min _floor)" in body


def test_selection_uses_the_effective_floor_not_the_constant():
    body = code_only(function_body(text("ITW_CLASH_RuntimePatch.sqf"),
                                   "ITW_CLASH_fnc_SelectAnchorGroup"))
    assert "ITW_CLASH_fnc_AnchorFloorFor" in body
    assert "_conscious < _floor" in body
    assert "_conscious < ITW_CLASH_MinAnchorSoldiers) exitWith" not in body


def test_a_relaxed_anchor_is_stamped_with_what_it_was_accepted_at():
    # Without the stamp the audit demotes it next poll and the slot flaps.
    body = code_only(function_body(text("ITW_CLASH_RuntimePatch.sqf"),
                                   "ITW_CLASH_fnc_SelectAnchorGroup"))
    assert '"ITW_CLASH_AnchorAcceptedFloor",_floor' in body


def test_the_hold_floor_reads_the_stamp_and_cannot_exceed_the_minimum():
    body = code_only(function_body(text("ITW_CLASH.sqf"),
                                   "ITW_CLASH_fnc_AnchorHoldFloor"))
    assert "ITW_CLASH_AnchorAcceptedFloor" in body
    # A stamp must never raise the bar above the standing minimum.
    assert "min ITW_CLASH_MinAnchorSoldiers" in body


def test_demotion_judges_by_the_accepted_floor():
    body = code_only(function_body(text("ITW_CLASH_RuntimePatch.sqf"),
                                   "ITW_CLASH_fnc_AuditAnchors"))
    assert "ITW_CLASH_fnc_AnchorHoldFloor" in body
    assert "_conscious >= _holdFloor" in body


def test_coverage_state_judges_by_the_accepted_floor():
    # A 4-man anchor accepted at 4 must be able to read COVERED, or the audit
    # keeps requesting a refill for ground that is actually held.
    body = code_only(function_body(text("ITW_CLASH.sqf"),
                                   "ITW_CLASH_fnc_AuditAnchors"))
    assert "_anchorInside >= _holdFloor" in body
    assert "_anchorAlive < _holdFloor" in body


# --- hq-state blindness ----------------------------------------------------

def test_hq_snapshot_takes_a_commander():
    body = code_only(function_body(text("ITW_CLASH_CombatDiagnostics.sqf"),
                                   "ITW_CLASH_Diag_fnc_HQSnapshot"))
    assert 'params [["_hq",grpNull]]' in body
    # Still resolves one itself, so the manual snapshot call keeps working.
    assert "ITW_CLASH_Diag_fnc_HQ" in body


def test_hq_state_samples_both_commanders():
    source = text("ITW_CLASH_CombatDiagnostics.sqf")
    line = source.index('"hq-state"')
    window = source[line - 400:line + 400]
    assert "ITW_CLASH_HALHQ" in window and "ITW_CLASH_BLUFORHQ" in window
    assert "[_hq] call ITW_CLASH_Diag_fnc_HQSnapshot" in window


def test_the_snapshot_is_still_read_only():
    body = code_only(function_body(text("ITW_CLASH_CombatDiagnostics.sqf"),
                                   "ITW_CLASH_Diag_fnc_HQSnapshot"))
    assert "setVariable" not in body


# --- road distance budget --------------------------------------------------

def test_the_node_budget_scales_with_the_gap():
    source = text("ITW_CLASH_RoadDistance.sqf")
    body = code_only(function_body(source, "ITW_CLASH_RoadDistance_fnc_NodeBudget"))
    assert "distance2D" in body
    assert "ITW_CLASH_RoadDistanceNodesPerMetre" in body
    # The old fixed value survives as a floor for short queries.
    assert "max ITW_CLASH_RoadDistanceMaxNodes" in body
    assert "min ITW_CLASH_RoadDistanceMaxNodesCap" in body


def test_the_search_spends_the_scaled_budget():
    body = code_only(function_body(text("ITW_CLASH_RoadDistance.sqf"),
                                   "ITW_CLASH_RoadDistance_fnc_Calculate"))
    assert "ITW_CLASH_RoadDistance_fnc_NodeBudget" in body
    assert "_nodesExpanded < _budget" in body
    assert "_nodesExpanded < ITW_CLASH_RoadDistanceMaxNodes" not in body


def test_the_budget_now_covers_the_query_that_failed():
    # run4: 2220m between truck and MLRS, exhausted at exactly 300 nodes.
    source = text("ITW_CLASH_RoadDistance.sqf")
    per_metre = float(re.search(r'"ITW_CLASH_RoadDistanceNodesPerMetre",([\d.]+)', source).group(1))
    floor = int(re.search(r'"ITW_CLASH_RoadDistanceMaxNodes",(\d+)', source).group(1))
    cap = int(re.search(r'"ITW_CLASH_RoadDistanceMaxNodesCap",(\d+)', source).group(1))
    budget = min(max(2220 * per_metre, floor), cap)
    assert budget > 300, budget


def test_the_budget_covers_the_range_the_resupply_caller_asks_about():
    # ITW_CLASH_ResupplyGroundMaxRoad is the longest route resupply will accept;
    # the searcher must be able to actually look that far.
    road = text("ITW_CLASH_RoadDistance.sqf")
    resupply = text("ITW_CLASH_Resupply.sqf")
    per_metre = float(re.search(r'"ITW_CLASH_RoadDistanceNodesPerMetre",([\d.]+)', road).group(1))
    cap = int(re.search(r'"ITW_CLASH_RoadDistanceMaxNodesCap",(\d+)', road).group(1))
    max_road = int(re.search(r'\["ITW_CLASH_ResupplyGroundMaxRoad",(\d+)\]', resupply).group(1))
    assert cap >= max_road * per_metre * 0.8, (cap, max_road * per_metre)


def test_exhaustion_reports_the_budget_it_spent():
    body = code_only(function_body(text("ITW_CLASH_RoadDistance.sqf"),
                                   "ITW_CLASH_RoadDistance_fnc_Calculate"))
    assert '"search-exhausted",[_posA,_posB,_nodesExpanded,_budget' in body


def test_minus_one_still_means_unproven_not_zero():
    # The contract the callers rely on; raising the budget must not change it.
    source = " ".join(text("ITW_CLASH_RoadDistance.sqf").split())
    assert "unproven, not merely unmeasured" in source


# --- the stranded-group correction ----------------------------------------

def test_the_live_allocation_audit_deliberately_never_releases():
    """Zero allocation-drift events in run4 is correct, not a missing arm.

    ITW_CLASH.sqf's canonical audit does release on drift, but the live owner
    is the InfantryAuthority allocation fix, which replaces that mutation on
    purpose for persistent infantry authority. Five groups sitting 3-5km back
    on 'awaiting-order' were therefore never HAL's to be taken from - they were
    free, unassigned, and simply never tasked.
    """
    source = text("ITW_CLASH_InfantryAuthorityAllocationFix.sqf")
    assert "ITW_CLASH_InfantryAuthorityAllocationFix_fnc_SetAffinity" in source
    body = code_only(source)
    assert "ITW_CLASH_fnc_ReleaseGroup" not in body
    assert "ITW_CLASH_ReeligibleAt" not in body
