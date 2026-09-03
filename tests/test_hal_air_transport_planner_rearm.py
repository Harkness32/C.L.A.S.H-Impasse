from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def executable_lines(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines()
        if not line.strip().startswith("//")
    )


def test_scargo_stall_repair_rearms_existing_hal_waypoint_only():
    text = (MISSION / "initServer.sqf").read_text(encoding="utf-8")
    executable = executable_lines(text)

    assert 'ITW_CLASH_SCargoAirDiagVersion = 5;' in text
    assert '_phase == "EMBARKED"' in executable
    assert '_wpType == "MOVE"' in executable
    assert '_wpDistance > 100' in executable
    assert '_expectedMode == "DoNotPlan"' in executable
    assert '_carrier land "NONE";' in executable
    assert '_pilot action ["CancelLand",_carrier];' in executable
    assert '_carrierGroup setCurrentWaypoint [_carrierGroup,_wpIndex];' in executable
    assert '_pilot setDestination [_wpPos,"LEADER PLANNED",true];' in executable
    assert '"PILOT-PLANNER-REARMED"' in executable

    start = executable.index('if (_wpType == "MOVE"')
    end = executable.index('if (time - _lastMoveStall', start)
    repair = executable[start:end]
    assert "addWaypoint" not in repair
    assert "RYD_WPadd" not in repair
    assert "doMove" not in repair
    assert "commandMove" not in repair
    assert "deleteWaypoint" not in repair
