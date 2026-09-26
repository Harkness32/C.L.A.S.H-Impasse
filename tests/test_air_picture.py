import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def air_picture() -> str:
    return text("ITW_CLASH_AirPicture.sqf")


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


def test_air_picture_only_observes():
    source = air_picture()
    # Nothing here may buy, task, move or open a demand: ThreatCoverage turns
    # the signal into a demand and the ETB only sees the demand.
    for forbidden in [
        "ITW_CLASH_fnc_RequestCapability",
        "RYD_Dispatcher",
        "doMove",
        "addWaypoint",
        "createVehicle",
        "ITW_CLASH_ETB_fnc",
    ]:
        assert forbidden not in source, forbidden


def test_it_uses_hals_own_knowledge_test_on_a_faster_clock():
    source = air_picture()
    hal = (HAL / "HAC_fnc2.sqf").read_text(encoding="utf-8", errors="replace")
    # HAL's own threshold, so the picture can never see more than HAL would.
    assert "knowsAbout _enemyU) >= 0.05" in hal
    assert 'ITW_CLASH_AirPictureKnowledgeThreshold",0.05' in source
    assert "(_x knowsAbout _veh) >= ITW_CLASH_AirPictureKnowledgeThreshold" in source
    assert 'ITW_CLASH_AirPicturePoll",5' in source
    assert 'Ryd_NoReports' in source


def test_sighting_waits_but_a_kill_by_enemy_air_does_not():
    source = air_picture()
    assert 'ITW_CLASH_AirPictureSightingGrace",15' in source
    assert 'ITW_CLASH_AirPictureUnseenTimeout",300' in source
    assert '"EntityKilled"' in source
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_Hostiles")
    assert "_immediate ||" in body
    assert "ITW_CLASH_AirPictureSightingGrace" in body


def test_armor_threats_are_classified_from_the_vehicle_not_hals_categories():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_IsArmoredThreat")
    # Armored base class AND real anti-armor ammo: HAL files a Rhino as a car
    # and a Bobcat as heavy armor, so its categories would be wrong both ways.
    assert 'isKindOf "Tank"' in body
    assert 'isKindOf "Wheeled_APC_F"' in body
    assert '"antiArmor"' in body
    assert "RydHQ_EnHArmor" not in body
    assert "RHQ_HArmor" not in body


def test_anti_armor_test_is_the_engine_flag_the_echelon_rule_already_uses():
    source = air_picture()
    assert "ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo" in source
    checkbook = text("ITW_CLASH_DualHALCheckbook.sqf")
    assert "ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo = {" in checkbook
    assert "512" in checkbook


def test_anti_air_test_matches_hals_own_auto_classification():
    source = air_picture()
    hal = (HAL / "HAC_fnc2.sqf").read_text(encoding="utf-8", errors="replace")
    assert 'getNumber (_ammoC >> "airLock")) > 1' in hal
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_IsAntiAirAmmo")
    assert '"airLock")) > 1' in body


def test_combat_aircraft_excludes_door_gun_transports():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_IsCombatAircraft")
    assert '"antiArmor"' in body
    assert '"ordnance"' in body
    assert '"antiAirMissile"' in body
    # Merely being armed is not enough - a minigun transport is not a threat.
    assert '(_profile get "armed")' not in body
    ordnance = function_body(source, "ITW_CLASH_AirPicture_fnc_AmmoIsOrdnance")
    assert "shotbullet" not in ordnance


def test_spaa_is_air_capable_and_not_an_ifv_with_an_incidental_ability():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_IsSPAA")
    assert '(_profile get "antiAir")' in body
    assert '!(_profile get "antiArmor")' in body


def test_air_defence_weights_and_umbrellas_match_the_decided_table():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_AirDefenceProfile")
    assert '["MANPAD",0.25,ITW_CLASH_AirPictureManpadUmbrella]' in body
    assert '["STATIC_AA_GUN",0.25,ITW_CLASH_AirPictureStaticGunUmbrella]' in body
    assert '["STATIC_AA_LAUNCHER",0.25,ITW_CLASH_AirPictureManpadUmbrella]' in body
    assert '["RADAR_SAM",1,ITW_CLASH_AirPictureRadarUmbrella]' in body
    assert '["SPAA",1,ITW_CLASH_AirPictureSPAAUmbrella]' in body
    assert '["CRAM",1,ITW_CLASH_AirPictureCRAMUmbrella]' in body
    assert 'ITW_CLASH_AirPictureManpadUmbrella",3000' in source
    assert 'ITW_CLASH_AirPictureStaticGunUmbrella",1500' in source
    assert 'ITW_CLASH_AirPictureRadarUmbrella",5000' in source
    assert 'ITW_CLASH_AirPictureCRAMUmbrella",3000' in source
    # Radar comes from the vehicle's own sensors, so modded SAM sites work.
    assert "SensorsManagerComponent" in source
    assert "activeradarsensorcomponent" in source


def test_only_systems_built_to_kill_aircraft_are_hard_kill():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_ThreatTier")
    assert "ITW_CLASH_AirPictureHardKillMissiles" in body
    assert '"HARD_KILL"' in body
    assert '"TOLERATED"' in body
    assert 'ITW_CLASH_AirPictureHardKillMissiles",4' in source
    # A MANPAD or a static gun never closes a corridor.
    tiers = [line for line in body.splitlines() if "HARD_KILL" in line]
    assert all("Manpad" not in line and "StaticGun" not in line for line in tiers)


def test_corridor_gate_adds_what_hal_does_not_know_about():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_ClassifyCorridor")
    # HAL's AA list, plus gun-only AA and radar sites it never files, plus our
    # own recent losses.
    assert 'RydHQ_AAthreat' in body
    assert "ITW_CLASH_AirPicture_fnc_KnownAirDefence" in body
    assert "ITW_CLASH_AirPicture_fnc_LossClosed" in body
    assert "ITW_CLASH_ThunderRun_fnc_CorridorStats" in body
    for state in ["COLD", "CONTESTED", "HOT", "AIR_DENIED"]:
        assert f'"{state}"' in body


def test_loss_counter_needs_two_losses_close_in_space_and_time():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_LossClosed")
    assert "ITW_CLASH_AirPictureLossRadius" in body
    assert "ITW_CLASH_AirPictureLossWindow" in body
    assert "count _recent < 2" in body
    assert 'ITW_CLASH_AirPictureLossRadius",1500' in source
    assert 'ITW_CLASH_AirPictureLossWindow",600' in source


def test_front_application_is_a_setting_with_the_open_question_recorded():
    source = air_picture()
    assert 'ITW_CLASH_AirPictureIgnoreFront",true' in source
    assert "Open question for Hark" in source
    assert "RydHQ_Front" in source


def test_air_picture_loads_before_threat_coverage():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_AirPicture.sqf"' in init
    assert "air-picture-missing" in init
    assert init.index("ITW_CLASH_AirPicture.sqf") < init.index("ITW_CLASH_HALThreatCoverage.sqf")
