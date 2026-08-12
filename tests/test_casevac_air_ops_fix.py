from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_air_ops_patch_is_started_after_casevac():
    init = text("init.sqf")
    assert 'execVM "ITW_CLASH_CASEVAC.sqf"' in init
    assert 'execVM "ITW_CLASH_CASEVAC_AirOpsFix.sqf"' in init
    assert init.index('execVM "ITW_CLASH_CASEVAC.sqf"') < init.index('execVM "ITW_CLASH_CASEVAC_AirOpsFix.sqf"')


def test_casevac_spawn_fix_removes_named_scope_return_bug():
    source = text("ITW_CLASH_CASEVAC_AirOpsFix.sqf")
    assert 'ITW_CLASH_CASEVAC_fnc_SpawnHeli = {' in source
    assert 'for "_candidateIndex" from 0 to ((count _ordered) - 1) do {' in source
    assert "private _result = [];" in source
    assert "_result = [_heli,_crewGroup,_vehDef,_baseIndex,_spawnSource,+_spawnPos];" in source
    assert 'scopeName "ITW_CLASH_CASEVAC_SPAWN"' not in source
    assert 'breakOut "ITW_CLASH_CASEVAC_SPAWN"' not in source
    assert '"spawn-selected"' in source


def test_casevac_helicopter_gets_explicit_inbound_lz_route():
    source = text("ITW_CLASH_CASEVAC_AirOpsFix.sqf")
    assert "ITW_CLASH_CASEVAC_fnc_OrderHeliLZ" in source
    assert "_crewGroup addWaypoint [_lz,0]" in source
    assert '_wp setWaypointType "MOVE";' in source
    assert '_wp setWaypointSpeed "FULL";' in source
    assert '_wp setWaypointBehaviour "CARELESS";' in source
    assert '_wp setWaypointCompletionRadius 80;' in source
    assert '"inbound-route"' in source


def test_run_extraction_routes_before_waiting_for_landing_distance():
    source = text("ITW_CLASH_CASEVAC_AirOpsFix.sqf")
    assert "ITW_CLASH_CASEVAC_fnc_RunExtraction_V1Base" in source
    assert "call ITW_CLASH_CASEVAC_fnc_OrderHeliLZ" in source
    assert '"inbound-route-failed"' in source
    assert "_this call ITW_CLASH_CASEVAC_fnc_RunExtraction_V1Base" in source


def test_spawn_fix_preserves_impasse_ticket_and_aircraft_accounting():
    source = text("ITW_CLASH_CASEVAC_AirOpsFix.sqf")
    assert "ITW_AtkSpawnVeh" in source
    assert "ITW_VEH_COUNT_INCR" in source
    assert "ITW_TICKET_REDUCE" in source
    assert '"ITW_VehDef"' in source
    assert "ITW_AtkAddVehicle" not in source


def test_casevac_bypasses_impasse_vehicle_count_cap_but_still_requires_tickets():
    source = text("ITW_CLASH_CASEVAC_AirOpsFix.sqf")
    candidate_start = source.index("private _candidates = (_transport + _dualVeh) select {")
    candidate_end = source.index("if (_candidates isEqualTo [])", candidate_start)
    candidate_filter = source[candidate_start:candidate_end]

    assert "ITW_VEH_REQD_TICKETS" in candidate_filter
    assert "ITW_VEH_CURR_TICKETS" in candidate_filter
    assert "ITW_VEH_COUNT" not in candidate_filter
    assert "ITW_VEH_MAX" not in candidate_filter
    assert '"cap-bypass"' in source
    assert "ITW_CLASH_CASEVAC_AirOpsFixVersion = 2;" in source
    assert "capBypass=true tickets=true" in source
