import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def overwatch() -> str:
    return text("ITW_CLASH_SPAAOverwatch.sqf")


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


def test_spaa_leaves_every_pool_hal_dispatches_from():
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Detach")
    for pool in [
        "RydHQ_AttackAv", "RydHQ_FlankAv", "RydHQ_LArmorG", "RydHQ_HArmorG",
        "RydHQ_LArmorATG", "RydHQ_CarsG", "RydHQ_ReconAv",
    ]:
        assert pool in body, pool
    assert '["NoAttack","NoRecon","NoDef"],true' in body


def test_the_doctrine_covers_impasse_spawned_spaa_too():
    source = overwatch()
    # Trace 3: unless every SPAA obeys the rule, the coverage count cannot
    # trust Impasse's own Cheetahs and the commander buys one it already has.
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_Sweep")
    assert "allGroups select" in body
    assert "ITW_CLASH_AirPicture_fnc_IsSPAA" in body
    assert "ITW_CLASH_SPAAOverwatch_fnc_Adopt" in body
    assert 'ITW_CLASH_SPAAOverwatchAdoptImpasse",true' in source
    # A player's own vehicle is never adopted.
    assert "isPlayer _x" in body


def test_hal_cannot_take_it_back_between_cycles():
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Station")
    assert "ITW_CLASH_SPAAOverwatch_fnc_Detach" in body
    station = body.index("ITW_CLASH_SPAAOverwatch_fnc_Detach")
    assert station < body.index("ITW_CLASH_SPAAOverwatch_fnc_Sector")


def test_it_stands_behind_the_front_at_the_decided_standoff():
    source = overwatch()
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_Position")
    assert "ITW_CLASH_SPAAOverwatchStandoff" in body
    assert "ITW_CLASH_SPAAOverwatch_fnc_NearestKnownGround" in body
    assert 'ITW_CLASH_SPAAOverwatchStandoff",1500' in source
    # Nothing on the line clears the standoff: stay at the rear.
    assert "_position = +_rear}" in body


def test_it_covers_where_enemy_air_is_actually_operating():
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Sector")
    assert "ITW_CLASH_AirPicture_fnc_Hostiles" in body
    assert "ITW_CLASH_AirAlarmPosition" in body


def test_it_relocates_only_for_a_real_change_and_never_advances():
    source = overwatch()
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_Station")
    assert "ITW_CLASH_SPAAOverwatchHysteresis" in body
    assert 'ITW_CLASH_SPAAOverwatchHysteresis",600' in source
    # It only ever withdraws when threatened; a station closer to the enemy is
    # refused otherwise.
    assert "ITW_CLASH_SPAAOverwatchWithdrawAt" in body
    assert "if (!_threatened && {" in body


def test_overwatch_is_loaded_and_adopted_from_the_purchase_path():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_SPAAOverwatch.sqf"' in init
    assert "spaa-overwatch-missing-or-prereq-failed" in init
    cover = function_body(
        text("ITW_CLASH_HALThreatCoverage.sqf"),
        "ITW_CLASH_HALThreatCoverage_fnc_Cover",
    )
    assert "ITW_CLASH_SPAAOverwatch_fnc_Adopt" in cover
    # An SPAA purchase is never offered to HAL's dispatcher.
    spaa = cover.index('_capability isEqualTo "SPAA"')
    branch = cover[spaa:cover.index("} else {", spaa)]
    assert "ITW_CLASH_HALThreatCoverage_fnc_Offer" not in branch


# ------------------------------------------- one mobile AA in the back line

def test_the_back_line_holds_one_by_default():
    source = overwatch()
    assert 'ITW_CLASH_SPAAOverwatchMaxPerSide",1' in source
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_AtCapacity")
    assert "ITW_CLASH_SPAAOverwatchMaxPerSide" in body
    assert "ITW_CLASH_SPAAOverwatch_fnc_Held" in body


def test_what_is_held_is_counted_live():
    # Counted from the live roster rather than a tally, so a loss frees the
    # slot at the next sweep with no bookkeeping to go stale.
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Held")
    assert "ITW_CLASH_SPAAOverwatchGroups select" in body
    assert "{alive _x} count units _x" in body
    assert "alive _veh" in body
    assert "side _x isEqualTo _side" in body


def test_the_cap_is_enforced_at_one_chokepoint():
    # Every caller goes through Adopt, so the sweep and a purchase cannot
    # disagree about the limit.
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Adopt")
    assert "ITW_CLASH_SPAAOverwatch_fnc_AtCapacity" in body
    # Re-adopting one already held is not a new hold and must not be refused.
    assert "!(_group in ITW_CLASH_SPAAOverwatchGroups)" in body


def test_a_spare_is_left_with_hal_and_said_once():
    source = overwatch()
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_Sweep")
    assert '"over-cap"' in body
    # Once per change, not once per poll: a side that permanently owns a spare
    # would otherwise repeat this every 30 seconds all mission.
    assert 'getVariable ["ITW_CLASH_SPAAOverwatchPassed",-1]' in body
    assert 'setVariable ["ITW_CLASH_SPAAOverwatchPassed",_passed]' in body


def test_the_cap_is_reported_at_boot():
    source = overwatch()
    assert "maxPerSide=%7" in source
    assert "ITW_CLASH_SPAAOverwatchMaxPerSide\n];" in source


# ------------------------------------------- the gun is cued to the track

def test_a_stationed_spaa_is_told_what_it_is_covering():
    source = overwatch()
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_Cue")
    assert "ITW_CLASH_AirPicture_fnc_Hostiles" in body
    assert "_unit reveal [_x,ITW_CLASH_SPAAOverwatchCueLevel]" in body
    assert 'ITW_CLASH_SPAAOverwatchCueLevel",2' in source
    # Guarded, so a mission without the air picture still stations normally.
    assert 'isNil "ITW_CLASH_AirPicture_fnc_Hostiles"' in body


def test_the_cue_matches_hals_own_reveal_level():
    source = overwatch()
    level = int(re.search(r'ITW_CLASH_SPAAOverwatchCueLevel", *(\d+)', source).group(1))
    rev = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "Rev.sqf").read_text(
        encoding="utf-8", errors="replace"
    )
    assert level == int(re.search(r"_x reveal \[_KnU, *(\d+)\]", rev).group(1))


def test_it_cues_only_live_tracks_the_commander_holds():
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Cue")
    assert "select {!isNull _x && {alive _x}}" in body
    # Nothing map-wide and no unit sweep of its own.
    assert "allUnits" not in body
    assert "RydHQ_KnEnemies" not in body


def test_stationing_cues_and_records_it():
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Station")
    assert "ITW_CLASH_SPAAOverwatch_fnc_Cue" in body
    assert "_cued" in body
