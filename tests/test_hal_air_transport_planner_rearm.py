from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def executable_lines(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines()
        if not line.strip().startswith("//")
    )


def test_scargo_stall_repair_combines_native_hal_unstick_with_landing_release():
    text = (MISSION / "initServer.sqf").read_text(encoding="utf-8")
    executable = executable_lines(text)

    assert 'ITW_CLASH_SCargoAirDiagVersion = 7;' in text
    assert '_phase == "EMBARKED"' in executable
    assert '_wpType == "MOVE"' in executable
    assert '_wpDistance > 100' in executable
    assert '_expectedMode == "DoNotPlan"' in executable
    assert '"InfGetinCheck" + str _carrierGroup' in executable
    assert '_carrierGroup setVariable [_flag,true];' in executable
    assert '_carrier land "NONE";' in executable
    assert '_pilot action ["CancelLand",_carrier];' in executable
    assert '"HAL-NATIVE-UNSTICK-ARMED-LANDING-RELEASED"' in executable
    assert '["lastMoveOR",_carrier getVariable ["LastMoveOR",0]]' in executable

    start = executable.index('if (_wpType == "MOVE"')
    end = executable.index('if (time - _lastMoveStall', start)
    repair = executable[start:end]
    for forbidden in [
        "setDestination",
        "setCurrentWaypoint",
        "addWaypoint",
        "RYD_WPadd",
        "doMove",
        "commandMove",
        "deleteWaypoint",
    ]:
        assert forbidden not in repair
