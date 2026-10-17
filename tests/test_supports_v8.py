"""Supports v8 and airborne v3: what the first console tests showed.

2026-10-17, Hark, after the first console tests of the drops:

- No vehicle delivery flew. GUER fields no cars, so every test was refused
  NO_VEHICLE_FIT before anything spawned; the carrier would have been GUER's
  Ghost Hawk (WEST's Huron), since the side's own carriers came before the
  Blackfish, which neither side lists. Hark: the Blackfish first (1A); try
  cars, then APCs and tanks, and let the loading decide (2B); a side with no
  troop plane flies the Blackfish's infantry variant (3A).
- "The huron lands, drops two dudes off and then goes forward into the zone":
  nobody may leave before the jump, and anything that tries is logged.
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


CORE = code_text(raw("ITW_CLASH_Supports.sqf"))
AIRBORNE = code_text(raw("ITW_CLASH_SupportsAirborne.sqf"))


def test_versions():
    assert "ITW_CLASH_SupportsVersion = 8;" in raw("ITW_CLASH_Supports.sqf")
    assert "ITW_CLASH_SupportsAirborneVersion = 3;" in raw("ITW_CLASH_SupportsAirborne.sqf")


# ------------------------------------------------------------ 1A the carrier


def test_the_blackfish_comes_before_the_sides_own_carriers():
    pick = function_body(CORE, "ITW_CLASH_Supports_fnc_PickClass")
    viv = pick[pick.index('case "VIV": {'):pick.index('case "HELI";')]
    own = viv.index('if (_own isNotEqualTo []) exitWith {[_own#0,""]};')
    preferred = viv.index('if (_preferred isNotEqualTo []) exitWith {[_preferred#0,""]};')
    lifters = viv.index("CarrierLoad")
    assert own < preferred < lifters


def test_model_carrier_order():
    def pick(preferred, side_carriers, loads):
        own = [c for c in preferred if c in side_carriers]
        if own:
            return own[0]
        if preferred:
            return preferred[0]
        if side_carriers:
            return max(side_carriers, key=lambda c: loads[c])
        return ""
    loads = {"ghosthawk": 2000, "huron": 10000, "blackfish": 30000}
    # 2026-10-17: neither side lists the Blackfish.
    assert pick(["blackfish"], ["ghosthawk"], loads) == "blackfish"
    assert pick(["blackfish"], ["huron", "ghosthawk"], loads) == "blackfish"
    # A host who empties the list gets the side's own strongest lifter.
    assert pick([], ["huron", "ghosthawk"], loads) == "huron"
    assert pick([], [], loads) == ""


# ------------------------------------------------- 2B what can be delivered


def test_delivery_is_cars_then_apcs_then_tanks_that_can_be_carried():
    tiers = function_body(CORE, "ITW_CLASH_Supports_fnc_DeliveryTiers")
    assert '["Car","Apc","Tank"] apply {' in tiers
    assert '} forEach ["ClassesAttack","ClassesDual"];' in tiers
    assert 'getNumber (configFile >> "CfgVehicles" >> _class >> "VehicleTransport" >> "Cargo" >> "canBeTransported") == 1' in tiers
    assert '_class isKindOf "LandVehicle"' in tiers
    classes = function_body(CORE, "ITW_CLASH_Supports_fnc_Classes")
    assert 'if (_kind isEqualTo "DELIVERY") exitWith {' in classes
    assert "([_side] call ITW_CLASH_Supports_fnc_DeliveryTiers)" in classes


def test_the_run_tries_in_tier_order_shuffled_within_each():
    run = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_RunVehicle")
    assert "{_cars append (_x call BIS_fnc_arrayShuffle)} forEach ([_side] call ITW_CLASH_Supports_fnc_DeliveryTiers);" in run
    assert '[_side,"CAR"] call ITW_CLASH_Supports_fnc_Classes' not in run
    load = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_LoadVehicle")
    assert "} forEach _cars;" in load
    assert "BIS_fnc_arrayShuffle" not in load


def test_a_side_with_nothing_to_carry_is_never_offered_a_delivery():
    gate = function_body(CORE, "ITW_CLASH_Supports_fnc_FlavorGate")
    assert 'case ((_row getOrDefault ["aircraft",""]) isEqualTo "VIV" && {([_side,"DELIVERY"] call ITW_CLASH_Supports_fnc_Classes) isEqualTo []}): {"NO_VEHICLE_FIT"};' in gate
    # Refused before the money is read, so it never reads as "saving up".
    assert gate.index('{"NO_VEHICLE_FIT"}') < gate.index('{"INSUFFICIENT_FUNDS"}')
    direct = function_body(CORE, "ITW_CLASH_Supports_fnc_DirectPick")
    assert 'if (([_side,"DELIVERY"] call ITW_CLASH_Supports_fnc_Classes) isEqualTo []) then {_failed = "NO_VEHICLE_FIT"};' in direct


# ------------------------------------------------------- 3A the troop plane


def test_a_side_without_a_troop_plane_flies_the_preferred_one():
    source = raw("ITW_CLASH_Supports.sqf")
    assert '["ITW_CLASH_SupportsPlaneTroopClasses",["B_T_VTOL_01_infantry_F"]]' in source
    pick = function_body(CORE, "ITW_CLASH_Supports_fnc_PickClass")
    plane = pick[pick.index('case "HELI";'):]
    assert 'if (_carriers isEqualTo [] && {_kind isEqualTo "PLANE"}) then {' in plane
    assert plane.index("ITW_CLASH_SupportsPlaneTroopClasses select") < plane.index('if (_carriers isEqualTo []) exitWith {["","NO_AIRCRAFT"]};')
    assert "planeTroop=%46" in source


# --------------------------------------------- "the huron lands" (airborne v3)


def test_the_squads_ride_without_a_will_of_their_own():
    hold = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_HoldCargo")
    assert "_veh setUnloadInCombat [false,false]" in hold
    assert '_x disableAI "AUTOCOMBAT"' in hold and '_x enableAI "AUTOCOMBAT"' in hold
    assert '_group setBehaviourStrong "CARELESS"' in hold and '_group setBehaviour "AWARE"' in hold
    run = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_Run")
    held = run.index("[_veh,_squads,true] call ITW_CLASH_SupportsAirborne_fnc_HoldCargo;")
    assert run.index('["boarded",[') < held < run.index("while {_result isEqualTo []} do {")
    jump = run.index("[_veh,grpNull,_squads,[]] call ITW_AtkUnloadAirplane;")
    released = run.index("[_veh,_squads,false] call ITW_CLASH_SupportsAirborne_fnc_HoldCargo;")
    assert jump < released
    lost = run[run.index('case "LOST": {'):]
    assert "[_veh,_squads,false] call ITW_CLASH_SupportsAirborne_fnc_HoldCargo;" in lost


def test_a_passenger_who_is_told_to_get_out_is_put_back_and_said():
    keep = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_KeepAboard")
    assert "if ((assignedVehicle _unit) isNotEqualTo _veh) then {" in keep
    assert "_unit assignAsCargo _veh;" in keep and "[_unit] orderGetIn true;" in keep
    for event in ['"passenger-reassigned"', '"passenger-out-early"', '"touched-down"']:
        assert event in keep, event
    # Each said once.
    assert "if !(_unit in _reassigned) then {" in keep
    assert "if !(_unit in _early) then {" in keep
    assert "if (!_touched && {isTouchingGround _veh || {((getPos _veh)#2) < 3}}) then {" in keep
    run = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_Run")
    loop = run[run.index("while {_result isEqualTo []} do {"):run.index('switch (_result#0) do {')]
    assert "[_support,_veh,_aboard,_dz,_keep] call ITW_CLASH_SupportsAirborne_fnc_KeepAboard;" in loop
    # The release line carries the count of each.
    assert "count (_keep#1),count (_keep#0),_keep#2" in run


def test_boarding_never_overfills():
    # Hark asked whether the Huron was packed too full: a man without a seat
    # is deleted at the base, and a squad under strength stays home.
    board = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_Board")
    assert "_x moveInCargo _veh;" in board
    assert "deleteVehicle _x;" in board
    assert "< ITW_CLASH_SupportsAirborneMinSquad) then {" in board
