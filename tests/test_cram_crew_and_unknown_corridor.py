"""Two field reports from one run, and one shared root cause each.

1. "GEUR AA is spawning as Blufor" and "if base AA is destroyed, it respawns
   on zone flip" were one bug. fnc_Maintain treated a dead GUNNER as a dead
   EMPLACEMENT, so killing the crew deleted an intact vehicle and built a new
   one, and in the meantime the uncrewed hull took its CONFIG side - which for
   GUER's B_APC_Tracked_01_AA_F is BLUFOR, because GUER's whole order of
   battle is NATO in this mission.

2. "we are losing so many littlebirds to first engagements" was the corridor
   classifier having no way to say "nobody has looked". An unobserved corridor
   returned COLD/corridor-clear, identical to one verified empty, so HotDrop
   declined it and HAL flew an ordinary landing approach into it.
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


# --- 1. crew loss is not emplacement loss --------------------------------

def test_a_dead_gunner_is_no_longer_a_dead_emplacement():
    body = code_only(function_body(text("ITW_CLASH_RearBaseCRAM.sqf"),
                                   "ITW_CLASH_RearBaseCRAM_fnc_Maintain"))
    # The conflated test is gone.
    assert "isNull _veh || {!alive _veh} || {isNull (gunner _veh)}" not in body
    # An intact but uncrewed piece is re-crewed, and that arm comes first.
    assert "alive _veh && {isNull (gunner _veh)}" in body
    assert body.index("isNull (gunner _veh)") < body.index("_destroyedAt <= 0")


def test_recrewing_is_in_place_and_does_not_replace_the_vehicle():
    body = code_only(function_body(text("ITW_CLASH_RearBaseCRAM.sqf"),
                                   "ITW_CLASH_RearBaseCRAM_fnc_Maintain"))
    arm = body[body.index("alive _veh && {isNull (gunner _veh)}"):body.index("if (alive _veh) exitWith")]
    assert "ITW_CLASH_RearBaseCRAM_fnc_Crew" in arm
    assert "ITW_CLASH_RearBaseCRAM_fnc_Spawn" not in arm, "re-crew must not respawn the piece"
    assert "recrewed" in arm


def test_recrewing_is_bounded():
    source = text("ITW_CLASH_RearBaseCRAM.sqf")
    bound = int(re.search(r'"ITW_CLASH_RearBaseCRAMMaxRecrews",(\d+)', source).group(1))
    assert bound >= 1, bound
    body = code_only(function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_Maintain"))
    assert "ITW_CLASH_RearBaseCRAMMaxRecrews" in body


def test_an_uncrewable_hull_is_removed_rather_than_left_side_ambiguous():
    # This is the BLUFOR-reading-vehicle half of the report: an uncrewed hull
    # must never be left standing in the base.
    body = code_only(function_body(text("ITW_CLASH_RearBaseCRAM.sqf"),
                                   "ITW_CLASH_RearBaseCRAM_fnc_Maintain"))
    arm = body[body.index("recrew-exhausted"):]
    assert "deleteVehicle _veh" in arm[:400]


def test_a_failed_spawn_never_leaves_an_uncrewed_vehicle():
    body = code_only(function_body(text("ITW_CLASH_RearBaseCRAM.sqf"),
                                   "ITW_CLASH_RearBaseCRAM_fnc_Spawn"))
    assert "ITW_CLASH_RearBaseCRAM_fnc_Crew" in body
    tail = body[body.index("ITW_CLASH_RearBaseCRAM_fnc_Crew"):]
    assert "deleteVehicle _veh" in tail


def test_crewing_never_deletes_the_vehicle_itself():
    # The caller owns the hull; fnc_Crew only owns the crew it made.
    body = code_only(function_body(text("ITW_CLASH_RearBaseCRAM.sqf"),
                                   "ITW_CLASH_RearBaseCRAM_fnc_Crew"))
    assert "deleteVehicle _veh" not in body
    assert "deleteVehicle _gunner" in body
    assert "createGroup [_side,true]" in body


def test_a_replacement_stands_where_the_original_did():
    # Re-resolving the base graph made a replacement appear at a different base
    # after a zone flip, which reads as the emplacement teleporting.
    body = code_only(function_body(text("ITW_CLASH_RearBaseCRAM.sqf"),
                                   "ITW_CLASH_RearBaseCRAM_fnc_Maintain"))
    assert "_fresh set [3,_position]" in body


def test_clearing_a_rear_base_can_be_made_permanent():
    source = text("ITW_CLASH_RearBaseCRAM.sqf")
    body = code_only(function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_Maintain"))
    assert "ITW_CLASH_RearBaseCRAMRespawn <= 0) exitWith {false}" in body


# --- 2. unknown is not clear ---------------------------------------------

def test_the_classifier_can_say_unknown():
    body = code_only(function_body(text("ITW_CLASH_AirPicture.sqf"),
                                   "ITW_CLASH_AirPicture_fnc_ClassifyCorridor"))
    assert '_result set ["state","UNKNOWN"]' in body
    assert '"destination-unobserved"' in body


def test_unknown_is_decided_last_so_measured_threat_always_wins():
    # A corridor with a real threat must report that threat, not UNKNOWN.
    body = code_only(function_body(text("ITW_CLASH_AirPicture.sqf"),
                                   "ITW_CLASH_AirPicture_fnc_ClassifyCorridor"))
    unknown = body.index('_result set ["state","UNKNOWN"]')
    for measured in ("AIR_DENIED", "HOT", "CONTESTED"):
        assert body.index(f'"{measured}"') < unknown, measured


def test_observation_counts_friendlies_and_known_enemies():
    body = code_only(function_body(text("ITW_CLASH_AirPicture.sqf"),
                                   "ITW_CLASH_AirPicture_fnc_Observed"))
    assert "RydHQ_KnEnemies" in body
    assert "RydHQ_Friends" in body
    assert "ITW_CLASH_AirPictureObservedRadius" in body


def test_observation_is_read_only():
    body = code_only(function_body(text("ITW_CLASH_AirPicture.sqf"),
                                   "ITW_CLASH_AirPicture_fnc_Observed"))
    assert "setVariable" not in body


def test_the_rear_is_observed_by_definition():
    """Why UNKNOWN does not re-widen HotDrop to every lift on the map.

    Including COLD once made HotDrop take essentially every troop lift. UNKNOWN
    cannot, because the observation test is satisfied by our own units being
    near the destination - which is always true of a rear ferry. Only genuinely
    unvisited forward ground reads UNKNOWN. That bound lives in fnc_Observed
    checking RydHQ_Friends, so this test guards it.
    """
    body = code_only(function_body(text("ITW_CLASH_AirPicture.sqf"),
                                   "ITW_CLASH_AirPicture_fnc_Observed"))
    friends = body[body.index("RydHQ_Friends") - 600:]
    assert "units _x" in friends or "units _group" in friends


# --- 3. unknown corridors are parachuted, never landed into --------------

def test_hotdrop_takes_unknown_corridors():
    source = text("ITW_CLASH_HotDrop.sqf")
    states = re.search(r'"ITW_CLASH_HotDropStates",\[([^\]]*)\]', source).group(1)
    assert '"UNKNOWN"' in states
    # COLD stays HAL's: a corridor measured quiet does not need the profile.
    assert '"COLD"' not in states


def test_landing_is_refused_where_the_corridor_is_dangerous_or_unknown():
    source = text("ITW_CLASH_HotDrop.sqf")
    noland = re.search(r'"ITW_CLASH_HotDropNoLandStates",\[([^\]]*)\]', source).group(1)
    for state in ('"HOT"', '"AIR_DENIED"', '"UNKNOWN"'):
        assert state in noland, state
    # CONTESTED is measured and survivable; landing there stays allowed.
    assert '"CONTESTED"' not in noland


def test_both_landing_paths_honour_the_refusal():
    body = code_only(function_body(text("ITW_CLASH_HotDrop.sqf"),
                                   "ITW_CLASH_HotDrop_fnc_PutOut"))
    assert body.count("_noLand") >= 3
    # The host-disabled-parachutes path and the paradrop-refused path.
    assert body.count('land "GET OUT"') == 2
    for segment in body.split('land "GET OUT"')[:-1]:
        assert "_noLand" in segment


def test_a_refused_landing_hands_the_lift_back_instead_of_flying_home_loaded():
    # Falling through would hit the wait-for-empty loop, time out, and egress
    # with the troops still aboard.
    body = code_only(function_body(text("ITW_CLASH_HotDrop.sqf"),
                                   "ITW_CLASH_HotDrop_fnc_Run"))
    assert 'if (_method isEqualTo "NO_LAND") exitWith {["NO_LAND"] call _abort}' in body
    assert body.index("fnc_PutOut") < body.index('"NO_LAND") exitWith')


def test_the_corridor_state_is_recorded_before_the_drop_needs_it():
    source = text("ITW_CLASH_HotDrop.sqf")
    assert '_state set ["corridorState",_corridorState]' in source
    put_out = code_only(function_body(source, "ITW_CLASH_HotDrop_fnc_PutOut"))
    assert '_state getOrDefault ["corridorState",""]' in put_out
