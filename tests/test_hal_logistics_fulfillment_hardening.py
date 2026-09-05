import hal_logistics_fulfillment_hardening_core as _core


_original_mission = _core.mission


def _mission_with_thunder_core(name: str) -> str:
    text = _original_mission(name)
    if name == "ITW_CLASH_ThunderRun.sqf":
        core = _original_mission("ITW_CLASH_ThunderRun_Core.sqf")
        return core + "\n" + text
    return text


_core.mission = _mission_with_thunder_core

from hal_logistics_fulfillment_hardening_core import *  # noqa: F401,F403,E402


def test_thunder_run_v3_visible_sling_and_vehicle_ammo_bridge():
    overlay = _original_mission("ITW_CLASH_ThunderRun.sqf")
    core = _original_mission("ITW_CLASH_ThunderRun_Core.sqf")

    assert "ITW_CLASH_ThunderRunVersion = 2;" in core
    assert "ITW_CLASH_ThunderRunVersion = 3;" in overlay
    assert "ITW_CLASH_ThunderRun_fnc_ApplyStagingCore" in overlay
    assert "ITW_CLASH_HALLogistics_fnc_PrimeExactAmmoSling" in overlay
    assert '"package-sling-departure"' in overlay
    assert '"THUNDER RUN SLING LOADED' in overlay
    assert "setSlingLoad objNull" in overlay
    assert '"THUNDER RUN PACKAGE TRANSITION' in overlay
    assert '"slingTransit",true' in overlay
    assert '"packageTransitioned",true' in overlay
    assert "ITW_CLASH_ThunderRun_fnc_RegisterStagedBox" in overlay

    assert "ITW_CLASH_ThunderRun_fnc_VehicleAmmoTargets" in overlay
    assert '"RydHQ_Hollow"' in overlay
    assert "someAmmo _target" in overlay
    assert '"RydHQ_AmmoDrop"' in overlay
    assert '"RydHQ_ASupportedG"' in overlay
    assert '"RydHQ_AmmoBoxes"' in overlay
    assert '"CLASH_VEHICLE_AMMO_AIR",true,true' in overlay
    assert '"vehicle-ammo-bridge-dispatch"' in overlay
    assert '_state in ["CONTESTED","HOT"]' in overlay
    assert "HAL_GoAmmoSupp" in overlay

    # Vehicle admission must not weaken safety. The short commit-window lock can
    # preserve a CONTESTED/HOT decision only when the recheck became SAFE/NORMAL;
    # AIR_DENIED is never overwritten.
    classify = overlay.split("ITW_CLASH_ThunderRun_fnc_Classify = {", 1)[1].split(
        "ITW_CLASH_ThunderRun_fnc_VehicleAmmoTargets = {", 1
    )[0]
    assert 'in ["NORMAL","SAFE"]' in classify
    assert 'in ["CONTESTED","HOT"]' in classify
    assert '"AIR_DENIED"' not in classify.split("_result set [\"state\",_lockedState]", 1)[0]

    # Busy remains the HAL retask lock, while the enhancement layer never blinds
    # TARGET/AUTOTARGET during the sortie.
    staging = overlay.split("ITW_CLASH_ThunderRun_fnc_ApplyStaging = {", 1)[1].split(
        "ITW_CLASH_ThunderRun_fnc_TransitionPackage = {", 1
    )[0]
    assert '"Busy" + str _group,true' in staging
    assert 'disableAI "TARGET"' not in staging
    assert 'disableAI "AUTOTARGET"' not in staging
