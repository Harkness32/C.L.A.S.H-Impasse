from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def ground_text() -> str:
    return "\n".join([
        text("ITW_CLASH_GroundMEDEVAC.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_Extraction.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_Manager.sqf"),
    ])


def test_ground_medevac_is_wired_after_casevac_stack():
    init = text("init.sqf")
    assert 'execVM "ITW_CLASH_CASEVAC.sqf"' in init
    assert 'execVM "ITW_CLASH_CASEVAC_AirOpsFix.sqf"' in init
    assert 'execVM "ITW_CLASH_CASEVAC_LZPadFix.sqf"' in init
    assert 'execVM "ITW_CLASH_GroundMEDEVAC.sqf"' in init
    assert 'execVM "ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf"' in init
    assert init.index('execVM "ITW_CLASH_CASEVAC.sqf"') < init.index('execVM "ITW_CLASH_GroundMEDEVAC.sqf"')
    assert init.index('execVM "ITW_CLASH_GroundMEDEVAC.sqf"') < init.index('execVM "ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf"')
    main = text("ITW_CLASH_GroundMEDEVAC.sqf")
    assert 'ITW_CLASH_GroundMEDEVAC_Extraction.sqf' in main
    assert 'ITW_CLASH_GroundMEDEVAC_Manager.sqf' in main


def test_ground_medevac_doctrine_gates_are_explicit():
    source = ground_text()
    expected = [
        "ITW_CLASH_GroundMEDEVAC_MaxConcurrent = 2;",
        "ITW_CLASH_GroundMEDEVAC_MinWithdrawalTime = 60;",
        "ITW_CLASH_GroundMEDEVAC_MinDisengageDistance = 500;",
        "ITW_CLASH_GroundMEDEVAC_EnemyClearance = 700;",
        "ITW_CLASH_GroundMEDEVAC_InboundAbortClearance = 500;",
        "ITW_CLASH_GroundMEDEVAC_ObjectiveClearance = 500;",
        "ITW_CLASH_GroundMEDEVAC_MinEgressDistance = 400;",
        "ITW_CLASH_GroundMEDEVAC_MaxPreferredEgressDistance = 3500;",
        "ITW_CLASH_GroundMEDEVAC_RallyOffset = 30;",
    ]
    for token in expected:
        assert token in source


def test_ground_medevac_requires_forward_fob_land_spawn_and_roadside_pickup():
    source = ground_text()
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in source
    assert 'surfaceIsWater _spawnPos' in source
    assert 'ITW_OBJ_V_SPAWN' in source
    assert "nearRoads ITW_CLASH_GroundMEDEVAC_RoadSearchRadius" in source
    assert "BIS_fnc_nearestPosition" in source
    assert "ITW_CLASH_GroundMEDEVAC_RallyOffset" in source
    assert '_wp setWaypointCompletionRadius 15;' in source
    assert "forceFollowRoad true" in source


def test_ground_medevac_only_uses_active_faction_car_or_apc_pool_and_bypasses_count_cap():
    source = ground_text()
    assert "ITW_AtkReconstitutionTransportContext" in source
    assert "(_transport + _dualVeh) select" in source
    assert "[ITW_TYPE_VEH_CAR,ITW_TYPE_VEH_APC]" in source
    assert "ITW_VEH_REQD_TICKETS" in source
    assert "ITW_VEH_CURR_TICKETS" in source
    candidate_block = source[source.index("private _candidates ="):source.index("if (_candidates isEqualTo [])")]
    assert "ITW_VEH_MAX" not in candidate_block
    assert "ITW_VEH_COUNT_INCR" in source
    assert "ITW_TICKET_REDUCE" in source
    assert '"cap-bypass"' in source


def test_ground_medevac_vehicle_policy_routes_by_survivor_requirement_not_faction_classnames():
    policy = text("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf")
    assert "ITW_CLASH_GroundMEDEVAC_LightMaxSurvivors = 3;" in policy
    assert "ITW_CLASH_GroundMEDEVAC_MediumMaxSurvivors = 6;" in policy
    assert 'exitWith {"light"}' in policy
    assert 'exitWith {"medium"}' in policy
    assert '"heavy"' in policy
    assert 'getNumber (_cfg >> "transportSoldier")' in policy
    assert "private _excessSeats" in policy
    assert "_excessSeats * 20" in policy
    assert 'getNumber (_cfg >> "maxSpeed")' in policy
    assert "ITW_TYPE_VEH_APC" in policy
    assert "ITW_VEH_ROLE_TRANSPORT" in policy
    for hardcoded in ["O_LSV_02_unarmed_F", "O_Truck_03_medical_F", "B_LSV", "rhs_"]:
        assert hardcoded not in policy


def test_ground_medevac_policy_keeps_medical_as_soft_preference_not_absolute_first_choice():
    policy = text("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf")
    assert 'find "ambulance"' in policy
    assert 'find "medical"' in policy
    assert 'find "medevac"' in policy
    assert "if (_medical) then {_score = _score - 12};" in policy
    assert "_medical + _pureCars" not in policy
    assert "ITW_CLASH_GroundMEDEVAC_MedicalClassOverrides" in policy


def test_ground_medevac_policy_has_future_faction_metadata_hooks_without_bypassing_requirements():
    policy = text("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf")
    assert "ITW_CLASH_GroundMEDEVAC_ClassScoreAdjustments" in policy
    assert "ITW_CLASH_GroundMEDEVAC_MedicalClassOverrides" in policy
    assert "_manualAdjustment" in policy
    assert "_score = _score + _manualAdjustment" in policy
    # Explicit faction hints never replace the live Impasse ticket/capacity gates.
    assert "(_x#ITW_VEH_REQD_TICKETS) <= (_x#ITW_VEH_CURR_TICKETS)" in policy
    assert '_veh emptyPositions "cargo"' in policy
    assert "if (_actualCapacity < _seatCount)" in policy


def test_ground_medevac_policy_spawns_exact_ranked_variant_but_accounts_original_definition():
    policy = text("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf")
    assert "private _spawnDef = +_vehDef;" in policy
    assert "_spawnDef set [ITW_VEH_CLASSES,[_variant]];" in policy
    assert "_spawnDef,_crewTypes,_unitTypes,_side,_spawnPos" in policy
    assert "ITW_VEH_COUNT_INCR(_vehDef);" in policy
    assert 'ITW_TICKET_REDUCE(_vehDef);' in policy
    assert '_veh setVariable ["ITW_VehDef",_vehDef];' in policy


def test_ground_medevac_policy_is_fail_open_to_baseline_selector():
    policy = text("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf")
    assert "ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle_Base" in policy
    assert '"vehicle-policy-fallback"' in policy
    assert '"no-ranked-variant"' in policy
    assert '"ranked-spawns-failed"' in policy


def test_ground_medevac_vehicle_selection_telemetry_exposes_requirement_and_fit():
    policy = text("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf")
    assert '"vehicle-selected"' in policy
    assert '"spawn-selected"' in policy
    assert "_profile,_seatCount,_actualCapacity,_estimatedCapacity" in policy
    assert "_vehDef#ITW_VEH_TYPE,_vehDef#ITW_VEH_ROLE" in policy
    assert "routing=capability-score" in policy
    assert "factionPool=true" in policy


def test_ground_pickup_is_physical_not_teleported():
    source = ground_text()
    assert "assignAsCargo" in source
    assert "orderGetIn true" in source
    assert "moveInAny" not in source
    assert "moveInCargo" not in source
    assert "setPosATL" not in source


def test_ground_vehicle_order_replaces_pickup_driver_stop_with_explicit_move():
    source = text("ITW_CLASH_GroundMEDEVAC.sqf")
    order_at = source.index("ITW_CLASH_GroundMEDEVAC_fnc_OrderVehicle")
    order_block = source[order_at:source.index("ITW_CLASH_GroundMEDEVAC_fnc_OrderRally")]
    assert "private _driver = driver _veh;" in order_block
    assert "_driver doMove _position;" in order_block
    assert "group waypoint alone" in order_block


def test_ground_medevac_never_owns_reconstitution_credit():
    source = ground_text()
    assert "ITW_AtkQueueReconstitution" not in source
    assert "ITW_CLASH_Withdrawals getOrDefault" in source
    assert "_veh distance2D _returnPos <= 140" in source
    assert "rear-absorption-timeout" in source


def test_ground_and_air_are_mutually_exclusive_but_air_reopens_on_ground_deferral():
    source = ground_text()
    assert "ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase" in source
    assert 'ITW_CLASH_CASEVAC_State","ground-inbound"' in source
    assert 'ITW_CLASH_CASEVAC_State","ground-rtb"' in source
    assert "air-deferred-ground-preferred" in source
    assert "ITW_CLASH_GroundMEDEVAC_AirFallbackDelay = 30;" in source
    assert '"no-ground-vehicle-available"' in source


def test_ground_failure_restores_physical_foot_withdrawal():
    source = ground_text()
    assert 'call ITW_CLASH_fnc_OrderWithdrawal;' in source
    assert 'action ["GetOut",_veh]' in source
    assert "_dismountDeadline = time + 8" in source
    assert "moveOut _" not in source
    assert "ITW_CLASH_GroundMEDEVAC_RetryCooldown = 120;" in source

def test_ground_medevac_claims_both_arbitration_gates_before_spawn_can_yield():
    main = text("ITW_CLASH_GroundMEDEVAC.sqf")
    manager = text("ITW_CLASH_GroundMEDEVAC_Manager.sqf")
    dispatch = manager.split("ITW_CLASH_GroundMEDEVAC_fnc_Dispatch = {", 1)[1].split(
        "// Air/ground arbitration.", 1
    )[0]

    assert "ITW_CLASH_GroundMEDEVAC_Version = 3;" in main
    ground_claim = '_group setVariable ["ITW_CLASH_GroundMEDEVAC_State","ground-spawning"];'
    air_gate = '_group setVariable ["ITW_CLASH_CASEVAC_State","ground-spawning"];'
    spawn = "] call ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle;"
    assert dispatch.index(ground_claim) < dispatch.index(spawn)
    assert dispatch.index(air_gate) < dispatch.index(spawn)
    assert '_group setVariable ["ITW_CLASH_GroundMEDEVAC_State",nil];' in dispatch
    assert '_group setVariable ["ITW_CLASH_CASEVAC_State",nil];' in dispatch


def test_ground_medevac_uses_shared_modular_capacity_estimator():
    policy = text("ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf")
    assert "ITW_CLASH_GroundMEDEVAC_VehiclePolicyVersion = 3;" in policy
    assert "ITW_CLASH_ServiceCapacity_fnc_ConfigCargoSeats" in policy
    assert "sharedCapacityEstimator=true" in policy


def test_ground_medevac_fast_tracks_shattered_remnants_but_keeps_safety_gates():
    manager = text("ITW_CLASH_GroundMEDEVAC_Manager.sqf")
    assert 'getVariable ["ITW_CLASH_RemnantEvac",false]' in manager
    assert "ITW_CLASH_RemnantEvacMinWithdrawalTime" in manager
    assert "if (!_remnantEvac && {" in manager
    assert "_moved < ITW_CLASH_GroundMEDEVAC_MinDisengageDistance" in manager
    assert "_enemyDistance < ITW_CLASH_GroundMEDEVAC_EnemyClearance" in manager
    assert "_objectiveClearance < ITW_CLASH_GroundMEDEVAC_ObjectiveClearance" in manager
