from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def source() -> str:
    return (MISSION / "ITW_CLASH_HALThreatCoverage.sqf").read_text(
        encoding="utf-8", errors="replace"
    )


def test_purchased_combat_asset_keeps_the_triggering_threat():
    text = source()
    assert '["_targetGroup",grpNull]' in text
    assert '["threatGroup",_targetGroup]' in text
    assert '["threatKind",_kind]' in text
    assert 'getPosATL (vehicle (leader _targetGroup))' in text


def test_purchase_is_immediately_offered_to_hal_dispatchers():
    text = source()
    assert 'ITW_CLASH_HALThreatCoverage_fnc_DispatchPurchased' in text
    assert '_attackAv pushBackUnique _group;' in text
    assert 'call RYD_Dispatcher;' in text
    assert 'call CLASH_fnc_HALAdd_Respond;' in text
    assert '"hal-selected"' in text
    assert '"immediate-ready"' in text


def test_native_handoff_preserves_hals_risk_tables():
    text = source()
    assert 'case "ATInf": {[0,0,85]};' in text
    assert 'case "Inf": {[75,80,85]};' in text
    assert 'case "Armor": {[50,0,85]};' in text
    assert 'case "Art": {[70,75,75]};' in text
    assert 'case "Air": {[0,0,75]};' in text
    assert 'private _nativeKinds = ["ATInf","Inf","Armor","Cars","Art","Static","Air"];' in text


def test_busy_committed_responder_counts_as_coverage():
    text = source()
    assert 'ITW_CLASH_ThreatCoverageCommitments = createHashMap;' in text
    assert 'ITW_CLASH_HALThreatCoverage_fnc_CommitmentActive' in text
    assert '_responder getVariable ["Busy" + str _responder,false]' in text
    assert 'ITW_CLASH_ThreatCoverageCommitmentTimeout' in text
    assert 'ITW_CLASH_ThreatCoverageCommitments deleteAt _key;' in text
    assert '!([_hq,_x,_kind] call' in text
    assert '!([_hq,_x,"Air"] call' in text


def test_immediate_handoff_version_and_boot_log_are_explicit():
    text = source()
    assert 'ITW_CLASH_HALThreatCoverageVersion = 5;' in text
    assert 'immediateHALHandoff=true' in text
    assert 'activeCommitmentCoverage=true' in text
