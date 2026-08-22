from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_rpt_binder_defects_are_removed_at_the_source():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    hardening = mission("ITW_CLASH_DualHALCheckbookHardening.sqf")

    request = dual.split("ITW_CLASH_Checkbook_fnc_RequestTransport =", 1)[1].split(
        "ITW_CLASH_Checkbook_fnc_HasCargoCapacity =", 1
    )[0]
    cargo = dual.split("ITW_CLASH_Checkbook_fnc_HasCargoCapacity =", 1)[1].split(
        "ITW_CLASH_Checkbook_fnc_CargoMode =", 1
    )[0]
    cargo_predicate = cargo.split("(_cargo findIf {", 1)[1].split("}) >= 0", 1)[0]

    assert 'scopeName "CLASH_CHECKBOOK_TRANSPORT"' not in request
    assert "breakOut" not in request
    assert "private _result = objNull;" in request
    assert "if (!isNull _result) then {continue};" in request
    assert "exitWith {false}" not in cargo_predicate
    assert 'isKindOf "Logic"' in dual
    assert 'isKindOf "VirtualMan_F"' in dual
    assert "NR6_fnc_HALcore =" not in dual
    assert "ITW_CLASH_DualHALHardening_fnc_RequestTransportBase" not in hardening


def test_impasse_exports_capability_pools_before_cleanup():
    arrays = mission("VehicleArrays.sqf")

    export = "ITW_CLASH_PlayerArtilleryClasses = +va_pArtyClasses;"
    complete = "VEHICLE_ARRAYS_COMPLETE = true;"
    cleanup = "va_eAmmoClasses = nil;"

    assert export in arrays
    assert "ITW_CLASH_EnemyArtilleryClasses = +va_eArtyClasses;" in arrays
    assert "ITW_CLASH_PlayerAmmoHeloClasses" in arrays
    assert "ITW_CLASH_EnemyAmmoHeloClasses" in arrays
    assert arrays.index(export) < arrays.index(complete) < arrays.index(cleanup)


def test_generation_resolver_is_symmetric_and_node_derived():
    generation = mission("ITW_CLASH_ForceGeneration.sqf")

    assert "ITW_CLASH_Generation_fnc_Resolve" in generation
    assert "ITW_ATTACK_LAND_F" in generation
    assert "ITW_ATTACK_LAND_E" in generation
    assert "ITW_ATTACK_AIR_F" in generation
    assert "ITW_ATTACK_AIR_E" in generation
    assert 'case "INTERSTITIAL"' in generation
    assert "ITW_CLASH_Generation_fnc_Interstitial" in generation
    assert "nearRoads 1000" in generation
    assert '"distinct-rear-forward-nodes-unavailable"' in generation
    assert '"source","itw-base-graph"' in generation
    assert "nearestLocation" not in generation
    assert "addWaypoint" not in generation


def test_ai_artillery_uses_checkbook_budget_and_hal_registration():
    generation = mission("ITW_CLASH_ForceGeneration.sqf")

    assert '["ARTILLERY","LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"]' in generation
    assert "ITW_CLASH_Generation_fnc_SelectBillingDefs" in generation
    assert "ITW_VEH_COUNT_INCR(_vehDef);" in generation
    assert "ITW_TICKET_REDUCE(_vehDef);" in generation
    assert 'setVariable ["ITW_VehDef",_vehDef]' in generation
    assert 'getVariable ["RydHQ_ArtG",[]]' in generation
    assert 'setVariable ["RydHQ_ArtG",_art]' in generation
    assert '"ARTILLERY",_hq,_requirements,"HIGH"' in generation
    assert "ITW_PlayerSide" in generation and "ITW_EnemySide" in generation
    assert "doArtilleryFire" not in generation
    assert "commandArtilleryFire" not in generation
    assert "setWaypoint" not in generation


def test_player_garage_artillery_is_pending_until_server_resolved_boarding():
    garage = mission("ITW_CLASH_PlayerGarageDeployment.sqf")
    client = mission("initPlayerLocal.sqf")

    assert '"ITW_CLASH_PlayerArtyDeploymentState","PENDING_PLAYER_BOARD"' in garage
    assert 'player addEventHandler ["GetInMan"' in garage
    assert "remoteExecutedOwner != _owner" in garage
    assert '"PLAYER_ARTILLERY","INTERSTITIAL"' in garage
    assert '"ITW_CLASH_PlayerArtyDeploymentState","DEPLOYED"' in garage
    assert "ITW_CLASH_DualHAL_fnc_RegisterGroup" not in garage
    assert "ITW_CLASH_fnc_RequestCapability" not in garage
    assert 'execVM "ITW_CLASH_PlayerGarageDeployment.sqf"' in client


def test_hal_logistics_wraps_native_demand_but_not_tactical_execution():
    logistics = mission("ITW_CLASH_HALLogistics.sqf")
    generation = mission("ITW_CLASH_ForceGeneration.sqf")

    assert "ITW_CLASH_HALLogistics_fnc_NativeSuppAmmo = HAL_SuppAmmo;" in logistics
    assert "ITW_CLASH_HALLogistics_fnc_NativeSuppFuel = HAL_SuppFuel;" in logistics
    assert "ITW_CLASH_HALLogistics_fnc_NativeSuppRep = HAL_SuppRep;" in logistics
    assert 'getVariable ["RydHQ_Hollow",[]]' in logistics
    assert 'getVariable ["RydHQ_Dried",[]]' in logistics
    assert 'getVariable ["RydHQ_damaged",[]]' in logistics
    assert '"LOGISTICS_AMMO","AIR"' in logistics
    assert '"LOGISTICS_AMMO","GROUND"' in logistics
    assert '"LOGISTICS_FUEL","GROUND"' in logistics
    assert '"LOGISTICS_REPAIR","GROUND"' in logistics
    assert 'getVariable ["RydHQ_AmmoDrop",[]]' in generation
    assert 'getVariable ["RydHQ_Support",[]]' in generation
    assert "addWaypoint" not in logistics
    assert "doMove" not in logistics
    assert "moveTo" not in logistics


def test_certification_harness_covers_artillery_sof_and_interdiction():
    cert = mission("ITW_CLASH_ArtilleryCertification.sqf")
    init = mission("init.sqf")

    assert 'missionNamespace getVariable ["ITW_CLASH_CertificationMode",false]' in cert
    assert '"AI_ARTILLERY_FULFILLED_"' in cert
    assert '"ARTILLERY_OUTSIDE_NODE_SANCTUARIES_"' in cert
    assert '"ENEMY_ARTILLERY_RECOGNIZED_"' in cert
    assert '"SOF_INTERDICTION_ELIGIBLE_"' in cert
    assert "CLASH CERT | COMPLETE" in cert
    assert 'execVM "ITW_CLASH_ArtilleryCertification.sqf"' in init
