"""AI ammo helicopters stay HAL's ammo-drop carriers (2026-10-28, Hark).

"We broke slingload cargo drops somehow down the road, I don't see them flown
anymore". HAL's situation report resets the commander's RydHQ_AmmoDrop from
the side's global every cycle (NR6 Hal HQSitRepB.sqf:405, inside the loop), and
CLASH only ever wrote the commander. A bought or reactivated ammo helicopter
was an ammo-drop carrier for one cycle; after that HAL's dispatch, CLASH
Resupply's crate drop and Thunder Run never saw it, and the capacity check
bought another. Every add and removal now also writes the global.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
PARITY = "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership"


def code(name: str) -> str:
    text = (MISSION / name).read_text(encoding="utf-8")
    return re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


def test_hal_resets_the_list_from_its_global_every_cycle():
    sitrep = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "HQSitRepB.sqf").read_text(encoding="utf-8")
    loop = sitrep.index("while {true} do")
    assert sitrep.index('_HQ setVariable ["RydHQ_AmmoDrop",RydHQB_AmmoDrop];') > loop


def test_the_parity_helper_writes_the_commander_and_the_global():
    parity = code("ITW_CLASH_CommanderParity.sqf")
    assert 'private _globalName = _prefix + _suffix;' in parity
    assert "missionNamespace setVariable [_globalName,_global];" in parity


def test_a_provided_ammo_helicopter_is_written_through():
    gen = code("ITW_CLASH_ForceGeneration.sqf")
    assert f"[_group,[\"AmmoDrop\"],true] call {PARITY};" in gen
    assert "ITW_CLASH_ForceGenerationVersion = 5;" in gen
    assert "ammoDropGlobal=true" in gen


def test_the_player_logistics_role_is_written_through_both_ways():
    support = code("ITW_CLASH_PlayerTaskSupport.sqf")
    assert f"[_group,[\"AmmoDrop\"],_eligible] call {PARITY};" in support
    assert f"[_x,[\"AmmoDrop\"],false] call {PARITY};" in support
    assert "ITW_CLASH_PlayerTaskSupportVersion = 4;" in support


def test_lifecycle_sweeps_take_a_group_out_of_the_global_too():
    for name, version in [
        ("ITW_CLASH_ServiceLifecycle.sqf", "ITW_CLASH_ServiceLifecycleVersion = 5;"),
        ("ITW_CLASH_CrewRemnantCleanup.sqf", "ITW_CLASH_CrewRemnantCleanupVersion = 4;"),
    ]:
        source = code(name)
        assert f"[_group,[\"AmmoDrop\"],false] call {PARITY};" in source, name
        assert version in source, name


def test_no_commander_only_write_is_left():
    for path in sorted(MISSION.glob("ITW_CLASH_*.sqf")):
        source = code(path.name)
        writes = source.count('setVariable ["RydHQ_AmmoDrop"')
        assert source.count('["AmmoDrop"]') >= writes, path.name
