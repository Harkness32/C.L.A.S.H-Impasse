from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def fob() -> str:
    return text("ITW_CLASH_FOBAirDefence.sqf")


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


def test_the_gap_being_filled_is_still_real():
    # HAL hands AA squads to its garrison routine, but that routine digs a group
    # in where it already stands, so nothing ever sends one to a FOB.
    hal2 = (HAL / "HAC_fnc2.sqf").read_text(encoding="utf-8", errors="replace")
    assert "spawn HAL_Garrison" in hal2
    assert "_AAinf" in hal2
    garrison = (HAL / "HAL" / "Garrison.sqf").read_text(encoding="utf-8", errors="replace")
    assert "_pos = getPosATL (vehicle (leader _unitG));" in garrison


def test_garrisoning_stays_hals_job():
    source = fob()
    # We move the squad and hand it over; HAL's own routine digs it in.
    body = function_body(source, "ITW_CLASH_FOBAirDefence_fnc_HandOver")
    assert "RydHQ_Garrison" in body
    assert 'setVariable ["Garrisoned" + str _group,false]' in body
    assert 'setVariable ["NOGarrisoned" + str _group,false]' in body
    # No garrison behaviour is reimplemented.
    for forbidden in ["setUnitPos", "doWatch", "disableAI", "createVehicle"]:
        assert forbidden not in source, forbidden


def test_handover_waits_for_arrival():
    source = fob()
    # Hand it over early and HAL digs it in halfway down the road.
    body = function_body(source, "ITW_CLASH_FOBAirDefence_fnc_Maintain")
    assert "ITW_CLASH_FOBAirDefenceArrival" in body
    assert "ITW_CLASH_FOBAirDefence_fnc_HandOver" in body
    send = function_body(source, "ITW_CLASH_FOBAirDefence_fnc_Send")
    assert "RydHQ_Garrison" not in send
    assert 'ITW_CLASH_FOBAirDefenceArrival",75' in source


def test_only_an_idle_loaded_aa_squad_is_taken():
    source = fob()
    body = function_body(source, "ITW_CLASH_FOBAirDefence_fnc_Candidates")
    assert "RydHQ_AAInfG" in body
    assert "ITW_CLASH_HALThreatCoverage_fnc_HasLoadedLauncher" in body
    # A squad HAL has tasked is left alone, and a player's squad is never moved.
    assert 'getVariable ["Busy" + str _group,false]' in body
    assert "isPlayer _x" in body


def test_a_stalled_walk_or_a_lost_fob_frees_the_squad():
    source = fob()
    body = function_body(source, "ITW_CLASH_FOBAirDefence_fnc_Maintain")
    assert "ITW_CLASH_FOBAirDefenceTimeout" in body
    assert '"fob-lost"' in body
    assert '"walk-timed-out"' in body
    assert 'ITW_CLASH_FOBAirDefenceTimeout",900' in source


def test_state_is_written_into_the_live_entry_not_a_copy():
    source = fob()
    body = function_body(source, "ITW_CLASH_FOBAirDefence_fnc_Maintain")
    # `+` is a deep copy in SQF: an entry reached through one cannot be updated,
    # and these loops delete from the map they walk.
    assert "forEach (+_assignments)" not in body
    assert body.count("forEach (keys _assignments)") == 2
    assert '_entry set [2,"GARRISONED"]' in body


def test_coverage_counts_them_with_no_further_work():
    # The weight and umbrella already exist, which is why this file only moves
    # squads: an AA squad with a loaded launcher counts 0.25 within 3 km.
    coverage = text("ITW_CLASH_HALThreatCoverage.sqf")
    body = function_body(coverage, "ITW_CLASH_HALThreatCoverage_fnc_AirCoverage")
    assert "RydHQ_AAInfG" in body
    assert "ITW_CLASH_ThreatCoverageAAInfantryUmbrella" in body
    assert "ITW_CLASH_ThreatCoverageInfantryWeight" in body


def test_it_loads_behind_threat_coverage():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_FOBAirDefence.sqf"' in init
    assert "fob-air-defence-missing-or-prereq-failed" in init
    assert init.index("ITW_CLASH_HALThreatCoverage.sqf") < init.index(
        "ITW_CLASH_FOBAirDefence.sqf"
    )
