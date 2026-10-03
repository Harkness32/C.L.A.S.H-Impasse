import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def hal(rel: str) -> str:
    return (HAL / rel).read_text(encoding="utf-8", errors="replace")


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


def test_hal_shares_only_what_its_own_side_has_seen():
    # The guarantee this setting rests on: an enemy nobody observed is never
    # revealed to anyone, so a wider radius is not omniscience.
    rev = hal("HAL/Rev.sqf")
    assert "(_x knowsAbout _KnU) > 0.01" in rev
    assert '_enemies = (_HQ getVariable ["RydHQ_KnEnemies",[]]);' in rev


def test_troops_receive_it_only_inside_the_awareness_radius():
    rev = hal("HAL/Rev.sqf")
    assert "if (RydxHQ_NEAware > 0) then" in rev
    assert "if (_dst < RydxHQ_NEAware) then" in rev
    assert "_x reveal [_KnU,2]" in rev


def test_clash_widens_it_past_hals_default():
    source = text("ITW_CLASH.sqf")
    assert 'RydxHQ_NEAware = missionNamespace getVariable ["ITW_CLASH_HALAwareRadius",1500];' in source
    assert 'publicVariable "RydxHQ_NEAware";' in source
    init = hal("RydHQInit.sqf")
    default = int(re.search(r'RydxHQ_NEAware", *(\d+)', init).group(1))
    ours = int(re.search(r'ITW_CLASH_HALAwareRadius", *(\d+)', source).group(1))
    assert ours > default, (ours, default)


def test_it_is_set_where_the_other_hal_tuning_lives():
    source = text("ITW_CLASH.sqf")
    body_start = source.index("ITW_CLASH_fnc_ConfigureHAL = {")
    body_end = source.index("ITW_CLASH_fnc_CreateCommander = {")
    body = source[body_start:body_end]
    assert "RydxHQ_NEAware" in body
    # And that function is actually called at bootstrap.
    assert '"ITW_CLASH_fnc_ConfigureHAL",' in text("ITW_CLASH_Bootstrap.sqf")


def test_sharing_runs_far_more_often_than_a_hal_cycle():
    # Distribution was never the bottleneck - Rev runs every 20s - so the
    # radius is the only thing worth changing.
    core = hal("HAC_fnc2.sqf")
    assert "(time - _ctRev) >= 20" in core
    assert "[_HQ] call HAL_Rev;" in core


# --------------------------- the asset is told what it was bought to kill

def test_a_bought_counter_is_briefed_on_its_threat():
    source = text("ITW_CLASH_HALThreatCoverage.sqf")
    body = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_Brief")
    assert "_unit reveal [_x,ITW_CLASH_ThreatCoverageBriefLevel]" in body
    assert 'ITW_CLASH_ThreatCoverageBriefLevel",2' in source


def test_the_brief_matches_what_hal_itself_reveals_at():
    source = text("ITW_CLASH_HALThreatCoverage.sqf")
    level = int(re.search(r'ITW_CLASH_ThreatCoverageBriefLevel", *(\d+)', source).group(1))
    rev = hal("HAL/Rev.sqf")
    hal_level = int(re.search(r"_x reveal \[_KnU, *(\d+)\]", rev).group(1))
    # Same brief a group gets for standing near the contact, no better.
    assert level == hal_level, (level, hal_level)


def test_it_reveals_only_that_threats_own_group():
    body = function_body(
        text("ITW_CLASH_HALThreatCoverage.sqf"),
        "ITW_CLASH_HALThreatCoverage_fnc_Brief",
    )
    assert "group effectiveCommander _threat" in body
    assert "forEach units _targetGroup" in body
    # Nothing map-wide: no commander knowledge pool is read here at all.
    assert "RydHQ_KnEnemies" not in body
    assert "allUnits" not in body


def test_the_brief_happens_before_the_dispatcher_runs():
    body = function_body(
        text("ITW_CLASH_HALThreatCoverage.sqf"),
        "ITW_CLASH_HALThreatCoverage_fnc_Offer",
    )
    assert body.index("ITW_CLASH_HALThreatCoverage_fnc_Brief") < body.index("RYD_Dispatcher")


def test_spaa_is_briefed_too():
    body = function_body(
        text("ITW_CLASH_HALThreatCoverage.sqf"),
        "ITW_CLASH_HALThreatCoverage_fnc_Cover",
    )
    assert "ITW_CLASH_SPAAOverwatch_fnc_Adopt" in body
    assert "ITW_CLASH_HALThreatCoverage_fnc_Brief" in body


def test_the_offer_line_records_what_was_briefed():
    body = function_body(
        text("ITW_CLASH_HALThreatCoverage.sqf"),
        "ITW_CLASH_HALThreatCoverage_fnc_Offer",
    )
    assert "_briefed" in body
