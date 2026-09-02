from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AMMO = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "GoAmmoSupp.sqf"


def test_ground_ammo_retry_stays_centered_on_original_recipient():
    source = AMMO.read_text(encoding="utf-8")
    start = source.index("while {(_counter <= 3)} do")
    end = source.index("_pos = [_posX,_posY];", start)
    retry = source[start:end]

    assert '_posX = ((position _Trg) select 0) + (random 100) -  50;' in retry
    assert '_posY = ((position _Trg) select 1) + (random 100) -  50;' in retry
    assert '_posX = ((position _unit) select 0)' not in retry
    assert '_posY = ((position _unit) select 1)' not in retry
