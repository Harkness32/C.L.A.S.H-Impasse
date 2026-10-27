"""Request Transport: lift a real squad along its own orders (adapter v2).

2026-10-27, Hark: a transport pilot can ask for work the way a strike player
can. The request finds a real AI squad of ours on foot at or near a base with a
long walk to its destination - nothing is spawned - and the squad is taken off
HAL for the ride, then handed back on the drop.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code_text(text: str) -> str:
    return re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


def raw(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def body_of(source: str, name: str) -> str:
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
    raise AssertionError(name)


RAW = raw("ITW_CLASH_PlayerTaskRequestTransport.sqf")
CODE = code_text(RAW)


def test_the_slot_the_bootstrap_expected_is_filled_and_registered():
    assert '["TRANSPORT","ITW_CLASH_PlayerTaskRequestTransport.sqf"]' in raw("ITW_CLASH_PlayerTaskRequestBootstrap.sqf")
    assert '"TRANSPORT"' in raw("ITW_CLASH_PlayerTaskRequests.sqf")
    assert '["TRANSPORT",ITW_CLASH_PlayerTaskRequestTransport_fnc_Request] call' in CODE
    assert "ITW_CLASH_PlayerTaskRequestTransportVersion = 2;" in RAW
    assert "CLASH BOOT | player-task-request-transport-ready |" in RAW
    assert "spawnsNothing=true" in RAW


def test_nothing_is_spawned():
    for verb in ["createGroup", "createUnit", "createVehicle", "ITW_AtkSpawn", "ITW_AtkUnitToGroup"]:
        assert verb not in CODE, verb


def test_candidates_are_real_squads_waiting_at_a_base():
    body = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Candidates")
    for gate in [
        "forEach +ITW_CLASH_DualHALBLUFORGroups;",
        "side _squad != ITW_PlayerSide",
        "ITW_CLASH_DualHAL_fnc_IsPlayerGroup",
        "_squad in _specFor",
        "count _alive > _seats",
        'vehicle _x != _x || {!(_x isKindOf "CAManBase")}',
        '"ITW_CLASH_Withdrawing"',
        '"ITW_CLASH_AnchorObjective"',
        "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved",
        "[getPosATL _leader] call ITW_BaseNearest",
        "> ITW_CLASH_PlayerLiftBaseRadius",
        "_far < ITW_CLASH_PlayerLiftMinDistance",
    ]:
        assert gate in body, gate
    # A squad HAL already queued for a lift of its own is never taken.
    assert '"CargoCheckPending" + str _squad' in body
    assert '"CargoChosen"' in body
    assert '"AssignedCargo" + str _squad' in body
    # Nearest to the pilot first.
    assert "{_x#4},\"ASCEND\"] call BIS_fnc_sortBy" in body


def test_destination_is_the_squads_own_unfinished_orders():
    body = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Destination")
    assert "waypointPosition [_squad,_count - 1]" in body
    # A squad with no orders, or orders it has finished, is HAL's reserve.
    assert "if (_count == 0 || {currentWaypoint _squad >= _count}) exitWith {[[],\"\"]};" in body
    assert '"fob-air-defence"' in body
    assert '"orders"' in body
    # v1 guessed COLOSSUS's plan objective for an orderless squad.
    assert "ColossusPlans" not in CODE
    assert "colossus-plan" not in CODE
    # No exitWith hidden in a then block (the CLASH scope trap).
    for block in re.findall(r"then \{([^{}]*)\}", body):
        assert "exitWith" not in block, block


def test_the_task_says_where_the_orders_lead():
    text = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_DestinationText")
    assert "for air defence" in text
    assert "_x#ITW_OBJ_HIDDEN" in text
    assert "ITW_OBJ_NAME" in text
    assert "ITW_OWNER_FRIENDLY" in text
    request = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Request")
    assert "[_destination,_source] call ITW_CLASH_PlayerTaskRequestTransport_fnc_DestinationText" in request
    assert "the front" not in CODE


def test_the_drop_zone_is_marked_from_assignment_and_cleared_at_the_end():
    request = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Request")
    assert "createMarker [_zone,_destination];" in request
    assert '_zone setMarkerShape "ELLIPSE";' in request
    assert "_zone setMarkerSize [ITW_CLASH_PlayerLiftDropRadius,ITW_CLASH_PlayerLiftDropRadius];" in request
    assert "createMarker [_drop,_destination];" in request
    assert request.index('_job set ["markers",[_zone,_drop]];') < request.index("call BIS_fnc_taskCreate")
    finish = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish")
    assert '{deleteMarker _x} forEach (_job getOrDefault ["markers",[]]);' in finish


def test_the_squad_is_off_hal_for_the_ride_and_back_on_the_drop():
    request = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Request")
    mark = request.index('_squad setVariable ["ITW_CLASH_PlayerLift",_jobId];')
    assert request.index('_squad setVariable ["Break",true]', mark) > mark
    assert "call ITW_CLASH_DualHAL_fnc_SyncIncluded" in request
    # The reservation reads as lifecycle-reserved, which is what drops a group
    # from the BLUFOR layer's Included list.
    assert "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved = {" in CODE
    assert '(_group getVariable ["ITW_CLASH_PlayerLift",""]) isNotEqualTo ""' in CODE
    sync = body_of(code_text(raw("ITW_CLASH_DualHALCheckbook.sqf")), "ITW_CLASH_DualHAL_fnc_SyncIncluded")
    assert "ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup" in sync
    owner = body_of(code_text(raw("ITW_CLASH_DualHALCheckbook.sqf")), "ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup")
    assert "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" in owner
    # Release: the mark clears, Break is not left set to kill HAL's next task,
    # and the squad keeps moving toward its destination until HAL retasks it.
    release = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_ReleaseSquad")
    assert '_squad setVariable ["ITW_CLASH_PlayerLift",nil];' in release
    assert '_squad setVariable ["Break",nil];' in release
    assert '_squad addWaypoint [_destination,50]' in release
    assert "call ITW_CLASH_DualHAL_fnc_SyncIncluded" in release


def test_pickup_gathers_to_a_grounded_carrier_and_loads_at_once():
    pickup = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Pickup")
    ready = pickup.index("private _ready =")
    assert "ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer" in pickup[ready:ready + 400]
    assert "<= ITW_CLASH_PlayerLiftGatherRadius" in pickup[ready:ready + 400]
    load = pickup.index("_x moveInCargo _vehicle;")
    assert pickup.index("> ITW_CLASH_PlayerLiftLoadRadius") < load
    assert pickup.index('(_vehicle emptyPositions "cargo") < count _men') < load
    assert pickup.index('_job set ["phase","CARRY"];') > load


def test_the_job_ends_on_the_ground_near_the_destination():
    monitor = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Monitor")
    assert "_grounded && {(_carrier distance2D _destination) <= ITW_CLASH_PlayerLiftDropRadius}" in monitor
    assert '"COMPLETED","squad-delivered"' in monitor
    assert '"FAILED","carrier-lost"' in monitor
    assert '"CANCELED","pickup-timeout"' in monitor
    assert '"CANCELED","squad-withdrawing"' in monitor
    # Cancel mid-flight waits for the ground before anyone gets out.
    cancel = monitor[monitor.index('case (_group getVariable ["ITW_CLASH_PlayerLiftJobCancel",false]): {\n                    if (_grounded)'):]
    assert cancel.index("if (_grounded)") < cancel.index("ITW_CLASH_PlayerTaskRequestTransport_fnc_Unload")


def test_reward_seam_and_router_hooks():
    finish = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish")
    assert '["rewardClass","TRANSPORT"]' in finish
    assert '"PLAYER_TASK_REWARD_AUTHORIZED"' in finish
    router = raw("ITW_CLASH_PlayerTaskRequests.sqf")
    assert "ITW_CLASH_PlayerTaskRequestsVersion = 4;" in router
    assert 'if (_requestType == "TRANSPORT" && {' in router
    assert "ITW_CLASH_PlayerTaskRequestTransport_fnc_Finish" in router
    assert 'private _liftJob = _group getVariable ["ITW_CLASH_PlayerLiftJobId",""];' in CODE


def test_no_capability_and_no_task_answers():
    request = body_of(CODE, "ITW_CLASH_PlayerTaskRequestTransport_fnc_Request")
    assert '"NO_CAPABILITY","Get in a vehicle with passenger seats' in request
    assert '"NO_TASK",format ["No squad with orders is at a base' in request
