import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"

TARGETS = ["GoCapture", "GoRecon", "GoAttInf", "GoRest"]


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def guard() -> str:
    return text("ITW_CLASH_HALWaypointGuardFix.sqf")


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


def test_the_unguarded_read_is_really_there():
    # The defect, as a test. If HAL guards it upstream, this fails first and
    # the patch is no longer needed.
    for name in TARGETS:
        source = (HAL / f"{name}.sqf").read_text(encoding="utf-8", errors="replace")
        assert "_wp0 isEqualTo []" in source, name
        assert 'isNil "_wp0"' not in source, name


def test_gorest_shows_the_shape_plainly():
    # Its initialiser is inside a conditional while two later reads assume it
    # ran - the clearest instance of the same bug.
    source = (HAL / "GoRest.sqf").read_text(encoding="utf-8", errors="replace")
    assert source.count("_wp0 isEqualTo []") == 2
    assert "\n\t_wp0 = [];" in source


def test_the_transformation_produces_valid_sqf_on_real_hal():
    needle = "_wp0 isEqualTo []"
    replacement = 'isNil "_wp0" || {_wp0 isEqualTo []}'
    for name in TARGETS:
        source = (HAL / f"{name}.sqf").read_text(encoding="utf-8", errors="replace")
        hits = source.count(needle)
        patched = source.replace(needle, replacement)
        assert patched.count('isNil "_wp0"') == hits, name
        assert "RYD_WPadd" in patched, name
        assert f"if ({replacement}) then {{_wp0 = [_unitG," in patched, name


def test_every_read_is_replaced_not_just_the_first():
    # GoRest reads _wp0 twice.
    body = function_body(guard(), "ITW_CLASH_HALWaypointGuard_fnc_ReplaceAll")
    assert "while {_searching} do {" in body
    assert "_count = _count + 1" in body


def test_the_guard_is_the_only_change():
    source = guard()
    body = function_body(source, "ITW_CLASH_HALWaypointGuard_fnc_Patch")
    assert '_needle = "_wp0 isEqualTo []"' in body
    assert '_replacement = "isNil ""_wp0"" || {_wp0 isEqualTo []}"' in body
    # An undefined _wp0 takes the same branch an empty one takes.
    assert "RYD_WPadd" in body


def test_it_covers_the_orders_that_read_it():
    source = guard()
    for name in TARGETS:
        assert f'"HAL_{name}"' in source, name


def test_it_is_idempotent_and_fails_safe():
    source = guard()
    body = function_body(source, "ITW_CLASH_HALWaypointGuard_fnc_Patch")
    assert '(_source find "isNil ""_wp0""") >= 0) exitWith {["already-guarded",0]}' in body
    for guard_case in ["not-code", "text-unavailable", "no-read", "recompile-failed", "verification-failed"]:
        assert guard_case in body, guard_case
    assert "stock HAL order retained" in source


def test_a_missing_order_is_not_treated_as_a_failure():
    # A modpack need not ship every order, and HAL may fix one upstream.
    source = guard()
    assert '["absent",0]' in source
    assert '_status in ["recompile-failed","verification-failed","not-code"]' in source


def test_it_loads_scheduled_and_warns_when_it_cannot():
    init = text("init.sqf")
    assert '[] execVM "ITW_CLASH_HALWaypointGuardFix.sqf"' in init
    assert "hal-waypoint-guard-missing" in init
    assert '["ITW_CLASH_HALWaypointGuard","waypoint guard"' in text("ITW_CLASH_DebugPreflight.sqf")


def test_no_exit_with_inside_a_then_block():
    source = re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", guard(), flags=re.S))
    for match in re.finditer(r"then\s*\{", source):
        segment = source[match.end():]
        depth, i = 1, 0
        while i < len(segment) and depth > 0:
            if segment[i] == "{":
                depth += 1
            elif segment[i] == "}":
                depth -= 1
            i += 1
        assert "exitWith" not in segment[:i]
