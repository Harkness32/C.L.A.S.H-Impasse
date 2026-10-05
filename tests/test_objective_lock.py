"""When an objective locks, stop defending it and push on.

Hark: "we need to wire HAL to ITW, when an OBJ becomes locked, we should stop
defending it and push on."

ITW_Objectives.sqf:2529 stamps ITW_FlagUnlockTime = serverTime +
ITW_ParamObjLockTime on a flag the moment a flip to a NEW owner completes, and
the capture loop then skips that flag entirely (:2433) until it expires. A
locked objective is not harder to take - its phase is not processed at all, in
either direction, by anyone.

Hark chose full release over re-anchoring before the lock lifts: "Locked
objectives are LOCKED." The objective stands empty when the window expires and
HAL's normal defence response handles it when an enemy turns up.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def read(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace")


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


def code_only(body: str) -> str:
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return re.sub(r"//[^\n]*", "", body)


# -------------------------------------------------------------- the ITW premise

def test_itw_really_does_freeze_a_locked_flag():
    """The whole justification. If ITW ever changes the lock to a slowdown
    rather than a freeze, releasing the defence stops being safe."""
    objectives = read("ITW_Objectives.sqf")
    assert '_flag setVariable ["ITW_FlagUnlockTime",serverTime + ITW_ParamObjLockTime,true];' in objectives
    assert "if (_flagUnlockTime > serverTime) then {continue};" in objectives


def test_the_lock_is_only_set_on_a_change_of_owner():
    objectives = read("ITW_Objectives.sqf")
    assert 'ITW_ParamObjLockTime > 0 && {_flag getVariable ["ITW_FlagLockOwner",false] != _flagIsPlayer}' in objectives


# ------------------------------------------------------------------ the predicate

def test_remaining_is_read_from_the_flag_itw_already_stamps():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ObjectiveLockRemaining"))
    assert "ITW_CLASH_fnc_GetObjectiveFlag" in body
    assert '_flag getVariable ["ITW_FlagUnlockTime",0]' in body
    assert "serverTime" in body


def test_every_absence_of_a_lock_reads_zero():
    """ITW clears the variable to nil on expiry and on a zone change, and the
    parameter defaults to 0, so no caller needs to special-case any of it."""
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ObjectiveLockRemaining"))
    assert "if (isNull _flag) exitWith {0}" in body
    assert "if !(_unlockAt isEqualType 0) exitWith {0}" in body
    assert "if (_remaining <= 0) exitWith {0}" in body


def test_locked_is_defined_in_terms_of_remaining():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ObjectiveLocked"))
    assert "ITW_CLASH_fnc_ObjectiveLockRemaining" in body


# ------------------------------------------------------- stop defending it

def test_the_audit_releases_and_skips_a_locked_objective():
    source = code_only(read("ITW_CLASH.sqf"))
    assert '[_objectiveIndex,"objective-locked"] call ITW_CLASH_fnc_ClearAnchorSlot' in source
    assert "anchor-released-locked" in source


def test_a_locked_objective_generates_no_refill_demand():
    """Releasing the anchor is pointless if the next poll immediately demands a
    replacement for the slot it just vacated."""
    source = code_only(read("ITW_CLASH.sqf"))
    block = source[source.index("private _lockRemaining ="):]
    block = block[:block.index("private _anchorValid")]
    assert "ITW_CLASH_AnchorRefills deleteAt _key" in block
    assert "continue" in block


def test_the_release_actually_makes_the_group_leave():
    """The RydHQ_Def* removals stop HAL COUNTING it as defence; these are what
    make it move."""
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ClearAnchorSlot"))
    block = body[body.index('if (_reason isEqualTo "objective-locked") then {'):]
    block = block[:block.index("};")]
    assert '_group setVariable ["Defending",false]' in block
    assert '_group setVariable ["Break",true]' in block
    assert "ITW_CLASH_fnc_ClearGroupWaypoints" in block


def test_the_release_still_strips_hal_s_four_defence_lists():
    """Unchanged behaviour of ClearAnchorSlot, asserted because the new reason
    depends on it."""
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ClearAnchorSlot"))
    for var in ("RydHQ_DefSpot", "RydHQ_Def", "RydHQ_DefRes", "RydHQ_RecDefSpot"):
        assert f'"{var}"' in body, var


def test_one_owner_decides_who_anchors_what():
    """The release lives in the anchor audit rather than a second poll, which
    would race it: released one tick, re-anchored the next."""
    source = read("ITW_CLASH.sqf")
    assert source.count('"objective-locked"] call ITW_CLASH_fnc_ClearAnchorSlot') == 1


# ------------------------------------------------------------------ push on

def test_colossus_stops_holding_a_locked_objective():
    """The hold gate exists because a fresh capture is vulnerable. A locked one
    is not, so the reason for the hold is absent."""
    body = code_only(function_body(
        read("ITW_CLASH_Colossus.sqf"), "ITW_CLASH_Colossus_fnc_HoldingUnanchored"
    ))
    assert "ITW_CLASH_fnc_ObjectiveLocked" in body
    assert "continue" in body


def test_colossus_degrades_if_the_predicate_is_missing():
    body = code_only(function_body(
        read("ITW_CLASH_Colossus.sqf"), "ITW_CLASH_Colossus_fnc_HoldingUnanchored"
    ))
    assert '!isNil "ITW_CLASH_fnc_ObjectiveLocked"' in body


def test_both_consumers_read_the_same_predicate():
    """Not two notions of locked."""
    assert "ITW_CLASH_fnc_ObjectiveLocked" in read("ITW_CLASH_Colossus.sqf")
    assert "ITW_CLASH_fnc_ObjectiveLockRemaining" in read("ITW_CLASH.sqf")


# ------------------------------------------------------------------- inert at 0

def test_nothing_runs_when_the_mission_has_locking_switched_off():
    """ITW_ParamObjLockTime defaults to 0, and at 0 ITW never stamps the
    variable, so the predicate reads 0 and every consumer behaves exactly as it
    did before this change. No separate enable flag to get out of sync."""
    params = (MISSION / "params.sqf").read_text(encoding="utf-8", errors="replace")
    assert "ITW_ParamObjLockTime" in params
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ObjectiveLockRemaining"))
    assert "ITW_ParamObjLockTime" not in body, (
        "read the stamped flag, not the parameter: the parameter does not say "
        "whether THIS objective is locked right now"
    )
