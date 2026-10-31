"""A pilot sent for a squad that no longer exists (2026-10-31, Hark).

"got assigned to pick up alpha 2-6, when I got there, nobody is around and task
is still active." The squad was wiped out as the pilot arrived. Once a squad is
seated on paper, HAL's SCargo never looks at it again and waits on CargoM, so
the Pick Up task stayed open. Separately, the RTB watcher that closes HAL's
return tasks died on its first look at a task: HACAddedTasks holds ids, and
taskDescription wants a Task.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code(name: str) -> str:
    text = (MISSION / name).read_text(encoding="utf-8")
    return re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


BRIDGE = code("ITW_CLASH_PlayerTransportNativeBridge.sqf")
RTB = code("ITW_CLASH_PlayerTransportRTB.sqf")


def test_scargo_really_has_no_check_on_the_squad_while_it_waits():
    scargo = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "SCargo.sqf").read_text(encoding="utf-8")
    start = scargo.index('if not (_GD == _unitG) then')
    wait = scargo[start:scargo.index("_unitvar = str _GD;", start)]
    assert "units _unitG)) < 1" not in wait
    assert '_busy = _GD getvariable ("CargoM" + (str _GD));' in wait


def test_a_lost_squad_releases_its_carrier_through_scargos_own_exit():
    assert "ITW_CLASH_PlayerTransportNativeBridgeVersion = 8;" in BRIDGE
    assert '_carrierGroup setVariable ["CargoM" + str _carrierGroup,false];' in BRIDGE
    assert '_reason isEqualTo "cargo-group-lost" && {alive _lastCarrier}' in BRIDGE
    release = BRIDGE.index("[_lastCarrier,_name] call ITW_CLASH_PlayerTransport_fnc_ReleaseCarrier;")
    assert release < BRIDGE.index('if (_reason isNotEqualTo "contract-replaced") then {')


def test_the_name_survives_the_group():
    # groupId of a deleted group is empty.
    monitor = BRIDGE[BRIDGE.index("ITW_CLASH_PlayerTransport_fnc_MonitorObservedHALContract = {"):]
    assert monitor.index("private _name = groupId _group;") < monitor.index("while {true} do {")


def test_the_pilot_is_told_in_the_house_voice():
    assert '"C.L.A.S.H.: Pickup cancelled. %1 is gone."' in BRIDGE


def test_the_rtb_watcher_never_calls_a_task_command_on_an_id():
    assert "ITW_CLASH_PlayerTransportRTBVersion = 4;" in RTB
    for command, helper in [
        ("taskDescription _task", "BIS_fnc_taskDescription"),
        ("taskState _task", "BIS_fnc_taskState"),
        ("taskDestination _task", "BIS_fnc_taskDestination"),
    ]:
        assert RTB.count(command) == 1, command
        guarded = RTB[RTB.index(command) - 200:RTB.index(command)]
        assert '_task isEqualType ""' in guarded, command
        assert helper in RTB, helper
    assert "taskDescription _x" not in RTB
    assert "taskState _x" not in RTB
    assert "taskDestination _x" not in RTB
    assert "taskState _trackedTask" not in RTB
    assert "taskDestination _trackedTask" not in RTB
