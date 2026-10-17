"""Supports v5 / strike v5, and the 2026-10-17 HAL copy fixes.

See docs/CLASH_CommanderSupports_Model.md and docs/CLASH_HALAirEmployment_Model.md.

- Strikes about twice as often: bomb and guided cost 10 minutes of income,
  carpet 20, and SAVE pulls half as hard (Hark: "supports are just crazy rare").
- A UAV lost within a minute of reaching its station marks a killbox: no UAV
  is sent or retasked within 1.5 km of it for 15 minutes.
- The bomb pass spawns 6 km out, flies no faster than 550 km/h, re-lines only
  with 10 s of flight left before the final check, and drops nothing more than
  its footprint (50 m) off the line, checked again on the first release frame.
- The lead is scaled by 1.08 from the first live stick (115 m long).
- A break-off turns away from the target from where the jet is, and is logged
  with its geometry.
- The players' own HAL commander draws Info Markers; the enemy's does not.
- GoAttAir declares _wp before the helicopter branch; GoAmmoSupp ends a
  delivery whose recipient is gone.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL_COPY = ROOT / "CLASH HAL Additions" / "addons" / "clash_hal_additions" / "hal"


def code_text(text: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def code(name: str) -> str:
    return code_text((MISSION / name).read_text(encoding="utf-8"))


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
UAV = code("ITW_CLASH_SupportsUAV.sqf")


# ------------------------------------------------------------------- tempo


def test_strikes_cost_half_what_they_did():
    for flavor, minutes in (("Bomb", 10), ("Guided", 10), ("Carpet", 20)):
        assert f'["ITW_CLASH_Supports{flavor}Cadence",{minutes}]' in CORE, flavor
    # The UAV is unchanged; the drops moved to their own wallet in v7.
    assert '["ITW_CLASH_SupportsAirborneHeliCadence",15]' in CORE
    assert '["ITW_CLASH_SupportsAirbornePlaneCadence",25]' in CORE
    assert '["ITW_CLASH_SupportsUAVCadence",4]' in CORE
    # A price is still income times cadence, so the tempo is in minutes.
    price = function_body(CORE, "ITW_CLASH_Supports_fnc_Price")
    assert 'private _price = _rate * ([_flavor,"cadence",10] call ITW_CLASH_Supports_fnc_RowNumber);' in price


def test_save_pulls_half_as_hard():
    assert '["ITW_CLASH_SupportsSaveScale",0.5]' in CORE
    # v7: one SAVE rule for every wallet.
    weight = function_body(CORE, "ITW_CLASH_Supports_fnc_SaveWeight")
    assert "ITW_CLASH_SupportsSaveScale * (switch (true) do {" in weight
    assess = function_body(CORE, "ITW_CLASH_Supports_fnc_Assess")
    assert 'private _saveWeight = [_ledger,"MAIN"] call ITW_CLASH_Supports_fnc_SaveWeight;' in assess


def save_weight(fill, scale=0.5):
    base = 3 if fill < 1 / 3 else 2 if fill < 2 / 3 else 1 if fill < 1 else 0.5
    return scale * base


def test_a_strike_wins_more_picks_once_save_is_halved():
    # The 0:55 pool on 2026-10-17: UAV 3, SAVE 3 (empty bank), BOMB 0.24,
    # GUIDED 0.58. With SAVE halved the strikes' share goes from 12% to 15%;
    # at a strike weight of 1 to 1.5 it goes from 14 to 20% to 18 to 25%.
    # Most of the doubling is the price: the money gate opens twice as often.
    def share(strike, save):
        return strike / (strike + 3 + save)
    assert abs(share(0.82, save_weight(0, 1)) - 0.12) < 0.01
    assert abs(share(0.82, save_weight(0)) - 0.154) < 0.01
    assert share(0.82, save_weight(0, 1)) < share(0.82, save_weight(0))
    assert share(1.0, save_weight(0)) > share(1.0, save_weight(0, 1))


# ----------------------------------------------------------------- killbox


def test_a_uav_lost_on_arrival_marks_a_killbox():
    run = function_body(UAV, "ITW_CLASH_SupportsUAV_fnc_Run")
    mark = run[run.index("(_result#0) isEqualTo \"LOST\""):]
    assert "{(time - _arrivedAt) <= ITW_CLASH_SupportsUAVKillboxSeconds}" in mark
    assert "[_side,getPosATL _veh] call ITW_CLASH_Supports_fnc_MarkKillbox;" in mark
    for name, value in (("Seconds", 60), ("Radius", 1500), ("Duration", 900)):
        assert f'["ITW_CLASH_SupportsUAVKillbox{name}",{value}]' in CORE, name
    assert "ITW_CLASH_SupportsUAVVersion = 4;" in (MISSION / "ITW_CLASH_SupportsUAV.sqf").read_text()


def test_no_uav_is_sent_or_retasked_into_a_killbox():
    inbox = function_body(CORE, "ITW_CLASH_Supports_fnc_InKillbox")
    assert "(time - (_x#1)) <= ITW_CLASH_SupportsUAVKillboxDuration" in inbox
    assert "((_x#0) distance2D _position) <= ITW_CLASH_SupportsUAVKillboxRadius" in inbox
    task = function_body(CORE, "ITW_CLASH_Supports_fnc_UAVTask")
    assert "private _planBoxed = [_side,_planPos] call ITW_CLASH_Supports_fnc_InKillbox;" in task
    assert "if (_planBoxed) then {_planPos = []};" in task
    assert "&& {!([_side,_pos] call ITW_CLASH_Supports_fnc_InKillbox)}" in task
    assert 'if (_planBoxed) exitWith {[[],_planObjective,"killbox"]};' in task
    assess = function_body(CORE, "ITW_CLASH_Supports_fnc_Assess")
    assert '[_context,"UAV",_taskObjective,"","UAV_KILLBOX"] call ITW_CLASH_Supports_fnc_Exclude;' in assess
    # The live UAV follows the stored task, and an empty one moves nothing.
    run = function_body(UAV, "ITW_CLASH_SupportsUAV_fnc_Run")
    assert "if (_taskPos isNotEqualTo [] && {(_taskPos distance2D _station) > ITW_CLASH_SupportsUAVRetask}) then {" in run


# -------------------------------------------------------------- bomb pass


def test_the_bomb_pass_starts_further_out_and_slower():
    assert '["ITW_CLASH_SupportsSpawnDistanceBomb",6000]' in CORE
    spawn = function_body(CORE, "ITW_CLASH_Supports_fnc_SpawnDistance")
    assert 'if (_flavor isEqualTo "BOMB") exitWith {ITW_CLASH_SupportsSpawnDistanceBomb};' in spawn
    assert '["ITW_CLASH_SupportsStrikeBombKph",550]' in STRIKE
    run = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_Run")
    assert 'if (_flavor isEqualTo "BOMB") then {_veh limitSpeed ITW_CLASH_SupportsStrikeBombKph};' in run


def test_a_bomb_is_held_to_its_footprint_off_the_line():
    assert '["ITW_CLASH_SupportsStrikeCrossLimitBomb",50]' in STRIKE
    limit = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_CrossLimit")
    assert 'if (_flavor isEqualTo "BOMB") exitWith {ITW_CLASH_SupportsStrikeCrossLimitBomb};' in limit
    unguided = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_UnguidedPass")
    assert "private _crossLimit = if (_test) then {ITW_CLASH_SupportsStrikeCrossLimit} else {" in unguided
    assert '["crossLimit",_crossLimit]' in unguided


def test_the_line_is_checked_again_on_the_first_release_frame():
    frame = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_ReleaseFrame")
    check = frame.index('if (_next == 0 && {_along <= (_lead - ((_pattern#0)#0))} && {_cross > (_state get "crossLimit")}) exitWith {')
    drop = frame.index("call ITW_CLASH_SupportsStrike_fnc_DropBomb;")
    assert check < drop
    assert '_state set ["done","wide"];' in frame
    # Still only the three removals: a wide stick goes by the top check.
    assert frame.count('removeMissionEventHandler ["EachFrame",_thisEventHandler];') == 3


def test_the_release_lead_is_scaled_from_the_first_stick():
    assert '["ITW_CLASH_SupportsStrikeReleaseScale",1.08]' in STRIKE
    lead = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_Lead")
    assert "* ITW_CLASH_SupportsStrikeReleaseScale" in lead
    # The impact log keeps measuring against the raw model, so it can be refitted.
    drop = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_DropBomb")
    assert "ReleaseScale" not in drop


def no_drag_lead(speed, height, vz=0.0):
    import math
    fall = (vz + math.sqrt(vz * vz + 2 * 9.81 * height)) / 9.81
    return speed * fall


def test_the_scale_matches_the_measured_stick():
    # 196 m/s from 266 m (less the 5 m drop offset), 115 m long on average.
    lead = no_drag_lead(196, 261)
    assert 1400 < lead < 1500
    assert abs((lead * 1.08 - lead) - 115) < 10


def test_a_break_off_turns_away_and_says_why():
    run = function_body(STRIKE, "ITW_CLASH_SupportsStrike_fnc_Run")
    assert 'private _brokeOff = (_result param [0,""]) isEqualTo "BREAKOFF" && {alive _veh};' in run
    assert '["breakoff-geometry",[' in run
    assert '_veh getVariable ["ITW_CLASH_StrikeMissiles",0]' in run
    assert "if ((_veh getRelDir (_support get \"aim\")) <= 180) then {(getDir _veh) - 100} else {(getDir _veh) + 100};" in run
    assert "[_veh,_group,getPosATL _veh,_away,4000,300,_support] spawn ITW_CLASH_Supports_fnc_Egress;" in run
    # Delivered passes still go on past the target.
    assert "_veh,_group,_support get \"aim\",_support getOrDefault [\"heading\",_heading],4000,300,_support" in run
    assert '_veh removeEventHandler ["IncomingMissile",_missileHandler]' in run


def test_versions():
    assert "ITW_CLASH_SupportsVersion = 8;" in (MISSION / "ITW_CLASH_Supports.sqf").read_text()
    assert "ITW_CLASH_SupportsStrikeVersion = 5;" in (MISSION / "ITW_CLASH_SupportsStrike.sqf").read_text()


# ------------------------------------------------------------------- HAL


def test_only_the_players_commander_draws_info_markers():
    dual = code("ITW_CLASH_DualHALCheckbook.sqf")
    assert '["ITW_CLASH_PlayerInfoMarkers",true]' in dual
    configure = function_body(dual, "ITW_CLASH_DualHAL_fnc_ConfigureBLUFORGlobals")
    assert "RydHQB_InfoMarkers = ITW_CLASH_PlayerInfoMarkers;" in configure
    # HAL's markers are global: the enemy commander's would show the players
    # what it knows of them. Nothing in the mission turns them on.
    for path in MISSION.glob("*.sqf"):
        assert "RydHQ_InfoMarkers =" not in code_text(path.read_text(encoding="utf-8", errors="replace")), path.name


def test_goattair_declares_the_waypoint_before_the_branch():
    source = code_text((HAL_COPY / "GoAttAir.sqf").read_text(encoding="utf-8"))
    branch = source.index("if (_clashHeli) then")
    assert source.index("_wp = [];") < branch
    assert "if (_timer > 120) then {deleteWaypoint _wp};" in source[branch:]


def test_goammosupp_ends_a_delivery_whose_recipient_is_gone():
    source = code_text((HAL_COPY / "GoAmmoSupp.sqf").read_text(encoding="utf-8"))
    loop = source[source.index("while {(_counter <= 3)} do"):]
    guard = loop.index("if ((isNull _Trg) or {not (alive _Trg)}) exitWith {};")
    assert guard < loop.index("if (_counter == 0) then {_wp waypointAttachVehicle _Trg};")
    assert guard < loop.index("call RYD_WPadd;")
