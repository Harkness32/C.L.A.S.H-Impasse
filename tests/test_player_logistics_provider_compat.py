from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def test_player_logistics_roster_uses_physical_sling_vehicle():
    text = (MISSION / "ITW_CLASH_PlayerTaskSupport.sqf").read_text(encoding="utf-8")

    assert 'ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle = {' in text
    assert 'private _vehicle = vehicle _leader;' in text
    assert '!(_vehicle isKindOf "Helicopter")' in text
    assert '"slingLoadMaxCargoMass"' in text
    assert 'ITW_CLASH_PlayerTasks_fnc_SyncLogisticsRole = {' in text
    assert '_drops.pushBackUnique' not in text  # preserve SQF syntax check below
    assert '_drops pushBackUnique _group;' in text
    assert '_hq setVariable ["RydHQ_AmmoDrop",_drops];' in text
    assert '_group setVariable ["ITW_CLASH_PlayerLogisticsAir",_eligible,true];' in text


def test_native_suppammo_uses_shared_physical_provider_resolver():
    text = (HAL / "SuppAmmo.sqf").read_text(encoding="utf-8")
    mission_logistics = (MISSION / "ITW_CLASH_HALLogistics.sqf").read_text(encoding="utf-8")

    assert '_providerVehicle = {' in text
    start = text.index('_providerVehicle = {')
    stop = text.index('_ammo = RHQ_Ammo', start)
    helper = text[start:stop]

    assert 'ITW_CLASH_HALLogistics_fnc_ProviderVehicle' in helper
    assert 'assignedVehicle _unit' in helper
    assert '(units _group findIf {isPlayer _x}) >= 0' in mission_logistics
    assert '"ITW_CLASH_ServiceAsset",false' in mission_logistics
    assert '"ITW_CLASH_CheckbookAsset",false' in mission_logistics
    assert 'private _physical = vehicle _unit;' in mission_logistics
    assert '"provider-physical-vehicle-fallback"' in mission_logistics

    assert '_mtr = [_x] call _providerVehicle;' in text
    assert text.count('_MTruck = [_x] call _providerVehicle;') >= 2
    assert text.count('private _nearProvider = [_x] call _providerVehicle;') >= 2


def test_player_sling_dispatch_still_uses_clash_job_executor_not_native_movement():
    text = (MISSION / "ITW_CLASH_PlayerTaskSupport.sqf").read_text(encoding="utf-8")

    wrapper = text[text.index('HAL_GoAmmoSupp = {'):]
    assert 'private _playerProvider = _humanProvider' in wrapper
    assert '"ITW_CLASH_PlayerLogisticsAir",false' in wrapper
    assert 'if (_drop && {_playerProvider} && {!isNull _box}) exitWith {' in wrapper
    assert '_this spawn ITW_CLASH_PlayerTasks_fnc_PlayerAmmoJob' in wrapper
    assert '_this call ITW_CLASH_PlayerTasks_fnc_NativeGoAmmoSupp' in wrapper

    job_start = text.index('ITW_CLASH_PlayerTasks_fnc_PlayerAmmoJob = {')
    job_stop = text.index('ITW_CLASH_PlayerTasks_fnc_CancelGroupJob = {', job_start)
    job = text[job_start:job_stop]
    assert '"HAL Logistics: Ammunition Sling"' in job
    assert '[_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;' in job
    assert 'RYD_WPadd' not in job
    assert 'addWaypoint' not in job
    assert 'doMove' not in job
