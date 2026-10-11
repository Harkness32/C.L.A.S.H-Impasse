"""A helicopter fills with its chalk and then never leaves.

Hark: "helos arent launching, they fill with their chalk and then stay"

Run of 2026-10-10 20:53, BLUFOR lifts:

    G30  anchor-promoted 20:56:50, lift requested 20:56:55, embarked 20:57:41
         -> POST-EMBARK-NO-OUTBOUND-MOVE until the log ends
    G34  anchor-promoted 20:57:43, lift requested 20:57:43, embarked 20:58:17
         -> the same
    G32  anchor-promoted 20:58:18 while walking to its carrier
         -> recon order aborted, lift cancelled
    G29  no promotion during its lift
         -> boarded, flew, paradropped at 21:03:33

CommanderParity takes an anchor by setting Break on the squad and then issuing
HAL_GoDef. Break does not abort a HAL order that is in its cargo loop. The loop
reads it as "leave after this pass", resets _alive two lines later and still
spawns HAL_SCargo in that pass. The order then walks on while SCargo finishes
the pickup alone, the base embark teleports the squad into the carrier, and
nobody is left to write the outbound waypoint. Both stuck squads show a fresh
foot waypoint to the recon destination six seconds after the lift request.

HAL_GoDef exits at once on a Busy group, so the promotion bought nothing.

Two changes:

  - the anchor never takes, breaks or unwinds a squad HAL is using;
  - the base-embark seam cancels a lift whose squad already has its own route,
    through HAL's own abort, for every other source of Break.

The run without the addon (20:14) launched its lifts because its only anchor,
G29 with fifteen men, was never a lifted squad. It is not evidence about the
addon either way.
"""

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


def embark() -> str:
    return mission("ITW_CLASH_HALCargoDiceFix.sqf")


BREAK_ENDS_LOOP = (
    'if (_unitG getVariable ["Break",false]) then '
    '{_endThis = true;_alive = false; _unitG setVariable ["Break",false];}'
)
SPAWN_LIFT = "[[_unitG,_HQ,[_posX,_posY]],HAL_SCargo] call RYD_Spawn;"
BUSY_GATE = 'if not (_unitG getVariable [("Busy" + (str _unitG)),false]) exitwith {};'


# ------------------------------------------------------- the premise, in HAL

def test_break_ends_the_cargo_loop_but_still_spawns_the_lift():
    """The whole fault is this ordering, and it is stock HAL. If an NR6 update
    changes it, the reasoning above needs reading again."""
    for name in ("GoRecon.sqf", "GoAttInf.sqf", "GoCapture.sqf"):
        source = code_only(hal(name))
        at_break = source.index(BREAK_ENDS_LOOP)
        # _alive is put back before anything reads it.
        at_reset = source.index("_alive = true;", at_break)
        at_spawn = source.index(SPAWN_LIFT, at_break)
        at_end = source.index("(_endThis)", at_break)
        assert at_break < at_reset < at_spawn < at_end, name


def test_the_order_carries_on_after_the_loop_as_long_as_it_is_busy():
    for name in ("GoRecon.sqf", "GoAttInf.sqf", "GoCapture.sqf"):
        source = code_only(hal(name))
        at_end = source.index("(_endThis)", source.index(BREAK_ENDS_LOOP))
        assert BUSY_GATE in source[at_end:at_end + 400], name


def test_godef_refuses_a_busy_group_so_the_promotion_bought_nothing():
    source = code_only(hal("GoDef.sqf"))
    assert '_busy = _unitG getvariable ("Busy" + _unitvar);' in source
    assert 'if ((_busy) or (_unitG in (_HQ getVariable ["RydHQ_SupportG",[]]))) exitwith' in source


def test_godef_never_marks_its_own_group_busy():
    """Why Busy can be the test: a squad holding as anchor is under GoDef, and
    GoDef leaves Busy alone, so the rule cannot evict a working anchor."""
    source = code_only(hal("GoDef.sqf"))
    assert '("Busy" + _unitvar), true]' not in source


# ------------------------------------------------- the anchor leaves HAL alone

def test_committed_means_busy_lifting_locked_or_riding():
    body = function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_IsHALCommitted")
    assert '_group getVariable ["Busy" + str _group,false]' in body
    assert '_group getVariable ["CargoChosen",false]' in body
    assert '_group getVariable ["CargoCheckPending" + str _group,false]' in body
    assert '_group getVariable ["ITW_CLASH_TransportRetaskLock",false]' in body
    assert "vehicle _x != _x" in body


def test_the_flags_are_the_ones_hal_and_the_bridge_actually_write():
    scargo = hal("SCargo.sqf")
    assert '_unitG setVariable ["CargoChosen",true,true]' in scargo
    assert '_unitG setVariable ["CargoCheckPending" + (str _unitG),true];' in scargo
    authority = mission("ITW_CLASH_PlayerTransportAuthority.sqf")
    assert '_group setVariable ["ITW_CLASH_TransportRetaskLock",true];' in authority


def test_a_committed_squad_is_never_selected():
    body = function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_Select")
    eligible = body.index("ITW_CLASH_CommanderParity_Anchor_fnc_IsEligible")
    committed = body.index("ITW_CLASH_CommanderParity_Anchor_fnc_IsHALCommitted")
    assert eligible < committed
    assert "continue" in body[committed:committed + 80]
    # ...and both come before any candidate is scored.
    assert committed < body.index("_bestStrongScore = _score;")


def test_break_is_never_set_on_a_committed_squad():
    """Checked at the write, not only at selection: the squad can be tasked
    between the audit that chose it and the order thread being scheduled."""
    body = function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_Order")
    committed = body.index("ITW_CLASH_CommanderParity_Anchor_fnc_IsHALCommitted")
    brk = body.index('_group setVariable ["Break",true];')
    assert committed < brk
    guard = body[committed:brk]
    assert "exitWith" in guard
    assert '"order-deferred"' in guard
    assert '"ITW_CLASH_CommanderParity_AnchorOrderPending",nil' in guard
    # One Break in the function, and it is the guarded one.
    assert body.count('["Break",true]') == 1


def test_releasing_an_anchor_does_not_unwind_a_squad_hal_now_owns():
    """G30's route was deleted at 20:57:43, two seconds after it was put in a
    helicopter, because being aboard made it ineligible and Clear unwound it."""
    body = function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_Clear")
    gate = body.index("if !([_group] call ITW_CLASH_CommanderParity_Anchor_fnc_IsHALCommitted) then {")
    for write in (
        '_group setVariable ["Defending",false];',
        '_group setVariable ["Break",false];',
        "[_group] call RYD_WPdel;",
        "{deleteWaypoint _x} forEachReversed waypoints _group;",
    ):
        assert body.count(write) == 1, write
        assert body.index(write) > gate, write
    # The bookkeeping is still unconditional.
    assert body.index('"ITW_CLASH_CommanderParity_AnchorObjective",nil') < gate
    assert "ITW_CLASH_CommanderParity_AnchorGroups deleteAt _key;" in body


def test_eligibility_itself_did_not_learn_about_busy():
    """Eligibility is also how a standing anchor is kept. Putting Busy there
    would make the audit evict and unwind an anchor for a transient flag."""
    body = function_body(parity(), "ITW_CLASH_CommanderParity_Anchor_fnc_IsEligible")
    assert "Busy" not in body
    assert "IsHALCommitted" not in body


def test_the_boot_line_says_the_rule_is_loaded():
    source = parity()
    assert "ITW_CLASH_CommanderParityVersion = 3;" in source
    assert "anchorSkipsHALCommitted=true" in source


# --------------------------------------------- the lift nobody is waiting for

def test_a_waiting_order_parks_its_squad():
    """What makes "has its own route" a sign at all."""
    park = "setWaypointPosition [getPosATL (vehicle (leader _unitG)), 0]"
    for name in ("GoRecon.sqf", "GoAttInf.sqf", "GoCapture.sqf"):
        assert code_only(hal(name)).count(park) >= 2, name
    # The older protocol deletes the waypoints outright before it asks.
    for name, spawn in (
        ("GoFlank.sqf", "[[_unitG,_HQ,[_posXWP4,_posYWP4]],HAL_SCargo] call RYD_Spawn;"),
        ("GoSFAttack.sqf", "[[_unitG,_HQ,[_posXWP4,_posYWP4]],HAL_SCargo] call RYD_Spawn;"),
    ):
        source = code_only(hal(name))
        at_spawn = source.index(spawn)
        assert "[_unitG] call RYD_WPdel;" in source[:at_spawn], name


def test_the_route_must_be_far_from_the_squad_and_from_the_carrier():
    body = function_body(embark(), "ITW_CLASH_HALCargoDice_fnc_OrphanReason")
    assert "waypointPosition [_unitG,_current]" in body
    assert "currentWaypoint _unitG" in body
    assert "_current >= count _waypoints" in body, "a finished route is not a route"
    assert "(_target distance2D (leader _unitG)) > _limit" in body
    # SCargo walks a squad to an off-road pickup point itself.
    assert "(_target distance2D _vehicle) > _limit" in body
    assert "ITW_CLASH_OrphanLiftRouteDistance" in body
    assert '"own-route"' in body
    native = hal("SCargo.sqf")
    assert "_wp = [_unitG,([_Lpos,30] call RYD_RandomAround)] call RYD_WPadd;" in native


def test_the_distance_sits_between_what_the_runs_measured():
    """Seven healthy lifts had nothing further than 60m. Both orphans had 3.9km."""
    import re
    source = embark()
    limit = int(re.search(r'"ITW_CLASH_OrphanLiftRouteDistance",(\d+)', source).group(1))
    assert 60 < limit < 3900
    assert limit >= 150, "inside a base footprint is not a route"


def test_one_reading_is_never_enough_to_cancel_a_lift():
    body = function_body(embark(), "ITW_CLASH_HALCargoDice_fnc_OrphanLift")
    assert body.count("call ITW_CLASH_HALCargoDice_fnc_OrphanReason") == 2
    first = body.index("call ITW_CLASH_HALCargoDice_fnc_OrphanReason")
    wait = body.index("sleep ITW_CLASH_OrphanLiftConfirmSeconds;")
    second = body.rindex("call ITW_CLASH_HALCargoDice_fnc_OrphanReason")
    assert first < wait < second
    # Where it cannot wait it gives no verdict.
    assert 'if (!canSuspend) exitWith {""};' in body
    assert body.index("canSuspend") < wait


def test_the_confirmation_spans_a_full_pass_of_the_order_loop():
    import re
    source = embark()
    seconds = int(re.search(r'"ITW_CLASH_OrphanLiftConfirmSeconds",(\d+)', source).group(1))
    # The cargo loops poll on `sleep 5`.
    assert "sleep 5;" in hal("GoRecon.sqf")
    assert seconds > 5


def test_an_orphaned_lift_is_cancelled_before_anyone_is_seated():
    body = function_body(embark(), "ITW_CLASH_HALCargoDice_fnc_BaseEmbark")
    orphan = body.index("call ITW_CLASH_HALCargoDice_fnc_OrphanLift")
    assert orphan < body.index("_x assignAsCargo _vehicle;")
    assert orphan < body.index("_x moveInCargo _vehicle;")
    # Players are turned away first, so a human's own waypoints are never read.
    assert body.index('["player-in-squad"] call _decline') < orphan


def test_it_cancels_through_hals_own_abort():
    """Clearing CargoM is how HAL's order files call a lift off. SCargo's seat
    wait reads it and takes its own return-to-base exit, which frees the
    carrier. Nothing here writes a waypoint or touches Busy."""
    body = function_body(embark(), "ITW_CLASH_HALCargoDice_fnc_BaseEmbark")
    start = body.index("call ITW_CLASH_HALCargoDice_fnc_OrphanLift")
    block = body[start:body.index("// The confirmation above", start)]
    assert '_orphanCarrierG setVariable ["CargoM" + str _orphanCarrierG,false];' in block
    assert "orphan-lift-cancelled" in block
    assert block.rstrip().endswith("true\n    };"), "the caller must not seat anybody"
    for forbidden in ("addWaypoint", "RYD_WPadd", "RYD_WPdel", "doMove", "moveInCargo",
                      '"Busy" + str _orphanCarrierG', "land "):
        assert forbidden not in block, forbidden

    native = code_only(hal("SCargo.sqf"))
    seat_wait = native.index('if not (_GD getvariable [("CargoM" + (str _GD)),false]) then {_alive = false;};')
    abort = native.index("if not (_alive) exitwith {", seat_wait)
    exit_block = native[abort:abort + 2600]
    assert "_ChosenOne land 'NONE';" in exit_block
    assert '_unitG setVariable ["CargoCheckPending" + (str _unitG),false];' in exit_block
    assert '_GD setVariable [("Busy" + (str _GD)), false];' in exit_block


def test_the_squad_is_read_again_after_the_wait():
    body = function_body(embark(), "ITW_CLASH_HALCargoDice_fnc_BaseEmbark")
    orphan = body.index("call ITW_CLASH_HALCargoDice_fnc_OrphanLift")
    reread = body.index("_troops = (units _unitG) select {alive _x};", orphan)
    assert reread < body.index('["not-all-on-foot"] call _decline')


def test_the_scargo_source_patch_itself_did_not_change():
    """The guard lives inside the function the patch already calls, so the
    all-or-nothing text swap is exactly what the earlier runs certified."""
    source = embark()
    assert (
        'private _clashBaseEmbarked = false; if (not (_withdraw) and not (_request) '
        'and not (_emptyV) and {!isNil "ITW_CLASH_HALCargoDice_fnc_BaseEmbark"}) then '
        '{_clashBaseEmbarked = [_unitG,_ChosenOne,_HQ] call ITW_CLASH_HALCargoDice_fnc_BaseEmbark;};'
    ) in source
    assert "ITW_CLASH_HALCargoDiceFixVersion = 6;" in source
    assert "orphanLiftGuard=true" in source
