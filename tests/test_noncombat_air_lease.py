"""A helicopter HAL calls non-combat is leased as a transport.

Hark, 2026-10-11: "very long rpt, tons of helicopters hanging". Then, of the
fix that asks HAL: "1 is fucking peak."

Run of 2026-10-11 20:23, mission 2. Sixteen dual-role helicopters were handed
from Impasse to HAL. HAL gave attack orders to the ones it counts as combat
aircraft. Eleven never had a waypoint. The unarmed Ghost Hawks among them:

    G242  enemy   handed over 21:24   no waypoint to the end of the log
    G304  BLUFOR  handed over 21:45   no waypoint to the end of the log
    G366  BLUFOR  handed over 22:03   shot down at 48 m, 22:32:56
    G504  BLUFOR  handed over 22:58   shot down at 48 m, 23:00:26
    G121  enemy   handed over 20:53   shot down at 48 m, 20:55:52

Why nobody moved them:

  1. StageFieldVehicle puts the aircraft at ground level near the base and
     gives it no order. Impasse spawned it in flight, so it climbs back up and
     hovers.
  2. The storage lease went only to transport deployments. "combat DUAL
     deployments bypass the lifecycle wrapper entirely."
  3. HAL's idle pass leaves out aircraft and non-combat cargo.

v4 of ITW_CLASH_ServiceAuthority.sqf asks HAL whether the helicopter can fight,
with the lists and the expression HAL's own situation report uses, and gives a
non-combat one exactly what a transport deployment gets.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r", "")


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
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return "\n".join(
        line for line in source.split("\n") if not line.lstrip().startswith("//")
    )


def authority() -> str:
    return read(MISSION / "ITW_CLASH_ServiceAuthority.sqf")


def verdict() -> str:
    return code_only(function_body(authority(), "ITW_CLASH_ServiceAuthority_fnc_HALAirVerdict"))


def await_() -> str:
    return code_only(function_body(authority(), "ITW_CLASH_ServiceAuthority_fnc_AwaitAirVerdict"))


def wrapper() -> str:
    source = authority()
    start = source.index("ITW_CLASH_ServiceAuthority_fnc_StageFieldVehicleLifecycleBase = ")
    return code_only(function_body(source[start:], "ITW_CLASH_DualHAL_fnc_StageFieldVehicle"))


# --- why they hung, in the source ----------------------------------------------


def test_hal_never_gives_an_idle_order_to_aircraft_or_noncombat_cargo():
    orders = read(NR6 / "HAL" / "HQOrders.sqf")
    reserve = orders[orders.index("_reserve = (_HQ getVariable [\"RydHQ_Friends\",[]])"):]
    reserve = reserve[:reserve.index("\n")]
    assert '(_HQ getVariable ["RydHQ_AirG",[]])' in reserve
    assert "RydHQ_NCCargoG" in reserve
    assert "HAL_GoIdle" in orders


def test_the_handoff_gives_an_aircraft_no_order_and_adds_it_to_hals_air():
    stage = function_body(read(MISSION / "ITW_CLASH_DualHALCheckbook.sqf"), "ITW_CLASH_DualHAL_fnc_StageFieldVehicle")
    assert '_air pushBackUnique _crewGroup;' in stage
    assert '_hq setVariable ["RydHQ_AirG",_air];' in stage
    for order in ("addWaypoint", "land ", "doMove", "commandMove"):
        assert order not in stage, order


def test_the_lease_went_only_to_transport_deployments():
    body = wrapper()
    gate = body.index("if (_transportDeployment && {!isNull _veh} && {!isNull _group}) then {")
    assert '"TRANSPORT","impasse-handoff"' in body[gate:gate + 400]
    assert "combat DUAL deployments bypass the lifecycle wrapper entirely" in authority()


def test_hal_files_an_aircraft_as_unarmed_when_it_carries_only_flares():
    fnc2 = read(NR6 / "HAC_fnc2.sqf")
    assert "_isArmed = (count (_mags - _flareMags)) > 0;" in fnc2
    flares = fnc2[fnc2.index("_flareMags = ["):]
    flares = flares[:flares.index("];")]
    # The unarmed Ghost Hawk's only magazine (dual-hal-echelon-decided, G242).
    assert '"168Rnd_CMFlare_Chaff_Magazine"' in flares
    unarmed = fnc2[fnc2.index('case ("air") :'):]
    unarmed = unarmed[:600]
    assert "RHQ_Air pushBackUnique _veh;" in unarmed
    assert "if not (_isArmed) then" in unarmed
    assert "RHQ_NCAir pushBackUnique _veh;" in unarmed


def test_hal_puts_a_group_on_its_noncombat_air_list_by_the_drivers_vehicle_class():
    sitrep = read(NR6 / "HAL" / "HQSitRep.sqf")
    assert "_NCAir_class = RHQ_NCAir + RYD_WS_NCAir_class - RHQs_NCAir;" in sitrep
    assert "_Air_class = RHQ_Air + RYD_WS_Air_class - RHQs_Air;" in sitrep
    fnc2 = read(NR6 / "HAC_fnc2.sqf")
    assert "_Tvh = toLower (typeOf _vh);" in fnc2
    assert "if (((_grp == _grpD) and {(_Tvh in _NCAir_class)}) or {(_tp in _NCAir_class)}) then {_NCAircheck = true;" in fnc2
    assert '_HQ setVariable ["RydHQ_NCAirG",_NCAirG];' in fnc2
    # Its attack pool leaves that list out.
    orders = read(NR6 / "HAL" / "HQOrders.sqf")
    assert '(_HQ getVariable ["RydHQ_AirG",[]]) - ((_HQ getVariable ["RydHQ_NCAirG",[]])' in orders


# --- HAL's verdict, read the way HAL reads it -------------------------------------


def test_the_verdict_uses_hals_lists_and_hals_expression():
    body = verdict()
    assert "private _class = toLower (typeOf _veh);" in body
    squash = re.sub(r"\s+", " ", body)
    assert (
        'private _ncAir = RHQ_NCAir + (missionNamespace getVariable ["RYD_WS_NCAir_class",[]]) '
        '- (missionNamespace getVariable ["RHQs_NCAir",[]]);'
    ) in squash
    assert (
        'private _air = RHQ_Air + (missionNamespace getVariable ["RYD_WS_Air_class",[]]) '
        '- (missionNamespace getVariable ["RHQs_Air",[]]);'
    ) in squash


def test_unarmed_is_asked_first_and_an_unknown_class_is_no_verdict():
    body = verdict()
    nc = body.index('if (_class in _ncAir) exitWith {"non-combat"};')
    combat = body.index('if (_class in _air) exitWith {"combat"};')
    assert nc < combat
    assert body.rstrip().rstrip("}").rstrip().endswith('""')
    assert 'if (isNil "RHQ_Air" || {isNil "RHQ_NCAir"}) exitWith {""};' in body


def test_the_per_cycle_combat_lists_are_not_the_verdict():
    """RydHQ_CombatAv and RydHQ_AttackAv say who is free this cycle. G119 and
    G460, attack helicopters, first showed on them 11 and 23 minutes after
    their handover."""
    for body in (verdict(), await_(), wrapper()):
        for name in ("RydHQ_CombatAv", "RydHQ_AttackAv", "RydHQ_FlankAv", "Busy"):
            assert name not in body, name


# --- what a non-combat helicopter gets ---------------------------------------------


def test_only_a_helicopter_that_was_not_already_a_transport_is_asked_about():
    body = wrapper()
    asked = body.index("[_veh,_group] spawn ITW_CLASH_ServiceAuthority_fnc_AwaitAirVerdict;")
    gate = body[body.rindex("if (", 0, asked):asked]
    for term in (
        "ITW_CLASH_ServiceNonCombatAirLease",
        "{!_transportDeployment}",
        '{_veh isKindOf "Helicopter"}',
        "{!isNull _veh}",
        "{!isNull _group}",
    ):
        assert term in gate, term
    # After the transport lease, inside the same successful-handoff block.
    assert body.index('"TRANSPORT","impasse-handoff"') < asked
    assert body.index("if (_result && {_vehInfo isEqualType []}") < asked


def test_it_runs_beside_the_handoff_and_never_holds_it_up():
    body = wrapper()
    assert "spawn ITW_CLASH_ServiceAuthority_fnc_AwaitAirVerdict" in body
    assert "call ITW_CLASH_ServiceAuthority_fnc_AwaitAirVerdict" not in body


def test_the_wait_is_bounded_and_ends_if_the_helicopter_or_crew_is_gone():
    body = await_()
    loop = body[body.index("while {"):]
    assert '_verdict isEqualTo "" && {time < _startedAt + ITW_CLASH_ServiceAirVerdictWait}' in loop[:200]
    assert "isNull _veh || {!alive _veh} || {isNull _group}" in loop
    assert "exitWith {_lost = true}" in loop
    assert "sleep 5" in loop
    assert "if (_lost) exitWith {false};" in body


def test_a_combat_verdict_or_no_verdict_changes_nothing():
    body = await_()
    for event in ('"air-verdict-timeout"', '"air-verdict-combat"'):
        at = body.index(event)
        branch = body[body.rindex("exitWith {", 0, at):body.index("};", at)]
        assert "SetLease" not in branch and "ApplyTransportDoctrine" not in branch
        assert branch.rstrip().endswith("false")


def test_a_noncombat_helicopter_gets_what_a_transport_deployment_gets_in_the_same_order():
    body = await_()
    already = body.index("if ([_veh] call ITW_CLASH_ServiceAuthority_fnc_HasLease) exitWith {false};")
    doctrine = body.index('[_group,true,"hal-noncombat-air"] call')
    lease = body.index('[_veh,_group,"TRANSPORT","hal-noncombat-air"] call')
    register = body.index('_veh,"TRANSPORT",[_veh] call ITW_CLASH_Service_fnc_ModeForVehicle,"hal-noncombat-air"')
    logged = body.index('"air-verdict-noncombat-leased"')
    assert body.index('"air-verdict-combat"') < already < doctrine < lease < register < logged
    assert "ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine" in body[doctrine:lease]
    assert "ITW_CLASH_ServiceAuthority_fnc_SetLease" in body[lease:register]
    assert "] call ITW_CLASH_Service_fnc_RegisterPhysical;" in body[register:logged]

    # The transport path in StageFieldVehicle: doctrine first, then the lease.
    stage = function_body(read(MISSION / "ITW_CLASH_DualHALCheckbook.sqf"), "ITW_CLASH_DualHAL_fnc_StageFieldVehicle")
    assert "ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine" in stage


def test_the_lease_is_what_makes_hal_able_to_fly_it_as_cargo():
    """Doctrine puts the crew on RydHQ_CargoG, the list HAL's cargo order
    picks carriers from."""
    doctrine = function_body(read(MISSION / "ITW_CLASH_DualHALCheckbook.sqf"), "ITW_CLASH_DualHAL_fnc_ApplyTransportDoctrine")
    assert 'private _cargo = +(_hq getVariable ["RydHQ_CargoG",[]]);' in doctrine
    scargo = read(NR6 / "HAL" / "SCargo.sqf")
    assert '_cargos = ((_HQ getVariable ["RydHQ_CargoG",[]])' in scargo


def test_registration_needs_the_lease_first():
    register = function_body(authority(), "ITW_CLASH_Service_fnc_RegisterPhysical")
    assert '"no-explicit-service-lease"' in register


def test_the_verdict_thread_moves_nothing():
    body = await_() + verdict()
    for order in ("addWaypoint", "land ", "doMove", "commandMove", "setPos", "deleteVehicle", "engineOn"):
        assert order not in body, order


def test_the_stored_helicopter_is_the_lifecycle_already_flown():
    """Stored after four minutes unclaimed at home: SVC-603477-2, registered
    20:33:42, stored 20:38:01."""
    lifecycle = read(MISSION / "ITW_CLASH_ServiceLifecycle.sqf")
    assert '"ITW_CLASH_ServiceInitialStorageGrace",240' in lifecycle
    assert '"ITW_CLASH_ServiceStrandedFieldGrace",300' in lifecycle


# --- switches and boot line ----------------------------------------------------------


def test_switches_and_boot_line():
    source = authority()
    assert "ITW_CLASH_ServiceAuthorityVersion = 4;" in source
    assert '"ITW_CLASH_ServiceNonCombatAirLease",true' in source
    assert '"ITW_CLASH_ServiceAirVerdictWait",600' in source
    assert "nonCombatAirLease=%2 airVerdictWait=%3s airVerdictFrom=RHQ_NCAir" in source
