from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_air_transport_probe_is_read_only():
    text = mission("initServer.sqf")
    assert "ITW_CLASH_SCargoAirDiagVersion = 8;" in text
    assert "observerOnly=true" in text
    assert '"POST-EMBARK-MOVE-STALLED"' in text
    assert '"carrierInAirG"' in text
    assert '"cargoInNCrewInfG"' in text
    assert '"sitrepSinceInjection"' in text

    for forbidden in [
        'land "NONE"',
        'CancelLand',
        'setDestination',
        'setCurrentWaypoint',
        'setVariable [_flag,true]',
        'doMove',
        'commandMove',
    ]:
        assert forbidden not in text


def test_native_ryd_wait_is_not_wrapped():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    assert 'ITW_CLASH_Checkbook_fnc_NativeRYDWait' not in dual
    assert '"ryd-wait-scope-fix-ready"' not in dual
    assert 'if (isNil "HAL_SCargo") exitWith {false};' in dual


def test_ai_transport_is_outside_service_virtualization():
    life = mission("ITW_CLASH_ServiceLifecycle.sqf")
    auth = mission("ITW_CLASH_ServiceAuthority.sqf")
    stability = mission("ITW_CLASH_ServiceStability.sqf")

    provider_block = life[life.index("ITW_CLASH_Service_fnc_InstallProviderWrappers = {"):
                          life.index("call ITW_CLASH_Service_fnc_InstallProviderWrappers;")]
    assert '"TRANSPORT"' not in provider_block
    assert 'checkbook-register' not in life
    assert 'impasse-handoff"] call ITW_CLASH_Service_fnc_RegisterPhysical' not in life
    assert '"TRANSPORT","checkbook-transport"' not in auth
    assert 'if (_capability == "TRANSPORT") exitWith {createHashMap};' in stability


def test_transport_injection_records_sitrep_cycle_only():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")
    assert '"ITW_CLASH_CheckbookInjectedCycle"' in dual
    assert 'getVariable ["RydHQ_Cyclecount",-1]' in dual
