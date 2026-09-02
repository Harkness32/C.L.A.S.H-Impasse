from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"

CAPTURE_READ = '_Trg getVariable ("Capturing" + (str _Trg) + (str _HQ));'
GUARDED_CAPTURE_READ = (
    '_Trg getVariable [("Capturing" + (str _Trg) + (str _HQ)),[1,_amountG]];'
)


def source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_hal_logistics_wrappers_preserve_defined_native_results_and_default_nil() -> None:
    text = source(MISSION / "ITW_CLASH_HALLogistics.sqf")

    assert "ITW_CLASH_HALLogisticsVersion = 3;" in text
    assert text.count("private _result = true;") == 3
    assert text.count("private _nativeResult = _this call") == 3
    assert text.count('if !(isNil "_nativeResult") then {_result = _nativeResult};') == 3
    assert "private _result = _this call ITW_CLASH_HALLogistics_fnc_NativeSupp" not in text
    assert "nativeNilReturnSafe=true" in text


def test_ground_capture_cleanup_survives_missing_objective_state() -> None:
    text = source(HAL / "GoCapture.sqf")

    assert CAPTURE_READ not in text
    assert text.count(GUARDED_CAPTURE_READ) == 11


def test_naval_capture_cleanup_has_the_same_state_guard() -> None:
    text = source(HAL / "GoCaptureNaval.sqf")

    assert CAPTURE_READ not in text
    assert text.count(GUARDED_CAPTURE_READ) == 5
