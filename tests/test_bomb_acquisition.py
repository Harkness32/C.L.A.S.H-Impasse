"""Supports v4 / strike v4: lone targets for the bomb, on-site acquisition.

See docs/CLASH_CommanderSupports_Model.md. These pin the contracts:

- BOMB and GUIDED share the acquiring floor (1.5; v4 bomb, v5 both): a lone
  vehicle, a lone tank, a manned static or a pair of riflemen qualifies; one
  rifleman does not.
- CARPET stays for clusters: fewer than three contacts is NOT_CLUSTERED.
- BOMB and GUIDED acquire on site. They skip the assessment's uncertainty
  gate, and go on a contact still believed to exist after its position has
  gone stale; the others still need a position good enough to drop on.
- The bomber acquires only what it has itself: a track on its own sensors or
  a sighting by its own crew after the pass began. A reveal points the crew;
  it is never a sighting.
- Nothing acquired by the final check: the report only if it is still inside
  the uncertainty limit, otherwise a refunded break-off.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code(name: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", (MISSION / name).read_text(encoding="utf-8"), flags=re.S)
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


CORE = code("ITW_CLASH_Supports.sqf")
STRIKE = code("ITW_CLASH_SupportsStrike.sqf")


# ------------------------------------------------------------------- gates


def test_the_acquiring_flavors_have_their_own_floor_and_carpet_needs_a_cluster():
    assert '["ITW_CLASH_SupportsValueFloorAcquire",1.5]' in CORE
    assert '["ITW_CLASH_SupportsCarpetMinContacts",3]' in CORE
    # The general floor is unchanged for everything else.
    assert '["ITW_CLASH_SupportsValueFloor",2]' in CORE
    candidates = function_body(CORE, "ITW_CLASH_Supports_fnc_StrikeCandidates")
    assert (
        'if (_flavor isEqualTo "CARPET" && {(_cluster get "count") < ITW_CLASH_SupportsCarpetMinContacts}) then {'
        in candidates
    )
    assert '[_context,_flavor,-1,_targetKey,"NOT_CLUSTERED"] call ITW_CLASH_Supports_fnc_Exclude;' in candidates
    # v5: the guided pass too; it was excluded from four lone vehicles in one
    # session while the bomb flew at them.
    assert "private _floor = if (_flavor in ITW_CLASH_SupportsAcquireFlavors) then {" in candidates
    assert "ITW_CLASH_SupportsValueFloorAcquire" in candidates
    assert 'if ((_cluster get "worth") < _floor) then {' in candidates
    # Carpet is refused as a non-cluster before the floor is read.
    assert candidates.index('"NOT_CLUSTERED"') < candidates.index('"BELOW_FLOOR"')
    # The bomb still needs a real sighting at assessment.
    assert '"NO_CONTACT"' in candidates


def test_a_lone_rifleman_stays_below_the_bomb_floor():
    # COLOSSUS weights, through the knowledge layer's ClassWorth.
    knowledge = code("ITW_CLASH_Knowledge.sqf")
    worth = function_body(knowledge, "ITW_CLASH_Knowledge_fnc_ClassWorth")
    weights = dict(re.findall(r'case "([A-Z]+)": \{missionNamespace getVariable \["[A-Za-z_]+",([0-9.]+)\]\}', worth))
    floor = 1.5
    assert float(weights["INFANTRY"]) < floor
    assert 2 * float(weights["INFANTRY"]) >= floor
    assert float(weights["VEHICLE"]) >= floor
    assert float(weights["ARMOR"]) >= floor
    assert float(weights["STATIC"]) + float(weights["INFANTRY"]) >= floor


def test_the_acquiring_passes_go_on_a_stale_position_the_others_do_not():
    target_now = function_body(CORE, "ITW_CLASH_Supports_fnc_TargetNow")
    assert 'params ["_side","_keys",["_ahead",0],["_held",false]];' in target_now
    held = target_now[target_now.index("if (_held) then {"):]
    held = held[:held.index("private _weight")]
    assert "([_record] call ITW_CLASH_Knowledge_fnc_Existence) <= 0" in held
    assert '([_record] call ITW_CLASH_Knowledge_fnc_Status) isEqualTo "LOST"' in held

    pre_run = function_body(CORE, "ITW_CLASH_Supports_fnc_PreRun")
    assert 'private _acquires = (_support get "flavor") in ITW_CLASH_SupportsAcquireFlavors;' in pre_run
    assert '_support get "ahead",_acquires] call' in pre_run
    assert "if (!_acquires && {_r > ITW_CLASH_SupportsUncertaintyLimit}) exitWith {" in pre_run
    assert '_support set ["denied","TARGET_GONE"]' in pre_run


def test_the_boot_line_reports_the_new_gates():
    assert "acquireFloor=%22 carpetMinContacts=%23 acquireOnSite=%24" in CORE
    assert 'ITW_CLASH_SupportsAcquireFlavors joinString "/"' in CORE
    assert "bombAcquires=%20 reveal=%21 reline=%22s/%23m lead=%24s/%25s/%26m" in STRIKE


# ------------------------------------------------------------- acquisition


def test_a_reveal_is_never_a_sighting():
    sighting = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_CrewSighting")
    assert "private _intel = _x targetKnowledge _object;" in sighting
    # A revealed, unseen target has no sighting time on the clock; only one
    # after the pass began counts.
    assert "_seen >= _since" in sighting
    assert "_seen <= (time + 1)" in sighting

    unguided = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    reveal = unguided.index("{_group reveal [_x,ITW_CLASH_SupportsStrikeRevealValue]} forEach _wanted;")
    since = unguided.index("_since = time + 1;")
    assert reveal < since
    assert '["ITW_CLASH_SupportsStrikeRevealValue",1.5]' in STRIKE


def test_a_fix_is_the_jets_own_sensor_track_or_crew_sighting():
    fix = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_BombFix")
    assert "getSensorTargets _veh" in fix
    assert '(_x param [2,""]) isEqualTo "enemy"' in fix
    assert '"SENSOR"' in fix and '"SIGHT"' in fix
    assert "call ITW_CLASH_SupportsStrike_fnc_CrewSighting" in fix
    # A track is checked first, being fresher.
    assert fix.index("getSensorTargets") < fix.index("fnc_CrewSighting")


def test_the_scan_takes_only_acquired_targets_clear_of_our_people():
    scan = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_BombScan")
    assert "forEach (getSensorTargets _veh);" in scan
    assert "{_pool pushBackUnique (vehicle _x)} forEach (_x targets [true,_reach]);" in scan
    for needle in (
        "if (_fix isEqualTo []) then {continue};",
        "if (((_fix#0) distance2D _report) > _radius) then {continue};",
        "if ([_friendlies,_fix#0,_footprint] call ITW_CLASH_Supports_fnc_DangerClose) then {continue};",
        "if ([_hq,[_object]] call ITW_CLASH_Supports_fnc_ETBAnswering) then {continue};",
        'if (_class in ["","AIR"]) then {continue};',
    ):
        assert needle in scan, needle
    # Ranked by the bomb's own class weights, then the ground's contacts, then
    # distance from the report.
    assert '(["BOMB"] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["weights",createHashMap]' in scan
    assert "((-(_x#0)) * 1e7) + ((_x#1) * 1e5) + (_x#2)" in scan
    assert "[1,0] select (_object in _wanted)" in scan


def test_the_lead_is_from_the_jets_own_fixes_and_bounded():
    aim = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_BombAim")
    assert "if (_dt >= ITW_CLASH_SupportsStrikeLeadSample) then {" in aim
    assert "private _cap = [_class] call ITW_CLASH_Knowledge_fnc_Speed;" in aim
    assert "if (_length > ITW_CLASH_SupportsStrikeLeadCap) then {" in aim
    assert "((time - (_fix#1)) max 0) + ((_along max 0) / (_groundSpeed max 1))" in aim
    # It never reads the target object: only the fixes the jet made.
    assert "velocity _veh" in aim
    assert "getPos" not in aim and "_object" not in aim


def test_only_the_bomb_acquires_and_only_outside_a_console_test():
    unguided = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    assert "private _acquire = (_flavor in ITW_CLASH_SupportsAcquireFlavors) && {!_test};" in unguided
    # The crew may watch for what it was not told about while it looks, and
    # stops when the looking is over. It never engages: the spawn's CARELESS
    # and BLUE stand.
    assert '{_x enableAI "AUTOTARGET"} forEach (units _group);' in unguided
    restore = unguided.index('if (_acquire) then {{_x disableAI "AUTOTARGET"} forEach (units _group)};')
    # Restored after the approach loop, before anything is released, on every
    # way out of the loop (lost, break-off or armed).
    assert unguided.index("while {_result isEqualTo [] && {!_armed}} do {") < restore
    assert restore < unguided.index("if (_result isNotEqualTo []) exitWith {_result};")
    assert restore < unguided.index("private _state = createHashMapFromArray [")
    assert "setCombatMode" not in unguided and "setBehaviour" not in unguided


def test_the_jet_is_re_lined_only_while_it_can_turn():
    unguided = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    # v5: in seconds of flight left before the final check, at the speed it
    # is flying (1800 m was 2 s at 200 m/s on 2026-10-17).
    assert "&& {_toCheck >= ITW_CLASH_SupportsStrikeRelineSeconds}" in unguided
    assert "private _toCheck = (_along - (_lead - _first + ITW_CLASH_SupportsStrikeCheckLead))" in unguided
    assert "if (_moved > ITW_CLASH_SupportsStrikeRelineShift) then {" in unguided
    assert '["ITW_CLASH_SupportsStrikeRelineSeconds",10]' in STRIKE
    assert "RelineMin" not in STRIKE
    # Re-lining comes after the approach line-up and before the final check.
    approach = unguided.index("_along <= ITW_CLASH_SupportsStrikeApproachUpdate")
    reline = unguided.index('["bomb-relined",')
    check = unguided.index("_along <= (_lead - _first + ITW_CLASH_SupportsStrikeCheckLead)")
    assert approach < reline < check


def test_nothing_acquired_bombs_the_report_only_if_it_is_good_enough():
    unguided = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    check = unguided[unguided.index("_along <= (_lead - _first + ITW_CLASH_SupportsStrikeCheckLead)"):]
    assert "private _usable = _alive > 0 && {_r <= ITW_CLASH_SupportsUncertaintyLimit};" in check
    assert 'if (!_usable) then {_result = ["BREAKOFF","no-target-found"]};' in check
    # The fallback reads the report without stale members: the limit holds.
    assert "([_side,_keys,0] call ITW_CLASH_Supports_fnc_TargetNow)" in check
    # The acquired path aims at the jet's own fix, led to impact.
    assert "call ITW_CLASH_SupportsStrike_fnc_BombAim) params [\"_now\",\"_shift\",\"_speed\"];" in check
    assert "_entities = [_target];" in check


def test_a_breakoff_is_refunded():
    settle = function_body(CORE, "ITW_CLASH_Supports_fnc_Settle")
    assert 'private _refund = _state in ["REVOKED","BREAKOFF"];' in settle


def test_every_new_event_is_logged_through_the_strike_log():
    for event in (
        '["bomb-scan-start",[',
        '["bomb-acquired",[',
        '["bomb-relined",[',
        '["bomb-target-lost",[',
        '["bomb-release-fix",[',
    ):
        assert event in STRIKE, event


def test_every_block_comment_closes_before_the_next_opens():
    # A lost closing marker comments out code silently; the game would load
    # the file with whole functions missing.
    for name in ("ITW_CLASH_Supports.sqf", "ITW_CLASH_SupportsStrike.sqf"):
        source = (MISSION / name).read_text(encoding="utf-8")
        depth = 0
        for marker in re.findall(r"/\*|\*/", source):
            depth += 1 if marker == "/*" else -1
            assert depth in (0, 1), name
        assert depth == 0, name
