"""A squad HAL has made its garrison can never be used for anything else.

Run of 2026-10-10 23:22, BLUFOR:

    G40  fifteen-man anchor for objective 6
         23:43:05  arrives; HAL makes it the garrison; Busy true from here on
         23:47     five men left; the anchor asks for a new order every minute
                   and is deferred seven times, "hal-committed"
         23:53:36  one man left; withdrawal starts
         23:53:37  removed from RydHQ_Garrison ... and again at 23:55:06,
                   23:57:56, 00:00:28, 00:02:58 ... ten times in all
         gtfo-rest-restart-deferred [busy=true, resting=false, break=true]
                   sixteen times, 23:55:54 to 00:18:44; the log ends 00:19:03
    G37  taken as garrison 16 s after its order died on landing; "removed"
         fourteen times the same way

When an objective is taken and has no garrison within 500 m, HAL picks the
nearest free infantry group, sets its Busy flag by hand and adds it to
RydHQ_Garrison (HQReset.sqf). Two things then go wrong for anyone who wants the
squad back:

  - The list has two names. Every SitRep copies the global onto the HQ, so a
    removal from the HQ alone is undone within a cycle.
  - Busy has no owner. No order set it and nothing in HAL clears it. While it
    is set HAL will not task the squad, Garrison.sqf will not place it,
    HAL_GoDef exits on entry and HAL_GoRest waits on a Break nobody reads.

ITW_CLASH_CommanderParity_fnc_ReleaseGarrison removes the squad from both
names and marks the Busy; ITW_CLASH_CommanderParity_fnc_SettleGarrisonBusy
tries HAL's own cancel first and clears Busy by hand only when Break has gone
unread for the whole wait. The withdrawal watch and the Commander B anchor
order both use them.

HAL's pick itself is not touched, and a garrison squad that is neither
withdrawing nor wanted by its anchor stays exactly as HAL left it.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace").replace("\r", "")


def hal(name: str) -> str:
    return (HAL / name).read_text(encoding="utf-8", errors="replace").replace("\r", "")


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


def parity() -> str:
    return mission("ITW_CLASH_CommanderParity.sqf")


def release() -> str:
    return code_only(function_body(parity(), "ITW_CLASH_CommanderParity_fnc_ReleaseGarrison"))


def settle() -> str:
    return code_only(function_body(parity(), "ITW_CLASH_CommanderParity_fnc_SettleGarrisonBusy"))


def gtfo() -> str:
    return mission("ITW_CLASH_GTFO_Runtime.sqf")


BUSY_WRITE = re.compile(r'setVariable\s*\[\s*\(?\s*"Busy"\s*\+[^\]]*,\s*(true|false)', re.I)


# --- what HAL does, in HAL's own source -----------------------------------


def test_hal_sets_the_garrison_busy_by_hand_and_never_clears_it():
    reset = code_only(hal("HQReset.sqf"))
    writes = BUSY_WRITE.findall(reset)
    assert writes == ["true"], writes

    pick = reset[reset.index("_unitG setVariable [\"Busy\" + (str _unitG),true];"):]
    pick = pick[:pick.index("};")]
    assert "_garrison pushBack _unitG;" in pick
    assert '_HQ setVariable ["RydHQ_Garrison",_garrison];' in pick


def test_hal_only_picks_a_squad_that_was_not_busy():
    """So the Busy on a fresh pick is the pick's own, not an order's."""
    reset = hal("HQReset.sqf")
    assert '(_x getVariable ["Busy" + (str _x),false])) then {_UnableArr pushBack _x}' in reset
    assert "_fG = _fG - (_UnableArr);" in reset


def test_hal_will_not_place_a_busy_garrison():
    garrison = hal("Garrison.sqf")
    assert garrison.count("and not (_Unable) and not (_busy)) then") == 2


def test_hal_orders_do_not_run_on_that_busy():
    go_def = hal("GoDef.sqf")
    assert 'if ((_busy) or (_unitG in (_HQ getVariable ["RydHQ_SupportG",[]]))) exitwith' in go_def

    go_rest = hal("GoRest.sqf")
    wait = go_rest[go_rest.index('if (_unitG getVariable [("Busy" + (str _unitG)),false]) then {'):]
    wait = wait[:wait.index("[_unitG] call RYD_WPdel;")]
    assert '_unitG setVariable ["Break",true];' in wait
    assert 'waitUntil {sleep 5; not (_unitG getVariable ["Break",false])};' in wait
    # Busy and Resting are only taken after that wait returns.
    after = go_rest[go_rest.index(wait) + len(wait):]
    assert '_unitG setVariable [("Resting" + (str _unitG)),true];' in after


def test_sitrep_copies_the_global_list_onto_the_hq_every_cycle():
    """Why ten removals did not remove G40. One array, two names."""
    assert '_HQ setVariable ["RydHQ_Garrison",RydHQB_Garrison];' in hal("HQSitRepB.sqf")
    assert '_HQ setVariable ["RydHQ_Garrison",RydHQ_Garrison];' in hal("HQSitRep.sqf")


def test_the_side_prefixes_are_the_ones_sitrep_uses():
    prefix = function_body(parity(), "ITW_CLASH_CommanderParity_fnc_GlobalPrefixForSide")
    assert '_side == ITW_PlayerSide}) exitWith {"RydHQB_"}' in prefix
    assert '_side == ITW_EnemySide}) exitWith {"RydHQ_"}' in prefix


# --- the list ---------------------------------------------------------------


def test_release_writes_both_names():
    body = release()
    assert 'private _globalName = _prefix + "Garrison";' in body
    assert '_hq setVariable ["RydHQ_Garrison",_kept];' in body
    assert "missionNamespace setVariable [_globalName,_kept];" in body


def test_release_writes_one_array_to_both_names():
    """HQReset pushes onto the array it reads from the HQ. If the two names
    held different arrays that push would be lost at the next SitRep while its
    Busy stayed: a pinned squad that is not even on the list."""
    body = release()
    assert "+_kept" not in body
    assert body.count("_kept];") == 2


def test_release_keeps_everyone_else_from_either_copy():
    body = release()
    assert "private _kept = (_global + _hqList) - [_group];" in body


def test_release_is_a_no_op_for_a_squad_that_is_not_a_garrison():
    body = release()
    guard = body.index("if !(_group in _hqList || {_group in _global}) exitWith {false};")
    assert guard < body.index("_hq setVariable")
    assert guard < body.index("call ITW_CLASH_CommanderParity_fnc_Log")


def test_release_puts_the_garrisoned_flags_back_to_default():
    body = release()
    assert '_group setVariable ["Garrisoned" + str _group,false];' in body
    assert '_group setVariable ["NOGarrisoned" + str _group,false];' in body


# --- the Busy ---------------------------------------------------------------


def test_release_itself_never_writes_busy_or_break():
    body = release()
    assert not BUSY_WRITE.search(body)
    assert '"Break"' not in body


def test_release_marks_the_busy_only_when_there_is_one():
    body = release()
    assert 'private _busy = _group getVariable ["Busy" + str _group,false];' in body
    mark = body.index('_group setVariable ["ITW_CLASH_GarrisonBusyOrphan",true];')
    assert body.rindex("if (_busy) then {", 0, mark) > body.index("private _busy =")


def test_settle_does_nothing_without_the_mark():
    body = settle()
    first = body.index('if !(_group getVariable ["ITW_CLASH_GarrisonBusyOrphan",false]) exitWith {"none"};')
    assert first < body.index("spawn {")
    assert first < body.index('"Break"')


def test_settle_drops_the_mark_once_an_order_or_a_rest_owns_the_squad():
    body = settle()
    early = body[:body.index("spawn {")]
    assert "!(_group getVariable [_busyVar,false])" in early
    assert "|| {_group getVariable [_restVar,false]}" in early
    assert '_group setVariable ["ITW_CLASH_GarrisonBusyOrphan",nil];' in early


def test_one_probe_at_a_time():
    body = settle()
    assert 'if (_group getVariable ["ITW_CLASH_GarrisonBusyProbe",false]) exitWith {"probing"};' in body
    assert body.index('exitWith {"probing"};') < body.index("spawn {")


def test_the_probe_is_hals_own_cancel():
    probe = settle()
    probe = probe[probe.index("spawn {"):]
    asked = probe.index('_group setVariable ["Break",true];')
    waited = probe.index("waitUntil {")
    assert asked < waited
    assert "private _deadline = time + ITW_CLASH_GarrisonBusyProbeWait;" in probe


def test_busy_is_cleared_by_hand_only_after_break_went_unread():
    probe = settle()
    probe = probe[probe.index("spawn {"):]

    # The probe names the flag through _busyVar; no literal write hides here.
    assert not BUSY_WRITE.search(probe)
    assert probe.count("_group setVariable [_busyVar,") == 1
    clear = probe.index("_group setVariable [_busyVar,false];")
    assert 'private _busyVar = "Busy" + str _group;' in settle()

    # Everything that means "somebody answered" leaves before that line.
    answered = probe.index("if (_read || {!_busy} || {_resting}) exitWith {")
    assert probe.index("waitUntil {") < answered < clear

    # A read is noticed inside the wait, and ends it.
    wait = probe[probe.index("waitUntil {"):answered]
    assert '!(_group getVariable ["Break",false])' in wait
    assert "_read = true;" in wait
    assert "|| {_read}" in wait
    assert "|| {time >= _deadline}" in wait


def test_break_goes_with_the_busy_it_was_aimed_at():
    """Left set, it would abort the rest order the squad is about to get."""
    probe = settle()
    tail = probe[probe.index("_group setVariable [_busyVar,false];"):]
    assert '_group setVariable ["Break",false];' in tail
    assert '_group setVariable ["ITW_CLASH_GarrisonBusyOrphan",nil];' in tail
    assert '"garrison-busy-released"' in tail


def test_a_probe_that_found_a_reader_does_not_touch_busy_or_break():
    probe = settle()
    probe = probe[probe.index("if (_read || {!_busy} || {_resting}) exitWith {"):]
    branch = probe[:probe.index("};\n\n        _group setVariable [_busyVar,false];")]
    assert not BUSY_WRITE.search(branch)
    assert "_busyVar,false]" not in branch
    assert '["Break"' not in branch
    assert '"garrison-busy-owned"' in branch


def test_a_squad_in_a_lift_is_never_probed():
    """Break in a cargo loop strands the helicopter; that was the lift fix."""
    body = settle()
    held = body.index('if ([_group] call ITW_CLASH_CommanderParity_fnc_IsInLift) exitWith {"lifting"};')
    assert held < body.index("spawn {")
    assert held < body.index('_group setVariable ["Break",true];')

    order = code_only(function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_Order"))
    gate = order.index("if !([_group] call ITW_CLASH_CommanderParity_fnc_IsInLift) then {")
    assert gate < order.index("call ITW_CLASH_CommanderParity_fnc_ReleaseGarrison;")


def test_in_a_lift_means_what_the_anchor_already_meant_by_it():
    lift = function_body(parity(), "ITW_CLASH_CommanderParity_fnc_IsInLift")
    committed = function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_IsHALCommitted")
    for token in [
        '_group getVariable ["CargoChosen",false]',
        '_group getVariable ["CargoCheckPending" + str _group,false]',
        '_group getVariable ["ITW_CLASH_TransportRetaskLock",false]',
        "((units _group) findIf {alive _x && {vehicle _x != _x}}) >= 0",
    ]:
        assert token in lift, token
        assert token in committed, token
    assert "Busy" not in lift


def test_the_wait_is_a_tunable():
    source = parity()
    assert '"ITW_CLASH_GarrisonBusyProbeWait",20' in source


# --- who uses it ------------------------------------------------------------


def test_a_withdrawing_garrison_squad_is_released_through_the_projection():
    body = code_only(function_body(gtfo(), "ITW_CLASH_GTFO_fnc_ClearStaleHALRoles"))
    released = body.index("call ITW_CLASH_CommanderParity_fnc_ReleaseGarrison}")
    hq_only = body.index("_hq setVariable [_name,_members - [_group]];")
    assert released < hq_only
    assert '_removed pushBack "RydHQ_Garrison";' in body
    assert "call ITW_CLASH_CommanderParity_fnc_SettleGarrisonBusy;" in body
    # Still tracked withdrawals only.
    assert body.index("ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal") < released


def test_the_withdrawal_still_works_without_commander_parity():
    body = code_only(function_body(gtfo(), "ITW_CLASH_GTFO_fnc_ClearStaleHALRoles"))
    assert '!isNil "ITW_CLASH_CommanderParity_fnc_ReleaseGarrison"' in body
    assert '!isNil "ITW_CLASH_CommanderParity_fnc_SettleGarrisonBusy"' in body
    listed = body[body.index("} forEach ["):]
    assert '"RydHQ_Garrison"' in listed[:listed.index("];")]


def test_the_withdrawal_runtime_itself_still_never_clears_an_orders_busy():
    """Hark's rule in that file: the order that owns Busy releases it."""
    restart = code_only(function_body(gtfo(), "ITW_CLASH_GTFO_fnc_RequestNativeRestRestart"))
    assert not BUSY_WRITE.search(restart)
    roles = code_only(function_body(gtfo(), "ITW_CLASH_GTFO_fnc_ClearStaleHALRoles"))
    assert not BUSY_WRITE.search(roles)


def test_the_anchor_takes_its_squad_back_before_it_asks_whether_hal_has_it():
    order = code_only(function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_Order"))
    thread = order[order.index("spawn {"):]
    released = thread.index('[_group,"anchor-order"] call ITW_CLASH_CommanderParity_fnc_ReleaseGarrison;')
    settled = thread.index("ITW_CLASH_CommanderParity_fnc_SettleGarrisonBusy)")
    committed = thread.index("call ITW_CLASH_CommanderParity_Anchor_fnc_IsHALCommitted) exitWith {")
    broke = thread.index('_group setVariable ["Break",true];')
    issued = thread.index("HAL_GoDef] call RYD_Spawn;")
    assert released < settled < committed < broke < issued


def test_the_anchor_wait_is_bounded():
    order = code_only(function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_Order"))
    assert "private _settleBy = time + ITW_CLASH_GarrisonBusyProbeWait + 5;" in order
    assert "&& {time < _settleBy}" in order


def test_busy_still_counts_as_hal_having_the_squad():
    """The lift fix stands. Only the garrison's Busy is ever released, and by
    the probe, not by teaching this test to ignore Busy."""
    committed = function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_IsHALCommitted")
    assert '_group getVariable ["Busy" + str _group,false]' in committed
    assert "Garrison" not in committed


def test_hal_source_is_not_edited_or_patched_for_this():
    for name in ["ITW_CLASH_CommanderParity.sqf", "ITW_CLASH_GTFO_Runtime.sqf"]:
        source = code_only(mission(name))
        assert "HQReset.sqf\"" not in source
        assert "HAL_HQReset =" not in source


def test_the_boot_lines_say_the_fix_is_loaded():
    source = parity()
    assert "ITW_CLASH_CommanderParityVersion = 4;" in source
    assert "garrisonRelease=true garrisonBusyProbe=%3" in source
    runtime = gtfo()
    assert "ITW_CLASH_GTFORuntimeVersion = 5;" in runtime
    assert "garrisonRelease=true" in runtime
