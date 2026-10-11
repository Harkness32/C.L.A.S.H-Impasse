import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal"
ADD = ROOT / "CLASH HAL Additions" / "addons" / "clash_hal_additions"

ANCHOR = (
    'if (((group (assigneddriver _AV)) in (_HQ getVariable ["RydHQ_AirG",[]])) '
    'and (_unitG in (_HQ getVariable ["RydHQ_NCrewInfG",[]]))) then '
    '{_sts = ["true","(vehicle this) land \'GET OUT\';deletewaypoint [(group this), 0]"]};'
)

SITES = {
    "GoAttInf": ADD / "hal" / "GoAttInf.sqf",
    "GoRecon": ADD / "hal" / "GoRecon.sqf",
    "GoCapture": ADD / "hal" / "GoCapture.sqf",
    "GoRest": ADD / "hal" / "GoRest.sqf",
    "GoAttSniper": NR6 / "HAL" / "GoAttSniper.sqf",
    "GoFlank": NR6 / "HAL" / "GoFlank.sqf",
    "GoSFAttack": NR6 / "HAL" / "GoSFAttack.sqf",
}


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
    """Comments in this module quote Hark and name the very identifiers under
    test, so every assertion has to see executable text only."""
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return re.sub(r"//[^\n]*", "", body)


def central() -> str:
    return read(MISSION / "ITW_CLASH_HALUnload.sqf")


def test_all_seven_real_order_sites_have_one_stock_anchor():
    assert len(SITES) == 7
    for name, path in SITES.items():
        assert read(path).count(ANCHOR) == 1, (name, path)


def test_hand_edited_unload_logic_is_gone_from_addon_orders():
    for name in ("GoAttInf", "GoRecon"):
        source = read(SITES[name])
        assert "_clashPara" not in source, name
        assert "air-unload-waypoint" not in source, name
        assert "recon-air-unload-waypoint" not in source, name
        assert "ITW_CLASH_HALParadrop_fnc_ShouldUse" not in source, name


def test_addon_override_records_the_source_each_global_was_compiled_from():
    source = read(ADD / "functions" / "fnc_overrides.sqf")
    assert "CLASH_HALAdd_SourcePaths = createHashMap;" in source
    assert "CLASH_HALAdd_SourcePaths set [_global,_sourcePath];" in source
    assert 'private _sourcePath = "\\clash_hal_additions\\hal\\" + _file;' in source


def test_central_owner_names_exactly_the_seven_sites():
    source = central()
    specs = re.findall(r'\["(HAL_\w+)","(Go\w+\.sqf)","(Go\w+)"\]', source)
    assert len(specs) == 7, specs
    assert {label for _, _, label in specs} == set(SITES)


def test_source_patch_is_all_or_nothing():
    source = central()
    loop = source.index("} forEach ITW_CLASH_HALUnloadOrderSpecs;")
    failure = source.index('if (_failure isNotEqualTo "") exitWith {', loop)
    install = source.index("missionNamespace setVariable [_global,_compiled get _global];", failure)
    assert loop < failure < install
    assert "signature-missing" in source
    assert "signature-duplicate" in source
    assert "compile-failed" in source
    assert "stock HAL unload retained" in source


def test_order_hook_always_deletes_the_completed_waypoint():
    source = central()
    patch = function_body(source, "ITW_CLASH_HALUnload_fnc_PatchSource")
    assert "spawn ITW_CLASH_HALUnload_fnc_Unload" in patch
    assert "deletewaypoint [(group this), 0]" in patch
    # If the mission-side owner is missing, the addon/runtime patch degrades to
    # stock HAL landing rather than throwing inside the waypoint statement.
    assert 'isNil ""ITW_CLASH_HALUnload_fnc_Unload""' in patch
    assert 'land ""GET OUT""' in patch


def test_unload_decision_is_execution_time_and_has_no_route_actuator():
    source = central()
    body = function_body(source, "ITW_CLASH_HALUnload_fnc_Unload")
    assert "ITW_ParamHelisUnload" in body
    assert "ITW_CLASH_HALUnload_fnc_Corridor" in body
    assert "ITW_CLASH_HALUnload_fnc_Mode" in body
    for forbidden in (
        "doMove", "commandMove", "RYD_WPadd", "addWaypoint",
        "setWaypointPosition", "setCurrentWaypoint", "RYD_WPdel",
    ):
        assert forbidden not in body, forbidden


def test_mode_table_keeps_host_setting_and_corridor_doctrine_separate():
    body = function_body(central(), "ITW_CLASH_HALUnload_fnc_Mode")
    assert '_state in ["HOT","AIR_DENIED","UNKNOWN"]' in body
    assert 'if (_param == 0) exitWith {' in body
    assert 'if (_noLand) then {"NO_LAND"} else {"LAND"}' in body
    assert '_state in ["HOT","AIR_DENIED"]' in body
    assert '["HOT_PARADROP",100,_capacity]' in body
    assert '_state in ["CONTESTED","UNKNOWN"]' in body
    assert '["PARADROP",100,_capacity]' in body
    assert "ITW_CLASH_HALParadrop_fnc_ShouldUse" in body


def test_unsafe_paradrop_never_falls_back_to_a_forward_landing():
    source = central()
    body = function_body(source, "ITW_CLASH_HALUnload_fnc_Unload")
    assert 'private _noLand = _state in ["HOT","AIR_DENIED","UNKNOWN"];' in body
    assert '[_carrierGroup,_carrier,!_noLand] call' in body
    assert '[_carrierGroup,_carrier,false] call' in body
    assert 'case "NO_LAND"' in body
    # A refused unsafe drop releases any sticky landing state but keeps HAL as
    # flight owner; it does not invent a doMove or RTB.
    assert '_carrier land "NONE";' in body
    assert '"NO_LAND"' in body


def test_hot_profile_borrows_flares_but_not_flight_control():
    body = function_body(central(), "ITW_CLASH_HALUnload_fnc_StartHotFlares")
    assert "ITW_CLASH_HotDrop_fnc_Flare" in body
    assert "ITW_CLASH_ThunderRun_fnc_InitFlareBudget" in body
    for forbidden in ("doMove", "commandMove", "RYD_WPdel", "setWaypointPosition"):
        assert forbidden not in body, forbidden


def test_one_greppable_line_contains_the_entire_unload_result():
    source = central()
    line = next(x for x in source.splitlines() if "CLASH HAL UNLOAD | lift |" in x)
    for field in (
        "group=%1", "aircraft=%2", "order=%3", "param=%4", "corridor=%5",
        "mode=%6", "result=%7", "reason=%8", "chance=%9", "capacity=%10",
    ):
        assert field in line, field


def test_central_owner_is_loaded_after_paradrop_helper():
    init = read(MISSION / "init.sqf")
    assert '[] execVM "ITW_CLASH_HALUnload.sqf";' in init
    assert init.index('"ITW_CLASH_HALParadrop.sqf"') < init.index('"ITW_CLASH_HALUnload.sqf"')


def test_sof_repair_publishes_source_instead_of_owning_air_unload():
    source = read(MISSION / "ITW_CLASH_HALNativeSFFix.sqf")
    assert "ITW_CLASH_HALNativeSF_fnc_ParadropStatement" not in source
    assert "ITW_CLASH_HALNativeSF_Source = _attackSource;" in source
    assert "ITW_CLASH_HALUnload_fnc_PatchSource" in source


# --------------------------------------- the arity contract between the two owners

def test_execute_declares_every_argument_the_unload_owner_passes():
    """The defect that made this a silent failure.

    fnc_Execute's fallback branch was given an _allowLandFallback test without
    the parameter being declared, so it read an undefined local: a type error
    that aborted the exitWith block and the spawned thread running it. Nothing
    landed, nothing was released, the cargo-group stamp stayed on the carrier,
    and the one-line-per-lift trace below never printed. The symptom was
    silence, which is the worst shape a helicopter bug can take.
    """
    policy = read(MISSION / "ITW_CLASH_HALParadrop.sqf")
    body = function_body(policy, "ITW_CLASH_HALParadrop_fnc_Execute")
    params = re.search(r"params \[(.*?)\];", body, re.S).group(1)
    assert '"_carrierGroup"' in params
    assert '"_carrier"' in params
    assert '["_allowLandFallback",true]' in params
    # Every local the branch reads has to be in that one params line.
    assert "_allowLandFallback" in params


def test_the_two_argument_caller_keeps_the_old_behaviour():
    """HotDrop.sqf:445 passes two arguments. The default has to be true, or
    fixing the declaration would silently forbid its landing fallback."""
    policy = read(MISSION / "ITW_CLASH_HALParadrop.sqf")
    body = function_body(policy, "ITW_CLASH_HALParadrop_fnc_Execute")
    assert '["_allowLandFallback",true]' in body
    hotdrop = read(MISSION / "ITW_CLASH_HotDrop.sqf")
    assert "[_crewGroup,_veh] call ITW_CLASH_HALParadrop_fnc_Execute" in hotdrop


def test_the_unload_owner_passes_the_no_land_decision_through():
    """UNKNOWN corridors parachute and never land - Hark's rule after the
    Littlebird losses - so PARADROP forwards !_noLand and HOT_PARADROP, which
    only runs in HOT or AIR_DENIED, forwards a hard false."""
    body = function_body(central(), "ITW_CLASH_HALUnload_fnc_Unload")
    assert "[_carrierGroup,_carrier,!_noLand] call" in body
    assert "[_carrierGroup,_carrier,false] call" in body


def test_the_refusal_branch_leaves_the_airframe_flying():
    policy = read(MISSION / "ITW_CLASH_HALParadrop.sqf")
    body = function_body(policy, "ITW_CLASH_HALParadrop_fnc_Execute")
    refusal = body[body.index("if (!_allowLandFallback) then {"):]
    refusal = refusal[:refusal.index("} else {")]
    assert '_carrier land "NONE";' in refusal
    assert "fallback-refused" in refusal
    assert '_carrier land "GET OUT"' not in refusal


# ----------------------------------------------- the drop run: smooth, then gone

def test_the_climb_happens_en_route_not_over_the_objective():
    """Hark: "it flew there, leveled out, raised then, then paradroped".

    The level-and-raise was flyInHeight being set AT the insertion waypoint,
    so the aircraft arrived at HAL's transit height and climbed on top of the
    objective while Execute's waitUntil held it there."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_TrackLift"))
    assert "ITW_CLASH_HALUnloadClimbEnRoute" in body
    assert "flyInHeight" in body
    assert "ITW_CLASH_HALParadrop_MinAltitude" in body


def test_the_climb_waits_for_the_chalk_to_be_aboard_first():
    """Asking for altitude before anyone has boarded would climb away from the
    squad still walking to the aircraft."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_TrackLift"))
    assert body.index("ITW_CLASH_HALUnloadOrigin") < body.index("ITW_CLASH_HALUnloadClimbEnRoute")


def test_execute_still_guards_the_altitude_itself():
    """The en-route climb is an optimisation, not a replacement. If it is
    switched off, or the aircraft cannot climb, Execute's own wait still
    decides whether a drop is safe."""
    body = code_only(function_body(
        read(MISSION / "ITW_CLASH_HALParadrop.sqf"), "ITW_CLASH_HALParadrop_fnc_Execute"
    ))
    assert "ITW_CLASH_HALParadrop_ClimbTimeout" in body
    assert "ITW_CLASH_HALParadrop_MinAltitude" in body


def test_both_drop_modes_arm_a_through_waypoint_before_execute():
    """A paradrop is a fly-through, not an arrival procedure.

    The aircraft must have a forward destination before the first parachute
    opens. Otherwise Execute runs while HAL's insertion waypoint is already
    gone and the helicopter can decelerate or hover over the objective.
    """
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Unload"))
    assert body.count("call\n                    ITW_CLASH_HALUnload_fnc_PrepareDropRun") == 2

    para = body[body.index('case "PARADROP"'):body.index('case "HOT_PARADROP"')]
    hot = body[body.index('case "HOT_PARADROP"'):body.index('case "NO_LAND"')]
    assert para.index("ITW_CLASH_HALUnload_fnc_PrepareDropRun") < para.index(
        "ITW_CLASH_HALParadrop_fnc_Execute"
    )
    assert hot.index("ITW_CLASH_HALUnload_fnc_PrepareDropRun") < hot.index(
        "ITW_CLASH_HALParadrop_fnc_Execute"
    )


def test_prepare_drop_run_is_straight_through_at_full_speed():
    body = code_only(function_body(
        central(), "ITW_CLASH_HALUnload_fnc_PrepareDropRun"
    ))
    assert "ITW_CLASH_HALUnloadFlyThrough" in body
    assert "ITW_CLASH_HALUnloadEgressThrough" in body
    assert "ITW_CLASH_HALUnloadEgressOffset" not in body, (
        "the lateral break belongs after the chalk is clear"
    )
    assert "_through = _here getPos" in body
    assert "addWaypoint [_through,0]" in body
    assert 'setWaypointSpeed "FULL"' in body
    assert 'setSpeedMode "FULL"' in body
    assert '_carrier land "NONE"' in body
    assert "_carrier limitSpeed 1e10" in body
    assert "_carrier forceSpeed -1" in body


def test_drop_run_records_geometry_and_hotzone_dwell_telemetry():
    source = central()
    prepare = code_only(function_body(
        source, "ITW_CLASH_HALUnload_fnc_PrepareDropRun"
    ))
    egress = code_only(function_body(source, "ITW_CLASH_HALUnload_fnc_Egress"))
    for token in (
        "ITW_CLASH_HALUnloadDropRunArmed",
        "ITW_CLASH_HALUnloadDropBearing",
        "ITW_CLASH_HALUnloadDropThrough",
        "ITW_CLASH_HALUnloadDropPoint",
        "ITW_CLASH_HALUnloadDropStarted",
    ):
        assert token in prepare
        assert token in egress
    assert '"drop-run-armed"' in prepare
    assert "round speed _carrier" in prepare
    assert "time - _started" in egress
    assert "round speed _carrier" in egress


def test_egress_appends_the_break_after_the_prearmed_through_leg():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Egress"))
    assert "ITW_CLASH_HALUnloadDropRunArmed" in body
    assert "ITW_CLASH_HALUnloadDropThrough" in body
    assert "_break = _through getPos" in body
    assert "ITW_CLASH_HALUnloadEgressOffset" in body
    assert "forEach [[_break,150],[_home,200]]" in body

    # The normal path preserves the already-active through waypoint. Only a
    # legacy/failed preparation path clears and manufactures one here.
    assert "if (!_prepared) then {" in body
    assert "addWaypoint [_through,0]" in body


def test_safe_land_fallback_cancels_the_flythrough_first():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Unload"))
    assert body.count("ITW_CLASH_HALUnload_fnc_CancelDropRun") == 1
    at = body.index('"land-fallback"')
    window = body[at - 250:at + 350]
    assert "ITW_CLASH_HALUnload_fnc_CancelDropRun" in window
    assert window.index("ITW_CLASH_HALUnload_fnc_CancelDropRun") < window.index(
        '_carrier land "GET OUT"'
    )


def test_cancelling_a_drop_run_removes_only_its_continuation_state():
    body = code_only(function_body(
        central(), "ITW_CLASH_HALUnload_fnc_CancelDropRun"
    ))
    assert "ITW_CLASH_fnc_ClearGroupWaypoints" in body
    assert '"drop-run-cancelled"' in body
    for token in (
        "ITW_CLASH_HALUnloadDropRunArmed",
        "ITW_CLASH_HALUnloadDropBearing",
        "ITW_CLASH_HALUnloadDropThrough",
        "ITW_CLASH_HALUnloadDropPoint",
        "ITW_CLASH_HALUnloadDropStarted",
    ):
        assert token in body


def test_the_egress_uses_waypoints_not_domove():
    """The rule that run8 broke was taking an aircraft HAL was actively flying.
    Here HAL has finished and left it with nothing - but it still has to be
    handed back cleanly, so HAL's next dispatch replaces these through its own
    machinery."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Egress"))
    assert "doMove" not in body
    assert "addWaypoint" in body


def test_the_egress_releases_every_hold_on_the_airframe():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Egress"))
    assert '_carrier land "NONE"' in body
    assert "ITW_CLASH_HALUnloadTransitHeight" in body
    assert "forceSpeed -1" in body


def test_the_egress_never_touches_a_player_or_a_dead_airframe():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Egress"))
    assert "isPlayer _x" in body
    assert "alive _carrier" in body
    assert "canMove _carrier" in body


def test_the_egress_survives_a_missing_origin():
    """A lift whose origin was never stamped still has to leave."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Egress"))
    assert "getDir _carrier" in body, "fall back to the way it is pointing"
    assert "_home = if (" in body


def test_paired_aircraft_bank_opposite_ways():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Egress"))
    assert "BIS_fnc_netId" in body
    assert "90" in body and "-90" in body


def test_the_egress_can_be_switched_off_without_touching_the_drop():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Egress"))
    assert "if (!ITW_CLASH_HALUnloadEgress) exitWith {false}" in body


def test_the_climb_waits_for_the_last_third_of_the_run():
    """v1 climbed as soon as the chalk was aboard, which flew the WHOLE route
    at drop altitude - more exposure for longer on every lift, into a loss
    closure that punishes air losses collectively. Hark liked the fix and
    asked for it."""
    source = central()
    assert "ITW_CLASH_HALUnloadClimbFraction" in source
    body = code_only(function_body(source, "ITW_CLASH_HALUnload_fnc_TrackLift"))
    assert "ITW_CLASH_HotDrop_fnc_Destination" in body
    assert "_total * ITW_CLASH_HALUnloadClimbFraction" in body


def test_an_unreadable_destination_climbs_immediately():
    """Fail-open to v1 rather than never climbing, which would bring the hover
    back."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_TrackLift"))
    assert "if (_destination isEqualTo []) exitWith {" in body


def test_the_climb_stops_caring_once_the_chalk_is_gone():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_TrackLift"))
    assert "vehicle _x == _carrier" in body
    assert "!alive _carrier" in body


def test_the_drop_floor_is_forty_five():
    """Hark: "we can also loosen the 55m thing, 45 and above is mint." Less
    climbing is less exposure."""
    paradrop = read(MISSION / "ITW_CLASH_HALParadrop.sqf")
    assert '"ITW_CLASH_HALParadrop_MinAltitude",45' in paradrop
    # And still clear of the fallback altitude, or every drop would be refused.
    fallback = int(
        re.search(r'"ITW_CLASH_HALParadrop_FallbackAltitude",(\d+)', paradrop).group(1)
    )
    assert fallback < 45, fallback


# ------------------------------------------------- more than one squad aboard

def test_every_group_aboard_is_found_not_just_the_first():
    """Hark: "alpha 2-5 has two different groups in his helo, hes just sitting
    there forever." fnc_CargoGroup returns ONE group - the stamped one or the
    first passenger's - and the unload acted on that alone, so the second squad
    rode home in a carrier that had already finished its job."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_CargoGroups"))
    assert "pushBackUnique _group" in body
    assert "forEach (crew _carrier)" in body


def test_the_crew_and_turret_gunners_are_not_cargo():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_CargoGroups"))
    assert "_group isEqualTo _carrierGroup" in body
    assert '_role in ["Driver","Turret"]' in body


def test_a_still_boarding_stamped_group_is_not_lost():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_CargoGroups"))
    assert "ITW_CLASH_HALUnloadCargoGroup" in body
    assert "!(_stamped in _groups)" in body


def test_both_drop_modes_unload_every_group():
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Unload"))
    assert body.count("forEach _cargoGroups") == 2, "PARADROP and HOT_PARADROP"
    assert body.count('setVariable ["ITW_CLASH_HALParadropCargoGroup",_x]') == 2


def test_the_paradrop_owners_contract_is_unchanged():
    """The stamp is moved between passes rather than teaching Execute about
    lists, so a multi-group lift is simply several single-group drops."""
    paradrop = code_only(function_body(
        read(MISSION / "ITW_CLASH_HALParadrop.sqf"), "ITW_CLASH_HALParadrop_fnc_Execute"
    ))
    assert 'getVariable [\n        "ITW_CLASH_HALParadropCargoGroup",grpNull\n    ]' in paradrop


def test_a_multi_group_lift_is_announced():
    """Nothing in the RPT said there were two, which is why the first evidence
    was Hark watching an aircraft do nothing."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Unload"))
    assert "multi-group-lift" in body
    assert "count _cargoGroups > 1" in body


def test_flythrough_defaults_are_long_enough_to_clear_the_drop_zone():
    source = central()
    assert '"ITW_CLASH_HALUnloadEgressThrough",1000' in source
    assert '"ITW_CLASH_HALUnloadEgressOffset",600' in source


def test_hal_unload_version_moved_to_five_for_the_run_in():
    assert "ITW_CLASH_HALUnloadVersion = 5;" in central()


def test_native_itw_paradrop_preserves_the_prearmed_through_waypoint():
    """ITW_AllyParadropCargo deliberately calls the native airplane unload with
    grpNull, so ITW_AtkUnloadAirplane ejects the chalk but does not delete or
    replace the helicopter crew group's waypoint. The fly-through would be
    defeated if that contract changed.
    """
    ally = read(MISSION / "ITW_Ally.sqf")
    helper = code_only(function_body(ally, "ITW_AllyParadropCargo"))
    assert '[_veh,grpNull,[_grp],[]] call ITW_AtkUnloadAirplane;' in helper

    attack = read(MISSION / "ITW_Attack.sqf")
    native = code_only(function_body(attack, "ITW_AtkUnloadAirplane"))
    assert 'if !(_crewGroup isEqualTo grpNull) then {' in native
    guarded = native[native.index('if !(_crewGroup isEqualTo grpNull) then {'):]
    assert "ITW_DELETE_WAYPOINTS(_crewGroup)" in guarded[:1200]


# ------------------------------------------------ the run-in: ITW's way, on HAL's lift

HAL = NR6 / "HAL"
# The four order files the addon forks are compiled from the addon when it is
# loaded and from NR6 when it is not, so both copies have to hold the shape.
RELEASE_AT_DROP = {
    "GoAttInf": [HAL / "GoAttInf.sqf", ADD / "hal" / "GoAttInf.sqf"],
    "GoRecon": [HAL / "GoRecon.sqf", ADD / "hal" / "GoRecon.sqf"],
    "GoCapture": [HAL / "GoCapture.sqf", ADD / "hal" / "GoCapture.sqf"],
    "GoRest": [HAL / "GoRest.sqf", ADD / "hal" / "GoRest.sqf"],
}
RELEASE_AT_BREAK = {
    "GoFlank": [HAL / "GoFlank.sqf"],
    "GoSFAttack": [HAL / "GoSFAttack.sqf"],
}
CARGO_CLEAR = '_GDV setVariable [("CargoM" + (str _GDV)), false];'


def body_of(name: str) -> str:
    return code_only(function_body(central(), f"ITW_CLASH_HALUnload_fnc_{name}"))


def after_the_carrier_wait(path: Path) -> str:
    """From the carrier wait that follows the unload seam to the line where
    the order file looks the carrier up again."""
    source = read(path)
    seam = source.index("land 'GET OUT'")
    wait = source.index("call RYD_Wait", seam)
    return source[wait:source.index("_AV = assignedVehicle _UL;", wait)]


def test_native_itw_never_puts_a_waypoint_on_the_drop():
    """Hark: "waitpoint behavior for the paradrops are all wrong, we need to
    mimic how ITW does it. currently, we set the waypoint on the ground, helo
    paths to transport place, slows, lowers, gets there, then raises, then
    paradrops, then leaves. its stupid clunky."

    What ITW does, pinned so the thing being copied cannot drift unnoticed:
    the destination goes 1500 m beyond, the drop is a distance check, and the
    aircraft is never arriving anywhere."""
    native = code_only(function_body(read(MISSION / "ITW_Attack.sqf"), "ITW_AtkUnloadAirplane"))
    assert "_vPos getPos [1500," in native
    assert "_veh distance2D _objPt < _unloadDist" in native
    assert native.index("_vPos getPos [1500,") < native.index("call ITW_AtkParachute")


def test_arming_moves_hals_own_waypoint_and_makes_none():
    """HAL's carrier wait counts waypoints and its statement is the unload
    seam. Moving the waypoint HAL wrote keeps both alive; replacing it would
    have ended the wait and thrown the seam away."""
    body = body_of("ArmRunIn")
    assert "call ITW_CLASH_HALUnload_fnc_HALWaypoint" in body
    assert "_through = _dropZone getPos [" in body
    assert "ITW_CLASH_HALUnloadEgressThrough" in body
    assert "_wp setWaypointPosition [_through,0];" in body
    for forbidden in (
        "addWaypoint", "deleteWaypoint", "RYD_WPadd", "RYD_WPdel",
        "ITW_CLASH_fnc_ClearGroupWaypoints", "setWaypointStatements", "doMove",
    ):
        assert forbidden not in body, forbidden


def test_the_waypoint_move_is_the_last_thing_arming_does():
    """Everything before it is height, speed and bookkeeping. A fault part way
    through leaves the waypoint where HAL put it, which is a v4 lift."""
    body = body_of("ArmRunIn")
    move = body.index("_wp setWaypointPosition [_through,0];")
    for earlier in (
        "_carrier flyInHeight _height;",
        '_carrierGroup setSpeedMode "FULL";',
        'setVariable ["ITW_CLASH_HALUnloadDropRunArmed",true]',
        'setVariable ["ITW_CLASH_HALUnloadDropZone",_dropZone]',
        '"run-in-armed"',
    ):
        assert body.index(earlier) < move, earlier
    after = body[move:]
    assert "setVariable" not in after
    assert "flyInHeight" not in after
    assert "call " not in after


def test_the_run_in_is_fast_and_at_drop_height():
    """Hark chose it: hold cruise speed, settle at drop height about a
    kilometre out, drop on the move."""
    body = body_of("ArmRunIn")
    assert '"ITW_CLASH_HALParadrop_MinAltitude",45' in body
    assert '"ITW_CLASH_HotDropDropHeight",130' in body
    assert '_mode isEqualTo "HOT_PARADROP"' in body
    assert "_carrier limitSpeed 1e10;" in body
    assert "_carrier forceSpeed -1;" in body
    assert '_carrier land "NONE";' in body
    source = central()
    assert '"ITW_CLASH_HALUnloadRunInDistance",1200' in source


def test_arming_hands_egress_the_names_it_already_reads():
    """Hark kept the lateral break. fnc_Egress appends it to a prepared run by
    reading these, so a run armed a kilometre out gets the same J-hook as one
    armed at the seam, from unchanged code."""
    arm = body_of("ArmRunIn")
    egress = body_of("Egress")
    for token in (
        "ITW_CLASH_HALUnloadDropRunArmed",
        "ITW_CLASH_HALUnloadDropBearing",
        "ITW_CLASH_HALUnloadDropThrough",
        "ITW_CLASH_HALUnloadDropPoint",
        "ITW_CLASH_HALUnloadDropStarted",
    ):
        assert token in arm, token
        assert token in egress, token
    run = body_of("RunIn")
    assert run.index("ITW_CLASH_HALParadrop_fnc_Execute") < run.index(
        "call ITW_CLASH_HALUnload_fnc_Egress"
    )


def test_hals_waypoint_is_found_by_its_statement_not_its_index():
    """HAL deletes waypoint 0 from inside its own statements, so every stored
    index is wrong one completion later."""
    body = body_of("HALWaypoint")
    assert "waypointStatements _x" in body
    assert '"ITW_CLASH_HALUnload_fnc_Unload"' in body
    patch = function_body(central(), "ITW_CLASH_HALUnload_fnc_PatchSource")
    assert "spawn ITW_CLASH_HALUnload_fnc_Unload" in patch


def test_the_run_in_decides_with_the_seams_owner_and_table():
    body = body_of("RunIn")
    assert "call ITW_CLASH_HALUnload_fnc_Commander" in body
    assert "[_hq,_carrierGroup,_carrier,_dropZone] call ITW_CLASH_HALUnload_fnc_Corridor" in body
    assert "[_carrier,_state,_carrierGroup] call ITW_CLASH_HALUnload_fnc_Mode" in body
    assert '"|player-touch"' in body
    # The corridor is the one to the drop zone, not to wherever the aircraft
    # happens to be a kilometre short of it.
    corridor = body_of("Corridor")
    assert '["_destination",[]]' in corridor
    assert "_destination = getPosATL _carrier;" in corridor


def test_a_lift_that_is_going_to_land_is_not_touched():
    """LAND and NO_LAND are HAL's lift to HAL's waypoint. Nothing below the
    decision may run for them, and nothing above it may act on the aircraft."""
    body = body_of("RunIn")
    leave = body.index('if !(_mode in ["PARADROP","HOT_PARADROP"]) exitWith {};')
    assert leave < body.index("call ITW_CLASH_HALUnload_fnc_ArmRunIn")
    before = body[:leave]
    for actuator in (
        "flyInHeight", "setWaypointPosition", "setWaypointCompletionRadius",
        "addWaypoint", "deleteWaypoint", "setSpeedMode", "setBehaviourStrong",
        "limitSpeed", "forceSpeed", " land ", "doMove", "RydHQ_MIA", "CargoM",
        "ITW_CLASH_HALUnload_fnc_Claim",
    ):
        assert actuator not in before, actuator


def test_the_run_in_does_not_arm_on_the_pad():
    """A short lift is inside the run-in distance before it has taken off, and
    an armed run has a clock on it."""
    body = body_of("RunIn")
    arm = body.index("call ITW_CLASH_HALUnload_fnc_ArmRunIn")
    transit = body[:arm]
    assert "ITW_CLASH_HALUnloadRunInMinHeight" in transit
    assert "ITW_CLASH_HALUnloadRunInDistance" in transit


def test_the_release_is_measured_along_the_approach_line():
    """A radius misses an aircraft that passes wide and never ends for one that
    turns away. Distance to run along the line reaches zero abeam either way."""
    body = body_of("RunIn")
    assert "_along = _range * cos _angle;" in body
    assert "_cross = abs (_range * sin _angle);" in body
    assert "_along <= _lead" in body
    assert "call ITW_CLASH_HALUnload_fnc_StickLead" in body
    assert "_cross > ITW_CLASH_HALUnloadMaxOffset" in body


def test_the_stick_lead_uses_itws_own_jumper_spacing():
    native = read(MISSION / "ITW_Attack.sqf")
    assert "private _sleep = 0.1 max (40/_speed) min 0.5;" in native
    assert "_veh modeltoWorld [7, -30, -20]" in native
    body = body_of("StickLead")
    assert "(0.1 max (40 / _kph)) min 0.5" in body
    assert "- 30" in body
    assert "ITW_CLASH_HALUnloadReleaseBias" in body


def test_a_fly_by_never_lands_and_never_waits_over_the_point():
    """At the seam the paradrop owner may wait 45 s for altitude, because the
    aircraft is standing there. On a run-in that is two kilometres further in."""
    body = body_of("RunIn")
    assert "[_carrierGroup,_carrier,false,ITW_CLASH_HALUnloadReleaseWait] call" in body
    assert '"ITW_CLASH_HALUnloadReleaseWait",1' in central()
    policy = read(MISSION / "ITW_CLASH_HALParadrop.sqf")
    execute = code_only(function_body(policy, "ITW_CLASH_HALParadrop_fnc_Execute"))
    assert '["_climbTimeout",-1]' in execute
    # The default is untouched, so the seam and HotDrop wait as they always did.
    assert "private _deadline = time + ITW_CLASH_HALParadrop_ClimbTimeout;" in execute
    assert "if (_climbTimeout >= 0) then {_deadline = time + _climbTimeout};" in execute


def test_the_run_in_drops_every_group_through_the_paradrop_owner():
    body = body_of("RunIn")
    assert body.count("forEach _cargoGroups") >= 2
    assert 'setVariable ["ITW_CLASH_HALParadropCargoGroup",_x]' in body
    assert 'setVariable ["ITW_CLASH_HALParadropOrigin",_origin]' in body
    assert "ITW_AllyParadropCargo" not in body, "the paradrop owner calls ITW, not this"
    assert '"multi-group-lift"' in body


def test_a_pass_that_does_not_drop_gives_hal_its_waypoint_back():
    """The worst the run-in may do is v4."""
    run = body_of("RunIn")
    assert "if (_dropped == 0 && {_aboard > 0}) exitWith {" in run
    declined = run[run.index("if (_dropped == 0 && {_aboard > 0}) exitWith {"):]
    assert "ITW_CLASH_HALUnload_fnc_AbortRunIn" in declined[:200]
    assert '"never-crossed"' in run
    assert '"passed-wide"' in run

    abort = body_of("AbortRunIn")
    assert "_wp setWaypointPosition [_dropZone,0];" in abort
    assert "_wp setWaypointCompletionRadius _radius;" in abort
    assert 'setVariable ["ITW_CLASH_HALUnloadPhase","TRANSIT"]' in abort
    assert "call ITW_CLASH_HALUnload_fnc_ClearDropState" in abort
    for forbidden in ("addWaypoint", "deleteWaypoint", "RYD_WPdel", ' land "GET OUT"'):
        assert forbidden not in abort, forbidden
    # And the radius it restores is the one it found, not a guess.
    assert "waypointCompletionRadius _wp" in body_of("ArmRunIn")


def test_only_one_of_the_seam_and_the_run_in_acts():
    """Two threads can reach the same aircraft: the watcher, and HAL's waypoint
    statement. A scheduled script can be paused between any two statements, so
    the check and the write are one uninterruptible step."""
    claim = body_of("Claim")
    assert "isNil {" in claim
    inside = claim[claim.index("isNil {"):]
    assert inside.index("getVariable") < inside.index("if (_was in _from)") < inside.index("setVariable")

    run = body_of("RunIn")
    arm = run.index('[_carrierGroup,["TRANSIT"],"RUN_IN"] call ITW_CLASH_HALUnload_fnc_Claim')
    drop = run.index('[_carrierGroup,["RUN_IN"],"DROPPING"] call ITW_CLASH_HALUnload_fnc_Claim')
    assert arm < run.index("call ITW_CLASH_HALUnload_fnc_ArmRunIn")
    assert arm < drop < run.index("ITW_CLASH_HALParadrop_fnc_Execute")

    seam = body_of("Unload")
    assert '["","TRANSIT","RUN_IN","SEAM"],"SEAM"' in seam
    assert seam.index("ITW_CLASH_HALUnload_fnc_Claim") < seam.index("ITW_ParamHelisUnload")


def test_the_seam_does_nothing_after_a_run_in_drop():
    """HAL's statement still fires, at the through point, a kilometre past the
    drop zone with nobody aboard. It has to find the lift finished."""
    seam = body_of("Unload")
    done = seam.index('"seam-after-run-in"')
    assert seam.index("if (!_mine && {!isNull _carrierGroup}) exitWith {") < done
    assert done < seam.index("ITW_CLASH_HALUnload_fnc_CargoGroups")
    assert done < seam.index("switch (_mode) do")
    # DROPPING and DROPPED are exactly the phases the seam may not take.
    assert '"DROPPING"' not in seam and '"DROPPED"' not in seam


def test_the_seam_can_still_take_an_armed_run():
    """If the waypoint completes before the watcher releases, the chalk is
    still aboard and somebody has to own it. That is the v4 seam, from where
    the aircraft is, and the RPT says so."""
    seam = body_of("Unload")
    assert 'if (_was isEqualTo "RUN_IN") then {' in seam
    assert '"seam-took-over"' in seam
    assert "call ITW_CLASH_HALUnload_fnc_ClearDropState" in seam


def test_one_roll_per_lift():
    """A quiet corridor is decided by chance and the question is now asked
    twice. Two rolls could tell a lift LAND a kilometre out and PARADROP on
    arrival, which is the hover again."""
    mode = body_of("Mode")
    assert '["_carrierGroup",grpNull]' in mode
    assert mode.count("call ITW_CLASH_HALParadrop_fnc_ShouldUse") == 1
    assert 'getVariable ["ITW_CLASH_HALUnloadRoll",[]]' in mode
    assert 'setVariable ["ITW_CLASH_HALUnloadRoll",_roll]' in mode
    assert 'setVariable ["ITW_CLASH_HALUnloadRoll",nil]' in body_of("TrackLift")
    assert "[_carrier,_state,_carrierGroup] call ITW_CLASH_HALUnload_fnc_Mode" in body_of("Unload")


def test_a_new_lift_starts_clean():
    body = body_of("TrackLift")
    assert 'setVariable ["ITW_CLASH_HALUnloadPhase","TRANSIT"]' in body
    assert 'setVariable ["ITW_CLASH_HALUnloadSerial",_serial]' in body
    assert "call ITW_CLASH_HALUnload_fnc_ClearDropState" in body
    patch = function_body(central(), "ITW_CLASH_HALUnload_fnc_PatchSource")
    assert '"[_cg,_AV,_unitG," + str _orderFile + "] call ITW_CLASH_HALUnload_fnc_TrackLift; "' in patch


def test_switched_off_the_run_in_leaves_v4():
    body = body_of("TrackLift")
    off = body.index("if (ITW_CLASH_HALUnloadRunIn) exitWith {")
    assert off < body.index("ITW_CLASH_HALUnloadClimbEnRoute")
    assert "spawn\n                    ITW_CLASH_HALUnload_fnc_RunIn" in body
    source = central()
    assert '"ITW_CLASH_HALUnloadRunIn",true' in source
    assert '"ITW_CLASH_HALUnloadHandback",true' in source
    assert "if (!ITW_CLASH_HALUnloadHandback) exitWith {false};" in body_of("Handback")


# ---------------------------------------------- handing the aircraft back to HAL

def test_hals_carrier_wait_ends_on_no_waypoints_or_on_mia():
    """Why a paradrop needs a handback at all. The egress route is waypoints,
    so the wait HAL leaves on an empty waypoint list does not end; and the flag
    it does read is cleared by the read, so one flag ends one wait."""
    hac = read(NR6 / "HAC_fnc.sqf")
    wait = hac[hac.index("RYD_Wait = "):hac.index("RYD_CreateDecoy = ")]
    assert "(count (waypoints _GDV)) < _wplimit" in wait
    assert (
        'case ((_this select 0) getVariable ["RydHQ_MIA",false]) : '
        '{_alive = false;(_this select 0) setVariable ["RydHQ_MIA",nil]};'
    ) in wait


def test_itw_unassigns_every_jumper():
    """Which is why HAL's own CargoM clear cannot find the carrier after a
    drop: it looks it up through assignedVehicle."""
    para = code_only(function_body(read(MISSION / "ITW_Attack.sqf"), "ITW_AtkParachute"))
    assert "unassignVehicle _unit;" in para


def test_four_orders_can_be_released_at_the_drop():
    """Their only reachable CargoM clear comes after they look the carrier up
    again, so releasing them early cannot send the aircraft home early."""
    for name, paths in RELEASE_AT_DROP.items():
        for path in paths:
            span = after_the_carrier_wait(path)
            guard = span.index("if (not (_alive) and not (_OtherGroup)) exitwith")
            assert span.index(CARGO_CLEAR) > guard, (name, path)
            for at in (m.start() for m in re.finditer(re.escape(CARGO_CLEAR), span)):
                line_start = span.rfind("\n", 0, at) + 1
                assert span[line_start:at] == "\t\t", (name, path, "not inside an exit block")
        assert name not in re.search(
            r'"ITW_CLASH_HALUnloadReleaseAtBreak",\[(.*?)\]', central()
        ).group(1)


def test_flank_and_sf_are_released_at_the_break():
    """They clear CargoM on the carrier group they already hold, on the line
    after the wait. Released at the drop they would turn the aircraft for home
    over the drop zone and the break would never be flown."""
    table = re.search(r'"ITW_CLASH_HALUnloadReleaseAtBreak",\[(.*?)\]', central()).group(1)
    for name, paths in RELEASE_AT_BREAK.items():
        assert f'"{name}"' in table, name
        for path in paths:
            span = after_the_carrier_wait(path)
            at = span.index(CARGO_CLEAR)
            line_start = span.rfind("\n", 0, at) + 1
            assert span[line_start:at] == "\t", (name, path, "expected an unconditional clear")
            assert "exitwith" not in span[:at].lower(), (name, path)
    handback = body_of("Handback")
    assert "_atBreak = _orderFile in ITW_CLASH_HALUnloadReleaseAtBreak;" in handback
    first = handback.index("if (!_atBreak) then {")
    wait = handback.index("ITW_CLASH_HALUnloadHandbackRadius")
    second = handback.index("if (_atBreak) then {")
    assert first < wait < second


def test_the_order_thread_is_released_with_hals_own_flag():
    body = body_of("OrderRelease")
    assert '_carrierGroup setVariable ["RydHQ_MIA",true];' in body
    # Once per squad that was aboard: the read clears it.
    assert 'for "_i" from 1 to (_orders max 1) do {' in body
    assert "ITW_CLASH_HALUnloadOrderReleaseWait" in body
    for forbidden in ('"Busy"', "CargoChosen", "terminate", "deleteWaypoint", '"CC"'):
        assert forbidden not in body, forbidden
    # C.L.A.S.H. already releases groups from HAL this way.
    assert '_group setVariable ["RydHQ_MIA",true];' in read(MISSION / "ITW_CLASH.sqf")


def test_a_flag_nobody_read_is_taken_back():
    """Left set, it would end the wait of the next lift this aircraft flies on
    its first poll, with the chalk aboard."""
    body = body_of("OrderRelease")
    unread = body.index('"order-release-unread"')
    assert body.index('_carrierGroup setVariable ["RydHQ_MIA",nil];') < unread
    assert "time >= _deadline" in body
    # RYD_Wait polls a carrier every 6 s; the window has to cover two polls.
    wait = int(re.search(r'"ITW_CLASH_HALUnloadOrderReleaseWait",(\d+)', central()).group(1))
    assert wait > 12, wait


def test_scargo_is_released_with_its_own_exit_at_the_break():
    scargo = read(HAL / "SCargo.sqf")
    assert '_busy = _GD getvariable ("CargoM" + (str _GD));' in scargo
    assert "(not (_busy) or (_timer > 600) or (_reqdone) or not (_alive));" in scargo

    body = body_of("Handback")
    assert '_carrierGroup setVariable ["CargoM" + str _carrierGroup,false];' in body
    clear = body.index('setVariable ["CargoM" + str _carrierGroup,false]')
    assert body.index("(_carrier distance2D _break) <= ITW_CLASH_HALUnloadHandbackRadius") < clear
    assert body.index("time >= _deadline") < clear
    # SCargo frees the carrier itself. This module never writes Busy.
    assert 'setVariable ["Busy"' not in central()
    assert 'setVariable ["ITW_CLASH_HALUnloadBreak",_break]' in body_of("Egress")


def test_the_handback_never_writes_to_a_lift_it_does_not_own():
    """Clearing CargoM on a lift in flight would send it home with the chalk
    aboard. The serial is taken when the drop finishes and checked before
    every write."""
    handback = body_of("Handback")
    assert 'private _serial = _carrierGroup getVariable ["ITW_CLASH_HALUnloadSerial",-1];' in handback
    clear = handback.index('setVariable ["CargoM" + str _carrierGroup,false]')
    assert handback.index("isNotEqualTo _serial) exitWith {") < clear
    assert "isPlayer _x" in handback
    release = body_of("OrderRelease")
    assert release.index("if !(call _current) exitWith {};") < release.index(
        'setVariable ["RydHQ_MIA",true]'
    )


def test_every_drop_is_handed_back_whichever_path_made_it():
    """Run A's one paradrop, 62 s later: three waypoints, Busy and CargoM both
    true. That was the seam path, so it gets the handback too."""
    seam = body_of("Unload")
    assert seam.count("ITW_CLASH_HALUnload_fnc_Handback") == 2
    para = seam[seam.index('case "PARADROP"'):seam.index('case "HOT_PARADROP"')]
    hot = seam[seam.index('case "HOT_PARADROP"'):seam.index('case "NO_LAND"')]
    for branch in (para, hot):
        assert branch.index("ITW_CLASH_HALUnload_fnc_Egress") < branch.index(
            "ITW_CLASH_HALUnload_fnc_Handback"
        )
    run = body_of("RunIn")
    assert run.index("call ITW_CLASH_HALUnload_fnc_Egress") < run.index(
        "call ITW_CLASH_HALUnload_fnc_Handback"
    )
    # A landing is HAL's own finish and is left to it.
    land = seam[seam.index("default {"):]
    assert "ITW_CLASH_HALUnload_fnc_Handback" not in land


def test_the_lift_line_says_which_path_wrote_it():
    source = central()
    line = next(x for x in source.splitlines() if "CLASH HAL UNLOAD | lift |" in x)
    assert "via=%11" in line
    assert source.count("CLASH HAL UNLOAD | lift |") == 1, "one format, two callers"
    assert '_chance,_capacity,"seam"' in body_of("Unload")
    assert '_chance,_capacity,"run-in"' in body_of("RunIn")


def test_the_boot_line_certifies_the_run_in():
    source = central()
    line = next(x for x in source.splitlines() if "hal-unload-ready" in x)
    for field in ("runIn=%6", "runInDistance=%7", "handback=%8", "sources=%9"):
        assert field in line, field
