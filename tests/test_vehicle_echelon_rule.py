from pathlib import Path

MISSION = Path(__file__).resolve().parents[1] / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def function(source: str, name: str) -> str:
    start = source.index(name + " = {")
    return source[start:source.index("\n};", start)]


def dual() -> str:
    return mission("ITW_CLASH_DualHALCheckbook.sqf")


def test_rear_echelon_is_artillery_or_anything_that_can_kill_a_tank():
    rule = function(dual(), "ITW_CLASH_DualHAL_fnc_IsRearEchelon")
    assert '"artilleryScanner"' in rule
    assert "ITW_CLASH_PlayerArtilleryClasses" in rule
    assert "ITW_CLASH_EnemyArtilleryClasses" in rule
    # the spawned vehicle's real weapons, including dynamic-loadout pylons
    assert "magazinesAllTurrets _veh" in rule
    assert "getPylonMagazines _veh" in rule
    assert "ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo" in rule
    # never the ITW row type: ITW fills car-typed dual rows with APC/IFV classes
    assert "VEHINFO_TYPE" not in rule
    assert "ITW_VehDef" not in rule


def test_anti_armour_uses_the_engines_ammo_flag_on_ammo_and_submunition():
    ammo = function(dual(), "ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo")
    assert '"aiAmmoUsageFlags"' in ammo
    assert "(floor (_flags / 512)) mod 2 == 1" in ammo
    assert '"submunitionAmmo"' in ammo
    assert "isNumber _entry" in ammo  # numeric form
    assert 'splitString "+ "' in ammo  # "64 + 128 + 512" text form


def test_field_staging_sends_only_non_rear_echelon_forward():
    spawn = function(dual(), "ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn")
    forward = spawn.index("if !([_veh] call ITW_CLASH_DualHAL_fnc_IsRearEchelon) exitWith {")
    assert forward < spawn.index("ITW_CLASH_DualHAL_fnc_GetSupportSpawn")
    assert '"INTERSTITIAL"' not in spawn
    assert 'if (_air) then {"REAR_AIR"} else {"REAR"}' in spawn


def test_resolved_rear_node_is_returned_not_discarded():
    # Live run: 50/50 armor hand-offs logged field-rear-unresolved-native-origin
    # because exitWith inside `then {}` only left that block.
    spawn = function(dual(), "ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn")
    resolve = spawn[spawn.index("ITW_CLASH_Generation_fnc_Resolve"):]
    assert "_rear = [" in resolve
    assert "if (_rear isNotEqualTo []) exitWith {_rear};" in spawn
    inner = resolve[:resolve.index("if (_rear isNotEqualTo [])")]
    assert "exitWith" not in inner


def test_rear_echelon_never_fails_forward():
    spawn = function(dual(), "ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn")
    tail = spawn[spawn.index("if (_rear isNotEqualTo []) exitWith {_rear};"):]
    assert "GetSupportSpawn" not in tail
    assert '"field-rear-unresolved-native-origin"' in tail


def test_forward_fob_transports_reject_rear_echelon_vehicles():
    transport = function(dual(), "ITW_CLASH_Checkbook_fnc_RequestTransport")
    assert "[_veh] call ITW_CLASH_DualHAL_fnc_IsRearEchelon" in transport
    recon = function(
        mission("ITW_CLASH_ReconstitutionDispatchFix.sqf"),
        "ITW_AtkDispatchReconstitutionTransport",
    )
    assert "[_veh] call ITW_CLASH_DualHAL_fnc_IsRearEchelon" in recon
    assert "if (_availableSeats < _requiredSeats || {_rearEchelon}) then {" in recon


def test_ai_artillery_purchases_spawn_rear_not_mid_corridor():
    generation = mission("ITW_CLASH_ForceGeneration.sqf")
    provider = function(generation, "ITW_CLASH_Generation_fnc_Provider")
    assert '"INTERSTITIAL"' not in provider
    assert 'if (_mode == "AIR") then {"REAR_AIR"} else {"REAR"}' in provider
    fulfillment = generation[generation.index('scriptName "ITW_CLASH_AIArtilleryFulfillment";'):]
    assert '["profile","REAR"]' in fulfillment
    assert '["profile","INTERSTITIAL"]' not in fulfillment
