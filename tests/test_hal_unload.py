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
