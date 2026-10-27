"""HAL never puts a non-combat player group on defense (2026-10-27, Hark).

A player helicopter crew finished a transport run and was handed "Defend
Position" with a SENTRY waypoint. HQOrdersDef adds RydHQ_NCCargoG (transport
crews) back into the defend pool after subtracting CargoOnly; only NoDef is
subtracted after that. The transport contract's own NoDef entry lapsed with the
contract, and the combat gate's CargoOnly was written to the commander only,
which HQSitRepB rewrites from the RydHQB_* globals every cycle.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def code_text(text: str) -> str:
    return re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


def body_of(source: str, name: str) -> str:
    start = source.index(f"{name} = {{")
    depth = 0
    i = source.index("{", start)
    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1
    raise AssertionError(name)


GATE = body_of(
    code_text((MISSION / "ITW_CLASH_PlayerTaskStateHardening.sqf").read_text(encoding="utf-8")),
    "ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission",
)


def test_hal_adds_transport_crews_back_after_cargo_only_and_only_no_def_removes_them():
    orders = (HAL / "HQOrdersDef.sqf").read_text(encoding="utf-8", errors="replace")
    readds = [line for line in orders.splitlines() if '+ (_HQ getVariable ["RydHQ_NCCargoG",[]])) - (_HQ getVariable ["RydHQ_NoDef",[]])' in line]
    assert len(readds) == 2


def test_hal_sitrep_rewrites_cargo_only_and_no_def_from_the_globals():
    sitrep = (HAL / "HQSitRepB.sqf").read_text(encoding="utf-8", errors="replace")
    assert '_HQ setVariable ["RydHQ_CargoOnly",RydHQB_CargoOnly];' in sitrep
    assert '_HQ setVariable ["RydHQ_NoDef",RydHQB_NoDef];' in sitrep


def test_non_combat_player_groups_are_in_no_def_and_combat_releases_it():
    assert '["NoDef","ITW_CLASH_PlayerCombatGateOwnsNoDef",!_combat]' in GATE
    assert '["CargoOnly","ITW_CLASH_PlayerCombatGateOwnsCargoOnly",!_combat]' in GATE
    # Only an entry the gate added is removed.
    off = GATE[GATE.index("} else {", GATE.index("if (_on) then {")):]
    assert off.index("if (_owned) then {") < off.index("[_suffix,false] call _set;")
    assert "_group setVariable [_flag,nil];" in off


def test_every_write_goes_to_the_commander_and_the_global():
    assert "[_group,[_suffix],_on] call" in GATE
    assert "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership" in GATE
    # No direct hq-only write remains outside the parity fallback.
    assert GATE.count("_hq setVariable") == 1


def test_commander_parity_loads_before_the_gate():
    init = (MISSION / "init.sqf").read_text(encoding="utf-8")
    assert init.index('"ITW_CLASH_CommanderParity.sqf"') < init.index('"ITW_CLASH_PlayerTransportAuthority.sqf"')
    transport = (MISSION / "ITW_CLASH_PlayerTransportAuthority.sqf").read_text(encoding="utf-8")
    assert 'execVM "ITW_CLASH_PlayerTaskStateHardening.sqf"' in transport
