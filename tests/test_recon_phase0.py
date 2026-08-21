from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def recon() -> str:
    return text(MISSION / "ITW_CLASH_ReconObserver.sqf")


def test_recon_observer_is_server_wired_and_fail_open():
    init = text(MISSION / "init.sqf")
    source = recon()
    assert 'execVM "ITW_CLASH_ReconObserver.sqf"' in init
    assert "if (!isServer) exitWith {};" in source
    assert 'isNil "HAL_GoRecon"' in source
    assert 'isNil "HAL_GoDefRecon"' in source
    assert "native HAL recon retained" in source


def test_recon_observer_restores_native_broad_recon_instead_of_sof_only_gate():
    source = recon()
    assert "ITW_CLASH_ReconPhase0Version = 2;" in source
    assert "nativeBroadRecon=true" in source
    assert "observerOnly=true" in source
    assert "specForExcludedByHAL=true" in source
    assert '"blocked-nonsof"' not in source
    assert '"sofOnly=true"' not in source
    assert 'setVariable ["RydHQ_NoRecon"' not in source
    assert 'setVariable ["RydHQ_ReconG"' not in source
    assert 'setVariable ["RydHQ_SpecForG"' not in source


def test_recon_observer_wraps_native_hal_recon_without_reimplementing_it():
    source = recon()
    assert "ITW_CLASH_Recon_fnc_NativeGoRecon = HAL_GoRecon;" in source
    assert "ITW_CLASH_Recon_fnc_NativeGoDefRecon = HAL_GoDefRecon;" in source
    assert "HAL_GoRecon = {" in source
    assert "HAL_GoDefRecon = {" in source
    assert "_this call ITW_CLASH_Recon_fnc_NativeGoRecon;" in source
    assert "_this call ITW_CLASH_Recon_fnc_NativeGoDefRecon;" in source
    assert "createUnit" not in source
    assert "createVehicle" not in source
    assert "ITW_TICKET_REDUCE" not in source


def test_recon_observer_is_intelligence_telemetry_only():
    source = recon()
    for token in [
        '"assigned"',
        '"contact"',
        '"intel-gained"',
        '"complete"',
        '"aborted"',
        '"wiped"',
        '"unexpected-specfor-assignment"',
    ]:
        assert token in source
    assert "knowsAbout _target" in source
    assert '"RydHQ_KnEnemies"' in source
    assert " reveal " not in source.lower()


def test_native_hal_source_excludes_specfor_from_ordinary_recon_pool():
    orders = text(HAL / "Orders.sqf")
    assert 'RydHQ_SpecForG' in orders
    assert '_ReconAv' in orders
    assert 'HAL_GoRecon' in orders


def test_native_hal_statusquo_has_real_specfor_classification_surface():
    source = text(ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAC_fnc2.sqf")
    assert '_SpecForcheck' in source
    assert '_specFor_class' in source
    assert 'setVariable ["RydHQ_SpecForG",_SpecForG]' in source
