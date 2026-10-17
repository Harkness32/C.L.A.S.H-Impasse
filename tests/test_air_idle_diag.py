"""Why a HAL helicopter is not sent (2026-10-17 run 4: "stub wing helicopters
no longer move out"). Observe only."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
TEXT = (MISSION / "ITW_CLASH_AirIdleDiag.sqf").read_text(encoding="utf-8")
CODE = re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", TEXT, flags=re.S))


def test_it_names_every_attackav_gate_hal_applies():
    hal = (ROOT / "NR6 Hal/addons/nr6_hal/HAL/HQOrders.sqf").read_text(encoding="utf-8", errors="replace")
    # The gates are HAL's own (HQOrders.sqf builds AttackAv from them).
    for name in ["RydHQ_StaticG", "RydHQ_ArtG", "RydHQ_SpecForG", "RydHQ_AmmoDrop", "RydHQ_CargoOnly",
                 "RydHQ_reconG", "RydHQ_FOG", "RydHQ_SupportG", "RydHQ_NoAttack", "RydHQ_NCCargoG"]:
        assert name in hal, name
        assert '"%s"' % name in CODE, name
    for gate in ['"busy"', '"unable"', '"flank"', '"cannot-move"', '"fuel"', '"damage"',
                 '"no-magazines"', '"ammo-full-count"', '"crew-hurt"']:
        assert gate in CODE, gate
    assert "[_group,_ncVeh] call RYD_AmmoFullCount" in CODE
    assert "_ammoFull < 0.15" in CODE


def test_it_reads_and_never_writes_hal_state():
    assert "setVariable" not in CODE
    assert "RydHQ_AAthreat" in CODE


def test_it_is_loaded_and_has_a_console_report():
    init = (MISSION / "init.sqf").read_text(encoding="utf-8")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_AirIdleDiag.sqf";' in init
    assert "ITW_CLASH_AirIdleDiag_fnc_Report = {" in CODE
    assert '["air-idle",_x] call ITW_CLASH_AirIdleDiag_fnc_Log' in CODE
