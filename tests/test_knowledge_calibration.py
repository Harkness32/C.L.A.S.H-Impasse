"""Knowledge layer v3: the diagnostics the 2026-10-15 review asked for.

The run's truth diagnostic put WEST|STATIC 100% outside its envelope with a
mean error of 0 m: statics get speed 0, the engine reports an error near 0,
so R was 0 and any sub-metre difference was a miss. 743 reports were thrown
away for a lastSeen off the time clock with no record of why. And the window
means could not give a percentile to calibrate the movement allowances
against. None of this changes a decision except the R floor.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code(name: str) -> str:
    source = (MISSION / name).read_text(encoding="utf-8")
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


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


def knowledge() -> str:
    return code("ITW_CLASH_Knowledge.sqf")


def test_no_envelope_is_smaller_than_the_floor():
    source = knowledge()
    assert 'ITW_CLASH_KnowledgeMinUncertainty",5]' in source
    body = function_body(source, "ITW_CLASH_Knowledge_fnc_Uncertainty")
    assert body.rstrip("};\n ").endswith("max ITW_CLASH_KnowledgeMinUncertainty")


def test_the_allowances_are_unchanged_until_data_sets_them():
    source = knowledge()
    assert 'ITW_CLASH_KnowledgeSpeedStatic",0]' in source
    assert 'ITW_CLASH_KnowledgeSpeedInfantry",2]' in source
    assert 'ITW_CLASH_KnowledgeSpeedVehicle",8]' in source


def test_a_rejected_report_records_why():
    report = function_body(knowledge(), "ITW_CLASH_Knowledge_fnc_ReadReport")
    start = report.index("if (_lastSeen < 0 || {_lastSeen > (time + 1)}) exitWith {")
    reject = report[start:report.index("if !(_position isEqualType [] && {count _position >= 2})")]
    for field in ["_lastSeen,", "_lastSeen - time,", "_lastSeen - serverTime,", "_lastSeen - diag_tickTime,",
                  "_byUnit isEqualTo true,", "_recoverable >= 0"]:
        assert field in reject, field
    assert "count ITW_CLASH_KnowledgeClockSamples < ITW_CLASH_KnowledgeClockSampleCap" in reject
    # Still discarded: the branch returns no report and touches no record.
    assert reject.rstrip().endswith("[]\n    };"), reject[-40:]
    assert "_record" not in reject


def test_the_clock_line_splits_negative_from_future():
    summary = function_body(knowledge(), "ITW_CLASH_Knowledge_fnc_Summary")
    line = summary[summary.index('["clock-anomaly",['):]
    assert "private _negative = _samples select {(_x#0) < 0};" in summary
    assert "private _future = _samples select {(_x#0) >= 0};" in summary
    for spread in ["[_negative apply {_x#0}]", "[_future apply {_x#1}]",
                   "[_future apply {_x#2}]", "[_future apply {_x#3}]"]:
        assert spread in line, spread
    assert "[round time,round serverTime,round diag_tickTime]" in line
    assert "ITW_CLASH_KnowledgeClockSamples = [];" in summary


def test_truth_keeps_per_sample_speeds_and_stays_read_only():
    source = knowledge()
    truth = function_body(source, "ITW_CLASH_Knowledge_fnc_TruthSample")
    assert "(speed _entity) / 3.6" in truth
    assert '_record getOrDefault ["moving",false]' in truth
    assert "_age >= ITW_CLASH_KnowledgeTruthMinAge" in truth
    assert "_record set" not in truth
    # The entity's real state is read in the diagnostic and nowhere else.
    assert source.count("speed _entity") == 1
    assert source.count("getPosATL _entity") == 1


def test_the_calibration_line_reports_percentiles_by_motion():
    summary = function_body(knowledge(), "ITW_CLASH_Knowledge_fnc_Summary")
    line = summary[summary.index('["truth-speed",['):]
    assert "[_implied] call ITW_CLASH_Knowledge_fnc_Spread" in line
    assert "[_impliedMoving] call ITW_CLASH_Knowledge_fnc_Spread" in line
    assert "[_samples apply {_x#3}] call ITW_CLASH_Knowledge_fnc_Spread" in line
    assert "ITW_CLASH_KnowledgeTruthSamples = createHashMap;" in summary


def spread(values):
    """Python mirror of ITW_CLASH_Knowledge_fnc_Spread."""
    if not values:
        return []
    s = sorted(values)
    last = len(s) - 1
    at = lambda q: s[max(0, min(last, int(q * last)))]
    return [round(v * 10) / 10 for v in (s[0], at(0.5), at(0.9), s[last])]


def test_spread_math():
    body = function_body(knowledge(), "ITW_CLASH_Knowledge_fnc_Spread")
    assert "(floor (_q * _last)) max 0 min _last" in body
    assert spread([]) == []
    assert spread([3]) == [3, 3, 3, 3]
    assert spread(list(range(11))) == [0, 5, 9, 10]
