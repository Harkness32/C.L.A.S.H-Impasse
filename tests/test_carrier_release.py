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


def test_central_unload_owns_every_normal_and_fallback_release():
    source = read(MISSION / "ITW_CLASH_HALUnload.sqf")
    body = code_only(function_body(source, "ITW_CLASH_HALUnload_fnc_Unload"))

    # Ordinary LAND and permitted declined-paradrop fallback both go through
    # the single release adapter. Unsafe corridors instead use NO_LAND.
    assert body.count("ITW_CLASH_HALUnload_fnc_Release") >= 2
    assert '_carrier land "GET OUT"' in body
    assert '"LAND_FALLBACK"' in body
    assert '"NO_LAND"' in body


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
    # Exact number pinned in tests/test_hotdrop_scargo_interlock.py.
    version = int(re.search(r"ITW_CLASH_HotDropVersion = (\d+);",
                            read(MISSION / "ITW_CLASH_HotDrop.sqf")).group(1))
    assert version >= 6, version


def test_paradrop_version_moved():
    # Exact number pinned in tests/test_paradrop_origin_guard.py, so a bump
    # touches one test. Here it only has to be at or past the release work.
    version = int(re.search(r"ITW_CLASH_HALParadropVersion = (\d+);", policy()).group(1))
    assert version >= 2, version


def test_central_release_adapter_survives_a_missing_paradrop_module():
    source = read(MISSION / "ITW_CLASH_HALUnload.sqf")
    release = code_only(function_body(source, "ITW_CLASH_HALUnload_fnc_Release"))
    assert 'isNil "ITW_CLASH_HALParadrop_fnc_ReleaseCarrier"' in release
    assert "call ITW_CLASH_HALParadrop_fnc_ReleaseCarrier" in release

    # The generated waypoint also has its own fail-open path if the entire
    # centralized owner is absent on a version-skewed mission.
    patch = function_body(source, "ITW_CLASH_HALUnload_fnc_PatchSource")
    assert 'isNil ""ITW_CLASH_HALUnload_fnc_Unload""' in patch
    assert 'isNil ""ITW_CLASH_HALParadrop_fnc_ReleaseCarrier""' in patch


def test_land_mode_does_not_depend_on_paradrop_readiness():
    source = read(MISSION / "ITW_CLASH_HALUnload.sqf")
    mode = code_only(function_body(source, "ITW_CLASH_HALUnload_fnc_Mode"))
    # Param 0 is resolved before readiness can force a normal COLD/CONTESTED
    # lift into some undefined state. Unsafe states become NO_LAND instead.
    assert mode.index("if (_param == 0)") < mode.index("ITW_CLASH_HALParadropReady")
    assert 'if (_noLand) then {"NO_LAND"} else {"LAND"}' in mode
