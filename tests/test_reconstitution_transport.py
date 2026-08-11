from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def function_block(source: str, name: str, next_name: str) -> str:
    start = source.index(f"{name} = {{")
    end = source.index(f"{next_name} = {{", start)
    return source[start:end]


def test_reconstitution_is_created_at_support_corridor_and_queued_for_transit():
    source = text("ITW_Attack.sqf")
    start = source.index("//// C.L.A.S.H. cap-exempt squad reconstitution ////")
    end = source.index("private _spawnRate =", start)
    block = source[start:end]
    assert "ITW_CLASH_fnc_GetSupportCorridorSpawn" in block
    assert "ITW_OBJ_V_SPAWN" in block
    assert "ITW_AtkBeginReconstitutionTransit" in block
    assert "ITW_CLASH_fnc_AcknowledgeReconstitution" not in block


def test_transit_dispatch_preserves_whole_group():
    source = text("ITW_Attack.sqf")
    block = function_block(source, "ITW_AtkDispatchReconstitutionTransport", "ITW_AtkBeginReconstitutionTransit")
    assert 'private _availableSeats = _veh emptyPositions "";' in block
    assert "_availableSeats < _requiredSeats" in block
    assert "forEach _members" in block
    assert "joinSilent" not in block
    assert "_vehInfo,false,false" in block


def test_transit_group_is_hidden_from_normal_infantry_manager():
    source = text("ITW_Attack.sqf")
    block = function_block(source, "ITW_AtkGetInfantryGroups", "ITW_AtkInfantryManager")
    assert 'ITW_CLASH_ReconstitutionTransit' in block


def test_forced_transit_objective_is_honored_by_enemy_vectors():
    source = text("ITW_Enemy.sqf")
    block = function_block(source, "ITW_EnemyAttackVectors", "ITW_EnemyGetAssignedGroups")
    assert '"ITW_CLASH_TransitObjective"' in block
    assert "_forcedObjective in _objIndexes" in block


def test_runtime_acknowledgement_no_longer_relocates_squad():
    source = text("ITW_CLASH_RuntimePatch.sqf")
    start = source.index("ITW_CLASH_fnc_AcknowledgeReconstitution = {")
    end = source.index("// The four public overrides", start)
    block = source[start:end]
    assert "setPosATL" not in block
    assert "ITW_CLASH_fnc_AcknowledgeReconstitution_V6Base" in block
    assert "reconstitution-handoff" in block


def test_long_corridor_prefers_air_but_walk_is_only_timeout_fallback():
    source = text("ITW_Attack.sqf")
    dispatch = function_block(source, "ITW_AtkDispatchReconstitutionTransport", "ITW_AtkBeginReconstitutionTransit")
    manager = source[source.index("ITW_AtkReconstitutionTransitManager = {"):source.index("#define WEAPONLESS_FACTIONS")]
    assert "_routeDistance > 2500" in dispatch
    assert '"air-preferred"' in dispatch
    assert "ITW_AtkReconstitutionTransportWait" in manager
    assert '"reconstitution-transport-fallback-walk"' in manager


def test_air_only_corridor_requires_air_transport_and_never_falls_back_to_walk():
    source = text("ITW_Attack.sqf")
    dispatch = function_block(source, "ITW_AtkDispatchReconstitutionTransport", "ITW_AtkBeginReconstitutionTransit")
    manager = source[source.index("ITW_AtkReconstitutionTransitManager = {"):source.index("#define WEAPONLESS_FACTIONS")]
    assert "private _ordered = if (_airRoute) then" in dispatch
    assert "+_preferred" in dispatch
    assert "private _airOnly = _corridor isNotEqualTo []" in manager
    assert "if (!_airOnly && {" in manager
