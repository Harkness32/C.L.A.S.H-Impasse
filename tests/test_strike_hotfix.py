"""
2026-10-18 run (Hark: "strikes are utterly useless").

1. The commanders flew nothing for 90 minutes. v8's console strike test passed
   its point as a target's fourth element; in a real assessment that slot is
   the objective's picture entry, a hashmap, so the first assessment died on
   "Type HashMap, expected Array" (Supports.sqf:1323) and took COLOSSUS's loop
   with it, for both sides.
2. The guided pass flew cluster-bomb jets. Arma simulates a bomb as a missile
   with no thrust, so a CBU-85 with a seeker and an armour flag read as a
   guided anti-armour missile and was launched from missile range.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code(name: str) -> str:
    source = (MISSION / name).read_text(encoding="utf-8")
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


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


CORE = code("ITW_CLASH_Supports.sqf")
STRIKE = code("ITW_CLASH_SupportsStrike.sqf")
DEBUG = code("ITW_CLASH_SupportsDebug.sqf")


# ------------------------------------------- 1. the assessment's target shape

def test_a_real_target_carries_the_picture_entry_in_its_fourth_slot():
    assess = function_body(CORE, "ITW_CLASH_Supports_fnc_Assess")
    assert '_targets pushBack [_index,"HOLD",_urgency,_entry,_pressure];' in assess
    assert '_targets pushBack [_index,"TAKE",1,_entry,-1];' in assess
    assert "[_context,_active] call ITW_CLASH_Supports_fnc_StrikeCandidates" in assess


def test_the_strike_pool_never_reads_a_target_past_its_urgency():
    body = function_body(CORE, "ITW_CLASH_Supports_fnc_StrikeCandidates")
    loop = body[body.index("{", body.index("private _centers = [];")):body.index("} forEach _targets;")]
    params = re.search(r"_x params \[([^\]]*)\];", loop).group(1)
    assert params.count('"') == 6, params  # exactly three names
    assert "_x#3" not in loop and "param [3" not in loop and "select 3" not in loop
    # The test's point comes off the context, and only for a test.
    assert 'private _at = if (_test) then {_context getOrDefault ["at",[]]} else {[]};' in loop


def test_the_console_test_puts_its_point_on_the_context():
    strike = function_body(DEBUG, "ITW_CLASH_SupportsDebug_fnc_Strike")
    assert '_context set ["at",_point];' in strike
    assert "[[_objective,_reason,1]]" in strike
    assert "_point]]" not in strike


def test_a_test_says_why_a_cluster_was_worth_nothing():
    # 4:22:24, "4 contacts known within 2000 m; nothing it could strike": a
    # bomb takes no lead-only cluster, and a test now says that.
    body = function_body(CORE, "ITW_CLASH_Supports_fnc_StrikeCandidates")
    zero = body[body.index("if (_base <= 0) then {"):]
    zero = zero[:zero.index("private _gate")]
    assert 'if (_test) then {[_context,_flavor,-1,_targetKey,"NOT_FOR_" + _class] call ITW_CLASH_Supports_fnc_Exclude};' in zero
    assert "continue" in zero


# --------------------------------------------- 2. guided means a motor

def test_a_guided_strike_needs_a_powered_round():
    body = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor")
    motor = body.index('"thrust"')
    assert '(getNumber (_motor >> "thrust")) <= 0 && {(getNumber (_motor >> "thrustTime")) <= 0}' in body
    # Before the rack's own answer, so a bomb never reaches it.
    assert motor < body.index("ITW_CLASH_Rack_fnc_IsGuidedAntiArmour")
    # Both readers go through it: the class pick and the jet's own weapon.
    assert "ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor" in function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_ClassGuided")
    assert "ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor" in function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_GuidedWeapon")


def test_the_bomb_the_mission_drops_is_a_motorless_missile():
    # The boot line read in that run: ["Bo_Mk82",true,"shotMissile",0.08,0.12,100,0,0,120],
    # thrust and thrustTime the two zeros. The ammo log prints them in that order.
    raw = (MISSION / "ITW_CLASH_SupportsStrike.sqf").read_text(encoding="utf-8")
    ammo = raw[raw.index('["ammo",['):]
    assert ammo.index('"simulation"') < ammo.index('"thrust"') < ammo.index('"thrustTime"')


def test_which_jets_can_fly_it_is_said_once_per_class():
    body = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_ClassGuided")
    assert '["guided-class",[_class,_guided,' in body
    assert body.index("ITW_CLASH_SupportsStrikeGuidedClasses get _class") < body.index('"guided-class"')
    raw = (MISSION / "ITW_CLASH_SupportsStrike.sqf").read_text(encoding="utf-8")
    assert "ITW_CLASH_SupportsStrikeVersion = 6;" in raw
    assert "guidedNeedsMotor=true" in raw


# --------------------------------------- 3. lead time (Hark: "jets are fast")

def test_every_strike_starts_eight_km_out():
    raw = (MISSION / "ITW_CLASH_Supports.sqf").read_text(encoding="utf-8")
    assert '["ITW_CLASH_SupportsSpawnDistanceJet",8000]' in raw
    assert '["ITW_CLASH_SupportsSpawnDistanceBomb",8000]' in raw
    spawn = function_body(CORE, "ITW_CLASH_Supports_fnc_SpawnDistance")
    assert 'if (_kind isEqualTo "JET") exitWith {ITW_CLASH_SupportsSpawnDistanceJet};' in spawn
    # Helicopters, transport planes and the UAV are unchanged.
    assert '["ITW_CLASH_SupportsSpawnDistanceSlow",5000]' in raw
    assert "jetSpawn=%47m projectionJet=%48" in raw


def test_flight_time_is_projected_at_what_jets_fly():
    raw = (MISSION / "ITW_CLASH_Supports.sqf").read_text(encoding="utf-8")
    assert '["ITW_CLASH_SupportsSpeedJet",150]' in raw
    speed = function_body(CORE, "ITW_CLASH_Supports_fnc_ProjectionSpeed")
    assert 'case "JET": {ITW_CLASH_SupportsSpeedJet};' in speed


def test_the_guided_scan_runs_from_five_km_to_minimum_range():
    raw = (MISSION / "ITW_CLASH_SupportsStrike.sqf").read_text(encoding="utf-8")
    assert '["ITW_CLASH_SupportsStrikeScanRange",5000]' in raw
    assert '["ITW_CLASH_SupportsStrikeScanWindow",60]' in raw
    # It starts where the missile's default lock reaches, inside the spawn.
    max_range = int(re.search(r'"ITW_CLASH_SupportsStrikeMaxRange",(\d+)', raw).group(1))
    assert max_range == 5000
    body = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_GuidedPass")
    assert '(_veh distance2D _report) <= ITW_CLASH_SupportsStrikeScanRange' in body
    # Minimum range still ends it first.
    assert 'if (_along < _minRange) exitWith {_ended = "inside-min-range"};' in body
