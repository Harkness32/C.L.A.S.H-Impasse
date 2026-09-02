from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_native_faction_pools_drop_blank_and_non_man_classes():
    attack = text("ITW_Attack.sqf")
    setup = attack.split("private _side      =", 1)[1].split("private _squadNames", 1)[0]
    assert "private _validManClass = {" in setup
    assert '_class isNotEqualTo ""' in setup
    assert 'isClass (configFile >> "CfgVehicles" >> _class)' in setup
    assert '_class isKindOf "CAManBase"' in setup
    assert "_rawUnitTypes" in setup
    assert "_rawCrewTypes" in setup
    assert '"CLASH SPAWN | sanitized-faction-unit-pool' in setup


def test_unit_creation_rejects_bad_pool_before_global_create_semaphore():
    attack = text("ITW_Attack.sqf")
    unit = attack.split("ITW_AtkUnitToGroup = {", 1)[1].split("ITW_AtkVehicleSpawner = {", 1)[0]
    assert unit.index('"CLASH SPAWN | rejected-invalid-unit-pool') < unit.index("SEM_LOCK(ITW_AtkUnitCreateSem)")
    assert '_x isNotEqualTo ""' in unit
    assert 'isClass (configFile >> "CfgVehicles" >> _x)' in unit


def test_vehicle_spawn_validates_class_and_never_inherits_blank_cfg_crew():
    attack = text("ITW_Attack.sqf")
    spawn = attack.split("ITW_AtkSpawnVeh = {", 1)[1].split("ITW_AtkVehRemoveMagazines = {", 1)[0]
    assert '"rejected-empty-vehicle-type"' in spawn
    assert '"rejected-missing-vehicle-class"' in spawn
    assert "if !(isClass _vehCfg)" in spawn
    assert '_vehCrew isNotEqualTo ""' in spawn
    assert '"rejected-no-valid-crew-pool"' in spawn


def test_vehicle_and_crew_spawn_is_atomic():
    attack = text("ITW_Attack.sqf")
    spawn = attack.split("ITW_AtkSpawnVeh = {", 1)[1].split("ITW_AtkVehRemoveMagazines = {", 1)[0]
    assert "private _crewFailed = false;" in spawn
    assert '"vehicle-crew-transaction-aborted"' in spawn
    assert "_expectedCrewCount > 0" in spawn
    assert "{deleteVehicle _x} forEach units _crewGrp;" in spawn
    assert "deleteVehicle _veh" in spawn
    assert "_veh = objNull;" in spawn


def test_checkbook_crew_resolution_uses_same_man_class_sanitation():
    checkbook = text("ITW_CLASH_DualHALCheckbook.sqf")
    block = checkbook.split("ITW_CLASH_Checkbook_fnc_GetCrewTypes = {", 1)[1].split(
        "ITW_CLASH_Checkbook_fnc_RegisterTransport = {", 1
    )[0]
    assert "_rawUnitTypes" in block
    assert "_rawCrewTypes" in block
    assert '_class isNotEqualTo ""' in block
    assert '_class isKindOf "CAManBase"' in block
    assert '"crew-pool-sanitized"' in block


def test_recovery_walk_cutoff_is_400m_for_ground_and_air():
    ground = text("ITW_CLASH_GroundMEDEVAC.sqf")
    air = text("ITW_CLASH_CASEVAC.sqf")
    assert "ITW_CLASH_GroundMEDEVAC_MinEgressDistance = 400;" in ground
    assert "ITW_CLASH_CASEVAC_MinEgressDistance = 400;" in air
    assert "ITW_CLASH_GroundMEDEVAC_EnemyClearance = 700;" in ground
    assert "ITW_CLASH_CASEVAC_EnemyClearance = 650;" in air
