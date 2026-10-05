"""A FOB the front has left behind keeps its sentries, and their slots.

Hark, with a map: "queen, where I'm at, far left of the map, large bluefor
concentration. Front has shifted to the far east now. Xanthiope and Golf are
active, with golf being a rear base."

Queen is neither forward nor rear any more, and it is still holding a large
concentration. Those slots are what stop fresh troops spawning at the FOBs that
are now live, because ITW_AtkAiCount is a cap measured against living units.

This is the DESTRUCTIVE sibling of the locked-objective release in
ITW_CLASH.sqf, and the distinction is the whole design:

  locked objective -> RELEASE, the ground still matters and the groups are
                      handed back to HAL to use elsewhere
  stale FOB        -> WIPE, the ground does not matter and the point is the
                      slots, not the men
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def read(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace")


def sweep() -> str:
    return read("ITW_CLASH_FOBGarrisonSweep.sqf")


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


# ------------------------------------------------- who decides what is stale

def test_the_campaign_graph_decides_not_this_module():
    """Generation_fnc_Resolve already owns forward/rear. A second geography
    model here could disagree with the first and delete the wrong base."""
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_LiveBases"))
    assert "ITW_CLASH_Generation_fnc_Resolve" in body
    assert '"forwardBase"' in body
    assert '"rearBase"' in body


def test_air_and_ground_nodes_are_both_kept():
    """A side can stage armour from one base and aircraft from another; wiping
    the one that is only an air node is exactly the mistake to avoid."""
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_LiveBases"))
    for profile in ("FORWARD", "REAR", "FORWARD_AIR", "REAR_AIR"):
        assert f'"{profile}"' in body, profile


def test_an_unresolvable_graph_deletes_nothing():
    """Fail closed. This is the one layer where fail-open destroys things."""
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_LiveBases"))
    assert 'if (isNil "ITW_CLASH_Generation_fnc_Resolve") exitWith {[-1]}' in body
    assert "if (_live isEqualTo []) exitWith {[-1]}" in body
    side = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide"))
    assert "if (_live isEqualTo [-1]) exitWith {" in side
    assert "graph-unresolved" in side


# ------------------------------------------------------------ what gets wiped

def test_only_garrison_members_are_candidates():
    """Garrison membership is what HAL's own leash reads, so it is the
    definition of manning the FOB. A group merely standing near a stale FOB is
    passing through."""
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide"))
    assert '_hq getVariable ["RydHQ_Garrison",[]]' in body


def test_only_units_inside_the_radius():
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide"))
    assert "distance2D _basePos <= ITW_CLASH_FOBGarrisonSweepRadius" in body


def test_unspawned_bases_are_not_swept():
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide"))
    assert "ITW_BASE_SPAWNED" in body


# --------------------------------------------- what is never wiped, and why

def test_the_exclusions_are_broad_because_deletion_is_final():
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_IsSweepable"))
    assert "isPlayer _unit" in body
    assert "findIf {isPlayer _x}" in body
    assert "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" in body
    assert "ITW_CLASH_fnc_IsCommanderGroup" in body
    assert "ITW_CLASH_FOBAirDefence" in body


def test_a_crewed_vehicle_is_never_destroyed_for_a_slot():
    """An asset the checkbook paid for is worth more than an infantry slot."""
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_IsSweepable"))
    assert "if (vehicle _unit != _unit) exitWith {false}" in body
    assert 'if !(_unit isKindOf "CAManBase") exitWith {false}' in body


def test_there_is_a_ceiling_per_front_change():
    """A graph that goes wrong must not be able to empty the map in one pass."""
    source = sweep()
    assert '"ITW_CLASH_FOBGarrisonSweepMax",24' in source
    body = code_only(function_body(source, "ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide"))
    assert "_wiped >= ITW_CLASH_FOBGarrisonSweepMax" in body
    assert "sweep-capped" in body


def test_emptied_groups_leave_hals_garrison_list():
    """An empty group lingering in RydHQ_Garrison is a slot HAL believes it
    still has."""
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide"))
    assert '_hq setVariable ["RydHQ_Garrison",_survivors]' in body
    assert "deleteGroup _x" in body


# ------------------------------------------------------------- when it runs

def test_it_triggers_on_a_front_change_and_lets_the_graph_settle():
    source = sweep()
    assert "ITW_ZoneIndex != _lastZone" in source
    assert "front-changed" in source
    # Resolving mid-transition is how the wrong base gets called stale.
    watch = source[source.index("ITW_ZoneIndex != _lastZone"):]
    assert "sleep 10" in watch[:600]


def test_both_sides_are_swept():
    body = code_only(function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_Sweep"))
    assert "ITW_PlayerSide" in body
    assert "ITW_EnemySide" in body


def test_the_radius_can_be_judged_from_the_log():
    """There is no canonical base radius to borrow, so the default is a
    judgement and the near-misses are reported rather than guessed at twice."""
    source = sweep()
    assert '"ITW_CLASH_FOBGarrisonSweepRadius",300' in source
    assert "radius-near-miss" in source
    assert "_nearMiss" in source


def test_the_logger_does_not_call_itself():
    """It did. The LoudDebug branch recursed into fnc_Log instead of Emit,
    which is an unbounded recursion on the first logged event."""
    body = function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_Log")
    assert "call ITW_CLASH_LoudDebug_fnc_Emit" in body
    assert body.count("ITW_CLASH_FOBGarrisonSweep_fnc_Log") == 1, "the definition only"


def test_wired_into_init():
    init = read("init.sqf")
    assert '"ITW_CLASH_FOBGarrisonSweep.sqf"' in init


def test_it_can_be_switched_off():
    assert "if (!ITW_CLASH_FOBGarrisonSweepEnabled) exitWith {" in sweep()


# ----------------------------------------- the two systems stay distinguished

def test_release_and_wipe_are_different_owners():
    """The locked-objective path releases; this one deletes. Confusing them
    either throws away men who are still useful or leaves slots locked up."""
    assert "ITW_CLASH_fnc_ReleaseLockedGarrison" in read("ITW_CLASH.sqf")
    assert "deleteVehicle" not in code_only(
        function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison")
    )
    assert "deleteVehicle _x" in code_only(
        function_body(sweep(), "ITW_CLASH_FOBGarrisonSweep_fnc_SweepSide")
    )
