"""A helicopter armed only with door guns is a transport, and keeps its guns.

Hark, 2026-10-12: "we should strip armed hurons and armed ghosthawks (minus the
stub wing variants) from the dual roles. calling those attack helos is
ridiculous, they can shred a small squad as they insert at BEST." Asked how
wide: "Any door-gun-only helicopter". Asked about the guns: "Keep them loaded".

Impasse's split (VehicleArrays.sqf, _fnAttackTransportSplit) calls a vehicle
armed when any turret, pylon or weapon has a magazine that is not flares or
smoke, or when its config offers CAS support. Armed with enough seats is DUAL,
a combat vehicle. In the run of 2026-10-11 that made door-gun Ghost Hawks and
Hurons combat vehicles, and the unarmed Ghost Hawk too (staged with role 22,
its only magazine flares). Eleven of those sixteen dual helicopters never got a
waypoint from HAL.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def read(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace").replace("\r", "")


def code_only(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return "\n".join(
        line for line in source.split("\n") if not line.lstrip().startswith("//")
    )


def block(source: str, start_marker: str) -> str:
    start = source.index(start_marker)
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
    raise AssertionError(f"unterminated {start_marker}")


def arrays() -> str:
    return code_only(read("VehicleArrays.sqf"))


def split() -> str:
    return block(arrays(), "private _fnAttackTransportSplit = {")


def door_gun_only() -> str:
    return block(arrays(), "private _fnClashDoorGunOnly = {")


def armed_magazine() -> str:
    return block(arrays(), "private _fnClashArmedMagazine = {")


# --- why they were combat vehicles ------------------------------------------------


def test_impasse_counted_cas_support_and_any_gun_as_armed_and_armed_with_seats_as_dual():
    body = split()
    assert 'if ("CAS_Bombing" in _supportTypes || {"CAS_Heli" in _supportTypes}) then {_turrets = true};' in body
    dual = body.index("_dual pushBack _vehType;")
    assert "if (_transportSeats >= _minCargoSeats) then {" in body[dual - 120:dual]


def test_the_split_runs_for_both_sides_helicopters():
    source = arrays()
    runner = source[source.index("[_x,MIN_CARGO_SEATS_FOR_TRANSPORT] call _fnAttackTransportSplit;"):]
    runner = runner[:runner.index('"va_cCarClasses"')]
    assert '"va_pHeliClasses"' in runner and '"va_eHeliClasses"' in runner


# --- the rule ---------------------------------------------------------------------


def test_the_door_gun_check_comes_before_the_dual_push_and_only_for_helicopters_with_seats():
    body = split()
    rule = body.index("private _doorGunTransport = _turrets")
    test = body[rule:body.index(";", body.index("[_cfg] call _fnClashDoorGunOnly", rule)) + 1]
    for term in (
        "{ITW_CLASH_DoorGunHelisAreTransports}",
        '{(_varArray find "HeliClasses") >= 0}',
        "{_transportSeats >= _minCargoSeats}",
        "{[_cfg] call _fnClashDoorGunOnly}",
    ):
        assert term in test, term
    assert rule < body.index("_dual pushBack _vehType;")


def test_a_door_gun_helicopter_goes_to_transport_and_is_recorded_once():
    body = split()
    branch = body[body.index("if (_doorGunTransport) then {"):body.index("} else {\n            if (_turrets) then {")]
    assert "_transport pushBack _vehType;" in branch
    assert "_dual pushBack" not in branch and "_attack pushBack" not in branch
    assert "ITW_CLASH_DoorGunTransportClasses pushBack (toLowerANSI _class);" in branch
    assert "if !((toLowerANSI _class) in ITW_CLASH_DoorGunTransportClasses) then {" in branch
    assert '"CLASH VEHICLES | door-gun-transport | %1"' in branch


def test_everything_else_is_split_exactly_as_before():
    body = split()
    original = body[body.index("} else {\n            if (_turrets) then {"):]
    assert "_dual pushBack _vehType;" in original
    assert '_dualAsTransportVar = (_varArray select [2]) + "DualAsTransport";' in original
    assert "} else {_attack pushBack _vehType};" in original
    assert "if (_transportSeats >= _minCargoSeats) then {_transport pushBack _vehType};" in original


def test_door_gun_only_means_nothing_the_pilots_fire_and_no_armed_pylon():
    body = door_gun_only()
    pilot = body.index('((getArray (_cfg >> "Magazines")) findIf {[_x] call _fnClashArmedMagazine}) >= 0) exitWith {false};')
    pylon = body.index('"TransportPylonsComponent" >> "Pylons","isClass _x"')
    assert '[getText (_x >> "attachment")] call _fnClashArmedMagazine' in body[pylon:pylon + 200]
    assert pilot < pylon


def test_every_armed_turret_is_crew_served_and_fires_bullets():
    body = door_gun_only()
    turrets = block(body, "private _fnClashTurrets = {")
    assert 'if (getNumber (_x >> "isCopilot") > 0) then {_crewServedOnly = false};' in turrets
    assert 'if !(_ammo isKindOf ["BulletBase",configFile >> "CfgAmmo"]) then {' in turrets
    assert 'getText (_x >> "gun") != ""' in turrets
    # Nested turrets are walked, as the split itself walks them.
    assert 'if (isClass (_x >> "Turrets")) then {_x call _fnClashTurrets};' in turrets
    assert 'configProperties [_this >> "Turrets","isClass _x",true]' in turrets
    assert body.rstrip().rstrip("}").rstrip().endswith("_crewServedOnly")


def test_armed_means_what_the_split_already_means():
    """Same exclusions as Impasse's own test: lasers, flares, smoke, water cannon."""
    ours = armed_magazine()
    theirs = split()
    excluded = '["FlareCore","SmokeShell","SmokeLauncherAmmo","CMflareAmmo"] findIf {_ammo isKindOf _x}'
    assert excluded in ours and excluded in theirs
    assert '_mag isKindOf ["Laserbatteries",configFile >> "cfgMagazines"]' in ours
    assert '_x isKindOf ["Laserbatteries",configFile >> "cfgMagazines"]' in theirs
    assert '"waterCannonMagazine_RF"' in ours and '"waterCannonMagazine_RF"' in theirs


def test_the_switch_and_the_list_exist_before_the_split_runs():
    source = arrays()
    switch = source.index('"ITW_CLASH_DoorGunHelisAreTransports",true')
    listed = source.index("ITW_CLASH_DoorGunTransportClasses = [];")
    runs = source.index("[_x,MIN_CARGO_SEATS_FOR_TRANSPORT] call _fnAttackTransportSplit;")
    assert switch < listed < runs


# --- the guns stay loaded ----------------------------------------------------------


KEEP = '!(!isNil "ITW_CLASH_fnc_KeepsDoorGuns" && {[_veh] call ITW_CLASH_fnc_KeepsDoorGuns})'


def test_the_keep_predicate_reads_the_recorded_classes():
    source = arrays()
    body = block(source, "ITW_CLASH_fnc_KeepsDoorGuns = {")
    assert "(toLowerANSI typeOf _veh) in ITW_CLASH_DoorGunTransportClasses" in body
    assert "!isNull _veh" in body
    assert source.index("ITW_CLASH_fnc_KeepsDoorGuns = {") < source.index("VEHICLE_ARRAYS_COMPLETE = true;")
    assert "CLASH BOOT | door-gun-transports-ready | enabled=%1 classes=%2" in source


def test_every_disarm_for_being_a_transport_skips_a_door_gun_helicopter():
    sites = {
        "ITW_Attack.sqf": "_vehInfo#VEHINFO_ROLE == ITW_VEH_ROLE_TRANSPORT",
        "ITW_CLASH_DualHALCheckbookPreInit.sqf": "_vehInfo#VEHINFO_ROLE == ITW_VEH_ROLE_TRANSPORT",
        "ITW_CLASH_DualHALCheckbookHardening.sqf": "(_vehInfo#VEHINFO_ROLE) == ITW_VEH_ROLE_TRANSPORT",
        "ITW_CLASH_DualHALCheckbook.sqf": "(_vehDef#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT",
    }
    for name, role_test in sites.items():
        source = code_only(read(name))
        strip = source.index('[_veh] remoteExec ["ITW_AtkVehRemoveMagazines",_veh];')
        guard = source[source.rindex("if (", 0, source.rindex(role_test, 0, strip)):strip]
        assert role_test in guard, name
        assert KEEP in guard, name
        assert source.count('remoteExec ["ITW_AtkVehRemoveMagazines",_veh]') == 1, name


def test_casevac_and_medevac_still_disarm_whatever_they_take():
    for name in ("ITW_CLASH_CASEVAC.sqf", "ITW_CLASH_CASEVAC_AirOpsFix.sqf",
                 "ITW_CLASH_GroundMEDEVAC.sqf", "ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf"):
        assert "ITW_CLASH_fnc_KeepsDoorGuns" not in read(name), name


def test_the_disarm_itself_is_unchanged():
    source = read("ITW_Attack.sqf")
    body = block(source, "ITW_AtkVehRemoveMagazines = {")
    assert 'select {_n=toLowerANSI (_x#0);!("smoke" in _n) && !("flare" in _n)};' in body
    assert "KeepsDoorGuns" not in body


def test_versions():
    assert "ITW_CLASH_DualHALCheckbookPreInitVersion = 3;" in read("ITW_CLASH_DualHALCheckbookPreInit.sqf")
    assert "ITW_CLASH_DualHALCheckbookHardeningVersion = 6;" in read("ITW_CLASH_DualHALCheckbookHardening.sqf")
    assert "ITW_CLASH_DualHALCheckbookVersion = 8;" in read("ITW_CLASH_DualHALCheckbook.sqf")
