from pathlib import Path

MISSION = Path(__file__).resolve().parents[1] / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def function(source: str, name: str) -> str:
    start = source.index(name + " = {")
    return source[start:source.index("\n};", start)]


def test_handed_off_units_never_reach_the_impasse_writer():
    # Live run 2026-09-26: every handed-off vehicle got Impasse's
    # search-and-destroy order 2 s after staging, because `if (_handled)
    # exitWith` sat inside a `then` block and fell through to the base.
    bridge = mission("ITW_CLASH_DualHALCheckbookPreInit.sqf")
    assert "ITW_CLASH_DualHALCheckbookPreInitVersion = 2;" in bridge
    for name, base in [
        ("ITW_AtkAddVehicle", "ITW_CLASH_DualHAL_fnc_AtkAddVehicleBase"),
        ("ITW_AtkEngageInfantry", "ITW_CLASH_DualHAL_fnc_AtkEngageInfantryBase"),
        ("ITW_AtkEngageVehicle", "ITW_CLASH_DualHAL_fnc_AtkEngageVehicleBase"),
    ]:
        body = function(bridge, name)
        assert "private _handled = false;" in body, name
        # the exit sits at function scope (4-space indent), before the base
        exit = body.index("\n    if (_handled) exitWith {")
        assert exit < body.index(f"_this call {base}"), name
        assert "\n            if (_handled) exitWith" not in body, name
        assert "\n        if (_handled) exitWith" not in body, name


def test_transport_disarm_still_runs_on_a_handled_add():
    body = function(mission("ITW_CLASH_DualHALCheckbookPreInit.sqf"), "ITW_AtkAddVehicle")
    handled = body[body.index("\n    if (_handled) exitWith {"):body.index("_this call")]
    assert '[_veh] remoteExec ["ITW_AtkVehRemoveMagazines",_veh];' in handled
    assert "ITW_VEH_ROLE_TRANSPORT" in handled


def test_unarmed_vehicles_join_hals_noncombat_cargo_list():
    # HAL sent 3 of 4 ammo runs to unarmed Prowlers: its autofill counts only
    # transportSoldier seats as cargo, and Prowler passengers sit in FFV seats.
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    classify = function(dual, "ITW_CLASH_DualHAL_fnc_ClassifyUnarmedForHAL")
    assert "RHQ_NCCargo pushBackUnique _class;" in classify
    assert "toLowerANSI (typeOf _veh)" in classify
    assert "magazinesAllTurrets _veh" in classify
    assert "getPylonMagazines _veh" in classify
    # live weapons survive magazine stripping, so a disarmed armed class is never listed
    assert "weaponsTurret" in classify
    assert "allTurrets [_veh,false]" in classify
    assert '"CarHorn","SmokeLauncher","CMFlareLauncher","Laserdesignator_mounted"' in classify
    assert "select {_x#4}" in classify  # fire-from-vehicle seats count as passenger seats
    assert '"hal-noncombat-cargo-class"' in classify

    call = "[_veh] call ITW_CLASH_DualHAL_fnc_ClassifyUnarmedForHAL;"
    for owner in [
        "ITW_CLASH_DualHAL_fnc_StageFieldVehicle",
        "ITW_CLASH_Checkbook_fnc_RegisterTransport",
        "ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles",
    ]:
        assert call in function(dual, owner), owner
