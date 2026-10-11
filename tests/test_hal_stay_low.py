import re
from pathlib import Path

from tools import approach_sim as sim

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal"
HAL = NR6 / "HAL"
G = 9.81
KMH = 3.6


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def function_body(source: str, name: str) -> str:
    start = source.index(f"{name} = {{")
    depth = 0
    in_string = False
    i = source.index("{", start)
    while i < len(source):
        ch = source[i]
        if ch == '"':
            if in_string and i + 1 < len(source) and source[i + 1] == '"':
                i += 2
                continue
            in_string = not in_string
        elif not in_string:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return source[start:i + 1]
        i += 1
    raise AssertionError(f"unterminated {name}")


def code_only(body: str) -> str:
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return re.sub(r"//[^\n]*", "", body)


def stay_low() -> str:
    return read(MISSION / "ITW_CLASH_HALStayLow.sqf")


def body_of(name: str) -> str:
    return code_only(function_body(stay_low(), f"ITW_CLASH_HALStayLow_fnc_{name}"))


def default(name: str) -> float:
    return float(re.search(rf'"{name}",([\d.]+)', stay_low()).group(1))


def sqf_schedule(metres: float) -> tuple[float, float]:
    """fnc_Schedule, in Python, from the defaults in the SQF file."""
    end = default("ITW_CLASH_HALStayLowFinalKmh") / KMH
    beyond = max(metres - default("ITW_CLASH_HALStayLowFinalDistance"), 0.0)
    kmh = KMH * (end ** 3 + 3 * default("ITW_CLASH_HALStayLowPower") * beyond) ** (1 / 3)
    height = min(
        default("ITW_CLASH_HALStayLowFinalHeight")
        + default("ITW_CLASH_HALStayLowHeightPerKmh")
        * max(kmh - default("ITW_CLASH_HALStayLowFinalKmh"), 0.0),
        default("ITW_CLASH_HALStayLowCruiseHeight"),
    )
    return kmh, height


# ------------------------------------------------- what the RPT measured

def test_every_leg_that_ends_at_a_waypoint_sits_on_the_arrival_law():
    """Hark: "we land on clear corridors, that causes our helos to raise in the
    air to slow themselves down."

    Five legs in the 2026-10-10 23:22 RPT end at a waypoint: two Huron pickups,
    one Huron delivery, two Littlebird hops. Once each is braking, speed over
    distance is the same number in all of them. The delivery has two braking
    samples and not more because the aircraft was lost twenty seconds later."""
    for name, leg in sim.LEGS.items():
        fastest = max(range(len(leg)), key=lambda i: leg[i][2])
        braking = [s for s in leg[fastest:] if s[1] < 650 and s[2] > 5]
        assert len(braking) >= 2, name
        for _, metres, speed, _ in braking:
            assert 0.062 <= speed / metres <= 0.080, (name, metres, speed)


def test_the_height_gained_is_the_speed_shed():
    """Braking is a nose-up flare and the energy goes somewhere. On both Huron
    pickups the climb is within a quarter of the kinetic energy lost."""
    # Last sample before the nose comes up, and the sample at the top.
    for name, fast, slow in (("A", 5, 7), ("B", 2, 5)):
        leg = sim.LEGS[name]
        shed = (leg[fast][2] ** 2 - leg[slow][2] ** 2) / (2 * G)
        gained = leg[slow][3] - leg[fast][3]
        assert gained > 150, (name, gained)
        assert 0.75 <= gained / shed <= 1.25, (name, gained, shed)


def test_the_model_reproduces_the_balloon_it_was_fitted_to():
    leg = sim.LEGS["A"]
    first = next(i for i, s in enumerate(leg) if s[1] < 1400)
    _, metres, speed, height = leg[first]
    result, _ = sim.fly(sim.none, sim.PILOTS["soft"], speed * KMH,
                        start_m=metres, start_v=speed, start_h=height)
    measured = max(s[3] for s in leg)
    assert measured == 291
    assert abs(result["peak"] - measured) / measured < 0.15, result["peak"]


def test_the_arrival_law_alone_balloons_above_a_speed_hal_always_exceeds():
    """Zoom is k v^2 / g and the pilot comes down at 8 to 10 m/s. They cross
    near 130 km/h. HAL's transports arrive at 210 to 260."""
    pilot = sim.PILOTS["middle"]
    crossover = (pilot.u_down * G / (pilot.k_arrive * pilot.eta)) ** 0.5 * KMH
    assert 100 < crossover < 150, crossover
    arrivals = [max(s[2] for s in sim.LEGS[name]) * KMH for name in "ABC"]
    assert min(arrivals) > 200, arrivals


# ------------------------------------------------ what the simulation says

def test_starting_at_the_decision_point_does_not_work():
    """The option first offered to Hark as the recommended one: ITW's last
    rungs, inside the 1.2 km run-in decision. A Huron has two thirds of its
    speed left to lose in the last kilometre, and still balloons."""
    for pilot in sim.PILOTS.values():
        bare = sim.exposure(sim.none, pilot, 250.0, 3000.0)["peak"]
        late = sim.exposure(sim.inside_1200, pilot, 250.0, 3000.0)["peak"]
        assert late > 0.9 * bare, (late, bare)


def test_the_chosen_schedule_cuts_the_peak_under_every_pilot():
    """The RPT does not say how hard the pilot corrects a small height error,
    so the choice has to hold for a soft pilot, a firm one, and between."""
    chosen = sim.constant_power(sim.CHOSEN_POWER)
    for kmh in sim.AIRFRAMES.values():
        for leg_m in sim.LEGS_M:
            for name, pilot in sim.PILOTS.items():
                bare = sim.exposure(sim.none, pilot, kmh, leg_m)["peak"]
                held = sim.exposure(chosen, pilot, kmh, leg_m)["peak"]
                assert bare > 100, (name, kmh, leg_m, bare)
                assert held <= 75, (name, kmh, leg_m, held)
                assert held < 0.6 * bare, (name, kmh, leg_m, held, bare)


def test_it_beats_itws_ladder_on_height_for_about_the_same_time():
    chosen = sim.constant_power(sim.CHOSEN_POWER)
    for kmh in sim.AIRFRAMES.values():
        for leg_m in sim.LEGS_M:
            soft = sim.PILOTS["soft"]
            ladder = sim.exposure(sim.itw_stairs, soft, kmh, leg_m)
            curve = sim.exposure(chosen, soft, kmh, leg_m)
            assert curve["peak"] < ladder["peak"], (kmh, leg_m)
            assert curve["time"] <= ladder["time"] + 8, (kmh, leg_m)


def test_the_cost_is_seconds():
    chosen = sim.constant_power(sim.CHOSEN_POWER)
    for kmh in sim.AIRFRAMES.values():
        for leg_m in sim.LEGS_M:
            bare = sim.exposure(sim.none, sim.PILOTS["middle"], kmh, leg_m)["time"]
            held = sim.exposure(chosen, sim.PILOTS["middle"], kmh, leg_m)["time"]
            assert held - bare <= 25, (kmh, leg_m, held - bare)
            assert held / bare <= 1.25, (kmh, leg_m)


def test_gentler_is_lower_and_slower_all_the_way_down():
    """The tradeoff has no knee to hide behind: every step of power is paid for
    in height under the soft pilot, and bought back in seconds."""
    peaks, times = [], []
    for power in (10, 15, 20, 25, 35, 50):
        r = sim.exposure(sim.constant_power(power), sim.PILOTS["soft"], 250.0, 4400.0)
        peaks.append(r["peak"])
        times.append(r["time"])
    assert peaks == sorted(peaks)
    assert times == sorted(times, reverse=True)


# --------------------------------------------- the schedule that was shipped

def test_the_sqf_schedule_is_the_one_that_was_simulated():
    assert default("ITW_CLASH_HALStayLowPower") == sim.CHOSEN_POWER
    assert default("ITW_CLASH_HALStayLowFinalKmh") == sim.END_KMH
    assert default("ITW_CLASH_HALStayLowFinalDistance") == sim.END_M
    assert default("ITW_CLASH_HALStayLowFinalHeight") == sim.LOW_M
    body = body_of("Schedule")
    assert "((_end ^ 3) + (3 * ITW_CLASH_HALStayLowPower * _beyond)) ^ (1 / 3)" in body
    assert "min ITW_CLASH_HALStayLowCruiseHeight" in body
    model = sim.constant_power(sim.CHOSEN_POWER)
    cruise = default("ITW_CLASH_HALStayLowCruiseHeight")
    for metres in (0, 150, 300, 500, 1000, 2000, 4400):
        kmh, height = sqf_schedule(metres)
        model_kmh, model_height = model(metres, cruise)
        assert abs(kmh - model_kmh) < 0.01, metres
        assert abs(height - model_height) < 0.01, metres


def test_the_last_rung_is_itws_and_joins_the_arrival_law():
    """80 km/h and 10 m inside 300 m, as ITW has it. 80 km/h at 300 m is the
    arrival law's own speed there, so the aircraft joins it without braking."""
    attack = read(MISSION / "ITW_Attack.sqf")
    assert "case (_distToAo < _heliSlowDist0): {_speed =  80;_height = 10};" in attack
    for metres in (0, 300):
        kmh, height = sqf_schedule(metres)
        assert abs(kmh - 80.0) < 1e-6 and abs(height - 10.0) < 1e-6, metres
    assert 0.062 <= (kmh / KMH) / 300 <= 0.080


def test_itws_seven_heights_are_one_line_in_its_own_speeds():
    attack = read(MISSION / "ITW_Attack.sqf")
    rungs = re.findall(
        r"case \(_distToAo < _heliSlowDist\d\): \{_speed = +(\d+);_height = (\d+)\};", attack
    )
    assert len(rungs) == 7, rungs
    slope = default("ITW_CLASH_HALStayLowHeightPerKmh")
    for kmh, height in rungs:
        assert abs(10 + slope * (int(kmh) - 80) - int(height)) <= 1.0, (kmh, height)


def test_the_schedule_never_asks_for_more_than_cruise_height():
    cruise = default("ITW_CLASH_HALStayLowCruiseHeight")
    assert cruise == 30
    heights = [sqf_schedule(m)[1] for m in range(0, 8000, 100)]
    assert max(heights) == cruise
    assert heights == sorted(heights)
    limits = [sqf_schedule(m)[0] for m in range(0, 8000, 100)]
    assert limits == sorted(limits)


# ------------------------------------------------------------- what it owns

def test_hal_sets_neither_input_on_a_troop_lift():
    """Which is what makes them free to set. HAL owns the route and every
    waypoint; it has no opinion on height or on a speed limit."""
    for name in ("SCargo", "GoAttInf", "GoRecon", "GoCapture", "GoRest",
                 "GoFlank", "GoSFAttack", "GoAttSniper"):
        source = read(HAL / f"{name}.sqf").lower()
        assert "flyinheight" not in source, name
        assert "limitspeed" not in source, name


def test_it_writes_height_and_speed_and_nothing_else():
    source = code_only(stay_low())
    for forbidden in (
        "addWaypoint", "deleteWaypoint", "setWaypointPosition", "setCurrentWaypoint",
        "setWaypointStatements", "RYD_WPadd", "RYD_WPdel", "doMove", "commandMove",
        "forceSpeed", "setBehaviour", "setCombatMode", "setSpeedMode", ' land "',
        "RydHQ_MIA", '"CargoM"', '"Busy"', "moveOut", "unassignVehicle",
    ):
        assert forbidden not in source, forbidden
    # Every group variable it sets is its own.
    for written in re.findall(r'setVariable \[\s*"([^"]+)"', source):
        assert written.startswith("ITW_CLASH_HALStayLow"), written


def test_carriers_are_read_off_scargos_own_bookkeeping():
    scargo = read(HAL / "SCargo.sqf")
    assert '_unitG setVariable ["CargoChosen",true' in scargo
    assert '_unitG setVariable ["AssignedCargo" + (str _unitG),_ChosenOne' in scargo
    body = body_of("Carriers")
    assert '_x getVariable ["CargoChosen",false]' in body
    assert '_x getVariable ["AssignedCargo" + str _x,objNull]' in body
    assert '_carrier isKindOf "Helicopter"' in body


def test_a_leg_is_what_hals_waypoint_statement_says_it_is():
    scargo = read(HAL / "SCargo.sqf")
    assert "land 'GET IN'} foreach (units (group this));deletewaypoint" in scargo
    assert "land 'LAND'} foreach (units (group this))}; deletewaypoint" in scargo
    assert "land 'GET OUT';deletewaypoint [(group this), 0]" in read(HAL / "GoAttInf.sqf")
    body = body_of("Leg")
    assert "waypointStatements _waypoint" in body
    for marker, kind in (
        ('"ITW_CLASH_HALUnload_fnc_Unload"', '"DELIVERY"'),
        ("\"land 'GET IN'\"", '"PICKUP"'),
        ("\"land 'LAND'\"", '"RETURN"'),
        ("\"land 'GET OUT'\"", '"LANDING"'),
    ):
        assert marker in body, marker
        assert kind in body, kind
    # The patched delivery still has GET OUT in its fallback, so it is tested first.
    assert body.index('"ITW_CLASH_HALUnload_fnc_Unload"') < body.index("\"land 'GET OUT'\"")
    tick = body_of("Tick")
    assert 'case "PICKUP";' in tick and 'case "RETURN";' in tick and 'case "LANDING": {true};' in tick


def test_a_lift_that_is_going_to_drop_is_not_slowed():
    """A paradrop flies through its waypoint and wants every km/h it has. The
    unload owner says which it is, with the function its run-in decides by."""
    body = body_of("Arrives")
    assert "call ITW_CLASH_HALUnload_fnc_Decide" in body
    # NO_LAND keeps the chalk aboard but still stops over the point.
    assert '_arrives = _mode in ["LAND","NO_LAND"];' in body
    assert '"PARADROP"' not in body
    unload = read(MISSION / "ITW_CLASH_HALUnload.sqf")
    assert "ITW_CLASH_HALUnload_fnc_Decide = {" in unload
    tick = body_of("Tick")
    assert 'case "DELIVERY": {' in tick
    assert "call ITW_CLASH_HALStayLow_fnc_Arrives" in tick


def test_with_no_unload_owner_every_delivery_is_a_landing():
    body = body_of("Arrives")
    guard = body[:body.index("exitWith {true}")]
    assert 'isNil "ITW_CLASH_HALUnload_fnc_Decide"' in guard
    assert "ITW_CLASH_HALUnloadReady" in guard


def test_the_answer_is_asked_again_because_the_corridor_is():
    body = body_of("Arrives")
    assert "ITW_CLASH_HALStayLowIntentSeconds" in body
    assert "time < (_cached select 1)" in body
    assert 0 < default("ITW_CLASH_HALStayLowIntentSeconds") <= 10


def test_a_drop_run_has_height_and_speed_to_itself():
    """From arming to egress the unload owner asks for 45 m and full speed.
    A second writer asking for 30 m would have the paradrop owner waiting on
    an altitude that never comes."""
    tick = body_of("Tick")
    hands_off = tick.index('_group getVariable ["ITW_CLASH_HALUnloadDropRunArmed",false]')
    assert '["RUN_IN","DROPPING"]' in tick
    for write in ("_carrier limitSpeed _limit;", "_carrier flyInHeight _ask;",
                  "_carrier flyInHeight ITW_CLASH_HALStayLowCruiseHeight;"):
        assert hands_off < tick.index(write), write
    unload = read(MISSION / "ITW_CLASH_HALUnload.sqf")
    for owner in ("ITW_CLASH_HALUnload_fnc_ArmRunIn", "ITW_CLASH_HALUnload_fnc_PrepareDropRun"):
        assert 'setVariable ["ITW_CLASH_HALUnloadDropRunArmed",true]' in function_body(unload, owner)


def test_it_stands_aside_for_anyone_else_flying_the_aircraft():
    tick = body_of("Tick")
    first_write = tick.index("_carrier limitSpeed _limit;")
    for owner in ("isPlayer _x", "ITW_CLASH_ThunderRunActive", "ITW_CLASH_HotDropActive"):
        assert tick.index(owner) < first_write, owner


def test_the_limit_moves_in_small_steps_every_pass():
    """A ladder steps, and a pilot that brakes hard for an overspeed flares for
    each rung. The limit here moves a few km/h between passes."""
    tick = body_of("Tick")
    assert "call ITW_CLASH_HALStayLow_fnc_Schedule" in tick
    assert "_carrier limitSpeed _limit;" in tick
    assert "_carrier flyInHeight _ask;" in tick
    poll = default("ITW_CLASH_HALStayLowPoll")
    assert poll <= 0.5
    # A Huron on the schedule at 2 km: how far the limit falls in one pass.
    kmh, _ = sqf_schedule(2000)
    step = kmh - sqf_schedule(2000 - (kmh / KMH) * poll)[0]
    assert 0 < step < 2.0, step


def test_a_speed_limit_never_outlives_its_approach():
    """A limit left on is an 80 km/h helicopter for the rest of the mission,
    and a height left at 10 m is the next system's problem."""
    release = body_of("Release")
    assert "_carrier limitSpeed 1e10;" in release
    assert "_carrier flyInHeight ITW_CLASH_HALStayLowCruiseHeight;" in release
    assert 'setVariable ["ITW_CLASH_HALStayLowApproach",nil]' in release
    tick = body_of("Tick")
    # Lost, crewless, taken by another owner, and the ordinary end of a leg.
    assert tick.count("call ITW_CLASH_HALStayLow_fnc_Release") == 4
    for why in ('"lost"', '"no-crew"', '"other-owner"', '"leg-ended"'):
        assert why in tick, why
    source = code_only(stay_low())
    off = source[source.index("if (!ITW_CLASH_HALStayLow) then {"):]
    assert '"switched-off"] call ITW_CLASH_HALStayLow_fnc_Release} forEach _tracked;' in off[:400]


def test_every_approach_leaves_the_measurement_that_tunes_the_schedule():
    """The one number the RPT could not give is how the pilot answers a gentle
    schedule. Peak height per approach, next to the power it was flown at, is
    that number."""
    release = body_of("Release")
    assert '["approach",[' in release
    for field in ("round _from", "round _to", "round _peak", "round _fastest",
                  "ITW_CLASH_HALStayLowPower"):
        assert field in release, field
    tick = body_of("Tick")
    assert "_approach set [3,(_approach select 3) max _height];" in tick
    assert "_approach set [4,(_approach select 4) max _kmh];" in tick


def test_stay_low_can_be_switched_off():
    source = stay_low()
    assert '"ITW_CLASH_HALStayLow",true' in source
    assert "if (!ITW_CLASH_HALStayLow) then {" in source


def test_it_waits_for_hal_and_is_loaded_after_the_unload_owner():
    source = stay_low()
    assert 'missionNamespace getVariable ["ITW_CLASH_HALReady",false]' in source
    init = read(MISSION / "init.sqf")
    assert '[] execVM "ITW_CLASH_HALStayLow.sqf";' in init
    assert init.index('"ITW_CLASH_HALUnload.sqf"') < init.index('"ITW_CLASH_HALStayLow.sqf"')


def test_the_boot_line_carries_the_numbers_it_flies():
    line = next(x for x in stay_low().splitlines() if "hal-stay-low-ready" in x)
    for field in ("version=%1", "enabled=%2", "cruise=%3", "power=%4", "at1000=%8kmh/%9m"):
        assert field in line, field
    assert "ITW_CLASH_HALStayLowVersion = 1;" in stay_low()


def test_an_aircraft_off_scargos_books_is_watched_but_not_written_to():
    """SCargo clears CargoChosen and AssignedCargo, then writes the flight
    home. Between the two the aircraft is nobody's carrier and has no
    waypoint. Dropping it there would lose the return leg; holding a height on
    it for good would be flying somebody else's aircraft."""
    scargo = read(HAL / "SCargo.sqf")
    tail = scargo[scargo.rindex('_unitG setVariable ["CargoChosen",false,true];'):]
    assert tail.index('"AssignedCargo" + (str _unitG),objNull') < tail.index("land 'LAND'")

    tick = body_of("Tick")
    off_books = tick.index("if (!_isCarrier) exitWith {")
    assert "ITW_CLASH_HALStayLowLinger" in tick[off_books:off_books + 200]
    # Cruise height is only ever asked of a chosen carrier.
    assert off_books < tick.index("_carrier flyInHeight ITW_CLASH_HALStayLowCruiseHeight;")
    assert '_kind in ["PICKUP","RETURN"]' in tick
    assert 0 < default("ITW_CLASH_HALStayLowLinger") <= 30


def test_an_empty_cabin_is_not_an_arrival():
    """After a run-in drop the aircraft is still on HAL's delivery waypoint,
    which the unload owner moved a kilometre past the drop zone. Read as a
    delivery it would be slowed to 135 km/h on its way out. The unload owner
    answers with an empty mode when nobody is aboard, and only LAND and
    NO_LAND are arrivals."""
    unload = read(MISSION / "ITW_CLASH_HALUnload.sqf")
    decide = code_only(function_body(unload, "ITW_CLASH_HALUnload_fnc_Decide"))
    assert '["","COLD","no-cargo",0,0,[],grpNull]' in decide
    arm = code_only(function_body(unload, "ITW_CLASH_HALUnload_fnc_ArmRunIn"))
    assert "_wp setWaypointPosition [_through,0];" in arm
    assert "setWaypointStatements" not in arm, "the moved waypoint still reads as a delivery"
    body = body_of("Arrives")
    assert 'param [0,""]' in body
    assert '"" in' not in body
