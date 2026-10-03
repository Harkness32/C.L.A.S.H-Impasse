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
    # COLD was briefly included; including it made HotDrop take essentially
    # every troop lift on the map, which is more intervention than the profile
    # is worth when nothing is shooting.
    source = hotdrop()
    body = function_body(source, "ITW_CLASH_HotDrop_fnc_Run")
    assert "ITW_CLASH_AirPicture_fnc_ClassifyCorridor" in body
    assert 'ITW_CLASH_HotDropStates",["CONTESTED","HOT","AIR_DENIED"]' in source
    assert '"COLD"' in body


def test_the_quiet_ones_are_handed_back_at_launch():
    # The decline fires on the real corridor, read from the real route, after
    # the lift has launched - not at boarding where there was no route yet.
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Run")
    assert "if !(_corridorState in ITW_CLASH_HotDropStates) exitWith {" in body
    assert '"declined"' in body


def test_it_only_takes_the_airframe_for_the_last_leg():
    source = hotdrop()
    body = function_body(source, "ITW_CLASH_HotDrop_fnc_Run")
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


def test_the_mission_is_never_changed_only_the_behaviour():
    source = hotdrop()
    # The decided line: a committed flight goes in. HotDrop may change how it
    # flies, never where it is going or whether it goes.
    run = function_body(source, "ITW_CLASH_HotDrop_fnc_Run")
    # Every doMove in the run is to a point derived from the lift's own
    # destination - an initial point, the destination, or an egress away from
    # it - never to a place of safety.
    assert run.count("doMove") == 3
    assert "_driver doMove _ip;" in run
    assert "_driver doMove _destination;" in run
    assert "_driver doMove _away;" in run
    assert "_ip = _destination getPos" in run
    assert "_away = _destination getPos" in run
    # And nothing anywhere cancels the lift or sends it home.
    code = code_only(source)
    for forbidden in ["RTB", "ReturnHome", "_home", "land \"NONE\""]:
        assert forbidden not in code, forbidden


# --------------------------------------------- v2: claimed at boarding

def test_it_never_seizes_an_airborne_lift():
    # The v1 defect: a map-wide scan found aircraft another system had already
    # planned and flew them somewhere else two minutes into their own flight.
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible")
    assert "ITW_CLASH_HotDropBoardingHeight" in body
    assert '((getPosATL _veh)#2) > ITW_CLASH_HotDropBoardingHeight' in body
    # And the old inverted test is gone.
    assert "< ITW_CLASH_HotDropIngressHeight) exitWith {false}" not in body


def test_the_scan_only_looks_at_loading_aircraft():
    source = hotdrop()
    tail = source[source.index("while {isNil \"ITW_GameOver\""):]
    assert "((getPosATL _x)#2) <= ITW_CLASH_HotDropBoardingHeight" in tail
    assert 'ITW_CLASH_HotDropBoardingHeight",3' in source


def test_it_yields_to_an_owner_that_already_has_the_lift():
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible")
    assert 'isNil {_crewGroup getVariable "ITW_CLASH_HALParadropCargoGroup"}' in body
    # That marker is what the native SF insertion path sets on selection.
    native = text("ITW_CLASH_HALNativeSFFix.sqf")
    assert '_carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_team]' in native


def test_passengers_must_actually_be_aboard_to_be_claimed():
    source = hotdrop()
    consider = function_body(source, "ITW_CLASH_HotDrop_fnc_Consider")
    assert "ITW_CLASH_HotDrop_fnc_Aboard) isEqualTo []) exitWith {false}" in consider
    aboard = function_body(source, "ITW_CLASH_HotDrop_fnc_Aboard")
    # Same test the DROP phase uses, so the two cannot disagree.
    assert "alive _x && {vehicle _x == _veh}" in aboard
    run = function_body(source, "ITW_CLASH_HotDrop_fnc_Run")
    assert "alive _x && {vehicle _x == _veh}" in run


def test_a_declined_lift_is_not_reconsidered():
    source = hotdrop()
    consider = function_body(source, "ITW_CLASH_HotDrop_fnc_Run")
    assert 'setVariable ["ITW_CLASH_HotDropDeclined",true]' in consider
    eligible = function_body(source, "ITW_CLASH_HotDrop_fnc_IsEligible")
    assert 'getVariable ["ITW_CLASH_HotDropDeclined",false]) exitWith {false}' in eligible
    assert '"declined"' in consider


def test_still_boarding_is_not_a_decision():
    # The occupancy rejection must NOT mark the lift declined, or a lift would
    # be refused for the crime of not having finished loading yet.
    consider = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Consider")
    head = consider[:consider.index("ITW_CLASH_HotDrop_fnc_Aboard) isEqualTo []")]
    assert "ITW_CLASH_HotDropDeclined" not in head


def test_land_fallback_actually_lands():
    # The paradrop module lands for itself on exactly one of its false returns.
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_PutOut")
    assert 'if (!_dropped && {([_veh,_cargoGroup] call ITW_CLASH_HotDrop_fnc_Aboard) isNotEqualTo []}) then {' in body
    assert body.count('_veh land "GET OUT"') == 2
    paradrop = text("ITW_CLASH_HALParadrop.sqf")
    assert paradrop.count('_carrier land "GET OUT"') == 1


def test_both_put_out_paths_report_a_real_altitude():
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_PutOut")
    assert body.count('round ((getPosATL _veh)#2)') == 2
    # The LAND branch used to log the unload setting where metres are printed.
    assert 'groupId _cargoGroup,_unload]' not in body


def test_the_put_out_sentence_is_not_misindexed():
    loud = text("ITW_CLASH_LoudDebug.sqf")
    line = [l for l in loud.splitlines() if "troops out by" in l][0]
    placeholders = {int(p) for p in re.findall(r"%(\d)", line)}
    supplied = len(re.findall(r"\d+ call _p", line))
    assert max(placeholders) <= supplied, (placeholders, supplied)


def test_the_decline_speaks():
    loud = text("ITW_CLASH_LoudDebug.sqf")
    assert 'case "hot-drop|declined"' in loud


def test_the_version_moved():
    assert "ITW_CLASH_HotDropVersion = 5;" in hotdrop()
    assert "claimedAt=boarding" in hotdrop()
    assert "seizesAirborne=false" in hotdrop()


# ------------------------------------- v4: the lift has to be going somewhere

def test_the_destination_is_not_read_at_boarding():
    # At the pickup the pilot's expectedDestination is the LZ it just landed
    # on, so reading it there gives the aircraft's own position.
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Consider")
    assert "ITW_CLASH_HotDrop_fnc_Destination" not in body
    assert "ITW_CLASH_HotDropTakeoverRadius" not in body
    assert '_veh,_cargoGroup,[],_hq,""' in body
    assert '_state set ["boardedAt",getPosATL _veh]' in body


def test_nothing_flies_until_the_lift_is_airborne_and_going_somewhere():
    source = hotdrop()
    body = function_body(source, "ITW_CLASH_HotDrop_fnc_Run")
    assert "ITW_CLASH_HotDrop_fnc_Destination" in body
    assert "((getPosATL _veh)#2) > ITW_CLASH_HotDropBoardingHeight" in body
    assert "(_now distance2D _boardedAt) >= ITW_CLASH_HotDropMinRun" in body
    assert "(_now distance2D (getPosATL _veh)) >= ITW_CLASH_HotDropMinRun" in body
    assert 'ITW_CLASH_HotDropMinRun",600' in source


def test_the_launch_wait_comes_before_any_flying():
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Run")
    assert body.index("ITW_CLASH_HotDropLaunchTimeout") < body.index('"INGRESS"')
    assert body.index("ITW_CLASH_HotDropMinRun") < body.index("flyInHeight")


def test_a_lift_that_never_launches_is_handed_back_untouched():
    source = hotdrop()
    body = function_body(source, "ITW_CLASH_HotDrop_fnc_Run")
    assert 'if (_destination isEqualTo []) exitWith {["NO_RUN"] call _abort};' in body
    assert 'ITW_CLASH_HotDropLaunchTimeout",900' in source


def test_losing_the_squad_while_waiting_ends_the_run():
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Run")
    assert "ITW_CLASH_HotDrop_fnc_Aboard) isEqualTo []" in body


def test_the_corridor_is_read_from_the_real_route():
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Run")
    assert body.index('_state set ["destination"') < body.index("ClassifyCorridor")


def test_the_profile_is_still_only_the_last_leg():
    # Claiming at boarding means owning the whole flight, but the 25 m ingress
    # must not start until the aircraft is near the drop.
    body = function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Run")
    assert "(_now distance2D (getPosATL _veh)) <= ITW_CLASH_HotDropTakeoverRadius" in body
