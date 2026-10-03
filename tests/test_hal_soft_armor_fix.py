import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def fix() -> str:
    return text("ITW_CLASH_HALDispatcherSoftArmorFix.sqf")


def dispatcher_body() -> str:
    src = (HAL / "HAC_fnc.sqf").read_text(encoding="utf-8", errors="replace")
    i = src.index("RYD_Dispatcher")
    start = src.index("{", i)
    depth = 0
    j = start
    while j < len(src):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return src[start + 1:j]


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


def test_only_armour_currently_checks_for_armour():
    # The defect, as a test. If HAL ever widens this gate the patch is no
    # longer needed and this fails first.
    body = dispatcher_body()
    assert "(_chosen in (_LArmorG + _HArmorG)) and ((count _ATthreat) > 0)" in body


def test_the_anchor_is_unique_in_both_raw_and_normalised_text():
    body = dispatcher_body()
    for variant in (body, " ".join(body.split())):
        pairs = []
        scan = 0
        while True:
            hit = variant.find("_LArmorG", scan)
            if hit < 0:
                break
            after = variant[hit + len("_LArmorG"):hit + len("_LArmorG") + 24]
            plus, h = after.find("+"), after.find("_HArmorG")
            if plus >= 0 and h > plus:
                pairs.append(hit)
            scan = hit + len("_LArmorG")
        assert len(pairs) == 1, (len(pairs), variant is body)


def test_the_patch_appends_rather_than_rewrites():
    source = fix()
    assert '+ " + ITW_CLASH_SoftVehicleGroups" +' in source
    # A rewrite of the condition would be a far larger surface to get wrong.
    assert "_LArmorG + _HArmorG)) and" not in source


def test_it_refuses_an_ambiguous_or_unrecognised_dispatcher():
    source = fix()
    for guard in [
        "dispatcher-signature-missing",
        "armor-pool-pair-not-unique",
        "armor-pool-context-missing",
        "recompile-failed",
        "verification-failed",
        "hal-runtime-bind-timeout",
    ]:
        assert guard in source, guard
    assert "if ((count _pairs) != 1) exitWith {" in source
    # And a miss keeps stock HAL rather than half-patching.
    assert "stock HAL dispatcher retained" in source


def test_it_is_idempotent():
    source = fix()
    assert '(_source find "ITW_CLASH_SoftVehicleGroups") >= 0) exitWith' in source
    assert "already-fixed" in source


def test_the_global_exists_before_the_patch_can_run():
    # A nil global inside the dispatcher would throw on every dispatch.
    source = fix()
    assert source.index("ITW_CLASH_SoftVehicleGroups = missionNamespace getVariable") < source.index(
        'RYD_Dispatcher = _compiled'
    )
    refresh = function_body(source, "ITW_CLASH_HALSoftArmor_fnc_Refresh")
    assert "ITW_CLASH_SoftVehicleGroups = _soft;" in refresh


def test_dismounted_infantry_is_never_swept_in():
    # An AT team on foot is a legitimate answer to a tank, and a man's own
    # config armour would grade 0.
    body = function_body(fix(), "ITW_CLASH_HALSoftArmor_fnc_IsSoftMounted")
    assert "if (_veh isEqualTo _leader) exitWith {false};" in body
    assert "ITW_CLASH_AirPicture_fnc_ProtectionGrade) < 1" in body
    assert 'isNil "ITW_CLASH_AirPicture_fnc_ProtectionGrade"' in body


def test_the_list_is_rebuilt_not_mutated():
    # A group that dismounts or dies leaves on the next pass with no
    # bookkeeping to go stale.
    body = function_body(fix(), "ITW_CLASH_HALSoftArmor_fnc_Refresh")
    assert "private _soft = [];" in body
    assert "pushBackUnique" in body


def test_it_covers_both_commanders():
    body = function_body(fix(), "ITW_CLASH_HALSoftArmor_fnc_Commanders")
    assert "ITW_PlayerSide,ITW_EnemySide" in body
    assert "select {!isNull _x}" in body


def test_it_loads_scheduled_and_warns_when_it_cannot():
    init = text("init.sqf")
    assert '[] execVM "ITW_CLASH_HALDispatcherSoftArmorFix.sqf"' in init
    assert "hal-soft-armor-fix-missing" in init


def test_the_preflight_knows_about_it():
    assert '["ITW_CLASH_HALSoftArmorFix","soft-armor fix"' in text("ITW_CLASH_DebugPreflight.sqf")


def test_no_exit_with_inside_a_then_block():
    source = re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", fix(), flags=re.S))
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
