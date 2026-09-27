import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def hotdrop() -> str:
    return text("ITW_CLASH_HotDrop.sqf")


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
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def test_transport_and_logistics_stay_separate():
    source = code_only(hotdrop())
    # HotDrop must not enter, claim or alter the logistics run in any way.
    for forbidden in [
        "ITW_CLASH_ThunderRun_fnc_Start",
        "ITW_CLASH_ThunderRun_fnc_Run",
        "ITW_CLASH_ThunderRun_fnc_ApplyStaging",
        "ITW_CLASH_ThunderRun_fnc_Dispose",
        "ITW_CLASH_ThunderRuns",
        "RYD_AmmoDrop",
        "RydHQ_AmmoPoints",
        "RydHQ_Boxed",
    ]:
        assert forbidden not in source, forbidden
    # And it owns its own state, not Thunder Run's.
    assert "ITW_CLASH_HotDropRuns = createHashMap;" in source


def test_it_borrows_the_payload_agnostic_machinery_by_calling_it():
    source = hotdrop()
    for borrowed in [
        "ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter",
        "ITW_CLASH_ThunderRun_fnc_InitFlareBudget",
        "ITW_CLASH_ThunderRun_fnc_MaybeFlare",
        "ITW_CLASH_AirPicture_fnc_ClassifyCorridor",
        "ITW_CLASH_HALParadrop_fnc_Execute",
    ]:
        assert borrowed in source, borrowed
    # Borrowed, not forked: none of them is redefined here.
    for borrowed in [
        "ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter",
        "ITW_CLASH_ThunderRun_fnc_InitFlareBudget",
        "ITW_CLASH_ThunderRun_fnc_MaybeFlare",
    ]:
        assert f"{borrowed} = {{" not in source, borrowed


def test_the_flare_state_keys_match_the_machinery_it_calls():
    source = hotdrop()
    core = text("ITW_CLASH_ThunderRun_Core.sqf")
    budget = function_body(core, "ITW_CLASH_ThunderRun_fnc_InitFlareBudget")
    assert '"countermeasureEmitter"' in budget
    assert '["countermeasureEmitter",' in source
    # The machinery's cadence table knows RELEASE, not DROP, so the drop phase
    # is mapped when asking for a flare and nowhere else.
    flare = function_body(source, "ITW_CLASH_HotDrop_fnc_Flare")
    assert '_phase isEqualTo "DROP"' in flare
    assert '"RELEASE"' in flare


def test_a_clear_approach_is_left_to_hal():
    source = hotdrop()
    body = function_body(source, "ITW_CLASH_HotDrop_fnc_Consider")
    assert "ITW_CLASH_AirPicture_fnc_ClassifyCorridor" in body
    assert "if !(_corridorState in ITW_CLASH_HotDropStates) exitWith {false};" in body
    assert 'ITW_CLASH_HotDropStates",["CONTESTED","HOT","AIR_DENIED"]' in source
    assert '"COLD"' in body


def test_it_only_takes_the_airframe_for_the_last_leg():
    source = hotdrop()
    body = function_body(source, "ITW_CLASH_HotDrop_fnc_Consider")
    code = code_only(source)
    assert "ITW_CLASH_HotDropTakeoverRadius" in body
    assert 'ITW_CLASH_HotDropTakeoverRadius",3000' in source
    # And it never asks HAL for a lift or changes HAL's mind about one.
    assert "ITW_CLASH_fnc_RequestCapability" not in code
    assert "HAL_SCargo" not in code


def test_nothing_a_player_touches_is_taken():
    source = hotdrop()
    eligible = function_body(source, "ITW_CLASH_HotDrop_fnc_IsEligible")
    assert "(crew _veh) findIf {isPlayer _x} >= 0" in eligible
    consider = function_body(source, "ITW_CLASH_HotDrop_fnc_Consider")
    assert "((units _cargoGroup) findIf {isPlayer _x}) >= 0" in consider
    cargo = function_body(source, "ITW_CLASH_HotDrop_fnc_CargoGroup")
    assert "isPlayer _unit" in cargo


def test_runs_owned_by_another_system_are_left_alone():
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible")
    assert 'ITW_CLASH_ThunderRunActive' in body
    assert "ITW_CLASH_CASEVAC_State" in body
    assert "ITW_CLASH_GroundMEDEVAC_State" in body
    assert "ITW_CLASH_HotDropCooldownUntil" in body


def test_cargo_means_passengers_not_the_door_gunner():
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_CargoGroup")
    assert "_unitGroup isEqualTo _crewGroup" in body
    assert '_role in ["Driver","Turret"]' in body
    assert 'isKindOf "CAManBase"' in body


def test_the_host_decides_whether_troops_may_parachute():
    source = hotdrop()
    body = function_body(source, "ITW_CLASH_HotDrop_fnc_PutOut")
    # ITW_ParamHelisUnload 0 means the host wants landings.
    assert "ITW_ParamHelisUnload" in body
    assert "_unload > 0" in body
    assert '_veh land "GET OUT";' in body
    assert "ITW_CLASH_HALParadrop_fnc_Execute" in body


def test_the_pop_up_puts_it_above_the_paradrop_minimum():
    source = hotdrop()
    assert 'ITW_CLASH_HotDropDropHeight",130' in source
    paradrop = text("ITW_CLASH_HALParadrop.sqf")
    assert 'ITW_CLASH_HALParadrop_MinAltitude",55' in paradrop
    # 130 clears 55, so the drop needs no second climb.
    assert 'ITW_CLASH_HotDropIngressHeight",25' in source


def test_the_airframe_is_always_handed_back():
    source = hotdrop()
    body = function_body(source, "ITW_CLASH_HotDrop_fnc_Handback")
    assert 'enableAI "TARGET"' in body
    assert 'enableAI "AUTOTARGET"' in body
    assert "forceSpeed -1" in body
    assert "ITW_CLASH_HotDropTransitHeight" in body
    assert 'setVariable ["ITW_CLASH_HotDropActive",false,true]' in body
    # Every phase exit leads to a handback, including a lost airframe.
    run = function_body(source, "ITW_CLASH_HotDrop_fnc_Run")
    assert run.count("ITW_CLASH_HotDrop_fnc_Handback") >= 2
    assert '"AIRFRAME_LOST"' in run
    assert "ITW_CLASH_HotDropPhaseTimeout" in run


def test_it_loads_behind_the_air_picture():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_HotDrop.sqf"' in init
    assert "hot-drop-missing-or-prereq-failed" in init
    assert init.index('"ITW_CLASH_AirPicture.sqf"') < init.index('"ITW_CLASH_HotDrop.sqf"')
