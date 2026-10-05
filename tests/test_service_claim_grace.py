"""A helicopter handed to HAL at base must outlive HAL's planning pass.

Measured, 7:15-7:17:

    7:15:32  service-physical-registered  SVC-3 AIR B_Heli_Light_01_F "impasse-handoff"
    7:16:20  service-hal-return-zone-entered  SVC-3 ... 7, 300
    7:16:30  service-virtualized  SVC-3 ... "hal-returned-home"

Seven metres from home. It never left. Two more died at 60s and 59s the same
way. InitialStorageGrace was 45s and IdleGrace 10s, so an unclaimed asset lived
55 seconds against a HAL planning pass of about sixty - a race it usually lost
rather than sometimes.

It is also why the player side looked like it bought no aircraft: it bought
them and lost them inside a minute, before anything could count or dispatch
them.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def lifecycle() -> str:
    return (MISSION / "ITW_CLASH_ServiceLifecycle.sqf").read_text(
        encoding="utf-8", errors="replace"
    )


def setting(source: str, name: str) -> int:
    return int(re.search(rf'"{name}",(\d+)', source).group(1))


def test_an_unclaimed_asset_outlives_hals_planning_pass():
    """The whole fix. HAL plans on roughly a sixty second cycle, so anything
    at or under that is a coin flip the asset usually loses."""
    source = lifecycle()
    initial = setting(source, "ITW_CLASH_ServiceInitialStorageGrace")
    idle = setting(source, "ITW_CLASH_ServiceIdleGrace")
    assert initial + idle > 180, (initial, idle)


def test_the_grace_allows_several_passes_not_just_one():
    source = lifecycle()
    assert setting(source, "ITW_CLASH_ServiceInitialStorageGrace") >= 240


def test_a_tasked_asset_is_never_subject_to_the_initial_grace():
    """taskSeen is set when the asset is busy, carrying, or has left the
    storage radius, and it bypasses this path entirely."""
    source = lifecycle()
    assert '_entry set ["taskSeen",true];' in source
    assert 'private _taskSeen = _entry getOrDefault ["taskSeen",false];' in source
    assert "if (!_taskSeen && {" in source


def test_the_drain_still_exists():
    """The intent was right - an unused truck parked forever is strategic
    stock, not a permanent decoration. Only the number was wrong."""
    source = lifecycle()
    assert "ITW_CLASH_ServiceIdleGrace" in source
    assert '[_i,"hal-returned-home"] call ITW_CLASH_Service_fnc_Retire;' in source


def test_the_return_zone_line_says_whether_it_ever_left():
    """A never-tasked asset a minute old sitting seven metres from home was
    never 'returning', and the log said nothing that would show it."""
    source = lifecycle()
    block = source[source.index('["hal-return-zone-entered",['):]
    block = block[:block.index("]] call")]
    assert "round (time - _spawnedAt)" in block
    assert "_taskSeen" in block


def test_the_storage_radius_is_why_seven_metres_counted_as_home():
    source = lifecycle()
    assert setting(source, "ITW_CLASH_ServiceRTBAirRadius") >= 300
