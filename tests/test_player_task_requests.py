from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def _text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def _block(text: str, start: str, end: str) -> str:
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


def test_request_router_is_ephemeral_leader_authoritative_and_subscription_independent():
    text = _text("ITW_CLASH_PlayerTaskRequests.sqf")

    assert "ITW_CLASH_PlayerTasks_fnc_RemotePlayerValid" in text
    assert "ITW_CLASH_PlayerTaskRequests_fnc_HasActiveJob" in text
    assert "ITW_CLASH_AuthorityHold" in text
    assert "ITW_CLASH_PlayerTaskRequestCooldown" not in text
    assert "ITW_CLASH_PlayerTaskRequestNextAt" not in text
    assert "HAL is still processing your last task query." not in text
    assert "queryCooldown=false" in text
    assert "ITW_CLASH_PlayerTaskRequestAdapters = createHashMap" in text
    assert "ephemeralRequests=true" in text
    assert "subscriptionsRequired=false" in text

    handler = _block(
        text,
        "ITW_CLASH_PlayerTaskRequests_fnc_HandleRemote = {",
        "[] spawn {",
    )
    assert "ITW_CLASH_PlayerTasks_fnc_IsSubscribed" not in handler
    assert "ITW_CLASH_PlayerJobSubscriptions" not in handler
    assert "ITW_CLASH_PlayerDemands set" not in handler


def test_request_menu_is_separate_and_exposes_locked_revision_one_shape():
    menu = _text("ITW_CLASH_PlayerTaskRequestMenu.sqf")
    employment = _text("ITW_CLASH_PlayerEmploymentMenu.sqf")
    local_init = _text("initPlayerLocal.sqf")

    assert "Request HAL Task" in menu
    assert "Soft Targets" in menu
    assert "Light Armor" in menu
    assert "Heavy Armor" in menu
    assert "Recon" in menu
    assert "Artillery" in menu
    assert "Transport" in menu
    assert "LOGISTICS" not in menu
    assert "SEEK" not in menu.upper()
    assert "ITW_CLASH_PlayerTaskRequestMenu.sqf" in local_init
    assert "Request HAL Task" not in employment


def test_strike_menu_uses_native_commanding_menu_submenu_link():
    menu = _text("ITW_CLASH_PlayerTaskRequestMenu.sqf")
    open_menu = _block(
        menu,
        "ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenMenu = {",
        "ITW_CLASH_PlayerTaskRequestMenu_fnc_Install = {",
    )
    strike_builder = _block(
        menu,
        "ITW_CLASH_PlayerTaskRequestMenu_fnc_BuildStrike = {",
        "ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenStrike = {",
    )

    assert '"Strike >"' in open_menu
    assert '"#USER:ITW_CLASH_PlayerTaskRequestStrikeMenu"' in open_menu
    assert '[] call ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenStrike' not in open_menu
    assert '"Back"' in strike_builder
    assert '"",-4,' in strike_builder
    assert "nativeSubmenuLink=true" in menu


def test_artillery_request_uses_hal_known_targets_and_native_cff_reservation():
    text = _text("ITW_CLASH_PlayerTaskRequestArtillery.sqf")

    request = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestArtillery_fnc_Request = {",
        "[] spawn {",
    )
    assert 'getVariable ["RydHQ_KnEnemies",[]]' in request
    assert "RYD_CFF_TGT" in request
    assert "RYD_ArtyMission" in request
    assert "ITW_CLASH_PlayerArtillery_fnc_NewJob" in request
    assert "ITW_CLASH_PlayerArtillery_fnc_Monitor" in request
    assert "ITW_CLASH_PlayerTasks_fnc_IsSubscribed" not in request
    assert "nearestObjects" not in request
    assert "nearEntities" not in request
    assert "allUnits" not in request

    assert 'setVariable ["CFF_Taken",true]' in text
    assert 'setVariable ["CFF_Taken",false]' in text
    assert "ITW_CLASH_PlayerRequestedCFFReservation" in text
    assert '"origin","PLAYER_REQUEST"' in text
    assert '"requestType","ARTILLERY"' in text


def test_artillery_explicit_request_requires_current_deployed_capability():
    text = _text("ITW_CLASH_PlayerTaskRequestArtillery.sqf")
    eligible = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestArtillery_fnc_EligibleVehicle = {",
        "ITW_CLASH_PlayerTaskRequestArtillery_fnc_TargetGroup = {",
    )

    assert "ITW_CLASH_PlayerArtillery_fnc_GetVehicle" in eligible
    assert "ITW_CLASH_PlayerGarageAsset" in eligible
    assert "ITW_CLASH_PlayerArtyDeploymentState" in eligible
    assert "ITW_CLASH_PlayerArtillery_fnc_OutsideRearSanctuary" in eligible
    assert "ITW_CLASH_PlayerTasks_fnc_IsSubscribed" not in eligible


def test_requested_cff_reservation_releases_only_its_own_marker_on_terminalization():
    text = _text("ITW_CLASH_PlayerTaskRequestArtillery.sqf")

    release = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReleaseReservation = {",
        "ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReserveTarget = {",
    )
    assert "_current != _ownerToken" in release
    assert 'setVariable ["CFF_Taken",false]' in release

    binder = text[text.index("ITW_CLASH_PlayerTaskRequestArtillery_fnc_FinishJobBase ="):]
    assert "ITW_CLASH_PlayerArtillery_fnc_FinishJob" in binder
    assert '_origin == "PLAYER_REQUEST"' in binder
    assert "ITW_CLASH_PlayerTaskRequestArtillery_fnc_ReleaseReservation" in binder


def test_request_layer_boots_after_demand_first_native_interceptors():
    boot = _text("ITW_CLASH_PlayerDemandNativeInterceptors.sqf")
    assert "ITW_CLASH_PlayerTaskRequests.sqf" in boot
    assert "ITW_CLASH_PlayerTaskRequestArtillery.sqf" in boot
    assert "player-initiated tasking is a follow-on layer".lower() in boot.lower()


def test_request_router_allows_immediate_requery_when_no_job_is_assigned():
    text = _text("ITW_CLASH_PlayerTaskRequests.sqf")
    handler = _block(
        text,
        "ITW_CLASH_PlayerTaskRequests_fnc_HandleRemote = {",
        "[] spawn {",
    )

    assert "COOLDOWN" not in handler
    assert "PlayerTaskRequestNextAt" not in handler
    assert "PlayerTaskRequestCooldown" not in handler
    assert "ITW_CLASH_PlayerTaskRequests_fnc_HasActiveJob" in handler


def test_request_router_uses_shared_active_lease_and_inflight_claim():
    text = _text("ITW_CLASH_PlayerTaskRequests.sqf")
    handler = _block(
        text,
        "ITW_CLASH_PlayerTaskRequests_fnc_HandleRemote = {",
        "[] spawn {",
    )

    assert "ITW_CLASH_PlayerTaskRequestActiveJobId" in text
    assert "ITW_CLASH_PlayerTaskRequestClaimUntil" in handler
    assert "active-lease-acquired" in handler
    assert "ITW_CLASH_PlayerTaskRequests_fnc_WatchActiveLease" in text
    assert "ITW_CLASH_PlayerTaskRequests_fnc_ReleaseActiveLease" in text
    assert "sharedActiveLease=true" in text
    assert "oneActiveJob=true" in text


def test_request_death_event_fails_all_active_player_requested_jobs_for_participant():
    text = _text("ITW_CLASH_PlayerTaskRequests.sqf")

    assert 'addMissionEventHandler [' in text
    assert '"EntityKilled"' in text
    assert "getPlayerUID _killed" in text
    assert '(_job getOrDefault ["origin",""]) != "PLAYER_REQUEST"' in text
    assert '(_x param [0,""]) == _uid' in text
    assert '"assigned-player-killed"' in text
    assert "ITW_CLASH_PlayerTaskRequests_fnc_FailMatchedJob" in text
    assert "ITW_CLASH_PlayerTaskRequestStrike_fnc_Finish" in text
    assert "ITW_CLASH_PlayerTaskRequestRecon_fnc_Finish" in text
    assert "ITW_CLASH_PlayerArtillery_fnc_FinishJob" in text
    assert "deathFailsTask=true" in text


def test_active_lease_reconciles_visible_task_to_terminal_backend_state():
    text = _text("ITW_CLASH_PlayerTaskRequests.sqf")
    watch = _block(
        text,
        "ITW_CLASH_PlayerTaskRequests_fnc_WatchActiveLease = {",
        "ITW_CLASH_PlayerTaskRequests_fnc_FailMatchedJob = {",
    )

    assert '["COMPLETED","FAILED","CANCELED"]' in watch
    assert "BIS_fnc_taskSetState" in watch
    assert 'case "COMPLETED": {"SUCCEEDED"}' in watch
    assert 'case "CANCELED": {"CANCELED"}' in watch
    assert 'default {"FAILED"}' in watch
