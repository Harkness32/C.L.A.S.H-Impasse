import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal"
ADD = ROOT / "CLASH HAL Additions" / "addons" / "clash_hal_additions"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def overrides() -> dict:
    source = read(ADD / "functions" / "fnc_overrides.sqf")
    return dict(re.findall(r'\["(HAL_\w+)","(\w+\.sqf)"\]', source))


def test_nr6_hal_source_carries_no_clash_code():
    # Test runs load the public Workshop NR6 HAL, so edits here never execute;
    # every CLASH change to HAL belongs in CLASH HAL Additions.
    for path in NR6.rglob("*.sqf"):
        assert "ITW_CLASH" not in read(path), path


def test_hal_start_is_redirected_through_config_after_nr6_hal():
    config = read(ADD / "config.cpp")
    assert 'requiredAddons[] = { "NR6_HAL" };' in config
    assert 'file = "\\clash_hal_additions\\hal\\RydHQInit.sqf";' in config
    assert "class HALcore" in config
    nr6 = read(NR6 / "config.cpp")
    assert 'file="\\NR6_HAL\\RydHQInit.sqf";' in nr6
    assert 'function="NR6_fnc_HALcore";' in nr6


def test_start_copy_differs_from_hal_only_where_clash_swaps_scripts():
    original = read(NR6 / "RydHQInit.sqf").splitlines()
    copy = read(ADD / "hal" / "RydHQInit.sqf").splitlines()
    removed = [line for line in original if line not in copy]
    added = [line for line in copy if line not in original]
    assert removed == [
        'call compile preprocessfile (RYD_Path + "VarInit.sqf");',
        'call compile preprocessfile (RYD_Path + "TaskInitNR6.sqf");',
    ]
    assert "isNil {" in added
    assert "\tcall CLASH_fnc_HALAdd_Overrides;" in added
    assert '\tcall compile preprocessfile (RYD_Path + "VarInit.sqf");' in added
    assert 'call compile preprocessFileLineNumbers "\\clash_hal_additions\\hal\\TaskInitNR6.sqf";' in added


def test_every_swapped_global_is_one_hal_compiles_from_the_same_file():
    var_init = read(NR6 / "VarInit.sqf")
    swaps = overrides()
    assert len(swaps) == 8
    for global_name, file_name in swaps.items():
        native = f'{global_name} = compile preprocessfile (RYD_Path + "HAL\\{file_name}");'
        assert native in var_init, global_name
        copy = ADD / "hal" / file_name
        assert copy.exists(), copy
        assert read(copy) != read(NR6 / "HAL" / file_name), file_name


def test_overridden_task_init_carries_clash_fixes():
    copy = read(ADD / "hal" / "TaskInitNR6.sqf")
    assert copy != read(NR6 / "TaskInitNR6.sqf")
    assert '"_this isEqualTo _target"' in copy
    assert '["TASKINIT_GROUND",false,false]' in copy
