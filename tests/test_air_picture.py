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


def test_a_helicopter_is_never_hard_kill_however_it_is_armed():
    # An enemy gunship is a real air threat and opens counter-air demand like
    # any other combat aircraft, but it must not shut a corridor down: only
    # fixed-wing interceptors do that.
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_ThreatTier")
    air = body.index('isKindOf "Air"')
    hard = body.index("HARD_KILL", air)
    assert 'isKindOf "Plane"' in body[air:hard]
    # A helicopter is still combat air, so it still opens demand.
    combat = function_body(source, "ITW_CLASH_AirPicture_fnc_IsCombatAircraft")
    assert 'isKindOf "Plane"' not in combat
    # And it can never be counted as one of our own fighter responders either.
    fighter = function_body(source, "ITW_CLASH_AirPicture_fnc_IsFighter")
    assert 'isKindOf "Plane"' in fighter


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


def test_loss_counter_needs_several_losses_close_in_space_and_time():
    """Was a hard-coded pair. At a 2500m radius two losses is a bad afternoon,
    not a nest: one run raised 15 lift refusals and accepted none, 12 of them
    "recent-losses", while infantry walked 3484m, 3323m and 2200m. Seven
    aircraft died across the map and their discs covered it."""
    source = air_picture()
    # The trip is detected when a loss is recorded; LossClosed only reads the
    # areas that detection tripped.
    record = function_body(source, "ITW_CLASH_AirPicture_fnc_RecordLoss")
    assert "ITW_CLASH_AirPictureLossRadius" in record
    assert "ITW_CLASH_AirPictureLossWindow" in record
    assert "_score < ITW_CLASH_AirPictureLossThreshold" in record
    assert "count _pair < 2" not in record, "the hard-coded pair is the defect"
    closed = function_body(source, "ITW_CLASH_AirPicture_fnc_LossClosed")
    assert "ITW_CLASH_AirPictureLossRadius" in closed
    assert 'ITW_CLASH_AirPictureLossWindow",600' in source


def test_the_loss_threshold_is_four_and_settable():
    source = air_picture()
    assert '"ITW_CLASH_AirPictureLossThreshold",4' in source


def test_a_below_threshold_loss_says_so():
    """The old rule was silent about near-misses, so a corridor that was one
    loss away from closing looked identical to one nowhere near it."""
    record = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RecordLoss")
    assert "loss-below-threshold" in record


def test_the_loss_radius_spans_two_approaches_not_one_launcher():
    # One team can down two helicopters coming in from different directions,
    # and the crash sites land well over a kilometre apart.
    assert 'ITW_CLASH_AirPictureLossRadius",2500' in air_picture()


def test_a_closure_is_ten_minutes_flat_and_never_scales():
    """It used to double on every re-trip inside a 1800s window up to 2400s,
    with each trip resetting the clock - forty minutes from the most recent
    loss, which in a thirty minute run is permanent. Hark: "this means that we
    potentially ground all flights the entire game because some shitbird IFV
    got lucky."
    """
    source = air_picture()
    record = function_body(source, "ITW_CLASH_AirPicture_fnc_RecordLoss")
    assert "ITW_CLASH_AirPictureLossEscalation" not in source, "escalation is gone"
    assert "* 2) min" not in record, "no doubling"
    assert 'ITW_CLASH_AirPictureLossClosure",600' in source
    assert 'ITW_CLASH_AirPictureLossClosureMax",600' in source
    # And the memory goes with it: a nest that is still a nest re-trips on its
    # own merits, so there is nothing to escalate from.
    closed = function_body(source, "ITW_CLASH_AirPicture_fnc_LossClosed")
    assert "(time - (_x#1)) <= (_x#2)" in closed
    assert "max ITW_CLASH_AirPictureLossEscalation" not in closed


def test_a_lucky_ifv_can_never_close_a_corridor():
    """Hark: "losses due to AA, as in radar AA? yeah, different fucking story."

    An autocannon that happened to be looking up says nothing about whether the
    corridor is defended. It contributes zero, however many times it gets
    lucky."""
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_LossWeight")
    assert 'if !(_profile get "antiAir") exitWith {0}' in body


def test_radar_aa_counts_double():
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_LossWeight")
    assert 'if (_profile get "radar") exitWith {2}' in body
    # So two radar AA kills reach the threshold of four on their own.
    source = air_picture()
    threshold = int(
        re.search(r'"ITW_CLASH_AirPictureLossThreshold",(\d+)', source).group(1)
    )
    assert threshold == 4, threshold


def test_the_trip_is_weighted_not_counted():
    record = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RecordLoss")
    assert "_score = _score + (_x param [3,0])" in record
    assert "count _nearby <" not in record, "counting is the defect"


def test_the_killer_is_carried_from_the_kill_event_to_the_record():
    source = air_picture()
    on_kill = function_body(source, "ITW_CLASH_AirPicture_fnc_OnKill")
    assert "[_victim,_killer] call ITW_CLASH_AirPicture_fnc_RecordLoss" in on_kill
    record = function_body(source, "ITW_CLASH_AirPicture_fnc_RecordLoss")
    assert 'params ["_veh",["_killer",objNull]]' in record


def test_an_unknown_killer_is_not_treated_as_air_defence():
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_LossWeight")
    assert "if (isNull _killer) exitWith {0}" in body


def test_denial_timers_are_measured_in_hal_cycles():
    source = air_picture()
    # A flat three minutes is shorter than one HAL cycle in a big game, so a
    # corridor could reopen before HAL has looked again.
    cycle = function_body(source, "ITW_CLASH_AirPicture_fnc_HALCycleSeconds")
    assert 'RydHQ_myDelay' in cycle
    window = function_body(source, "ITW_CLASH_AirPicture_fnc_DenialWindow")
    assert "ITW_CLASH_AirPicture_fnc_HALCycleSeconds" in window
    assert "_cycle * ITW_CLASH_AirPictureDenialMobileCycles" in window
    assert "max ITW_CLASH_AirPictureDenialMobileFloor" in window
    assert 'ITW_CLASH_AirPictureDenialMobileCycles",3' in source
    assert 'ITW_CLASH_AirPictureDenialMobileFloor",480' in source


def test_hal_publishes_the_cycle_length_we_read():
    hal = (HAL / "HAC_fnc2.sqf").read_text(encoding="utf-8", errors="replace")
    assert '_HQ setVariable ["RydHQ_myDelay",_delay];' in hal
    assert "_delay = ((count _friends) * 5)" in hal
    # And the cycle counter the mobile rule counts in is maintained per commander.
    for name in ["HQSitRep.sqf", "HQSitRepB.sqf"]:
        sitrep = (HAL / "HAL" / name).read_text(encoding="utf-8", errors="replace")
        assert "RydHQ_Cyclecount" in sitrep


def test_a_mobile_launcher_needs_both_three_cycles_and_the_floor():
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RefreshDenials")
    assert '_cycles >= ITW_CLASH_AirPictureDenialMobileCycles' in body
    assert "_unseen >= _window" in body
    assert "RydHQ_Cyclecount" in body


def test_a_static_site_stays_closed_until_it_is_dead():
    source = air_picture()
    kind = function_body(source, "ITW_CLASH_AirPicture_fnc_DenialKind")
    assert 'isKindOf "StaticWeapon"' in kind
    assert '"radar"' in kind
    assert '"STATIC_SAM"' in kind
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_RefreshDenials")
    # It cannot move, so unseen only means nobody is looking: only death, or the
    # safety valve for a site that died unseen, reopens it.
    assert '_drop = "dead"' in body
    assert '"safety-valve"' in body
    assert 'ITW_CLASH_AirPictureDenialStaticValve",1200' in source


def test_a_fighters_window_is_short_only_while_we_scan_faster_than_hal():
    source = air_picture()
    window = function_body(source, "ITW_CLASH_AirPicture_fnc_DenialWindow")
    assert "if (ITW_CLASH_AirPicturePoll < _cycle) then {" in window
    assert "ITW_CLASH_AirPictureDenialFighterSeconds" in window
    assert 'ITW_CLASH_AirPictureDenialFighterSeconds",180' in source


def test_seeing_it_again_resets_the_timer_and_death_reopens_at_once():
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RefreshDenials")
    assert '_entry set ["lastSeenAt",time];' in body
    assert '_entry set ["lastSeenCycle",_cycle];' in body
    reset = body.index('_entry set ["lastSeenAt",time];')
    assert body.index('_drop = "dead"') > reset


def test_the_corridor_reads_the_memory_not_just_live_knowledge():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_KnownAirDefence")
    assert "ITW_CLASH_AirPicture_fnc_Denials" in body
    assert "RydHQ_KnEnemies" not in body
    # And the memory is refreshed on the air picture's clock, not HAL's.
    assert "[_hq] call ITW_CLASH_AirPicture_fnc_RefreshDenials;" in source


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


# ------------------------------------------------ protection grading

def test_protection_is_graded_from_the_vehicle_not_a_class_list():
    source = air_picture()
    body = function_body(source, "ITW_CLASH_AirPicture_fnc_ProtectionGrade")
    assert 'isKindOf "Tank"' in body
    assert 'isKindOf "Wheeled_APC_F"' in body
    assert 'configFile >> "CfgVehicles" >> _class >> "armor"' in body
    assert "ITW_CLASH_AirPictureArmourHeavy" in body
    assert "ITW_CLASH_AirPictureArmourLight" in body
    assert 'ITW_CLASH_AirPictureArmourHeavy",400' in source
    assert 'ITW_CLASH_AirPictureArmourLight",60' in source


def test_the_grade_is_cached_like_every_other_class_lookup():
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_ProtectionGrade")
    assert "ITW_CLASH_AirPictureProtection getOrDefault" in body
    assert "ITW_CLASH_AirPictureProtection set" in body
    assert "if (_cached >= 0) exitWith {_cached};" in body


def test_a_counter_may_be_one_grade_below_its_threat():
    # Demanding a match would price most factions out of answering armour.
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RequiredGrade")
    assert "ITW_CLASH_AirPicture_fnc_ProtectionGrade) - 1) max 0" in body
