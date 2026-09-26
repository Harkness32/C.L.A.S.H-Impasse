from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def coverage() -> str:
    return text("ITW_CLASH_HALThreatCoverage.sqf")


def generation() -> str:
    return text("ITW_CLASH_ForceGeneration.sqf")


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


# ---------------------------------------------------------------- the seam

def test_combat_buys_have_left_impasses_rows():
    source = coverage()
    # The whole point: a threat counter no longer competes with Impasse's own
    # spawner for the same tickets, so it no longer loses 113 times in 117.
    assert "ITW_CLASH_fnc_RequestCapability" not in source
    assert "GROUND_ATTACK_LIGHT" not in source
    assert "CAS_AIRCRAFT" not in source
    assert "ITW_CLASH_Generation_fnc_ETBFulfil" in source


def test_it_asks_for_a_need_never_a_vehicle_type():
    source = coverage()
    assert '"ANTI_ARMOR"' in source
    assert '"COUNTER_AIR"' in source
    cover = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_Cover")
    # The provider is chosen by doctrine here, but what can be built and what it
    # costs belong to Force Generation and the ETB.
    assert "ITW_CLASH_ETB_fnc_Authorize" not in cover
    assert "ITW_AtkSpawnVeh" not in source


def test_only_the_two_structural_gaps_open_demand():
    source = coverage()
    evaluate = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_Evaluate")
    for gone in ["RydHQ_EnInf", "RydHQ_EnCars", "RydHQ_EnArt", "RydHQ_EnCargo", "RydHQ_EnStatic"]:
        assert gone not in source, gone
    assert evaluate.count("ITW_CLASH_HALThreatCoverage_fnc_Refresh") == 2


# ------------------------------------------------------------------ threats

def test_threats_are_classified_from_the_vehicle_with_hal_as_the_known_set():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_ArmorThreats")
    # Invariant 2: HAL is the source of WHICH enemies are known. Its categories
    # are not, because they file a Rhino as a car.
    assert 'RydHQ_KnEnemies' in body
    assert "ITW_CLASH_AirPicture_fnc_IsArmoredThreat" in body
    # Rechecked as alive and still known at evaluation: HAL's lists refresh
    # once per cycle, so a dead tank can still sit in them.
    assert "alive _veh" in body


def test_counter_air_threats_come_from_the_air_picture():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_AirThreats")
    assert "ITW_CLASH_AirPicture_fnc_Hostiles" in body


# --------------------------------------------------------------- responders

def test_a_responder_counts_only_if_hal_can_use_it_or_is_using_it_on_this_need():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_ArmorCoverage")
    assert "ITW_CLASH_HALThreatCoverage_fnc_UsableGroups" in body
    assert "ITW_CLASH_HALThreatCoverage_fnc_TaskedAgainst" in body
    assert "if (!_usable && {!_tasked}) then {continue};" in body


def test_launcher_squads_count_a_quarter_and_only_when_loaded():
    source = coverage()
    assert 'ITW_CLASH_ThreatCoverageInfantryWeight",0.25' in source
    armor = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_ArmorCoverage")
    assert "ITW_CLASH_HALThreatCoverage_fnc_HasLoadedLauncher" in armor
    assert "ITW_CLASH_ThreatCoverageInfantryWeight" in armor
    loaded = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_HasLoadedLauncher")
    assert "secondaryWeapon _unit" in loaded
    assert "secondaryWeaponMagazine _unit" in loaded


def test_air_coverage_is_local_except_for_fighters():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_AirCoverage")
    # An AA squad on the far side of the map covers nothing: that is what made
    # the earlier map-wide count wrong.
    assert "_umbrella" in body
    assert "ITW_CLASH_AirPicture_fnc_AirDefenceProfile" in body
    assert "ITW_CLASH_ThreatCoverageAAInfantryUmbrella" in body
    assert "ITW_CLASH_AirPicture_fnc_IsFighter" in body
    assert 'ITW_CLASH_ThreatCoverageAAInfantryUmbrella",3000' in coverage()


def test_an_asset_still_driving_counts_as_committed_to_its_demand():
    source = coverage()
    body = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_EnRoute")
    assert "ITW_CLASH_ThreatCoverageEnRouteWindow" in body
    assert '(_x get "need") isEqualTo _need' in body
    # Otherwise the air lane, which has no funding wait, buys a second SPAA at
    # the next pacing interval while the first is still on the road.
    for name in [
        "ITW_CLASH_HALThreatCoverage_fnc_ArmorCoverage",
        "ITW_CLASH_HALThreatCoverage_fnc_AirCoverage",
    ]:
        assert "ITW_CLASH_HALThreatCoverage_fnc_EnRoute" in function_body(source, name)


def test_coverage_is_observed_not_assumed():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_TaskedAgainst")
    # Our offer hands HAL the whole group pool, so HAL may task a different
    # group than the one we bought.
    assert 'getVariable ["Busy" + str _group,false]' in body
    assert "ITW_CLASH_ThreatCoverageTarget" in body
    assert "ITW_CLASH_ThreatCoverageNeed" in body


# ----------------------------------------------------------------- demands

def test_one_demand_per_need_carrying_the_threat_that_caused_it():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Refresh")
    assert "_demands set [_need,_demand];" in body
    assert '["threat",_threat]' in body
    assert '["threatKey",_key]' in body


def test_a_demand_keeps_its_age_through_its_grace_period():
    source = coverage()
    body = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_Refresh")
    assert '(time - (_demand get "lastSeenAt")) >= _grace' in body
    assert "_demands deleteAt _need;" in body
    assert 'ITW_CLASH_ThreatCoverageGroundGrace",180' in source
    assert 'ITW_CLASH_ThreatCoverageAirGrace",300' in source
    # The age base is separate from the open time, so a reopen keeps it.
    assert '["ageAt",time]' in body


def test_ground_demand_waits_but_the_first_air_response_does_not():
    source = coverage()
    body = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_Funded")
    assert "ITW_CLASH_ThreatCoverageGroundPersistence" in body
    assert '_demand get "immediate"' in body
    assert 'ITW_CLASH_ThreatCoverageGroundPersistence",90' in source


def test_a_zone_change_clears_demands_and_failure_memory():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_ZoneGuard")
    assert "ITW_CLASH_ThreatCoverageDemands = createHashMap;" in body
    assert "ITW_CLASH_ThreatCoverageCommitments = createHashMap;" in body
    assert "ITW_ZoneIndex" in body


def test_failure_memory_makes_the_next_purchase_try_another_provider():
    source = coverage()
    assert 'ITW_CLASH_ThreatCoverageFailureMemory",600' in source
    choose = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_ChooseProvider")
    assert "ITW_CLASH_HALThreatCoverage_fnc_ProviderFailed" in choose
    cover = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_Cover")
    assert "ITW_CLASH_HALThreatCoverage_fnc_MarkProviderFailed" in cover


# ------------------------------------------------------------------- money

def test_existing_answers_come_before_any_purchase():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Cover")
    idle = body.index("ITW_CLASH_HALThreatCoverage_fnc_IdleAssets")
    paced = body.index("ITW_CLASH_ETB_fnc_Paced")
    buy = body.index("ITW_CLASH_Generation_fnc_ETBFulfil")
    assert idle < paced < buy
    assert '"IDLE_RESPONDER_REOFFERED"' in body
    assert '"PACING"' in body
    assert '"THREAT_GONE"' in body


def test_the_oldest_affordable_demand_gets_the_money_and_air_jumps_the_queue():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Evaluate")
    assert '{_x get "ageAt"},"ASCEND"' in body
    assert '(_x get "need") isEqualTo "COUNTER_AIR" && {_x get "immediate"}' in body
    assert "_queue insert [0,[_first]];" in body


def test_queue_rotation_stops_a_permanent_shortfall_starving_the_other_need():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Cover")
    assert '_demand set ["ageAt",time];' in body


def test_escrow_is_marked_with_the_real_price_of_the_bypassed_counter():
    source = coverage()
    body = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_Evaluate")
    assert "ITW_CLASH_ETB_fnc_MarkBypassed" in body
    assert "ITW_CLASH_Generation_fnc_ETBCheapestPrice" in body
    # Reachability is what keeps an unaffordable demand from freezing the rest.
    assert "ITW_CLASH_Generation_fnc_ETBCheapestPrice = {" in generation()


def test_only_one_purchase_per_pass():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Evaluate")
    assert "if (_spent) exitWith {};" in body


# ------------------------------------------------------------ provider choice

def test_the_aa_corridor_decides_between_cas_and_ground_anti_armor():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_ChooseProvider")
    assert "ITW_CLASH_AirPicture_fnc_ClassifyCorridor" in body
    assert '"corridor-cold"' in body
    assert '"corridor-contested"' in body
    assert 'in ["HOT","AIR_DENIED"]' in body
    # Cold favours CAS because it arrives fastest; hot is ground only.
    cold = body.index("corridor-cold")
    assert 'ANTI_ARMOR_CAS","corridor-cold"' in body[cold - 40:cold + 40]


def test_spaa_answers_counter_air_where_there_is_no_airport():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_ChooseProvider")
    assert "ITW_ObjOwnsAirport" in body
    assert '"CAP_AIRCRAFT","airport-owned"' in body
    assert '"SPAA","no-airport-or-cap-failed"' in body


# --------------------------------------------------- the generation contract

def test_candidates_come_from_impasses_own_attack_and_dual_rows():
    body = function_body(generation(), "ITW_CLASH_Generation_fnc_ETBCandidates")
    # Invariant 5: no foreign or hard-coded classes, nothing above its
    # escalation tier, no aircraft without an owned airport.
    assert "ITW_VEH_ROLE_ATTACK,ITW_VEH_ROLE_DUAL" in body
    assert "ITW_VEH_ZONES_OWNED" in body
    assert "ITW_ObjOwnsAirport" in body
    # Impasse's own balance is deliberately not read: the ETB does not care
    # whether Impasse can afford the row.
    assert "ITW_VEH_CURR_TICKETS" not in body
    assert "ITW_VEH_COUNT" not in body


def test_candidates_are_cheapest_first_so_a_too_dear_one_is_skipped():
    source = generation()
    body = function_body(source, "ITW_CLASH_Generation_fnc_ETBCandidates")
    assert '{_x#2},"ASCEND"' in body
    fulfil = function_body(source, "ITW_CLASH_Generation_fnc_ETBFulfil")
    assert '(_reply get "reason") isNotEqualTo "COST_EXCEEDS_CAPACITY"' in fulfil


def test_provider_definitions_are_read_off_the_vehicle_once():
    source = generation()
    body = function_body(source, "ITW_CLASH_Generation_fnc_ETBQualifiesProfile")
    assert '"GROUND_ANTI_ARMOR"' in body
    assert '"ANTI_ARMOR_CAS"' in body
    assert '"CAP_AIRCRAFT"' in body
    assert '"SPAA"' in body
    # An IFV with an incidental AA ability is not SPAA.
    assert '_profile get "antiAir"} && {!(_profile get "antiArmor")}' in body
    # The same definition answers a config guess and the spawned vehicle.
    for name in [
        "ITW_CLASH_Generation_fnc_ETBQualifiesClass",
        "ITW_CLASH_Generation_fnc_ETBQualifiesVehicle",
    ]:
        assert "ITW_CLASH_Generation_fnc_ETBQualifiesProfile" in function_body(source, name)


def test_the_transaction_reserves_first_and_returns_everything_on_failure():
    body = function_body(generation(), "ITW_CLASH_Generation_fnc_ETBFulfil")
    reserve = body.index("ITW_CLASH_ETB_fnc_Authorize")
    spawn = body.index("ITW_AtkSpawnVeh")
    assert reserve < spawn
    # Every failure after the reservation gives the money and the slot back.
    assert body.count("ITW_CLASH_ETB_fnc_Cancel") >= 5
    for reason in ["THREAT_GONE", "SPAWN_FAILED", "HAL_REGISTRATION_FAILED"]:
        assert reason in body, reason
    # A plane with no owned airport is denied by the spawn point and its reason
    # is carried back out, not swallowed.
    assert "[_spawnReason,[_class]] call _deny" in body
    assert 'AIRPORT_REQUIRED' in function_body(
        generation(), "ITW_CLASH_Generation_fnc_ETBSpawnPoint"
    )


def test_a_class_that_does_not_fulfil_its_capability_is_never_tried_again():
    body = function_body(generation(), "ITW_CLASH_Generation_fnc_ETBFulfil")
    check = body.index("ITW_CLASH_Generation_fnc_ETBQualifiesVehicle")
    assert "deleteVehicle _veh;" in body[check:]
    assert "ITW_CLASH_Generation_fnc_ETBRejectClass" in body[check:]
    candidates = function_body(generation(), "ITW_CLASH_Generation_fnc_ETBCandidates")
    assert "ITW_CLASH_ETBRejectedClasses" in candidates


def test_the_etb_registration_path_never_stamps_itw_vehdef():
    source = generation()
    body = function_body(source, "ITW_CLASH_Generation_fnc_ETBRegisterAsset")
    assert "ITW_VehDef" not in body
    assert "ITW_CLASH_DualHAL_fnc_RegisterGroup" in body
    # The Checkbook path still stamps it, which is why this one exists.
    assert 'setVariable ["ITW_VehDef",_vehDef];' in function_body(
        source, "ITW_CLASH_Generation_fnc_RegisterAsset"
    )


def test_spaa_enters_no_hal_dispatch_pool_at_all():
    body = function_body(generation(), "ITW_CLASH_Generation_fnc_ETBRegisterAsset")
    spaa = body.index('case "SPAA":')
    tail = body[spaa:]
    assert "ITW_CLASH_SPAAOverwatch" in tail
    for pool in ["RydHQ_RCAS", "RydHQ_RCAP", "RydHQ_AirG", "RydHQ_LArmorG", "RydHQ_CarsG"]:
        assert pool not in tail, pool


def test_players_are_cued_only_once_the_counter_air_has_been_spotted():
    source = coverage()
    body = function_body(source, "ITW_CLASH_HALThreatCoverage_fnc_WarnOpposingPlayers")
    assert "ITW_CLASH_AirPicture_fnc_IsKnown" in body
    assert "enemy fighters inbound" in body
    assert 'ITW_CLASH_ThreatCoverageAirWarning",true' in source


def test_the_air_reaction_reoffers_and_publishes_but_recalls_nothing():
    body = function_body(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_AirReaction")
    assert "ITW_CLASH_HALThreatCoverage_fnc_IdleAssets" in body
    assert "ITW_CLASH_AirAlarmPosition" in body
    # Flights already under way continue: that is the decided direction.
    assert "deleteWaypoint" not in body
    assert "doMove" not in body
