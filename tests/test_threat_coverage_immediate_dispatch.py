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


def test_purchase_is_immediately_handed_to_native_hal_attack_logic():
    text = source()
    assert 'ITW_CLASH_HALThreatCoverage_fnc_DispatchPurchased' in text
    assert '_group setVariable ["Busy" + str _group,true];' in text
    assert '"RydHQ_AttackAv",' in text
    assert '[_pattern] call RYD_GoLaunch' in text
    assert '[[_group,_target,_hq],_launcher] call RYD_Spawn;' in text


def test_ground_and_air_purchase_patterns_match_hal_native_dispatch():
    text = source()
    assert 'case "TANK": {"ARM"};' in text
    assert 'case "CAR": {"INF"};' in text
    assert 'if (toUpperANSI _kind == "AIR") then {"AIRCAP"} else {"AIR"}' in text


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
