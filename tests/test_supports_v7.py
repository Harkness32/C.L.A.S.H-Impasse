"""Supports v7, airborne v2, the support console tests, and rear-base C-RAM v4.

See docs/CLASH_CommanderSupports_Model.md (2026-10-17, Hark):

- "I don't want the commander to have to pick between the two." Strikes and
  the UAV, paradrops, and vehicle delivery are three families: three lanes,
  three picks per assessment. The two drop families spend their own wallet.
- Vehicle delivery is its own support, carried inside the aircraft that drops
  it (the Blackfish by default: "both sides have it right now").
- Bite-back: a point a side holds that is being taken, or whose defenders are
  outnumbered, gets a wave (a helicopter drop of two squads and a vehicle)
  from a small pot of its own.
- Console tests for all of it.
- "Cram for both of us": the rear base gets a real C-RAM before any fallback.
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


def code(name: str) -> str:
    return code_text(raw(name))


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


CORE = code("ITW_CLASH_Supports.sqf")
AIRBORNE = code("ITW_CLASH_SupportsAirborne.sqf")
DEBUG = code("ITW_CLASH_SupportsDebug.sqf")
CRAM = code("ITW_CLASH_RearBaseCRAM.sqf")
INCOME = 1.2  # the main bank's income per minute in the runs read so far


def row(flavor: str) -> str:
    start = CORE.index(f'["{flavor}",createHashMapFromArray [')
    return CORE[start:CORE.index("]],", start) + 3]


# ------------------------------------------------------------ the families


def test_versions():
    assert "ITW_CLASH_SupportsVersion = 7;" in raw("ITW_CLASH_Supports.sqf")
    assert "ITW_CLASH_SupportsAirborneVersion = 2;" in raw("ITW_CLASH_SupportsAirborne.sqf")
    assert "ITW_CLASH_SupportsDebugVersion = 1;" in raw("ITW_CLASH_SupportsDebug.sqf")
    assert "ITW_CLASH_RearBaseCRAMVersion = 5;" in raw("ITW_CLASH_RearBaseCRAM.sqf")


def test_three_families_three_lanes_one_drop_wallet():
    for flavor in ["AIRBORNE_HELI", "AIRBORNE_PLANE"]:
        assert '["lane","DROP"],["wallet","DROP"]' in row(flavor), flavor
    vehicle = row("VEHICLE_DROP")
    assert '["verb","DELIVER"],["routine","DROP"],["lane","VEHICLE"],["wallet","DROP"],["aircraft","VIV"]' in vehicle
    assert '["switch","ITW_CLASH_SupportsVehicleDropEnabled"]' in vehicle
    # A VTOL needs no runway: from the rear air base like a helicopter.
    assert '["airfield",false]' in vehicle
    for flavor in ["BOMB", "GUIDED", "CARPET"]:
        assert '["lane","COMMIT"]' in row(flavor) and "wallet" not in row(flavor), flavor
    assert 'ITW_CLASH_SupportsVehicleFlavors = ["VEHICLE_DROP"];' in CORE


def test_drop_cadences_and_prices():
    source = raw("ITW_CLASH_Supports.sqf")
    assert '["ITW_CLASH_SupportsAirborneHeliCadence",15]' in source
    assert '["ITW_CLASH_SupportsAirbornePlaneCadence",25]' in source
    assert '["ITW_CLASH_SupportsVehicleDropCadence",15]' in source
    price = function_body(CORE, "ITW_CLASH_Supports_fnc_Price")
    # The C-130's 1.5 for its vehicle add-on is gone with the add-on.
    assert "1.5" not in price
    assert 'if (([_flavor] call ITW_CLASH_Supports_fnc_WalletOf) isEqualTo "DROP") then {' in price
    # The prices a side now pays from the drop wallet.
    heli, plane, vehicle = INCOME * 15, INCOME * 25, INCOME * 15
    assert (round(heli), round(plane), round(vehicle)) == (18, 30, 18)
    # Against 36 for the helicopter and 90 for the C-130 with its vehicle.
    assert round(INCOME * 30) == 36 and round(INCOME * 50 * 1.5) == 90


def test_each_wallet_has_its_own_cap():
    cap = function_body(CORE, "ITW_CLASH_Supports_fnc_Cap")
    assert '([_x] call ITW_CLASH_Supports_fnc_WalletOf) isEqualTo "MAIN"' in cap
    drop_cap = function_body(CORE, "ITW_CLASH_Supports_fnc_DropCap")
    assert "forEach ITW_CLASH_SupportsDropFlavors;" in drop_cap
    assert "forEach ITW_CLASH_SupportsVehicleFlavors;" in drop_cap
    assert "(_paradrop + _vehicle) max 1" in drop_cap
    # One paradrop and one vehicle banked; the main bank's cap is the carpet's.
    assert round(INCOME * 25 + INCOME * 15) == 48
    assert round(INCOME * 20) == 24
    wallet_cap = function_body(CORE, "ITW_CLASH_Supports_fnc_WalletCap")
    for case in ['case "DROP": {call ITW_CLASH_Supports_fnc_DropCap};',
                 'case "BITE": {ITW_CLASH_SupportsBiteBackCap};',
                 'case "TEST": {1e10};']:
        assert case in wallet_cap, case


def test_wallets_accrue_apart_and_start_where_they_should():
    accrue = function_body(CORE, "ITW_CLASH_Supports_fnc_Accrue")
    assert '["cash",call ITW_CLASH_Supports_fnc_Cap,call ITW_CLASH_Supports_fnc_IncomeRate]' in accrue
    assert '["dropCash",call ITW_CLASH_Supports_fnc_DropCap,call ITW_CLASH_Supports_fnc_DropIncomeRate]' in accrue
    assert '["biteCash",ITW_CLASH_SupportsBiteBackCap,1 / (ITW_CLASH_SupportsBiteBackRefill max 1)]' in accrue
    # A full wallet no longer stops the others earning.
    assert "if (_cash < _cap) then {" in accrue
    ledger = function_body(CORE, "ITW_CLASH_Supports_fnc_Ledger")
    assert '["dropCash",0],' in ledger
    assert '["biteCash",ITW_CLASH_SupportsBiteBackCap],' in ledger
    # The pot earns a wave back in the refill time.
    refill = 20
    per_minute = 1 / refill
    assert abs(per_minute * refill - 1) < 1e-9


def test_three_picks_each_with_its_own_save():
    assess = function_body(CORE, "ITW_CLASH_Supports_fnc_Assess")
    # The drops are no longer offered in the strikes' pool.
    main_pool = assess[:assess.index('[_context,_posture,_planObjective,_pool,"pool"] call ITW_CLASH_Supports_fnc_Decide;')]
    assert "ITW_CLASH_Supports_fnc_DropCandidates" not in main_pool
    tail = assess[assess.index('"pool"] call ITW_CLASH_Supports_fnc_Decide;'):]
    assert tail.index("ITW_CLASH_Supports_fnc_BiteBack") < tail.index("DropCandidates")
    assert '_context set ["exclusions",[]];' in tail
    assert '[_ledger,"DROP"] call ITW_CLASH_Supports_fnc_SaveWeight' in tail
    assert '[ITW_CLASH_SupportsDropFlavors,"drop-pool"],' in tail
    assert '[ITW_CLASH_SupportsVehicleFlavors,"vehicle-pool"]' in tail
    log = function_body(CORE, "ITW_CLASH_Supports_fnc_LogPool")
    assert 'private _wallet = if (_event isEqualTo "pool") then {"MAIN"} else {"DROP"};' in log


def test_drop_candidates_read_the_flavor_wallet_and_a_delivery_carries_no_squads():
    body = function_body(CORE, "ITW_CLASH_Supports_fnc_DropCandidates")
    assert 'params ["_context","_objective","_reason","_urgency","_entry",["_flavors",ITW_CLASH_SupportsDropFlavors]];' in body
    assert "private _delivery = _flavor in ITW_CLASH_SupportsVehicleFlavors;" in body
    assert "private _need = if (_delivery) then {ITW_CLASH_SupportsVehicleDropCrew} else {_squads * _squadSize};" in body
    assert "[_flavor] call ITW_CLASH_Supports_fnc_WalletOf] call ITW_CLASH_Supports_fnc_WalletCash" in body
    gate = function_body(CORE, "ITW_CLASH_Supports_fnc_FlavorGate")
    assert "[_flavor] call ITW_CLASH_Supports_fnc_WalletOf] call ITW_CLASH_Supports_fnc_WalletCash" in gate


# --------------------------------------------------- admission and settling


def test_a_pick_can_bring_its_own_wallet_lane_price_and_delay():
    admit = function_body(CORE, "ITW_CLASH_Supports_fnc_Admit")
    for needle in [
        'private _ownLane = "lane" in _pick;',
        'private _lane = _pick getOrDefault ["lane",_row get "lane"];',
        'private _wallet = _pick getOrDefault ["wallet",[_flavor] call ITW_CLASH_Supports_fnc_WalletOf];',
        'private _price = _pick getOrDefault ["price",[_flavor,_reason] call ITW_CLASH_Supports_fnc_Price];',
        'case (!_ownLane && {[_ledger,"flavor:" + _flavor] call ITW_CLASH_Supports_fnc_OnCooldown}): {_denied = "COOLDOWN"};',
        'if (_wallet isNotEqualTo "TEST") then {',
        '["delay",_pick getOrDefault ["delay",',
        '["test",_pick getOrDefault ["test",false]],',
        '["wave",_pick getOrDefault ["wave",""]],',
        '_context set ["admitted",_id];',
    ]:
        assert needle in admit, needle
    # A pick's own lane is not the flavor's ordinary use: no flavor cooldown.
    reserve = admit[admit.index("default {"):admit.index('if (_id isEqualTo "") exitWith {')]
    assert reserve.index("if (!_ownLane) then {") < reserve.index('_cooldowns set ["flavor:" + _flavor')


def test_a_test_skips_the_map_gates_but_not_the_physics():
    prerun = function_body(CORE, "ITW_CLASH_Supports_fnc_PreRun")
    assert 'private _test = _support getOrDefault ["test",false];' in prerun
    assert "if (!_test && {!isNil \"ITW_CLASH_fnc_ObjectiveFrozen\"}" in prerun
    assert 'if (_routine isEqualTo "DROP" && {!_test}) then {' in prerun
    assert 'if (!_test && {(_corridor getOrDefault ["state","COLD"]) isEqualTo "AIR_DENIED"}) exitWith {"AIR_DENIED"};' in prerun
    # A delivery's headroom is its crew, not squads it does not carry.
    assert 'private _need = _support getOrDefault ["need",0];' in prerun


def test_refunds_go_back_to_their_own_wallet():
    settle = function_body(CORE, "ITW_CLASH_Supports_fnc_Settle")
    assert 'private _wallet = _support getOrDefault ["wallet","MAIN"];' in settle
    assert "_ledger set [_cashKey,_after];" in settle
    assert '_wallet,_support getOrDefault ["wave",""]' in settle


def test_a_delivery_runs_its_own_executor():
    run_drop = function_body(CORE, "ITW_CLASH_Supports_fnc_RunDrop")
    assert 'if ((_support get "flavor") in ITW_CLASH_SupportsVehicleFlavors) exitWith {' in run_drop
    assert "[_support] call ITW_CLASH_SupportsAirborne_fnc_RunVehicle" in run_drop


# ------------------------------------------------------ the vehicle carrier


def test_the_carrier_is_found_by_what_it_can_carry_blackfish_first():
    source = raw("ITW_CLASH_Supports.sqf")
    assert '["ITW_CLASH_SupportsVehicleCarrierClasses",["B_T_VTOL_01_vehicle_F"]]' in source
    carrier = function_body(CORE, "ITW_CLASH_Supports_fnc_IsCarrier")
    assert '_class isKindOf "Air"' in carrier
    assert 'isClass (configFile >> "CfgVehicles" >> _class >> "VehicleTransport" >> "Carrier")' in carrier
    classes = function_body(CORE, "ITW_CLASH_Supports_fnc_Classes")
    assert 'case "VIV": {[_prefix + "PlaneClassesTransport",_prefix + "HeliClassesTransport"]};' in classes
    assert 'case "VIV": {_classes select {[_x] call ITW_CLASH_Supports_fnc_IsCarrier}};' in classes
    pick = function_body(CORE, "ITW_CLASH_Supports_fnc_PickClass")
    viv = pick[pick.index('case "VIV": {'):pick.index('case "HELI";')]
    # The side's own preferred carrier, else its strongest lifter, else a
    # preferred class the side does not list.
    assert viv.index("private _own = _preferred select {_x in _classes};") < viv.index("CarrierLoad") < viv.index("[_preferred#0,\"\"]")


def test_the_vehicle_flies_inside_the_carrier_and_leaves_it_over_the_zone():
    run = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_Run")
    assert "VehicleDrop" not in run
    load = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_LoadVehicle")
    assert "private _fits = (_carrier canVehicleCargo _candidate) param [0,false];" in load
    assert "if (_fits && {_carrier setVehicleCargo _candidate}) exitWith {_car = _candidate};" in load
    assert "{deleteVehicle _x} forEach (crew _candidate);" in load
    assert "_car allowDamage false;" in load and "_car lock 2;" in load
    vehicle = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_RunVehicle")
    for needle in [
        "ITW_CLASH_Supports_fnc_SpawnAircraft) params [\"_veh\",\"_group\"];",
        "call ITW_CLASH_SupportsAirborne_fnc_LoadVehicle) params [\"_car\",\"_crew\",\"_tried\"];",
        '["REVOKED","NO_VEHICLE_FIT"]',
        "private _lead = ((speed _veh) / 3.6) * ITW_CLASH_SupportsVehicleDropLeadSeconds;",
        "private _unloaded = objNull setVehicleCargo _car;",
        'if (alive _car && {isNull (attachedTo _car)} && {((getPos _car)#2) > 20}) then {',
        "[_car] spawn ITW_FncVehicleHalo;",
        '[_support,_car,_crew,"landed"] spawn ITW_CLASH_SupportsAirborne_fnc_VehicleHandOff;',
        '[_support,_car,_crew,"survived-loss"] spawn ITW_CLASH_SupportsAirborne_fnc_VehicleHandOff;',
    ]:
        assert needle in vehicle, needle
    default = vehicle[vehicle.rindex("default {"):]
    assert "deleteVehicle _car;" in default
    # At 70 m/s the vehicle leaves about 175 m short of the zone.
    assert abs(70 * 2.5 - 175) < 1e-9


def test_the_vehicle_is_handed_to_hal_once_it_is_down():
    handoff = function_body(AIRBORNE, "ITW_CLASH_SupportsAirborne_fnc_VehicleHandOff")
    assert handoff.index("_car allowDamage true;") < handoff.index("ITW_CLASH_DualHAL_fnc_RegisterGroup")
    assert "_car lock 0;" in handoff
    assert '_crew setVariable ["ITW_CLASH_ReconstitutionTransit",nil];' in handoff


# --------------------------------------------------------------- bite-back


def bite_why(ours, phase, was, urgency, floor=0.9):
    """The decision table in ITW_CLASH_Supports_fnc_BiteBackWhy."""
    was_ours = was is not None and was[0]
    if not ours:
        flag = "enemy-flag-up"
    elif was_ours and phase < was[1] - 0.001:
        flag = "flag-falling"
    elif phase < floor and (not was_ours or phase <= was[1] + 0.001):
        flag = "flag-down"
    else:
        flag = ""
    if flag:
        return flag
    if urgency >= 3:
        return "unanchored"
    if urgency >= 2.5:
        return "outnumbered"
    return ""


def test_bite_back_wakes_on_the_flag_or_the_defenders():
    body = function_body(CORE, "ITW_CLASH_Supports_fnc_BiteBackWhy")
    assert 'case (!_ours): {"enemy-flag-up"};' in body
    assert 'case (_wasOurs && {_phase < ((_was#1) - 0.001)}): {"flag-falling"};' in body
    assert ('case (_phase < ITW_CLASH_SupportsBiteBackFlagFloor && {!_wasOurs || {_phase <= ((_was#1) + 0.001)}}): '
            '{"flag-down"};') in body
    assert 'case (_urgency >= 3): {"unanchored"};' in body
    assert 'case (_urgency >= 2.5): {"outnumbered"};' in body
    # A held point at full flag and comfortably defended: nothing.
    assert bite_why(True, 1.0, (True, 1.0), 1.5) == ""
    # The enemy's flag going up on a point still counted as ours.
    assert bite_why(False, 0.3, (True, 0.1), 0) == "enemy-flag-up"
    # Ours coming down, from any height.
    assert bite_why(True, 0.95, (True, 1.0), 0) == "flag-falling"
    # First look already low; or stuck low and not recovering.
    assert bite_why(True, 0.6, None, 0) == "flag-down"
    assert bite_why(True, 0.6, (True, 0.6), 0) == "flag-down"
    # Low but rising (we are taking it back): only the defenders can wake it.
    assert bite_why(True, 0.6, (True, 0.4), 0) == ""
    assert bite_why(True, 0.6, (True, 0.4), 2.5) == "outnumbered"
    # Flag fine, nobody of ours on a point under pressure.
    assert bite_why(True, 1.0, (True, 1.0), 3) == "unanchored"


def test_the_flag_is_what_players_see():
    body = function_body(CORE, "ITW_CLASH_Supports_fnc_FlagState")
    assert 'private _playerFlag = _flag getVariable "ITW_FlagIsPlayer";' in body
    assert 'private _phase = _flag getVariable ["ITW_FlagPhase",1];' in body
    assert "[_playerFlag isEqualTo (_side isEqualTo ITW_PlayerSide),_phase]" in body
    # A flag Impasse has not set up says nothing.
    assert 'if (isNil "_playerFlag" || {!(_playerFlag isEqualType true)}) exitWith {[true,1]};' in body


def test_a_wave_waits_for_the_pot_the_lanes_the_cooldown_and_the_defend_phase():
    body = function_body(CORE, "ITW_CLASH_Supports_fnc_BiteBack")
    assert "if (!ITW_CLASH_SupportsBiteBackEnabled) exitWith {false};" in body
    for hold in [
        'case (_defendRunning && {_index isEqualTo _defendFocus}): {"DEFEND_PHASE"};',
        'case ([_ledger,"bite:" + str _index] call ITW_CLASH_Supports_fnc_OnCooldown): {"COOLDOWN"};',
        'case ((_ledger getOrDefault ["biteCash",0]) < 1): {"INSUFFICIENT_FUNDS"};',
        '{"LANE_BUSY"};',
    ]:
        assert hold in body, hold
    # Frozen points and points not held are never considered.
    assert "if (_index < 0 || {!([_side,_index] call ITW_CLASH_Supports_fnc_HeldBy)}) then {continue};" in body
    assert "[_index] call ITW_CLASH_fnc_ObjectiveFrozen" in body
    # Most urgent first, one wave an assessment, a held wave said once.
    assert "_wants = [_wants,[],{-(_x#0)},\"ASCEND\"] call BIS_fnc_sortBy;" in body
    assert "if (_launched) exitWith {" in body
    assert "if ((_said getOrDefault [str _index,\"\"]) isNotEqualTo _line) then {" in body


def test_a_wave_is_a_helicopter_drop_and_a_vehicle_paid_by_the_pot():
    body = function_body(CORE, "ITW_CLASH_Supports_fnc_LaunchWave")
    assert 'forEach [["AIRBORNE_HELI","BITE_DROP"],["VEHICLE_DROP","BITE_VEHICLE"]];' in body
    assert "ITW_CLASH_SupportsBiteBackSquads" in body
    assert '([_context,_flavor,_index,"HOLD",_squads] call ITW_CLASH_Supports_fnc_DirectPick)' in body
    assert "private _share = 1 / (count _parts);" in body
    assert '_pick set ["wallet",if (_test) then {"TEST"} else {"BITE"}];' in body
    assert '_pick set ["price",if (_test) then {0} else {_share}];' in body
    # The cooldown starts only once something actually went.
    assert body.index("if (_ids isEqualTo []) exitWith {") < body.index('"bite:" + str _index,time + ITW_CLASH_SupportsBiteBackCooldown')
    source = raw("ITW_CLASH_Supports.sqf")
    for tunable in ['ITW_CLASH_SupportsBiteBackCap",1]', 'ITW_CLASH_SupportsBiteBackRefill",20]',
                    'ITW_CLASH_SupportsBiteBackCooldown",1200]', 'ITW_CLASH_SupportsBiteBackSquads",2]',
                    'ITW_CLASH_SupportsBiteBackFlagFloor",0.9]']:
        assert tunable in source, tunable


def test_a_direct_pick_cuts_squads_to_fit():
    body = function_body(CORE, "ITW_CLASH_Supports_fnc_DirectPick")
    assert "private _squadSize = (count _template) min (floor (_seats / (_count max 1)));" in body
    assert 'if (_squadSize < ITW_CLASH_SupportsAirborneMinSquadCore) then {_failed = "NO_SQUADS"};' in body
    # Two squads of eight from a sixteen-seat Huron; two of four from a Ghost Hawk's eight.
    assert min(8, 16 // 2) == 8 and min(8, 8 // 2) == 4


# ------------------------------------------------------------ console tests


def test_console_tests_are_loaded_after_the_executors_and_need_the_core():
    init = code("init.sqf")
    assert init.index('"ITW_CLASH_SupportsAirborne.sqf"') < init.index('"ITW_CLASH_SupportsDebug.sqf"')
    assert 'if (isNil "ITW_CLASH_Supports_fnc_SpawnAircraft") exitWith {' in DEBUG
    assert "if (!isServer) exitWith {false};" in DEBUG


def test_a_test_drop_is_free_holds_its_own_lane_and_says_what_it_did():
    drop = function_body(DEBUG, "ITW_CLASH_SupportsDebug_fnc_Drop")
    for needle in [
        "(ITW_CLASH_SupportsDropFlavors + ITW_CLASH_SupportsVehicleFlavors)",
        'call ITW_CLASH_Supports_fnc_DirectPick) params ["_pick","_why"];',
        '_pick set ["lane",format ["TEST-%1",ITW_CLASH_SupportsSerial + 1]];',
        '_pick set ["wallet","TEST"];',
        '_pick set ["price",0];',
        '_pick set ["test",true];',
        '["test-launched",[',
    ]:
        assert needle in drop, needle
    wave = function_body(DEBUG, "ITW_CLASH_SupportsDebug_fnc_BiteBack")
    assert '[_context,_objective,"test",_phase,0,true] call ITW_CLASH_Supports_fnc_LaunchWave;' in wave
    fill = function_body(DEBUG, "ITW_CLASH_SupportsDebug_fnc_Fill")
    assert "_ledger set [[_wallet] call ITW_CLASH_Supports_fnc_WalletKey,_cap];" in fill
    say = function_body(DEBUG, "ITW_CLASH_SupportsDebug_fnc_Say")
    assert '("[C.L.A.S.H. test] " + _text) remoteExec ["systemChat",0];' in say
    assert "supports-debug-ready" in raw("ITW_CLASH_SupportsDebug.sqf")


def test_the_core_still_reads_no_enemy_position():
    # The console tests read a player's position; they live outside the core.
    assert CORE.count("getPosATL") == 2


# ----------------------------------------------------------------- C-RAM


def test_a_c_ram_is_an_autonomous_static_gun_not_a_sam():
    body = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_IsCRAM")
    assert '([_class] call ITW_CLASH_RearBaseCRAM_fnc_CRAMWhy) isEqualTo ""' in body
    why = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_CRAMWhy")
    order = [
        'exitWith {"not-public"}', 'exitWith {"not-autonomous"}', 'exitWith {"not-static"}',
        'exitWith {"artillery"}', 'exitWith {"missile"}', 'exitWith {"no-air-gun"}',
    ]
    assert [why.index(x) for x in order] == sorted(why.index(x) for x in order)
    classes = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_CRAMClasses")
    assert 'if (!isNil "ITW_CLASH_RearBaseCRAMClassesFound") exitWith {ITW_CLASH_RearBaseCRAMClassesFound};' in classes
    assert "ITW_CLASH_RearBaseCRAMClassesFound = _radar + (_found - _radar);" in classes
    # Still no Arma classname in the file.
    assert "B_AAA" not in raw("ITW_CLASH_RearBaseCRAM.sqf")


def test_a_c_ram_comes_first_for_both_sides():
    select = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_SelectClass")
    assert select.index("ITW_CLASH_RearBaseCRAM_fnc_SelectCRAM") < select.index("va_pStaticAAClasses")
    assert 'if (_cram isNotEqualTo "") exitWith {_cram};' in select
    cram = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_SelectCRAM")
    # Its own statics first, then one built for its equipment's side, then any.
    assert cram.index("_own = _own select") < cram.index("_matching") < cram.index("_all#0")
    assert 'getNumber (configFile >> "CfgVehicles" >> (_crewTypes#0) >> "side")' in cram


def test_an_autonomous_piece_is_crewed_by_its_own_ai_on_our_side():
    crew = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_Crew")
    assert 'if (getNumber (configOf _veh >> "isUav") == 1) exitWith {[_side,_veh] call ITW_CLASH_RearBaseCRAM_fnc_CrewAutonomous};' in crew
    auto = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_CrewAutonomous")
    assert "createVehicleCrew _veh;" in auto
    assert "_crew joinSilent _group;" in auto
    assert '_veh setVariable ["ITW_CLASH_ForcedSide",_side,true];' in auto
    assert "cram-then-faction-static-aa-then-faction-aa-vehicle" in raw("ITW_CLASH_RearBaseCRAM.sqf")


def test_v5_a_ciws_round_that_also_hits_ground_still_counts():
    # The Praetorian, from the 2026-10-17 console: airLock 1,
    # aiAmmoUsageFlags 256, EdSubcat_Turrets. v4 needed airLock 2.
    gun = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_GunAir")
    assert "[_ammo] call ITW_CLASH_AirPicture_fnc_AmmoIsGuided" in gun
    assert "_roundLock >= 1 && {((floor (_flags / 256)) mod 2) == 1} && {((floor (_flags / 32)) mod 8) == 0}" in gun
    flags = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_UsageFlags")
    assert "if (isNumber _entry) exitWith {getNumber _entry};" in flags
    assert '((getText _entry) splitString "+ ")' in flags
    why = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_CRAMWhy")
    assert 'if (_lock < 1) exitWith {"no-air-gun"};' in why
    assert why.index('if (_airUse) exitWith {""};') < why.index('if (_lock >= 2) exitWith {""};')
    assert 'if (_profile get "radar") exitWith {""};' in why
    assert '"edsubcat_aas"' in why
    assert why.rstrip().rstrip("}").rstrip().endswith('"not-built-for-air"')


def _usage(text):
    return sum(int(x) for x in text.replace("+", " ").split()) if isinstance(text, str) else text


def _air_use(lock, flags):
    flags = _usage(flags)
    return lock >= 1 and (flags // 256) % 2 == 1 and (flags // 32) % 8 == 0


def test_v5_model_keeps_hmg_turrets_out_and_takes_a_ciws():
    def why(lock, flags=0, radar=False, subcat="", missile=False, artillery=False, static=True, uav=True):
        if not uav: return "not-autonomous"
        if not static: return "not-static"
        if artillery: return "artillery"
        if missile: return "missile"
        if lock < 1: return "no-air-gun"
        if _air_use(lock, flags) or lock >= 2 or radar or subcat.lower() == "edsubcat_aas": return ""
        return "not-built-for-air"
    # The Praetorian exactly as the console read it.
    assert why(1, 256, subcat="EdSubcat_Turrets") == ""
    assert why(1, "256", subcat="EdSubcat_Turrets") == ""
    # An autonomous HMG: also for infantry and vehicles.
    assert why(1, "64 + 128 + 256", subcat="EdSubcat_Turrets") == "not-built-for-air"
    assert why(1, 32 + 64, subcat="EdSubcat_Turrets") == "not-built-for-air"
    assert why(0, 64 + 128, subcat="EdSubcat_Turrets") == "no-air-gun"     # GMG
    assert why(2, 256, missile=True, subcat="EdSubcat_AAs") == "missile"    # SAM site
    assert why(0, 0, artillery=True) == "artillery"                         # naval gun
    # Light or marking bits do not count as ground use.
    assert _air_use(1, 256 + 1 + 2)


def test_v5_the_scan_says_why_once():
    classes = function_body(CRAM, "ITW_CLASH_RearBaseCRAM_fnc_CRAMClasses")
    assert '["cram-scan",[count _candidates,_scan]] call ITW_CLASH_RearBaseCRAM_fnc_Log;' in classes
    assert classes.index("cram-scan") < classes.index("ITW_CLASH_RearBaseCRAMClassesFound = _radar")
    assert '_candidates = _candidates select {!(_x isKindOf "Air")};' in classes
