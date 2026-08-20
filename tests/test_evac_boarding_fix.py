from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_evac_boarding_fix_is_wired_after_casevac_and_ground_modules():
    init = text("init.sqf")
    assert 'execVM "ITW_CLASH_CASEVAC_AirOpsFix.sqf"' in init
    assert 'execVM "ITW_CLASH_GroundMEDEVAC.sqf"' in init
    assert 'execVM "ITW_CLASH_EvacBoardingFix.sqf"' in init
    assert init.index('execVM "ITW_CLASH_GroundMEDEVAC.sqf"') < init.index('execVM "ITW_CLASH_EvacBoardingFix.sqf"')


def test_shared_boarding_uses_stable_vehicle_assignment_without_domove_spam():
    source = text("ITW_CLASH_EvacBoardingFix.sqf")
    assert 'ITW_CLASH_EvacBoarding_fnc_Board' in source
    assert '_x assignAsCargo _vehicle;' in source
    assert '_survivors orderGetIn true;' in source
    assert 'assignedVehicle _x' in source
    assert 'boarding-assignment-repaired' in source
    assert 'doMove getPosATL _vehicle' not in source
    assert 'moveInCargo' not in source
    assert 'moveInAny' not in source


def test_air_boarding_enters_explicit_boarding_state_and_preserves_airops_wrapper():
    source = text("ITW_CLASH_EvacBoardingFix.sqf")
    assert 'ITW_CLASH_CASEVAC_fnc_RunExtraction_V1Base = {' in source
    assert 'ITW_CLASH_CASEVAC_fnc_RunExtraction = {' not in source
    assert '_group setVariable ["ITW_CLASH_CASEVAC_State","boarding"]' in source
    assert '["landed",[_id,_lineage,_lz]] call ITW_CLASH_CASEVAC_fnc_Log;' in source
    assert '"air",_id,_lineage,_group,_heli,ITW_CLASH_CASEVAC_BoardingTimeout' in source


def test_ground_boarding_uses_same_state_machine():
    source = text("ITW_CLASH_EvacBoardingFix.sqf")
    assert 'ITW_CLASH_GroundMEDEVAC_fnc_RunExtraction = {' in source
    assert '_group setVariable ["ITW_CLASH_GroundMEDEVAC_State","boarding"]' in source
    assert '_group setVariable ["ITW_CLASH_CASEVAC_State","ground-boarding"]' in source
    assert '"ground",_id,_lineage,_group,_veh,ITW_CLASH_GroundMEDEVAC_BoardingTimeout' in source


def test_boarding_telemetry_exposes_unit_state_if_it_still_fails():
    source = text("ITW_CLASH_EvacBoardingFix.sqf")
    for event in [
        '"boarding-start"',
        '"boarding-progress"',
        '"boarding-assignment-repaired"',
        '"boarding-complete"',
        '"boarding-timeout-detail"',
    ]:
        assert event in source
    assert 'lifeState _x' in source
    assert 'canMove _x' in source
    assert 'CONSCIOUS(_x)' in source
    assert 'round (_x distance2D _vehicle)' in source


def test_boarding_does_not_extend_existing_timeout_contract():
    source = text("ITW_CLASH_EvacBoardingFix.sqf")
    assert 'ITW_CLASH_CASEVAC_BoardingTimeout' in source
    assert 'ITW_CLASH_GroundMEDEVAC_BoardingTimeout' in source
    assert 'time + _timeout' in source
