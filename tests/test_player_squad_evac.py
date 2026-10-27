"""Players first for a withdrawing squad's lift (ITW_CLASH_PlayerSquadEvac.sqf v1).

2026-10-27, Hark: "when ai calls for MEDEVAC, no matter the cause, players get
first dibs." The player MEDEVAC job only fired for a man alive above 75% damage
or unable to stand, which vanilla AI almost never is; every squad actually cut
up withdrew and was lifted by AI CASEVAC or ground MEDEVAC, which players never
saw. The menu offers one tick: Combat Search and Rescue.

Same day: "Medevac has them withdraw and with a ton of checks before they can
radio for pickup, that's good behavior we shouldn't reserve just for the AI
pickup." So the squad behaves exactly as for an AI pilot: withdraw, call when
CASEVAC's own checks pass, hold the landing zone, pop smoke, abort on contact.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code_text(text: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


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
    raise AssertionError(f"unterminated {name}")


RAW = raw("ITW_CLASH_PlayerSquadEvac.sqf")
EVAC = code_text(RAW)


def test_boot_and_load_order():
    assert "ITW_CLASH_PlayerSquadEvacVersion = 1;" in RAW
    assert "CLASH BOOT | squad-evac-ready |" in RAW
    init = raw("init.sqf")
    # After CASEVAC, ground MEDEVAC and CSAR, inside CASEVAC's own block.
    assert init.index('[] execVM "ITW_CLASH_GroundMEDEVAC.sqf";') < init.index('[] execVM "ITW_CLASH_PlayerSquadEvac.sqf";')
    assert init.index('[] execVM "ITW_CLASH_CSAR.sqf";') < init.index('[] execVM "ITW_CLASH_PlayerSquadEvac.sqf";')


def test_one_tick_called_combat_search_and_rescue():
    menu = raw("ITW_CLASH_PlayerEmploymentMenu.sqf")
    assert '["MEDEVAC","Accept Combat Search and Rescue Missions"]' in menu
    assert "ITW_CLASH_PlayerEmploymentMenuVersion = 3;" in menu
    # The squad extraction rides the same channel: no new subscription.
    assert 'ITW_CLASH_PlayerSquadEvacChannel = "MEDEVAC";' in EVAC
    assert '"CSAR: Squad Extraction"' in EVAC


def test_the_call_is_casevacs_own_check_at_the_ais_own_moment():
    # The radio check is CASEVAC's unwrapped air eligibility: every safety gate
    # and the landing zone, nothing invented here.
    assert '!isNil "ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase"' in EVAC
    assert "ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase\n    };" in EVAC
    radio = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_Radio")
    assert "side _squad != ITW_PlayerSide" in radio
    check = radio.index("call ITW_CLASH_PlayerSquadEvac_fnc_RadioCheck")
    assert radio.index("ITW_CLASH_PlayerSquadEvac_fnc_PlayerAvailable") < check
    assert radio.index('"ITW_CLASH_PlayerSquadEvacRetryAt"') < check
    # Publish only after the check passes and a landing zone came back with it.
    assert check < radio.index("call ITW_CLASH_PlayerSquadEvac_fnc_Publish")
    assert "_data param [12,[]]" in radio
    # Nothing is offered at the start of a withdrawal any more.
    assert "Offerable" not in EVAC
    assert "MinEgress" not in EVAC


def test_both_ai_gates_ask_players_first():
    assert EVAC.count("if ([_entry] call ITW_CLASH_PlayerSquadEvac_fnc_PlayerHolds) exitWith {[false,[]]};") == 2
    assert EVAC.count("if ([_id,_entry] call ITW_CLASH_PlayerSquadEvac_fnc_Radio) exitWith {[false,[]]};") == 2
    assert "ITW_CLASH_PlayerSquadEvac_fnc_CasevacEligibleBase = ITW_CLASH_CASEVAC_fnc_Eligible;" in EVAC
    assert "ITW_CLASH_PlayerSquadEvac_fnc_GroundEligibleBase = ITW_CLASH_GroundMEDEVAC_fnc_Eligible;" in EVAC
    # The tick asks too, so a call never waits on a free AI slot.
    tick = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_Tick")
    assert "call ITW_CLASH_PlayerSquadEvac_fnc_Radio" in tick


def test_nobody_free_hands_the_call_to_the_ai_without_flapping():
    radio = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_Radio")
    assert "ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup" in radio
    hand = radio[radio.index("} else {"):radio.index("if (_demandId isNotEqualTo \"\") exitWith {_owned};")]
    assert '[_demandId,"no-player-free"] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;' in hand
    assert '[_demandId,"INVALID","no-player-free"] call ITW_CLASH_PlayerDemand_fnc_SetState;' in hand
    assert '"ITW_CLASH_PlayerDemandDeclineCooldown",120' in hand
    # No player free at all: the AI's own gate decides, unchanged.
    assert "if !(call ITW_CLASH_PlayerSquadEvac_fnc_PlayerAvailable) exitWith {false};" in radio


def test_the_squad_holds_the_landing_zone_as_for_an_ai_pilot():
    hold = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_HoldAtLz")
    assert '[_demandId,"player-lz"] call ITW_CLASH_PlayerSquadEvac_fnc_HoldSquad;' in hold
    assert "[_squad,_lz] call ITW_CLASH_CASEVAC_fnc_OrderLZ;" in hold
    lock = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_HoldSquad")
    assert '_squad setVariable ["ITW_CLASH_CASEVAC_State",_state];' in lock
    assert "_entry set [8,time + 1e6];" in lock


def test_contact_at_the_landing_zone_aborts_as_casevac_aborts():
    prepare = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_Prepare")
    for name in [
        "ITW_CLASH_CASEVAC_CommitDistance",
        "ITW_CLASH_CASEVAC_CommittedAbortClearance",
        "ITW_CLASH_CASEVAC_InboundAbortClearance",
        "ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance",
    ]:
        assert name in prepare, name
    assert '[_demandId,"contact-at-lz"] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;' in prepare
    # Moving on, it calls again from the next safe spot, for the same player.
    again = prepare.index('if !(_demand getOrDefault ["squadHeld",false]) exitWith {')
    assert prepare.index("ITW_CLASH_PlayerSquadEvac_fnc_RadioCheck", again) > again
    assert '"radio-again"' in prepare


def abort_clearance(carrier_to_lz, commit=800, inbound=450, committed=150):
    return committed if carrier_to_lz <= commit else inbound


def test_abort_model():
    assert abort_clearance(2000) == 450
    assert abort_clearance(700) == 150


def test_pickup_gathers_to_a_grounded_carrier_and_loads_at_once():
    prepare = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_Prepare")
    ready = prepare.index("private _ready =")
    assert "ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer" in prepare[ready:ready + 400]
    assert "<= ITW_CLASH_PlayerSquadEvacGatherRadius" in prepare[ready:ready + 400]
    # A carrier that lifts before loading sends them back to the landing zone.
    assert '"carrier-left-back-to-lz"' in prepare
    load = prepare.index("_x moveInCargo _vehicle;")
    assert prepare.index("> ITW_CLASH_PlayerSquadEvacLoadRadius") < load
    assert prepare.index('(_vehicle emptyPositions "cargo") < count _survivors') < load
    assert prepare.index('_squad setVariable ["ITW_CLASH_CASEVAC_State","player-rtb"];') > load


def test_smoke_on_the_held_landing_zone_within_casevacs_distance():
    smoke = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_Smoke")
    assert '["player-lz","player-pickup"]' in smoke
    assert "(_vehicle distance2D _lz) > ITW_CLASH_CASEVAC_SmokeDistance" in smoke
    assert 'createVehicle [ITW_CLASH_CASEVAC_SmokeClass,_lz,[],0,"CAN_COLLIDE"]' in smoke
    assert "ITW_CLASH_PlayerSquadEvacSmokeRepop <= 0" in smoke
    assert 'ITW_CLASH_PlayerSquadEvacSmokeRepop",120]' in EVAC


def smoke_due(distance, last, now, repop, smoke_distance=700):
    if distance > smoke_distance:
        return False
    if last >= 0 and (repop <= 0 or now - last < repop):
        return False
    return True


def test_smoke_model():
    assert not smoke_due(900, -1, 0, 120)
    assert smoke_due(650, -1, 0, 120)
    assert not smoke_due(400, 100, 160, 120)
    assert smoke_due(400, 100, 220, 120)
    assert not smoke_due(400, 100, 1000, 0)


def test_validity_tracks_ownership():
    start = EVAC.index("ITW_CLASH_PlayerDemand_fnc_StillValid = {")
    valid = EVAC[start:EVAC.index("ITW_CLASH_PlayerSquadEvac_fnc_UpdateReservedBase", start)]
    assert '_casevac in ["","player-lz"]' in valid
    assert "_casevac in ITW_CLASH_PlayerSquadEvacStates" in valid
    assert '(_entry#0) isNotEqualTo _squad' in valid
    assert "_this call ITW_CLASH_PlayerSquadEvac_fnc_StillValidBase" in valid
    assert 'ITW_CLASH_PlayerSquadEvacStates = ["player-lz","player-pickup","player-rtb"];' in EVAC


def test_binds_outside_the_dispatchers_own_layers():
    assert 'missionNamespace getVariable ["ITW_CLASH_PlayerDemandReservationHardeningReady",false]' in EVAC
    update = EVAC[EVAC.index("ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {"):]
    first = update.index("_this call ITW_CLASH_PlayerSquadEvac_fnc_UpdateReservedBase;")
    assert first < update.index("[_demandId] call ITW_CLASH_PlayerSquadEvac_fnc_Prepare")
    assert "if (_kind isEqualTo ITW_CLASH_PlayerSquadEvacKind) exitWith {ITW_CLASH_PlayerSquadEvacMarker};" in EVAC
    assert EVAC.count("[_demand] call ITW_CLASH_PlayerSquadEvac_fnc_ClearMarker;") == 2


def test_handing_back_restores_the_walk_and_the_pad():
    back = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad")
    assert "in ITW_CLASH_PlayerSquadEvacStates" in back
    assert "call ITW_CLASH_fnc_OrderWithdrawal;" in back
    assert "[_squad] call ITW_CLASH_PlayerSquadEvac_fnc_ClearPad;" in back
    assert "RetryAt" not in back


def test_delivery_is_the_withdrawal_audits_absorption():
    run = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_RunDelivery")
    gone = run.index("if (_entry isEqualTo []) exitWith {")
    block = run[gone:run.index("_taskId isNotEqualTo", gone)]
    assert "(_vehicle distance2D _rally) <= _arrival" in block
    assert '"squad-delivered-to-rally-point"] call ITW_CLASH_PlayerDemand_fnc_Complete;' in block
    assert "time - _arrivedAt >= ITW_CLASH_PlayerSquadEvacDeliveryHold" in run
    assert run.count("[_vehicle,_evacuees] call ITW_CLASH_PlayerSquadEvac_fnc_Unload;") == 2
    for unload in re.finditer(r"\[_vehicle,_evacuees\] call ITW_CLASH_PlayerSquadEvac_fnc_Unload;", run):
        assert "_grounded" in run[max(0, unload.start() - 400):unload.start()]
    assert "ITW_AtkQueueReconstitution" not in EVAC


def test_no_exitwith_hides_inside_a_then_block():
    run = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_RunDelivery")
    assert "exitWith" not in run[run.index("private _grounded"):]
    prepare = body_of(EVAC, "ITW_CLASH_PlayerSquadEvac_fnc_Prepare")
    abort = prepare[prepare.index('if (_state isEqualTo "player-lz"'):prepare.index('if !(_demand getOrDefault ["squadHeld",false]) exitWith {')]
    assert "exitWith" not in abort
