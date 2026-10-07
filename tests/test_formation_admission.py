from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def src(name):
    return (MISSION / name).read_text(encoding="utf-8")


def fn(code, name):
    marker = name + " = {"
    assert marker in code, name
    start = code.index(marker)
    end = code.index("\n};", start)
    return code[start : end + 3]


def test_boot_order_and_no_native_hal_edits():
    init = src("init.sqf")
    assert init.index('"ITW_CLASH_DualHALCheckbookHardening.sqf"') < init.index(
        '"ITW_CLASH_FormationAdmission.sqf"'
    ) < init.index('"ITW_CLASH_CheckbookAPI.sqf"')
    assert "formation-admission-missing-or-prereq-failed" in init


def test_native_producer_writes_intent_before_cap_cutoff():
    attack = src("ITW_Attack.sqf")
    start = attack.index("//// Infantry AI Spawner ////")
    end = attack.index("//// Delivery Troops ////", start)
    producer = attack[start:end]
    assert "private _plannedSquadTemplate = [];" in producer
    assert "_plannedSquadTemplate = +_squad;" in producer
    assert 'ITW_CLASH_ProducerSquadSerial' in producer
    assert '"ITW_CLASH_ProducerPlannedTemplate"' in producer
    assert '"ITW_CLASH_ProducerBatch"' in producer
    assert producer.index("_plannedSquadTemplate = +_squad;") < producer.index(
        "_squad deleteAt 0"
    )
    assert producer.index("ITW_CLASH_ProducerPlannedTemplate") < producer.index(
        "_newSquads pushBack [_unit];"
    )
    assembled = fn(attack, "ITW_AtkAddInfantryGroup")
    assert '"ITW_CLASH_ProducedStrength"' in assembled
    assert '"ITW_CLASH_ProducedIntent"' in assembled
    assert '"ITW_CLASH_ProducedBatch"' in assembled
    assert "producer-cap-fragment" in assembled
    assert assembled.index("ITW_CLASH_ProducedStrength") < assembled.index(
        "ITW_CLASH_Archetype"
    )


def test_every_friendly_primary_field_handoff_is_preflighted():
    dual = src("ITW_CLASH_DualHALCheckbook.sqf")
    stage = fn(dual, "ITW_CLASH_DualHAL_fnc_StageFriendlyInfantry")
    assert '"impasse-spawn-support-corridor",_spawnInfo' in stage
    assert 'if (_state == "BANKED") exitWith {true};' in stage
    assert 'if (_state != "ALLOW") exitWith {' in stage
    assert 'isNil "ITW_CLASH_FormationAdmission_fnc_Gate"' in stage

    # Registration must complete before a SINGLE native waypoint / position
    # mutation. HAL tasking is disabled between registration and staging.
    preflight = stage.index("ITW_CLASH_FormationAdmission_fnc_Gate")
    hold = stage.index('setVariable ["Unable",true]')
    committed = stage.index("] call ITW_CLASH_DualHAL_fnc_RegisterGroup;")
    first_move = stage.index("[_group,_staging] call ITW_AtkSafeMove;")
    clear = stage.index("{deleteWaypoint _x}")
    assert preflight < hold < committed < first_move < clear
    assert 'if (!_registered) exitWith {' in stage
    assert 'setVariable ["Unable",nil]' in stage
    assert 'setVariable ["BUnable",nil]' in stage


def test_runtime_scan_never_erases_pending_or_withdrawal_waypoints():
    dual = src("ITW_CLASH_DualHALCheckbook.sqf")
    scan = dual.split('call ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives;', 1)[1]
    candidate = scan.split('call ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles;', 1)[0]
    assert 'isNil "ITW_CLASH_FormationAdmission_fnc_Gate"' in candidate
    assert '[_group,"runtime-existing-field"]' not in candidate or (
        "runtime-existing-field" in candidate
    )
    assert "private _admitted =" in candidate
    assert 'if (_admitted && {!isNull _group} && {' in candidate
    assert '"ITW_CLASH_Withdrawing",false' in candidate
    assert candidate.index('call ITW_CLASH_DualHAL_fnc_RegisterGroup;') < (
        candidate.index('{deleteWaypoint _x}')
    )


def test_runtime_stability_blocks_entire_function_on_pending():
    module = src("ITW_CLASH_FormationAdmission.sqf")
    stable = fn(module, "ITW_CLASH_FormationAdmission_fnc_RuntimeStability")
    gate = fn(module, "ITW_CLASH_FormationAdmission_fnc_Gate")
    assert "ITW_CLASH_FormationAdmissionStableSeconds" in stable
    assert "ITW_CLASH_FormationAdmissionSignature" in stable
    assert "ITW_CLASH_FormationAdmissionStableSince" in stable
    assert '"membership-unstable"' in stable
    assert '"membership-stable"' in stable
    assert '"PENDING","stability-window"' in stable
    assert 'if ((_stability#0) != "ALLOW") exitWith {_stability};' in gate
    assert gate.index("ITW_CLASH_FormationAdmission_fnc_TransitionReason") < (
        gate.index("ITW_CLASH_FormationAdmission_fnc_IsSpecialist")
    )


def test_transitional_vehicle_and_specialist_guards():
    module = src("ITW_CLASH_FormationAdmission.sqf")
    transition = fn(module, "ITW_CLASH_FormationAdmission_fnc_TransitionReason")
    for token in (
        '"ITW_CLASH_VehicleCrewGroup",false',
        '"ITW_CLASH_VehicleCrewUnit",false',
        '"itwInitGrp",false',
        '"itwDelivery",false',
        'assignedVehicle _x',
        'currentCommand _x',
    ):
        assert token in transition
    specialist = fn(module, "ITW_CLASH_FormationAdmission_fnc_IsSpecialist")
    for pool in ("RHQ_Snipers", "RHQ_Recon", "RHQ_SpecFor", "RHQ_ATInf"):
        assert pool in specialist
    gate = fn(module, "ITW_CLASH_FormationAdmission_fnc_Gate")
    assert '["ALLOW","specialist"]' in gate
    assert '["ALLOW","attrited-preexisting-archetype"]' in gate
    assert '["PENDING","unknown-small-group-provenance"]' in gate


def test_vehicle_cargo_preview_before_mutating_vehicle():
    dual = src("ITW_CLASH_DualHALCheckbook.sqf")
    stage = fn(dual, "ITW_CLASH_DualHAL_fnc_StageFieldVehicle")
    assert 'isNil "ITW_CLASH_FormationAdmission_fnc_CargoPreflight"' in stage
    assert "ITW_CLASH_FormationAdmission_fnc_CargoPreflight" in stage
    assert 'if (_cargoPreflightFailed) exitWith {' in stage
    assert stage.index("ITW_CLASH_FormationAdmission_fnc_CargoPreflight") < (
        stage.index("ALLOW_DAMAGE(_veh,false)")
    )
    assert 'setVariable ["ITW_CLASH_FormationAdmissionContext"' in stage or (
        '"ITW_CLASH_FormationAdmissionContext",+_spawnInfo' in stage
    )
    assert '"legacy-impasse-cargo-staged"' in stage


def test_bank_keys_include_support_node_and_snapshots_are_transactional():
    module = src("ITW_CLASH_FormationAdmission.sqf")
    bank = fn(module, "ITW_CLASH_FormationAdmission_fnc_Bank")
    issue = fn(module, "ITW_CLASH_FormationAdmission_fnc_IssueBank")
    assert '"%1|base:%2"' in bank
    assert '"%1|zone:%2|objective:%3"' in bank
    assert '"runtime-existing-field"' in bank
    assert '"support-node-unavailable"' in bank
    assert "getUnitLoadout _x" in bank
    assert "rank _x" in bank
    assert "speaker _x" in bank
    assert 'setVariable ["ITW_CLASH_DeploymentRemnant",true,true]' in bank
    assert '"remnant-banked"' in bank
    assert '"deployment-remnant-provisional"' in issue
    assert "count _records >= ITW_CLASH_FormationAdmissionMinCombatSize" in issue
    assert "if (_accepted) then {" in issue
    assert issue.index("if (_accepted) then {") < issue.index(
        "_records deleteRange"
    )
    assert '["remnant-issue-deferred"' in issue
    assert "deleteVehicle _x" in issue
    assert "ITW_CLASH_FormationAdmissionBanks set [_key,_entry]" in issue


def test_shattered_admission_withdrawal_before_hal_task_cycle():
    module = src("ITW_CLASH_FormationAdmission.sqf")
    immediate = fn(module, "ITW_CLASH_FormationAdmission_fnc_ImmediateShattered")
    wrapper = fn(module, "ITW_CLASH_DualHAL_fnc_RegisterGroup")
    stage = fn(src("ITW_CLASH_DualHALCheckbook.sqf"),
               "ITW_CLASH_DualHAL_fnc_StageFriendlyInfantry")
    for token in (
        "ITW_CLASH_FormationRecoveryMaxShatteredSurvivors",
        "ITW_CLASH_FormationRecoveryMaxShatteredFraction",
        "ITW_CLASH_fnc_StartWithdrawal",
        '"admission-pre-shattered"',
    ):
        assert token in immediate
    assert "ITW_CLASH_FormationAdmission_fnc_ImmediateShattered" in wrapper
    assert "ITW_CLASH_FormationAdmission_fnc_ImmediateShattered" in stage


def test_loud_logging_and_periodic_invariant_audit():
    module = src("ITW_CLASH_FormationAdmission.sqf")
    audit = fn(module, "ITW_CLASH_FormationAdmission_fnc_Audit")
    for event in (
        "admission-pending",
        "membership-unstable",
        "membership-stable",
        "archetype-locked",
        "admitted",
        "remnant-banked",
        "remnant-issued",
        "remnant-issue-deferred",
        "ILLEGAL-INFANTRY-FORMATION",
        "SHATTERED-NOT-WITHDRAWING",
        "SHATTERED-ADMISSION-WITHDRAWAL-FAILED",
    ):
        assert event in module
    assert '"RydHQ_AttackAv"' in audit
    assert '"RydHQ_CombatAv"' in audit
    assert "ITW_CLASH_FormationAdmissionAssertRepeat" in audit
    assert "formation-admission-ready" in module

def test_enemy_native_cap_tail_is_banked_before_impasse_orders():
    attack = src("ITW_Attack.sqf")
    native = fn(attack, "ITW_AtkAddInfantryGroup")
    module = fn(
        src("ITW_CLASH_FormationAdmission.sqf"),
        "ITW_CLASH_FormationAdmission_fnc_Gate",
    )
    assert '"impasse-native-enemy-onfoot"' in native
    assert '"impasse-native-enemy-onfoot"' in module
    assert '"ITW_CLASH_ProducedBatch"' in native
    assert "side _group == ITW_EnemySide" in native
    assert "if (_enemyBanked) exitWith {true};" in native
    assert native.index("if (_enemyBanked) exitWith {true};") < native.index(
        "[_group,_teleportToAttackPos,_objToPopulate] call ITW_AtkEngageInfantry;"
    )
    enemy = fn(
        src("ITW_CLASH_SpawnArchetypePreInit.sqf"),
        "ITW_EnemyGroupCallback",
    )
    assert "if (isNull _group) exitWith {};" in enemy
    assert enemy.index("if (isNull _group) exitWith {};") < enemy.index(
        "ITW_EnemyGroups pushBack _group;"
    )


def test_enemy_transport_fragments_bank_without_reentering_hal_callback():
    stage = fn(
        src("ITW_CLASH_DualHALCheckbook.sqf"),
        "ITW_CLASH_DualHAL_fnc_StageFieldVehicle",
    )
    assert '"ITW_EnemySide"' in stage
    assert '"legacy-impasse-cargo-staged",_spawnInfo' in stage
    assert 'ITW_CLASH_FormationAdmission_fnc_Bank' in stage
    assert 'if (_enemyCargoBanked) then {' in stage
    assert 'ITW_EnemyGroups = ITW_EnemyGroups - [_cargoGroup];' in stage
    assert stage.index('if (_enemyCargoBanked) then {') < stage.index(
        '[_cargoGroup] call ITW_EnemyGroupCallback;'
    )
    assert 'ITW_CLASH_FormationAdmission_fnc_CargoPreflight' in stage
