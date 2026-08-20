from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_preinit_defers_and_installs_physical_movement_patch():
    preinit = text("preInit.sqf")
    assert '"ITW_AtkSafeMove"' in preinit
    assert '"ITW_AtkAddVehicle"' in preinit
    assert 'ITW_CLASH_PhysicalMovementPreInit.sqf' in preinit
    assert 'ITW_CLASH_PhysicalMovementPreInitReady = _physicalMovementFixed;' in preinit
    assert 'physical-movement-fallback' in preinit
    assert 'private _physicalMovementFixed = false;' in preinit


def test_live_safe_move_is_physical_and_baseline_remains_fail_open():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    assert 'missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]' in source
    assert '_this call ITW_CLASH_AtkSafeMove_Baseline' in source
    assert '_group move _destination;' in source
    assert '"strategic-teleport-suppressed"' in source

    live_block = source[source.index('ITW_AtkSafeMove = {'):source.index('ITW_AtkAddVehicle = {')]
    assert 'setPosATL' not in live_block
    assert 'setPosASL' not in live_block


def test_headless_owned_groups_use_physical_helper_not_remote_baseline_safemove():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    assert 'ITW_CLASH_PhysicalMovementPreInitVersion = 2;' in source
    assert 'ITW_CLASH_fnc_PhysicalMoveLocal = {' in source
    assert '["ITW_CLASH_fnc_PhysicalMoveLocal"] call SKL_fnc_CompileFinal;' in source
    assert '[[ _group,_destination],"ITW_AtkSafeMove"' not in source
    assert '"ITW_CLASH_fnc_PhysicalMoveLocal",_group] call ITW_FncRemoteLocalGroup' in source
    assert 'hcSafe=true' in source


def test_live_vehicle_add_disables_initial_relocation():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    add_block = source[source.index('ITW_AtkAddVehicle = {'):source.index('isNil {', source.index('ITW_AtkAddVehicle = {'))]
    assert '_args set [2,false];' in add_block
    assert '_args pushBack false;' in add_block
    assert '"vehicle-teleport-suppressed"' in add_block
    assert '_args call ITW_CLASH_AtkAddVehicle_Baseline' in add_block


def test_physical_movement_patch_finalizes_only_its_deferred_surface():
    source = text("ITW_CLASH_PhysicalMovementPreInit.sqf")
    assert 'ITW_CLASH_DeferredFinalizers' in source
    assert '["ITW_AtkSafeMove","ITW_AtkAddVehicle"]' in source
    assert '["ITW_AtkSafeMove"] call SKL_fnc_CompileFinal' in source
    assert '["ITW_AtkAddVehicle"] call SKL_fnc_CompileFinal' in source
    assert 'strategicTeleport=false' in source


def test_init_confirms_no_teleport_preinit_authority():
    init = text("init.sqf")
    assert 'ITW_CLASH_PhysicalMovementPreInitReady' in init
    assert 'physical-movement-preinit-authority-confirmed' in init
    assert 'strategicTeleport=false' in init
