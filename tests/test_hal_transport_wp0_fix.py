from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def executable_lines(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines()
        if not line.strip().startswith("//")
    )


def test_workshop_hal_goattinf_wp0_is_repaired_before_execution_guard_capture():
    execution = mission("ITW_CLASH_ServiceExecutionGuards.sqf")

    assert 'RYD_Path + "HAL\\\\GoAttInf.sqf"' in execution
    assert 'preprocessFileLineNumbers _goAttInfPath' in execution
    assert '_goAttInfSource find "_wp0 isEqualTo []"' in execution
    assert '_goAttInfSource find "_wp0 = [];"' in execution
    assert '+ "_wp0 = [];_wp = [];\\n"' in execution
    assert 'HAL_GoAttInf = compile _goAttInfSource;' in execution
    assert '"GoAttInf-wp0-fix"' in execution

    patch_at = execution.index("private _goAttInfPath")
    capture_at = execution.index(
        "ITW_CLASH_ServiceExecution_fnc_GoAttInfBase = HAL_GoAttInf;"
    )
    assert patch_at < capture_at


def test_scargo_air_diagnostics_are_observer_only_again():
    init_server = executable_lines(mission("initServer.sqf"))
    assert "CancelLand" not in init_server
    assert ' land "NONE"' not in init_server
    assert "LANDING-LATCH-CLEARED" not in init_server
