"""CSAR: a downed crew is player work, and only player work.

The crew of a destroyed vehicle is quarantined and deleted by
ITW_CLASH_CrewRemnantCleanup. CSAR asks cleanup to hold one while a player is
ticked for the work, walks it clear of the wreck with the mission's own
withdrawal primitives, and tests it against CASEVAC's safety gate.

Two boundaries are the point of this file, and both are the user's own rule:

  - Unless a player is ticked, CSAR does not exist. No claim, no order, no
    state, and a held crew is handed straight back.
  - No AI CSAR. ITW_CLASH_Withdrawals is where AI CASEVAC and ground MEDEVAC
    get their work, so nothing here may write it or set ITW_CLASH_Withdrawing.

This pass decides and logs; it publishes no mission yet.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace").replace("\r", "")


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


def code_only(source: str) -> str:
    """Drop comments, so prose about the old behaviour cannot answer for code."""
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return "\n".join(
        line for line in source.split("\n") if not line.lstrip().startswith("//")
    )


def csar() -> str:
    return mission("ITW_CLASH_CSAR.sqf")


def tick() -> str:
    return function_body(csar(), "ITW_CLASH_CSAR_fnc_Tick")


# --- the two boundaries ---------------------------------------------------


def test_nothing_here_makes_a_crew_an_ai_rescue_job():
    """AI CASEVAC and ground MEDEVAC both work from ITW_CLASH_Withdrawals and
    both require ITW_CLASH_Withdrawing on the group. Writing neither is what
    keeps an AI aircraft from being sent for a downed crew."""
    code = code_only(csar())
    assert "ITW_CLASH_Withdrawals" not in code
    assert "ITW_CLASH_Withdrawing" not in code
    assert "ITW_CLASH_RemnantEvac" not in code


def test_no_subscriber_means_no_claim_and_no_hold():
    body = code_only(tick())
    wanted = body.index("private _wanted = call ITW_CLASH_CSAR_fnc_HasSubscriber;")
    handback = body.index('[_group,"no-subscriber"] call ITW_CLASH_CSAR_fnc_Release;')
    guard = body.index("if (!_wanted) exitWith {true};")
    claim = body.index("[_group] call ITW_CLASH_CSAR_fnc_Claim;")
    # Held crews are handed back first, and the claim loop is behind the guard.
    assert wanted < handback < guard < claim


def test_a_subscription_is_willingness_not_availability():
    """A CSAR player already carrying another job must not stop a crew from
    escaping; whether that group can take this one is the dispatcher's test."""
    body = function_body(csar(), "ITW_CLASH_CSAR_fnc_HasSubscriber")
    assert "ITW_CLASH_PlayerTasks_fnc_IsSubscribed" in body
    assert "ITW_CLASH_CSARChannel" in body
    assert "HasActiveJob" not in body
    assert 'ITW_CLASH_CSARChannel = "MEDEVAC";' in csar()


# --- what may be claimed --------------------------------------------------


def test_only_a_player_side_crew_on_its_feet_is_claimed():
    body = code_only(tick())
    claim = body.index("[_group] call ITW_CLASH_CSAR_fnc_Claim;")
    for guard in [
        "side _group != ITW_PlayerSide",
        "call ITW_CLASH_CSAR_fnc_OnFoot",
        "call ITW_CLASH_CrewRemnant_fnc_IsReserved",
    ]:
        assert guard in body, guard
        assert body.index(guard) < claim, guard
    # Candidates come from cleanup's own roll, which CSAR reads and never writes.
    assert "forEach +ITW_CLASH_CrewRemnantQuarantined" in body
    assert "ITW_CLASH_CrewRemnantQuarantined pushBack" not in body


def test_a_parachute_is_not_a_crew_on_foot():
    """An ejected pilot reports the parachute from `vehicle`, so the same test
    CASEVAC commits on keeps CSAR off a crew still in the air - without an
    ejection event handler that a modded ejection could break."""
    body = function_body(csar(), "ITW_CLASH_CSAR_fnc_OnFoot")
    assert "vehicle _x != _x" in body
    assert "units _group select {alive _x}" in body
    assert "addEventHandler" not in csar()


def test_the_reservation_test_is_the_deleters_own():
    """If cleanup's list of other owners grows, CSAR must not keep a stale copy
    of it."""
    code = code_only(csar())
    assert "ITW_CLASH_CrewRemnant_fnc_IsReserved" in code
    for flag in [
        "ITW_CLASH_GroundMEDEVAC",
        "ITW_CLASH_ReconstitutionTransit",
        "ITW_CLASH_RecoveryOwned",
        "itwDelivery",
    ]:
        assert flag not in code, flag


# --- the gate is CASEVAC's gate -------------------------------------------


def test_the_gate_reuses_casevacs_numbers_rather_than_restating_them():
    source = csar()
    body = function_body(source, "ITW_CLASH_CSAR_fnc_Gate")
    for const in [
        "ITW_CLASH_CASEVAC_MinWithdrawalTime",
        "ITW_CLASH_CASEVAC_MinDisengageDistance",
        "ITW_CLASH_CASEVAC_ObjectiveClearance",
        "ITW_CLASH_CASEVAC_EnemyClearance",
    ]:
        assert const in body, const
        # Read, never redefined: one definition of battlefield safety.
        assert f"{const} =" not in source, const
    for helper in [
        "ITW_CLASH_CASEVAC_fnc_GetObjectiveClearance",
        "ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance",
        "ITW_CLASH_CASEVAC_fnc_FindLZ",
    ]:
        assert helper in body, helper


def test_the_expensive_tests_come_last():
    """The enemy scan is every member against every hostile unit and FindLZ is
    a safe-position search, so neither runs until the cheap ones pass."""
    body = code_only(function_body(csar(), "ITW_CLASH_CSAR_fnc_Gate"))
    order = [
        "ITW_CLASH_CSAR_fnc_OnFoot",
        "ITW_CLASH_CASEVAC_MinWithdrawalTime",
        "ITW_CLASH_CASEVAC_MinDisengageDistance",
        "ITW_CLASH_CASEVAC_fnc_GetObjectiveClearance",
        "ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance",
        "ITW_CLASH_CASEVAC_fnc_FindLZ",
    ]
    found = [body.index(token) for token in order]
    assert found == sorted(found), order


def test_the_crew_it_went_down_beside_is_the_objective_it_must_clear():
    body = function_body(csar(), "ITW_CLASH_CSAR_fnc_NearestObjective")
    assert "ITW_OBJ_POS" in body and "ITW_OBJ_SIZE" in body
    assert '#include "defines.hpp"' in csar()


# --- escape, then hold ----------------------------------------------------


def test_the_escape_is_the_missions_own_withdrawal_order():
    body = function_body(csar(), "ITW_CLASH_CSAR_fnc_OrderEscape")
    assert "ITW_CLASH_fnc_GetEgressPoint" in body
    assert "ITW_CLASH_fnc_OrderWithdrawal" in body
    # Provenance in the RPT: a crew escape is not a HAL withdrawal.
    assert '"csar-" + str _source' in body


def test_a_clear_crew_holds_at_the_pickup_point():
    body = function_body(csar(), "ITW_CLASH_CSAR_fnc_Escaping")
    hold = body.index('_entry set ["state","HOLDING"];')
    assert body.index("ITW_CLASH_CASEVAC_fnc_OrderLZ") > hold
    # Re-ordering the corridor move stops once it is holding.
    assert body.index("ITW_CLASH_CSAROrderCooldown") > hold


def test_a_held_crew_is_not_re_gated():
    """Once a rescue is offerable the battlefield changing is the player's
    problem, not a reason to withdraw the opportunity."""
    source = csar()
    # One caller, and it is the escape step.
    assert code_only(source).count("call ITW_CLASH_CSAR_fnc_Gate") == 1
    assert "call ITW_CLASH_CSAR_fnc_Gate" in function_body(
        source, "ITW_CLASH_CSAR_fnc_Escaping"
    )
    body = code_only(tick())
    escaping = body.index("call ITW_CLASH_CSAR_fnc_Escaping")
    assert body.index('case "ESCAPING"') < escaping < body.index('case "HOLDING"')


def test_the_waiting_line_says_why_it_is_not_offerable_yet():
    body = function_body(csar(), "ITW_CLASH_CSAR_fnc_Escaping")
    line = body[body.index('["waiting",['):]
    for field in ["_reason", "_measure#0", "_measure#1", "_measure#2"]:
        assert field in line, field
    gate = function_body(csar(), "ITW_CLASH_CSAR_fnc_Gate")
    for reason in ['"settling"', '"distance"', '"objective"', '"enemy"', '"lz"']:
        assert reason in gate, reason


# --- ownership and lifecycle ----------------------------------------------


def test_cleanup_still_owns_the_delete():
    """CSAR asks for a hold. It never removes a man or a group itself."""
    code = code_only(csar())
    for command in ["deleteVehicle", "deleteGroup", "deleteVehicleCrew"]:
        assert command not in code, command
    assert '_group setVariable ["ITW_CLASH_CSAR",true];' in code
    release = function_body(csar(), "ITW_CLASH_CSAR_fnc_Release")
    assert '_group setVariable ["ITW_CLASH_CSAR",nil]' in release


def test_a_claim_that_never_becomes_offerable_is_handed_back():
    body = code_only(tick())
    ceiling = body.index("ITW_CLASH_CSARClaimCeiling")
    # The ceiling is a claim ceiling, not a deadline on a rescue: it is only
    # reachable while the crew is still escaping.
    state = body.rindex('(_entry get "state") isEqualTo "ESCAPING"', 0, ceiling)
    assert ceiling - state < 160
    assert '"never-offerable"' in body


def test_no_deadline_anywhere_else():
    """A deadline on an accepted rescue could only live in the steps that run
    while one exists."""
    source = csar()
    for name in [
        "ITW_CLASH_CSAR_fnc_RunDelivery",
        "ITW_CLASH_CSAR_fnc_Offered",
        "ITW_CLASH_PlayerDemand_fnc_StillValid",
    ]:
        body = code_only(function_body(source, name))
        assert "time -" not in body, name
        for token in ["Deadline", "Timeout", "Expir"]:
            assert token not in body, (name, token)
    # The two clocks that do exist both run before a mission is published: the
    # gate's settling period, and the ceiling on an unoffered claim.
    assert 'time - (_entry get "onFootAt") < ITW_CLASH_CASEVAC_MinWithdrawalTime' in source
    assert 'time - (_entry get "onFootAt") > ITW_CLASH_CSARClaimCeiling' in source


def test_the_boot_line_says_what_it_will_not_do():
    source = csar()
    assert "ITW_CLASH_CSARVersion = 4;" in source
    for claim in [
        "writesWithdrawals=false",
        "aiDispatch=false",
        "publishesMission=true",
        "missionDeadline=none",
        "playerSideOnly=true",
    ]:
        assert claim in source, claim


# --- the mission ----------------------------------------------------------


def test_the_mission_rides_the_channel_the_player_ticked():
    body = function_body(csar(), "ITW_CLASH_CSAR_fnc_Publish")
    assert "ITW_CLASH_CSARChannel" in body
    assert "ITW_CLASH_CSARKind" in body
    assert "ITW_CLASH_PlayerDemand_fnc_Publish" in body
    assert "ITW_CLASH_CSAR_fnc_SourceKey" in body
    assert '"CSAR: Downed Crew"' in body
    # Published from the hold, not from the escape.
    body = code_only(tick())
    assert body.index('case "HOLDING"') < body.index("call ITW_CLASH_CSAR_fnc_Publish")
    assert 'ITW_CLASH_CSARKind = "CSAR_CREW";' in csar()


def test_the_dispatcher_is_extended_not_edited():
    """Both wrappers hand every other kind back to what was there before, the
    way the ammo validity hardening extends the same two functions."""
    source = csar()
    for name, base in [
        ("ITW_CLASH_PlayerDemand_fnc_StillValid", "ITW_CLASH_CSAR_fnc_StillValidBase"),
        ("ITW_CLASH_PlayerDemand_fnc_UpdateReserved", "ITW_CLASH_CSAR_fnc_UpdateReservedBase"),
    ]:
        assert f"{base} = {name};" in source, name
        body = function_body(source, name)
        assert 'getOrDefault ["kind",""]) isNotEqualTo ITW_CLASH_CSARKind' in body, name
        assert f"_this call {base}" in body, name
    # No branch for this kind in the owner file, and no call into this module.
    # Its one CSAR is the player-facing title on the casualty run, a label.
    dispatch = code_only(mission("ITW_CLASH_PlayerDemandDispatch.sqf"))
    assert "CSAR_CREW" not in dispatch
    assert "ITW_CLASH_CSAR" not in dispatch


def test_a_rescue_is_valid_while_there_is_a_crew_to_rescue():
    body = function_body(csar(), "ITW_CLASH_PlayerDemand_fnc_StillValid")
    assert '{alive _x} count units _crew) == 0' in body
    assert '_crew getVariable ["ITW_CLASH_CSAR",false]' in body
    # No clock in the validity test, which is where a deadline would hide.
    for token in ["time -", "time >", "time <"]:
        assert token not in body, token


def test_a_rescued_pilot_is_not_asked_to_be_a_casualty():
    """Every medical test in the dispatcher asks IsSevereCasualty, and a downed
    pilot is unhurt. The transfer rules around it are still the dispatcher's."""
    source = csar()
    assert "IsSevereCasualty" not in code_only(source)
    survivors = function_body(source, "ITW_CLASH_CSAR_fnc_Survivors")
    assert "alive _x && {vehicle _x == _x}" in survivors
    execution = function_body(source, "ITW_CLASH_CSAR_fnc_StartExecution")
    for reused in [
        "ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle",
        "ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity",
        "ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer",
        'emptyPositions "cargo"',
    ]:
        assert reused in execution, reused
    # The delivery distance is the dispatcher's.
    assert "ITW_CLASH_CSARHomeRadius" not in source


def test_survivors_walk_to_a_grounded_carrier_and_board_together():
    """2026-10-27, Hark: "polaris crew do not want to get in". v2 loaded only
    when every survivor already stood inside the dispatcher's 35m casualty
    radius and never told them to move."""
    source = csar()
    execution = code_only(function_body(source, "ITW_CLASH_CSAR_fnc_StartExecution"))
    assert "ITW_CLASH_PlayerDemandMedevacPickupRadius" not in execution
    gather = execution.index("_x distance2D _vehicle <= ITW_CLASH_CSARGatherRadius")
    board = execution.index("[_men,_vehicle,_demand] call ITW_CLASH_PlayerDemand_fnc_BoardOnFoot")
    executing = execution.index('_demand set ["state","EXECUTING"];')
    assert gather < board < executing
    assert "moveInCargo" not in execution
    # Seats are checked against the men still outside.
    assert '(_vehicle emptyPositions "cargo") >= count _survivors' in execution
    # A carrier that leaves mid-boarding releases the men outside.
    not_ready = execution[execution.index("if (!_ready) exitWith {"):board]
    assert "ITW_CLASH_PlayerDemand_fnc_CancelBoarding" in not_ready
    # The squad evac's gather distance.
    assert 'getVariable ["ITW_CLASH_CSARGatherRadius",300]' in source


def test_the_run_home_resolves_the_base_every_pass_and_ends_only_on_events():
    body = function_body(csar(), "ITW_CLASH_CSAR_fnc_RunDelivery")
    assert "ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup" in body
    assert "BIS_fnc_taskSetDestination" in body
    assert "ITW_CLASH_PlayerDemandMedevacHomeRadius" in body
    assert '"csar-carrier-lost"' in body
    # Cancel waits for the wheels to be down before it puts anyone out.
    cancel = body.index('ITW_CLASH_PlayerDemandCancel')
    grounded = body.index("ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer", cancel)
    assert grounded < body.index('"player-canceled-csar"')
    # Nobody is counted home until they are actually out of the vehicle.
    assert body.index("moveOut _x") < body.index("ITW_CLASH_PlayerDemand_fnc_Complete")


def test_a_recovery_pays_nothing_and_hands_the_crew_back():
    source = csar()
    for economy in [
        "ITW_AtkQueueReconstitution",
        "Reconstitution",
        "Checkbook",
        "ITW_VEH_COUNT",
    ]:
        assert economy not in source, economy
    body = function_body(source, "ITW_CLASH_CSAR_fnc_Recovered")
    assert 'call ITW_CLASH_CSAR_fnc_Release' in body


def test_an_accepted_rescue_survives_the_last_tick_being_removed():
    """A job a player has taken is theirs until something happens to it; only
    an unaccepted one is handed back when nobody is subscribed any more."""
    body = code_only(tick())
    assert '_accepted = ([_demandId] call ITW_CLASH_CSAR_fnc_DemandState)' in body
    assert 'in ["RESERVED","EXECUTING"]' in body
    assert "if (!_wanted && {!_accepted}) then {" in body
    # The hold is dropped first, so the mission ends through its own validity.
    release = body.index('[_group,"no-subscriber"] call ITW_CLASH_CSAR_fnc_Release;')
    demand = body.index('[_demandId,"csar-no-subscriber",false] call')
    assert release < demand


def test_the_tick_is_called_csar_and_nothing_behind_it_is_renamed():
    """The user's call: rename the job on player-facing text only. One opt-in
    covers casualty evacuation and crew recovery."""
    menu = mission("ITW_CLASH_PlayerEmploymentMenu.sqf")
    assert '["MEDEVAC","Accept Combat Search and Rescue Missions"]' in menu
    assert "Accept MEDEVAC Missions" not in menu
    # Both kinds on the channel read as CSAR to the player.
    for name in [
        "ITW_CLASH_PlayerDemandDispatch.sqf",
        "ITW_CLASH_PlayerDemandNativeInterceptors.sqf",
    ]:
        source = mission(name)
        assert '"CSAR: Casualties"' in source, name
        assert "HAL MEDEVAC" not in source, name

    # Behind the menu nothing moved, so no subscription is migrated.
    support = mission("ITW_CLASH_PlayerTaskSupport.sqf")
    assert '"COMBAT","TRANSPORT","MEDEVAC","LOGISTICS","ARTILLERY"' in support
    # The chat line names the channel CSAR; the stored id stays MEDEVAC.
    assert support.count("CSAR") == 1
    assert '["MEDEVAC","CSAR"]' in support
    assert '"MEDEVAC_SEVERE"' in mission("ITW_CLASH_PlayerDemandDispatch.sqf")


def test_finished_demands_leave_the_table():
    """CSAR_CREW publishes one demand per crew that survives its vehicle, and
    the 1 Hz loop walks every key, so terminal rows cannot accumulate for a
    whole campaign any more."""
    dispatch = mission("ITW_CLASH_PlayerDemandDispatch.sqf")
    assert "ITW_CLASH_PlayerDemandDispatchVersion = 5;" in dispatch
    assert "ITW_CLASH_PlayerDemandRetention" in dispatch
    assert "ITW_CLASH_PlayerDemands deleteAt _x;" in dispatch
    assert "prunesTerminalDemands=true" in dispatch
    prune = dispatch[dispatch.index("ITW_CLASH_PlayerDemands deleteAt _x;") - 600:]
    # Only finished rows, and only once they have been readable for a while.
    assert 'in ["COMPLETED","INVALID","FAILED"]' in prune.split("deleteAt _x;")[0]
    assert "ITW_CLASH_PlayerDemandRetention" in prune.split("deleteAt _x;")[0]
    # A pruned row cannot resurrect a mission: the lookup already skips
    # terminal states.
    find = function_body(dispatch, "ITW_CLASH_PlayerDemand_fnc_FindBySourceKey")
    assert 'in ["COMPLETED","INVALID","FAILED"]' in find


def test_csar_is_started_by_the_server_init_behind_casevac():
    init = mission("init.sqf")
    casevac = init.index('if (fileExists "ITW_CLASH_CASEVAC.sqf") then {')
    assert init.index('fileExists "ITW_CLASH_CSAR.sqf"') > casevac
    assert 'execVM "ITW_CLASH_CSAR.sqf"' in init
    assert "csar-missing" in init
    # Server only, and a second read cannot start a second loop.
    assert "if (!isServer) exitWith {false};" in csar()
    assert 'getVariable ["ITW_CLASH_CSARStarted",false]' in csar()
