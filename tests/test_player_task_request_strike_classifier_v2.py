from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def source(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_boot_loads_strike_classifier_after_base_adapter() -> None:
    text = source("ITW_CLASH_PlayerTaskRequestBootstrap.sqf")
    base = '"STRIKE","ITW_CLASH_PlayerTaskRequestStrike.sqf"'
    layer = '"ITW_CLASH_PlayerTaskRequestStrikeClassifierV2.sqf"'
    assert base in text
    assert layer in text
    assert text.index(base) < text.index(layer)
    assert "strikeClassifierV2=true" in text


def test_v2_uses_only_hal_known_contacts_as_candidate_source() -> None:
    text = source("ITW_CLASH_PlayerTaskRequestStrikeClassifierV2.sqf")

    assert 'getVariable ["RydHQ_KnEnemiesG",[]]' in text
    assert 'getVariable ["RydHQ_KnEnemies",[]]' in text
    assert "ITW_CLASH_PlayerTaskRequestStrike_fnc_KnownGroups" in text
    assert "forEach _known" in text

    for forbidden in (
        "allUnits",
        "allGroups",
        "nearEntities",
        "nearestObjects",
        "reveal ",
        "RydHQ_EnHArmorG",
        "RydHQ_EnMArmorG",
        "RydHQ_EnLArmorG",
        "RydHQ_EnInfG",
    ):
        assert forbidden not in text


def test_v2_classifies_known_groups_from_native_rhq_taxonomy() -> None:
    text = source("ITW_CLASH_PlayerTaskRequestStrikeClassifierV2.sqf")

    for token in (
        '"RHQ_HArmor","RYD_WS_HArmor_class","RHQs_HArmor"',
        '"RHQ_MArmor","RYD_WS_MArmor_class","RHQs_MArmor"',
        '"RHQ_LArmor","RYD_WS_LArmor_class","RHQs_LArmor"',
        '"RHQ_LArmorAT","RYD_WS_LArmorAT_class","RHQs_LArmorAT"',
        '"RHQ_Inf","RYD_WS_Inf_class","RHQs_Inf"',
        '"RHQ_Static","RYD_WS_Static_class","RHQs_Static"',
        '"RHQ_Cars","RYD_WS_Cars_class","RHQs_Cars"',
        '"RHQ_Art","RYD_WS_Art_class","RHQs_Art"',
        '"RHQ_Support","RYD_WS_Support_class","RHQs_Support"',
        '"RHQ_Cargo","RYD_WS_Cargo_class","RHQs_Cargo"',
        '"RHQ_NCCargo","RYD_WS_NCCargo_class","RHQs_NCCargo"',
        "toLower (typeOf _unit)",
        "toLower (typeOf _vehicle)",
    ):
        assert token in text

    assert 'if ((_types arrayIntersect _heavy) isNotEqualTo [])' in text
    assert 'if ((_types arrayIntersect _light) isNotEqualTo [])' in text
    assert 'if ((_types arrayIntersect _soft) isNotEqualTo [])' in text


def test_v2_does_not_promote_passenger_infantry_to_carrier_class() -> None:
    text = source("ITW_CLASH_PlayerTaskRequestStrikeClassifierV2.sqf")

    assert "driver _vehicle" in text
    assert "gunner _vehicle" in text
    assert "commander _vehicle" in text
    assert "group _driver == _group" in text
    assert "group _gunner == _group" in text
    assert "group _commander == _group" in text
    assert "if (_operatedByGroup) then" in text


def test_v2_preserves_native_nearest_threat_selection_after_classification() -> None:
    text = source("ITW_CLASH_PlayerTaskRequestStrikeClassifierV2.sqf")

    assert "distance2D _hqVehicle" in text
    assert "private _best = _candidates#0;" in text
    selector = text[text.index("ITW_CLASH_PlayerTaskRequestStrike_fnc_SelectTarget = {"):]
    assert "random" not in selector.lower()
    assert "rating" not in selector.lower()


def test_v2_logs_classification_and_no_candidate_breakdown() -> None:
    text = source("ITW_CLASH_PlayerTaskRequestStrikeClassifierV2.sqf")

    assert '"target-classified"' in text
    assert '"no-candidate"' in text
    assert '"knEnemiesG",count _knownGroupProjection' in text
    assert '"knEnemies",count _knownObjectProjection' in text
    assert '"knownLiveGroups",count _known' in text
    assert '"heavy",_heavyCount' in text
    assert '"light",_lightCount' in text
    assert '"soft",_softCount' in text
    assert '"unclassified",_unclassifiedCount' in text
    assert '"reserved",_reservedCount' in text
    assert "cachedEnemyCategoryIntersection=false" in text
    assert "omniscientScan=false" in text
