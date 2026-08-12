from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_enemy_callback_finalizer_is_deferred_until_native_archetype_patch():
    pre = text("preInit.sqf")
    enemy_compile = 'preprocessFileLineNumbers "ITW_Enemy.sqf"'
    patch_compile = 'preprocessFileLineNumbers "ITW_CLASH_SpawnArchetypePreInit.sqf"'
    assert '"ITW_EnemyGroupCallback"' in pre
    assert pre.index('ITW_CLASH_DeferredFinalizers = [') < pre.index(enemy_compile)
    assert pre.index(enemy_compile) < pre.index(patch_compile)
    assert "ITW_CLASH_SpawnArchetypeAuthorityReady" in pre


def test_native_enemy_callback_snapshots_immutable_spawn_template():
    source = text("ITW_CLASH_SpawnArchetypePreInit.sqf")
    assert "ITW_CLASH_SpawnArchetypePreInitVersion = 1;" in source
    assert 'ITW_EnemyGroupCallback = {' in source
    assert '_members apply {toLowerANSI typeOf _x}' in source
    assert '"ITW_CLASH_SpawnArchetype"' in source
    assert '"ITW_CLASH_SpawnStrength"' in source
    assert '"ITW_CLASH_SpawnArchetypeCapturedAt"' in source
    assert 'if ((_group getVariable ["ITW_CLASH_Archetype",[]]) isEqualTo []) then {' in source
    assert '_group setVariable ["ITW_CLASH_Archetype",+_spawnArchetype];' in source


def test_native_callback_preserves_impasse_callback_contract():
    source = text("ITW_CLASH_SpawnArchetypePreInit.sqf")
    assert "ITW_EnemyGroups pushBack _group;" in source
    assert '["enemy-group-callback",_group] call ITW_CLASH_fnc_ObserveGroup;' in source
    remove_at = source.index('_deferred = _deferred - ["ITW_EnemyGroupCallback"]')
    finalize_at = source.index('["ITW_EnemyGroupCallback"] call SKL_fnc_CompileFinal;')
    assert remove_at < finalize_at
    assert "spawn-archetype-preinit-ready" in source


def test_init_reports_native_spawn_template_authority():
    init = text("init.sqf")
    assert "spawn-archetype-authority-confirmed" in init
    assert "native enemy callback active" in init
