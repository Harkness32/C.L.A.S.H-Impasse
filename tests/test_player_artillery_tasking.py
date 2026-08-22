from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "13715765820790864929_legacy"


def source(name: str) -> str:
    return (LEGACY / name).read_text(encoding="utf-8")


def before(text: str, left: str, right: str) -> None:
    assert left in text, left
    assert right in text, right
    assert text.index(left) < text.index(right), (left, right)


def test_boot_loads_artillery_after_tasks_and_garage() -> None:
    text = source("init.sqf")
    before(
        text,
        '"ITW_CLASH_PlayerTaskSupport.sqf"',
        '"ITW_CLASH_PlayerArtilleryTasks.sqf"',
    )
    before(
        text,
        '"ITW_CLASH_PlayerGarageDeployment.sqf"',
        '"ITW_CLASH_PlayerArtilleryTasks.sqf"',
    )
    assert "&& {_playerArtilleryLoaded isEqualTo true}" in text
    assert "playerArtillery=%6" in text


def test_garage_asset_provenance_is_public() -> None:
    text = source("ITW_CLASH_PlayerGarageDeployment.sqf")
    assert '"ITW_CLASH_PlayerGarageAsset",true,true' in text
    assert '"ITW_CLASH_PlayerGarageOwnerUID",getPlayerUID player,true' in text
    assert '"ITW_CLASH_PlayerArtyDeploymentState","DEPLOYED",true' in text
    before(
        text,
        '"ITW_CLASH_PlayerArtyDeploymentState","DEPLOYED",true',
        'systemChat "C.L.A.S.H. artillery deployed',
    )


def test_hal_targeting_is_hooked_before_direct_fire() -> None:
    text = source("ITW_CLASH_PlayerArtilleryTasks.sqf")
    assert "ITW_CLASH_PlayerArtillery_fnc_NativeCFF = RYD_CFF;" in text
    assert "RYD_CFF = {" in text
    assert "private _target = [_knownEnemies] call RYD_CFF_TGT;" in text
    assert "] call RYD_ArtyMission;" in text
    assert "_nativeArgs set [0,_aiGroups];" in text
    assert "_nativeArgs call ITW_CLASH_PlayerArtillery_fnc_NativeCFF" in text
    assert "doArtilleryFire" not in text


def test_human_groups_never_reach_native_cff() -> None:
    text = source("ITW_CLASH_PlayerArtilleryTasks.sqf")
    before(text, "private _humanGroups =", "private _aiGroups =")
    assert "private _aiGroups = _artilleryGroups - _humanGroups;" in text
    before(text, "_nativeArgs set [0,_aiGroups];", "_nativeArgs call")


def test_provider_requires_opt_in_garage_and_deployment() -> None:
    text = source("ITW_CLASH_PlayerArtilleryTasks.sqf")
    assert '"ITW_CLASH_PlayerTaskOptIn",false' in text
    assert '"ITW_CLASH_PlayerGarageAsset",false' in text
    assert '"ITW_CLASH_PlayerArtyDeploymentState",""' in text
    assert '!= "DEPLOYED"' in text
    assert "ITW_CLASH_PlayerArtillery_fnc_OutsideRearSanctuary" in text
    assert 'fullCrew [_vehicle,"gunner",true]' in text
    assert "getArtilleryAmmo [_vehicle]" in text


def test_v1_is_he_only_and_danger_close_guarded() -> None:
    text = source("ITW_CLASH_PlayerArtilleryTasks.sqf")
    assert '"HE",_amount,objNull' in text
    assert "ITW_CLASH_PlayerArtilleryDangerCloseRadius" in text
    assert '"danger-close-denied"' in text
    assert '"SMOKE"' not in text
    assert '"ILLUM"' not in text


def test_server_locks_and_validates_fire_contract() -> None:
    text = source("ITW_CLASH_PlayerArtilleryTasks.sqf")
    for token in (
        '["participants",_roster]',
        '["allowedMagazines",+_allowedMagazines]',
        '["authorizedRounds",_authorizedRounds]',
        '["requiredImpacts",_requiredImpacts]',
        '["shotIds",[]]',
        '["resolvedShotIds",[]]',
        "remoteExecutedOwner != owner _reporter",
        "_reporter in crew _vehicle",
    ):
        assert token in text


def test_client_observes_fired_and_reports_terminal_position() -> None:
    text = source("ITW_CLASH_PlayerTaskClient.sqf")
    assert 'addEventHandler ["Fired"' in text
    assert "ITW_CLASH_PlayerArtillery_fnc_ReportFiredRemote" in text
    assert "ITW_CLASH_PlayerArtillery_fnc_ReportImpactRemote" in text
    assert "_lastPosition = getPosATL _projectile;" in text
    assert "local _vehicle" in text
    assert 'removeEventHandler ["Fired",_ehId]' in text


def test_completion_is_mode_neutral_and_shared() -> None:
    text = source("ITW_CLASH_PlayerArtilleryTasks.sqf")
    assert '"ARTILLERY_MISSION_COMPLETED"' in text
    assert '"participants",_roster' in text
    assert "ITW_CLASH_PlayerArtilleryImpactRatio" in text
    lowered = text.lower()
    assert "payout" not in lowered
    assert "cash" not in lowered
    assert "reward" not in lowered


def test_interdiction_seam_records_without_enemy_injection() -> None:
    text = source("ITW_CLASH_PlayerArtilleryTasks.sqf")
    assert '"ARTILLERY_FIRING_POSITION_EMITTED"' in text
    assert '"ITW_CLASH_ArtilleryEmission"' in text
    assert "RydHQ_EnArtG" not in text
    assert "RydHQ_KnEnemies" not in text


def test_native_deny_cancels_artillery_job() -> None:
    text = source("ITW_CLASH_PlayerArtilleryTasks.sqf")
    assert "ITW_CLASH_PlayerArtillery_fnc_CancelGroupJobBase" in text
    assert '"ITW_CLASH_PlayerArtilleryJobCancel",true,true' in text
    assert '[_jobId,"CANCELED","player-denied-task"]' in text
