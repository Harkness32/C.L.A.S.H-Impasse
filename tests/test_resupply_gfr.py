"""GFR: what a claimed vehicle group does while it waits for resupply.

v1 withdrew it to a threat-screened rally, which in one run ordered a damaged
Namer 1250m off the line - far enough that HAL reads the tank as gone and buys
a replacement. v2 holds it where it stands, breaks only to cover when it is
actually being hit, and lets it close part of the gap to a dispatched truck.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def resupply() -> str:
    return (MISSION / "ITW_CLASH_Resupply.sqf").read_text(encoding="utf-8")


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


def test_module_is_v2():
    assert "ITW_CLASH_ResupplyVersion = 2;" in resupply()


def test_gfr_settings_exist_and_are_sane():
    source = resupply()
    assert '["ITW_CLASH_ResupplyGFRHold",true]' in source
    weight = float(re.search(r'\["ITW_CLASH_ResupplyGFRRendezvousWeight",([\d.]+)\]', source).group(1))
    # Weighted below half on purpose: the damaged or dry side moves less.
    assert 0 < weight < 0.5, weight
    breaks = int(re.search(r'\["ITW_CLASH_ResupplyGFRMaxBreaks",(\d+)\]', source).group(1))
    assert breaks >= 1, breaks
    radius = int(re.search(r'\["ITW_CLASH_ResupplyGFRBreakRadius",(\d+)\]', source).group(1))
    run = int(re.search(r'\["ITW_CLASH_ResupplyGFRMaxRecipientRun",(\d+)\]', source).group(1))
    # Both leashes must stay well under the 1250m withdraw that caused this.
    assert radius < run < 1250, (radius, run)


def test_a_vehicle_group_holds_instead_of_withdrawing():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_StepResolve"))
    hold = body.index("ITW_CLASH_Resupply_fnc_IsVehicleGroup")
    rally = body.index("ITW_CLASH_Resupply_fnc_FindSharedRally")
    # The hold arm has to come first, and exit, or the rally logic still runs.
    assert hold < rally, "GFR hold must pre-empt the v1 rally search"
    assert "ITW_CLASH_ResupplyGFRHold" in body
    assert "ITW_CLASH_Resupply_fnc_Hold" in body


def test_infantry_keeps_the_v1_rally():
    # The hold is gated on being a vehicle group; a hollow squad still screens.
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_StepResolve"))
    arm = body[body.index("ITW_CLASH_ResupplyGFRHold"):]
    gate = arm[:arm.index("exitWith")]
    assert "IsVehicleGroup" in gate, "the hold must not apply to infantry"


def test_an_immobile_vehicle_is_still_served_in_place():
    # Predates GFR and must survive it: no fuel or no drive means no movement.
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_StepResolve"))
    assert 'fuel _x <= 0 || {!canMove _x}' in body
    assert body.index("canMove") < body.index("ITW_CLASH_ResupplyGFRHold")


def test_under_fire_is_judged_by_damage_as_well_as_known_enemies():
    # A shooter HAL has not spotted still has to count, or the group sits and dies.
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_UnderFire"))
    assert "ITW_CLASH_ResupplyGFRDamageEpsilon" in body
    assert "ITW_CLASH_Resupply_fnc_Clearance" in body


def test_the_break_is_leashed():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_BreakPoint"))
    assert "ITW_CLASH_ResupplyGFRBreakRadius" in body
    assert "ITW_CLASH_Resupply_fnc_Clearance" in body
    assert "surfaceIsWater" in body


def test_breaking_is_bounded_and_only_while_held():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_StepAtRally"))
    arm = body[:body.index("ITW_CLASH_Resupply_fnc_BreakPoint")]
    assert '"frozen"' in arm
    assert "ITW_CLASH_Resupply_fnc_UnderFire" in arm
    assert "ITW_CLASH_ResupplyGFRMaxBreaks" in arm


def test_rendezvous_is_capped_and_vetted():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_Rendezvous"))
    assert "ITW_CLASH_ResupplyGFRRendezvousWeight" in body
    assert "min ITW_CLASH_ResupplyGFRMaxRecipientRun" in body
    assert "ITW_CLASH_Resupply_fnc_Clearance" in body
    assert "surfaceIsWater" in body
    # An immobile or dry vehicle never drives to meet anyone.
    assert "fuel _x <= 0 || {!canMove _x}" in body


def test_rendezvous_only_follows_a_chosen_truck():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_DispatchGround"))
    assert "ITW_CLASH_Resupply_fnc_Rendezvous" in body
    assert body.index("isNull _truck") < body.index("ITW_CLASH_Resupply_fnc_Rendezvous")


def test_reaching_the_rendezvous_re_holds():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_StepAwait"))
    assert '"rendezvous"' in body
    assert "ITW_CLASH_Resupply_fnc_Hold" in body
    # Must be settled before the in-flight check can exit the step.
    assert body.index('"rendezvous"') < body.index("ITW_CLASH_Resupply_fnc_InFlight")


def test_arriving_at_any_rally_re_holds_a_vehicle_group():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_StepMoving"))
    arrival = body[:body.index("_relocate")]
    assert "ITW_CLASH_Resupply_fnc_Hold" in arrival


def test_release_unholds_before_dropping_busy():
    # A group handed back under doStop would take HAL's next order and not move.
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_Release"))
    assert "ITW_CLASH_Resupply_fnc_Unhold" in body
    assert body.index("fnc_Unhold") < body.index('"Busy" + str _group,false')


def test_hold_pins_vehicles_not_just_waypoints():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_Hold"))
    assert "RYD_WPdel" in body
    assert "doStop" in body


def test_unhold_restores_follow():
    body = code_only(function_body(resupply(), "ITW_CLASH_Resupply_fnc_Unhold"))
    assert "doFollow" in body


def test_the_claim_message_reports_the_patience_actually_waited():
    # Every run logged "for 120s" even on repair claims taken at 30s.
    source = resupply()
    claim = function_body(source, "ITW_CLASH_Resupply_fnc_Claim")
    message = claim[claim.index("has needed"):]
    assert "ITW_CLASH_Resupply_fnc_Patience" in message
    assert "round ITW_CLASH_ResupplyPatience" not in message
