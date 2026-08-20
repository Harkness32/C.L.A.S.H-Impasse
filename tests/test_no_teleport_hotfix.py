from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_preinit_defers_only_midbattle_moveup_surface():
    preinit = text("preInit.sqf")
    assert '"ITW_AtkInfantryMoveUp"' in preinit
    assert 'ITW_CLASH_PhysicalMovementPreInit.sqf' in preinit
    assert 'ITW_CLASH_PhysicalMovementPreInitReady = _physicalMovementFixed;' in preinit
    assert 'physical-movement-fallback' in preinit
    assert 'private _physicalMovementFixed = false;' in preinit

    deferred_block = preinit[
        preinit.index("ITW_CLASH_DeferredFinalizers = ["):
        preinit.index("];", preinit.index("ITW_CLASH_DeferredFinalizers = ["))
    ]
    assert '"ITW_AtkSafeMove"' not in deferred_block
    assert '"ITW_AtkAddVehicle"' not in deferred_block


def test_initial_staging_remains_baseline_impasse():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    assert 'ITW_CLASH_PhysicalMovementPreInitVersion = 4;' in source
    assert 'ITW_CLASH_AtkInfantryMoveUp_Baseline = ITW_AtkInfantryMoveUp;' in source
    assert 'ITW_AtkSafeMove =' not in source
    assert 'ITW_AtkAddVehicle =' not in source
    assert 'initialStaging=true' in source
    assert 'safeMoveBaseline=true' in source
    assert 'addVehicleBaseline=true' in source


def test_midbattle_moveup_becomes_physical_waypoint():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    assert 'ITW_CLASH_fnc_PhysicalMoveUpLocal = {' in source
    assert '["ITW_CLASH_fnc_PhysicalMoveUpLocal"] call SKL_fnc_CompileFinal;' in source
    helper = source[
        source.index('ITW_CLASH_fnc_PhysicalMoveUpLocal = {'):
        source.index('["ITW_CLASH_fnc_PhysicalMoveUpLocal"] call SKL_fnc_CompileFinal;')
    ]
    assert 'addWaypoint' in helper
    assert 'setWaypointType "MOVE"' in helper
    assert 'setPosATL' not in helper
    assert 'setPosASL' not in helper
    assert 'ITW_AtkSafeMove' not in helper


def test_moveup_override_is_mode2_fail_open_and_hc_safe():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    assert 'ITW_CLASH_fnc_PhysicalMovementActive = {' in source
    assert 'missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]' in source
    assert 'missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]' in source
    assert 'missionNamespace getVariable ["ITW_ParamCLASHObserver",0]) == 2' in source
    assert '_this call ITW_CLASH_AtkInfantryMoveUp_Baseline' in source
    assert '"ITW_CLASH_fnc_PhysicalMoveUpLocal",_group] call ITW_FncRemoteLocalGroup' in source
    assert '"strategic-teleport-suppressed"' in source
    assert '"infantry-move-up"' in source
    assert 'failOpen=true' in source


def test_recovery_and_reconstitution_states_are_excluded_from_moveup_rewrite():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    assert 'ITW_CLASH_Managed' in source
    assert 'ITW_CLASH_Withdrawing' in source
    assert 'ITW_CLASH_ReconstitutionTransit' in source


def test_physical_movement_patch_finalizes_only_moveup():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    assert 'ITW_CLASH_DeferredFinalizers' in source
    assert '_deferred - ["ITW_AtkInfantryMoveUp"]' in source
    assert '["ITW_AtkInfantryMoveUp"] call SKL_fnc_CompileFinal' in source
    assert '["ITW_AtkSafeMove"] call SKL_fnc_CompileFinal' not in source
    assert '["ITW_AtkAddVehicle"] call SKL_fnc_CompileFinal' not in source
    assert 'midBattleMoveUpTeleport=false' in source


def test_init_confirms_staging_safe_movement_authority():
    init = text("init.sqf")
    assert 'ITW_CLASH_PhysicalMovementPreInitReady' in init
    assert 'physical-movement-preinit-authority-confirmed' in init
    assert 'midBattleMoveUpTeleport=false initialStaging=true' in init
