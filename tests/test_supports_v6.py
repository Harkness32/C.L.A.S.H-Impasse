"""Supports v6, UAV v4 and knowledge v6, from the second 2026-10-17 run.

See docs/CLASH_CommanderSupports_Model.md.

- Money stopped being the gate; targets did. The two clusters that came up
  near a plan objective were both DANGER_CLOSE. The guided missile, one
  precision round, gets a 100 m margin past its footprint (200 m from a
  player) instead of 300 and 500; bombs and carpet keep theirs. Every
  DANGER_CLOSE logs the friendly that caused it.
- The recon UAV saw 0 to 2 contacts through the engine's sensors in all 12
  sorties at 2000 m. It now reveals every enemy in its footprint that no
  building covers (Hark: "why don't we just reveal all targets below the UAV
  that aren't inside?"), reports them to the knowledge layer as a UAV
  sighting, and points its camera at the station.
"""

import math
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


# ------------------------------------------------------ guided danger margin


def margin(flavor: str, player: bool) -> int:
    if flavor == "GUIDED":
        return 200 if player else 100
    return 500 if player else 300


def test_versions():
    assert "ITW_CLASH_SupportsVersion = 9;" in raw("ITW_CLASH_Supports.sqf")
    assert "ITW_CLASH_SupportsUAVVersion = 4;" in raw("ITW_CLASH_SupportsUAV.sqf")
    assert "ITW_CLASH_KnowledgeVersion = 6;" in raw("ITW_CLASH_Knowledge.sqf")


def test_guided_margins_are_tighter_and_bombs_keep_theirs():
    source = raw("ITW_CLASH_Supports.sqf")
    assert 'ITW_CLASH_SupportsDangerMarginGuided",100]' in source
    assert 'ITW_CLASH_SupportsDangerMarginGuidedPlayer",200]' in source
    assert 'ITW_CLASH_SupportsDangerMargin",300]' in source
    assert 'ITW_CLASH_SupportsDangerMarginPlayer",500]' in source
    body = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_DangerMargin")
    assert 'if (_flavor isEqualTo "GUIDED") exitWith {' in body
    assert ("if (_player) then {ITW_CLASH_SupportsDangerMarginGuidedPlayer} "
            "else {ITW_CLASH_SupportsDangerMarginGuided}") in body
    assert ("if (_player) then {ITW_CLASH_SupportsDangerMarginPlayer} "
            "else {ITW_CLASH_SupportsDangerMargin}") in body


def test_danger_close_takes_the_flavor_and_defaults_to_the_wide_line():
    body = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_DangerClose")
    assert 'params ["_friendlies","_aim","_footprint",["_flavor",""]];' in body
    assert "(_footprint + ([_flavor,_player] call ITW_CLASH_Supports_fnc_DangerMargin))" in body
    # Footprint 50 for both: the lines a friendly must stay outside.
    assert 50 + margin("GUIDED", False) == 150 and 50 + margin("GUIDED", True) == 250
    assert 50 + margin("BOMB", False) == 350 and 50 + margin("BOMB", True) == 550
    assert 50 + margin("", False) == 350


def test_every_guided_check_passes_its_flavor_and_bombs_pass_none():
    core = code("ITW_CLASH_Supports.sqf")
    assert "[_context get \"friendlies\",_aim,_footprint,_flavor] call ITW_CLASH_Supports_fnc_DangerClose" in core
    assert "[_friendlies,_aim,_footprint,_support get \"flavor\"] call ITW_CLASH_Supports_fnc_DangerClose" in core
    strike = code("ITW_CLASH_SupportsStrike.sqf")
    assert '{!([_friendlies,getPosATL _x,_footprint,"GUIDED"] call ITW_CLASH_Supports_fnc_DangerClose)}' in strike
    # The bomb pass's own checks are unchanged: no flavor, the wide line.
    bomb_calls = re.findall(r"\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\] call ITW_CLASH_Supports_fnc_DangerClose", strike)
    assert len(bomb_calls) == 5
    assert sum('"GUIDED"' in call for call in bomb_calls) == 1


def danger_why(friendlies, aim, footprint, flavor):
    worst, depth_worst = [], 0
    for (x, y), player in friendlies:
        line = footprint + margin(flavor, player)
        distance = math.dist((x, y), aim)
        depth = line - distance
        if depth >= 0 and (not worst or depth > depth_worst):
            worst, depth_worst = [round(distance), player, line], depth
    return worst


def test_danger_why_names_the_friendly_deepest_inside_its_line():
    body = function_body(code("ITW_CLASH_Supports.sqf"), "ITW_CLASH_Supports_fnc_DangerWhy")
    assert "private _line = _footprint + ([_flavor,_player] call ITW_CLASH_Supports_fnc_DangerMargin);" in body
    assert "if (_depth >= 0 && {_worst isEqualTo [] || {_depth > _worstDepth}}) then {" in body
    assert "_worst = [round _distance,_player,round _line];" in body
    # The player 400 m away is deeper inside his 550 m line than an AI 300 m
    # away is inside its 350 m line; the guided line lets both through.
    friendlies = [((400, 0), True), ((0, 300), False)]
    assert danger_why(friendlies, (0, 0), 50, "BOMB") == [400, True, 550]
    assert danger_why(friendlies, (0, 0), 50, "GUIDED") == []
    assert danger_why([((0, 120), False)], (0, 0), 50, "GUIDED") == [120, False, 150]


def test_both_danger_close_denials_are_logged_with_the_friendly():
    core = code("ITW_CLASH_Supports.sqf")
    assess = core[core.index('["danger-close",[\n                    _context get "sign"'):]
    assert '_context get "sign",_flavor,_targetKey,"assess",' in assess
    assert assess.index("ITW_CLASH_Supports_fnc_DangerWhy") < assess.index('"DANGER_CLOSE"] call ITW_CLASH_Supports_fnc_Exclude;')
    prerun = function_body(core, "ITW_CLASH_Supports_fnc_PreRun")
    assert '_support get "sign",_support get "flavor",_support get "id","pre-run",' in prerun
    assert prerun.index('"danger-close"') < prerun.index('_support set ["denied","DANGER_CLOSE"]')
    # The denial vocabulary itself is unchanged.
    assert '"DANGER_CLOSE"' in raw("ITW_CLASH_Supports.sqf")


def test_supports_boot_line_reports_the_guided_margins():
    source = raw("ITW_CLASH_Supports.sqf")
    assert "danger=%15/%16 dangerGuided=%33/%34 dangerLogged=true" in source
    tail = source[source.index("CLASH BOOT | supports-ready"):]
    assert "ITW_CLASH_SupportsDangerMarginGuided,\n    ITW_CLASH_SupportsDangerMarginGuidedPlayer," in tail


# --------------------------------------------------------- UAV footprint


def test_uav_footprint_tunables_and_geometry():
    source = raw("ITW_CLASH_SupportsUAV.sqf")
    for tunable in ['ITW_CLASH_SupportsUAVFootprint",1200]', 'ITW_CLASH_SupportsUAVCoverRay",40]',
                    'ITW_CLASH_SupportsUAVCoverAny",false]', 'ITW_CLASH_SupportsUAVReportError",10]',
                    'ITW_CLASH_SupportsUAVFootprintCap",80]', 'ITW_CLASH_SupportsUAVCameraLock",true]']:
        assert tunable in source, tunable
    # The header's 70 degrees: the station centre from a 700 m ring at 2000 m.
    assert 70 <= math.degrees(math.atan2(2000, 700)) < 71
    assert "the objective sits 70 degrees below the horizon" in source
    # The footprint keeps the station's centre in view all the way round.
    assert 700 < 1200


def test_cover_is_a_roof_unless_cover_any():
    body = function_body(code("ITW_CLASH_SupportsUAV.sqf"), "ITW_CLASH_SupportsUAV_fnc_Covered")
    assert "private _from = aimPos _object;" in body
    assert "private _to = _from vectorAdd [0,0,ITW_CLASH_SupportsUAVCoverRay];" in body
    assert 'lineIntersectsSurfaces [_from,_to,_object,vehicle _object,true,3,"GEOM","NONE"]' in body
    assert "if (ITW_CLASH_SupportsUAVCoverAny) exitWith {_hits isNotEqualTo []};" in body
    assert 'private _thing = if (isNull (_x#3)) then {_x#2} else {_x#3};' in body
    assert '!isNull _thing && {_thing isKindOf "Building"}' in body


def test_footprint_is_enemies_under_the_uav_that_nothing_covers():
    body = function_body(code("ITW_CLASH_SupportsUAV.sqf"), "ITW_CLASH_SupportsUAV_fnc_Footprint")
    assert "_under set [2,0];" in body
    assert ('(_under nearEntities [["CAManBase","LandVehicle","StaticWeapon","Ship"],'
            'ITW_CLASH_SupportsUAVFootprint])') in body
    # Empty vehicles are nobody's; only the enemy's count.
    assert ('private _crew = if (_object isKindOf "CAManBase") then {[_object]} '
            'else {(crew _object) select {alive _x}};') in body
    assert "if (_crew isEqualTo []) then {continue};" in body
    assert "if !([_side,side group (_crew#0)] call BIS_fnc_sideIsEnemy) then {continue};" in body
    assert body.index("fnc_Covered") < body.index("_found pushBack _object;")
    # A ridge between the UAV and the target hides it too.
    assert "private _eye = getPosASL _veh;" in body
    # A metre up from the aim point, so a prone man on a slope is not masked by the slope he lies on.
    assert "if (terrainIntersectASL [_eye,(aimPos _object) vectorAdd [0,0,1]] || {[_object] call ITW_CLASH_SupportsUAV_fnc_Covered}) then {" in body
    assert "if ((count _found) >= ITW_CLASH_SupportsUAVFootprintCap) then {break};" in body
    assert "[_found,_covered]" in body


def test_footprint_reaches_hal_and_the_knowledge_layer():
    uav = code("ITW_CLASH_SupportsUAV.sqf")
    sweep = function_body(uav, "ITW_CLASH_SupportsUAV_fnc_Sweep")
    assert "([_veh,_side] call ITW_CLASH_SupportsUAV_fnc_Footprint) params [\"_footprint\",\"_covered\"];" in sweep
    assert "{_ground pushBackUnique _x} forEach _footprint;" in sweep
    assert sweep.index("_ground pushBackUnique _x} forEach _footprint") < sweep.index("_hq reveal [_x,ITW_CLASH_SupportsUAVRevealLevel]")
    assert "[_side,_footprint,_by] call ITW_CLASH_SupportsUAV_fnc_Report;" in sweep
    assert "[count _ground,count _footprint,_covered]" in sweep
    report = function_body(uav, "ITW_CLASH_SupportsUAV_fnc_Report")
    assert 'isNil "ITW_CLASH_KnowledgeUAVSightings"' in report
    assert "_x,[_position#0,_position#1,0],_now,ITW_CLASH_SupportsUAVReportError,_by" in report
    run = function_body(uav, "ITW_CLASH_SupportsUAV_fnc_Run")
    assert '([_veh,_hq,_side,_id] call ITW_CLASH_SupportsUAV_fnc_Sweep) params ["_all","_foot","_cover"];' in run
    assert "_looks,_peak,_retasks,_footPeak,_coverPeak,_reported" in run


def test_camera_points_at_the_station_unless_a_player_has_it():
    uav = code("ITW_CLASH_SupportsUAV.sqf")
    body = function_body(uav, "ITW_CLASH_SupportsUAV_fnc_PointCamera")
    assert "if (((UAVControl _veh) findIf {_x isEqualType objNull && {!isNull _x} && {isPlayer _x}}) >= 0) exitWith {false};" in body
    assert "private _turret = (allTurrets [_veh,false]) param [0,[]];" in body
    assert "_veh lockCameraTo [[_station#0,_station#1,(getTerrainHeightASL [_station#0,_station#1]) + 2],_turret];" in body
    run = function_body(uav, "ITW_CLASH_SupportsUAV_fnc_Run")
    assert run.index("[_veh,_station] call ITW_CLASH_SupportsUAV_fnc_PointCamera;") < run.index("call ITW_CLASH_SupportsUAV_fnc_Sweep")


def test_uav_boot_line():
    source = raw("ITW_CLASH_SupportsUAV.sqf")
    assert ("footprint=%11m coverRay=%12m coverAny=%13 reportError=%14m footprintCap=%15 "
            "cameraLock=%16 footprintReports=true") in source
    tail = source[source.index("CLASH BOOT | supports-uav-ready"):]
    assert tail.count("%") == 16


# --------------------------------------------------- knowledge v6 ingestion


def test_knowledge_reads_uav_sightings_as_one_more_report():
    source = code("ITW_CLASH_Knowledge.sqf")
    assert 'if (isNil "ITW_CLASH_KnowledgeUAVSightings") then {ITW_CLASH_KnowledgeUAVSightings = createHashMap};' in source
    update = function_body(source, "ITW_CLASH_Knowledge_fnc_Update")
    # Candidates, with stale and dead entries dropped where they are read.
    assert "private _uavSightings = ITW_CLASH_KnowledgeUAVSightings getOrDefault [_key,createHashMap,true];" in update
    assert ("if (isNull _entity || {!alive _entity} || {(_now - _at) > ITW_CLASH_KnowledgeForgetAfter}) then {\n"
            "            _uavSightings deleteAt _x;") in update
    assert "} forEach (+_uavSightings);" in update
    # The same rule as any observer: error plus speed times age, smallest wins.
    assert "private _r = _lookError + _speed * ((_now - _lookAt) max 0);" in update
    assert "if (_r < _bestR) then {" in update
    assert '_bestBy = "uav:" + _lookBy;' in update
    assert update.index("} forEach _observers;") < update.index("private _look = _uavSightings")
    assert update.index("private _look = _uavSightings") < update.index("if (_best isEqualTo []) then {continue};")
    # The record names who saw it.
    assert update.count('["moving",false],\n                ["observer",_observerName]') == 1
    assert update.count('_record set ["observer",_observerName];') == 1
    assert "[_bestObserver] call ITW_CLASH_Knowledge_fnc_GroupId" in update


def test_knowledge_key_is_computed_once_before_the_reports():
    update = function_body(code("ITW_CLASH_Knowledge.sqf"), "ITW_CLASH_Knowledge_fnc_Update")
    assert update.count("private _contactKey = [_target] call ITW_CLASH_Knowledge_fnc_ContactKey;") == 1
    assert update.index("private _contactKey = [_target]") < update.index("} forEach _observers;")


def test_knowledge_boot_line_says_it_takes_uav_reports():
    assert "groupmateSightings=true uavFootprintReports=true hqObserver=false" in raw("ITW_CLASH_Knowledge.sqf")
