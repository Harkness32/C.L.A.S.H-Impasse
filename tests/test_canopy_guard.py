"""A squad dropped by parachute loses its order when it lands.

Hark, 2026-10-11: "seems like we still have job wipe on delivery".

Run of 2026-10-11 20:23, mission 2, G51 (Alpha 4-6) on a capture order:

    20:46:28  dropped from 54 m by Bravo 1-2
    20:46:30  Bravo 1-2 shot down (air-loss, B_APC_Tracked_01_AA_F)
    20:46:34  the order is awake: waypoint to the objective written
    20:46:48  leader on foot
    20:46:53  Busy false
    20:47:03  a new order; 20:47:23 a new lift requested

The other four drops on that flight kept their orders.

RYD_Wait takes the leader's vehicle once, when it starts, and reads that
vehicle being null on any later pass as the group being lost. A parachute is a
vehicle and is deleted on landing. So a wait that starts while the leader is
under canopy ends on touchdown, and the order file clears Busy and exits.

The unload owner's v7 closed the way in that it had made: it no longer releases
the order until the squad is standing. But the order's carrier wait is itself a
RYD_Wait on the carrier group, and a dead aircraft ends that one. A carrier
shot down in the ten to twenty seconds after its drop wakes the order while the
men are still in the air.

ITW_CLASH_HALParadrop.sqf v7 wraps RYD_Wait. The wrapper holds a wait until the
leader is out of his chute, then runs HAL's own function unchanged. HAL source
is not edited.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal"
ADD = ROOT / "CLASH HAL Additions" / "addons" / "clash_hal_additions" / "hal"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r", "")


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


def code_only(source: str) -> str:
    """Drop // comments so a commented-out line cannot satisfy an assertion."""
    return "\n".join(
        line for line in source.split("\n") if not line.lstrip().startswith("//")
    )


def paradrop() -> str:
    return read(MISSION / "ITW_CLASH_HALParadrop.sqf")


def hal_wait() -> str:
    source = read(NR6 / "HAC_fnc.sqf")
    start = source.index("RYD_Wait = ")
    return source[start:source.index("RYD_CreateDecoy", start)]


def guard_thread() -> str:
    source = code_only(paradrop())
    start = source.index('scriptName "ITW_CLASH_HALParadrop_CanopyGuard";')
    return source[start:source.index("ITW_CLASH_HALParadropReady = true;", start)]


# --- the hazard, in HAL's own source ------------------------------------------


def test_hal_takes_the_leaders_vehicle_once_when_a_wait_starts():
    wait = hal_wait()
    taken = wait.index("_AV = vehicle _UL;")
    loop = wait.index("waituntil")
    assert taken < loop
    assert wait.count("_AV = vehicle _UL;") == 1


def test_hal_reads_that_vehicle_going_null_as_the_group_being_lost():
    wait = hal_wait()
    lost = wait.index("case (isNull _AV) : {_alive = false};")
    mia = wait.index('getVariable ["RydHQ_MIA",false]) : {_alive = false;')
    # First match wins, and this one is ahead of the release flag: a deleted
    # chute ends the wait as a loss even when a release is waiting to be read.
    assert lost < mia


def test_the_cargo_form_of_the_wait_reads_the_assigned_vehicle_instead():
    wait = hal_wait()
    cargo = wait[wait.index("if (_cargo) then"):]
    assert "_AV = assignedVehicle _UL;" in cargo[:400]


def test_every_order_ends_itself_when_an_on_foot_wait_says_lost():
    for name in ("GoCapture.sqf", "GoRecon.sqf", "GoAttInf.sqf"):
        source = read(ADD / name)
        exits = re.findall(r"if not \(_alive\) exitwith", source)
        assert len(exits) >= 2, name
        at = source.index("if not (_alive) exitwith")
        assert '_unitG setVariable [("Busy" + (str _unitG)),false];' in source[at:at + 900], name


def test_a_dead_carrier_wakes_the_order_and_does_not_end_it():
    """The carrier wait is a RYD_Wait on the carrier group. Its vehicle dying
    returns _alive false, and for a carrier that is somebody else's group the
    order carries on, straight into its next wait."""
    for name in ("GoCapture.sqf", "GoRecon.sqf", "GoAttInf.sqf"):
        source = read(ADD / name)
        carrier = re.search(r"_cause = \[_GDV,6,true,\d+,30,", source).start()
        assert "call RYD_Wait;" in source[carrier:carrier + 200], name
        carried_on = source.index("if (not (_alive) and not (_OtherGroup)) exitwith", carrier)
        # The next wait on the squad itself. Seven arguments, so the seventh,
        # _cargo, is false: it is the vehicle form, the one that takes
        # vehicle _UL at its start.
        next_wait = source.index("[_unitG,6,true,0,30,[],false] call RYD_Wait;", carried_on)
        assert carrier < carried_on < next_wait, name

    wait = hal_wait()
    assert "case (not (alive _AV)) : {_alive = false};" in wait


def test_the_thing_a_dropped_man_is_in_is_a_parachute_vehicle():
    itw = read(MISSION / "ITW_Attack.sqf")
    chute = itw.index('private _para = "Steerable_Parachute_F" createVehicle _pos;')
    assert "_unit moveindriver _para;" in itw[chute:chute + 400]


# --- the guard -------------------------------------------------------------------


def test_under_canopy_means_in_a_chute_or_still_assigned_to_one():
    body = code_only(function_body(paradrop(), "ITW_CLASH_HALParadrop_fnc_UnderCanopy"))
    assert '(vehicle _leader) isKindOf "ParachuteBase"' in body
    assert '|| {(assignedVehicle _leader) isKindOf "ParachuteBase"}' in body
    # Asked of the leader as he is now, not as he was.
    assert "private _leader = leader _group;" in body
    assert "if (isNull _group) exitWith {false};" in body


def test_a_wait_whose_leader_is_not_in_a_chute_is_not_delayed_at_all():
    body = code_only(function_body(paradrop(), "ITW_CLASH_HALParadrop_fnc_HoldForLanding"))
    not_under = body.index(
        "if !([_group] call ITW_CLASH_HALParadrop_fnc_UnderCanopy) exitWith {0};"
    )
    assert not_under < body.index("sleep")
    assert not_under < body.index("waitUntil")
    assert not_under < body.index("call ITW_CLASH_HALParadrop_fnc_Log")


def test_the_hold_ends_on_landing_or_at_the_bound():
    body = code_only(function_body(paradrop(), "ITW_CLASH_HALParadrop_fnc_HoldForLanding"))
    assert "private _deadline = time + ITW_CLASH_HALParadrop_CanopyWait;" in body
    wait = body[body.index("waitUntil {"):]
    wait = wait[:wait.index("};") + 2]
    assert "!([_group] call ITW_CLASH_HALParadrop_fnc_UnderCanopy)" in wait
    assert "|| {time >= _deadline}" in wait
    assert '"ITW_CLASH_HALParadrop_CanopyWait",90' in paradrop()


def test_the_hold_can_be_switched_off_and_never_runs_unscheduled():
    body = code_only(function_body(paradrop(), "ITW_CLASH_HALParadrop_fnc_HoldForLanding"))
    off = body.index("if (!ITW_CLASH_HALParadrop_CanopyGuard) exitWith {0};")
    unscheduled = body.index("if (!canSuspend) exitWith {0};")
    assert off < unscheduled < body.index("waitUntil")
    assert '"ITW_CLASH_HALParadrop_CanopyGuard",true' in paradrop()


def test_a_hold_that_happened_is_logged_with_how_long():
    body = code_only(function_body(paradrop(), "ITW_CLASH_HALParadrop_fnc_HoldForLanding"))
    assert '["wait-held-for-landing",[' in body
    line = body[body.index('["wait-held-for-landing",['):]
    assert "time >= _deadline" in line[:260]


# --- the wrapper -----------------------------------------------------------------


def test_hals_wait_is_kept_and_called_with_the_same_arguments():
    thread = guard_thread()
    kept = thread.index("ITW_CLASH_HALParadrop_fnc_WaitBase = RYD_Wait;")
    wrapped = thread.index("RYD_Wait = {")
    assert kept < wrapped
    wrapper = thread[wrapped:thread.index("};", wrapped) + 2]
    held = wrapper.index(
        "[_this param [0,grpNull]] call ITW_CLASH_HALParadrop_fnc_HoldForLanding;"
    )
    ran = wrapper.index("_this call ITW_CLASH_HALParadrop_fnc_WaitBase")
    assert held < ran
    # HAL's result is the wrapper's result: nothing after the call.
    assert wrapper[ran:].strip() == "_this call ITW_CLASH_HALParadrop_fnc_WaitBase\n    };".strip()


def test_the_wrapper_declares_nothing_hals_wait_could_trip_over():
    """HAL's wait reads variables out of the order that called it (_unitG is
    one). A local declared between the two would sit in its way."""
    thread = guard_thread()
    wrapped = thread.index("RYD_Wait = {")
    wrapper = thread[wrapped:thread.index("};", wrapped) + 2]
    for forbidden in ("private", "params", "_group", "_unitG", "_HQ", "spawn"):
        assert forbidden not in wrapper, forbidden
    assert "_unitG" in hal_wait(), "the reason for the rule"


def test_it_wraps_once_and_only_after_hals_own_init_has_finished():
    thread = guard_thread()
    ready = thread.index('(!isNil "RYD_Wait" && {!isNil "HAL_GoCapture"})')
    once = thread.index('if (!isNil "ITW_CLASH_HALParadrop_fnc_WaitBase") exitWith {};')
    kept = thread.index("ITW_CLASH_HALParadrop_fnc_WaitBase = RYD_Wait;")
    assert ready < once < kept

    # Why both names: HAL defines its functions, then its orders, in one init.
    init = read(NR6 / "RydHQInit.sqf")
    fnc = init.index('call compile preprocessfile (RYD_Path + "HAC_fnc.sqf");')
    var = init.index('call compile preprocessfile (RYD_Path + "VarInit.sqf");')
    assert fnc < var
    assert "HAL_GoCapture = compile" in read(NR6 / "VarInit.sqf")


def test_a_missing_hal_is_said_out_loud_and_changes_nothing():
    thread = guard_thread()
    failed = thread.index("hal-paradrop-canopy-guard-failed")
    assert failed < thread.index("ITW_CLASH_HALParadrop_fnc_WaitBase = RYD_Wait;")
    assert 'if (isNil "RYD_Wait" || {isNil "HAL_GoCapture"}) exitWith {' in thread


def test_hal_source_is_not_edited_or_recompiled_for_this():
    source = re.sub(r"/\*.*?\*/", "", code_only(paradrop()), flags=re.S)
    assert "HAC_fnc.sqf" not in source
    assert "preprocessFile" not in source
    assert "compile " not in source


# --- what it sits beside ---------------------------------------------------------


def test_the_unload_owner_still_holds_its_own_release_until_the_squad_stands():
    """v7's fix stays. This closes the other ways in; it does not replace it."""
    unload = read(MISSION / "ITW_CLASH_HALUnload.sqf")
    release = code_only(function_body(unload, "ITW_CLASH_HALUnload_fnc_OrderRelease"))
    assert "ITW_CLASH_HALUnloadLandedWait" in release
    assert release.index("call _riding") < release.index('setVariable ["RydHQ_MIA",true]')


def test_the_boot_lines_say_the_guard_is_loaded():
    source = paradrop()
    assert "ITW_CLASH_HALParadropVersion = 7;" in source
    assert "hal-paradrop-canopy-guard-ready | version=%1 enabled=%2 bound=%3s wraps=RYD_Wait" in source
    assert "ITW_CLASH_HALParadrop_CanopyGuardReady = true;" in source
