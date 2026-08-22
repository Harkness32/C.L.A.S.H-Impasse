from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def hal(name: str) -> str:
    return (HAL / name).read_text(encoding="utf-8")


def test_impasse_establishes_sides_inside_start_not_mission_init():
    init = mission("init.sqf")
    start = mission("ITW_Start.sqf")

    assert '[] execVM "ITW_Start.sqf"' in init
    assert 'ITW_PlayerSide = west;' in start
    assert 'ITW_EnemySide = if (' in start


def test_commander_b_side_binder_waits_for_impasse_identity_then_creates_only_b():
    api = mission("ITW_CLASH_CheckbookAPI.sqf")

    assert 'ITW_CLASH_DualHALSideBinderStarted' in api
    assert '!isNil "ITW_PlayerSide"' in api
    assert '!isNil "ITW_EnemySide"' in api
    assert 'call ITW_CLASH_DualHAL_fnc_PrepareCommanderB' in api
    assert 'call ITW_CLASH_DualHAL_fnc_Prepare;' not in api
    assert 'dual-hal-side-bound' in api
    assert 'sideBind=deferred-until-impasse-sides' in api


def test_native_hal_consumes_leader_hqb_after_varinit():
    ryd = hal("RydHQInit.sqf")

    assert 'call compile preprocessfile (RYD_Path + "VarInit.sqf")' in ryd
    assert 'if not (isNull leaderHQB)' in ryd
    assert 'setVariable ["RydHQ_CodeSign","B"]' in ryd
    assert ryd.index('call compile preprocessfile (RYD_Path + "VarInit.sqf")') < ryd.index('if not (isNull leaderHQB)')
