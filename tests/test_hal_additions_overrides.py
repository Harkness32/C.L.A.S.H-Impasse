from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal"
ADD = ROOT / "CLASH HAL Additions" / "addons" / "clash_hal_additions"


def read(path: Path) -> str:
    return path.read_text(
        encoding="utf-8", errors="replace"
    ).replace("\r\n", "\n")


def test_nr6_hal_source_carries_no_clash_code():
    # Workshop HAL remains a clean reference. C.L.A.S.H. never edits it.
    for path in NR6.rglob("*.sqf"):
        assert "ITW_CLASH" not in read(path), path


def test_additions_no_longer_replaces_halcore_or_taskinit():
    config = read(ADD / "config.cpp")
    assert 'requiredAddons[] = { "NR6_HAL" };' in config
    assert "class CfgFunctions" in config

    # This was the transport-breaking ownership inversion.
    assert "class NR6" not in config
    assert "class HALcore" not in config
    assert "RydHQInit.sqf" not in config
    assert "TaskInitNR6.sqf" not in config

    nr6 = read(NR6 / "config.cpp")
    assert 'file="\\NR6_HAL\\RydHQInit.sqf";' in nr6
    assert 'function="NR6_fnc_HALcore";' in nr6


def test_legacy_override_entry_is_a_zero_swap_compatibility_shim():
    source = read(ADD / "functions" / "fnc_overrides.sqf")
    assert "CLASH_HALAdd_NativeHALCore = true;" in source
    assert "CLASH_HALAdd_OverridesApplied = [];" in source
    assert "CLASH_HALAdd_SourcePaths = createHashMap;" in source
    assert "nativeHALCore=true" in source
    assert "functionSwaps=0" in source
    assert "taskInit=native" in source

    # The compatibility function may publish Additions metadata, but it must
    # never write a HAL function global or compile an alternate HAL script.
    assert "missionNamespace setVariable" not in source
    assert "compile preprocess" not in source
    assert "\\clash_hal_additions\\hal\\" not in source
    assert '["HAL_' not in source


def test_start_waits_for_native_hal_before_observer_loops():
    source = read(ADD / "functions" / "fnc_start.sqf")
    assert "call CLASH_fnc_HALAdd_Overrides;" in source
    assert "nativeHALCore=true" in source
    assert "functionSwaps=0" in source
    assert "taskInit=native" in source
    assert "RydxHQ_AllHQ" in source
    assert "_hq in RydxHQ_AllHQ" in source
    for helper in (
        "RYD_TerraCognita",
        "RYD_DistOrd",
        "RYD_AmmoCount",
        "RYD_GoLaunch",
        "RYD_Spawn",
    ):
        assert helper in source
    assert "CLASHHALADD | native-hal-ready" in source


def test_dead_hal_copies_are_unreachable_from_runtime_entry_points():
    config = read(ADD / "config.cpp")
    reachable = config
    for script in (ADD / "functions").glob("*.sqf"):
        reachable += "\n" + read(script)

    # Historical copies may remain in the PBO for now, but neither config nor
    # live function code may execute them.
    assert "\\clash_hal_additions\\hal\\" not in reachable
    assert "RydHQInit.sqf" not in reachable
    assert "TaskInitNR6.sqf" not in reachable


def test_watch_filters_transport_service_and_withdrawal_groups():
    watch = read(ADD / "functions" / "fnc_watch.sqf")
    for pool in (
        "RydHQ_NoAttack",
        "RydHQ_CargoOnly",
        "RydHQ_CargoG",
        "RydHQ_SupportG",
        "RydHQ_AmmoDrop",
        "RydHQ_Exhausted",
    ):
        assert f'"{pool}"' in watch
    assert '"ITW_CLASH_ServiceAsset",false' in watch
    assert '"CargoM" + str _group,false' in watch
    assert "_group in _reserved" in watch


def test_respond_revalidates_ownership_at_commit_boundary():
    respond = read(ADD / "functions" / "fnc_respond.sqf")
    for pool in (
        "RydHQ_NoAttack",
        "RydHQ_CargoOnly",
        "RydHQ_CargoG",
        "RydHQ_SupportG",
        "RydHQ_AmmoDrop",
        "RydHQ_Exhausted",
    ):
        assert f'"{pool}"' in respond
    assert '"CargoM" + str _chosen,false' in respond
    assert '"ITW_CLASH_ServiceAsset",false' in respond
    assert "private _nowReserved" in respond

    # The second ownership check must happen before Additions sets Busy and
    # launches a combat executor.
    guard = respond.index("private _nowReserved")
    commit = respond.index(
        '_chosen setVariable [("Busy" + str _chosen), true]',
        guard,
    )
    launch = respond.index("call RYD_Spawn;", commit)
    assert guard < commit < launch


def test_additions_does_not_own_transport_waypoints_or_scargo():
    source = "\n".join(
        read(p) for p in (
            ADD / "functions" / "fnc_start.sqf",
            ADD / "functions" / "fnc_overrides.sqf",
            ADD / "functions" / "fnc_watch.sqf",
            ADD / "functions" / "fnc_respond.sqf",
        )
    )
    assert "HAL_SCargo =" not in source
    assert "NR6_fnc_HALcore =" not in source
    for actuator in (
        "addWaypoint",
        "deleteWaypoint",
        "setWaypointPosition",
        "setCurrentWaypoint",
        "doMove",
        "commandMove",
        "orderGetIn",
        "assignAsCargo",
    ):
        assert actuator not in source
