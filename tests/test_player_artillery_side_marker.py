from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "13715765820790864929_legacy"


def source(name: str) -> str:
    return (LEGACY / name).read_text(encoding="utf-8")


def test_side_marker_loads_after_task_adapters() -> None:
    text = source("ITW_CLASH_PlayerTaskRequestBootstrap.sqf")
    assert 'forEach _adapters;' in text
    assert '"ITW_CLASH_PlayerArtillerySideMarker.sqf"' in text
    assert text.index('forEach _adapters;') < text.index(
        '"ITW_CLASH_PlayerArtillerySideMarker.sqf"'
    )


def test_artillery_fire_area_uses_native_side_marker_channel() -> None:
    text = source("ITW_CLASH_PlayerArtillerySideMarker.sqf")

    assert 'private _players = units _group select {isPlayer _x};' in text
    assert 'private _creator = [_group] call' in text
    assert 'private _marker = createMarker [' in text
    assert '_markerName,' in text
    assert '_targetPosition,' in text
    assert '        1,' in text
    assert '        _creator' in text
    assert 'setMarkerShape "ELLIPSE"' in text
    assert 'setMarkerBrush "Border"' in text
    assert 'setMarkerColor "ColorRed"' in text
    assert 'setMarkerSize [_targetRadius,_targetRadius]' in text
    assert 'setMarkerAlpha 0.9' in text


def test_side_marker_preserves_gun_crew_only_shot_authority() -> None:
    text = source("ITW_CLASH_PlayerArtillerySideMarker.sqf")

    assert 'ITW_CLASH_PlayerArtillerySideMarker_fnc_PushClientAssignmentBase =' in text
    assert 'ITW_CLASH_PlayerArtillery_fnc_PushClientAssignment;' in text
    assert '_this call\n        ITW_CLASH_PlayerArtillerySideMarker_fnc_PushClientAssignmentBase' in text
    assert 'ITW_CLASH_PlayerTaskClient_fnc_AssignArtilleryJob' not in text
    assert 'addEventHandler ["Fired"' not in text
    assert 'allPlayers' not in text
    assert 'remoteExecCall' not in text


def test_side_marker_uses_150m_aim_contract_not_250m_acceptance_contract() -> None:
    text = source("ITW_CLASH_PlayerArtillerySideMarker.sqf")

    assert '"targetRadius"' in text
    assert '"ITW_CLASH_PlayerArtilleryAimRadius",150' in text
    assert '"ITW_CLASH_PlayerArtilleryImpactAcceptanceRadius",250' in text
    assert 'acceptanceRadiusInvisible=%3' in text
    assert 'setMarkerSize [_targetRadius,_targetRadius]' in text
    assert 'setMarkerSize [250,250]' not in text


def test_side_marker_is_removed_through_existing_terminal_cleanup() -> None:
    text = source("ITW_CLASH_PlayerArtillerySideMarker.sqf")

    assert 'ITW_CLASH_PlayerArtillerySideMarker_fnc_ClearClientAssignmentBase =' in text
    assert 'ITW_CLASH_PlayerArtillery_fnc_ClearClientAssignment;' in text
    assert 'ITW_CLASH_PlayerArtillery_fnc_ClearClientAssignment = {' in text
    assert 'deleteMarker _markerName;' in text
    assert '_job deleteAt "sideTargetAreaMarker";' in text
    assert '[_group,_jobId] call ITW_CLASH_PlayerArtillerySideMarker_fnc_Clear;' in text


def test_marker_name_has_no_channel_separator_characters() -> None:
    text = source("ITW_CLASH_PlayerArtillerySideMarker.sqf")

    assert '"ITW_CLASH_ARTY_SIDE_" + ((_jobId splitString "-") joinString "_")' in text
    marker_function = text.split(
        "ITW_CLASH_PlayerArtillerySideMarker_fnc_Name = {", 1
    )[1].split("};", 1)[0]
    assert '"/"' not in marker_function
