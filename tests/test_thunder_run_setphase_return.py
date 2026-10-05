from pathlib import Path

MISSION = Path(__file__).resolve().parents[1] / "13715765820790864929_legacy"


def set_phase(name: str) -> str:
    source = (MISSION / name).read_text(encoding="utf-8")
    start = source.index("ITW_CLASH_ThunderRun_fnc_SetPhase = {")
    return source[start:source.index("\n};", start)]


def test_base_set_phase_returns_a_value_for_its_wrappers():
    # Live run: the base ended on a Log call, returned nil, and both wrappers
    # (ThunderRun.sqf, ThunderRun_Tuning.sqf) errored reading `_result`.
    assert set_phase("ITW_CLASH_ThunderRun_Core.sqf").rstrip().endswith("true")
    for wrapper in ["ITW_CLASH_ThunderRun.sqf", "ITW_CLASH_ThunderRun_Tuning.sqf"]:
        body = set_phase(wrapper)
        assert "private _result = [_state,_phase] call" in body
        assert body.rstrip().endswith("_result")
