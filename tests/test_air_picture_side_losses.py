"""Phase 0 of commander supports: two corridor fixes in the air picture.

1. The air-loss counter was one list for the whole map. A BLUFOR helicopter
   downed by an OPFOR SAM closed that area to OPFOR's own lifts. Losses and the
   areas they close now carry the side that lost the aircraft, and a corridor
   only reads its own side's closures.

2. The corridor check denied a route for any enemy plane with any air-to-air
   missile (IsFighter). The helicopter doctrine on ThreatTier says only a
   fixed-wing aircraft with four or more air-to-air missiles (HARD_KILL) closes
   a corridor; a CAS jet with a self-defence pair is tolerated. HARD_KILL is now
   the default rule. ThreatCoverage's CAS provider choice keeps the broader rule
   explicitly, because it is deciding whether to send a jet.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def air_picture() -> str:
    return text("ITW_CLASH_AirPicture.sqf")


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


# --------------------------------------------------------------- side losses


def test_a_loss_records_whose_aircraft_it_was():
    record = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RecordLoss")
    assert 'params ["_veh",["_killer",objNull],["_side",sideUnknown]]' in record
    # Weight stays at index 3 (the weighted trip reads it there); side is 4.
    assert (
        "ITW_CLASH_AirPictureLosses pushBack "
        "[_position,time,typeOf _veh,_weight,_side]"
    ) in record
    assert "_score = _score + (_x param [3,0])" in record


def test_the_kill_event_supplies_the_side():
    source = air_picture()
    on_kill = function_body(source, "ITW_CLASH_AirPicture_fnc_OnKill")
    assert (
        "private _lostSide = [_killed,_victim] call "
        "ITW_CLASH_AirPicture_fnc_LossSide"
    ) in on_kill
    assert (
        "[_victim,_killer,_lostSide] call ITW_CLASH_AirPicture_fnc_RecordLoss"
    ) in on_kill


def test_loss_side_prefers_the_group_and_falls_back_to_config():
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_LossSide")
    # A dead man reports civilian; his group still has the real side when the
    # kill event fires.
    group = body.index("side group _unit")
    config = body.index('"CfgVehicles" >> typeOf _veh >> "side"')
    assert group < config, "the group answers first, config is the fallback"
    assert "if (_side in [west,east,independent]) exitWith {_side};" in body
    # Config side 0/1/2 maps to east/west/independent; anything else is unknown.
    assert "[east,west,independent] param [_configSide,sideUnknown]" in body
    assert "sideUnknown" in body


def test_a_trip_counts_only_this_sides_losses():
    record = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RecordLoss")
    nearby = record[record.index("private _nearby"):record.index("private _score")]
    assert "((_x param [4,sideUnknown]) isEqualTo _side)" in nearby
    # The spatial and time windows are unchanged.
    assert "ITW_CLASH_AirPictureLossRadius" in nearby
    assert "ITW_CLASH_AirPictureLossWindow" in nearby


def test_a_closed_area_belongs_to_one_side():
    record = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RecordLoss")
    retrip = record[record.index("private _index"):record.index("private _closure")]
    assert "((_x param [3,sideUnknown]) isEqualTo _side)" in retrip, (
        "an OPFOR re-trip must not refresh a BLUFOR closure"
    )
    assert "ITW_CLASH_AirPictureLossAreas pushBack [_position,time,_closure,_side]" in record


def test_a_corridor_reads_only_its_own_sides_closures():
    source = air_picture()
    closed = function_body(source, "ITW_CLASH_AirPicture_fnc_LossClosed")
    assert 'params ["_position",["_side",sideUnknown]]' in closed
    assert "private _areaSide = _x param [3,sideUnknown];" in closed
    assert "(_side isEqualTo sideUnknown)" in closed
    assert "{_areaSide isEqualTo sideUnknown}" in closed
    assert "{_areaSide isEqualTo _side}" in closed
    # Expiry is unchanged.
    assert "(time - (_x#1)) <= (_x#2)" in closed
    corridor = function_body(source, "ITW_CLASH_AirPicture_fnc_ClassifyCorridor")
    assert "[_destination,side _hq] call ITW_CLASH_AirPicture_fnc_LossClosed" in corridor
    assert '"recent-losses"' in corridor


def test_no_caller_still_asks_for_a_side_blind_closure():
    for path in MISSION.glob("ITW_CLASH*.sqf"):
        source = path.read_text(encoding="utf-8")
        for match in re.finditer(r"\[([^\[\]]*)\]\s*call\s+ITW_CLASH_AirPicture_fnc_LossClosed", source):
            args = [a.strip() for a in match.group(1).split(",")]
            assert len(args) == 2, f"{path.name}: LossClosed called without a side: {match.group(0)}"


def test_loss_telemetry_names_the_side():
    record = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_RecordLoss")
    for event in ["air-loss", "loss-below-threshold", "loss-area-closed"]:
        start = record.index(f'"{event}"')
        end = record.index("call ITW_CLASH_AirPicture_fnc_Log", start)
        assert "toUpperANSI str _side" in record[start:end], event


# ------------------------------------------------------------- fighter rule


def test_the_corridor_defaults_to_the_hard_kill_rule():
    corridor = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_ClassifyCorridor")
    assert 'params ["_hq","_origin","_destination",["_fighterRule","HARD_KILL"]]' in corridor
    assert "[_veh,_fighterRule] call ITW_CLASH_AirPicture_fnc_DeniesAirspace" in corridor
    assert "ITW_CLASH_AirPicture_fnc_IsFighter" not in corridor, (
        "any-AA-missile was the defect for helicopter corridors"
    )
    # The denial reason the Thunder Run tiers and logs read is unchanged.
    assert '"enemy-fighter-corridor"' in corridor


def test_denies_airspace_is_fixed_wing_and_tier_based():
    body = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_DeniesAirspace")
    assert 'params ["_veh",["_rule","HARD_KILL"]]' in body
    assert '!(_veh isKindOf "Plane")' in body
    any_rule = body.index('"ANY_AA_MISSILE"')
    tier = body.index("ITW_CLASH_AirPicture_fnc_ThreatTier")
    assert "ITW_CLASH_AirPicture_fnc_IsFighter" in body[any_rule:tier]
    assert '"HARD_KILL"' in body[tier:]


def test_hard_kill_for_aircraft_still_means_four_missiles():
    tier = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_ThreatTier")
    assert (
        '(_profile get "airToAirMissiles") >= ITW_CLASH_AirPictureHardKillMissiles'
    ) in tier
    assert '"ITW_CLASH_AirPictureHardKillMissiles",4' in air_picture()


def test_only_the_cas_provider_choice_keeps_the_broad_rule():
    users = []
    for path in MISSION.glob("ITW_CLASH*.sqf"):
        if path.name == "ITW_CLASH_AirPicture.sqf":
            continue
        if '"ANY_AA_MISSILE"' in path.read_text(encoding="utf-8"):
            users.append(path.name)
    assert users == ["ITW_CLASH_HALThreatCoverage.sqf"], users
    coverage = function_body(
        text("ITW_CLASH_HALThreatCoverage.sqf"),
        "ITW_CLASH_HALThreatCoverage_fnc_ChooseProvider",
    )
    assert (
        '[_hq,_origin,getPosATL _threat,"ANY_AA_MISSILE"] call\n'
        "            ITW_CLASH_AirPicture_fnc_ClassifyCorridor"
    ) in coverage


def test_helicopter_callers_use_the_default_rule():
    for name in [
        "ITW_CLASH_HALCargoDiceFix.sqf",
        "ITW_CLASH_ThunderRunAirTiers.sqf",
        "ITW_CLASH_HotDrop.sqf",
        "ITW_CLASH_HALUnload.sqf",
    ]:
        source = text(name)
        assert "ITW_CLASH_AirPicture_fnc_ClassifyCorridor" in source, name
        assert "ANY_AA_MISSILE" not in source, name


def test_our_own_fighter_coverage_still_counts_any_aa_missile():
    # IsFighter itself is unchanged: ThreatCoverage counts our own CAP with it.
    fighter = function_body(air_picture(), "ITW_CLASH_AirPicture_fnc_IsFighter")
    assert 'isKindOf "Plane"' in fighter
    assert '"antiAirMissile"' in fighter


def test_version_and_boot_line():
    source = air_picture()
    assert "ITW_CLASH_AirPictureVersion = 4;" in source
    boot = source[source.index("air-picture-ready"):]
    for flag in [
        "lossClosuresPerSide=true",
        "corridorFighterRule=HARD_KILL",
        "casFighterRule=ANY_AA_MISSILE",
    ]:
        assert flag in boot, flag
