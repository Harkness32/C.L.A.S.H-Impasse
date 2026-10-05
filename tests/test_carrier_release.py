"""A helicopter that lands to unload has to be let go again.

Hark: "helos land, dont take off."

`land "GET OUT"` is sticky. It holds the aircraft on the ground until
`land "NONE"` cancels it, and a NEW WAYPOINT DOES NOT CANCEL IT - neither does
flyInHeight or doMove. HAL issues land 'NONE' in every pickup path
(GoAttInf:185, GoCapture:192, GoRecon:234, and throughout SCargo) but nowhere
after a drop-off, so stock behaviour is that a carrier which lands to unload
sits there until some later dispatch happens to re-task it through SCargo.

That was invisible for as long as the air unload itself was broken: no landing,
no stranded helicopter. Fixing the unload exposed it on every landing path at
once.
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


# --- the helper ----------------------------------------------------------

def test_the_release_waits_for_passengers_then_cancels_the_landing():
    body = code_only(function_body(policy(), "ITW_CLASH_HALParadrop_fnc_ReleaseCarrier"))
    assert 'land "NONE"' in body
    assert "waitUntil" in body
    # Passengers are anyone aboard who is not the carrier's own crew, so no
    # cargo-group bookkeeping is needed and an unstamped squad still counts.
    assert "group _x != _carrierGroup" in body
    assert "crew _carrier" in body


def test_the_release_is_bounded():
    source = policy()
    timeout = int(re.search(r'"ITW_CLASH_HALParadrop_ReleaseTimeout",(\d+)', source).group(1))
    assert timeout > 0, timeout
    body = code_only(function_body(source, "ITW_CLASH_HALParadrop_fnc_ReleaseCarrier"))
    assert "ITW_CLASH_HALParadrop_ReleaseTimeout" in body
    assert "time >= _deadline" in body


def test_the_release_does_not_touch_a_dead_carrier():
    body = code_only(function_body(policy(), "ITW_CLASH_HALParadrop_fnc_ReleaseCarrier"))
    assert "if (isNull _carrier) exitWith {false}" in body
    assert "if (!alive _carrier) exitWith {}" in body


def test_the_release_is_spawned_because_a_waypoint_statement_cannot_wait():
    body = code_only(function_body(policy(), "ITW_CLASH_HALParadrop_fnc_ReleaseCarrier"))
    assert "spawn {" in body


# --- every landing path uses it -----------------------------------------

def test_the_paradrop_modules_own_fallback_releases():
    """Execute's low-altitude fallback lands and returns false; it stranded the
    aircraft exactly like the others."""
    body = code_only(function_body(policy(), "ITW_CLASH_HALParadrop_fnc_Execute"))
    fallback = body[body.index('_carrier land "GET OUT"'):]
    assert "ITW_CLASH_HALParadrop_fnc_ReleaseCarrier" in fallback[:300]


def test_both_hal_overrides_release_on_both_of_their_landing_paths():
    for name in ("GoAttInf.sqf", "GoRecon.sqf"):
        source = read(ADD / "hal" / name)
        # Two landing paths per file: the ordinary LAND branch, and the
        # fallback when a chosen paradrop declines with troops still aboard.
        # Count real calls, not mentions: each is now preceded by an isNil
        # guard that names the same function.
        assert source.count("call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier") == 2, name
        # Every land 'GET OUT' in the unload statements is followed by a
        # release; the land 'NONE' calls above them are HAL's pickup paths.
        for stmt in re.findall(r'_sts = \["true","[^"]*"\]', source):
            if "land 'GET OUT'" in stmt:
                assert "ReleaseCarrier" in stmt, (name, stmt[:120])


def test_hotdrop_releases_before_it_tries_to_egress():
    """flyInHeight and doMove cannot lift an aircraft held by land "GET OUT",
    so the profile ended telling a grounded helicopter to fly away."""
    source = read(MISSION / "ITW_CLASH_HotDrop.sqf")
    # Comments stripped first: the explanation names flyInHeight and doMove,
    # which would otherwise match ahead of the real calls.
    egress = code_only(source[source.index("--- EGRESS"):])
    release = egress.index('_veh land "NONE"')
    assert release < egress.index("flyInHeight")
    assert release < egress.index("doMove")


def test_hotdrop_version_moved():
    assert "ITW_CLASH_HotDropVersion = 6;" in read(MISSION / "ITW_CLASH_HotDrop.sqf")


def test_paradrop_version_moved():
    assert "ITW_CLASH_HALParadropVersion = 2;" in policy()


def test_the_release_call_survives_a_mission_without_the_module():
    """Version-skew and fail-open protection.

    The LAND branch fires whenever _clashAirLift holds, independently of
    _halParadrop - so it runs even when the paradrop module never loaded. An
    unguarded call to an undefined function throws inside the waypoint
    statement, which means the deletewaypoint after it never runs either. That
    is worse than the stranding it was added to fix.

    Guarded, an absent module leaves stock HAL's behaviour exactly as it was.
    It also means a newer addon on an older mission degrades instead of
    erroring, since ReleaseCarrier lives in the mission and the callers live in
    the addon.
    """
    for name in ("GoAttInf.sqf", "GoRecon.sqf"):
        source = read(ADD / "hal" / name)
        calls = source.count("call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier")
        guards = source.count("isNil 'ITW_CLASH_HALParadrop_fnc_ReleaseCarrier'")
        assert calls == 2, (name, calls)
        assert guards == calls, (name, guards, calls)


def test_the_land_branch_does_not_depend_on_paradrop_readiness():
    """It must still land when the paradrop module is missing - landing is the
    fallback, so gating it on paradrop readiness would strand troops."""
    source = read(ADD / "hal" / "GoAttInf.sqf")
    branch = source[source.rindex("if (_clashAirLift) then"):]
    branch = branch[:branch.index("_wp = [_gp,_pos") if "_wp = [_gp,_pos" in branch else len(branch)]
    assert "ITW_CLASH_HALParadropReady" not in branch
    assert "land 'GET OUT'" in branch
