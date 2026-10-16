"""HAL helicopter sorties fly a rack-sized ring instead of HAL's radius-0 point.

Run of 2026-10-15: stub-wing Ghost Hawks sent by HAL's GoAttAir held 15 to 200
m from their target on a radius-0 search-and-destroy waypoint, with DAGR-M
that the AI fires only from 300 m. C.L.A.S.H. HAL Additions' copy of GoAttAir
hands helicopter sorties to ITW_CLASH_HeliAttack_fnc_Fly; HAL keeps the
target, the moment, the sortie limits and the return leg.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal"
ADD = ROOT / "CLASH HAL Additions" / "addons" / "clash_hal_additions"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def code(name: str) -> str:
    return strip_comments(read(MISSION / name))


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


def heli() -> str:
    return code("ITW_CLASH_HeliAttack.sqf")


def lines(source: str):
    return [line.strip() for line in source.splitlines() if line.strip()]


# ------------------------------------------------------------ the HAL copy


def original() -> str:
    return read(NR6 / "HAL" / "GoAttAir.sqf")


def copy() -> str:
    return read(ADD / "hal" / "GoAttAir.sqf")


def test_goattair_is_swapped():
    overrides = read(ADD / "functions" / "fnc_overrides.sqf")
    assert '["HAL_GoAttAir","GoAttAir.sqf"]' in overrides


def test_the_copy_keeps_every_line_of_hals_in_order():
    # Re-indented inside the else-branch, but nothing of HAL's removed or moved.
    theirs = lines(original())
    ours = lines(strip_comments(copy()))
    at = 0
    for line in theirs:
        if line.startswith("//"):
            continue
        found = ours.index(line, at) if line in ours[at:] else -1
        assert found >= 0, line
        at = found + 1


def test_the_copy_adds_only_the_helicopter_branch():
    theirs = set(lines(strip_comments(original())))
    added = [line for line in lines(strip_comments(copy())) if line not in theirs]
    assert added == [
        "_cause = [];",
        "_timer = 0;",
        "_alive = true;",
        "_clashHeli = (",
        "!(isPlayer (leader _unitG))",
        '&& {!isNil "ITW_CLASH_HeliAttack_fnc_Fly"}',
        '&& {!isNil "ITW_CLASH_Rack_fnc_Profile"}',
        "&& {(count _flight) > 0}",
        '&& {({not (_x isKindOf "Helicopter")} count _flight) == 0}',
        ");",
        "if (_clashHeli) then",
        'diag_log format ["CLASHHALADD | goattair-heli | group=%1 flight=%2",_unitG,_flight apply {typeOf _x}];',
        "_clashResult = [_unitG,_HQ,_Trg,[_posX,_posY],_flight] call ITW_CLASH_HeliAttack_fnc_Fly;",
        "_alive = _clashResult select 0;",
        "_timer = 0;",
        "_wp = [];",
        "}",
        "else",
    ], added


def test_what_the_branch_skips_is_declared_before_it():
    source = strip_comments(copy())
    branch = source.index("if (_clashHeli) then")
    for name in ["_lasT = ObjNull;", "_cause = [];", "_timer = 0;", "_alive = true;"]:
        assert source.index(name) < branch, name


def test_the_return_leg_is_hals():
    tail_from = '_unitG setVariable ["CurrCASLazeOff",true];'
    theirs = original()
    ours = copy()
    assert theirs[theirs.index(tail_from):].strip() == ours[ours.index(tail_from):].strip()


def test_planes_and_player_leads_take_hals_path():
    source = strip_comments(copy())
    gate = source[source.index("_clashHeli = ("):source.index("if (_clashHeli) then")]
    assert "!(isPlayer (leader _unitG))" in gate
    assert '({not (_x isKindOf "Helicopter")} count _flight) == 0' in gate


# ------------------------------------------------------------ the sortie


def test_it_never_fires_and_never_reads_ground_truth():
    source = heli()
    for verb in ["fireAtTarget", "doFire", "commandFire", "forceWeaponFire", "doTarget", "setAmmo",
                 "setVehicleAmmo", "allUnits", "nearEntities", "nearestObjects", "getPosATL _target"]:
        assert verb not in source, verb
    brief = function_body(source, "ITW_CLASH_HeliAttack_fnc_Brief")
    assert 'forEach (_hq getVariable ["RydHQ_KnEnemies",[]]);' in brief
    assert "_group reveal [vehicle _x,1.5];" in brief


def test_centres_are_reported_and_precise_enough():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_PickCentre")
    assert "forEach ([_side] call ITW_CLASH_Knowledge_fnc_Contacts);" in body
    assert "if (_r > ITW_CLASH_HeliAttackMaxUncertainty) then {continue};" in body
    assert "if (_distance > ITW_CLASH_HeliAttackRetargetRadius) then {continue};" in body
    # Only a contact the rack can hit.
    assert "if (((_types getOrDefault [_type,[0,-1,\"\"]])#0) <= 0) then {continue};" in body
    assert '[+_ordered,_type,"hal-point"]' in body


def test_hals_sortie_limits_end_it():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Stop")
    assert "damage _x > ITW_CLASH_HeliAttackMaxDamage" in body
    assert "fuel _x < ITW_CLASH_HeliAttackMinFuel" in body
    assert "(time - _started) > ITW_CLASH_HeliAttackMaxTime" in body
    raw = read(MISSION / "ITW_CLASH_HeliAttack.sqf")
    assert 'ITW_CLASH_HeliAttackMaxDamage",0.5]' in raw
    assert 'ITW_CLASH_HeliAttackMinFuel",0.3]' in raw
    assert 'ITW_CLASH_HeliAttackMaxTime",1200]' in raw
    hal = original()
    assert "((damage _x) > 0.5) or ((fuel _x) < 0.3)" in hal


def test_another_owner_wins_before_any_limit():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Stop")
    order = [
        body.index('"lost"'),
        body.index('"mia"'),
        body.index('"break"'),
        body.index('"withdrawing"'),
        body.index('"released"'),
        body.index('"rtb-condition"'),
        body.index('"time"'),
    ]
    assert order == sorted(order)
    assert 'ITW_CLASH_HeliAttackForeignStops = ["lost","mia","break","withdrawing","released"];' in heli()


def test_mia_is_acknowledged_as_hals_waiter_does():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Stop")
    assert 'if (_group getVariable ["RydHQ_MIA",false]) exitWith {_group setVariable ["RydHQ_MIA",nil]; "mia"};' in body
    hal = read(NR6 / "HAC_fnc.sqf")
    assert 'case ((_this select 0) getVariable ["RydHQ_MIA",false]) : {_alive = false;(_this select 0) setVariable ["RydHQ_MIA",nil]};' in hal


def test_the_withdrawals_it_yields_to_still_signal_the_way_it_reads():
    # CLASH's own withdrawal breaks the group; GTFO's keeps it HAL-managed
    # and only marks it withdrawing. If either changes, the sortie stops
    # noticing and its legs overwrite the withdrawal move.
    base = function_body(code("ITW_CLASH.sqf"), "ITW_CLASH_fnc_StartWithdrawal")
    assert '_group setVariable ["Break",true];' in base
    gtfo = function_body(code("ITW_CLASH_GTFO.sqf"), "ITW_CLASH_fnc_StartWithdrawal")
    assert '_group setVariable ["ITW_CLASH_Withdrawing",true];' in gtfo
    assert gtfo.index('"ITW_CLASH_Withdrawing",true') < gtfo.index("call ITW_CLASH_fnc_OrderWithdrawal")
    order = function_body(code("ITW_CLASH.sqf"), "ITW_CLASH_fnc_OrderWithdrawal")
    assert "addWaypoint" in order


def test_each_leg_is_checked_and_ordered_in_one_step():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    leg = fly[fly.index("// One step around the ring.") if "// One step" in fly else fly.index("_bearing = _bearing + (_direction * _step);"):]
    block = leg[leg.index("isNil {"):]
    block = block[:block.index("if (_reason isNotEqualTo \"\") exitWith {};")]
    assert "_reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;" in block
    assert block.index("fnc_Stop") < block.index("addWaypoint") < block.index("doMove")
    assert "_wp setWaypointName ITW_CLASH_HeliAttackWaypointName;" in block


def test_a_taken_group_keeps_its_new_owners_orders():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    cleanup = fly[fly.index("removeEventHandler"):]
    assert "isNil {" in cleanup
    foreign = cleanup[cleanup.index("if (_reason in ITW_CLASH_HeliAttackForeignStops) then {"):]
    foreign_branch, own_branch = foreign.split("} else {", 1)
    assert "waypointName [_group,_i]" in foreign_branch
    assert "ITW_CLASH_HeliAttack_fnc_ClearWaypoints" not in foreign_branch
    assert '_mode isEqualTo "ORBIT"' in foreign_branch
    assert "[_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;" in own_branch.split("};", 1)[0]
    # A late foreign reason supersedes a sortie's own ending.
    assert "if (_late in ITW_CLASH_HeliAttackForeignStops) then {_reason = _late};" in cleanup
    assert "private _alive = !(_reason in ITW_CLASH_HeliAttackForeignStops);" in fly


def test_a_taken_group_skips_hals_return_leg():
    # GoAttAir's not-alive exit issues no waypoint; the return leg is after it.
    source = strip_comments(copy())
    exit_at = source.index("if not (_alive) exitwith")
    rtb_at = source.index('_wp = [_unitG,_Posland,"MOVE","SAFE","GREEN"')
    assert exit_at < rtb_at
    exit_block = source[exit_at:source.index("if (_timer > 120)", exit_at)]
    assert "RYD_WPadd" not in exit_block
    assert '_unitG setVariable [("Busy" + (str _unitG)),false];' in exit_block


def test_an_empty_rack_or_nothing_to_hit_goes_home():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    assert '[true,"rack-empty"]' in fly
    assert '_reason = "winchester"' in fly
    assert '_reason = if (_hadTarget) then {"clear"} else {"nothing-to-hit"};' in fly
    assert '_source = "hal-point-hold";' in fly
    assert "if (_emptyPasses >= ITW_CLASH_HeliAttackClearLaps) exitWith {" in fly


def test_weapons_free_each_pass_and_lift_limits_cleared():
    # v2: fire at will (YELLOW) with attack off, so the crew shoots from its
    # line instead of leaving it to close in, as RED let it on 2026-10-16.
    arm = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Arm")
    assert '"RED"' not in arm
    for line in ['_group setBehaviourStrong "COMBAT";', '_group setCombatMode "YELLOW";', "_group enableAttack false;",
                 '_x enableAI "AUTOTARGET";', "_x limitSpeed 1e10;", "_x forceSpeed -1;", "_x flyInHeight _height;"]:
        assert line in arm, line


def test_it_loads_after_the_rack_and_the_supports():
    init = read(MISSION / "init.sqf")
    at = init.index('call compile preprocessFileLineNumbers "ITW_CLASH_HeliAttack.sqf";')
    gate = init[init.rindex("if (", 0, at):at]
    assert '"ITW_CLASH_RackProfileReady",false' in gate
    assert init.index('preprocessFileLineNumbers "ITW_CLASH_Supports.sqf"') < at
    assert init.index('call compile preprocessFileLineNumbers "ITW_CLASH_RackProfile.sqf";') < at
    preflight = read(MISSION / "ITW_CLASH_DebugPreflight.sqf")
    assert '["ITW_CLASH_HeliAttack","heli attack"' in preflight


def test_boot_line_says_what_it_does():
    raw = read(MISSION / "ITW_CLASH_HeliAttack.sqf")
    assert "ITW_CLASH_HeliAttackVersion = 2;" in raw
    assert "CLASH BOOT | heli-attack-ready |" in raw
    assert "yieldsToOwners=true" in raw
    assert "modes=ORBIT,RUN combatMode=YELLOW attack=false noSAD=true" in raw


# ------------------------------------------------------------- v2: attack runs


def test_no_search_and_destroy_anywhere_in_the_sortie():
    source = heli()
    assert '"SAD"' not in source
    assert '"STATION"' not in source
    assert "StationDwell" not in source


def test_a_run_is_two_move_waypoints_through_the_break():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    leg = fly[fly.index('if (_mode isEqualTo "RUN") then {\n            private _breakPoint'):]
    assert "private _breakPoint = _centre getPos [_break,_bearing];" in leg
    assert "private _nextBearing = _bearing + (_direction * ITW_CLASH_HeliAttackRunOffset);" in leg
    assert "private _ingressPoint = _centre getPos [_ingress,_nextBearing];" in leg
    assert "_points = [_breakPoint,_ingressPoint];" in leg
    order = leg[leg.index("isNil {"):]
    for line in ['_wp setWaypointType "MOVE";', '_wp setWaypointBehaviour "COMBAT";',
                 '_wp setWaypointCombatMode "YELLOW";',
                 "_wp setWaypointCompletionRadius (if (_forEachIndex == 0) then {200} else {ITW_CLASH_HeliAttackRunArrival});",
                 "if (_forEachIndex == 0) then {_group setCurrentWaypoint _wp};"]:
        assert line in order, line


def test_every_run_starts_from_the_side_it_is_on():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    assert 'if (_pass == 0 || {_mode isEqualTo "RUN"}) then {_bearing = _centre getDir (vehicle leader _group)};' in fly


def test_the_pass_as_flown_is_measured():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    wait = fly[fly.index("waitUntil {"):]
    assert "private _range = _veh distance2D _centre;" in wait
    assert "_closestSpeed = speed _veh;" in wait
    flown = fly[fly.index('["flown",['):]
    assert "round _closest,round _closestSpeed,round _closestHeight," in flown
    assert "[_flight] call ITW_CLASH_HeliAttack_fnc_TakeShots" in flown


def test_the_hold_says_what_hal_sent_it_at():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    assert "private _halType = [_target] call ITW_CLASH_HeliAttack_fnc_TypeOf;" in fly
    start = fly[fly.index('[if (_pass == 0) then {"start"} else {"pass"},['):]
    assert "_id,typeOf (_flight#0),_pass,_source,_type,_halType," in start


def test_attack_is_put_back_only_when_the_sortie_ends_on_its_own_terms():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    assert "private _attackWas = attackEnabled _group;" in fly
    cleanup = fly[fly.index("removeEventHandler"):]
    foreign = cleanup[cleanup.index("if (_reason in ITW_CLASH_HeliAttackForeignStops) then {"):]
    foreign_branch, own_branch = foreign.split("} else {", 1)
    assert "enableAttack" not in foreign_branch
    assert "_group enableAttack _attackWas;" in own_branch.split("private _alive", 1)[0]


def test_a_crippled_aircraft_ends_the_sortie():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Stop")
    assert "{!canMove _x}" in body


def closest_on_way_out(brk, ingress, offset_deg):
    """Closest distance to the centre on the leg from the break point to the
    next ingress point."""
    import math
    p0 = (0.0, float(brk))
    p1 = (ingress * math.sin(math.radians(offset_deg)), ingress * math.cos(math.radians(offset_deg)))
    d = (p1[0] - p0[0], p1[1] - p0[1])
    t = max(0.0, min(1.0, -(p0[0] * d[0] + p0[1] * d[1]) / (d[0] ** 2 + d[1] ** 2)))
    x, y = p0[0] + t * d[0], p0[1] + t * d[1]
    return (x * x + y * y) ** 0.5


def test_the_way_out_never_cuts_back_inside_the_break():
    raw = read(MISSION / "ITW_CLASH_HeliAttack.sqf")
    assert 'ITW_CLASH_HeliAttackRunOffset",60]' in raw
    # The DAP's run, and the shortest ingress the rack can give a 600 m break.
    for brk, ingress in [(600, 2900), (600, 1400), (417, 2900)]:
        assert closest_on_way_out(brk, ingress, 60) >= brk - 0.5, (brk, ingress)
    # Past cos(offset) = break / ingress it does cut back in.
    assert closest_on_way_out(600, 2900, 85) < 600
