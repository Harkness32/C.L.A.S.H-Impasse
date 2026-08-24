from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_service_home_is_resolved_from_live_impasse_bases():
    text = mission("ITW_CLASH_ServiceHomeResolver.sqf")

    assert 'ITW_CLASH_ServiceHomeRevalidateInterval' in text
    assert '"ITW_CLASH_ServiceHomeRevalidateInterval",120' in text
    assert '"ITW_CLASH_ServiceHomeChangeThreshold",200' in text
    assert 'ITW_BASE_SPAWNED' in text
    assert 'ITW_OBJ_OWNER' in text
    assert 'ITW_OBJ_INDEX' in text
    assert '"request-base"' in text
    assert '"nearest-base"' in text
    assert '"water-node"' in text
    assert '"fallback-start"' in text
    assert 'ITW_CLASH_SeaGuard_fnc_ResolveWaterPosition' in text


def test_service_home_resolution_is_load_bearing_and_write_through():
    text = mission("ITW_CLASH_ServiceHomeResolver.sqf")

    assert '_entry set ["homeResolvedAt",time];' in text
    assert '_entry set ["homeResolvedPos",+_position];' in text
    assert '_entry set ["homeBaseIndex",_baseIndex];' in text
    assert '_entry set ["homeMethod",_method];' in text
    assert '_entry set ["home",+_position];' in text
    assert '_group setVariable ["START" + str _group,+_position];' in text
    assert '_group setVariable ["ITW_CLASH_ServiceHome",+_position];' in text
    assert '["resolved",[' in text
    assert '["no-friendly-base",[' in text


def test_rtb_resolves_at_order_and_revalidates_while_progressing():
    text = mission("ITW_CLASH_ServiceHomeResolver.sqf")

    assert 'ITW_CLASH_ServiceHome_fnc_OrderRTBBase = ITW_CLASH_Service_fnc_OrderRTB;' in text
    assert '"order-rtb:" + _reason' in text
    assert 'ITW_CLASH_ServiceHome_fnc_ReissueRTBBase = ITW_CLASH_Service_fnc_ReissueRTB;' in text
    assert 'ITW_CLASH_ServiceHome_fnc_RefreshRTB' in text
    assert 'time - _resolvedAt >= ITW_CLASH_ServiceHomeRevalidateInterval' in text
    assert '_oldPosition distance2D _newPosition >= ITW_CLASH_ServiceHomeChangeThreshold' in text
    assert '["refreshed-no-waypoint-change",[' in text
    assert '["waypoint-changed",[' in text


def test_registration_cannot_clobber_resolver_written_home():
    text = mission("ITW_CLASH_ServiceHomeResolver.sqf")

    assert 'ITW_CLASH_ServiceHome_fnc_RegisterPhysicalBase = ITW_CLASH_Service_fnc_RegisterPhysical;' in text
    assert 'private _previousResolvedAt' in text
    assert 'private _previousResolvedPos' in text
    assert '_previousResolvedAt > 0' in text
    assert '_entry set ["home",+_previousResolvedPos];' in text
    assert '_entry set ["deploymentOrigin",+_rawHome];' in text
    assert '_entry set ["homeAuthority","UNRESOLVED"]' in text


def test_base_hint_is_reference_not_coordinate_snapshot():
    text = mission("ITW_CLASH_ServiceHomeResolver.sqf")

    assert 'ITW_CLASH_ServiceHome_fnc_SetBaseHint' in text
    assert '"ITW_CLASH_ServiceBaseHint"' in text
    assert '_entry set ["baseHint",_baseIndex];' in text
    assert '"transport-registration"' in text
    assert '"generated-service-registration"' in text
    assert '"field-handoff"' in text


def test_home_resolver_is_loaded_after_seaguard_path_starts():
    loader = mission("ITW_CLASH_ServiceExecutionGuards.sqf")
    assert '[] execVM "ITW_CLASH_ServiceHomeResolver.sqf";' in loader
    resolver = mission("ITW_CLASH_ServiceHomeResolver.sqf")
    assert 'missionNamespace getVariable ["ITW_CLASH_SeaGenerationGuardReady",false]' in resolver


def test_ownership_contract_carries_general_rule():
    doc = (ROOT / "docs" / "OWNERSHIP_CONTRACT.md").read_text(encoding="utf-8")
    assert "No system stores another system's answer; it stores the question, and asks at use time." in doc
    assert "homeResolvedAt" in doc
    assert "load-bearing" in doc
    assert "SeaGuard answers where a hull can float; it does not own home selection." in doc
