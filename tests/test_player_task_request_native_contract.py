from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NATIVE = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAC_fnc.sqf"


def _block(text: str, start: str, end: str) -> str:
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


def _function_block(text: str, start: str) -> str:
    a = text.index(start)
    b = text.find("\nRYD_", a + len(start))
    if b < 0:
        b = len(text)
    return text[a:b]


def test_native_cff_target_selector_honors_taken_marker():
    text = NATIVE.read_text(encoding="utf-8", errors="ignore")
    cff_tgt = _block(text, "RYD_CFF_TGT =", "RYD_ArtyMission =")

    assert 'getVariable ["CFF_Taken",false]' in cff_tgt
    assert "if not (_taken)" in cff_tgt
    assert "CFF_Temptation" in cff_tgt


def test_native_cff_uses_known_enemy_picture_and_target_selector():
    text = NATIVE.read_text(encoding="utf-8", errors="ignore")
    cff = _function_block(text, "RYD_CFF =")

    assert "_knEnemies = _this select 1" in cff
    assert "[_knEnemies] call RYD_CFF_TGT" in cff


def test_request_adapter_does_not_replace_native_target_selection():
    adapter = (MISSION / "ITW_CLASH_PlayerTaskRequestArtillery.sqf").read_text(
        encoding="utf-8"
    )

    assert 'getVariable ["RydHQ_KnEnemies",[]]' in adapter
    assert "RYD_CFF_TGT" in adapter
    assert "CFF_Temptation" not in adapter
    assert "rating _veh" not in adapter
