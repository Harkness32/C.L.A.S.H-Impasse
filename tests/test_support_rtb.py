"""Support vehicles go home when the job is done.

Hark: "we need to have support vehicles rtb after supply missions, sometimes
they do repairs at the front and that keeps them vulnerable."

HAL already has this and it is off by default. RydHQ_SupportRTB is read by all
four supply workers and decides two things at once:

    _pos = [_posX,_posY];                           // the supported unit
    if (RydHQ_SupportRTB) then {_pos = _startpos};  // or back where it began
    ...
    if not (RydHQ_SupportRTB) then {
        _cause = [_unitG,6,true,0,24,...] call RYD_Wait;   // and loiter there
    };

So false - the stock default - means a repair truck's next waypoint IS the
damaged vehicle's position and it then WAITS there. A setting, not a defect.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace").replace("\r", "")


def test_all_four_supply_workers_honour_the_flag():
    """If a future HAL drops it from one of these, that worker silently goes
    back to loitering at the front."""
    for name in ("GoRepSupp.sqf", "GoAmmoSupp.sqf", "GoFuelSupp.sqf", "GoMedSupp.sqf"):
        source = read(HAL / name)
        assert 'RydHQ_SupportRTB' in source, name


def test_the_flag_redirects_the_waypoint_home():
    source = read(HAL / "GoRepSupp.sqf")
    assert 'if (_HQ getVariable ["RydHQ_SupportRTB",false]) then {_pos = _startpos;' in source


def test_the_flag_also_removes_the_loiter():
    """Both halves matter. Sending it home but leaving the wait would park it
    at the front anyway."""
    source = read(HAL / "GoRepSupp.sqf")
    assert 'if not (_HQ getVariable ["RydHQ_SupportRTB",false]) then {' in source
    block = source[source.index('if not (_HQ getVariable ["RydHQ_SupportRTB",false]) then {'):]
    assert "RYD_Wait" in block[:260]


def test_hal_defaults_it_off():
    """The premise: this is a setting we are turning on, not a bug we fixed."""
    source = read(HAL / "GoRepSupp.sqf")
    assert '"RydHQ_SupportRTB",false' in source


def test_both_commanders_get_it():
    """The freeze is per commander: each HQSitRep copies RydHQ<Sign>_SupportRTB
    onto its own HQ, so setting one would leave the other loitering."""
    a = read(MISSION / "ITW_CLASH.sqf")
    b = read(MISSION / "ITW_CLASH_DualHALCheckbook.sqf")
    assert "RydHQ_SupportRTB = missionNamespace getVariable" in a
    assert "RydHQB_SupportRTB = ITW_CLASH_SupportRTB;" in b


def test_the_sitreps_copy_the_global_to_the_hq():
    """Which is why setting the global once is enough."""
    found = 0
    for name in ("HQSitRepF.sqf", "HQSitRepE.sqf", "HQSitRepB.sqf"):
        source = read(HAL / name)
        if 'setVariable ["RydHQ_SupportRTB"' in source:
            found += 1
    assert found == 3, found


def test_commander_a_is_set_with_the_static_settings_not_the_per_cycle_refresh():
    """ITW_CLASH.sqf has two RydHQ_ blocks: a per-cycle order refresh and the
    boot configuration. The global persists, so it belongs with the static
    settings - and putting it in the refresh would rewrite it every cycle for
    no reason."""
    source = read(MISSION / "ITW_CLASH.sqf")
    assert source.count("RydHQ_SupportRTB = missionNamespace getVariable") == 1
    idx = source.index("RydHQ_SupportRTB = missionNamespace getVariable")
    assert 'RydHQ_Order = "DEFEND";' in source[idx - 1200:idx]


def test_it_can_be_turned_off_in_one_place():
    a = read(MISSION / "ITW_CLASH.sqf")
    b = read(MISSION / "ITW_CLASH_DualHALCheckbook.sqf")
    assert '"ITW_CLASH_SupportRTB",true' in a
    assert '"ITW_CLASH_SupportRTB",true' in b
