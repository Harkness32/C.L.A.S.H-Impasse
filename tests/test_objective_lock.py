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

def test_colossus_stops_holding_a_frozen_objective():
    """The hold gate exists because a fresh capture is vulnerable. An objective
    that cannot change hands is not, so the reason for the hold is absent."""
    body = code_only(function_body(
        read("ITW_CLASH_Colossus.sqf"), "ITW_CLASH_Colossus_fnc_HoldingUnanchored"
    ))
    assert "ITW_CLASH_fnc_ObjectiveFrozen" in body
    assert "continue" in body


def test_colossus_degrades_if_the_predicate_is_missing():
    body = code_only(function_body(
        read("ITW_CLASH_Colossus.sqf"), "ITW_CLASH_Colossus_fnc_HoldingUnanchored"
    ))
    assert '!isNil "ITW_CLASH_fnc_ObjectiveFrozen"' in body


def test_both_consumers_read_the_same_predicate():
    """One notion of frozen, covering both the capture lock and the defend
    phase, because the consequence is identical."""
    assert "ITW_CLASH_fnc_ObjectiveFrozen" in read("ITW_CLASH_Colossus.sqf")
    source = read("ITW_CLASH.sqf")
    assert "ITW_CLASH_fnc_ObjectiveFrozen" in source
    body = code_only(function_body(source, "ITW_CLASH_fnc_ObjectiveFrozen"))
    assert "ITW_CLASH_fnc_DefendPhaseObjective" in body
    assert "ITW_CLASH_fnc_ObjectiveLockRemaining" in body


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


# ------------------------------------------- the garrison goes back to the pool

def test_the_garrison_is_released_only_when_the_objective_is_locked():
    """Hark: "ONLY when the objective is locked, do we de prioritize it."

    The call sits inside the lock branch, after the lock test, so an unlocked
    objective keeps its garrison exactly as before."""
    source = code_only(read("ITW_CLASH.sqf"))
    call = source.index("ITW_CLASH_fnc_ReleaseLockedGarrison;")
    gate = source.index("private _lockRemaining = ")
    nxt = source.index("private _anchorValid", gate)
    assert gate < call < nxt, "the release must be inside the locked branch"


def test_garrison_membership_is_the_leash_being_cut():
    """HAC_fnc.sqf:1593 refuses to dispatch any RydHQ_Garrison group beyond
    _garrR, so membership in that one list IS the leash."""
    hal = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAC_fnc.sqf").read_text(
        encoding="utf-8", errors="replace"
    )
    assert "(_chosen in _garrison) and (((vehicle (leader _chosen)) distance _tPos) > _garrR)" in hal
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison"))
    assert '_hq setVariable ["RydHQ_Garrison",_garrison - _released]' in body


def test_the_garrisoned_flags_are_cleared_so_hal_does_not_re_dig_them_in():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison"))
    assert 'setVariable ["Garrisoned" + str _x,false]' in body
    assert 'setVariable ["NOGarrisoned" + str _x,false]' in body


def test_only_groups_actually_on_the_objective_are_released():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison"))
    assert "distance2D _center > _radius" in body


def test_somebody_elses_groups_are_left_alone():
    """A deliberately placed FOB SPAA, a lifecycle-reserved group and anything
    a player is in are all here on purpose, not left over."""
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison"))
    assert "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" in body
    assert 'ITW_CLASH_FOBAirDefence' in body
    assert "isPlayer _x" in body


def test_the_sweep_uses_continue_not_exitwith():
    """exitWith inside a forEach body is ambiguous about which scope it leaves,
    and getting it wrong would abandon the sweep at the first group that
    belongs to somebody else."""
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison"))
    loop = body[body.index("private _released = ["):body.index("} forEach _garrison")]
    assert "exitWith" not in loop
    assert loop.count("continue") >= 5


def test_the_release_can_be_switched_off():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison"))
    assert "if (!ITW_CLASH_LockedGarrisonRelease) exitWith {0}" in body


def test_an_empty_garrison_costs_nothing():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison"))
    assert "if (_garrison isEqualTo []) exitWith {0}" in body
    assert "if (_released isEqualTo []) exitWith {0}" in body


def test_the_release_is_logged_with_what_it_let_go():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ReleaseLockedGarrison"))
    assert "garrison-released-locked" in body


# ----------------------------------- the defend phase, which is what Hark meant

def test_the_defend_phase_is_read_from_itws_own_variable():
    """Hark: "objectives are locked during the big siege mode... it's called a
    defend phase". ITW_Objectives.sqf:2415 skips every flag but the chosen one
    for the whole of the wait AND the phase."""
    objectives = read("ITW_Objectives.sqf")
    assert "if (ITW_defendPhaseObjIdx > 0 && {ITW_defendPhaseObjIdx != _objIdx}) then {continue};" in objectives
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_DefendPhaseObjective"))
    assert 'getVariable ["ITW_defendPhaseObjIdx",-1]' in body


def test_no_defend_phase_reads_as_minus_one():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_DefendPhaseObjective"))
    assert "if (_index <= 0) exitWith {-1}" in body
    assert "if !(_index isEqualType 0) exitWith {-1}" in body


def test_the_taken_list_is_narrowed_to_the_one_on_the_table():
    """Hark: "wipe the captured objectives / taken list and list that, and only
    that, threatened objective"."""
    source = code_only(read("ITW_CLASH.sqf"))
    assert '[_taken,"taken"] call ITW_CLASH_fnc_NarrowToDefendPhase' in source
    assert '[_offered,"candidates"] call ITW_CLASH_fnc_NarrowToDefendPhase' in source


def test_the_other_commander_is_narrowed_too():
    """The freeze is a property of the map, not of a side."""
    source = code_only(read("ITW_CLASH_DualHALCheckbookHardening.sqf"))
    assert '[_taken,"blufor-taken"] call ITW_CLASH_fnc_NarrowToDefendPhase' in source
    assert '!isNil "ITW_CLASH_fnc_NarrowToDefendPhase"' in source


def test_a_defend_phase_overrides_colossus():
    """Eleven of twelve objectives cannot change hands; that is the map, not a
    preference, so it is applied after COLOSSUS has had its say."""
    source = code_only(read("ITW_CLASH.sqf"))
    colossus = source.index("ITW_CLASH_Colossus_fnc_Concentrate")
    narrow = source.index("call ITW_CLASH_fnc_NarrowToDefendPhase")
    write = source.index("RydHQ_SimpleObjs = +_offered")
    assert colossus < narrow < write


def test_narrowing_with_no_matching_mirror_changes_nothing():
    """Returning [] would tell a commander it holds nothing and is attacking
    nothing, which is worse than the status quo."""
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_NarrowToDefendPhase"))
    assert "if (_narrowed isEqualTo []) exitWith {" in body
    assert "defend-phase-no-mirror" in body
    assert "_list" in body.split("if (_narrowed isEqualTo []) exitWith {")[1][:220]


def test_the_focus_objective_itself_is_never_frozen():
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_ObjectiveFrozen"))
    assert "_objectiveIndex != _focus" in body


def test_mirrors_match_by_stamp_or_by_flag():
    """Commander B keeps private mirrors; matching only on the stamped index
    would silently never narrow B."""
    body = code_only(function_body(read("ITW_CLASH.sqf"), "ITW_CLASH_fnc_NarrowToDefendPhase"))
    assert 'getVariable ["ITW_CLASH_ObjectiveIndex",-1]' in body
    assert "_x isEqualTo _flag" in body
