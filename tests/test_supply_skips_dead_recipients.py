from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def function(source: str, name: str) -> str:
    start = source.index(name + " = {")
    return source[start:source.index("\n};", start)]


def test_wreck_crews_are_hidden_from_native_ammo_and_fuel_scans():
    # Live run: a HEMTT drove to a destroyed armed Offroad. Surviving crew keep
    # the wreck as assignedVehicle and a wreck has no ammo or fuel.
    logistics = mission("ITW_CLASH_HALLogistics.sqf")
    wrecks = function(logistics, "ITW_CLASH_HALLogistics_fnc_WreckOnlyGroups")
    assert "assignedVehicle _x" in wrecks
    assert "_assigned findIf {alive _x} < 0" in wrecks
    call = function(logistics, "ITW_CLASH_HALLogistics_fnc_CallWithoutWrecks")
    assert call.index("_excluded + _hidden") < call.index("_args call _native;")
    assert call.index("_args call _native;") < call.index(") - _hidden];")
    assert '"RydHQ_ExReAmmo",ITW_CLASH_HALLogistics_fnc_NativeSuppAmmo' in logistics
    assert '"RydHQ_ExRefuel",ITW_CLASH_HALLogistics_fnc_NativeSuppFuel' in logistics


def test_native_ground_runs_skip_or_abort_a_dead_recipient():
    run = function(mission("ITW_CLASH_Resupply.sqf"), "ITW_CLASH_Resupply_fnc_RunNative")
    assert "if (_ground && {!alive _target}) exitWith {" in run
    assert "waitUntil {sleep 2; !alive _target};" in run
    assert '_provider setVariable ["Break",true];' in run
    # nothing downstream consumes Break or restores the aborted order's state
    cleanup = run[run.index('_provider getVariable ["ITW_CLASH_ResupplyDeadRecipient",false]'):]
    assert '_provider setVariable ["Break",false];' in cleanup
    assert "[_provider] call RYD_WPdel;" in cleanup
    assert '_vehicle enableAI "TARGET";' in cleanup


def test_air_ammo_drops_are_not_guarded_by_recipient_life():
    resupply = mission("ITW_CLASH_Resupply.sqf")
    start = resupply.index("    HAL_GoAmmoSupp = {")
    wrapper = resupply[start:resupply.index("\n    };", start)]
    assert "!(_this param [4,false])" in wrapper


def test_no_hal_mod_files_are_patched_for_this():
    hal = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"
    assert "while {(_counter <= 3)} do" in (hal / "GoAmmoSupp.sqf").read_text(encoding="utf-8")
