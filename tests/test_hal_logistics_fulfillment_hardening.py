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


def test_thunder_run_v4_visible_sling_vehicle_ammo_and_live_burn_tuning():
    overlay = _original_mission("ITW_CLASH_ThunderRun.sqf")
    core = _original_mission("ITW_CLASH_ThunderRun_Core.sqf")
    tuning = _original_mission("ITW_CLASH_ThunderRun_Tuning.sqf")

    assert "ITW_CLASH_ThunderRunVersion = 2;" in core
    assert "ITW_CLASH_ThunderRunVersion = 4;" in overlay
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

    classify = overlay.split("ITW_CLASH_ThunderRun_fnc_Classify = {", 1)[1].split(
        "ITW_CLASH_ThunderRun_fnc_VehicleAmmoTargets = {", 1
    )[0]
    assert 'in ["NORMAL","SAFE"]' in classify
    assert 'in ["CONTESTED","HOT"]' in classify
    assert '"AIR_DENIED"' not in classify.split(
        '_result set ["state",_lockedState]', 1
    )[0]

    staging = overlay.split("ITW_CLASH_ThunderRun_fnc_ApplyStaging = {", 1)[1].split(
        "ITW_CLASH_ThunderRun_fnc_TransitionPackage = {", 1
    )[0]
    assert '"Busy" + str _group,true' in staging
    assert 'disableAI "TARGET"' not in staging
    assert 'disableAI "AUTOTARGET"' not in staging

    assert '"ITW_CLASH_ThunderRun_Tuning.sqf"' in overlay
    assert "ITW_CLASH_ThunderRunTuningVersion = 1;" in tuning
    assert '"ITW_CLASH_ThunderRunTransitSpeedFraction",0.75' in tuning
    assert '"ITW_CLASH_ThunderRunTerminalSpeedFraction",0.90' in tuning
    assert '"ITW_CLASH_ThunderRunFlareCadenceScale",0.80' in tuning
    assert '"ITW_CLASH_ThunderRunReleaseBurstCount",6' in tuning
    assert '"ITW_CLASH_ThunderRunReleaseBurstCadence",0.16' in tuning
    assert '"ITW_CLASH_ThunderRunEgressFlareCadence",0.90' in tuning
    assert '"flare-burst"' in tuning
    assert '"rtb-immediate-after-cold"' in tuning
    assert '"rtb-ordered"' in tuning
    assert '"DoNotPlan"' in tuning
    assert '"LEADER PLANNED"' in tuning
    assert '"CLASH_VEHICLE_AMMO_AIR"' in tuning
    assert '"RydxHQ_MagicRearm"' in tuning
    assert "setVehicleAmmo 1" in tuning
    assert '"vehicle-ace-rearm"' in tuning
