"""The rack profile: what a vehicle can fire, read from its live rack.

Built from the 2026-10-16 console reads of the stub-wing Ghost Hawk (MH-80
DAP, Game Update 2.22): DAGR-M ammo M_PGM_AT flags "128 + 64", IR and laser
lock, no manual control, AI modes Far_AI 600-5000 and Medium_AI 300-3000,
player modes Burst and LoalDistance at 0-2 m, warhead ammo_Penetrator_PG_AT.
DAR rockets: flags 192, Far_AI 1000-3200, Medium_AI 400-1200.
"""

import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code(name: str) -> str:
    source = (MISSION / name).read_text(encoding="utf-8")
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


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


def rack() -> str:
    return code("ITW_CLASH_RackProfile.sqf")


# ------------------------------------------------------------ static contract


def test_it_reads_and_never_writes():
    source = rack()
    for verb in ["setVariable [\"Busy", "addWaypoint", "doMove", "setPylonLoadout", "setVehicleAmmo",
                 "setBehaviour", "setCombatMode", "flyInHeight", "fireAtTarget"]:
        assert verb not in source, verb


def test_flags_are_the_missile_and_its_warhead_together():
    """v2. The DAGR-M's own flags are 64 + 128 and its armour bit is on its
    warhead. v1 read the warhead only when the missile had none, so the DAP
    profiled ARMOR 0 while the AI fired DAGR-M at a Panther (2026-10-16)."""
    source = rack()
    flags = function_body(source, "ITW_CLASH_Rack_fnc_ConfigFlags")
    assert "if (isNumber _entry) exitWith {getNumber _entry};" in flags
    assert '(getText _entry) splitString "+ "' in flags
    ammo = function_body(source, "ITW_CLASH_Rack_fnc_Ammo")
    assert "private _sub = [_config] call ITW_CLASH_Rack_fnc_Submunition;" in ammo
    assert "call ITW_CLASH_Rack_fnc_Union;" in ammo
    # Hit and splash only when neither says anything.
    assert ammo.index("fnc_Union") < ammo.index("if (_flags <= 0) then {")
    assert '(getNumber (_config >> "hit") >= 150): {128 + 512}' in ammo
    sub = function_body(source, "ITW_CLASH_Rack_fnc_Submunition")
    assert "if (isText _entry) exitWith {getText _entry};" in sub
    assert "(getArray _entry) select {_x isEqualType \"\"}" in sub
    assert "ITW_CLASH_RackProfileVersion = 4;" in (MISSION / "ITW_CLASH_RackProfile.sqf").read_text()


def union(a, b):
    """Python mirror of ITW_CLASH_Rack_fnc_Union."""
    total, bit = 0, 1
    for _ in range(16):
        if (a // bit) % 2 == 1 or (b // bit) % 2 == 1:
            total += bit
        bit *= 2
    return total


def test_union_math():
    assert union(64 + 128, 512) == 64 + 128 + 512
    assert union(192, 192) == 192
    assert union(0, 512) == 512
    assert union(0, 0) == 0
    body = function_body(rack(), "ITW_CLASH_Rack_fnc_Union")
    assert 'for "_i" from 0 to 15 do {' in body


def test_lock_types_cover_manual_ace_ir_laser_and_unguided():
    ammo = function_body(rack(), "ITW_CLASH_Rack_fnc_Ammo")
    for lock in ['"MANUAL"', '"ACE"', '"IR_LASER"', '"IR"', '"LASER"', '"AIR"', '"NONE"']:
        assert lock in ammo, lock
    assert ammo.index('"manualControl"') < ammo.index('"irLock"')


def test_player_only_modes_are_not_ai_bands():
    source = rack()
    assert 'ITW_CLASH_RackAIModeMinReach",50]' in source
    bands = function_body(source, "ITW_CLASH_Rack_fnc_Bands")
    assert "if (_max >= ITW_CLASH_RackAIModeMinReach) then {_bands pushBackUnique [_min max 0,_max]};" in bands
    assert 'getArray (_config >> "muzzles")' in bands
    assert '"missileLockMinDistance"' in bands


def test_weapons_are_found_by_pylon_or_magazine_well():
    body = function_body(rack(), "ITW_CLASH_Rack_fnc_WeaponFor")
    assert '"pylonWeapon"' in body
    assert "compatibleMagazines _candidate" in body


def test_entries_come_from_the_live_rack_and_skip_countermeasures():
    body = function_body(rack(), "ITW_CLASH_Rack_fnc_Entries")
    assert "forEach (magazinesAllTurrets _veh);" in body
    assert "if (_rounds <= 0) then {continue};" in body
    assert "ITW_CLASH_Rack_fnc_IsCountermeasure" in body
    cm = function_body(rack(), "ITW_CLASH_Rack_fnc_IsCountermeasure")
    for kind in ['"CMFlareLauncher"', '"SmokeLauncher"', '"Laserdesignator_mounted"']:
        assert kind in cm


def test_only_missiles_rockets_and_carriers_guide():
    """v4. A bullet's airLock means it may shoot at aircraft, not that it has
    a seeker. v3 read it as AIR, so the Pawnee's M134 (flags 448) and the
    Blackfoot's 20 mm (192) did not count against infantry (2026-10-16)."""
    ammo = function_body(rack(), "ITW_CLASH_Rack_fnc_Ammo")
    assert 'private _guides = _simulation in ["shotmissile","shotrocket","shotsubmunitions"];' in ammo
    lock = ammo[ammo.index("private _lock = switch (true) do {"):]
    assert lock.index('case (!_guides): {"NONE"};') < lock.index('"manualControl"')
    assert "gunsUnguided=true" in rack()


def gun(flags, bands, aim="FIXED"):
    return {"flags": flags, "lock": "NONE", "aim": aim, "bands": bands}


def test_the_guns_now_count_against_infantry():
    m134 = gun(448, [(0, 300), (100, 600), (300, 800), (800, 1500)])
    dar = {"flags": 192, "lock": "NONE", "aim": "FIXED", "bands": [(1000, 3200), (400, 1200)]}
    # The Pawnee: both weapons against infantry, pointing from 1 km.
    assert [e for e in [m134, dar] if usable(e, "INFANTRY")] == [m134, dar]
    assert standoff([m134, dar]) == 1000
    assert orbit([m134, dar])[1] == "POINT"
    # The Blackfoot's chin gun is a turret: it orbits against infantry too.
    gatling = gun(192, [(0, 400), (200, 1000), (800, 1800), (1400, 2500)], aim="TURRET")
    assert usable(gatling, "INFANTRY")
    assert orbit([gatling])[1] == "ORBIT"


def test_seekers_cannot_be_used_on_infantry():
    body = function_body(rack(), "ITW_CLASH_Rack_fnc_Usable")
    assert 'if ((_bits#_bit) == 64 && {!(_lock in ["NONE","MANUAL"])}) exitWith {false};' in body


def test_guided_anti_armour_needs_a_seeker():
    body = function_body(rack(), "ITW_CLASH_Rack_fnc_IsGuidedAntiArmour")
    assert 'if (_simulation isNotEqualTo "shotmissile") exitWith {false};' in body
    assert 'if (_lock in ["NONE","AIR"]) exitWith {false};' in body
    # The warhead's armour bit is already in the flags (fnc_Ammo).
    assert "[_flags,512] call ITW_CLASH_Rack_fnc_HasBit" in body


def test_the_guided_pass_reads_through_the_rack():
    strike = code("ITW_CLASH_SupportsStrike.sqf")
    guided = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_IsGuidedAntiArmor")
    assert "[_ammo] call ITW_CLASH_Rack_fnc_IsGuidedAntiArmour" in guided
    weapon = function_body(strike, "ITW_CLASH_SupportsStrike_fnc_GuidedWeapon")
    assert "([_veh,_magazine,_turret] call ITW_CLASH_Rack_fnc_WeaponFor)#0" in weapon
    # v6 (2026-10-18) added the motor rule in front of the rack call.
    assert int(re.search(r"ITW_CLASH_SupportsStrikeVersion = (\d+);", (MISSION / "ITW_CLASH_SupportsStrike.sqf").read_text()).group(1)) >= 5


def test_it_boots_before_its_readers():
    init = (MISSION / "init.sqf").read_text(encoding="utf-8")
    rack_at = init.index('call compile preprocessFileLineNumbers "ITW_CLASH_RackProfile.sqf";')
    assert rack_at < init.index('preprocessFileLineNumbers "ITW_CLASH_Supports.sqf"')
    preflight = (MISSION / "ITW_CLASH_DebugPreflight.sqf").read_text(encoding="utf-8")
    assert '["ITW_CLASH_RackProfile","rack profile"' in preflight


# ------------------------------------------------------- the orbit, in Python

MARGIN = 1.2
R_MIN = 250
R_MAX = 1500
REACH = 50


def bands(modes):
    return [(lo, hi) for lo, hi in modes if hi >= REACH]


def usable(entry, kind):
    bits = {"INFANTRY": [64], "VEHICLE": [128], "ARMOR": [512], "STATIC": [128, 64]}[kind]
    hit = next((b for b in bits if (entry["flags"] // b) % 2 == 1), None)
    if hit is None:
        return False
    if hit == 64 and entry["lock"] not in ("NONE", "MANUAL"):
        return False
    return True


def orbit(entries, step=45):
    """Python mirror of ITW_CLASH_Rack_fnc_Orbit."""
    if not entries:
        return -1, ""
    inner = math.cos(math.radians(step / 2))
    candidates = set()
    for e in entries:
        for lo, hi in e["bands"]:
            r = max((lo / inner) * MARGIN, R_MIN)
            if r <= hi:
                candidates.add(round(r))
    candidates = sorted(candidates) or [R_MIN]
    best, best_score = candidates[0], -1
    for r in candidates:
        score = sum(1 for e in entries if any(lo <= r * inner and r <= hi for lo, hi in e["bands"]))
        if score > best_score:
            best, best_score = r, score
    radius = min(max(best, R_MIN), R_MAX)
    mode = "ORBIT" if any(e["aim"] == "TURRET" for e in entries) else "POINT"
    return radius, mode


GUIDED_MAX = 2000
UNGUIDED_MAX = 1000


def standoff(entries):
    """Python mirror of ITW_CLASH_Rack_fnc_Standoff."""
    if not entries:
        return -1
    guided = [e for e in entries if e["lock"] != "NONE"]
    chosen = guided or entries
    high = GUIDED_MAX if guided else UNGUIDED_MAX
    low = 0
    for e in chosen:
        if not e["bands"]:
            continue
        lo = min(b[0] for b in e["bands"])
        hi = max(b[1] for b in e["bands"])
        high = min(high, hi / MARGIN)
        low = max(low, lo * MARGIN)
    return round(max(high, low))


DAGRM = {"flags": union(192, 512), "lock": "IR_LASER", "aim": "FIXED",
         "bands": bands([(600, 5000), (300, 3000), (0, 2), (0, 2)])}
DAR = {"flags": 192, "lock": "NONE", "aim": "FIXED",
       "bands": bands([(1000, 3200), (400, 1200), (0, 2)])}


def test_player_modes_drop_out_of_the_dagr_m():
    assert DAGRM["bands"] == [(600, 5000), (300, 3000)]


def test_the_stock_dap_cannot_be_flown_at_infantry():
    rack_ = [DAGRM]
    assert [e for e in rack_ if usable(e, "INFANTRY")] == []
    assert orbit([e for e in rack_ if usable(e, "INFANTRY")]) == (-1, "")


def test_the_stock_dap_points_from_2_km_at_vehicles_and_armour():
    for kind in ["VEHICLE", "ARMOR"]:
        rack_ = [e for e in [DAGRM] if usable(e, kind)]
        assert rack_ == [DAGRM], kind
        assert orbit(rack_)[1] == "POINT"
        # The DAP hit from 1.6 to 2.7 km on 2026-10-16; 2 km is inside both
        # DAGR-M AI bands and well clear of the 342 to 685 m fight.
        assert standoff(rack_) == 2000


def test_rockets_point_from_a_kilometre():
    assert standoff([e for e in [DAGRM, DAR] if usable(e, "INFANTRY")]) == 1000


def test_with_a_guided_weapon_aboard_its_distance_wins():
    # Rockets and guns join in if they reach; the missiles set the range.
    assert standoff([DAGRM, DAR]) == 2000


def test_a_short_gun_points_from_where_it_reaches():
    pod = {"flags": 192, "lock": "NONE", "aim": "FIXED", "bands": [(0, 500)]}
    assert standoff([pod]) == round(500 / MARGIN)


def test_nothing_is_inside_a_floor():
    far_floor = {"flags": 192, "lock": "IR", "aim": "FIXED", "bands": [(1900, 2100)]}
    assert standoff([far_floor]) == round(1900 * MARGIN)


def test_the_standoff_mirror_matches_the_sqf_shape():
    body = function_body(rack(), "ITW_CLASH_Rack_fnc_Standoff")
    assert 'private _guided = _usable select {!((_x#6) isEqualTo "NONE")};' in body
    assert "_high = _high min (_hi / ITW_CLASH_RackRadiusMargin);" in body
    assert "_low = _low max (_lo * ITW_CLASH_RackRadiusMargin);" in body
    assert "round (_high max _low)" in body
    source = rack()
    assert 'ITW_CLASH_RackPointGuidedMax",2000]' in source
    assert 'ITW_CLASH_RackPointUnguidedMax",1000]' in source
    assert "fnc_Run" not in source
    profile = function_body(source, "ITW_CLASH_Rack_fnc_Profile")
    assert "_types set [_type,[count _usable,_radius,_mode,[_usable] call ITW_CLASH_Rack_fnc_Standoff]];" in profile


def test_rockets_put_infantry_inside_the_dar_band():
    radius, mode = orbit([e for e in [DAGRM, DAR] if usable(e, "INFANTRY")])
    inner = math.cos(math.radians(22.5))
    assert 400 <= radius * inner and radius <= 1200, radius
    assert mode == "POINT"


def test_a_gunner_on_the_rack_means_keep_moving():
    cannon = {"flags": 64 + 128, "lock": "NONE", "aim": "TURRET", "bands": [(0, 1500)]}
    radius, mode = orbit([cannon, DAGRM])
    assert mode == "ORBIT"
    # Both the turret gun and the DAGR-M's 300 m mode cover the ring.
    inner = math.cos(math.radians(22.5))
    assert radius * inner >= 300 and radius <= 1500


def test_the_python_mirror_matches_the_sqf_shape():
    body = function_body(rack(), "ITW_CLASH_Rack_fnc_Orbit")
    assert "private _inner = cos (_step / 2);" in body
    assert "((_min / _inner) * ITW_CLASH_RackRadiusMargin) max ITW_CLASH_RackRadiusMin" in body
    assert "((_x#0) <= (_radius * _inner)) && {_radius <= (_x#1)}" in body
    assert "if (_score > _bestScore) then {_bestScore = _score; _best = _radius};" in body
    assert '(_x#7) isEqualTo "TURRET"' in body
    assert 'ITW_CLASH_RackRadiusMargin",1.2]' in rack()
