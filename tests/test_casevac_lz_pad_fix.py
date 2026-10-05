import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_lz_pad_fix_is_started_after_air_ops():
    init = text("init.sqf")
    assert 'execVM "ITW_CLASH_CASEVAC_AirOpsFix.sqf"' in init
    assert 'execVM "ITW_CLASH_CASEVAC_LZPadFix.sqf"' in init
    assert init.index('execVM "ITW_CLASH_CASEVAC_AirOpsFix.sqf"') < init.index('execVM "ITW_CLASH_CASEVAC_LZPadFix.sqf"')


def test_casevac_uses_invisible_helipad_and_30m_infantry_rally():
    source = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    assert '"Land_HelipadEmpty_F"' in source
    # Was an exact pin on 2. The floor is what this test cares about.
    version = int(
        re.search(r"ITW_CLASH_CASEVAC_LZPadFixVersion = (\d+);", source).group(1)
    )
    assert version >= 2, version
    assert "ITW_CLASH_CASEVAC_InfantryRallyOffset = 30;" in source
    assert '_rally = _lz getPos [ITW_CLASH_CASEVAC_InfantryRallyOffset,_rallyBearing];' in source
    assert '_group addWaypoint [_rally,8]' in source
    assert '"lz-pad-created"' in source


def test_helicopter_is_pinned_to_pad_through_inbound_and_boarding():
    source = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    assert '_heli landAt [_pad,"GetIn",_wait,true]' in source
    assert 'if !(_state in ["inbound","boarding"]) exitWith {};' in source
    assert '_padDistance <= 650' in source
    # The pad is kept alive for the whole of boarding; the LANDING is
    # commanded once. Those are different things, and conflating them is
    # what made the aircraft re-approach every two seconds.
    assert '(!_commanded || {_lostApproach})' in source
    assert '"lz-pad-locked"' in source
    assert "pinStates=inbound+boarding" in source
    assert 'if !(_state isEqualTo "inbound") exitWith {};' not in source


def test_pad_is_cleaned_only_after_extraction_leaves_pickup_states():
    source = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    state_guard = source.index('if !(_state in ["inbound","boarding"]) exitWith {};')
    cleanup = source.index('if (!isNull _pad) then {deleteVehicle _pad};', state_guard)
    assert state_guard < cleanup
    assert '"ITW_CLASH_CASEVAC_LZPad",nil' in source
    assert '"ITW_CLASH_CASEVAC_Rally",nil' in source


# ------------------------------------------- the landing is commanded once

def test_the_landing_is_not_re_commanded_every_poll():
    """The loop called landAt every two seconds for the whole approach. Each
    call restarts the approach, so the aircraft descended, was re-commanded,
    re-approached and descended again, never settling - and when
    BoardingTimeout expired with nobody aboard the evac failed and the airframe
    went home. _successLogged guarded only the LOGGING, so the repetition never
    appeared in the RPT."""
    source = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    assert "private _commanded = false;" in source
    assert "if (_ok) then {_commanded = true}" in source


def test_an_abandoned_approach_is_re_commanded_but_bounded():
    source = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    assert "_lostApproach" in source
    assert "ITW_CLASH_CASEVAC_LZPadLostAltitude" in source
    assert "ITW_CLASH_CASEVAC_LZPadLostDistance" in source
    assert "ITW_CLASH_CASEVAC_LZPadMaxRecommands" in source
    assert "lz-pad-recommanded" in source


def test_a_normal_descent_is_never_treated_as_abandoned():
    """Both conditions, not either: the aircraft has to have climbed away AND
    drifted off the pad."""
    source = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    block = source[source.index("private _lostApproach = _commanded"):]
    block = block[:block.index(";")]
    assert "&&" in block
    assert "LZPadLostAltitude" in block and "LZPadLostDistance" in block
    assert "||" not in block
