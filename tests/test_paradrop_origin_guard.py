"""A squad must never be put out where it got in.

run7: the base-embark fast path finally worked - eight men teleported into a
Huron at base 5 - the paradrop was selected, and then

    Hark: "landed at base and kicked them out."

Execute waited 8 seconds for the carrier to reach MinAltitude (55m). If the
waypoint statement fires while the aircraft is still on the ground at base, it
cannot climb that far from a standstill in 8s, so the deadline expired at
altitude ~0 and the low-altitude fallback ran `land "GET OUT"` right there.

This is the same fault HotDrop had - troops out over their own pickup point -
and the same cure: require the lift to have actually gone somewhere.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
ADD = ROOT / "CLASH HAL Additions" / "addons" / "clash_hal_additions"


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


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


def policy() -> str:
    return read(MISSION / "ITW_CLASH_HALParadrop.sqf")


def test_a_low_carrier_still_at_its_origin_does_not_unload():
    body = code_only(function_body(policy(), "ITW_CLASH_HALParadrop_fnc_Execute"))
    # Anchor on the guard's own log reason, not the first mention of the
    # variable - it is also cleared earlier in the function.
    end = body.index("still-at-origin")
    guard = body[body.rindex("if (", 0, end):end + 200]
    assert "ITW_CLASH_HALParadrop_MinRun" in guard
    assert "distance2D _origin" in guard
    assert "still-at-origin" in guard
    # And it must NOT land: landing is what dumped them at base.
    assert 'land "GET OUT"' not in guard


def test_the_origin_guard_runs_before_the_landing_fallback():
    body = code_only(function_body(policy(), "ITW_CLASH_HALParadrop_fnc_Execute"))
    assert body.index("still-at-origin") < body.index('_carrier land "GET OUT"')


def test_declining_at_origin_keeps_the_cargo_stamp():
    """So the carrier keeps its cargo and the destination unload still happens.
    Clearing it would orphan the squad aboard with nothing owning the drop."""
    body = code_only(function_body(policy(), "ITW_CLASH_HALParadrop_fnc_Execute"))
    guard = body[body.index("still-at-origin") - 600:body.index("still-at-origin") + 400]
    assert "HALParadropCargoGroup" not in guard


def test_the_climb_wait_is_long_enough_for_a_standing_start():
    source = policy()
    timeout = int(re.search(r'"ITW_CLASH_HALParadrop_ClimbTimeout",(\d+)', source).group(1))
    assert timeout >= 30, timeout
    body = code_only(function_body(source, "ITW_CLASH_HALParadrop_fnc_Execute"))
    assert "time + ITW_CLASH_HALParadrop_ClimbTimeout" in body
    assert "time + 8" not in body


def test_the_min_run_exceeds_a_base_footprint():
    source = policy()
    min_run = int(re.search(r'"ITW_CLASH_HALParadrop_MinRun",(\d+)', source).group(1))
    embark = read(MISSION / "ITW_CLASH_HALCargoDiceFix.sqf")
    base_radius = int(re.search(r'"ITW_CLASH_BaseEmbarkRadius",(\d+)', embark).group(1))
    # A drop must be further from the pickup than the base that pickup happened
    # at, or it can still land inside the same installation.
    assert min_run > base_radius, (min_run, base_radius)


def test_the_origin_is_stamped_at_the_execution_time_unload_owner():
    unload = read(MISSION / "ITW_CLASH_HALUnload.sqf")
    # Both PARADROP and HOT_PARADROP stamp the real carrier departure before
    # Execute is called. No order file predicts the future at build time.
    assert unload.count('setVariable ["ITW_CLASH_HALParadropOrigin",_origin]') == 2
    assert 'getVariable ["START" + str _carrierGroup,[]]' in unload
    assert unload.count("ITW_CLASH_HALParadrop_fnc_Execute") >= 2


def test_the_origin_is_cleared_with_the_cargo_stamp():
    policy_source = read(MISSION / "ITW_CLASH_HALParadrop.sqf")
    unload = read(MISSION / "ITW_CLASH_HALUnload.sqf")

    # Execute owns successful/empty cleanup; the centralized owner owns the
    # NO_LAND cleanup after a refused unsafe drop.
    assert policy_source.count('"ITW_CLASH_HALParadropCargoGroup",nil') == policy_source.count(
        '"ITW_CLASH_HALParadropOrigin",nil'
    )
    assert unload.count('"ITW_CLASH_HALParadropCargoGroup",nil') == unload.count(
        '"ITW_CLASH_HALParadropOrigin",nil'
    )


def test_every_execute_exit_now_says_why():
    body = code_only(function_body(policy(), "ITW_CLASH_HALParadrop_fnc_Execute"))
    assert "exitWith {false}" not in body
    for reason in ("carrier-gone", "no-cargo-group", "nobody-aboard",
                   "carrier-lost-in-climb", "still-at-origin"):
        assert f'"{reason}"' in body, reason


def test_paradrop_version_moved_to_four():
    assert "ITW_CLASH_HALParadropVersion = 4;" in policy()
