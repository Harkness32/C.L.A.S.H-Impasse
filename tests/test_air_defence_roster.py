"""GUER's SPAA was a BLUFOR vehicle, correctly crewed with GUER.

Hark: "GEUR's spaa spawns as bluefor at all times, if it dies, it respawns as
blufore."

It was never a side-assignment bug. Both spawn paths set the side right:
ITW_AtkSpawnVeh does createGroup [_side,false] and DELETES the hull if crew
creation fails (ITW_Attack.sqf), so no uncrewed hull survives to inherit a
config side; RearBaseCRAM_fnc_Crew does createGroup [_side,true].

The fault is class selection. VehicleArrays.sqf:723 derives the enemy AA list
by filtering the enemy TANK list and hand-whitelists one classname:

    _threat#2 > 0.9 || {_class in ["B_APC_Tracked_01_AA_F"]}

That is the Cheetah - a BLUFOR class, written into the ENEMY AA selection. The
whitelist exists because neither upstream test could find a purpose-built SPAA:
the Cheetah is in va_eTankClasses at all, so its editorSubcategory is not "aa",
and it needed naming, so its threat array did not clear 0.9 either.

It reaches GUER because vehicle mode 0 ("full", VehicleArrays.sqf:160) sets
_isEnemyFaction = !_isGlobalCivFaction - every non-civilian vehicle in the game
is eligible for the enemy list whatever its config side - and GUER's whole order
of battle is B_* on this mission.

Both enemy AA sources read those lists: RearBaseCRAM.sqf:112 (statics, read
FIRST) then :130 (mobile), and ITW_Targets.sqf:749 for zone AA.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def read(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace")


def roster() -> str:
    return read("ITW_CLASH_AirDefenceRoster.sqf")


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
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return re.sub(r"//[^\n]*", "", body)


# ------------------------------------------------------------ the premise holds

def test_the_hand_whitelisted_blufor_class_is_still_upstream():
    """The defect this module exists to correct. If Impasse ever drops the
    whitelist this test should fail and the module can be reconsidered."""
    arrays = read("VehicleArrays.sqf")
    assert '_class in ["B_APC_Tracked_01_AA_F"]' in arrays
    # And it is in the ENEMY derivation, not the player's.
    block = arrays[arrays.index("// ensure enemy AA if possible"):]
    block = block[:block.index("va_pAllVehicles =")]
    assert "va_eAAClasses = va_eTankClasses select" in block
    assert "B_APC_Tracked_01_AA_F" in block


def test_both_spawn_paths_already_set_the_side_correctly():
    """Named so the diagnosis is not re-litigated: the side was never wrong,
    the vehicle was."""
    assert "createGroup [_side,true]" in read("ITW_CLASH_RearBaseCRAM.sqf")
    attack = read("ITW_Attack.sqf")
    assert "createGroup [_side,false]" in attack


def test_both_enemy_aa_readers_are_the_two_lists_this_module_rewrites():
    cram = read("ITW_CLASH_RearBaseCRAM.sqf")
    assert 'getVariable ["va_eStaticAAClasses",[]]' in cram
    assert 'getVariable ["va_eAAClasses",[]]' in cram
    # Statics are consulted first, which is why correcting only the mobile
    # list would leave the rear-base emplacement untouched.
    assert cram.index("va_eStaticAAClasses") < cram.index("va_eAAClasses")
    assert "va_eAAClasses,ITW_TGT_crewTypes" in read("ITW_Targets.sqf")


# ---------------------------------------------------------- capability, not name

def test_capability_comes_from_real_weapon_config():
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Tier"))
    assert "ITW_CLASH_AirPicture_fnc_ClassProfile" in body
    assert '_profile get "antiAir"' in body
    assert '_profile get "antiAirMissile"' in body


def test_no_classname_is_named_as_a_capability_test():
    """The whole point. A new faction's SPAA is found on its weapons, so it
    does not have to be subcategorised "aa", clear a threat array, or be
    listed here."""
    body = code_only(roster())
    assert "B_APC_Tracked_01_AA_F" not in body
    assert "threat" not in body
    assert "editorSubcategory" not in body


def test_the_threat_array_is_not_consulted_anywhere():
    assert 'getArray (configFile >> "cfgVehicles"' not in code_only(roster())


# ------------------------------------------------------------------ the ranking

def test_own_side_outranks_capability():
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Tier"))
    # Own side returns 0 or 1; another side returns 2 or 3. A guided
    # cross-side hull must never beat an own-side gun.
    assert "if (_ownSide) exitWith {if (_guided) then {0} else {1}}" in body
    assert "if (_guided) then {2} else {3}" in body


def test_an_undeclared_config_side_counts_as_own_side():
    """A mod that does not declare `side` is not evidence of the wrong army."""
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Tier"))
    assert "_sideNum < 0 || {_sideNum == _expectedSideNum}" in body


def test_a_class_that_cannot_engage_aircraft_is_rejected():
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Tier"))
    assert 'if !(_profile get "antiAir") exitWith {-1}' in body


def test_the_best_non_empty_tier_wins_and_keeps_all_its_entries():
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Rank"))
    assert "for \"_t\" from 0 to _maxTier do" in body
    assert "_chosenTier < 0" in body, "first non-empty tier only"


def test_cross_side_can_be_switched_off_entirely():
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Rank"))
    assert "if (ITW_CLASH_AirDefenceRosterAllowCrossSide) then {3} else {1}" in body


def test_string_config_sides_are_read_not_assumed():
    """CSLA ships `side` as a string; VehicleArrays.sqf:115 already has to work
    around it."""
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_ConfigSideNum"))
    assert "isNumber _entry" in body
    assert "isText _entry" in body
    assert 'case "teast": {0}' in body
    assert 'case "twest": {1}' in body


# ------------------------------------------------------------------- never worse

def test_a_list_is_never_emptied():
    """ITW_Targets.sqf:27 reads an empty va_eAAClasses as "this mission has no
    AA to destroy", so emptying it would silently delete a side task."""
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Correct"))
    write = body.index("missionNamespace setVariable [_listVar,_chosen]")
    guard = body.index("if (_chosen isEqualTo []) exitWith {")
    assert guard < write, "the empty-result guard must precede the write"
    assert "no-ranked-candidate" in body


def test_the_candidate_pool_is_only_what_impasse_already_allowed():
    """This module reorders and filters; it never widens what a side may
    field."""
    source = roster()
    assert '"va_eAAClasses","va_eTankClasses","va_eApcClasses"' in source
    assert '"va_eStaticAAClasses","va_eStaticClasses"' in source
    # No player-side list is ever read into an enemy pool.
    body = code_only(function_body(source, "ITW_CLASH_AirDefenceRoster_fnc_Correct"))
    assert "va_p" not in body


def test_entries_are_carried_through_intact():
    """VehicleArrays stores either a classname or [classname,...] and every
    consumer hands the whole entry to ITW_AtkSpawnVeh, which indexes it."""
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_ClassOf"))
    assert "_entry isEqualType []" in body
    assert "_entry#0" in body
    rank = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Rank"))
    assert "_bucket pushBack _x" in rank, "the entry, not its classname"


def test_a_cross_side_fallback_is_announced_loudly():
    body = code_only(function_body(roster(), "ITW_CLASH_AirDefenceRoster_fnc_Correct"))
    assert "if (_tier >= 2) then {" in body
    assert "cross-side-air-defence" in body
    assert "WARNING" in body


# ------------------------------------------------------------------- the ordering

def test_it_waits_for_a_real_completion_flag_not_mere_definition():
    """va_eAAClasses is initialised to [] several hundred lines before it is
    final, so "defined" is not "complete"."""
    source = roster()
    assert "ITW_CLASH_VehicleArraysReady" in source
    assert "ITW_CLASH_AirPictureReady" in source
    arrays = read("VehicleArrays.sqf")
    assert "ITW_CLASH_VehicleArraysReady = true;" in arrays
    # Set at the very end, after every list is composed.
    assert arrays.index("ITW_CLASH_VehicleArraysReady = true;") > arrays.index(
        "va_eAAClasses = va_eTankClasses select"
    )


def test_a_prerequisite_that_never_arrives_leaves_impasse_untouched():
    source = roster()
    assert "vehicle-arrays-not-ready" in source
    assert "air-picture-not-ready" in source
    assert "stock Impasse AA lists retained" in source


def test_the_enemy_side_is_read_from_the_mission_not_guessed():
    source = roster()
    assert "ITW_EnemySide call BIS_fnc_sideID" in source
    assert 'if (isNil "ITW_EnemySide") exitWith' in source


def test_wired_into_init_behind_the_air_picture():
    init = read("init.sqf")
    assert '"ITW_CLASH_AirDefenceRoster.sqf"' in init
    assert init.index('"ITW_CLASH_AirPicture.sqf"') < init.index(
        '"ITW_CLASH_AirDefenceRoster.sqf"'
    )
    # Before the two readers, so the file reads in dependency order.
    assert init.index('"ITW_CLASH_AirDefenceRoster.sqf"') < init.index(
        '"ITW_CLASH_RearBaseCRAM.sqf"'
    )


# ----------------------------------------- who mans the launcher, not just which

def cram() -> str:
    return read("ITW_CLASH_RearBaseCRAM.sqf")


def test_the_gunner_is_chosen_not_taken_first():
    """Hark photographed a GUER Mini-Spike emplacement manned by a helicopter
    pilot in a flight helmet. The crew class was _crewTypes#0 - whatever the
    faction list happened to put first."""
    body = code_only(function_body(cram(), "ITW_CLASH_RearBaseCRAM_fnc_Crew"))
    assert "_crewTypes#0" not in body, "the blind first pick is the defect"
    assert "ITW_CLASH_RearBaseCRAM_fnc_GunnerType" in body


def test_pilots_are_legitimately_in_the_crew_list():
    """The premise. Checkbook_fnc_GetCrewTypes asks FactionUnits for role
    "Crewman", and Arma gives pilots that same role - both are vehicle crew to
    the role taxonomy - so filtering has to happen at the point of use."""
    checkbook = read("ITW_CLASH_DualHALCheckbook.sqf")
    body = function_body(checkbook, "ITW_CLASH_Checkbook_fnc_GetCrewTypes")
    assert '["Crewman"]' in body


def test_pilots_are_detected_by_subcategory_and_classname():
    body = code_only(function_body(cram(), "ITW_CLASH_RearBaseCRAM_fnc_IsPilotClass"))
    assert "editorSubcategory" in body
    assert '["pilot",_subcat,false] call BIS_fnc_inString' in body
    assert '["pilot",toLowerANSI _class,false] call BIS_fnc_inString' in body


def test_a_non_pilot_wins_when_one_exists():
    body = code_only(function_body(cram(), "ITW_CLASH_RearBaseCRAM_fnc_GunnerType"))
    assert "ITW_CLASH_RearBaseCRAM_fnc_IsPilotClass" in body
    assert "if (_ground isNotEqualTo []) exitWith {_ground#0}" in body


def test_an_all_pilot_faction_still_gets_a_gunner():
    """Fail-open on purpose: a pilot in the seat is cosmetic, an uncrewed
    launcher reads as its CONFIG side, which is the fault this whole module
    exists to prevent."""
    body = code_only(function_body(cram(), "ITW_CLASH_RearBaseCRAM_fnc_GunnerType"))
    tail = body[body.index("if (_ground isNotEqualTo []) exitWith"):]
    assert "pilot-gunner-fallback" in tail
    assert tail.rstrip().rstrip("}").rstrip().endswith("_crewTypes#0")


def test_the_two_faults_in_that_screenshot_have_different_owners():
    """One photograph, two bugs: a BLUFOR launcher (class selection, the
    roster) and a pilot crewing it (crew selection, here). Neither fixes the
    other."""
    assert "ITW_CLASH_AirDefenceRoster_fnc_Correct" in roster()
    assert "ITW_CLASH_RearBaseCRAM_fnc_GunnerType" in cram()
    assert "GunnerType" not in roster()
