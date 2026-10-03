import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"

SITES = ["ITW_Attack.sqf", "ITW_Teammates.sqf", "ITW_Functions.sqf"]
READ = 'setSkill ["spotTime",missionNamespace getVariable ["ITW_CLASH_SpotTime",0.9]]'


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_every_spawn_path_raises_spotting_speed():
    for name in SITES:
        assert READ in text(name), name


def test_it_follows_the_flat_set_rather_than_preceding_it():
    # setSkill with a number overwrites every sub-skill, so an override placed
    # before it would be silently erased.
    for name in SITES:
        source = text(name)
        flat = min(
            source.index(m)
            for m in ["_unit setSkill _skill;", "_unit setSkill (ITW_ParamFriendlySquadSkill);", "_clone setSkill _skill;"]
            if m in source
        )
        assert flat < source.index(READ), name


def test_only_spotting_speed_moves():
    # Aiming stays where the difficulty parameter put it: react sooner, do not
    # shoot better.
    for name in SITES:
        source = text(name)
        for untouched in ["aimingAccuracy", "aimingSpeed", "aimingShake", "spotDistance"]:
            assert f'setSkill ["{untouched}"' not in source, (name, untouched)


def test_the_probe_logic_is_left_at_full_skill():
    # ITW_Functions.sqf:826 measures the server's coefficients by reading
    # skillFinal off a unit at skill 1. Touching it would corrupt the reading
    # the preflight now reports.
    source = text("ITW_Functions.sqf")
    probe = source.index("_logic setSkill 1;")
    assert "spotTime" not in source[probe:probe + 400]


def test_it_is_tunable_and_defaults_to_the_agreed_value():
    for name in SITES:
        assert 'getVariable ["ITW_CLASH_SpotTime",0.9]' in text(name)


def test_courage_is_still_set_where_it_was():
    # The override that proves this pattern was already in use here.
    assert '_unit setSkill ["courage",1]' in text("ITW_Attack.sqf")
    assert '_unit setSkill ["courage",1]' in text("ITW_Teammates.sqf")
