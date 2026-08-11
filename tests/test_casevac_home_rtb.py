from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_home_rtb_patch_is_started_with_casevac():
    init = text("init.sqf")
    assert 'execVM "ITW_CLASH_CASEVAC.sqf"' in init
    assert 'execVM "ITW_CLASH_CASEVAC_HomeRTB.sqf"' in init


def test_successful_cleanup_uses_canonical_enemy_home_spawn():
    source = text("ITW_CLASH_CASEVAC_HomeRTB.sqf")
    assert "ITW_Zones#-1" in source
    assert "ITW_OBJ_INDEX" in source
    assert "ITW_BASE_A_SPAWN" in source
    assert '"enemy-home-ai-spawn"' in source
    assert "ITW_CLASH_CASEVAC_fnc_SendHeliHome" in source


def test_successful_casevac_flies_home_for_ten_seconds_before_cleanup():
    source = text("ITW_CLASH_CASEVAC_HomeRTB.sqf")
    assert "_delay == 15" in source
    assert "sleep 10;" in source
    assert '"cleanup-egress"' in source
    assert "deleteVehicleCrew _heli;" in source
    assert "deleteVehicle _heli;" in source


def test_abort_and_failure_cleanup_keep_base_behavior():
    source = text("ITW_CLASH_CASEVAC_HomeRTB.sqf")
    assert "ITW_CLASH_CASEVAC_fnc_CleanupHeli_V1Base" in source
    assert "_this call ITW_CLASH_CASEVAC_fnc_CleanupHeli_V1Base;" in source
