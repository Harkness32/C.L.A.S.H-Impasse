from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def overwatch() -> str:
    return text("ITW_CLASH_SPAAOverwatch.sqf")


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


def test_spaa_leaves_every_pool_hal_dispatches_from():
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Detach")
    for pool in [
        "RydHQ_AttackAv", "RydHQ_FlankAv", "RydHQ_LArmorG", "RydHQ_HArmorG",
        "RydHQ_LArmorATG", "RydHQ_CarsG", "RydHQ_ReconAv",
    ]:
        assert pool in body, pool
    assert '["NoAttack","NoRecon","NoDef"],true' in body


def test_the_doctrine_covers_impasse_spawned_spaa_too():
    source = overwatch()
    # Trace 3: unless every SPAA obeys the rule, the coverage count cannot
    # trust Impasse's own Cheetahs and the commander buys one it already has.
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_Sweep")
    assert "allGroups select" in body
    assert "ITW_CLASH_AirPicture_fnc_IsSPAA" in body
    assert "ITW_CLASH_SPAAOverwatch_fnc_Adopt" in body
    assert 'ITW_CLASH_SPAAOverwatchAdoptImpasse",true' in source
    # A player's own vehicle is never adopted.
    assert "isPlayer _x" in body


def test_hal_cannot_take_it_back_between_cycles():
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Station")
    assert "ITW_CLASH_SPAAOverwatch_fnc_Detach" in body
    station = body.index("ITW_CLASH_SPAAOverwatch_fnc_Detach")
    assert station < body.index("ITW_CLASH_SPAAOverwatch_fnc_Sector")


def test_it_stands_behind_the_front_at_the_decided_standoff():
    source = overwatch()
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_Position")
    assert "ITW_CLASH_SPAAOverwatchStandoff" in body
    assert "ITW_CLASH_SPAAOverwatch_fnc_NearestKnownGround" in body
    assert 'ITW_CLASH_SPAAOverwatchStandoff",1500' in source
    # Nothing on the line clears the standoff: stay at the rear.
    assert "_position = +_rear}" in body


def test_it_covers_where_enemy_air_is_actually_operating():
    body = function_body(overwatch(), "ITW_CLASH_SPAAOverwatch_fnc_Sector")
    assert "ITW_CLASH_AirPicture_fnc_Hostiles" in body
    assert "ITW_CLASH_AirAlarmPosition" in body


def test_it_relocates_only_for_a_real_change_and_never_advances():
    source = overwatch()
    body = function_body(source, "ITW_CLASH_SPAAOverwatch_fnc_Station")
    assert "ITW_CLASH_SPAAOverwatchHysteresis" in body
    assert 'ITW_CLASH_SPAAOverwatchHysteresis",600' in source
    # It only ever withdraws when threatened; a station closer to the enemy is
    # refused otherwise.
    assert "ITW_CLASH_SPAAOverwatchWithdrawAt" in body
    assert "if (!_threatened && {" in body


def test_overwatch_is_loaded_and_adopted_from_the_purchase_path():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_SPAAOverwatch.sqf"' in init
    assert "spaa-overwatch-missing-or-prereq-failed" in init
    cover = function_body(
        text("ITW_CLASH_HALThreatCoverage.sqf"),
        "ITW_CLASH_HALThreatCoverage_fnc_Cover",
    )
    assert "ITW_CLASH_SPAAOverwatch_fnc_Adopt" in cover
    # An SPAA purchase is never offered to HAL's dispatcher.
    spaa = cover.index('_capability isEqualTo "SPAA"')
    branch = cover[spaa:cover.index("} else {", spaa)]
    assert "ITW_CLASH_HALThreatCoverage_fnc_Offer" not in branch
