"""Commander supports: the knowledge layer, the core, and the three executors.

See docs/CLASH_CommanderSupports_Model.md. These pin the contracts a review
has to hold the stack to, not the tuning:

- COLOSSUS only proposes, once per assessment, after its own order.
- Decisions read REPORTED positions from the knowledge layer. The HQ group is
  never an observer, and reports are never merged.
- Money, lane and cooldowns are taken in one unscheduled block. Money is spent
  only on delivery or loss; a support that ends with its aircraft alive and
  nothing delivered is refunded in full.
- Support aircraft never enter a HAL pool. The only HAL write in the stack is
  the airborne hand-off's single native order.
- Shadow mode is the default, and airborne is off.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
SUPPORT_FILES = [
    "ITW_CLASH_Supports.sqf",
    "ITW_CLASH_SupportsStrike.sqf",
    "ITW_CLASH_SupportsUAV.sqf",
    "ITW_CLASH_SupportsAirborne.sqf",
]


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def code(name: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", text(name), flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def function_body(source: str, name: str) -> str:
    start = source.index(f"{name} = {{")
    depth = 0
    i = source.index("{", start)
    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1
    raise AssertionError(f"unterminated {name}")


# ------------------------------------------------------------------ knowledge


def test_the_hq_group_is_never_an_observer():
    update = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_Update")
    assert "&& {_x isNotEqualTo _hq}" in update


def test_reports_are_never_merged_the_best_single_report_wins():
    update = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_Update")
    assert "if (_r < _bestR) then {" in update
    assert "_best = _report;" in update
    # No averaging of positions across observers anywhere in the update.
    assert "vectorAdd" not in update
    assert "_position = getPos" not in update


def test_only_the_truth_diagnostic_reads_where_an_enemy_really_is():
    source = code("ITW_CLASH_Knowledge.sqf")
    assert source.count("getPosATL _entity") == 1
    truth = function_body(source, "ITW_CLASH_Knowledge_fnc_TruthSample")
    assert "getPosATL _entity" in truth
    # And what it learns goes to a stats bucket, never back into a record.
    assert "_record set" not in truth


def test_uncertainty_is_error_plus_speed_times_age_and_time_ahead():
    uncertainty = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_Uncertainty")
    assert '((_record getOrDefault ["error",0]) + _speed * (_age + (_ahead max 0))) max ITW_CLASH_KnowledgeMinUncertainty' in uncertainty


def test_clock_anomalies_are_discarded_not_used():
    report = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_ReadReport")
    assert "if (_lastSeen < 0 || {_lastSeen > (time + 1)}) exitWith {" in report


def test_the_air_picture_counts_only_uav_looks_as_eyes():
    observed = code("ITW_CLASH_AirPicture.sqf")
    assert '[side _hq,_destination,-1,["uav"]] call ITW_CLASH_Knowledge_fnc_LookedAt' in observed


# ------------------------------------------------------------------- colossus


def test_colossus_proposes_once_after_its_own_order():
    source = code("ITW_CLASH_Colossus.sqf")
    assert "ITW_CLASH_ColossusVersion = 7;" in source
    assess = function_body(source, "ITW_CLASH_Colossus_fnc_Assess")
    commit = assess.index("call ITW_CLASH_Colossus_fnc_Commit;")
    propose = assess.index("call ITW_CLASH_Supports_fnc_Assess;")
    assert commit < propose
    # The hook is the only thing COLOSSUS knows about supports.
    assert re.findall(r"ITW_CLASH_Supports\w*", source) == [
        "ITW_CLASH_Supports_fnc_Assess",
        "ITW_CLASH_Supports_fnc_Assess",
    ]


def test_reported_positions_start_off_and_are_logged_beside_live():
    source = code("ITW_CLASH_Colossus.sqf")
    assert '"ITW_CLASH_ColossusReportedPositions",false' in source
    assert '["objective-intel",[' in source


# ----------------------------------------------------------------------- core


def test_every_support_is_live_by_default():
    # v3 (Hark, 2026-10-16): unlock all of them. Shadow mode stays one
    # variable away, and each flavor keeps its own switch. v4 keeps that.
    core = code("ITW_CLASH_Supports.sqf")
    assert "ITW_CLASH_SupportsVersion = 7;" in core
    assert '["ITW_CLASH_SupportsDryRun",false]' in core
    for flavor in ["UAV", "Bomb", "Guided", "Carpet", "AirborneHeli", "AirbornePlane", "VehicleDrop"]:
        assert f'["ITW_CLASH_Supports{flavor}Enabled",true]' in core, flavor


def test_shadow_mode_spends_and_holds_the_lane_but_spawns_nothing():
    run = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Run")
    dry = run[run.index('if (_support get "dryRun") exitWith {'):]
    dry = dry[:dry.index("};") + 2]
    assert 'sleep (_support get "nominal");' in dry
    assert '[_support,"DRY_RUN","shadow-spent"] call ITW_CLASH_Supports_fnc_Settle;' in dry
    assert "_fnc_Run" not in dry.replace("ITW_CLASH_Supports_fnc_Run", "")
    # And the executors are reached only after it.
    assert run.index('"dryRun"') < run.index("ITW_CLASH_SupportsUAV_fnc_Run")


def test_admission_reserves_money_lane_and_cooldowns_unscheduled():
    admit = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Admit")
    block = admit[admit.index("isNil {"):admit.index('if (_id isEqualTo "") exitWith {')]
    for needle in (
        '_denied = "LANE_BUSY"',
        '_denied = "COOLDOWN"',
        '_denied = "INSUFFICIENT_FUNDS"',
        # v7: from the pick's own wallet; a test's wallet is never charged.
        '_ledger set [_cashKey,(_ledger getOrDefault [_cashKey,0]) - _price];',
        "_lanes set [_lane,_id];",
        '_cooldowns set ["flavor:" + _flavor',
    ):
        assert needle in block, needle


def test_money_is_spent_only_on_delivery_or_loss():
    settle = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Settle")
    assert 'private _refund = _state in ["REVOKED","BREAKOFF"];' in settle
    # Refunded in full up to the ceiling; what would cross it is clipped and logged.
    # v7: back into the wallet it came from, against that wallet's cap.
    assert "private _after = (_before + _price) min (([_wallet] call ITW_CLASH_Supports_fnc_WalletCap) max _before);" in settle
    assert 'if (_refund && {_wallet isNotEqualTo "TEST"}) then {' in settle
    assert "_clipped = (_before + _price) - _after;" in settle
    assert "round _clipped" in settle
    # The lane is released only by its own holder.
    assert 'if ((_lanes getOrDefault [_lane,""]) isEqualTo _id) then {_lanes set [_lane,""]};' in settle
    # A lost UAV costs its side the next launch for a while.
    assert '_lane isEqualTo "RECON" && {_state isEqualTo "LOST"}' in settle


def test_lanes_so_nothing_blocks_another_family():
    # v7: the UAV, the strikes, the paradrops, deliveries, and the bite-back
    # wave's two parts each hold a lane of their own.
    core = code("ITW_CLASH_Supports.sqf")
    assert ('["RECON",""],["COMMIT",""],["DROP",""],["VEHICLE",""],["BITE_DROP",""],["BITE_VEHICLE",""]') in core
    assert core.count('["lane","RECON"]') == 1
    assert core.count('["lane","COMMIT"]') == 3
    assert core.count('["lane","DROP"]') == 2
    assert core.count('["lane","VEHICLE"]') == 1


def test_save_is_an_option_in_the_same_pool():
    assess = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Assess")
    assert '_pool pushBack (["SAVE","SAVE",-1,"",[],_saveWeight' in assess
    assert '[_context,_posture,_planObjective,_pool,"pool"] call ITW_CLASH_Supports_fnc_Decide;' in assess
    decide = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Decide")
    assert "([_pool] call ITW_CLASH_Supports_fnc_Pick)" in decide


def test_the_pick_is_logged_with_its_draw_in_a_stable_order():
    pick = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Pick")
    assert '[_pool,[],{_x get "key"},"ASCEND"] call BIS_fnc_sortBy' in pick
    assert "private _draw = random _total;" in pick
    assert "[_pick,_draw,_total]" in pick


def test_targets_come_from_the_knowledge_layer_only():
    core = code("ITW_CLASH_Supports.sqf")
    clusters = function_body(core, "ITW_CLASH_Supports_fnc_Clusters")
    assert "call ITW_CLASH_Knowledge_fnc_Contacts" in clusters
    target_now = function_body(core, "ITW_CLASH_Supports_fnc_TargetNow")
    assert "call ITW_CLASH_Knowledge_fnc_Record" in target_now
    assert "getPos" not in target_now
    # The only positions read in the core are our own people's: for danger
    # close, and for which of our formations an enemy is threatening.
    assert core.count("getPosATL") == 2
    assert "private _position = getPosATL _veh;" in function_body(core, "ITW_CLASH_Supports_fnc_Friendlies")
    assert "private _position = getPosATL _veh;" in function_body(core, "ITW_CLASH_Supports_fnc_Committed")


def test_unguided_flavors_never_bomb_a_guess_the_acquiring_ones_are_exempt():
    # v4: the bomb pass acquires on site like the guided pass, so both skip
    # the assessment's uncertainty gate. The bomb's report fallback is still
    # held to the limit at release (test_bomb_acquisition.py); carpet is not
    # exempt at all.
    core = code("ITW_CLASH_Supports.sqf")
    assert 'ITW_CLASH_SupportsAcquireFlavors = ["BOMB","GUIDED"];' in core
    strike = function_body(core, "ITW_CLASH_Supports_fnc_StrikeCandidates")
    assert "if !(_flavor in ITW_CLASH_SupportsAcquireFlavors) then {" in strike
    assert "if (_r > ITW_CLASH_SupportsUncertaintyLimit) exitWith {_multiplier = -1};" in strike
    assert "_multiplier = (_footprint / (_r max 1)) min 1;" in strike


def test_danger_close_ignores_civilians_and_high_aircraft():
    friendlies = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Friendlies")
    assert "if (_ownSide isEqualTo civilian) then {continue};" in friendlies
    assert "if ((_position#2) > ITW_CLASH_SupportsDangerAirHeight) then {continue};" in friendlies


def test_support_aircraft_never_enter_a_hal_pool():
    spawn = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_SpawnAircraft")
    for needle in (
        '_veh setVariable ["ITW_CLASH_SupportAsset",_id,true];',
        '_group setVariable ["ITW_CLASH_SupportAsset",_id];',
        '_group setVariable ["ITW_CLASH_ExcludeHAL",true];',
        '_group setBehaviourStrong "CARELESS";',
        '_group setCombatMode "BLUE";',
        "[_group] call ITW_CLASH_Knowledge_fnc_RegisterSensorGroup;",
    ):
        assert needle in spawn, needle
    assert "RegisterGroup" not in spawn


def test_a_shot_down_aircraft_is_left_to_fall():
    egress = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Egress")
    assert "if (isNull _veh || {!alive _veh}) exitWith {false};" in egress


def test_no_support_jet_carries_air_to_air_missiles():
    for name in ("ITW_CLASH_SupportsStrike.sqf", "ITW_CLASH_SupportsAirborne.sqf"):
        assert "[_veh] call ITW_CLASH_Supports_fnc_StripAirToAir;" in code(name), name


def test_the_only_hal_write_is_the_airborne_native_order():
    for name in SUPPORT_FILES:
        source = code(name)
        for needle in ("HAL_GoCapture", "HAL_GoDef", '"RydHQ_AttackAv"', '"RydHQ_DefSpot"', 'setVariable ["Busy"'):
            if name == "ITW_CLASH_SupportsAirborne.sqf":
                continue
            assert needle not in source, (name, needle)
    airborne = code("ITW_CLASH_SupportsAirborne.sqf")
    order = function_body(airborne, "ITW_CLASH_SupportsAirborne_fnc_NativeOrder")
    rest = airborne.replace(order, "")
    for needle in ("HAL_GoCapture", "HAL_GoDef", '"RydHQ_AttackAv"', '"RydHQ_DefSpot"'):
        assert needle in order, needle
        assert needle not in rest.replace('isNil "HAL_GoCapture"', ""), needle


# --------------------------------------------------------------------- strike


def test_unguided_release_is_by_fall_time_from_the_drop_height():
    strike = code("ITW_CLASH_SupportsStrike.sqf")
    fall = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_FallTime")
    assert "(_vz + sqrt ((_vz * _vz) + (2 * 9.81 * (_height max 1)))) / 9.81" in fall
    lead = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_Lead")
    assert "- ITW_CLASH_SupportsStrikeDropOffset - (getTerrainHeightASL _aim)" in lead
    assert '"ITW_CLASH_SupportsStrikeReleaseBias",0]' in strike


def test_the_jet_is_steered_onto_the_report_never_the_bombs():
    unguided = function_body(code("ITW_CLASH_SupportsStrike.sqf"), "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    approach = unguided.index("_along <= ITW_CLASH_SupportsStrikeApproachUpdate")
    line_up = unguided.index("[_group,_aim,_heading] call ITW_CLASH_SupportsStrike_fnc_LineUp;")
    check = unguided.index("_along <= (_lead - _first + ITW_CLASH_SupportsStrikeCheckLead)")
    assert approach < line_up < check
    # What is left off the line at the final check is a miss or a break-off.
    # v5: held to the flavor's own limit (the bomb's footprint); console test
    # passes keep the old 250 m.
    assert 'if (_wide > _crossLimit) exitWith {_result = ["BREAKOFF","passed-wide"]};' in unguided
    # The pass itself never creates a bomb: only the per-frame release does.
    assert "fnc_DropBomb" not in unguided


def test_bombs_leave_the_aircraft_with_its_velocity_credited_to_it():
    drop = function_body(code("ITW_CLASH_SupportsStrike.sqf"), "ITW_CLASH_SupportsStrike_fnc_DropBomb")
    assert "_bomb setShotParents [_veh,driver _veh];" in drop
    assert "private _velocity = velocity _veh;" in drop
    assert "_bomb setVelocity _velocity;" in drop
    # Created at the aircraft: its own position, its lateral slot, the drop offset.
    assert "private _position = (getPosASL _veh)" in drop


def test_release_runs_every_frame_and_skips_rather_than_conjures():
    strike = code("ITW_CLASH_SupportsStrike.sqf")
    unguided = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    assert 'addMissionEventHandler ["EachFrame",ITW_CLASH_SupportsStrike_fnc_ReleaseFrame,[_state]]' in unguided
    # Removing the handler is unscheduled, so it cannot race the handler.
    removal = unguided[unguided.index("isNil {"):]
    assert 'removeMissionEventHandler ["EachFrame",_handler];' in removal[:300]
    frame = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_ReleaseFrame")
    assert "if (_overshoot > ITW_CLASH_SupportsStrikeSkipDistance) then {" in frame
    assert "[_veh,_lateral,_state,_next,_overshoot] call ITW_CLASH_SupportsStrike_fnc_DropBomb;" in frame
    assert frame.count('removeMissionEventHandler ["EachFrame",_thisEventHandler];') == 3


def test_every_bomb_is_measured_against_the_model_and_the_pattern():
    strike = code("ITW_CLASH_SupportsStrike.sqf")
    drop = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_DropBomb")
    assert '_bomb addEventHandler ["Explode",ITW_CLASH_SupportsStrike_fnc_Impact];' in drop
    assert "(productVersion param [2,0]) >= 210" in drop
    impact = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_Impact")
    assert '([_predicted,_position,_track] call _split) params ["_modelAlong","_modelCross"];' in impact
    assert '([_intended,_position,_heading] call _split) params ["_aimAlong","_aimCross"];' in impact
    # The bomb's ballistic config is logged at boot, beside the impacts.
    assert 'getNumber (_bombConfig >> "airFriction")' in strike


def test_the_guided_pass_acquires_on_site_and_breaks_off_empty():
    guided = function_body(code("ITW_CLASH_SupportsStrike.sqf"), "ITW_CLASH_SupportsStrike_fnc_GuidedPass")
    assert "getSensorTargets _veh" in guided
    assert '["BREAKOFF","no-target-found"]' in guided
    # fireAtTarget first; a steered missile only as the fallback, on 2.10+.
    assert guided.index("fireAtTarget") < guided.index("setMissileTarget")
    assert "private _canSteer = (productVersion param [2,0]) >= 210;" in guided


def test_the_guided_pass_fires_only_inside_the_envelope_at_each_launch():
    strike = code("ITW_CLASH_SupportsStrike.sqf")
    envelope = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_Envelope")
    for needle in ('"TOO_CLOSE"', '"TOO_FAR"', '"OFF_NOSE"', '"NO_LINE_OF_SIGHT"', "_veh getRelDir _target"):
        assert needle in envelope, needle
    ammo_range = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_AmmoRange")
    assert '"missileLockMinDistance"' in ammo_range and '"missileLockMaxDistance"' in ammo_range
    guided = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_GuidedPass")
    loop = guided[guided.index('for "_shot" from 1 to ITW_CLASH_SupportsStrikeShots do {'):]
    assert loop.index("fnc_Envelope") < loop.index("fireAtTarget")
    assert 'if (_along < _minRange) exitWith {_ended = "inside-min-range"};' in guided


def test_a_test_pass_never_touches_the_ledger():
    test_pass = function_body(code("ITW_CLASH_SupportsStrike.sqf"), "ITW_CLASH_SupportsStrike_fnc_TestPass")
    assert "if (!isServer) exitWith" in test_pass
    for forbidden in ("fnc_Admit", "fnc_Settle", "fnc_Ledger", "fnc_Run;"):
        assert forbidden not in test_pass.replace("ITW_CLASH_SupportsStrike_fnc_Run;", ""), forbidden
    assert '["test",true]' in test_pass


def test_a_strike_lost_before_release_is_lost_not_refunded():
    unguided = function_body(code("ITW_CLASH_SupportsStrike.sqf"), "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    assert 'exitWith {_result = ["LOST","aircraft-lost"]};' in unguided
    assert 'case (_released == 0 && {_done isEqualTo "lost"}): {["LOST","aircraft-lost"]};' in unguided


# ------------------------------------------------------------------------ uav


def test_the_uav_looks_and_never_shoots():
    uav = code("ITW_CLASH_SupportsUAV.sqf")
    disarm = function_body(uav, "ITW_CLASH_SupportsUAV_fnc_Disarm")
    assert '_veh setPylonLoadout [_forEachIndex + 1,"",true];' in disarm
    assert 'if (_simulation isNotEqualTo "shotcm") then {' in disarm


def test_the_uav_stamps_its_look_and_reveals_to_its_commander():
    uav = code("ITW_CLASH_SupportsUAV.sqf")
    run = function_body(uav, "ITW_CLASH_SupportsUAV_fnc_Run")
    assert '[_side,_station,ITW_CLASH_SupportsUAVLookRadius,"uav"] call ITW_CLASH_Knowledge_fnc_StampLook;' in run
    sweep = function_body(uav, "ITW_CLASH_SupportsUAV_fnc_Sweep")
    assert "_hq reveal [_x,ITW_CLASH_SupportsUAVRevealLevel]" in sweep
    assert '!(_x isKindOf "Air")' in sweep


def test_the_uav_follows_the_assessment_without_a_new_roll():
    run = function_body(code("ITW_CLASH_SupportsUAV.sqf"), "ITW_CLASH_SupportsUAV_fnc_Run")
    assert "ITW_CLASH_SupportsUAVTasks getOrDefault [_sideKey,[]]" in run
    assert "[_group,_station,_height] call ITW_CLASH_SupportsUAV_fnc_Station;" in run


# ------------------------------------------------------------------- airborne


def test_squads_in_flight_carry_the_transit_flag_and_lose_it_on_the_ground():
    airborne = code("ITW_CLASH_SupportsAirborne.sqf")
    create = function_body(airborne, "ITW_CLASH_SupportsAirborne_fnc_CreateSquads")
    assert '_group setVariable ["ITW_CLASH_ReconstitutionTransit",true];' in create
    assert '_group setVariable ["ITW_CLASH_SupportAsset",_support get "id"];' in create
    assert "[_group,[_x],_ground,false] call ITW_AtkUnitToGroup;" in create
    handoff = function_body(airborne, "ITW_CLASH_SupportsAirborne_fnc_HandOff")
    clear = handoff.index('_group setVariable ["ITW_CLASH_ReconstitutionTransit",nil];')
    register = handoff.index('[_group,"support-airborne"] call ITW_CLASH_DualHAL_fnc_RegisterGroup')
    order = handoff.index("call ITW_CLASH_SupportsAirborne_fnc_NativeOrder")
    assert clear < register < order
    assert '_group setVariable ["ITW_CLASH_SupportAsset",nil];' in handoff


def test_the_jump_is_impasses_own():
    run = function_body(code("ITW_CLASH_SupportsAirborne.sqf"), "ITW_CLASH_SupportsAirborne_fnc_Run")
    assert "[_veh,grpNull,_squads,[]] call ITW_AtkUnloadAirplane;" in run
    assert "[_veh,_jumpers] call ITW_CLASH_HALUnload_fnc_StickLead" in run


def test_a_broken_off_drop_removes_squads_that_never_landed():
    run = function_body(code("ITW_CLASH_SupportsAirborne.sqf"), "ITW_CLASH_SupportsAirborne_fnc_Run")
    tail = run[run.index("switch (_result#0) do {"):]
    default = tail[tail.index("default {"):]
    assert "[_squads] call ITW_CLASH_SupportsAirborne_fnc_DeleteSquads;" in default
    lost = tail[tail.index('case "LOST": {'):tail.index("default {")]
    assert '"survived-loss"] spawn ITW_CLASH_SupportsAirborne_fnc_HandOff' in lost


def test_the_capture_order_is_written_as_hals_dispatcher_writes_it():
    order = function_body(code("ITW_CLASH_SupportsAirborne.sqf"), "ITW_CLASH_SupportsAirborne_fnc_NativeOrder")
    assert '_group setVariable ["Busy" + str _group,true];' in order
    assert 'private _key = "Capturing" + str _trg + str _hq;' in order
    assert "_trg setVariable [_key,[(_stage + 1) min 5,_count + count (units _group)]];" in order
    assert "[[_group,_stage,_hq,_trg],HAL_GoCapture] call RYD_Spawn;" in order
    assert '[[_group,_target,0,0,false,_hq getVariable ["RydHQ_Angle",0],_hq],HAL_GoDef] call RYD_Spawn;' in order


# ----------------------------------------------------------------------- boot


def test_boot_order_knowledge_colossus_supports_executors():
    init = code("init.sqf")
    knowledge = init.index('"ITW_CLASH_Knowledge.sqf"')
    colossus = init.index('preprocessFileLineNumbers "ITW_CLASH_Colossus.sqf"')
    core = init.index('preprocessFileLineNumbers "ITW_CLASH_Supports.sqf"')
    assert knowledge < colossus < core
    for executor in (
        '"ITW_CLASH_SupportsStrike.sqf"',
        '"ITW_CLASH_SupportsUAV.sqf"',
        '"ITW_CLASH_SupportsAirborne.sqf"',
    ):
        assert core < init.index(executor), executor
    assert "_knowledgeLoaded isEqualTo true" in init
    assert "_colossusLoaded isEqualTo true" in init


def test_executors_refuse_to_start_without_the_core():
    for name in SUPPORT_FILES[1:]:
        assert 'if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {' in code(name), name
    assert 'if (isNil "ITW_CLASH_Knowledge_fnc_Contacts") exitWith {' in code("ITW_CLASH_Supports.sqf")


def test_attack_restore_leaves_support_assets_alone():
    owned = function_body(code("ITW_CLASH_AttackRestore.sqf"), "ITW_CLASH_AttackRestore_fnc_Owned")
    assert '(_group getVariable ["ITW_CLASH_SupportAsset",""]) isNotEqualTo ""' in owned


def test_every_denial_used_is_in_the_vocabulary():
    core = code("ITW_CLASH_Supports.sqf")
    vocabulary_block = core[core.index("ITW_CLASH_SupportsDenials = ["):]
    vocabulary_block = vocabulary_block[:vocabulary_block.index("];")]
    vocabulary = set(re.findall(r'"([A-Z_]+)"', vocabulary_block))
    used = set()
    for name in SUPPORT_FILES:
        source = code(name)
        used |= set(re.findall(r',"([A-Z_]+)"\] call ITW_CLASH_Supports_fnc_Exclude', source))
        # Executor revocations, not the Settle's state list ["REVOKED","BREAKOFF"].
        used |= set(re.findall(r'\{\["REVOKED","([A-Z_]+)"\]\}', source))
        used |= set(re.findall(r'^\s*\["REVOKED","([A-Z_]+)"\]\s*$', source, re.M))
        used |= set(re.findall(r'_denied = "([A-Z_]+)"', source))
        used |= set(re.findall(r'_support set \["denied","([A-Z_]+)"\]', source))
    missing = sorted(used - vocabulary)
    assert not missing, missing


# ------------------------------------------------------------ v2: knowledge


def test_losing_the_position_is_not_losing_the_enemy():
    source = code("ITW_CLASH_Knowledge.sqf")
    assert "ITW_CLASH_KnowledgeVersion = 6;" in source
    held = function_body(source, "ITW_CLASH_Knowledge_fnc_Held")
    assert "([_y] call ITW_CLASH_Knowledge_fnc_Existence) > 0" in held
    census = function_body(source, "ITW_CLASH_Knowledge_fnc_Census")
    assert "forEach ([_side] call ITW_CLASH_Knowledge_fnc_Held);" in census
    assert "< ITW_CLASH_KnowledgePresenceFloor) then {continue};" in census
    strength = function_body(source, "ITW_CLASH_Knowledge_fnc_ReportedStrength")
    assert "forEach ([_side] call ITW_CLASH_Knowledge_fnc_Held);" in strength
    assert "call ITW_CLASH_Knowledge_fnc_Presence;" in strength
    # Targeting still never sees a LOST record.
    contacts = function_body(source, "ITW_CLASH_Knowledge_fnc_Contacts")
    assert 'if (_status isNotEqualTo "LOST") then' in contacts


def test_presence_is_existence_times_the_share_of_where_it_could_be():
    source = code("ITW_CLASH_Knowledge.sqf")
    presence = function_body(source, "ITW_CLASH_Knowledge_fnc_Presence")
    assert "/ (pi * _r * _r);" in presence
    assert "_existence * ((_share max 0) min 1)" in presence
    overlap = function_body(source, "ITW_CLASH_Knowledge_fnc_CircleOverlap")
    # SQF acos is in degrees; the segment formula needs radians.
    assert "(acos _a) * pi / 180" in overlap and "(acos _b) * pi / 180" in overlap


def test_the_best_report_is_the_most_certain_now_not_the_newest():
    update = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_Update")
    assert "if (_bestR <= _heldR) then {" in update
    assert "_seenAt > (_record get \"seenAt\")}) then {" not in update
    # Any sighting still proves it exists, and that is what forgetting reads.
    assert '_record set ["confirmedAt",_seenAt max' in update
    assert '(_now - (_record getOrDefault ["confirmedAt",_record get "seenAt"])) > ITW_CLASH_KnowledgeForgetAfter' in update
    existence = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_Existence")
    assert '_record getOrDefault ["confirmedAt"' in existence


def test_cleared_needs_our_people_on_the_ground_inside_the_objective():
    update = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_Update")
    assert '!((vehicle _x) isKindOf "Air")' in update
    assert '"ITW_CLASH_ColossusObjectiveRadius",500]' in update
    assert '"ITW_CLASH_AirPictureObservedRadius"' not in update


def test_a_look_is_only_refreshed_by_the_same_kind_of_look():
    stamp = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_StampLook")
    assert "&& {(_x#3) isEqualTo _source}" in stamp


# ----------------------------------------------------- v2: objective influence


def test_the_objective_biases_targets_rather_than_deciding_them():
    core = code("ITW_CLASH_Supports.sqf")
    assert '"ITW_CLASH_SupportsInfluenceRadius",2000]' in core
    assert '"ITW_CLASH_SupportsInfluenceEdge",0.3]' in core
    assert '"ITW_CLASH_SupportsThreatProximity",1000]' in core
    weight = function_body(core, "ITW_CLASH_Supports_fnc_DistanceWeight")
    assert "1 - ((1 - ITW_CLASH_SupportsInfluenceEdge) * (_distance - _inner)" in weight
    assert "if (_distance > ITW_CLASH_SupportsInfluenceRadius) exitWith {0};" in weight
    strike = function_body(core, "ITW_CLASH_Supports_fnc_StrikeCandidates")
    assert "[_side,_centers,ITW_CLASH_SupportsInfluenceRadius] call ITW_CLASH_Supports_fnc_Clusters" in strike
    assert "if (_threat) then {_falloff = 1};" in strike
    # One entry per cluster and flavor, at its best objective.
    assert "if (_weight > _bestWeight) then {" in strike


def test_threat_proximity_counts_only_formations_committed_to_that_objective():
    committed = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Committed")
    assert '"ITW_CLASH_ColossusCommittedRadius",900]' in committed
    assert 'if (_veh isKindOf "Air") then {continue};' in committed
    for pool in ("RydHQ_SupportG", "RydHQ_SpecForG", "RydHQ_ArtG", "RydHQ_CargoOnly", "RydHQ_Exhausted"):
        assert pool in committed, pool


def test_pressure_on_a_held_point_is_its_own_and_covers_its_influence():
    core = code("ITW_CLASH_Supports.sqf")
    pressure = function_body(core, "ITW_CLASH_Supports_fnc_Pressure")
    assert "forEach ([_side] call ITW_CLASH_Knowledge_fnc_Held);" in pressure
    assert "[_record,_center,ITW_CLASH_SupportsInfluenceRadius] call ITW_CLASH_Knowledge_fnc_Presence" in pressure
    assess = function_body(core, "ITW_CLASH_Supports_fnc_Assess")
    assert "ITW_CLASH_Supports_fnc_Pressure;" in assess
    assert '_entry getOrDefault ["enemyReported",-1]' not in assess


def test_every_candidate_is_affordable_before_the_roll():
    core = code("ITW_CLASH_Supports.sqf")
    strike = function_body(core, "ITW_CLASH_Supports_fnc_StrikeCandidates")
    assert '(_ledger get "cash") < ([_flavor,_reason] call ITW_CLASH_Supports_fnc_Price)' in strike
    drop = function_body(core, "ITW_CLASH_Supports_fnc_DropCandidates")
    assert '< ([_flavor,_reason] call ITW_CLASH_Supports_fnc_Price)) then {' in drop
    assess = function_body(core, "ITW_CLASH_Supports_fnc_Assess")
    assert '(["UAV","TAKE"] call ITW_CLASH_Supports_fnc_Price)' in assess


def test_the_uav_goes_where_uncertainty_blocks_a_decision():
    core = code("ITW_CLASH_Supports.sqf")
    task = function_body(core, "ITW_CLASH_Supports_fnc_UAVTask")
    assert 'if (_planIntel isEqualTo "STALE_CONTACT") exitWith {[_planPos,_planObjective,"stale-plan"]};' in task
    assess = function_body(core, "ITW_CLASH_Supports_fnc_Assess")
    assert 'case "unobserved-plan";\n                        case "stale-plan": {3};' in assess


def test_the_spawn_is_always_the_full_run_in_and_on_the_map():
    spawn = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_SpawnPoint")
    assert "+_origin" not in spawn
    assert "private _limit = worldSize - _margin;" in spawn
    assert "forEach [0,15,-15,30,-30,45,-45,60,-60,75,-75,90,-90];" in spawn


def test_egress_flies_on_turns_on_the_colder_side_and_goes_home():
    egress = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Egress")
    assert "_from getPos [ITW_CLASH_SupportsEgressSeparation,_heading]" in egress
    assert "[120,-120] apply {" in egress
    assert 'private _rank = ["COLD","UNKNOWN","CONTESTED","HOT","AIR_DENIED"];' in egress
    # Shot down on the way out: left where it falls.
    assert "if (!alive _veh) exitWith {false};" in egress
    for name in ("ITW_CLASH_SupportsStrike.sqf", "ITW_CLASH_SupportsAirborne.sqf"):
        assert re.search(r"4000,300,_support\s*\] spawn ITW_CLASH_Supports_fnc_Egress;", code(name)), name


def test_only_decisions_are_spoken_aloud():
    core = code("ITW_CLASH_Supports.sqf")
    log = function_body(core, "ITW_CLASH_Supports_fnc_Log")
    assert "_event in ITW_CLASH_SupportsLoudEvents" in log
    loud = core[core.index("ITW_CLASH_SupportsLoudEvents = ["):]
    loud = loud[:loud.index("];")]
    assert '"pool"' not in loud and '"ledger"' not in loud


def test_preflight_knows_the_five_modules():
    manifest = code("ITW_CLASH_DebugPreflight.sqf")
    for prefix in ("ITW_CLASH_Knowledge", "ITW_CLASH_Supports", "ITW_CLASH_SupportsStrike",
                   "ITW_CLASH_SupportsUAV", "ITW_CLASH_SupportsAirborne"):
        assert f'["{prefix}",' in manifest, prefix


def test_the_uav_is_fixed_wing_when_the_faction_has_one():
    # 2026-10-16: A's UAV was an AR-2 Darter, picked at random from a list
    # that also held fixed-wing UAVs, and sent 5 km out to loiter at 500 m.
    pick = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_PickClass")
    uav = pick[pick.index('case "UAV": {'):pick.index('case "JET": {')]
    assert 'private _fixed = _classes select {_x isKindOf "Plane"};' in uav
    assert "if (_fixed isNotEqualTo []) then {_classes = _fixed};" in uav
    assert uav.index("_fixed isNotEqualTo []") < uav.index("[selectRandom _classes,\"\"]")
    assert "uavFixedWingFirst=true" in (MISSION / "ITW_CLASH_Supports.sqf").read_text()


def test_fixed_wing_uavs_fly_above_spaa_reach_and_rotary_ones_stay_low():
    # 2026-10-16: a Greyhawk died 5 s after reaching its station at 500 m on
    # each side, over objectives covered by Cheetahs.
    source = code("ITW_CLASH_SupportsUAV.sqf")
    raw = (MISSION / "ITW_CLASH_SupportsUAV.sqf").read_text()
    assert "ITW_CLASH_SupportsUAVVersion = 4;" in raw
    assert 'ITW_CLASH_SupportsUAVHeight",2000]' in source
    assert 'ITW_CLASH_SupportsUAVHeightRotary",500]' in source
    run = function_body(source, "ITW_CLASH_SupportsUAV_fnc_Run")
    assert ('private _height = if (_class isKindOf "Plane") then {ITW_CLASH_SupportsUAVHeight} '
            'else {ITW_CLASH_SupportsUAVHeightRotary};') in run
    assert "private _start = [_spawn#0,_spawn#1,_height];" in run
    assert "_veh flyInHeight _height;" in run
    station = function_body(source, "ITW_CLASH_SupportsUAV_fnc_Station")
    assert "_wp setWaypointLoiterAltitude _height;" in station
    assert "ITW_CLASH_SupportsUAVHeight;" not in run
