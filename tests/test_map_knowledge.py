"""The players' map: Impasse's markers, HAL's knowledge (2026-10-17).

Hark: "can we untick HAL's [Info Markers] and leave Impasse's by default on,
but can we wire HAL's knows about to Impasse's".
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code(name):
    text = (MISSION / name).read_text(encoding="utf-8", errors="replace")
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def function_body(source, name):
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
    raise AssertionError(name)


MAP = code("ITW_CLASH_MapKnowledge.sqf")


def test_hal_info_markers_are_off_by_default():
    dual = code("ITW_CLASH_DualHALCheckbook.sqf")
    assert '["ITW_CLASH_PlayerInfoMarkers",false]' in dual
    assert "RydHQB_InfoMarkers = ITW_CLASH_PlayerInfoMarkers;" in dual


def test_impasse_draws_the_groups_the_players_commander_knows_of():
    radio = code("ITW_Radio.sqf")
    assert 'if (isNil "ITW_CLASH_MapKnownEnemyGroups") then {_playerSide knowsAbout _veh < 1} else {!(_group in ITW_CLASH_MapKnownEnemyGroups)}' in radio
    # Impasse's own switch still decides whether enemies are drawn at all.
    assert "if (!_isFriendly && {ITW_ParamShowEnemyOnMap == 0 || {" in radio
    # And its knowsAbout test survives as the fallback, nowhere else.
    assert radio.count("_playerSide knowsAbout _veh < 1") == 1


def test_the_list_is_hals_and_only_the_players_sides():
    known = function_body(MAP, "ITW_CLASH_MapKnowledge_fnc_Known")
    assert '(_hq getVariable ["RydHQ_KnEnemiesG",[]]) select {' in known
    assert "[_side] call ITW_CLASH_fnc_GetCommanderForSide" in known
    assert "((units _x) findIf {alive _x}) >= 0" in known
    assert "[ITW_PlayerSide] call ITW_CLASH_MapKnowledge_fnc_Known;" in MAP
    assert "ITW_EnemySide" not in MAP
    assert 'missionNamespace setVariable ["ITW_CLASH_MapKnownEnemyGroups",_published,true];' in MAP


def test_hals_cycle_reset_does_not_blink_the_map():
    # HAL empties RydHQ_KnEnemiesG at the start of each cycle and refills it.
    hal = (ROOT / "NR6 Hal/addons/nr6_hal/HAC_fnc2.sqf").read_text(encoding="utf-8", errors="replace")
    assert hal.index('_HQ setVariable ["RydHQ_KnEnemiesG",[]];') < hal.index('_HQ setVariable ["RydHQ_KnEnemiesG",_knownEG];')
    assert '["ITW_CLASH_MapKnowledgeEmptyHold",15]' in MAP
    assert "if (_known isEqualTo [] && {_published isNotEqualTo []}) then {" in MAP
    assert "if ((time - _emptySince) < ITW_CLASH_MapKnowledgeEmptyHold) then {" in MAP
    same = function_body(MAP, "ITW_CLASH_MapKnowledge_fnc_Same")
    assert "((_a - _b) isEqualTo []) && {(_b - _a) isEqualTo []}" in same


def test_model_empty_hold():
    def run(reads, hold=15, poll=5):
        published, empty_since, out = [], -1, []
        for i, known in enumerate(reads):
            t = i * poll
            if not known and published:
                if empty_since < 0:
                    empty_since = t
                if t - empty_since < hold:
                    known = published
            else:
                empty_since = -1
            if set(known) != set(published):
                published = list(known)
            out.append(len(published))
        return out
    # One empty read mid-cycle: the map keeps its groups.
    assert run([["a", "b"], [], ["a", "b"]]) == [2, 2, 2]
    # Really empty: cleared after the hold.
    assert run([["a"], [], [], [], [], []]) == [1, 1, 1, 1, 0, 0]


def test_it_is_loaded_on_the_server():
    init = (MISSION / "init.sqf").read_text(encoding="utf-8")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_MapKnowledge.sqf";' in init
    assert "if (!isServer) exitWith {false};" in MAP
