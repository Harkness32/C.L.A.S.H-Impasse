"""COLOSSUS v6: a push is for ground the commander does not hold.

Run of 2026-10-15 23:27: commander B held objectives 8 and 14 and planned to
push its own objective 8 (EMPTY, enemy 0) in all 16 assessments, because the
recommendation ranked every active objective by known enemy and held ground
with nobody near it scores lowest. Its supports pool had no TAKE target for
the whole run. These pins keep held ground out of the push and keep one
ownership rule for COLOSSUS and the supports layer.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def code_only(source: str) -> str:
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


def colossus() -> str:
    return code_only(text("ITW_CLASH_Colossus.sqf"))


def test_the_picture_records_ownership_from_one_predicate():
    source = colossus()
    held = function_body(source, "ITW_CLASH_Colossus_fnc_HeldBy")
    assert "[_index] call ITW_ObjContestedOwnerIsFriendly" in held
    assert "if (_side isEqualTo ITW_PlayerSide) exitWith {_friendlyOwns};" in held
    picture = function_body(source, "ITW_CLASH_Colossus_fnc_Picture")
    assert '["held",[side _hq,_index] call ITW_CLASH_Colossus_fnc_HeldBy]' in picture


def test_the_push_ranks_only_ground_the_enemy_holds():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_Recommend")
    push = body[body.index('_candidates = _picture select'):]
    assert '_candidates = _picture select {!(_x getOrDefault ["held",false])};' in push
    assert "private _ranked = [_candidates,[],{" in push
    # The CONSOLIDATE branch still rallies on the whole picture: held ground is
    # exactly where it should mass.
    consolidate = body[:body.index('_candidates = _picture select')]
    assert "[_picture] call ITW_CLASH_Colossus_fnc_RallyPoint" in consolidate


def test_holding_everything_plans_no_push_and_defends():
    source = colossus()
    body = function_body(source, "ITW_CLASH_Colossus_fnc_Recommend")
    assert "if (_candidates isEqualTo []) exitWith {" in body
    empty = body[body.index("if (_candidates isEqualTo []) exitWith {"):body.index("private _ranked = [_candidates")]
    assert '"no-push-candidate"' in empty
    assert '["objective",-1]' in empty
    assert '["feasible",false]' in empty
    # Not feasible under PUSH is DEFEND, through the existing order rule.
    order = function_body(source, "ITW_CLASH_Colossus_fnc_OrderFor")
    assert 'if (_plan getOrDefault ["feasible",false]) exitWith {"ATTACK"};' in order
    assert '"DEFEND"' in order


def test_concentration_names_the_empty_plan():
    body = function_body(colossus(), "ITW_CLASH_Colossus_fnc_Concentrate")
    assert 'if ((_plan getOrDefault ["objective",-1]) < 0) exitWith {["no-push-candidate"] call _decline};' in body
    assert body.index('"no-push-candidate"') < body.index("ITW_CLASH_Colossus_fnc_ResolveMirror")


def test_supports_use_the_same_ownership_rule():
    supports = code_only(text("ITW_CLASH_Supports.sqf"))
    held = function_body(supports, "ITW_CLASH_Supports_fnc_HeldBy")
    assert 'if (!isNil "ITW_CLASH_Colossus_fnc_HeldBy") exitWith {' in held
    assert "[_side,_index] call ITW_CLASH_Colossus_fnc_HeldBy" in held


def test_boot_line_and_version():
    raw = text("ITW_CLASH_Colossus.sqf")
    assert "ITW_CLASH_ColossusVersion = 6;" in raw
    assert "pushSkipsHeld=true" in raw


# --------------------------------------------------------- the 10-15 picture


def rank(picture, reported_positions=False, penalty=500):
    """Python mirror of fnc_Recommend's PUSH branch, v6."""
    candidates = [p for p in picture if not p.get("held", False)]
    if not candidates:
        return None

    def score(p):
        s = p["enemy"]
        if not p["sufficient"]:
            s += 1000
        if reported_positions and p.get("intel") == "UNOBSERVED":
            s += penalty
        return s

    return sorted(candidates, key=score)[0]["objective"]


def test_commander_b_no_longer_pushes_its_own_objective():
    # B's picture at 23:39 in the 10-15 run: it held 8 and 14, A held 23 and 28.
    picture = [
        {"objective": 8, "enemy": 0, "sufficient": True, "held": True},
        {"objective": 14, "enemy": 0, "sufficient": True, "held": True},
        {"objective": 23, "enemy": 1, "sufficient": True, "held": False},
        {"objective": 28, "enemy": 0, "sufficient": True, "held": False},
    ]
    v5 = sorted(picture, key=lambda p: p["enemy"] + (0 if p["sufficient"] else 1000))[0]["objective"]
    assert v5 == 8
    assert rank(picture) in (23, 28)


def test_holding_every_objective_yields_no_push():
    picture = [
        {"objective": 8, "enemy": 0, "sufficient": True, "held": True},
        {"objective": 14, "enemy": 3, "sufficient": False, "held": True},
    ]
    assert rank(picture) is None
