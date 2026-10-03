import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def scoot() -> str:
    return text("ITW_CLASH_ArtilleryScoot.sqf")


def battery() -> str:
    return text("ITW_CLASH_CounterBattery.sqf")


def code_only(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


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


# ----------------------------------------------------------------- scoot

def test_hal_already_counts_the_rounds_we_drive_off():
    hal = (HAL / "HAC_fnc.sqf").read_text(encoding="utf-8", errors="replace")
    assert 'setVariable ["RydHQ_ShotFired",true]' in hal
    assert 'RydHQ_ShotFired2' in hal
    assert "RydHQ_ShotFired2" in scoot()


def test_a_gun_moves_only_between_missions():
    body = function_body(scoot(), "ITW_CLASH_ArtilleryScoot_fnc_ShouldMove")
    # Still climbing round count means the mission is live.
    assert '[false,"still-firing"]' in body
    assert '[false,"settling"]' in body
    assert "ITW_CLASH_ArtilleryScootSettle" in body
    assert '[false,"hal-busy"]' in body
    assert 'ITW_CLASH_ArtilleryScootSettle",45' in scoot()


def test_it_moves_only_after_firing_enough_from_one_spot():
    source = scoot()
    body = function_body(source, "ITW_CLASH_ArtilleryScoot_fnc_ShouldMove")
    assert "_since < ITW_CLASH_ArtilleryScootRounds" in body
    assert "ITW_CLASH_ArtilleryScootBaseline" in body
    assert 'ITW_CLASH_ArtilleryScootRounds",6' in source
    assert 'ITW_CLASH_ArtilleryScootCooldown",240' in source


def test_it_never_displaces_toward_the_enemy():
    source = scoot()
    body = function_body(source, "ITW_CLASH_ArtilleryScoot_fnc_NextPosition")
    assert "ITW_CLASH_ArtilleryScootStandoff" in body
    assert "if (_safety < _hereSafety) then {continue};" in body
    assert "surfaceIsWater" in body
    assert 'ITW_CLASH_ArtilleryScootStandoff",1200' in source
    # Nowhere better means stay and fire, not drive into contact.
    move = function_body(source, "ITW_CLASH_ArtilleryScoot_fnc_Move")
    assert '"no-position"' in move


def test_it_changes_behaviour_not_the_mission():
    source = code_only(scoot())
    # It must not fire, retarget or cancel anything HAL decided.
    for forbidden in ["doArtilleryFire", "commandArtilleryFire", "RydHQ_ArtTargets", "doFire"]:
        assert forbidden not in source, forbidden
    # And it never touches a player's gun.
    guns = function_body(scoot(), "ITW_CLASH_ArtilleryScoot_fnc_Guns")
    assert "isPlayer _x" in guns


def test_a_move_that_stalls_releases_the_gun():
    body = function_body(scoot(), "ITW_CLASH_ArtilleryScoot_fnc_Settle")
    assert "ITW_CLASH_ArtilleryScootTimeout" in body
    assert 'ITW_CLASH_ArtilleryScootMoving",false' in body
    # A new position resets the round baseline, so it earns the next move afresh.
    assert "ITW_CLASH_ArtilleryScootBaseline" in body


# -------------------------------------------------------- counter-battery

def test_a_fix_is_earned_by_being_shelled_not_looked_up():
    source = battery()
    body = function_body(source, "ITW_CLASH_CounterBattery_fnc_Observe")
    # The gate is witnesses near the impact, not knowledge of the gun.
    assert "ITW_CLASH_CounterBatteryAcquireRadius" in body
    assert "if (_witnesses isEqualTo []) then {continue};" in body
    assert 'ITW_CLASH_CounterBatteryAcquireRadius",400' in source
    # A side never acquires a fix on its own guns.
    assert "if (_side isEqualTo _shooterSide) then {continue};" in body


def test_the_impact_is_followed_not_computed():
    source = battery()
    body = function_body(source, "ITW_CLASH_CounterBattery_fnc_Track")
    assert "_last = getPosATL _projectile" in body
    assert "ITW_CLASH_CounterBatteryFlightCap" in body
    watch = function_body(source, "ITW_CLASH_CounterBattery_fnc_Watch")
    assert '_veh addEventHandler ["Fired"' in watch
    assert "_projectile" in watch


def test_the_error_shrinks_with_rounds_observed():
    source = battery()
    body = function_body(source, "ITW_CLASH_CounterBattery_fnc_Error")
    assert "ITW_CLASH_CounterBatteryErrorFirst" in body
    assert "ITW_CLASH_CounterBatteryErrorFloor" in body
    assert "ITW_CLASH_CounterBatteryErrorRounds" in body
    assert 'ITW_CLASH_CounterBatteryErrorFirst",450' in source
    assert 'ITW_CLASH_CounterBatteryErrorFloor",120' in source
    assert 'ITW_CLASH_CounterBatteryErrorRounds",4' in source


def test_fixes_go_cold():
    source = battery()
    assert 'ITW_CLASH_CounterBatteryFixLife",900' in source
    expire = function_body(source, "ITW_CLASH_CounterBattery_fnc_Expire")
    assert "ITW_CLASH_CounterBatteryFixLife" in expire
    assert '"fix-cold"' in expire
    leads = function_body(source, "ITW_CLASH_CounterBattery_fnc_Leads")
    assert "ITW_CLASH_CounterBatteryFixLife" in leads


def test_leads_are_offered_sharpest_first():
    body = function_body(battery(), "ITW_CLASH_CounterBattery_fnc_Leads")
    assert '{_x#1},"ASCEND"' in body


def test_counter_battery_only_observes():
    source = code_only(battery())
    # It publishes leads. Anything that acts on them lives elsewhere.
    for forbidden in [
        "ITW_CLASH_ETB_fnc_Authorize",
        "RYD_Dispatcher",
        "GoSFAttack",
        "doMove",
        "addWaypoint",
        "createVehicle",
        "doArtilleryFire",
    ]:
        assert forbidden not in source, forbidden


def test_guns_are_found_from_config_not_a_class_list():
    body = function_body(battery(), "ITW_CLASH_CounterBattery_fnc_Sweep")
    assert "artilleryScanner" in body
    # Same test the echelon rule uses, so modded guns work.
    assert "artilleryScanner" in text("ITW_CLASH_DualHALCheckbook.sqf")


def test_scoot_leaves_a_stale_fix_which_is_the_whole_point():
    # The two files are each other's counterplay: the fix is on where the gun
    # was, and scooting invalidates it.
    settle = function_body(scoot(), "ITW_CLASH_ArtilleryScoot_fnc_Settle")
    assert 'setVariable ["ITW_CLASH_ArtilleryMovedAt",time,true]' in settle
    observe = function_body(battery(), "ITW_CLASH_CounterBattery_fnc_Observe")
    # The fix records the firing position at the moment of firing.
    assert "_shooterPosition" in observe
    watch = function_body(battery(), "ITW_CLASH_CounterBattery_fnc_Watch")
    assert "getPosATL _unit" in watch


def test_both_load_and_warn_when_they_cannot():
    init = text("init.sqf")
    for name, warning in [
        ("ITW_CLASH_CounterBattery.sqf", "counter-battery-missing"),
        ("ITW_CLASH_ArtilleryScoot.sqf", "artillery-scoot-missing"),
    ]:
        assert f'call compile preprocessFileLineNumbers "{name}"' in init
        assert warning in init
