"""Supports v10 and the JTAC (ITW_CLASH_SupportsJTAC.sqf v1).

2026-10-27, Hark: COLOSSUS is the supreme commander and calls supports from
the whole picture; a JTAC is a special forces team calling strikes on what it
sees itself. "A split": strike only, its own lane, one call per side every ten
minutes, separate from COLOSSUS's cooldowns.
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


CORE = code_text(raw("ITW_CLASH_Supports.sqf"))
JTAC_RAW = raw("ITW_CLASH_SupportsJTAC.sqf")
JTAC = code_text(JTAC_RAW)


def test_versions_and_boot():
    assert "ITW_CLASH_SupportsVersion = 10;" in raw("ITW_CLASH_Supports.sqf")
    assert "ITW_CLASH_SupportsJTACVersion = 1;" in JTAC_RAW
    assert "CLASH BOOT | supports-jtac-ready |" in JTAC_RAW
    # Loaded with the executors, after the core and the strike pass it flies.
    init = raw("init.sqf")
    assert init.index('"ITW_CLASH_SupportsStrike.sqf",') < init.index('"ITW_CLASH_SupportsJTAC.sqf",')
    assert 'if (isNil "ITW_CLASH_Supports_fnc_Admit") exitWith {' in JTAC


def test_strike_only_ten_minutes_shared_by_the_side():
    assert 'ITW_CLASH_SupportsJTACFlavors",["BOMB","GUIDED"]]' in JTAC
    assert 'ITW_CLASH_SupportsJTACCooldown",600]' in JTAC
    body = function_body(JTAC, "ITW_CLASH_SupportsJTAC_fnc_Assess")
    # One clock per side, read before any work and started only on admission.
    assert body.index('[_ledger,"jtac"] call ITW_CLASH_Supports_fnc_OnCooldown') < body.index("fnc_Clusters")
    admit = body.index("[_context,_pick] call ITW_CLASH_Supports_fnc_Admit")
    clock = body.index('(_ledger get "cooldowns") set ["jtac",time + ITW_CLASH_SupportsJTACCooldown];')
    assert admit < clock
    # Never anything that generates or directs forces.
    for family in ["AIRBORNE", "VEHICLE_DROP", "DropCandidates", "DirectPick", "LaunchWave"]:
        assert family not in JTAC, family


def test_its_own_lane_and_nothing_of_colossus():
    body = function_body(JTAC, "ITW_CLASH_SupportsJTAC_fnc_Assess")
    assert 'ITW_CLASH_SupportsJTACLane = "JTAC";' in JTAC
    assert '["lane",ITW_CLASH_SupportsJTACLane],["wallet","FREE"],["price",0]' in body
    # No objective: admission's per-objective cooldown is never started.
    assert '"STRIKE",_flavor,-1,"JTAC"' in body
    # A pick with its own lane neither reads nor starts the flavor cooldown,
    # and only the COMMIT lane starts the objective cooldown.
    admit = function_body(CORE, "ITW_CLASH_Supports_fnc_Admit")
    assert 'case (!_ownLane && {[_ledger,"flavor:" + _flavor] call ITW_CLASH_Supports_fnc_OnCooldown}): {_denied = "COOLDOWN"};' in admit
    assert 'if ((_pick get "objective") >= 0 && {_lane isEqualTo "COMMIT"}) then {' in admit
    # Nothing in the JTAC reads COLOSSUS's gates or cooldowns.
    assert "FlavorGate" not in JTAC
    assert '"flavor:"' not in JTAC
    assert '"objective:"' not in JTAC
    # A fresh context, so COLOSSUS's cached gates never leak in.
    assert "[_side] call ITW_CLASH_Supports_fnc_MakeContext" in body


def test_the_free_wallet_holds_and_costs_nothing():
    assert 'case "FREE": {"freeCash"};' in function_body(CORE, "ITW_CLASH_Supports_fnc_WalletKey")
    assert 'case "FREE": {0};' in function_body(CORE, "ITW_CLASH_Supports_fnc_WalletCap")
    ledger = function_body(CORE, "ITW_CLASH_Supports_fnc_Ledger")
    assert '["JTAC",""]' in ledger
    assert '["jtacSaid",""]' in ledger


def test_controllers_are_settled_special_forces_on_foot():
    body = function_body(JTAC, "ITW_CLASH_SupportsJTAC_fnc_Controllers")
    assert 'forEach (_hq getVariable ["RydHQ_SpecForG",[]]);' in body
    assert "vehicle _leader != _leader" in body
    assert '_group getVariable ["ITW_CLASH_Withdrawing",false]' in body
    assert "(time - (_settle#1)) >= ITW_CLASH_SupportsJTACSettle" in body
    # Moving off the mark starts the clock again.
    assert "((_settle#0) distance2D _position) > ITW_CLASH_SupportsJTACSettleRadius" in body


def test_sight_is_the_teams_own_and_cheapest_first():
    body = function_body(JTAC, "ITW_CLASH_SupportsJTAC_fnc_Sight")
    order = [
        "_distance > ITW_CLASH_SupportsJTACRange",
        "targetKnowledge _entity",
        "(time - _seenAt) > ITW_CLASH_SupportsJTACSightAge",
        "terrainIntersectASL",
        "lineIntersectsSurfaces",
    ]
    positions = [body.index(step) for step in order]
    assert positions == sorted(positions)
    # The team's own men, never the commander's or another group's report.
    assert "forEach (units _group);" in body
    assert "ReadReport" not in JTAC
    assert "RydHQ_KnEnemies" not in JTAC
    # A revealed, never-seen target (lastSeen off the clock) is not a sighting.
    assert "_lastSeen >= 0" in body
    # The line goes to where the team saw it, not where it really is.
    assert "AGLToASL [_seenPos#0,_seenPos#1,1.5]" in body
    assert "getPos _entity" not in body and "getPosATL _entity" not in body


def test_the_pipelines_own_gates():
    body = function_body(JTAC, "ITW_CLASH_SupportsJTAC_fnc_Option")
    for gate in ['"DISABLED"', '"NO_CONTACT"', '"BELOW_FLOOR"', '"ETB_ANSWERING"', '"DANGER_CLOSE"', '"AIR_DENIED"']:
        assert gate in body, gate
    # The floor is an exclusion, never lowered for a JTAC.
    assert "(_cluster get \"worth\") < ITW_CLASH_SupportsValueFloorAcquire" in body
    assert "ITW_CLASH_Supports_fnc_DangerClose" in body
    assert "ITW_CLASH_Supports_fnc_PickClass" in body


STRIKE = code_text(raw("ITW_CLASH_SupportsStrike.sqf"))


def test_a_jtac_call_has_one_150_m_margin_at_every_check():
    assert "ITW_CLASH_SupportsStrikeVersion = 7;" in raw("ITW_CLASH_SupportsStrike.sqf")
    assert 'ITW_CLASH_SupportsDangerMarginJTAC",150]' in CORE
    margin = function_body(CORE, "ITW_CLASH_Supports_fnc_DangerMargin")
    # Ahead of the flavor and player margins: any flavor, any friendly.
    assert margin.index("if (_jtac) exitWith {ITW_CLASH_SupportsDangerMarginJTAC};") < margin.index('"GUIDED"')
    for helper in ["ITW_CLASH_Supports_fnc_DangerClose", "ITW_CLASH_Supports_fnc_DangerWhy"]:
        body = function_body(CORE, helper)
        assert '["_jtac",false]' in body
        assert "[_flavor,_player,_jtac] call ITW_CLASH_Supports_fnc_DangerMargin" in body
    # The JTAC's own gate and the pre-run check ask with the JTAC's margin.
    assert "[_context get \"friendlies\",_aim,_footprint,_flavor,true] call ITW_CLASH_Supports_fnc_DangerClose" in JTAC
    prerun = function_body(CORE, "ITW_CLASH_Supports_fnc_PreRun")
    assert 'private _jtac = !isNull (_support getOrDefault ["controller",grpNull]);' in prerun
    assert '_support get "flavor",_jtac] call ITW_CLASH_Supports_fnc_DangerClose' in prerun
    # So does every check in the executor, or the jet would break off at the
    # flavor's margin after the call was made at the JTAC's.
    for name in ["ITW_CLASH_SupportsStrike_fnc_UnguidedPass", "ITW_CLASH_SupportsStrike_fnc_GuidedPass",
                 "ITW_CLASH_SupportsStrike_fnc_BombScan"]:
        body = function_body(STRIKE, name)
        checks = body.count("call ITW_CLASH_Supports_fnc_DangerClose")
        assert checks > 0, name
        assert body.count("_jtac] call ITW_CLASH_Supports_fnc_DangerClose") == checks, name
    # COLOSSUS's own picks use the flavor margins.
    strike_candidates = function_body(CORE, "ITW_CLASH_Supports_fnc_StrikeCandidates")
    assert "_jtac" not in strike_candidates


def jtac_margin(flavor, player, jtac, margins=None):
    """fnc_DangerMargin."""
    m = margins or {"jtac": 150, "precision": 150, "default": 300, "player": 500}
    if jtac:
        return m["jtac"]
    if flavor in ("BOMB", "GUIDED"):
        return m["precision"]
    return m["player"] if player else m["default"]


def test_margin_model():
    # A bomb on a JTAC call may land 200 m from a player (50 m footprint + 150).
    assert 50 + jtac_margin("BOMB", True, True) == 200
    # COLOSSUS's bomb and guided passes share 150 m too (supports v10)...
    assert 50 + jtac_margin("BOMB", True, False) == 200
    assert jtac_margin("GUIDED", False, False) == 150
    # ...and only its carpet keeps the wide line.
    assert 60 + jtac_margin("CARPET", True, False) == 560


def test_it_never_assigns_a_target():
    for verb in ["doTarget", "doFire", "commandTarget", "fireAtTarget", "setMissileTarget", "doWatch", "reveal"]:
        assert not re.search(rf"\b{verb}\b", JTAC), verb


def test_eyes_are_rechecked_before_the_jet_spawns():
    admit = function_body(CORE, "ITW_CLASH_Supports_fnc_Admit")
    assert '["controller",_pick getOrDefault ["controller",grpNull]]' in admit
    prerun = function_body(CORE, "ITW_CLASH_Supports_fnc_PreRun")
    assert "[_support] call ITW_CLASH_SupportsJTAC_fnc_StillSees" in prerun
    assert '_support set ["denied","NO_SIGHT"]' in prerun
    assert '"NO_SIGHT"' in CORE[CORE.index("ITW_CLASH_SupportsDenials = ["):]
    still = function_body(JTAC, "ITW_CLASH_SupportsJTAC_fnc_StillSees")
    assert "ITW_CLASH_SupportsJTAC_fnc_Sight" in still


SIGHT_ORDER = ["out-of-range", "not-seen", "no-los"]


def nearest_refusal(reasons):
    """fnc_Eyes: the closest any team came to seeing the cluster."""
    return SIGHT_ORDER[max(SIGHT_ORDER.index(r) for r in reasons)]


def test_a_refused_cluster_reports_how_close_a_team_came():
    assert 'ITW_CLASH_SupportsJTACSightOrder = ["out-of-range","not-seen","no-los"];' in JTAC
    assert nearest_refusal(["out-of-range", "no-los", "not-seen"]) == "no-los"
    assert nearest_refusal(["out-of-range"]) == "out-of-range"


def best_option(options):
    """fnc_Assess: the best option wins outright on class weight x worth x corridor."""
    best, best_weight = None, 0
    for name, base, worth, corridor in options:
        weight = base * worth * corridor
        if weight > best_weight:
            best, best_weight = name, weight
    return best


def test_a_battery_beats_a_truck():
    body = function_body(JTAC, "ITW_CLASH_SupportsJTAC_fnc_Option")
    assert '_base * (_cluster get "worth") * ([_corridor] call ITW_CLASH_Supports_fnc_CorridorFactor)' in body
    # Bomb on two parked guns (worth 3) against bomb on one parked truck (1.5).
    assert best_option([("truck", 3, 1.5, 1), ("battery", 3, 3, 1)]) == "battery"
    # A hot corridor halves it: two parked trucks on a cold run beat it.
    assert best_option([("battery-hot", 3, 3, 0.5), ("trucks", 3, 2, 1)]) == "trucks"
