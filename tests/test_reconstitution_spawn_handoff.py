"""A replacement squad is handed to its commander where it is born.

Hark, 2026-10-11: "Brav 2-4, littlebird, stuck in the air near enemy fob, why?"
then "maybe we should spawn the reconstitution squad, then immediately hand it
hal without any orders and let hal toss it where it needs to go?" and "BOTH
SIDES, we need to maintain parity at all times."

Run of 2026-10-11 20:23, mission 2. Two replacement lifts flew, one a side:

    RC1  BLUFOR, raised for objective 8
         20:56:54  Littlebird dispatched from base 9
         20:59:20  squad out by parachute, 500 m from objective 23
         20:59:26  dual-hal-vehicle-migrated ["G143","B_Heli_Light_01_F",21]
         20:59:29  Impasse's last waypoint, 1000 m off the objective
         21:00:09  waypoint NONE, to the end of the log at 21:07
         reconstitution-transport-unassigned [.., 4, 4, 4, 0]   31 times

    RC2  enemy, raised for objective 8
         21:02:54  squad out by parachute, 590 m from objective 8
         reconstitution-handoff-wait [.., 3 assigned, 590, "physical-dismount"]
         to the end of the log

    reconstitution-transit-arrived   0 times

The lift is a third kind of lift, between Impasse and HAL. It has a handoff at
each end and one in the middle, and each had a fault:

    takeoff   the BLUFOR vector did not read the objective the lift was raised
              for; the enemy vector did
    drop      the Dual-HAL migration took the empty aircraft from Impasse two
              seconds before Impasse would have sent it home, and gave it no
              order
    landing   the handoff waited for assignedVehicles to be empty, and a
              deleted parachute stays in that list as a null object

The main change takes the lift out of the usual path: the squad is given to its
commander at the forward FOB, with the handoff it already got at the end of the
lift, and HAL moves it. The lift is still there for a squad the commander will
not take, with all three handoffs repaired.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace").replace("\r", "")


def function_body(source: str, name: str, nth: int = 0) -> str:
    start = -1
    for _ in range(nth + 1):
        start = source.index(f"{name} = {{", start + 1)
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


def code_only(source: str) -> str:
    """Drop comments so a commented-out line cannot satisfy an assertion."""
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return "\n".join(
        line for line in source.split("\n") if not line.lstrip().startswith("//")
    )


def depth_at(body: str, needle: str) -> int:
    """Brace depth of the first occurrence of needle inside a function body.
    1 is function scope."""
    at = body.index(needle)
    return body[:at].count("{") - body[:at].count("}")


def dispatch() -> str:
    return mission("ITW_CLASH_ReconstitutionDispatchFix.sqf")


def transit() -> str:
    return mission("ITW_CLASH_ReconstitutionTransitFix.sqf")


def handoff() -> str:
    return code_only(function_body(dispatch(), "ITW_CLASH_Reconstitution_fnc_SpawnHandoff"))


def begin() -> str:
    return code_only(function_body(dispatch(), "ITW_AtkBeginReconstitutionTransit"))


# --- the handoff a replacement squad already got writes no order ---------------


def test_the_existing_handoff_registers_the_squad_and_orders_nothing():
    """Both sides. This is what "hand it to HAL without any orders" already
    was; it was only being called after the lift."""
    blufor = function_body(mission("ITW_CLASH_RuntimePatch.sqf"), "ITW_CLASH_fnc_AcknowledgeReconstitution")
    enemy = function_body(mission("ITW_CLASH.sqf"), "ITW_CLASH_fnc_AcknowledgeReconstitution")
    assert '"ITW_CLASH_DualHALObjectiveAffinity",_objectiveIndex' in blufor
    assert '_group,"reconstitution-handoff"' in blufor
    assert "call ITW_CLASH_DualHAL_fnc_RegisterGroup" in blufor
    assert "call ITW_CLASH_fnc_RegisterGroup" in enemy
    # The BLUFOR wrapper falls through to the enemy one for the other side.
    assert "call ITW_CLASH_fnc_AcknowledgeReconstitution_V6Base" in blufor
    for body in (blufor, enemy):
        for order in ("addWaypoint", "doMove", "commandMove", "setPosATL"):
            assert order not in body, order

    for name, register in (
        ("ITW_CLASH_DualHALCheckbook.sqf", "ITW_CLASH_DualHAL_fnc_RegisterGroup"),
        ("ITW_CLASH.sqf", "ITW_CLASH_fnc_RegisterGroup"),
    ):
        body = function_body(mission(name), register)
        assert "addWaypoint" not in body, register


def test_the_admission_gate_does_not_hold_a_reconstitution_handoff():
    gate = function_body(mission("ITW_CLASH_FormationAdmission.sqf"), "ITW_CLASH_FormationAdmission_fnc_Gate")
    reasons = gate[gate.index("private _gatedReasons = ["):gate.index("];", gate.index("private _gatedReasons = ["))]
    assert "reconstitution" not in reasons
    assert 'if !(_reason in _gatedReasons) exitWith {["ALLOW","not-gated"]};' in gate


def test_both_commanders_refuse_a_group_impasse_still_marks_as_being_built():
    """Why the spawn handoff clears itwInitGrp before it asks."""
    assert 'if (_group getVariable ["itwInitGrp",false]) exitWith {[true,"spawn-transition",[]]};' in mission(
        "ITW_CLASH_InfantryAuthority.sqf"
    )
    assert 'if (_group getVariable ["itwInitGrp",false]) exitWith {"itw-init-group"};' in mission(
        "ITW_CLASH_FormationAdmission.sqf"
    )
    spawner = mission("ITW_Attack.sqf")
    made = spawner.index("private _reconstitutionGroup = createGroup [_side,false];")
    assert '_reconstitutionGroup setVariable ["itwInitGrp",true,true];' in spawner[made:made + 300]


# --- the spawn handoff ------------------------------------------------------------


def test_the_squad_is_offered_to_its_commander_before_it_is_put_in_transit():
    body = begin()
    placed = body.index("_x setPosATL _offset;")
    offered = body.index("] call ITW_CLASH_Reconstitution_fnc_SpawnHandoff) exitWith {true};")
    transit_flag = body.index('_group setVariable ["ITW_CLASH_ReconstitutionTransit",true];')
    queued = body.index("ITW_AtkReconstitutionTransits pushBack [")
    assert placed < offered < transit_flag < queued
    # The call is at function scope, so its exitWith leaves the function.
    assert depth_at(body, "] call ITW_CLASH_Reconstitution_fnc_SpawnHandoff) exitWith {true};") == 1
    call = body[body.rindex("if ([", 0, offered):offered]
    assert "_group,_requestId,_objectiveIndex,_archetype,_lineage,_queuedAt" in call


def test_a_squad_the_commander_takes_never_carries_the_transit_reservation():
    """ITW_CLASH_ReconstitutionTransit makes the group lifecycle-reserved,
    which hides it from HAL. It must not be set on a squad HAL now owns."""
    reserved = function_body(mission("ITW_CLASH_DualHALCheckbook.sqf"), "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved")
    assert 'if (_group getVariable ["ITW_CLASH_ReconstitutionTransit",false]) exitWith {true};' in reserved
    assert "ITW_CLASH_ReconstitutionTransit" not in handoff()
    assert "ITW_AtkReconstitutionTransits" not in handoff()


def test_the_handoff_is_the_one_the_lift_ended_with_and_the_same_call_for_both_sides():
    body = handoff()
    call = body.index("] call ITW_CLASH_fnc_AcknowledgeReconstitution;")
    args = body[body.rindex("private _accepted = [", 0, call):call]
    assert "_group,_requestId,_objectiveIndex,_archetype,_lineage,_queuedAt" in args
    # Nothing about which side it is before the call: parity is the same line.
    assert "side _group" not in body[:call]
    assert "ITW_PlayerSide" not in body[:call]
    assert "ITW_EnemySide" not in body[:call]

    manager = code_only(function_body(transit(), "ITW_AtkReconstitutionTransitManager"))
    assert "_group,_requestId,_objectiveIndex,_archetype,_lineage,_queuedAt" in manager
    assert "] call ITW_CLASH_fnc_AcknowledgeReconstitution;" in manager


def test_the_being_built_mark_is_cleared_first_and_put_back_if_refused():
    body = handoff()
    cleared = body.index('_group setVariable ["itwInitGrp",nil,true];')
    objective = body.index("VAR_SET_OBJ_IDX(_group,_objectiveIndex);")
    call = body.index("] call ITW_CLASH_fnc_AcknowledgeReconstitution;")
    refused = body.index("if (!_accepted) exitWith {")
    restored = body.index('_group setVariable ["itwInitGrp",true,true];')
    assert cleared < objective < call < refused < restored
    refusal = body[refused:body.index("\n    };", refused)]
    assert '"reconstitution-spawn-handoff-refused"' in refusal
    assert refusal.rstrip().endswith("false")


def test_a_refused_squad_goes_down_the_transit_path_unchanged():
    body = begin()
    offered = body.index("] call ITW_CLASH_Reconstitution_fnc_SpawnHandoff) exitWith {true};")
    after = body[offered:]
    for line in (
        '_group setVariable ["ITW_CLASH_ReconstitutionTransit",true];',
        '_group setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];',
        '_group setVariable ["ITW_CLASH_TransitState","waiting-transport"];',
        '_group setVariable ["ITW_CLASH_ReconstitutionRequest",_requestId];',
        '_group setVariable ["itwInitGrp",true,true];',
        "0 spawn ITW_AtkReconstitutionTransitManager;",
        '["reconstitution-transit-queued",[',
    ):
        assert line in after, line


def test_the_handoff_writes_no_order_and_moves_nobody():
    body = handoff()
    for order in ("addWaypoint", "doMove", "commandMove", "setPos", "moveIn", "ITW_AtkEngageInfantry"):
        assert order not in body, order


def test_the_enemy_gets_the_same_closing_step_the_transit_manager_gives_it():
    body = handoff()
    accepted = body.index("if (!_accepted) exitWith {")
    callback = body.index("[_group] call ITW_EnemyGroupCallback")
    assert accepted < callback
    manager = code_only(function_body(transit(), "ITW_AtkReconstitutionTransitManager"))
    assert "[_group] call ITW_EnemyGroupCallback" in manager


def test_the_handoff_is_logged_with_how_far_the_squad_has_to_go():
    body = handoff()
    line = body[body.index('["reconstitution-spawn-handoff",['):]
    line = line[:line.index("call ITW_CLASH_fnc_Log")]
    for token in ("_requestId", "_lineage", "_objectiveIndex", "side _group", "_distance"):
        assert token in line, token
    assert "leader _group distance2D ((ITW_Objectives#_objectiveIndex)#ITW_OBJ_POS)" in body


def test_it_can_be_switched_off_and_fails_closed_without_the_handoff_function():
    body = handoff()
    off = body.index("if (!ITW_CLASH_ReconstitutionSpawnHandoff) exitWith {false};")
    missing = body.index('isNil "ITW_CLASH_fnc_AcknowledgeReconstitution"')
    touched = body.index('_group setVariable ["itwInitGrp",nil,true];')
    assert off < missing < touched
    assert '"ITW_CLASH_ReconstitutionSpawnHandoff",true' in dispatch()
    # A nil return from a function that errored is a refusal, not a crash.
    assert 'if (isNil "_accepted") then {_accepted = false};' in body


# --- landing: a deleted vehicle is not an assigned vehicle ------------------------


def test_a_parachute_is_a_vehicle_made_for_each_man():
    itw = mission("ITW_Attack.sqf")
    chute = itw.index('private _para = "Steerable_Parachute_F" createVehicle _pos;')
    assert "_unit moveindriver _para;" in itw[chute:chute + 400]


def test_three_modules_tried_to_clear_the_list_and_none_could():
    """The field hardening pass logs the list after leaveVehicle and
    unassignVehicle. In the 2026-10-11 run it is still <NULL-object>."""
    hardening = mission("ITW_CLASH_FieldHardening.sqf")
    assert "{_group leaveVehicle _x} forEach _assignedBefore;" in hardening
    assert '["reconstitution-stale-assignment-cleared",[' in hardening
    reconcile = function_body(transit(), "ITW_CLASH_Reconstitution_fnc_ReconcileDismountOwnership")
    assert "unassignVehicle _x;" in reconcile


def test_only_vehicles_that_still_exist_are_counted():
    body = code_only(function_body(transit(), "ITW_CLASH_Reconstitution_fnc_LiveAssigned"))
    assert "(assignedVehicles _group) select {!isNull _x}" in body
    assert "if (isNull _group) exitWith {[]};" in body
    # A wreck still exists and still counts, as it does for BLUFOR admission.
    assert "alive" not in body


def test_the_transit_manager_gate_reads_the_filtered_list():
    manager = code_only(function_body(transit(), "ITW_AtkReconstitutionTransitManager"))
    assert "assignedVehicles" not in manager
    assert manager.count("ITW_CLASH_Reconstitution_fnc_LiveAssigned") == 2
    gate = manager[manager.index("private _handoffBlocked ="):]
    assert "_assigned isNotEqualTo []" in gate[:200]

    reconcile = code_only(function_body(transit(), "ITW_CLASH_Reconstitution_fnc_ReconcileDismountOwnership"))
    assert "count assignedVehicles" not in reconcile
    assert reconcile.count("ITW_CLASH_Reconstitution_fnc_LiveAssigned") == 2


def test_the_logistics_guard_stops_reconciling_what_cannot_be_reconciled():
    guard = code_only(mission("ITW_CLASH_LogisticsGuard.sqf"))
    assert "[_grp] call ITW_CLASH_Reconstitution_fnc_LiveAssigned" in guard
    assert "private _assigned = assignedVehicles _grp;" not in guard
    for use in re.findall(r"assignedVehicles _grp\)?[^\n]*", guard):
        assert "select {!isNull _x}" in use, use


def test_both_enemy_classifiers_read_the_list_the_same_way():
    """Without this the enemy squad passes the transit gate and is then
    refused registration for the same null parachutes."""
    for name, verdict in (
        ("ITW_CLASH.sqf", '[false,"assigned-vehicle",[]]'),
        ("ITW_CLASH_InfantryAuthority.sqf", '[true,"assigned-vehicle",[]]'),
    ):
        source = code_only(mission(name))
        at = source.index(verdict)
        test = source[source.rindex("if (", 0, at):at]
        assert "((assignedVehicles _group) select {!isNull _x}) isNotEqualTo []" in test, name
        assert "assignedVehicles _group isNotEqualTo []" not in source, name


def test_blufor_admission_already_asked_each_man_which_a_deleted_vehicle_passes():
    """The parity point: assignedVehicle of a man is null once the vehicle is
    deleted, so BLUFOR never had this fault at admission."""
    admission = mission("ITW_CLASH_FormationAdmission.sqf")
    assert '(_alive findIf {!isNull assignedVehicle _x}) >= 0) exitWith {"assigned-vehicle"};' in admission


# --- takeoff: both vectors read the objective the lift was raised for -------------


def forced_block(source: str, name: str) -> tuple[str, str]:
    body = code_only(function_body(source, name))
    read = body[body.index("private _forcedObjective = _group getVariable ["):body.index("if (ITW_defendPhaseObjIdx > 0) then {")]
    write = body[body.index("VAR_SET_OBJ_IDX(_group,_objIndex);"):body.index("private _objTo = ITW_Objectives#_objIndex;")]
    squash = lambda s: re.sub(r"\s+", " ", s).strip()
    return squash(read), squash(write)


def test_the_blufor_vector_has_the_enemy_vectors_forced_objective_branch():
    enemy = forced_block(mission("ITW_Enemy.sqf"), "ITW_EnemyAttackVectors")
    ally = forced_block(mission("ITW_Ally.sqf"), "ITW_AllyAttackVectors")
    assert ally[0] == enemy[0]
    assert ally[1] == enemy[1]
    assert '"ITW_CLASH_TransitObjective",-1' in ally[0]
    assert '_x setVariable ["ITW_CLASH_TransitObjective",_objIndex];' in ally[1]


def test_both_vectors_honour_it_only_inside_the_live_zone_and_not_in_a_defend_phase():
    for name, function in (("ITW_Enemy.sqf", "ITW_EnemyAttackVectors"), ("ITW_Ally.sqf", "ITW_AllyAttackVectors")):
        body = re.sub(r"\s+", " ", code_only(function_body(mission(name), function)))
        defend = body.index("if (ITW_defendPhaseObjIdx > 0) then { _objIndex = ITW_defendPhaseObjIdx; } else {")
        forced = body.index("if (_forcedObjective >= 0 && { _forcedObjective in _objIndexes }) then { _objIndex = _forcedObjective; } else {")
        assert defend < forced, name


def test_the_lift_still_says_which_objective_it_was_raised_for():
    source = dispatch()
    lift = code_only(function_body(source, "ITW_AtkDispatchReconstitutionTransport"))
    assert '_group setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];' in lift
    assert '_crewGroup setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];' in lift
    assert lift.index('_crewGroup setVariable ["ITW_CLASH_TransitObjective",_objectiveIndex];') < lift.index(
        "[_vehInfo,false,false] call ITW_AtkAddVehicle;"
    )


def test_the_ally_file_kept_its_line_endings():
    raw = (MISSION / "ITW_Ally.sqf").read_bytes()
    assert raw.count(b"\r\n") == raw.count(b"\n")


# --- drop: the empty lift stays Impasse's and goes home ---------------------------


def test_impasse_sends_an_empty_transport_home_and_deletes_it_there():
    manager = function_body(mission("ITW_Attack.sqf"), "ITW_AtkVehicleManager")
    done = manager.index("if (_transportDone || _attackDone) then {")
    branch = manager[done:manager.index("_returningVehicles pushBack [_veh,time + 180];", done)]
    assert "_removeVehs pushBack _vehInfo;" in branch
    assert "private _wp1 = _grp addWaypoint [_fromPos,0];" in branch
    assert "deleteVehicle _veh;" in branch


def test_the_migration_took_it_out_of_impasse_and_gave_it_no_order():
    migrate = function_body(mission("ITW_CLASH_DualHALCheckbook.sqf"), "ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles")
    assert "ITW_ManagedVehs deleteAt _i;" in migrate
    assert "addWaypoint" not in migrate
    assert "if !([_crewGroup,_vehInfo] call ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter) then {" in migrate
    # And the service lifecycle only ever registers what it bought or generated.
    service = mission("ITW_CLASH_ServiceLifecycle.sqf")
    sources = re.findall(r'\[_veh,_capability,_mode,"([a-z-]+)"\] call ITW_CLASH_Service_fnc_RegisterPhysical', service)
    assert sorted(sources) == ["generation-register", "new-purchase"]


def test_the_reservation_flag_on_the_vehicle_could_not_have_stopped_it():
    """The vehicle tests in the reservation predicate sit inside a `then`
    block, where exitWith only leaves the block, and the flag is dropped at the
    dismount anyway. If this is ever repaired the mark below is still needed,
    because the flag is still dropped."""
    reserved = function_body(mission("ITW_CLASH_DualHALCheckbook.sqf"), "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved")
    assert depth_at(reserved, '_veh getVariable ["ITW_CLASH_ReconstitutionTransport",false]') > 1
    release = function_body(transit(), "ITW_CLASH_Reconstitution_fnc_ReleaseTransportReservation")
    assert '_veh setVariable ["ITW_CLASH_ReconstitutionTransport",nil,true];' in release


def test_the_lift_is_marked_for_life_before_impasse_is_given_it():
    lift = code_only(function_body(dispatch(), "ITW_AtkDispatchReconstitutionTransport"))
    marked = lift.index('_veh setVariable ["ITW_CLASH_ReconstitutionLift",true,true];')
    assert marked < lift.index("[_vehInfo,false,false] call ITW_AtkAddVehicle;")
    for path in MISSION.glob("*.sqf"):
        source = path.read_text(encoding="utf-8", errors="replace")
        assert '"ITW_CLASH_ReconstitutionLift",nil' not in source, path.name
        assert '"ITW_CLASH_ReconstitutionLift",false,' not in source, path.name


def test_a_marked_lift_is_never_taken_from_impasse():
    suppress = code_only(function_body(
        mission("ITW_CLASH_DualHALCheckbook.sqf"), "ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter"
    ))
    mark = '_veh getVariable ["ITW_CLASH_ReconstitutionLift",false]'
    test = suppress.index(mark)
    assert "}) exitWith {false};" in suppress[test:test + 120]
    # Function scope: the `if` that holds it is not inside another block.
    assert depth_at(suppress, "if (!isNull _veh && {") == 1
    assert test < suppress.index("call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved")

    # Every way C.L.A.S.H. takes a vehicle from Impasse asks that function.
    preinit = mission("ITW_CLASH_DualHALCheckbookPreInit.sqf")
    assert preinit.count("call ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter) then {") == 2


def test_impasse_sends_a_marked_lift_home_whatever_role_it_was_bought_under():
    manager = function_body(mission("ITW_Attack.sqf"), "ITW_AtkVehicleManager")
    assert (
        "private _transportDone = (_role == ITW_VEH_ROLE_TRANSPORT || "
        '{_veh getVariable ["ITW_CLASH_ReconstitutionLift",false]}) && {_cargoGroups isEqualTo []};'
    ) in manager
    # The lift can be a dual-role vehicle, which that branch never matched.
    lift = function_body(dispatch(), "ITW_AtkDispatchReconstitutionTransport")
    assert "private _candidates = (_transport + _dualVeh) select {" in lift


# --- versions and boot lines ------------------------------------------------------


def test_the_boot_lines_say_what_is_loaded():
    source = dispatch()
    assert "ITW_CLASH_ReconstitutionDispatchFixVersion = 7;" in source
    assert "spawnHandoff=%2 liftReturnsToImpasse=true" in source
    assert "ITW_CLASH_ReconstitutionTransitFixVersion = 6;" in transit()
    assert "deletedVehiclesNotAssigned=true" in transit()
    guard = mission("ITW_CLASH_LogisticsGuard.sqf")
    assert "ITW_CLASH_LogisticsHandoffVersion = 5;" in guard
    assert "deletedVehiclesNotAssigned=true" in guard
    assert "ITW_CLASH_DualHALCheckbookVersion = 7;" in mission("ITW_CLASH_DualHALCheckbook.sqf")
    assert "ITW_CLASH_InfantryAuthorityVersion = 5;" in mission("ITW_CLASH_InfantryAuthority.sqf")
