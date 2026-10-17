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
        "_wp = [];",
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
    # v4: _wp too. HAL's own path makes it in the else block and deletes it
    # after the block (2026-10-17 RPT, GoAttAir line 317).
    for name in ["_lasT = ObjNull;", "_cause = [];", "_timer = 0;", "_alive = true;", "_wp = [];"]:
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
    # v3 points (doWatch, doTarget) but the crew still pulls the trigger
    # (Hark, 2026-10-16: "let the crew pull the trigger").
    source = heli()
    for verb in ["fireAtTarget", "doFire", "commandFire", "forceWeaponFire", "setAmmo", "setWeaponReloadingTime",
                 "setVehicleAmmo", "allUnits", "nearEntities", "nearestObjects", "getPosATL _target",
                 "getPos _tgt", "getPosATL _tgt", "getPosASL _tgt", "position _tgt", "getPosATL _primary"]:
        assert verb not in source, verb
    # Where a target is comes only from the crew's own knowledge.
    perceived = function_body(source, "ITW_CLASH_HeliAttack_fnc_Perceived")
    assert "private _intel = _lead targetKnowledge _object;" in perceived
    detect = function_body(source, "ITW_CLASH_HeliAttack_fnc_Detect")
    assert "(_group targets [true,ITW_CLASH_HeliAttackRetargetRadius,[],0,_centre])" in detect
    assert "call ITW_CLASH_HeliAttack_fnc_Perceived" in detect
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


def test_each_order_is_checked_and_given_in_one_step():
    for name in ["ITW_CLASH_HeliAttack_fnc_FlyOrbit", "ITW_CLASH_HeliAttack_fnc_MoveTo"]:
        body = function_body(heli(), name)
        block = body[body.index("isNil {"):]
        block = block[:block.index("if (_reason isNotEqualTo \"\") exitWith {")]
        assert "_reason = [_group,_flight,_started] call ITW_CLASH_HeliAttack_fnc_Stop;" in block, name
        assert block.index("fnc_Stop") < block.index("doMove"), name
    # No waypoints of its own any more: nothing to leave on a group.
    assert "addWaypoint" not in heli()


def test_a_taken_group_keeps_its_new_owners_orders():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    cleanup = fly[fly.index('_x params ["_veh","_fired","_threats"];'):]
    assert "isNil {" in cleanup
    foreign = cleanup[cleanup.index("if (_reason in ITW_CLASH_HeliAttackForeignStops) then {"):]
    foreign_branch, own_branch = foreign.split("} else {", 1)
    assert "ITW_CLASH_HeliAttack_fnc_ClearWaypoints" not in foreign_branch
    assert "if (!isNull _lead) then {_lead doFollow _lead};" in foreign_branch
    assert "[_group] call ITW_CLASH_HeliAttack_fnc_ClearWaypoints;" in own_branch.split("private _alive", 1)[0]
    # Ours on both paths: watch, target, speed cap and the yaw assist go.
    assert "[_flight] call ITW_CLASH_HeliAttack_fnc_Unwatch;" in cleanup
    assert "[_veh] call ITW_CLASH_HeliAttack_fnc_YawRelease;" in cleanup
    assert "_veh limitSpeed 1e10;" in cleanup
    for handler in ['"Fired"', '"Hit"', '"IncomingMissile"']:
        assert f"_veh removeEventHandler [{handler}," in cleanup, handler
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
    orbit = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FlyOrbit")
    point = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FlyPoint")
    for body in [orbit, point]:
        assert '_reason = "winchester"' in body
        assert '_reason = if (_hadTarget) then {"clear"} else {"nothing-to-hit"};' in body
    assert '_source = "hal-point-hold";' in orbit
    assert "if (_emptyPasses >= ITW_CLASH_HeliAttackClearLaps) exitWith {" in orbit
    # Two looks with nothing found, then home.
    assert "if (_looks > ITW_CLASH_HeliAttackClearLaps) exitWith {" in point


def test_weapons_free_each_pass_and_lift_limits_cleared():
    # v2: fire at will (YELLOW) with attack off, so the crew shoots from its
    # line instead of leaving it to close in, as RED let it on 2026-10-16.
    arm = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Arm")
    assert '"RED"' not in arm
    for line in ['_group setBehaviourStrong "COMBAT";', '_group setCombatMode "YELLOW";', "_group enableAttack false;",
                 '_x enableAI "AUTOTARGET";', "_x limitSpeed 1e10;", "_x forceSpeed -1;",
                 "[_flight,_height] call ITW_CLASH_HeliAttack_fnc_SetHeight;"]:
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
    assert "ITW_CLASH_HeliAttackVersion = 4;" in raw
    assert "CLASH BOOT | heli-attack-ready |" in raw
    assert "yieldsToOwners=true" in raw
    assert "modes=ORBIT,POINT" in raw
    assert "combatMode=YELLOW attack=false noSAD=true crewFires=true" in raw


# ------------------------------------------------------------- shared by both


def test_no_search_and_destroy_anywhere_in_the_sortie():
    source = heli()
    assert '"SAD"' not in source
    assert '"STATION"' not in source
    assert '"RUN"' not in source


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
    assert "case (!canMove _x): {\"disabled\"};" in body


def test_a_gunner_anywhere_means_the_ring_and_only_the_airframe_means_point():
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    assert ('private _mode = if (((values _types) findIf {((_x#0) > 0) && {(_x#2) isEqualTo "ORBIT"}}) >= 0) '
            'then {"ORBIT"} else {"POINT"};') in fly
    assert "[_ctx] call ITW_CLASH_HeliAttack_fnc_FlyOrbit" in fly
    assert "[_ctx] call ITW_CLASH_HeliAttack_fnc_FlyPoint" in fly


def test_the_ring_is_measured_each_lap():
    orbit = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FlyOrbit")
    wait = orbit[orbit.index("waitUntil {"):]
    assert "private _range = _veh distance2D _centre;" in wait
    flown = orbit[orbit.index('["flown",['):]
    assert "round _closest,round _closestSpeed,round _closestHeight," in flown
    assert "[_flight] call ITW_CLASH_HeliAttack_fnc_TakeShots" in flown


def test_flares_are_not_shots():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_WatchShots")
    assert body.index("ITW_CLASH_Rack_fnc_IsCountermeasure") < body.index("ITW_CLASH_HeliAttackShotTotal")


# ------------------------------------------------------------- v3: point at


def test_detect_is_crew_knowledge_ranked_hal_first_then_armour_down():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Detect")
    assert 'private _rank = if (_veh isEqualTo _halVeh) then {-1} else {(["ARMOR","VEHICLE","STATIC","INFANTRY"] find _class) max 0};' in body
    assert "if (((_types getOrDefault [_class,[0]])#0) <= 0) then {continue};" in body
    assert "[_found,[],{((_x#0) + 1) * 1e6 + (_x#1)},\"ASCEND\"] call BIS_fnc_sortBy;" in body


def test_a_revealed_unseen_target_can_be_pointed_at_but_a_stale_sighting_cannot():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Perceived")
    assert ("if (_maxAge > 0 && {_lastSeen isEqualType 0} && {_lastSeen >= 0} && "
            "{(time - _lastSeen) > _maxAge}) exitWith {[]};") in body
    raw = read(MISSION / "ITW_CLASH_HeliAttack.sqf")
    assert 'ITW_CLASH_HeliAttackPointKnownAge",120]' in raw


def test_a_firing_position_sees_the_target_and_keeps_clear_of_others():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FiringPosition")
    assert "private _los = !(terrainIntersectASL [_from,_eye]);" in body
    assert "private _near = {(_x distance2D _pos) < ITW_CLASH_HeliAttackPointClearRadius} count _others;" in body
    assert "private _score = (if (_los) then {0} else {1000}) + (_near * 100) + (abs _offset);" in body
    assert "} forEach [0,30,-30,60,-60];" in body


def test_get_far_then_point_three_times_then_hop_to_the_side():
    point = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FlyPoint")
    engage = point[point.index("(_found#0) params"):]
    order = [
        engage.index("call ITW_CLASH_HeliAttack_fnc_FiringPosition"),
        engage.index("call ITW_CLASH_HeliAttack_fnc_MoveTo"),
        engage.index('for "_i" from 1 to ITW_CLASH_HeliAttackPointAims do {'),
        engage.index("call ITW_CLASH_HeliAttack_fnc_Aim"),
        engage.index('["engage",['),
    ]
    assert order == sorted(order)
    # From the side it is on; after the first, a hop to alternating sides.
    assert "private _base = _primaryPos getDir _heli;" in engage
    assert ("if (_moved) then {_base = _base + (_zig * ([_standoff] call ITW_CLASH_HeliAttack_fnc_HopStep)); "
            "_zig = -_zig};") in engage
    # Aims go to targets not yet pointed at first.
    assert "private _next = _now findIf {!((_x#0) in _aimed)};" in engage
    raw = read(MISSION / "ITW_CLASH_HeliAttack.sqf")
    assert 'ITW_CLASH_HeliAttackPointAims",3]' in raw


def test_every_leg_is_low_and_it_climbs_only_once_there():
    # v4: 5 of 7 point-at sorties died in transit at 149 to 258 m.
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_MoveTo")
    assert 'params ["_ctx","_point",["_height",-1]];' in body
    transit = body.index("[_flight,ITW_CLASH_HeliAttackTransitHeight] call ITW_CLASH_HeliAttack_fnc_SetHeight;")
    wait = body.index("waitUntil {")
    popup = body.index("[_flight,_height] call ITW_CLASH_HeliAttack_fnc_SetHeight;")
    assert transit < wait < popup
    assert "(_height * ITW_CLASH_HeliAttackPopUpFraction)" in body
    # The troop lifts' arrival schedule, so it does not balloon on arrival.
    assert 'private _schedule = !isNil "ITW_CLASH_HALStayLow_fnc_Schedule";' in body
    assert "call ITW_CLASH_HALStayLow_fnc_Schedule)#0) min _limit;" in body
    point = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FlyPoint")
    assert point.count("call ITW_CLASH_HeliAttack_fnc_MoveTo;") == 2
    assert point.count("[_ctx,_pos,_height] call ITW_CLASH_HeliAttack_fnc_MoveTo;") == 2
    orbit = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FlyOrbit")
    assert "private _onto = ((vehicle _lead) distance2D _point) > ((_radius * 2) max 800);" in orbit
    raw = read(MISSION / "ITW_CLASH_HeliAttack.sqf")
    assert 'ITW_CLASH_HeliAttackTransitHeight",30]' in raw


def test_heights_are_forced_and_released_for_the_landing():
    helper = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_SetHeight")
    assert "_x flyInHeight [_height,_forced];" in helper
    assert "_x flyInHeight _height;" in helper
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    cleanup = fly[fly.index('_x params ["_veh","_fired","_threats"];'):]
    # A forced height keeps a helicopter from landing: always released.
    release = cleanup.index("[_flight,ITW_CLASH_HeliAttackReleaseHeight,false] call ITW_CLASH_HeliAttack_fnc_SetHeight;")
    assert release < cleanup.index("if (_reason in ITW_CLASH_HeliAttackForeignStops) then {")


def test_the_end_line_says_which_sortie_limit():
    stop = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Stop")
    assert '_group setVariable ["ITW_CLASH_HeliAttackRtbWhy",_rtb]; "rtb-condition"' in stop
    for why in ('"dead"', '"disabled"', '"damage-%1"', '"fuel-%1"'):
        assert why in stop, why
    fly = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Fly")
    assert '_group getVariable ["ITW_CLASH_HeliAttackRtbWhy",""]' in fly


def test_a_hop_is_short_and_slow_a_transit_is_not():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_MoveTo")
    assert ("private _limit = if (_distance <= ITW_CLASH_HeliAttackPointHopFar) then "
            "{ITW_CLASH_HeliAttackPointHopSpeed} else {1e10};") in body
    assert "[_flight] call ITW_CLASH_HeliAttack_fnc_Unwatch;" in body
    raw = read(MISSION / "ITW_CLASH_HeliAttack.sqf")
    for name, value in [("PointHop", 700), ("PointHopMaxStep", 40), ("PointHopFar", 1500), ("PointHopSpeed", 120)]:
        assert f'ITW_CLASH_HeliAttack{name}",{value}]' in raw, name


def hop_step(standoff, hop=700, cap=40):
    """Python mirror of ITW_CLASH_HeliAttack_fnc_HopStep, degrees."""
    import math
    return min(2 * math.degrees(math.asin(min(hop / (2 * max(standoff, 1)), 1))), cap)


def chord(standoff, step):
    import math
    return 2 * standoff * math.sin(math.radians(step / 2))


def test_the_hop_is_about_700_m_at_any_standoff_and_never_crosses_the_target():
    import math
    # 2 km (guided): a 20 degree step, a 700 m hop. 1 km (unguided): the cap,
    # 40 degrees, a 684 m hop.
    assert abs(hop_step(2000) - 20.2) < 0.1 and abs(chord(2000, hop_step(2000)) - 700) < 1
    assert hop_step(1000) == 40 and abs(chord(1000, 40) - 684) < 1
    for standoff in [2000, 1000]:
        step = hop_step(standoff)
        # Closest the hop's straight line comes to the target: well outside.
        assert standoff * math.cos(math.radians(step / 2)) > 0.9 * standoff
    # Close in, the cap keeps the turn round the target small.
    assert hop_step(417) == 40
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_HopStep")
    assert "(2 * (asin ((ITW_CLASH_HeliAttackPointHop / (2 * (_standoff max 1))) min 1))) min ITW_CLASH_HeliAttackPointHopMaxStep" in body


def test_a_point_at_turns_the_nose_and_never_the_trigger():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Aim")
    assert "if (!isNull _x && {alive _x}) then {_x doWatch _tgt; _x doTarget _tgt};" in body
    # Native first; the assist only after AssistAfter with the nose not on.
    assert ("if (!_assisted && {_onAt < 0} && {(time - _start) >= ITW_CLASH_HeliAttackPointAssistAfter}) then {") in body
    assert "{[_x,_pos] call ITW_CLASH_HeliAttack_fnc_YawHold} forEach _flight;" in body
    assert "{[_x] call ITW_CLASH_HeliAttack_fnc_YawRelease} forEach _flight;" in body
    # Done on hold, two seconds after the crew's shot, or never on in time.
    assert "(_onAt >= 0 && {(time - _onAt) >= ITW_CLASH_HeliAttackPointHold})" in body
    assert "|| {_shotAt >= 0 && {(time - _shotAt) >= 2}}" in body
    assert "|| {_onAt < 0 && {(time - _start) >= ITW_CLASH_HeliAttackPointAlignTimeout}}" in body
    for why in ['_why = "dead"', '_why = "lost"', '_why = "threat"']:
        assert why in body, why


def test_a_hit_or_a_missile_breaks_off():
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_WatchThreats")
    assert '_veh addEventHandler ["Hit",' in body
    assert '_veh addEventHandler ["IncomingMissile",' in body
    point = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FlyPoint")
    assert 'if (_why isEqualTo "threat") exitWith {_leave = "threat"};' in point


def test_the_yaw_assist_is_heading_only_capped_local_and_lapses():
    source = heli()
    frame = function_body(source, "ITW_CLASH_HeliAttack_fnc_YawFrame")
    assert "!isNull (_x#0) && {alive (_x#0)} && {local (_x#0)} && {time <= (_x#2)}" in frame
    assert "if ((speed _veh) > ITW_CLASH_HeliAttackYawMaxSpeed || {((getPosATL _veh)#2) < 5}) then {continue};" in frame
    assert ("private _rate = (((rad _err) * ITW_CLASH_HeliAttackYawGain) max (-ITW_CLASH_HeliAttackYawRate)) "
            "min ITW_CLASH_HeliAttackYawRate;") in frame
    # Pitch and roll rates are the flight model's; only yaw is set.
    assert "_veh setAngularVelocityModelSpace [_w#0,_w#1,_rate * _sign];" in frame
    assert "private _sign = [_veh] call ITW_CLASH_HeliAttack_fnc_YawSignOf;" in frame
    hold = function_body(source, "ITW_CLASH_HeliAttack_fnc_YawHold")
    assert "private _entry = [_veh,+_pos,time + 1.5];" in hold
    assert 'addMissionEventHandler ["EachFrame",{call ITW_CLASH_HeliAttack_fnc_YawFrame}];' in source
    raw = read(MISSION / "ITW_CLASH_HeliAttack.sqf")
    # v4: measured in game 2026-10-17, positive turns the nose clockwise.
    assert 'ITW_CLASH_HeliAttackYawSign",1]' in raw


def test_a_turn_that_does_not_close_the_error_flips_that_airframes_sign():
    # v4: v3 flipped only when the error grew, which an aircraft already
    # parked tail on (the wrong sign's resting point) can never show.
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_Aim")
    assert "&& {_err > (_assistErr - ITW_CLASH_HeliAttackYawMinProgress)}" in body
    # Only while the assist is really turning it, and never once locked.
    assert '(time - (_lead getVariable ["ITW_CLASH_HeliAttackYawAppliedAt",-1e10])) < 1' in body
    assert "if (!_turning) exitWith {_checkSignAt = time + 1};" in body
    assert "!_locked" in body and "{_flips < ITW_CLASH_HeliAttackYawMaxFlips}" in body
    assert "ITW_CLASH_HeliAttackYawSigns set [typeOf _lead,[-_sign,false,_flips + 1]];" in body
    assert '["yaw-sign-flipped",[' in body
    # An assisted point-at that comes on locks the class's sign.
    assert "ITW_CLASH_HeliAttackYawSigns set [typeOf _lead,[_sign,true,_flips]];" in body
    assert '["yaw-sign-confirmed",[' in body
    frame = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_YawFrame")
    assert '_veh setVariable ["ITW_CLASH_HeliAttackYawAppliedAt",time];' in frame
    state = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_YawState")
    assert "getOrDefault [typeOf _veh,[ITW_CLASH_HeliAttackYawSign,false,0]]" in state


def yaw_rate(err_deg, gain=2.0, cap=0.8, sign=1):
    """Python mirror of the assist's commanded yaw rate (rad/s, model z)."""
    import math
    return max(-cap, min(cap, math.radians(err_deg) * gain)) * sign


def test_yaw_rate_model():
    # A target to the right needs a clockwise turn from above, which in Arma
    # is positive about the model's up axis (v4, measured 2026-10-17).
    assert yaw_rate(20) > 0
    assert yaw_rate(-20) < 0
    assert yaw_rate(90) == 0.8
    assert abs(yaw_rate(5) - 0.1745) < 0.001


def rest(start_err, sign, steps=400, dt=0.05):
    """The assist's loop on a bare yaw: where the heading error settles.

    The rate turns the heading (positive clockwise); the error is the
    target's bearing less the heading, so it moves the other way.
    """
    err = start_err
    for _ in range(steps):
        err -= yaw_rate(err, sign=sign) * 57.2958 * dt
        err = ((err + 540) % 360) - 180
    return err


def test_a_wrong_sign_parks_the_tail_on_the_target():
    # Hark's 2026-10-17 report, as the loop's arithmetic: from either side,
    # the inverted assist comes to rest tail on; the right one nose on.
    for start in (20, 97, -97, 170, -170):
        assert abs(abs(rest(start, -1)) - 180) < 2, start
        assert abs(rest(start, 1)) < 2, start


def heading_error(heli_dir, bearing):
    return ((bearing - heli_dir) + 540) % 360 - 180


def test_heading_error_wraps():
    assert heading_error(350, 10) == 20
    assert heading_error(10, 350) == -20
    assert heading_error(0, 180) == 180 - 360 or heading_error(0, 180) == 180
    body = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_HeadingError")
    assert "((((_veh getDir _pos) - (getDir _veh)) + 540) mod 360) - 180" in body


def test_each_firing_position_and_look_is_logged():
    point = function_body(heli(), "ITW_CLASH_HeliAttack_fnc_FlyPoint")
    engage = point[point.index('["engage",['):]
    assert "_id,_positions,_class,_source,round _standoff,_arrived,round _bearing,_los,_near," in engage
    assert "_aims,_leave,round (time - _positionStart)," in engage
    assert '["look",[' in point
    assert '["start",[' in point and "_halType" in point
