"""Source-level contracts for the optional ACE AA threat map.

These tests intentionally do not pretend to execute SQF/Arma config lookups.
Live modded-weapon range and MP replication still require an in-game test.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
OVERLAY = MISSION / "ITW_CLASH_AirThreatOverlay.sqf"


def body(name: str) -> str:
    source = OVERLAY.read_text(encoding="utf-8")
    start = source.index(f"{name} = {{")
    depth = 0
    at = source.index("{", start)
    for index in range(at, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError(f"unterminated {name}")


def test_client_and_server_load_from_init_without_replacing_hal():
    init = (MISSION / "init.sqf").read_text(encoding="utf-8")
    assert "ITW_CLASH_AirThreatOverlay.sqf" in init
    assert '[] execVM "ITW_CLASH_AirThreatOverlay.sqf"' in init
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_AirThreatOverlay.sqf"' in init
    assert init.index('"ITW_CLASH_AirPicture.sqf"') < init.index(
        'call compile preprocessFileLineNumbers "ITW_CLASH_AirThreatOverlay.sqf"'
    )


def test_read_only_side_scoped_server_payload():
    source = OVERLAY.read_text(encoding="utf-8")
    for forbidden in (
        "createVehicle", "doMove", "addWaypoint", "setWaypoint",
        "RydHQ_Order", "reveal ", "setVariable [\"RydHQ",
        "publicVariable ",
    ):
        assert forbidden not in source, forbidden
    assert '(_hq getVariable ["RydHQ_KnEnemies",[]])' in source
    assert 'ITW_CLASH_AirPicture_fnc_Denials' in source
    assert 'ITW_CLASH_AirPicture_fnc_Observers' in source
    assert 'side group _x == _side' in source
    assert 'remoteExecCall ["ITW_CLASH_AirThreatOverlay_fnc_Receive",_x]' in source
    assert "remoteExecutedOwner != 2" in source


def test_report_does_not_follow_real_enemy_position():
    source = OVERLAY.read_text(encoding="utf-8")
    assert "targetKnowledge _target" in body(
        "ITW_CLASH_AirThreatOverlay_fnc_Perceived"
    )
    # No direct position query on a live hostile can be used by this overlay.
    assert "getPosATL _veh" not in source
    assert "getPosASL" not in source
    assert "_lastSeen < time - 180" in source
    assert "ITW_CLASH_AirThreatOverlayMobileMemory" in source
    assert "ITW_CLASH_AirThreatOverlayStaticMemory" in source


def test_longest_available_aa_weapon_range_is_used():
    range_body = body("ITW_CLASH_AirThreatOverlay_fnc_Range")
    for field in ("missileLockMaxDistance", "maxControlRange", "maxRange"):
        assert field in range_body
    assert "CfgMagazines" in range_body
    assert "CfgAmmo" in range_body
    assert "CfgWeapons" in range_body
    assert "_best = _best max _range" in range_body
    assert "ITW_CLASH_AirThreatOverlayMargin" in range_body
    assert "_best = if (_radar) then {12000} else {8000}" in range_body
    assert "maxSpeed" not in range_body and "timeToLive" not in range_body


def test_ace_toggle_and_map_markers_are_client_local_only():
    source = OVERLAY.read_text(encoding="utf-8")
    assert "ace_interact_menu_fnc_createAction" in source
    assert "ace_interact_menu_fnc_addActionToObject" in source
    assert '["ACE_SelfActions"]' in source
    assert "Show AirThreats" in source and "Hide AirThreats" in source
    assert "createMarkerLocal" in body("ITW_CLASH_AirThreatOverlay_fnc_Render")
    assert "deleteMarkerLocal" in body("ITW_CLASH_AirThreatOverlay_fnc_Clear")
    assert 'setMarkerBrushLocal' in source
    assert 'setMarkerAlphaLocal' in source
    assert "createMarker [" not in source
    assert "setMarkerPos " not in source
