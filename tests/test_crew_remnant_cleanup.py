"""Crews that lose their vehicle are quarantined and then never deleted.

Three RPTs of 2026-10-10:

    20:14   16 quarantined   0 cleaned
    20:53    3 quarantined   0 cleaned
    23:22   24 quarantined   0 cleaned

ITW_CLASH_CrewRemnantCleanup.sqf is meant to take a crew out of HAL when its
vehicle is gone, dead or cannot move, and delete it 20 s later if no player is
within 300 m. Version 1 could not reach the second step, for two reasons that
were each enough alone:

  1. The loop walked ITW_CLASH_DualHALBLUFORGroups and
     ITW_CLASH_DualHALOPFORExtraGroups. Quarantine ends in
     ITW_CLASH_Service_fnc_RemoveHALOwnership, which removes the group from
     both.
  2. The loop skips any group ITW_CLASH_DualHAL_fnc_IsLifecycleReserved, whose
     first test is ITW_CLASH_ExcludeHAL. Quarantine sets ITW_CLASH_ExcludeHAL.

Version 2 keeps its own list of quarantined crews, walks it, and does not read
its own ExcludeHAL as somebody else's reservation. The grace, the radius and
the survivor limit are unchanged.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace").replace("\r", "")


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


def code_only(source: str) -> str:
    """Drop // comments so a commented-out line cannot satisfy an assertion."""
    return "\n".join(
        line for line in source.split("\n") if not line.lstrip().startswith("//")
    )


def cleanup() -> str:
    return mission("ITW_CLASH_CrewRemnantCleanup.sqf")


def loop() -> str:
    source = code_only(cleanup())
    return source[source.index('scriptName "ITW_CLASH_CrewRemnantCleanup";'):]


# --- what made version 1 blind -------------------------------------------


def test_quarantine_still_removes_the_crew_from_both_lists_the_loop_started_from():
    """The first blocker, in the source it lives in. If this ever stops being
    true the private list is merely redundant, not wrong."""
    remove = function_body(
        mission("ITW_CLASH_ServiceLifecycle.sqf"),
        "ITW_CLASH_Service_fnc_RemoveHALOwnership",
    )
    assert "ITW_CLASH_DualHALBLUFORGroups - [_group]" in remove
    assert "ITW_CLASH_DualHALOPFORExtraGroups - [_group]" in remove

    quarantine = function_body(cleanup(), "ITW_CLASH_CrewRemnant_fnc_RemoveHAL")
    assert "ITW_CLASH_Service_fnc_RemoveHALOwnership" in quarantine


def test_quarantine_sets_the_flag_that_the_reservation_check_reads_first():
    """The second blocker. A crew this module quarantined looked reserved by
    somebody else because of the flag the module had just set."""
    reserved = function_body(
        mission("ITW_CLASH_DualHALCheckbook.sqf"),
        "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved",
    )
    assert '_group getVariable ["ITW_CLASH_ExcludeHAL",false]' in reserved

    quarantine = function_body(cleanup(), "ITW_CLASH_CrewRemnant_fnc_RemoveHAL")
    assert '_group setVariable ["ITW_CLASH_ExcludeHAL",true]' in quarantine


# --- the loop can see a quarantined crew again ----------------------------


def test_the_loop_walks_its_own_quarantine_list_as_well():
    body = loop()
    assert "_groups append ITW_CLASH_DualHALBLUFORGroups;" in body
    assert "_groups append ITW_CLASH_DualHALOPFORExtraGroups;" in body
    assert "_groups append ITW_CLASH_CrewRemnantQuarantined;" in body
    assert body.index("_groups append ITW_CLASH_CrewRemnantQuarantined;") < body.index(
        "} forEach _groups;"
    )


def test_a_crew_is_listed_before_its_hal_ownership_is_removed():
    """Listed first, so there is no pass on which it is in neither place."""
    body = loop()
    listed = body.index("ITW_CLASH_CrewRemnantQuarantined pushBackUnique _group;")
    removed = body.index("[_group] call ITW_CLASH_CrewRemnant_fnc_RemoveHAL;")
    stamped = body.index('_group setVariable ["ITW_CLASH_CrewRemnantSince",time];')
    assert stamped < listed < removed


def test_the_quarantine_list_drops_dead_and_deleted_crews():
    body = loop()
    prune = body[body.index("ITW_CLASH_CrewRemnantQuarantined = ITW_CLASH_CrewRemnantQuarantined select {"):]
    prune = prune[:prune.index("};") + 2]
    assert "!isNull _x" in prune
    assert "findIf {alive _x}" in prune
    assert body.index("ITW_CLASH_CrewRemnantQuarantined select {") < body.index(
        "_groups append ITW_CLASH_CrewRemnantQuarantined;"
    )


def test_the_loop_no_longer_asks_dualhal_directly_whether_the_crew_is_reserved():
    body = loop()
    assert "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" not in body
    assert "{[_group] call ITW_CLASH_CrewRemnant_fnc_IsReserved}" in body


def test_a_quarantined_crew_is_not_reserved_by_its_own_exclude_flag():
    reserved = code_only(function_body(cleanup(), "ITW_CLASH_CrewRemnant_fnc_IsReserved"))
    assert "ITW_CLASH_ExcludeHAL" not in reserved
    # Anything not quarantined is still judged by DualHAL, flag and all.
    first = reserved.index("if !(_group in ITW_CLASH_CrewRemnantQuarantined) exitWith {")
    assert "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" in reserved[first:reserved.index("};", first)]


def test_every_other_reservation_still_protects_a_quarantined_crew():
    """The group flags are DualHAL's list. If that list grows, this one must."""
    dual = function_body(
        mission("ITW_CLASH_DualHALCheckbook.sqf"),
        "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved",
    )
    flags = re.findall(r'_group getVariable \["([A-Za-z_]+)",false\]', dual)
    assert "ITW_CLASH_ExcludeHAL" in flags
    others = [flag for flag in flags if flag != "ITW_CLASH_ExcludeHAL"]
    assert len(others) >= 5

    reserved = function_body(cleanup(), "ITW_CLASH_CrewRemnant_fnc_IsReserved")
    for flag in others:
        assert f'_group getVariable ["{flag}",false]' in reserved, flag


# --- the delete step is the one that was designed -------------------------


def test_the_design_numbers_did_not_move():
    source = cleanup()
    assert '"ITW_CLASH_CrewRemnantGrace",20' in source
    assert '"ITW_CLASH_CrewRemnantPlayerRadius",300' in source
    assert '"ITW_CLASH_CrewRemnantMaxSurvivors",4' in source


def test_grace_then_player_distance_then_delete():
    body = loop()
    grace = body.index("if (time - _since < ITW_CLASH_CrewRemnantGrace) then {continue};")
    players = body.index("ITW_CLASH_CrewRemnantPlayerRadius")
    logged = body.index('["cleaned",[')
    deleted = body.index("deleteVehicle _x;")
    assert grace < players < logged < deleted


def test_only_a_crew_with_a_lost_vehicle_and_crew_provenance_is_touched():
    body = loop()
    assert '!(_group getVariable ["ITW_CLASH_VehicleCrewGroup",false])' in body
    assert '!(_x getVariable ["ITW_CLASH_VehicleCrewUnit",false])' in body
    assert "isNull _veh || {!alive _veh} || {!canMove _veh}" in body
    assert "[_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup" in body
    lost = body.index("if (!_vehicleLost) then {")
    assert lost < body.index("ITW_CLASH_CrewRemnantQuarantined pushBackUnique _group;")


def test_a_man_in_a_seat_is_removed_by_the_vehicle():
    body = loop()
    assert "private _seat = objectParent _x;" in body
    assert "_seat deleteVehicleCrew _x;" in body
    assert "_group deleteGroupWhenEmpty true;" in body


def test_the_quarantine_line_says_what_is_wrong_with_the_vehicle():
    """G36 and G57 left working-looking vehicles at base within 25 s of their
    first order and the version 1 line could not say why."""
    state = function_body(cleanup(), "ITW_CLASH_CrewRemnant_fnc_VehicleState")
    for token in ['"vehicle-null"', '"vehicle-dead"', '"cannot-move"', "getAllHitPointsDamage _veh"]:
        assert token in state
    body = loop()
    line = body[body.index('["quarantined",['):body.index("call ITW_CLASH_CrewRemnant_fnc_Log", body.index('["quarantined",['))]
    assert "_state#0" in line and "_state#1" in line
    assert "{vehicle _x != _x} count _survivors" in line


def test_the_boot_line_says_the_fix_is_loaded():
    source = cleanup()
    assert "ITW_CLASH_CrewRemnantCleanupVersion = 2;" in source
    assert "walksQuarantined=true" in source
