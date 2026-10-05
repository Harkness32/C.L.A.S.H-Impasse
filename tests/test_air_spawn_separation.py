from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def attack() -> str:
    return (MISSION / "ITW_Attack.sqf").read_text(encoding="utf-8", errors="replace")


def spawn_veh() -> str:
    source = attack()
    start = source.index("ITW_AtkSpawnVeh = {")
    return source[start:source.index("\n};", start)]


def air_branch() -> str:
    body = spawn_veh()
    start = body.index('    if (_vehType isKindOf "Air") then {')
    return body[start:body.index("\n    } else {", start)]


def test_aircraft_take_a_ring_slot_before_crew_or_vehicle_is_created():
    # CLASH spawners (Checkbook, service assets, CASEVAC, transports,
    # reconstitution) all pass one fixed base point and never run Impasse's
    # offsetter, so aircraft created together were stacked and collided.
    branch = air_branch()
    slot = branch.index("call ITW_AtkSpawnOffsetter")
    assert slot < branch.index("ITW_AtkUnitToGroup")
    assert slot < branch.index('"FLY"')
    assert "_spawnPt = _airSlot" in branch


def test_planes_and_helis_use_their_own_ring_heights():
    branch = air_branch()
    assert 'if (_vehType isKindOf "Plane") then {ITW_TYPE_VEH_AIRPLANE} else {ITW_TYPE_VEH_HELI}' in branch


def test_the_air_ring_rotates_on_every_call():
    source = attack()
    start = source.index("ITW_AtkSpawnOffsetter = {")
    offsetter = source[start:source.index("\n};", start)]
    air_start = offsetter.index("    if (ITW_VEH_IS_AIR(_type)) then {")
    air = offsetter[air_start:offsetter.index("\n    } else {", air_start)]
    assert "ITW_SpawnPlaneOffset = (_offset+1) mod 16;" in air
    assert offsetter.rstrip().endswith("[_newPos,_newDir]")


def land_branch() -> str:
    body = spawn_veh()
    marker = '    } else {\n        private _landSpawn = +_spawnPt;'
    start = body.index(marker)
    end = body.index("\n\n    if (!_crewFailed", start)
    return body[start:end]


def test_ground_vehicle_spawns_rotate_around_the_staging_point():
    branch = land_branch()
    assert 'ITW_CLASH_GroundSpawnOffsets = createHashMap' in branch
    assert '(_slot + 1) mod 12' in branch
    assert 'if (_slot < 6) then {20} else {40}' in branch
    assert '(_slot mod 6) * 60' in branch


def test_ground_vehicle_spawn_uses_empty_position_and_does_not_move_ships():
    branch = land_branch()
    assert 'if (_vehType isKindOf "LandVehicle") then {' in branch
    assert 'findEmptyPosition [0,12,_vehType]' in branch
    assert 'surfaceIsWater _candidate' in branch
