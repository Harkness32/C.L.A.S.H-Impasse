"""
2026-10-17, run 4 (Hark): "the tanks spawning at a rear base and the cram not
being in that same rear base is weird", then "should we just move airspawns to
the same rear base?" / "A for sure", and "we should stop reserving backline aa
vehicles since we got the CRAM fix built, if hal wants aa he should make that
move now".

  1. REAR_AIR walks the land chain, so aircraft and armour share a rear base.
  2. Resolve keeps a ledger of where the rear echelon actually spawned, written
     only by callers that put something there.
  3. The C-RAM stands at the newest of those, and an old one is stood down once
     nothing has spawned at its base for a while.
  4. The SPAA overwatch is gone: HAL employs every SPAA as its own armour.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def code(name: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", text(name), flags=re.S)
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


GEN = "ITW_CLASH_ForceGeneration.sqf"
CRAM = "ITW_CLASH_RearBaseCRAM.sqf"


# ------------------------------------------------- 1. one rear base for both

def test_rear_air_walks_the_land_chain():
    body = function_body(code(GEN), "ITW_CLASH_Generation_fnc_Resolve")
    assert 'private _slot = if (_profileKey isEqualTo "FORWARD_AIR") then {' in body
    slot = body[body.index("private _slot = "):body.index("private _objectiveIds")]
    assert slot.index("ITW_ATTACK_AIR_F") < slot.index("ITW_ATTACK_LAND_F")
    # The aircraft still spawns at the base's own vehicle point.
    assert 'private _air = _profileKey in ["FORWARD_AIR","REAR_AIR"];' in body
    assert "[_rearBase,_air] call ITW_CLASH_Generation_fnc_BaseSpawn" in body


def test_forward_air_lifts_keep_the_air_chain():
    # CASEVAC and transport lifts launch from the nearest base in the air.
    assert '"CASEVAC","FORWARD_AIR"' in code("ITW_CLASH_CASEVAC.sqf")
    body = function_body(code(GEN), "ITW_CLASH_Generation_fnc_Resolve")
    assert "ITW_ATTACK_AIR_E" in body


# ------------------------------------------------------- 2. the spawn ledger

def test_the_ledger_is_written_only_for_a_spawning_rear_answer():
    source = code(GEN)
    body = function_body(source, "ITW_CLASH_Generation_fnc_Resolve")
    assert '["_reference",[]],["_spawning",false]];' in body
    assert 'if (_spawning && {_profileKey in ["REAR","REAR_AIR"]}) then {' in body
    assert "[_side,_rearBase] call ITW_CLASH_Generation_fnc_NoteRearUse;" in body
    # Written once the answer is known to be usable, never for a failure.
    assert body.index("deployment-position-unavailable") < body.index("NoteRearUse")
    assert 'if (isNil "ITW_CLASH_GenerationRearUse") then {ITW_CLASH_GenerationRearUse = createHashMap};' in source
    uses = function_body(source, "ITW_CLASH_Generation_fnc_RearUses")
    assert '"DESCEND"] call BIS_fnc_sortBy' in uses


def test_every_caller_that_puts_something_at_the_rear_says_so():
    gen = code(GEN)
    assert "_side,_capability,_profile,_reference,true\n    ] call ITW_CLASH_Generation_fnc_Resolve;" in function_body(gen, "ITW_CLASH_Generation_fnc_Provider")
    assert "_side,_capability,_profile,_reference,true" in code("ITW_CLASH_ServiceStability.sqf")
    field = function_body(code("ITW_CLASH_DualHALCheckbook.sqf"), "ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn")
    assert 'if (_air) then {"REAR_AIR"} else {"REAR"},\n            getPosATL _veh,\n            true' in field
    assert '"LOGISTICS_PACKAGE_AMMO","REAR_AIR",_reference,true' in code("ITW_CLASH_PlayerTaskSupport.sqf")


def test_callers_that_only_ask_do_not():
    # A question is not a spawn: these must never make a base look used.
    assert '[_side,"TRANSPORT",_x,[]] call ITW_CLASH_Generation_fnc_Resolve' in code("ITW_CLASH_FOBGarrisonSweep.sqf")
    assert '[_side,"SUPPORT_AIR","REAR_AIR",_aim] call ITW_CLASH_Generation_fnc_Resolve' in code("ITW_CLASH_Supports.sqf")
    assert '_side,"ANTI_ARMOR_CAS","REAR_AIR",getPosATL _threat\n            ] call' in code("ITW_CLASH_HALThreatCoverage.sqf")
    current = function_body(code(CRAM), "ITW_CLASH_RearBaseCRAM_fnc_CurrentBase")
    assert "ITW_CLASH_Generation_fnc_Resolve" not in current
    # 2026-10-28: an ETB purchase is a one-off, not the rear echelon.
    etb = function_body(code(GEN), "ITW_CLASH_Generation_fnc_ETBSpawnPoint")
    assert '_side,_capability,"REAR",_reference\n    ] call ITW_CLASH_Generation_fnc_Resolve;' in etb
    assert "NoteRearUse" not in etb


def test_an_etb_asset_stages_where_the_rear_echelon_last_spawned():
    # Hark, 2026-10-28: "its just weird having the mass majority of our force
    # gen at the rear and then boom, etb jumps to the front".
    etb = function_body(code(GEN), "ITW_CLASH_Generation_fnc_ETBSpawnPoint")
    uses = etb.index("[_side] call ITW_CLASH_Generation_fnc_RearUses;")
    base = etb.index("[(_uses#0)#0,false] call ITW_CLASH_Generation_fnc_BaseSpawn")
    staged = etb.index('if (_rear isNotEqualTo []) exitWith {["rear-base","",_rear]};')
    threat = etb.index("ITW_CLASH_Generation_fnc_Resolve")
    assert uses < base < staged < threat
    # A plane still needs an owned airport, ahead of all of it.
    assert etb.index("AIRPORT_REQUIRED") < uses
    assert "ITW_CLASH_ForceGenerationVersion = 4;" in code(GEN)
    assert "etbSpawn=current-rear-fob" in code(GEN)


# ------------------------------------------------- 3. the C-RAM follows it

def test_the_current_rear_base_is_where_the_rear_echelon_last_spawned():
    body = function_body(code(CRAM), "ITW_CLASH_RearBaseCRAM_fnc_CurrentBase")
    assert "ITW_CLASH_Generation_fnc_RearUses" in body
    # v7 (2026-10-27, "CRAM's are spawning in inactive bases"): no guess
    # before the first spawn. The graph's unreferenced answer put BLUFOR's
    # first piece at base 3 while its rear echelon only ever used base 0.
    assert "if (_uses isEqualTo []) exitWith {-1};" in body
    assert "(_uses#0)#0" in body
    follow = function_body(code(CRAM), "ITW_CLASH_RearBaseCRAM_fnc_Follow")
    assert "if (_current < 0 || {_current in _placed}) exitWith {false};" in follow


def test_an_old_base_stays_in_use_until_idle():
    source = code(CRAM)
    body = function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_InUse")
    assert "if (_base isEqualTo _current) exitWith {true};" in body
    assert "ITW_CLASH_RearBaseCRAMIdle" in body
    # The piece going up counts as a use, so a fresh one is not stood down on
    # the next poll before anything has had the chance to spawn.
    assert "(_entry param [5,-1])" in body
    assert 'ITW_CLASH_RearBaseCRAMIdle",600' in source


def test_follow_keeps_up_what_is_in_use_and_stands_down_the_rest():
    body = function_body(code(CRAM), "ITW_CLASH_RearBaseCRAM_fnc_Follow")
    walk = body[body.index("{"):body.index("} forEach (keys _placed);")]
    assert "ITW_CLASH_RearBaseCRAM_fnc_InUse" in walk
    assert walk.index("ITW_CLASH_RearBaseCRAM_fnc_Maintain") < walk.index("ITW_CLASH_RearBaseCRAM_fnc_StandDown")
    # Then one goes up at the current base, if none stands there.
    tail = body[body.index("} forEach (keys _placed);"):]
    assert "if (_current < 0 || {_current in _placed}) exitWith {false};" in tail
    assert "[_side,_current] call ITW_CLASH_RearBaseCRAM_fnc_Spawn" in tail
    assert '"followed"' in tail


def test_there_is_a_ceiling_per_side_and_hitting_it_is_said_once():
    source = code(CRAM)
    assert 'ITW_CLASH_RearBaseCRAMMaxPerSide",2' in source
    body = function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_Follow")
    assert "(count _placed) >= ITW_CLASH_RearBaseCRAMMaxPerSide" in body
    assert '"at-capacity"' in body
    assert "ITW_CLASH_RearBaseCRAMFullAt" in body


def test_a_stand_down_never_happens_in_front_of_a_player():
    source = code(CRAM)
    body = function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_StandDown")
    assert "allPlayers findIf" in body
    assert "ITW_CLASH_RearBaseCRAMStandDownClear" in body
    assert body.index("allPlayers findIf") < body.index("deleteVehicle _veh")
    assert '"stand-down-waits"' in body and '"stood-down"' in body
    # Crew, hull and group all go, and nothing a player is in.
    assert "(crew _veh) select {!isPlayer _x}" in body
    assert "deleteGroup _group" in body
    assert "_placed deleteAt _base" in body
    assert 'ITW_CLASH_RearBaseCRAMStandDownClear",300' in source


def test_it_is_placed_in_the_base_it_follows():
    body = function_body(code(CRAM), "ITW_CLASH_RearBaseCRAM_fnc_RearPosition")
    assert "[_base,false] call ITW_CLASH_Generation_fnc_BaseSpawn" in body
    spawn = function_body(code(CRAM), "ITW_CLASH_RearBaseCRAM_fnc_Spawn")
    assert 'params ["_side","_base",["_position",[]]];' in spawn
    assert "[_base] call ITW_CLASH_RearBaseCRAM_fnc_RearPosition" in spawn


def test_boot_line_and_loud_debug_name_the_new_behaviour():
    raw = text(CRAM)
    assert "ITW_CLASH_RearBaseCRAMVersion = 7;" in raw
    assert "followsRearBase=spawn-ledger-only idle=%7 maxPerSide=%8 standDownClear=%9" in raw
    loud = text("ITW_CLASH_LoudDebug.sqf")
    assert 'case "rear-cram|followed":' in loud
    assert 'case "rear-cram|stood-down":' in loud


# ------------------------------------------------- 4. no back-line reservation

def test_the_spaa_overwatch_is_gone():
    assert not (MISSION / "ITW_CLASH_SPAAOverwatch.sqf").exists()
    assert '"ITW_CLASH_SPAAOverwatch.sqf"' not in text("init.sqf")
    offenders = [
        p.name for p in MISSION.glob("*.sqf")
        if "ITW_CLASH_SPAAOverwatch" in code(p.name)
    ]
    assert offenders == [], offenders


def test_an_idle_hal_spaa_is_audited_like_any_other_asset():
    body = function_body(code("ITW_CLASH_EmergingThreatsBudget.sqf"), "ITW_CLASH_ETB_fnc_AssetIsEmployed")
    assert "SPAAOverwatch" not in body
