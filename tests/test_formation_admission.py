from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def function_body(source: str, name: str) -> str:
    marker = f"{name} = {{"
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    in_string = False
    i = brace
    while i < len(source):
        ch = source[i]
        if ch == '"':
            if in_string and i + 1 < len(source) and source[i + 1] == '"':
                i += 2
                continue
            in_string = not in_string
        elif not in_string:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return source[start : i + 1]
        i += 1
    raise AssertionError(f"unterminated function {name}")


def test_formation_admission_loads_after_dual_hal_hardening_before_runtime_consumers():
    init = mission("init.sqf")

    dual = 'call compile preprocessFileLineNumbers "ITW_CLASH_DualHALCheckbook.sqf"'
    hardened = 'call compile preprocessFileLineNumbers "ITW_CLASH_DualHALCheckbookHardening.sqf"'
    admission = '"ITW_CLASH_FormationAdmission.sqf"'
    api = 'call compile preprocessFileLineNumbers "ITW_CLASH_CheckbookAPI.sqf"'

    assert dual in init
    assert hardened in init
    assert admission in init
    assert api in init
    assert init.index(dual) < init.index(hardened) < init.index(admission) < init.index(api)


def test_runtime_existing_field_requires_a_membership_stability_window():
    source = mission("ITW_CLASH_FormationAdmission.sqf")
    gate = function_body(source, "ITW_CLASH_FormationAdmission_fnc_Gate")

    assert '"runtime-existing-field"' in gate
    assert "ITW_CLASH_FormationAdmissionStableSeconds" in gate
    assert "ITW_CLASH_FormationAdmissionSignature" in gate
    assert "ITW_CLASH_FormationAdmissionStableSince" in gate
    assert '"membership-unstable"' in gate
    assert '"membership-stable"' in gate

    # The exact spawn-race states seen in the RPT must prevent admission.
    transition = function_body(
        source, "ITW_CLASH_FormationAdmission_fnc_TransitionReason"
    )
    assert "assignedVehicle _x" in transition
    assert "currentCommand _x" in transition
    assert '"ITW_CLASH_VehicleCrewGroup",false' in transition
    assert '"ITW_CLASH_VehicleCrewUnit",false' in transition
    assert '"itwInitGrp",false' in transition


def test_impasse_transport_fragments_are_banked_below_four_not_given_to_hal():
    source = mission("ITW_CLASH_FormationAdmission.sqf")
    gate = function_body(source, "ITW_CLASH_FormationAdmission_fnc_Gate")
    bank = function_body(source, "ITW_CLASH_FormationAdmission_fnc_Bank")
    issue = function_body(source, "ITW_CLASH_FormationAdmission_fnc_IssueBank")

    assert 'ITW_CLASH_FormationAdmissionMinCombatSize",4' in source
    assert '"legacy-impasse-cargo-staged"' in gate
    assert "ITW_CLASH_FormationAdmission_fnc_Bank" in gate
    assert '"BANKED","below-minimum-combat-size"' in gate

    assert 'setVariable ["ITW_CLASH_DeploymentRemnant",true,true]' in bank
    assert 'setVariable ["ITW_CLASH_ExcludeHAL",true,true]' in bank
    assert '"remnant-banked"' in bank

    assert "count _bank >= ITW_CLASH_FormationAdmissionMinCombatSize" in issue
    assert '"deployment-remnant-provisional"' in issue
    assert 'setVariable ["ITW_CLASH_ProvisionalFormation",true,true]' in issue
    assert '"remnant-issued"' in issue


def test_archetype_is_only_locked_after_the_admission_gate_allows_the_group():
    source = mission("ITW_CLASH_FormationAdmission.sqf")
    wrapper = function_body(source, "ITW_CLASH_DualHAL_fnc_RegisterGroup")

    assert "ITW_CLASH_FormationAdmission_fnc_Gate" in wrapper
    assert 'if (_state != "ALLOW") exitWith {false};' in wrapper
    assert "ITW_CLASH_FormationAdmission_fnc_RegisterGroupBase" in wrapper
    assert wrapper.index("ITW_CLASH_FormationAdmission_fnc_Gate") < wrapper.index(
        "ITW_CLASH_FormationAdmission_fnc_RegisterGroupBase"
    )
    assert '"archetype-locked"' in wrapper
    assert '"admitted"' in wrapper


def test_specialist_teams_are_not_forced_into_the_four_man_bank():
    source = mission("ITW_CLASH_FormationAdmission.sqf")
    specialist = function_body(
        source, "ITW_CLASH_FormationAdmission_fnc_IsSpecialist"
    )

    for pool in (
        "RHQ_Snipers",
        "RHQ_Recon",
        "RHQ_SpecFor",
        "RHQ_FO",
        "RHQ_ATInf",
        "RHQ_AAInf",
    ):
        assert f'"{pool}"' in specialist

    gate = function_body(source, "ITW_CLASH_FormationAdmission_fnc_Gate")
    assert '["ALLOW","specialist"]' in gate


def test_loud_assertions_cover_fresh_singletons_and_missed_shattered_squads():
    source = mission("ITW_CLASH_FormationAdmission.sqf")
    audit = function_body(source, "ITW_CLASH_FormationAdmission_fnc_Audit")

    assert '"CLASH ASSERT | %1 | %2"' in source
    assert '"ILLEGAL-INFANTRY-FORMATION"' in audit
    assert '"SHATTERED-NOT-WITHDRAWING"' in audit
    assert "ITW_CLASH_FormationAdmissionAssertRepeat" in audit
    assert 'getVariable ["RydHQ_AttackAv",[]]' in audit
    assert 'getVariable ["RydHQ_CombatAv",[]]' in audit


def test_formation_admission_debug_stream_is_event_driven_and_explicit():
    source = mission("ITW_CLASH_FormationAdmission.sqf")

    for event in (
        "admission-pending",
        "membership-unstable",
        "membership-stable",
        "archetype-locked",
        "admitted",
        "remnant-banked",
        "remnant-issued",
    ):
        assert f'"{event}"' in source

    assert "formation-admission-ready" in source
    assert "loudDebug=true" in source
