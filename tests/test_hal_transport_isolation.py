from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_air_transport_probe_is_read_only_during_leader_pilot_spawn_test():
    text = mission("initServer.sqf")
    assert "ITW_CLASH_SCargoAirDiagVersion = 13;" in text
    assert "observerOnly=true" in text
    assert "leaderPilotSpawnTest=true" in text
    assert '"POST-EMBARK-MOVE-STALLED"' in text
    assert '"carrierInAirG"' in text
    assert '"cargoInNCrewInfG"' in text
    assert '"sitrepSinceInjection"' in text
    assert '"hqLZ"' in text
    assert '"tempLZ"' in text
    assert '"nearHelipadCount"' in text
    assert '"nearHelipadDistance"' in text
    assert '"waypointCount"' in text
    assert '"leaderIsPilot"' in text
    assert '"leaderCommand"' in text
    assert '"leaderExpected"' in text
    assert "createHashMapFromArray _snap" in text
    assert 'getOrDefault ["wpDistance",-1]' in text


    for forbidden in [
        'land "NONE"',
        'CancelLand',
        'setDestination',
        'setVariable [_flag,true]',
        'doMove',
        'commandMove',
        'addWaypoint',
        'deleteWaypoint',
        'setCurrentWaypoint',
        'setWaypointPosition',
    ]:
        assert forbidden not in text


def test_native_ryd_wait_is_not_wrapped():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    assert 'ITW_CLASH_Checkbook_fnc_NativeRYDWait' not in dual
    assert '"ryd-wait-scope-fix-ready"' not in dual
    assert 'if (isNil "HAL_SCargo") exitWith {false};' in dual


def test_ai_transport_virtualizes_only_at_passive_hal_storage_boundary():
    life = mission("ITW_CLASH_ServiceLifecycle.sqf")
    auth = mission("ITW_CLASH_ServiceAuthority.sqf")
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    provider_block = life[life.index("ITW_CLASH_Service_fnc_InstallProviderWrappers = {"):
                          life.index("call ITW_CLASH_Service_fnc_InstallProviderWrappers;")]
    assert '"TRANSPORT"' in provider_block
    assert '"ITW_CLASH_ServiceTransportRetirePlayerRadius",75' in life
    assert '"hal-return-zone-entered"' in life
    assert '[_i,"hal-returned-home"] call ITW_CLASH_Service_fnc_Retire;' in life

    assert '[_veh,_crewGroup,"TRANSPORT","checkbook-transport"] call' in auth
    assert '[_veh,_group,"TRANSPORT","impasse-handoff"] call' in auth
    assert '"impasse-handoff"] call\n                ITW_CLASH_Service_fnc_RegisterPhysical;' in auth

    assert 'if (_capability == "TRANSPORT") exitWith {createHashMap};' not in stability
    assert 'ITW_CLASH_Checkbook_fnc_RegisterTransport' in stability
    assert '"transportReuse=true"' not in stability  # boot text is raw, not quoted token
    assert 'transportReuse=true' in stability

    # Virtualization is bookkeeping/storage only: no CLASH transport movement
    # actuator is restored.
    transport_storage = life[life.index("/* HAL owns pickup, delivery and RTB."):
                             life.index("ITW_CLASH_ServiceLifecycleReady = true;")]
    for forbidden in [
        'land "NONE"',
        'CancelLand',
        'setDestination',
        'setCurrentWaypoint',
        'doMove',
        'commandMove',
        'addWaypoint',
        'deleteWaypoint',
    ]:
        assert forbidden not in transport_storage

    assert 'ALLOW_DAMAGE(_veh,true);' in dual

def test_transport_injection_records_sitrep_cycle_only():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    assert '"ITW_CLASH_CheckbookInjectedCycle"' in dual
    assert 'getVariable ["RydHQ_Cyclecount",-1]' in dual


def test_combat_diagnostics_resolve_hq_from_observed_group():
    text = mission("ITW_CLASH_CombatDiagnostics.sqf")
    assert 'params [["_group",grpNull]];' in text
    assert 'side _group == side ITW_CLASH_BLUFORHQ' in text
    assert 'side _group == side ITW_CLASH_HALHQ' in text
    assert '[_group] call ITW_CLASH_fnc_GetCommanderForGroup' in text
    group_fn = text[text.index("ITW_CLASH_Diag_fnc_Group = {"):
                    text.index("ITW_CLASH_Diag_fnc_HQSnapshot = {")]
    assert 'private _hq = [_group] call ITW_CLASH_Diag_fnc_HQ;' in group_fn
    assert 'params ["_otherUnit",["_observerGroup",grpNull]];' in text
    assert 'private _hq = [_observerGroup] call ITW_CLASH_Diag_fnc_HQ;' in text
    assert '[_otherUnit,_group] call ITW_CLASH_Diag_fnc_HALContactKnowledge' in text


def test_impasse_aircraft_driver_is_restored_as_crew_group_leader():
    text = mission("ITW_Attack.sqf")
    needle = '''_driver setRank "LIEUTENANT";
            [_driver,"CARELESS"] call ITW_FncSetUnitBehavior;
            _crewGrp selectLeader _driver;'''
    assert needle in text


def test_impasse_aircraft_driver_leadership_is_restored_in_both_air_paths():
    text = mission("ITW_Attack.sqf")
    assert text.count("_crewGrp selectLeader _driver;") == 2
    assert text.count('"aircraft-driver-leader-restored"') == 2


def test_transport_pool_enrollment_does_not_reintroduce_handoff_waypoint_surgery():
    auth = mission("ITW_CLASH_ServiceAuthority.sqf")
    stage = auth[auth.index("ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {"):
                 auth.index("ITW_CLASH_ServiceAuthorityReady = true;")]
    assert '"TRANSPORT","impasse-handoff"' in stage
    for forbidden in [
        "RYD_WPdel",
        "deleteWaypoint",
        "setCurrentWaypoint",
        "setWaypointPosition",
        "addWaypoint",
        "doMove",
        "commandMove",
    ]:
        assert forbidden not in stage


def test_hal_ai_transport_can_use_native_itw_paradrop_without_classname_doctrine():
    init = mission("init.sqf")
    policy = mission("ITW_CLASH_HALParadrop.sqf")
    attack = mission("ITW_Attack.sqf")
    ally = mission("ITW_Ally.sqf")
    go = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "GoAttInf.sqf").read_text(
        encoding="utf-8"
    )

    assert 'ITW_CLASH_HALParadropVersion = 1;' in policy
    assert 'missionNamespace getVariable ["ITW_ParamHelisUnload",50]' in policy
    assert 'ITW_CLASH_HALParadrop_HeavyCargoSeats' in policy
    assert 'ITW_CLASH_HALParadrop_HeavyChance' in policy
    assert 'ITW_CLASH_HALParadrop_ThreatChance' in policy
    assert 'ITW_CLASH_ServiceCapacity_fnc_ConfigCargoSeats' in policy
    assert '_chance > 0 && {_chance < 100}' in policy
    assert '[_carrier,_cargoGroup] call ITW_AllyParadropCargo;' in policy
    assert '_carrier land "GET OUT";' in policy
    assert '_carrier land "NONE";' in policy
    assert 'classnamesHardcoded=false' in policy

    # Borrow the actual Impasse parachute machinery rather than cloning it.
    assert 'ITW_AllyParadropCargo = {' in ally
    assert '[_veh,grpNull,[_grp],[]] call ITW_AtkUnloadAirplane;' in ally
    assert 'ITW_AtkParachute = {' in attack
    assert '"Steerable_Parachute_F" createVehicle _pos;' in attack

    # HAL decides at its own attack/dropoff seam. C.L.A.S.H. does not create
    # a second transport route; the waypoint either invokes paradrop or keeps
    # native GET OUT landing.
    assert '[_AV,_NeNMode] call ITW_CLASH_HALParadrop_fnc_ShouldUse' in go
    assert 'setVariable ["ITW_CLASH_HALParadropCargoGroup",_unitG]' in go
    assert 'ITW_CLASH_HALParadrop_MinAltitude' in go
    assert 'spawn ITW_CLASH_HALParadrop_fnc_Execute' in go
    assert "(vehicle this) land 'GET OUT'" in go
    assert 'and not (_halParadrop)' in go
    assert '((units _unitG) findIf {isPlayer _x}) < 0' in go
    assert '((units _GDV) findIf {isPlayer _x}) < 0' in go

    for hardcoded in ["Huron", "Chinook", "GhostHawk", "LittleBird"]:
        assert hardcoded not in policy

    assert 'call compile preprocessFileLineNumbers\n            "ITW_CLASH_HALParadrop.sqf"' in init
