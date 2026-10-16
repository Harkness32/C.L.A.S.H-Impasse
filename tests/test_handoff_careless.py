"""Dual-HAL Checkbook v9: Impasse's spawn CARELESS ends at the HAL handoff.

Impasse sets every vehicle driver (made leader) CARELESS at spawn and lifts it
with its own waypoints. After the handoff Impasse's writers never run, and HAL
only sets behaviour through a waypoint, so the CARELESS outlived the handoff.
On 2026-10-10 a stub-wing Ghost Hawk (G113) flew a whole search-and-destroy
CARELESS/YELLOW because its waypoint's COMBAT/RED never applied.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code(name: str) -> str:
    source = (MISSION / name).read_text(encoding="utf-8")
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def function_body(source: str, name: str) -> str:
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
    raise AssertionError(f"unterminated {name}")


def checkbook() -> str:
    return code("ITW_CLASH_DualHALCheckbook.sqf")


def test_the_spawn_careless_is_still_what_impasse_writes():
    # If Impasse stops doing this, the reset below is dead code: say so.
    attack = code("ITW_Attack.sqf")
    assert '[_driver,"CARELESS"] call ITW_FncSetUnitBehavior;' in attack


def test_only_careless_is_cleared_and_only_to_hals_default():
    body = function_body(checkbook(), "ITW_CLASH_DualHAL_fnc_ClearImpasseCareless")
    assert '!((behaviour _leader) isEqualTo "CARELESS")' in body
    assert '_group setBehaviourStrong "AWARE";' in body
    assert '[[_group,"AWARE"],"setBehaviourStrong",_group] call ITW_FncRemoteLocalGroup;' in body
    # Combat mode is not this function's business.
    assert "setCombatMode" not in body
    assert '"impasse-careless-cleared"' in body


def test_both_vehicle_handoffs_clear_it_and_transports_keep_it():
    source = checkbook()
    stage_from = source.index('[_crewGroup,"impasse-vehicle-handoff"] call ITW_CLASH_DualHAL_fnc_RegisterGroup;')
    stage = source[stage_from:source.index("ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles = {")]
    assert re.search(
        r'if \(_transportDeployment\) then \{\s*\[_crewGroup,true,"impasse-field"\] call\s*'
        r'ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine;\s*\} else \{\s*'
        r'\[_crewGroup,"impasse-field"\] call ITW_CLASH_DualHAL_fnc_ClearImpasseCareless;',
        stage,
    )
    migrate = function_body(source, "ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles")
    assert re.search(
        r'ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine;\s*\} else \{\s*'
        r'\[_crewGroup,"managed-vehicle-migration"\] call\s*ITW_CLASH_DualHAL_fnc_ClearImpasseCareless;',
        migrate,
    )
    # A Checkbook transport is a transport: no reset on that path.
    transport_from = source.index('[_crewGroup,"checkbook-transport"] call ITW_CLASH_DualHAL_fnc_RegisterGroup;')
    transport = source[transport_from:transport_from + 1200]
    assert "ClearImpasseCareless" not in transport


def test_version_and_boot_flag():
    raw = (MISSION / "ITW_CLASH_DualHALCheckbook.sqf").read_text(encoding="utf-8")
    assert "ITW_CLASH_DualHALCheckbookVersion = 9;" in raw
    assert "impasseCarelessCleared=true" in raw
