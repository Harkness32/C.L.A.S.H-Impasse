import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def dispatcher_body() -> str:
    """RYD_Dispatcher's own source, comments stripped the way compiling it does."""
    lines = (HAL / "HAC_fnc.sqf").read_text(encoding="utf-8", errors="replace").splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith("RYD_Dispatcher"))
    end = next(i for i, line in enumerate(lines[start + 1:], start + 1)
               if re.match(r"^RYD_\w+\s*=", line))
    return re.sub(r"//[^\n]*", "", "\n".join(lines[start:end]))


def test_the_defect_is_still_the_one_we_patch():
    # The AIR/AIRCAP branch gates on _AAthreat and then measures the distance to
    # the nearest _ATthreat. If HAL ever fixes this upstream the patch must go.
    body = dispatcher_body()
    gate = body.rfind("_AAthreat")
    assert gate >= 0
    assert "count _AAthreat" in body[gate - 40:gate + 20]
    tail = body[gate + len("_AAthreat"):]
    assert tail.find("_ATthreat") >= 0, "upstream already measures AA distance"


def test_patch_anchors_uniquely_on_the_air_branch_measurement():
    body = dispatcher_body()
    gate = body.rfind("_AAthreat")
    tail = body[gate + len("_AAthreat"):]
    target = tail.find("_ATthreat")
    # Exactly one threat-list reference after the AA gate, and it is the
    # argument of that gate's own RYD_CloseEnemyB call.
    assert tail[target + len("_ATthreat"):].find("_ATthreat") < 0
    assert "RYD_CloseEnemyB" in tail[target + len("_ATthreat"):][:80]
    assert "_chVP" in tail[:target]


def test_fix_reads_and_recompiles_the_function_without_touching_nr6():
    fix = text("ITW_CLASH_HALDispatcherAAFix.sqf")
    assert "toString RYD_Dispatcher" in fix
    assert "RYD_Dispatcher = _compiled;" in fix
    assert "compile _patched" in fix
    # No HAL file is read or rewritten: the function's own compiled text is the
    # only source, so nothing under NR6 Hal/ has to ship with the change.
    assert "RYD_Path" not in fix
    assert "preprocessFileLineNumbers" not in fix
    assert "copyToClipboard" not in fix


def test_fix_refuses_an_unrecognised_or_ambiguous_dispatcher():
    fix = text("ITW_CLASH_HALDispatcherAAFix.sqf")
    for reason in [
        "dispatcher-signature-missing",
        "aa-gate-missing",
        "aa-reference-ambiguous",
        "aa-reference-context-missing",
        "recompile-failed",
        "verification-failed",
        "hal-runtime-bind-timeout",
    ]:
        assert f'"{reason}"' in fix
    assert "_AAriskResign" in fix
    assert "RYD_CloseEnemyB" in fix


def test_fix_is_idempotent_and_reports_an_already_fixed_dispatcher():
    fix = text("ITW_CLASH_HALDispatcherAAFix.sqf")
    assert '"already-fixed"' in fix
    # An already-correct dispatcher is a success, not a failure.
    already = fix.index('"already-fixed"')
    assert "ITW_CLASH_HALDispatcherAAFixReady = true;" in fix[:already]


def test_fix_survives_a_function_text_that_carries_its_own_braces():
    fix = text("ITW_CLASH_HALDispatcherAAFix.sqf")
    assert "ITW_CLASH_HALDispatcherAAFix_fnc_Unwrap" in fix
    assert 'isEqualTo "{"' in fix
    assert 'isEqualTo "}"' in fix


def test_fix_is_loaded_scheduled_so_it_can_wait_for_hals_runtime_bind():
    init = text("init.sqf")
    assert '[] execVM "ITW_CLASH_HALDispatcherAAFix.sqf";' in init
    assert "hal-dispatcher-aa-fix-missing" in init
