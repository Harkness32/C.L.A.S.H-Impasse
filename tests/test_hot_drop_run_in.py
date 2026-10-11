"""HotDrop never fired, and could not.

Hark: "HOTDROPs never fire because the lift is always busy or already
reserved. its a flaw in our implementation."

Three flights on 2026-10-10 (20:14, 20:53, 23:22):

    hot-drop-declined-busy                111
    hot-drop-declined-reserved-carrier     26
    hot-drop-claimed                        0

ITW_CLASH_HotDrop.sqf polled for a loaded helicopter on the ground and took it,
unless its crew group was Busy. HAL_SCargo sets Busy on the carrier before it
flies to the pickup and clears it only after the return, so every helicopter
HAL has loaded is Busy for the whole of that window. Everything else that loads
a helicopter (CASEVAC, MEDEVAC, reconstitution) is declined as reserved. The
set of lifts it could take was empty by construction. The busy declines on the
23:22 flight are the same carriers the unload owner then paradropped: Alpha
4-4, Alpha 3-2, Bravo 1-2.

Dropping the Busy rule is run8 again, two pilots on one Littlebird. The lift
already has an owner for its last kilometre: ITW_CLASH_HALUnload.sqf, handed
the aircraft by HAL's own waypoint. So:

  - the hot drop is the unload owner's run-in, on HOT and CONTESTED corridors
    (Hark's choice; UNKNOWN stays a plain paradrop);
  - flares come in three stages, Hark's words: "start preflaring when we're
    decently close to the drop, then HAMMER THEM as we're away and then keep
    spraying them as we egress";
  - the HotDrop poll is off by default. Its code is left in place until the
    run-in hot drop has flown.
"""

import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


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


def unload() -> str:
    return read(MISSION / "ITW_CLASH_HALUnload.sqf")


def hotdrop() -> str:
    return read(MISSION / "ITW_CLASH_HotDrop.sqf")


def body_of(name: str) -> str:
    return code_only(function_body(unload(), f"ITW_CLASH_HALUnload_fnc_{name}"))


def tunable(name: str) -> float:
    match = re.search(rf'"ITW_CLASH_HALUnload{name}",\s*([0-9.]+)', unload())
    assert match, name
    return float(match.group(1))


# --- why the old module could not fire -------------------------------------


def test_the_two_rules_that_exclude_each_other_are_both_still_in_the_source():
    """Each was right when written. Together they leave nothing to claim."""
    eligible = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    # Only a helicopter on the ground ...
    assert "(((getPosATL _veh)#2) > ITW_CLASH_HotDropBoardingHeight) exitWith {false};" in eligible
    # ... whose crew group is not Busy ...
    assert '_crewGroup getVariable [("Busy" + str _crewGroup),false]' in eligible
    assert '"declined-busy"' in eligible
    # ... and not reserved.
    assert '"declined-reserved-carrier"' in eligible

    # And it has to be loaded.
    consider = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Consider"))
    assert "call ITW_CLASH_HotDrop_fnc_Aboard) isEqualTo []) exitWith {false};" in consider


def test_hal_holds_busy_on_the_carrier_from_before_pickup_until_after_the_return():
    scargo = read(HAL / "SCargo.sqf")
    taken = scargo.index('_GD setVariable [("Busy" + (str _GD)), true];')
    # Before the carrier is given its pickup waypoint ...
    assert taken < scargo.index("RYD_WPadd", taken)
    # ... and before the chalk is marked as riding.
    assert taken < scargo.index('"CargoM" + (str _GD)', taken)
    # Released only at the executor's exits.
    released = [m.start() for m in re.finditer(
        r'_GD setVariable \[\("Busy" \+ (?:\(str _GD\)|_unitvar)\), false\];', scargo
    )]
    assert len(released) == 4, released
    assert all(at > taken for at in released)


# --- the poll is off, nothing else in that file moved -----------------------


def test_the_hotdrop_poll_is_off_by_default():
    source = hotdrop()
    assert 'missionNamespace getVariable ["ITW_CLASH_HotDropEnabled",false];' in source
    assert '["ITW_CLASH_HotDropEnabled",true]' not in source
    poll = code_only(source[source.index('scriptName "ITW_CLASH_HotDrop";'):])
    assert poll.index("if (ITW_CLASH_HotDropEnabled) then {") < poll.index(
        "call ITW_CLASH_HotDrop_fnc_Consider;"
    )


def test_the_hotdrop_boot_line_says_who_flies_hot_drops_now():
    source = hotdrop()
    assert "enabled=%9 hotDropsFlownBy=hal-unload" in source
    tail = source[source.index('"CLASH BOOT | hot-drop-ready'):]
    assert "ITW_CLASH_HotDropEnabled\n];" in tail


def test_what_the_unload_owner_still_calls_in_that_file_is_still_there():
    assert "ITW_CLASH_HotDrop_fnc_Destination = {" in hotdrop()
    assert "ITW_CLASH_HotDrop_fnc_Destination" in unload()
    # The file still loads and still reports ready, so preflight is unchanged.
    assert "ITW_CLASH_HotDropReady = true;" in hotdrop()


def test_the_unload_owner_no_longer_needs_hotdrop_for_flares():
    source = code_only(unload())
    assert "ITW_CLASH_HotDrop_fnc_Flare" not in source
    assert "StartHotFlares" not in source


# --- which corridors are hot -------------------------------------------------


def test_hot_and_contested_are_hot_and_unknown_is_not():
    source = unload()
    match = re.search(r'"ITW_CLASH_HALUnloadHotStates",(\[[^\]]*\])', source)
    states = re.findall(r'"([A-Z_]+)"', match.group(1))
    assert set(states) == {"HOT", "AIR_DENIED", "CONTESTED"}
    assert "UNKNOWN" not in states and "COLD" not in states


def test_the_mode_table_reads_the_list_and_keeps_every_dangerous_corridor_a_drop():
    mode = body_of("Mode")
    hot = mode.index("if (_state in ITW_CLASH_HALUnloadHotStates) exitWith {")
    drop = mode.index('if (_state in ["HOT","AIR_DENIED","CONTESTED","UNKNOWN"]) exitWith {')
    roll = mode.index("ITW_CLASH_HALParadrop_fnc_ShouldUse")
    assert hot < drop < roll
    assert '["HOT_PARADROP",100,_capacity]' in mode[hot:drop]
    assert '["PARADROP",100,_capacity]' in mode[drop:roll]
    # The host's "never parachute" setting still comes first.
    assert mode.index("if (_param == 0) exitWith {") < hot


def test_hot_decides_flares_and_the_corridor_still_decides_landing():
    """CONTESTED could always fall back to a landing when a drop was refused.
    Calling it hot must not take that away, and must not give it to HOT."""
    seam = body_of("Unload")
    hot = seam[seam.index('case "HOT_PARADROP"'):seam.index('case "NO_LAND"')]
    assert 'private _noLand = _state in ["HOT","AIR_DENIED","UNKNOWN"];' in hot
    assert "[_carrierGroup,_carrier,!_noLand] call" in hot
    refused = hot[hot.index("} else {"):]
    assert refused.index("if (_noLand) then {") < refused.index('_result = "NO_LAND"')
    assert refused.index('_result = "NO_LAND"') < refused.index('_carrier land "GET OUT";')
    assert '_result = "LAND_FALLBACK"' in refused


# --- flares: the stages ------------------------------------------------------


def test_the_stage_is_a_pure_function_of_the_release_time():
    stage = body_of("FlareStage")
    pre = stage.index('if (_releasedAt < 0) exitWith {"PRE"};')
    hammer = stage.index('exitWith {"HAMMER"};')
    egress = stage.index('exitWith {"EGRESS"};')
    assert pre < hammer < egress
    assert "_since < ITW_CLASH_HALUnloadFlareHammerSeconds) exitWith" in stage
    assert "ITW_CLASH_HALUnloadFlareEgressSeconds" in stage
    for forbidden in ("setVariable", "getVariable", "call ", "diag_log"):
        assert forbidden not in stage, forbidden


def test_the_hammer_is_the_densest_stage_and_the_egress_outlasts_it():
    pre = tunable("FlarePreCadence")
    hammer = tunable("FlareHammerCadence")
    egress = tunable("FlareEgressCadence")
    assert hammer < egress < pre
    assert tunable("FlareEgressSeconds") > tunable("FlareHammerSeconds")
    # "Decently close": inside the distance the run-in is armed at, so the
    # aircraft is already ours when the first one goes.
    assert tunable("FlareStart") <= tunable("RunInDistance")


def test_the_flares_do_not_stop_when_the_chalk_is_out():
    """The old hot mode flared `while` someone was still aboard, so it went
    quiet as the aircraft turned away. That is the reverse of what was asked."""
    body = body_of("StartFlares")
    assert "ITW_CLASH_HALUnload_fnc_Aboard" not in body
    assert "ITW_CLASH_HALParadrop_ClimbTimeout" not in body


def test_pre_flaring_waits_for_the_distance_and_for_a_live_run():
    body = body_of("StartFlares")
    pre = body[body.index('case "PRE": {\n                            _spent < _preAllow'):]
    pre = pre[:pre.index('case "HAMMER"')]
    assert "(_carrier distance2D _dropZone)" in pre
    assert "<= ITW_CLASH_HALUnloadFlareStart" in pre
    # A run handed back to HAL, or armed and never released, stops flaring.
    assert 'if !(_phase in ["RUN_IN","DROPPING","SEAM"]) then {' in body
    assert '_why = "run-ended";' in body
    assert 'if (time >= _preBy) then {_why = "no-release"};' in body


def test_a_new_stage_pulls_at_once():
    """Otherwise the hammer starts up to one PRE interval after the release."""
    body = body_of("StartFlares")
    change = body.index("if (_stage isNotEqualTo _last) then {")
    assert "_next = 0;" in body[change:change + 120]
    assert change < body.index("if (_why isEqualTo \"\" && {time >= _next}) then {")


def test_the_limit_is_rounds_read_off_the_launcher_not_a_count_of_pulls():
    """What one pull dispenses differs by launcher mode and modset."""
    body = body_of("StartFlares")
    assert "private _rounds = [_carrier] call ITW_CLASH_HALUnload_fnc_FlareRounds;" in body
    assert "private _allow = _rounds * ITW_CLASH_HALUnloadFlareSpend;" in body
    assert "private _preAllow = _allow * ITW_CLASH_HALUnloadFlarePreShare;" in body
    assert "ITW_CLASH_HALUnloadFlarePreShare + ITW_CLASH_HALUnloadFlareHammerShare" in body
    read_back = body.index("_left = [_carrier] call ITW_CLASH_HALUnload_fnc_FlareRounds;")
    assert read_back < body.index("call ITW_CLASH_ThunderRun_fnc_FireCountermeasure")
    assert 'case "HAMMER": {_spent < _hammerAllow};' in body
    assert "default {_spent < _allow};" in body

    rounds = body_of("FlareRounds")
    assert "magazinesAllTurrets [_carrier,true]" in rounds
    assert '"shotcm"' in rounds


def test_the_shares_leave_the_egress_something():
    spend = tunable("FlareSpend")
    pre = tunable("FlarePreShare")
    hammer = tunable("FlareHammerShare")
    assert 0 < spend <= 1
    assert pre < hammer, "the hammer gets more than the warm-up"
    assert pre + hammer < 1, "what is left over is the egress's"
    assert 1 - pre - hammer >= 0.25


def simulate(rounds: int, per_pull: int, release_after: float, speed: float = 58.0):
    """The thread's own arithmetic, at 0.1 s, with the source's numbers.

    Armed 1200 m out at 58 m/s (the 23:22 run-ins were 206 to 220 km/h).
    Returns pulls per stage, the time of the first pull of each stage and the
    rounds left."""
    start = tunable("FlareStart")
    cadence = {
        "PRE": tunable("FlarePreCadence"),
        "HAMMER": tunable("FlareHammerCadence"),
        "EGRESS": tunable("FlareEgressCadence"),
    }
    hammer_s = tunable("FlareHammerSeconds")
    egress_s = tunable("FlareEgressSeconds")
    allow = rounds * tunable("FlareSpend")
    pre_allow = allow * tunable("FlarePreShare")
    hammer_allow = allow * (tunable("FlarePreShare") + tunable("FlareHammerShare"))

    left = rounds
    pulls = {"PRE": 0, "HAMMER": 0, "EGRESS": 0}
    first = {}
    nxt, last, t = 0.0, "", 0.0
    while True:
        t = round(t + 0.1, 1)
        if t < release_after:
            stage = "PRE"
        elif t - release_after < hammer_s:
            stage = "HAMMER"
        elif t - release_after < hammer_s + egress_s:
            stage = "EGRESS"
        else:
            break
        if stage != last:
            last, nxt = stage, 0.0
        if t < nxt:
            continue
        spent = rounds - left
        distance = abs(1200 - speed * t)
        ok = {
            "PRE": spent < pre_allow and distance <= start,
            "HAMMER": spent < hammer_allow,
            "EGRESS": spent < allow,
        }[stage]
        if stage == "EGRESS" and spent >= allow:
            break
        if ok:
            left = max(0, left - per_pull)
            pulls[stage] += 1
            first.setdefault(stage, t)
            nxt = t + cadence[stage]
        else:
            nxt = t + 0.5
    return pulls, first, left


def test_the_numbers_do_what_hark_asked_on_a_one_round_launcher():
    release = 1200 / 58.0
    pulls, first, left = simulate(rounds=168, per_pull=1, release_after=release)
    # Pre-flaring starts once inside FlareStart, not at arming.
    assert first["PRE"] >= (1200 - tunable("FlareStart")) / 58.0
    assert 3 <= pulls["PRE"] <= 10
    # The hammer starts on the release, not an interval later.
    assert first["HAMMER"] - release <= 0.2
    assert pulls["HAMMER"] >= 20
    # And it keeps going on the way out.
    assert pulls["EGRESS"] >= 15
    # Densest in the hammer.
    assert pulls["HAMMER"] / tunable("FlareHammerSeconds") > pulls["EGRESS"] / tunable("FlareEgressSeconds")
    assert left > 0


def test_a_greedy_burst_launcher_still_has_rounds_for_every_stage():
    """Sixty rounds and ten a pull: a count of pulls would have emptied it
    before the drop."""
    release = 1200 / 58.0
    pulls, first, left = simulate(rounds=60, per_pull=10, release_after=release)
    assert pulls["PRE"] >= 1
    assert pulls["HAMMER"] >= 1
    assert pulls["EGRESS"] >= 1
    assert pulls["PRE"] < pulls["HAMMER"] + pulls["EGRESS"]
    # FlareSpend is honoured to within the one pull that crosses it.
    assert left >= 60 * (1 - tunable("FlareSpend")) - 10


def test_one_hot_drop_does_not_empty_the_launcher():
    pulls, first, left = simulate(rounds=120, per_pull=4, release_after=1200 / 58.0)
    assert left >= math.floor(120 * (1 - tunable("FlareSpend"))) - 4


# --- flares: the thread --------------------------------------------------------


def test_flares_fire_through_thunder_runs_primitive():
    """So a modset's countermeasure override is honoured here too."""
    body = body_of("StartFlares")
    assert "[_carrier] call ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter" in body
    assert "[_state] call ITW_CLASH_ThunderRun_fnc_FireCountermeasure" in body
    assert '["countermeasureEmitter",_emitter]' in body
    assert "forceWeaponFire" not in body


def test_the_flare_thread_owns_no_movement():
    body = body_of("StartFlares")
    for forbidden in (
        "doMove", "commandMove", "addWaypoint", "setWaypointPosition",
        "deleteWaypoint", "RYD_WPdel", "flyInHeight", "limitSpeed",
        "forceSpeed", "setSpeedMode", "setBehaviour", "setCombatMode", "land ",
    ):
        assert forbidden not in body, forbidden


def test_one_flare_thread_per_lift():
    """The seam can take over a run that is already armed."""
    body = body_of("StartFlares")
    guard = body.index('(_carrierGroup getVariable ["ITW_CLASH_HALUnloadFlareSerial",-2])')
    claim = body.index('_carrierGroup setVariable ["ITW_CLASH_HALUnloadFlareSerial",_serial];')
    assert guard < claim < body.index("spawn {")
    assert "isEqualTo _serial\n    ) exitWith {false};" in body[guard:claim]


def test_the_thread_ends_with_the_lift():
    body = body_of("StartFlares")
    for why in ('"lift-gone"', '"carrier-lost"', '"next-lift"', '"done"', '"spent"'):
        assert why in body, why
    assert '(_carrierGroup getVariable ["ITW_CLASH_HALUnloadSerial",-1])' in body


def test_a_run_that_never_released_may_be_flared_by_whoever_takes_it_next():
    body = body_of("StartFlares")
    tail = body[body.index("&& {_released < 0}"):]
    assert '_carrierGroup setVariable ["ITW_CLASH_HALUnloadFlareSerial",nil];' in tail
    # And a run handed back to HAL forgets its release.
    assert '"ITW_CLASH_HALUnloadFlareRelease"' in body_of("ClearDropState")
    assert "call ITW_CLASH_HALUnload_fnc_ClearDropState;" in body_of("AbortRunIn")


def test_no_launcher_is_said_once_and_is_not_an_error():
    body = body_of("StartFlares")
    assert body.count('"flares-none"') == 2
    assert '"no-launcher-or-empty"' in body
    assert '"no-thunder-run"' in body


def test_one_line_says_what_was_fired():
    body = body_of("StartFlares")
    line = body[body.index('["flares",['):]
    assert "_pre,_hammer,_egress,_rounds,_left,_why," in line


# --- where the run-in and the seam start it ------------------------------------


def test_the_run_in_starts_flares_when_it_arms_a_hot_run():
    run = body_of("RunIn")
    armed = run.index("call ITW_CLASH_HALUnload_fnc_ArmRunIn) exitWith {")
    start = run.index("[_carrierGroup,_carrier,_dropZone] call ITW_CLASH_HALUnload_fnc_StartFlares;")
    assert armed < start
    gate = run.rindex('if (_mode isEqualTo "HOT_PARADROP") then {', 0, start)
    # Inside that gate: nothing closes the block between the two.
    assert "\n    };" not in run[gate:start]


def test_the_hammer_starts_as_the_first_man_goes():
    run = body_of("RunIn")
    mark = run.index('_carrierGroup setVariable ["ITW_CLASH_HALUnloadFlareRelease",_releasedAt];')
    assert run.index("private _releasedAt = time;") < mark
    assert mark < run.index("ITW_CLASH_HALParadrop_fnc_Execute")
    # Not before the pass is known to be a drop.
    assert run.index('"passed-wide"') < mark
    assert run.index('"never-crossed"') < mark


def test_the_seam_flares_a_hot_drop_the_same_way():
    seam = body_of("Unload")
    hot = seam[seam.index('case "HOT_PARADROP"'):seam.index('case "NO_LAND"')]
    start = hot.index("ITW_CLASH_HALUnload_fnc_StartFlares;")
    mark = hot.index('_carrierGroup setVariable ["ITW_CLASH_HALUnloadFlareRelease",time];')
    assert start < mark < hot.index("ITW_CLASH_HALParadrop_fnc_Execute")
    # A refused drop takes the release back.
    assert '_carrierGroup setVariable ["ITW_CLASH_HALUnloadFlareRelease",nil];' in hot[mark:]
    para = seam[seam.index('case "PARADROP"'):seam.index('case "HOT_PARADROP"')]
    assert "StartFlares" not in para


def test_the_boot_line_says_what_is_hot_and_how_it_flares():
    source = unload()
    assert "ITW_CLASH_HALUnloadVersion = 8;" in source
    assert "hotStates=%12 flares=%13 flareStart=%14 flareHammer=%15s/%16s flareEgress=%17s/%18s" in source


def test_a_hot_drop_says_so_in_the_log_and_in_game():
    run = body_of("RunIn")
    said = run.index('["hot-drop",[')
    assert run.rindex('if (_mode isEqualTo "HOT_PARADROP") then {', 0, said) > run.index(
        "call ITW_CLASH_HALUnload_fnc_ArmRunIn) exitWith {"
    )
    assert said < run.index("call ITW_CLASH_HALUnload_fnc_StartFlares;")
    seam = body_of("Unload")
    hot = seam[seam.index('case "HOT_PARADROP"'):seam.index('case "NO_LAND"')]
    assert '["hot-drop",[' in hot

    loud = read(MISSION / "ITW_CLASH_LoudDebug.sqf")
    for key in ('"hal-unload|hot-drop"', '"hal-unload|flares"', '"hal-unload|flares-none"'):
        assert f"case {key}: {{" in loud, key
    # The unload owner's logger is what speaks them.
    log = function_body(unload(), "ITW_CLASH_HALUnload_fnc_Log")
    assert '["hal-unload",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;' in log
