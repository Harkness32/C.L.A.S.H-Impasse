from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NATIVE_ORDERS = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "HQOrders.sqf"


def _text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def _block(text: str, start: str, end: str) -> str:
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


def test_strike_uses_only_hal_known_enemy_picture_and_hal_taxonomy():
    text = _text("ITW_CLASH_PlayerTaskRequestStrike.sqf")

    assert 'getVariable ["RydHQ_KnEnemiesG",[]]' in text
    assert 'getVariable ["RydHQ_KnEnemies",[]]' in text
    for key in (
        "RydHQ_EnHArmorG",
        "RydHQ_EnMArmorG",
        "RydHQ_EnLArmorG",
        "RydHQ_EnLArmorATG",
        "RydHQ_EnInfG",
        "RydHQ_EnStaticG",
        "RydHQ_EnCarsG",
    ):
        assert key in text

    for forbidden in ("allUnits", "nearEntities", "nearestObjects", "reveal "):
        assert forbidden not in text


def test_strike_reservation_is_player_job_only_and_does_not_block_hal_combat():
    text = _text("ITW_CLASH_PlayerTaskRequestStrike.sqf")

    assert "ITW_CLASH_PlayerStrikeReservation" in text
    assert "ITW_CLASH_PlayerStrikeJobId" in text
    assert "other friendly forces may engage the same enemy" in text
    for forbidden in (
        'setVariable ["RydHQ_NoAttack"',
        'setVariable ["RydHQ_NoRecon"',
        'setVariable ["RydHQ_NoDef"',
        'setVariable ["Unable",true',
    ):
        assert forbidden not in text


def test_strike_uses_native_nearest_known_threat_heuristic_after_class_filter():
    adapter = _text("ITW_CLASH_PlayerTaskRequestStrike.sqf")
    native = NATIVE_ORDERS.read_text(encoding="utf-8", errors="ignore")

    native_nearest = _block(native, '_HQ setVariable ["RydHQ_NearestE",ObjNull];', "_ReconAv = [];")
    assert 'getVariable ["RydHQ_KnEnemiesG",[]]' in native_nearest
    assert 'setVariable ["RydHQ_NearestE",_x]' in native_nearest
    assert "distance _vHQ" in native_nearest

    selector = _block(
        adapter,
        "ITW_CLASH_PlayerTaskRequestStrike_fnc_SelectTarget = {",
        "ITW_CLASH_PlayerTaskRequestStrike_fnc_Request = {",
    )
    assert "distance2D _hqVehicle" in selector
    assert "random" not in selector.lower()
    assert "rating" not in selector.lower()


def test_strike_tracks_hal_known_target_and_reward_authorization_only():
    text = _text("ITW_CLASH_PlayerTaskRequestStrike.sqf")
    monitor = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestStrike_fnc_Monitor = {",
        "ITW_CLASH_PlayerTaskRequestStrike_fnc_SelectTarget = {",
    )

    assert '["targetPosition",+_targetPosition]' in text
    assert "BIS_fnc_taskSetDestination" in monitor
    assert "ITW_CLASH_PlayerTaskRequestStrike_fnc_KnownGroups" in monitor
    assert "_halKnows" in monitor
    assert '["targetPosition",+_newPosition]' in monitor
    assert '"target-tracked"' in monitor
    assert '"PLAYER_TASK_REWARD_AUTHORIZED"' in text
    assert '["rewardClass","STRIKE"]' in text
    assert "setPos" not in text
    assert "setMarkerPos" not in text
    assert "addScore" not in text
    assert "money" not in text.lower()


def test_recon_history_can_only_remember_contacts_hal_previously_knew():
    text = _text("ITW_CLASH_PlayerTaskRequestRecon.sqf")

    history = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestRecon_fnc_KnownGroups = {",
        "ITW_CLASH_PlayerTaskRequestRecon_fnc_PlayerKnowledge = {",
    )
    assert 'getVariable ["RydHQ_KnEnemiesG",[]]' in history
    assert 'getVariable ["RydHQ_KnEnemies",[]]' in history
    assert "lastKnownPos" in history
    assert "lostAt" in history
    for forbidden in ("allUnits", "nearEntities", "nearestObjects", "reveal "):
        assert forbidden not in text


def test_recon_is_vehicle_agnostic_and_has_no_recon_variant_taxonomy():
    text = _text("ITW_CLASH_PlayerTaskRequestRecon.sqf")

    request = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestRecon_fnc_Request = {",
        "[] spawn {",
    )
    for forbidden in (
        "GetEmploymentVehicle",
        "HasPassengerCapacity",
        "isKindOf \"Air\"",
        "isKindOf \"LandVehicle\"",
        "SOF",
        "ARMORED_RECON",
        "FORCE_RECON",
        "IsSubscribed",
    ):
        assert forbidden not in request
    assert '["requestType","RECON"]' in request


def test_recon_success_requires_player_observation_and_hal_reacquisition():
    text = _text("ITW_CLASH_PlayerTaskRequestRecon.sqf")
    monitor = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestRecon_fnc_Monitor = {",
        "ITW_CLASH_PlayerTaskRequestRecon_fnc_SelectRecord = {",
    )

    assert "knowsAbout" in text
    assert "_playerKnowledge >= ITW_CLASH_PlayerReconKnowledgeThreshold" in monitor
    assert "&& {_halKnows}" in monitor
    assert '"hal-intel-reacquired"' in monitor
    assert '"contact-reacquired-by-other-friendly"' in monitor
    assert "killed" not in monitor.lower()


def test_recon_task_uses_frozen_last_known_marker_and_authorizes_reward_only_on_success():
    text = _text("ITW_CLASH_PlayerTaskRequestRecon.sqf")

    assert '["lastKnownPosition",+_lastKnownPos]' in text
    assert "The marker is the last legitimate HAL position and will not track the target." in text
    assert '"PLAYER_TASK_REWARD_AUTHORIZED"' in text
    assert '["rewardClass","RECON"]' in text
    assert "setMarkerPos" not in text
    assert "addScore" not in text


def test_armor_strike_completion_counts_combat_vehicles_not_dismounted_crew():
    text = _text("ITW_CLASH_PlayerTaskRequestStrike.sqf")
    threat = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestStrike_fnc_ThreatCount = {",
        "ITW_CLASH_PlayerTaskRequestStrike_fnc_CombatIneffective = {",
    )

    assert 'if (_requestType in ["STRIKE_LIGHT_ARMOR","STRIKE_HEAVY_ARMOR"]) then {' in threat
    assert "alive _vehicle" in threat
    assert "canFire _vehicle" in threat
    assert "count _vehicles" in threat
    assert "} else {" in threat
    assert "{alive _x} count units _targetGroup" in threat
    assert "Dismounted surviving crews are not part of the armor STRIKE objective." in text


def test_strike_task_presentation_uses_destroy_labels_and_last_known_tracking_language():
    text = _text("ITW_CLASH_PlayerTaskRequestStrike.sqf")
    presentation = _block(
        text,
        "ITW_CLASH_PlayerTaskRequestStrike_fnc_TaskPresentation = {",
        "ITW_CLASH_PlayerTaskRequestStrike_fnc_ReleaseReservation = {",
    )

    assert '"Destroy Squad"' in presentation
    assert '"Destroy Soft Target"' in presentation
    assert '"Destroy Light Armor"' in presentation
    assert '"Destroy Heavy Armor"' in presentation
    assert "latest known position" in presentation
    assert "Dismounted surviving crews are not part of the armor STRIKE objective." in presentation

    task_create = _block(
        text,
        "private _players = units _group select {isPlayer _x};",
        '["target-selected",[',
    )
    assert "_taskTitle" in task_create
    assert "_taskDescription" in task_create
    assert "true" in task_create
    assert '"destroy"' in task_create
