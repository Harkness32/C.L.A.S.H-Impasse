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


def test_a_successful_drop_is_followed_by_an_egress():
    """Hark: "flew forward a bit and sat still". HAL's waypoint is deleted by
    the waypoint statement before Unload is spawned, so after the drop the
    carrier has no destination at all."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Unload"))
    assert body.count("call ITW_CLASH_HALUnload_fnc_Egress") == 2, (
        "both PARADROP and HOT_PARADROP"
    )
    for mode in ('_result = "PARADROP";', '_result = "HOT_PARADROP";'):
        tail = body[body.index(mode):body.index(mode) + 200]
        assert "ITW_CLASH_HALUnload_fnc_Egress" in tail, mode


def test_the_egress_is_two_waypoints_so_it_banks_instead_of_pivoting():
    """A single waypoint home makes the aircraft turn on the spot, which reads
    as the stall it is meant to cure."""
    body = code_only(function_body(central(), "ITW_CLASH_HALUnload_fnc_Egress"))
    assert "forEach [[_through,150],[_home,200]]" in body
    assert "ITW_CLASH_HALUnloadEgressThrough" in body
    assert "ITW_CLASH_HALUnloadEgressOffset" in body


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
