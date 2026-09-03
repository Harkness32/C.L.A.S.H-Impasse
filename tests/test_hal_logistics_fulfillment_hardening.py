from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_logistics_rechecks_native_hal_after_checkbook_fulfills_capacity():
    text = mission("ITW_CLASH_HALLogistics.sqf")

    assert "ITW_CLASH_HALLogisticsVersion = 10;" in text
    assert "ITW_CLASH_HALLogistics_fnc_KickNative" in text
    assert '"native-recheck"' in text
    assert 'case "AMMO": {[_hq] call HAL_SuppAmmo};' in text
    assert 'case "FUEL": {[_hq] call HAL_SuppFuel};' in text
    assert 'case "REPAIR": {[_hq] call HAL_SuppRep};' in text
    assert '(_reply getOrDefault ["status",""]) == "APPROVED"' in text
    assert "postProvisionRecheck=true" in text


def test_zero_provider_bootstrap_breaks_hal_support_circular_dependency():
    text = mission("ITW_CLASH_HALLogistics.sqf")

    assert "ITW_CLASH_HALLogisticsZeroProviderBootstrap" in text
    assert 'if (_support isEqualTo []) then {' in text
    assert 'if ((_support + _drops) isEqualTo []) then {' in text
    assert '[_hq] call HAL_SuppFuel;' in text
    assert '[_hq] call HAL_SuppRep;' in text
    assert '[_hq] call HAL_SuppAmmo;' in text
    assert "zeroProviderBootstrap=true" in text


def test_checkbook_provider_availability_matches_native_busy_unable_fuel_rules():
    text = mission("ITW_CLASH_HALLogistics.sqf")
    helper = text.split("ITW_CLASH_HALLogistics_fnc_UsableGroups = {", 1)[1].split(
        "ITW_CLASH_HALLogistics_fnc_Request = {", 1
    )[0]

    assert "ITW_CLASH_HALLogistics_fnc_ProviderVehicle" in text
    assert "assignedVehicle _unit" in text
    assert '"ITW_CLASH_ServiceAsset",false' in text
    assert '"ITW_CLASH_CheckbookAsset",false' in text
    assert "private _physical = vehicle _unit;" in text
    assert '"provider-physical-vehicle-fallback"' in text
    assert "fuel _veh > 0.2" in helper
    assert '"Busy" + str _group' in helper
    assert 'getVariable ["Unable",false]' in helper


def test_air_ammo_pool_includes_sling_capable_utility_helicopters():
    text = mission("VehicleArrays.sqf")
    export = text.split("ITW_CLASH_PlayerAmmoHeloClasses =", 1)[1].split(
        "ITW_CLASH_CapabilityPoolsReady = true;", 1
    )[0]

    assert export.count('"slingLoadMaxCargoMass"') == 2
    assert export.count('"transportAmmo"') == 2
    assert "|| {getNumber" in export


def test_open_player_ammo_demand_uses_real_native_execution_not_supported_bookkeeping():
    validity = mission("ITW_CLASH_PlayerDemandAmmoValidityHardening.sqf")
    dispatch = mission("ITW_CLASH_PlayerDemandDispatch.sqf")
    intercept = mission("ITW_CLASH_PlayerDemandNativeInterceptors.sqf")

    assert "ITW_CLASH_PlayerDemandAmmoValidityHardeningVersion = 2;" in validity
    assert "ITW_CLASH_NativeAmmoExecution" in validity
    assert "RydHQ_ASupportedG" not in validity
    assert "supportedArrayNotAuthority=true" in validity

    publish = dispatch.split("ITW_CLASH_PlayerDemand_fnc_OnAmmoDemand = {", 1)[1].split(
        "ITW_CLASH_PlayerDemand_fnc_OnMedicalDemand = {", 1
    )[0]
    assert "ITW_CLASH_NativeAmmoExecution" in publish

    assert "ITW_CLASH_PlayerDemandNativeInterceptorsVersion = 10;" in intercept
    assert "native-ai-execution-started" in intercept
    assert "native-ai-execution-ended" in intercept
    assert 'setVariable ["ITW_CLASH_NativeAmmoExecution",nil]' in intercept



def test_hal_native_ace_logistics_workarounds_follow_ace_presence_without_magic_heal():
    text = mission("ITW_CLASH_HALLogistics.sqf")

    assert 'isClass (configFile >> "CfgPatches" >> "ace_main")' in text
    assert 'missionNamespace setVariable ["ITW_CLASH_ACEActive",ITW_CLASH_ACEActive,true];' in text
    assert 'missionNamespace setVariable ["RydxHQ_MagicRepair",ITW_CLASH_ACEActive,true];' in text
    assert 'missionNamespace setVariable ["RydxHQ_MagicRearm",ITW_CLASH_ACEActive,true];' in text
    assert 'missionNamespace setVariable ["RydxHQ_MagicRefuel",ITW_CLASH_ACEActive,true];' in text
    assert 'missionNamespace setVariable ["RydxHQ_MagicHeal",false,true];' in text
    assert "aceConditionalMagic=true" in text
    assert "aceMagicHeal=false" in text



def test_generated_ai_logistics_provider_admission_is_physical_and_declared():
    logistics = mission("ITW_CLASH_HALLogistics.sqf")
    generation = mission("ITW_CLASH_ForceGeneration.sqf")
    root = Path(__file__).resolve().parents[1]
    hal = root / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"

    assert "physicalServiceProviderFallback=true" in logistics
    assert "declaredCapabilityAdmission=true" in logistics
    assert '_group setVariable ["ITW_CLASH_GenerationCapability",_capability];' in generation

    for filename, capability in {
        "SuppAmmo.sqf": "LOGISTICS_AMMO",
        "SuppFuel.sqf": "LOGISTICS_FUEL",
        "SuppRep.sqf": "LOGISTICS_REPAIR",
    }.items():
        text = (hal / filename).read_text(encoding="utf-8")
        assert "ITW_CLASH_HALLogistics_fnc_ProviderVehicle" in text
        assert "_providerCapability = {" in text
        assert '"ITW_CLASH_ServiceCapability"' in text
        assert '"ITW_CLASH_GenerationCapability"' in text
        assert f'_declared == "{capability}"' in text
        assert "private _provider = [_x] call _providerVehicle;" in text


def test_fuel_and_repair_provider_dispatch_no_longer_require_direct_group_assignment():
    root = Path(__file__).resolve().parents[1]
    hal = root / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"
    fuel = (hal / "SuppFuel.sqf").read_text(encoding="utf-8")
    repair = (hal / "SuppRep.sqf").read_text(encoding="utf-8")

    assert "assignedVehicle (leader _x)" not in fuel
    assert "assignedvehicle (leader _x)" not in fuel
    assert "assignedVehicle (leader _x)" not in repair
    assert "assignedvehicle (leader _x)" not in repair
    assert fuel.count("[_x] call _providerVehicle") >= 5
    assert repair.count("[_x] call _providerVehicle") >= 5


def test_ai_air_ammo_provider_is_preloaded_only_after_exact_dispatch_is_known():
    logistics = mission("ITW_CLASH_HALLogistics.sqf")
    intercept = mission("ITW_CLASH_PlayerDemandNativeInterceptors.sqf")
    root = Path(__file__).resolve().parents[1]
    go = (root / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "GoAmmoSupp.sqf").read_text(
        encoding="utf-8"
    )

    assert "ITW_CLASH_HALLogistics_fnc_PrimeExactAmmoSling" in logistics
    assert "setSlingLoad _box" in logistics
    assert '"ITW_CLASH_PreloadedAmmoBox"' in logistics
    assert '"ITW_CLASH_PreloadedSlingCarrier"' in logistics
    assert "ammo-exact-sling-preloaded" in logistics

    evaluate = logistics.split("ITW_CLASH_HALLogistics_fnc_Evaluate = {", 1)[1].split(
        "[] spawn {", 1
    )[0]
    ammo_block = evaluate.split('case "AMMO": {', 1)[1].split('case "FUEL": {', 1)[0]
    assert ammo_block.index('"LOGISTICS_PACKAGE_AMMO","AIR"') < ammo_block.index('"LOGISTICS_AMMO","AIR"')
    assert "PrimeAmmoSling" not in ammo_block
    assert "PrimeExactAmmoSling" not in ammo_block

    assert "ITW_CLASH_HALLogistics_fnc_PrimeExactAmmoSling" in intercept
    assert "_drop" in intercept
    assert '_vehicle isKindOf "Helicopter"' in intercept
    assert "_preloadedSling = (getSlingLoad _unit) isEqualTo _ammoBox;" in go
    assert "RydxHQ_SlingDrop or {_preloadedSling}" in go


def test_thunder_run_uses_hal_intelligence_native_drop_and_existing_lifecycle():
    thunder = mission("ITW_CLASH_ThunderRun.sqf")
    intercept = mission("ITW_CLASH_PlayerDemandNativeInterceptors.sqf")
    logistics = mission("ITW_CLASH_HALLogistics.sqf")

    assert "ITW_CLASH_ThunderRunVersion = 2;" in thunder
    assert '"THUNDER RUN INITIATED"' in thunder
    assert "RYD_AmmoDrop" in thunder
    assert "B_Parachute_02_F" not in thunder
    assert "RYD_PointToSecDst" in thunder
    assert '"RydHQ_AAthreat"' in thunder
    assert '"RydHQ_Airthreat"' in thunder
    assert '"RydHQ_KnEnemiesG"' in thunder
    assert '"ITW_CLASH_ThunderRunActive"' in thunder
    assert "ITW_CLASH_Service_fnc_Retire" in thunder
    assert "_box allowDamage false" in thunder
    assert '"POPUP"' in thunder
    assert '"RELEASE"' in thunder
    assert '"EGRESS"' in thunder
    assert '"RTB"' in thunder
    assert "forceWeaponFire" in thunder
    assert "shotcm" in thunder

    wrapper = intercept.split("HAL_GoAmmoSupp = {", 1)[1].split(
        "ITW_CLASH_PlayerDemandNative_fnc_GoMedSuppBase", 1
    )[0]
    assert wrapper.index("ITW_CLASH_ThunderRun_fnc_Classify") < wrapper.index(
        "ITW_CLASH_HALLogistics_fnc_PrimeExactAmmoSling"
    )
    assert 'if (_airDecisionState == "AIR_DENIED") exitWith {' in wrapper
    assert "ITW_CLASH_AmmoDispatch_fnc_ReconcilePreDispatch" in wrapper
    assert "_providerHuman" in wrapper
    assert "thunderRunRouter=true" in intercept

    evaluate = logistics.split("ITW_CLASH_HALLogistics_fnc_Evaluate = {", 1)[1].split(
        "[] spawn {", 1
    )[0]
    ammo = evaluate.split('case "AMMO": {', 1)[1].split('case "FUEL": {', 1)[0]
    assert '"RydHQ_ASupportedG"' in ammo
    assert '"RydHQ_Boxed"' in ammo
    assert "if (_openDemandCount <= 0) exitWith {true};" in ammo
    assert "ITW_CLASH_ThunderRun_fnc_CommittedCapacity" in ammo
    assert "_effectiveAirCapacity < _openDemandCount" in ammo

    assert "ITW_CLASH_ThunderRunVersion = 2;" in thunder
    assert "ITW_CLASH_ThunderRun_fnc_Dispose" in thunder
    assert "ITW_CLASH_ThunderRun_fnc_Handback" in thunder
    assert '"DoNotPlan"' in thunder
    assert '"LEADER PLANNED"' in thunder
    assert "ITW_CLASH_ThunderRunStagedBoxes" in thunder
    assert '"reaper-crate"' in thunder
    assert "ITW_CLASH_ThunderRunIPRadius" in thunder
    assert '"ip-crossed"' in thunder
    assert "ITW_CLASH_ThunderRun_fnc_FireCountermeasure" in thunder
    assert "ITW_CLASH_ThunderRunCountermeasureFireOverride" in thunder
    assert "ITW_CLASH_ThunderRunCalibrationSamples" in thunder
    assert '"release-calibration"' in thunder
    assert '"CLASH_ThunderRun_Inherited"' in thunder
    assert "ITW_CLASH_ThunderRun_fnc_ResolveAlternateDZ" in thunder
    assert "ITW_CLASH_ThunderRunAlternateDZResolver" in thunder
    assert "ITW_CLASH_ThunderRun_fnc_ClearASupported" not in thunder.split(
        '["crate-release"', 1
    )[0].split('ITW_CLASH_ThunderRun_fnc_Run = {', 1)[1].split(
        '["crate-release"', 1
    )[0]
