import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def resupply() -> str:
    return text(MISSION / "ITW_CLASH_Resupply.sqf")


def fn(name: str) -> str:
    source = resupply()
    start = source.index(f"{name} = {{")
    end = source.index("\n};", start)
    return source[start:end]


def default(name: str) -> float:
    match = re.search(rf'\["{name}",([0-9.]+)\]', resupply())
    assert match, name
    return float(match.group(1))


def test_one_owner_replaces_the_dormant_withdrawal_file():
    assert not (MISSION / "ITW_CLASH_VehicleLogisticsWithdrawal.sqf").exists()
    source = resupply()
    for name in [
        "ITW_CLASH_Resupply_fnc_Detect",
        "ITW_CLASH_Resupply_fnc_Claim",
        "ITW_CLASH_Resupply_fnc_Dispatch",
        "ITW_CLASH_Resupply_fnc_ServiceAtCrate",
        "ITW_CLASH_Resupply_fnc_Release",
    ]:
        assert f"{name} = {{" in source


def test_native_hal_gets_first_chance_before_a_claim():
    detect = fn("ITW_CLASH_Resupply_fnc_Detect")
    in_flight = detect.index("ITW_CLASH_Resupply_fnc_InFlight")
    patience = detect.index("ITW_CLASH_ResupplyPatience")
    claim = detect.index("ITW_CLASH_Resupply_fnc_Claim")
    assert in_flight < patience < claim
    # patience restarts while a native delivery is actually running
    assert '_group setVariable ["ITW_CLASH_ResupplyNeedSince",[time,time]]' in detect


def test_in_flight_is_judged_by_real_execution_not_supported_lists():
    in_flight = fn("ITW_CLASH_Resupply_fnc_InFlight")
    assert "ITW_CLASH_ResupplyInFlight" in in_flight
    assert "ITW_CLASH_ThunderRuns" in in_flight
    # HAL rebuilds its supported lists every sitrep cycle and marks a dry
    # vehicle "covered" from 300m away, so those lists can't be trusted here.
    assert "SupportedG" not in in_flight


def test_all_three_native_delivery_scripts_are_stamped():
    source = resupply()
    for native in ["HAL_GoAmmoSupp", "HAL_GoFuelSupp", "HAL_GoRepSupp"]:
        wrapper_start = source.index(f"    {native} = {{")
        wrapper = source[wrapper_start:source.index("\n    };", wrapper_start)]
        assert "[_group,1] call ITW_CLASH_Resupply_fnc_Stamp" in wrapper
        assert "[_group,-1] call ITW_CLASH_Resupply_fnc_Stamp" in wrapper
        assert wrapper.index("[_group,1]") < wrapper.index("Base;") < wrapper.index("[_group,-1]")


def test_stamps_bind_after_the_player_demand_interceptor():
    source = resupply()
    interceptor = source.index("ITW_CLASH_PlayerDemandNativeInterceptorsReady")
    first_bind = source.index("ITW_CLASH_Resupply_fnc_GoAmmoSuppBase = HAL_GoAmmoSupp;")
    assert interceptor < first_bind


def test_claim_breaks_hal_order_before_taking_busy():
    claim = fn("ITW_CLASH_Resupply_fnc_Claim")
    wait = claim.index("waitUntil")
    breaking = claim.index('_group setVariable ["Break",true]')
    take_busy = claim.index('_group setVariable ["Busy" + _var,true]')
    assert wait < breaking < take_busy
    # a stale claim never grabs Busy after it was released
    assert claim.index('"ITW_CLASH_ResupplyClaimed",false') < take_busy
    # never force Busy over a HAL order that refused to unwind, and say why
    assert "hal-order-did-not-unwind busy=%1 resting=%2 breaksSent=%3" in claim


def test_claim_closes_the_retask_race_seen_in_the_live_run():
    # Live RPT: G56 aborted with hal-order-did-not-unwind. Polling once a
    # second and requiring Break to be clear left a gap for re-tasking.
    claim = fn("ITW_CLASH_Resupply_fnc_Claim")
    assert "sleep 0.2;" in claim
    # Break is re-sent whenever a new order holds the group
    assert "if (!_free && {!(_group getVariable [\"Break\",false])}) then {" in claim
    # a Break nobody consumed is always cleared, never left to kill the next order
    assert claim.count('if (_breaks > 0) then {_group setVariable ["Break",false]};') == 3
    assert default("ITW_CLASH_ResupplyUnwindTimeout") >= 60


def test_player_tasked_groups_are_never_claimed():
    eligible = fn("ITW_CLASH_Resupply_fnc_Eligible")
    for job in ["Strike", "Recon", "Ammo", "Artillery"]:
        assert f'"ITW_CLASH_Player{job}JobId"' in eligible


def test_release_only_clears_busy_it_owns():
    release = fn("ITW_CLASH_Resupply_fnc_Release")
    owned = release.index('_claim get "busyOwned"')
    clear = release.index('_group setVariable ["Busy" + str _group,false]')
    assert owned < clear


def test_players_and_other_owners_are_never_claimed():
    eligible = fn("ITW_CLASH_Resupply_fnc_Eligible")
    for token in [
        "isPlayer",
        '"RydHQ_Friends"',
        '"ITW_CLASH_GTFO"',
        '"ITW_CLASH_CASEVAC_State"',
        '"ITW_CLASH_GroundMEDEVAC_State"',
        '"ITW_CLASH_ThunderRunActive"',
        '"RydHQ_AmmoDrop"',
    ]:
        assert token in eligible, token


def test_checkbook_bought_combat_assets_are_never_excluded():
    # Cross-file contract: RegisterAsset flags EVERY Checkbook purchase,
    # combat vehicles included. Any group flag it sets must not be an
    # exclusion in Eligible, or the replacement IFV CLASH just bought for HAL
    # is the one unit this system ignores when it runs dry.
    generation = text(MISSION / "ITW_CLASH_ForceGeneration.sqf")
    start = generation.index("ITW_CLASH_Generation_fnc_RegisterAsset = {")
    register = generation[start:generation.index("\n};", start)]
    group_flags = re.findall(r'_group setVariable \["([A-Za-z_]+)"', register)
    assert "ITW_CLASH_CheckbookAsset" in group_flags
    eligible = fn("ITW_CLASH_Resupply_fnc_Eligible")
    for flag in group_flags:
        assert f'"{flag}"' not in eligible, flag


def test_service_providers_stay_excluded_because_that_flag_is_logistics_only():
    lifecycle = text(MISSION / "ITW_CLASH_ServiceLifecycle.sqf")
    start = lifecycle.index("ITW_CLASH_Service_fnc_IsCapability = {")
    capabilities = lifecycle[start:lifecycle.index("\n};", start)]
    assert set(re.findall(r'"([A-Z_]+)"', capabilities)) == {
        "TRANSPORT", "LOGISTICS_AMMO", "LOGISTICS_FUEL", "LOGISTICS_REPAIR"
    }
    assert '"ITW_CLASH_ServiceAsset"' in fn("ITW_CLASH_Resupply_fnc_Eligible")


def test_a_group_carrying_other_troops_is_never_broken_mid_transport():
    eligible = fn("ITW_CLASH_Resupply_fnc_Eligible")
    assert "(crew _x) findIf {alive _x && {group _x != _group}} >= 0" in eligible


def test_unarmed_vehicles_never_read_as_out_of_ammo():
    armed = fn("ITW_CLASH_Resupply_fnc_IsArmed")
    assert '"RydHQ_NCVeh"' in armed
    needs = fn("ITW_CLASH_Resupply_fnc_Needs")
    assert "!someAmmo _x && {[_x,_hq] call ITW_CLASH_Resupply_fnc_IsArmed}" in needs


def test_riders_do_not_inherit_another_groups_transport():
    vehicles = fn("ITW_CLASH_Resupply_fnc_GroundVehicles")
    assert "ITW_CLASH_Resupply_fnc_TargetGroup) isEqualTo _group" in vehicles
    # but a crew that bailed out of its own vehicle still owns it
    assert "(crew _x) select {alive _x}) isEqualTo []" in vehicles


def test_immobile_vehicles_are_served_in_place_not_withdrawn():
    resolve = fn("ITW_CLASH_Resupply_fnc_StepResolve")
    immobile = resolve.index("fuel _x <= 0 || {!canMove _x}")
    order_move = resolve.index("ITW_CLASH_Resupply_fnc_OrderMove")
    assert immobile < order_move
    assert '_claim set ["rallySource","immobile"]' in resolve


def test_rally_prefers_a_live_crate_then_a_shared_rally():
    shared = fn("ITW_CLASH_Resupply_fnc_FindSharedRally")
    assert shared.index("ITW_CLASH_Resupply_fnc_CrateNear") < shared.index('"shared-rally"')
    resolve = fn("ITW_CLASH_Resupply_fnc_StepResolve")
    assert resolve.index("FindSharedRally") < resolve.index("ResolveRally")


def test_infantry_is_never_sent_a_ground_truck():
    dispatch = fn("ITW_CLASH_Resupply_fnc_Dispatch")
    assert '_vehNeeds = _needs - ["AMMO_INF"]' in dispatch
    assert "DispatchGround" in dispatch
    for call in re.findall(r"\[_claim,[^\]]*\] call ITW_CLASH_Resupply_fnc_DispatchGround", dispatch):
        assert "_vehNeeds" in call


def test_multi_kind_or_infantry_needs_prefer_air():
    dispatch = fn("ITW_CLASH_Resupply_fnc_Dispatch")
    assert '_preferAir = _hasInfantry || {count _vehNeeds >= 2}' in dispatch


def test_ground_ranking_uses_road_distance_and_minus_one_is_never_near():
    ground = fn("ITW_CLASH_Resupply_fnc_DispatchGround")
    assert "ITW_CLASH_RoadDistance_fnc_Calculate" in ground
    assert "if (_cost < 0 || {_cost > ITW_CLASH_ResupplyGroundMaxRoad})" in ground
    assert "if (!_lastResort) then {continue};" in ground


def test_delivery_reuses_hal_native_go_scripts():
    air = fn("ITW_CLASH_Resupply_fnc_DispatchAir")
    assert "true,_box,_hq,false" in air
    assert "HAL_GoAmmoSupp] call RYD_Spawn" in air
    assert '"AIR_DENIED"' in air
    ground = fn("ITW_CLASH_Resupply_fnc_DispatchGround")
    for native in ["HAL_GoAmmoSupp", "HAL_GoFuelSupp", "HAL_GoRepSupp"]:
        assert f"{native}] call RYD_Spawn" in ground


def test_checkbook_only_buys_missing_capability_not_busy_capability():
    request = fn("ITW_CLASH_Resupply_fnc_RequestCapacity")
    assert "ITW_CLASH_HALLogistics_fnc_Request" in request
    assert "ITW_CLASH_ResupplyBuyCooldown" in request
    assert request.count("call _noneViable") == 2  # air pool and ground pools
    # a heli in the ammo pool must never count as ground ammo capability
    assert '"RydHQ_AmmoSupportG",[]]) - (_hq getVariable ["RydHQ_AmmoDrop",[]])' in request


def test_viability_requires_the_service_vehicle_not_just_a_surviving_crew():
    # A destroyed ammo truck with a surviving crew is NOT capability.
    viable = fn("ITW_CLASH_Resupply_fnc_ProviderViable")
    for check in ["!isNull _veh", "alive _veh", "canMove _veh", "fuel _veh > 0", '"Helicopter"', '"LandVehicle"']:
        assert check in viable, check
    # ...but a busy provider still is: it will come back.
    assert "Busy" not in viable


def test_cleared_hal_roles_are_recorded_and_audited_after_release():
    clear = fn("ITW_CLASH_Resupply_fnc_ClearHALRoles")
    assert "_removed pushBack _x;" in clear
    assert clear.rstrip().endswith("_removed")
    claim = fn("ITW_CLASH_Resupply_fnc_Claim")
    assert '_claim set ["rolesCleared",_roles]' in claim
    release = fn("ITW_CLASH_Resupply_fnc_Release")
    assert "sleep ITW_CLASH_ResupplyRoleAuditDelay;" in release
    assert "ITW_CLASH_Resupply_fnc_CurrentHALRoles" in release
    assert '"role-audit"' in release


def test_claims_and_deliveries_are_capped():
    assert "ITW_CLASH_ResupplyMaxClaimsPerHQ" in fn("ITW_CLASH_Resupply_fnc_Detect")
    assert "ITW_CLASH_ResupplyMaxDeliveriesPerHQ" in fn("ITW_CLASH_Resupply_fnc_StepAtRally")


def test_failed_deliveries_retry_then_release_instead_of_stranding():
    await_step = fn("ITW_CLASH_Resupply_fnc_StepAwait")
    assert "ITW_CLASH_ResupplyMaxRetries" in await_step
    assert '"delivery-failed"] call ITW_CLASH_Resupply_fnc_Release' in await_step
    ticks = fn("ITW_CLASH_Resupply_fnc_TickClaims")
    assert "ITW_CLASH_ResupplyClaimTimeout" in ticks
    assert '"timeout"] call ITW_CLASH_Resupply_fnc_Release' in ticks


def test_crates_get_three_uses():
    assert default("ITW_CLASH_ResupplyCrateUses") == 3
    service = fn("ITW_CLASH_Resupply_fnc_ServiceAtCrate")
    assert "_uses = _uses - 1;" in service
    assert '"used up"] call ITW_CLASH_Resupply_fnc_DeleteCrate' in service


def test_crate_deletion_clears_isboxed_before_deleting():
    delete = fn("ITW_CLASH_Resupply_fnc_DeleteCrate")
    clear = delete.index('_x setVariable ["isBoxed",nil]')
    gone = delete.index("deleteVehicle _crate")
    assert clear < gone
    assert '"RydHQ_Boxed"' in delete


def test_crate_service_uses_hal_ace_magic_flags():
    apply = fn("ITW_CLASH_Resupply_fnc_ApplyService")
    for flag in ['"RydxHQ_MagicRearm"', '"RydxHQ_MagicRefuel"', '"RydxHQ_MagicRepair"']:
        assert flag in apply
    assert '"setVehicleAmmo"' in apply
    assert '"setFuel"' in apply
    assert "setDamage 0" in apply
    service = fn("ITW_CLASH_Resupply_fnc_ServiceAtCrate")
    assert "ITW_CLASH_Resupply_fnc_MagicFor" in service


def test_reserved_stock_packages_are_never_registered_as_crates():
    register = fn("ITW_CLASH_Resupply_fnc_RegisterCrate")
    assert '"RESERVED"' in register
    assert '"AVAILABLE_AT_REAR"' in register
    assert '"RydHQ_AmmoBoxes"' in register
    assert "isObjectHidden _crate" in register


def test_known_ground_single_kind_issue_is_flagged():
    header = resupply()[: resupply().index("*/")]
    assert "Known unsolved" in header
    assert "one truck at a time" in header


def test_init_loads_resupply_after_hal_logistics_and_player_demand():
    source = text(MISSION / "init.sqf")
    load = source.index('call compile preprocessFileLineNumbers "ITW_CLASH_Resupply.sqf"')
    assert source.index('"ITW_CLASH_HALLogistics.sqf"') < load
    assert source.index('"ITW_CLASH_ThunderRun.sqf"') < load
    assert source.index('"ITW_CLASH_PlayerDemandNativeInterceptors.sqf"') < load
    guard = source[source.rindex("if (", 0, load):load]
    assert "_halLogisticsLoaded isEqualTo true" in guard
