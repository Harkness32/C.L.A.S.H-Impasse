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
    assert "ITW_CLASH_CASEVAC_InfantryRallyOffset = 30;" in source
    assert '_rally = _lz getPos [ITW_CLASH_CASEVAC_InfantryRallyOffset,_rallyBearing];' in source
    assert '_group addWaypoint [_rally,8]' in source
    assert '"lz-pad-created"' in source


def test_helicopter_is_pinned_to_pad_with_landat_until_boarding_finishes():
    source = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    assert '_heli landAt [_pad,"GetIn",_wait,true]' in source
    assert '_state isEqualTo "inbound"' in source
    assert '_heli distance2D _pad <= 650' in source
    assert '"lz-pad-locked"' in source


def test_pad_is_cleaned_after_extraction_state_changes():
    source = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    assert 'deleteVehicle _pad' in source
    assert '"ITW_CLASH_CASEVAC_LZPad",nil' in source
    assert '"ITW_CLASH_CASEVAC_Rally",nil' in source
