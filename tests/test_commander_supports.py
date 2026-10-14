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
    assert '(_record getOrDefault ["error",0]) + _speed * (_age + (_ahead max 0))' in uncertainty


def test_clock_anomalies_are_discarded_not_used():
    report = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_ReadReport")
    assert "if (_lastSeen < 0 || {_lastSeen > (time + 1)}) exitWith {" in report


def test_the_air_picture_counts_only_uav_looks_as_eyes():
    observed = code("ITW_CLASH_AirPicture.sqf")
    assert '[side _hq,_destination,-1,["uav"]] call ITW_CLASH_Knowledge_fnc_LookedAt' in observed


# ------------------------------------------------------------------- colossus


def test_colossus_proposes_once_after_its_own_order():
    source = code("ITW_CLASH_Colossus.sqf")
    assert "ITW_CLASH_ColossusVersion = 5;" in source
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


def test_shadow_mode_is_the_default_and_airborne_is_off():
    core = code("ITW_CLASH_Supports.sqf")
    assert '["ITW_CLASH_SupportsDryRun",true]' in core
    assert '["ITW_CLASH_SupportsAirborneHeliEnabled",false]' in core
    assert '["ITW_CLASH_SupportsAirbornePlaneEnabled",false]' in core
    assert '["ITW_CLASH_SupportsVehicleDropEnabled",false]' in core


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
        '_ledger set ["cash",(_ledger get "cash") - _price];',
        "_lanes set [_lane,_id];",
        '_cooldowns set ["flavor:" + _flavor',
    ):
        assert needle in block, needle


def test_money_is_spent_only_on_delivery_or_loss():
    settle = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Settle")
    assert 'private _refund = _state in ["REVOKED","BREAKOFF"];' in settle
    assert '_ledger set ["cash",(_ledger get "cash") + _price]' in settle
    # The lane is released only by its own holder.
    assert 'if ((_lanes getOrDefault [_lane,""]) isEqualTo _id) then {_lanes set [_lane,""]};' in settle
    # A lost UAV costs its side the next launch for a while.
    assert '_lane isEqualTo "RECON" && {_state isEqualTo "LOST"}' in settle


def test_two_lanes_so_the_uav_never_blocks_a_strike():
    core = code("ITW_CLASH_Supports.sqf")
    assert '["lanes",createHashMapFromArray [["RECON",""],["COMMIT",""]]]' in core
    assert core.count('["lane","RECON"]') == 1
    assert core.count('["lane","COMMIT"]') == 5


def test_save_is_an_option_in_the_same_pool():
    assess = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_Assess")
    assert '_pool pushBack (["SAVE","SAVE",-1,"",[],_saveWeight' in assess
    assert "([_pool] call ITW_CLASH_Supports_fnc_Pick)" in assess


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
    # The only position read in the core is our own people's, for danger close.
    assert core.count("getPosATL") == 1
    assert "private _position = getPosATL _veh;" in function_body(core, "ITW_CLASH_Supports_fnc_Friendlies")


def test_unguided_flavors_never_bomb_a_guess_guided_is_exempt():
    strike = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_StrikeCandidates")
    assert 'if (_flavor isNotEqualTo "GUIDED") then {' in strike
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


def test_unguided_release_is_by_fall_time_and_re_aimed_once():
    strike = code("ITW_CLASH_SupportsStrike.sqf")
    lead = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_Lead")
    assert "(_vz + sqrt ((_vz * _vz) + (2 * 9.81 * _height))) / 9.81" in lead
    unguided = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    assert "([_side,_keys,0] call ITW_CLASH_Supports_fnc_TargetNow)" in unguided
    assert "_aim = _now;" in unguided
    assert unguided.count("_checked = true;") == 1


def test_bombs_are_credited_to_the_aircraft():
    drop = function_body(code("ITW_CLASH_SupportsStrike.sqf"), "ITW_CLASH_SupportsStrike_fnc_DropBomb")
    assert "_bomb setShotParents [_veh,driver _veh];" in drop
    assert "_bomb setVelocity (velocity _veh);" in drop


def test_the_guided_pass_acquires_on_site_and_breaks_off_empty():
    guided = function_body(code("ITW_CLASH_SupportsStrike.sqf"), "ITW_CLASH_SupportsStrike_fnc_GuidedPass")
    assert "getSensorTargets _veh" in guided
    assert '["BREAKOFF","no-target-found"]' in guided
    # fireAtTarget first; a steered missile only as the fallback, on 2.10+.
    assert guided.index("fireAtTarget") < guided.index("setMissileTarget")
    assert "private _canSteer = (productVersion param [2,0]) >= 210;" in guided


def test_a_strike_lost_before_release_is_lost_not_refunded():
    unguided = function_body(code("ITW_CLASH_SupportsStrike.sqf"), "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    assert '} else {["LOST","aircraft-lost"]};' in unguided


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
    assert "[_group,_station] call ITW_CLASH_SupportsUAV_fnc_Station;" in run


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
