from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_ryd_wait_scope_leak_is_bound_to_waited_group():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    assert 'isNil "HAL_SCargo" || {isNil "RYD_Wait"}' in dual
    assert "ITW_CLASH_Checkbook_fnc_NativeRYDWait = RYD_Wait;" in dual
    assert "RYD_Wait = {" in dual
    assert "private _unitG = _this param [0,grpNull];" in dual
    assert "_this call ITW_CLASH_Checkbook_fnc_NativeRYDWait" in dual
    assert '"ryd-wait-scope-fix-ready"' in dual

    # The transport stall hook only opens HAL's own native unstick gate.
    init = mission("initServer.sqf")
    assert '"InfGetinCheck" + str _carrierGroup' in init
    assert '"HAL-NATIVE-UNSTICK-ARMED"' in init
    for forbidden in [
        "setDestination",
        "setCurrentWaypoint",
        "doMove",
        "commandMove",
        "RYD_WPadd",
    ]:
        # Check only the actual repair block, not unrelated diagnostics/comments.
        start = init.index('if (_wpType == "MOVE"')
        end = init.index('if (time - _lastMoveStall', start)
        assert forbidden not in init[start:end]
