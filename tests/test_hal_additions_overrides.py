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
    assert len(swaps) == 9
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



def test_paradrop_override_chain_is_runtime_self_proving():
    init = read(ADD / "hal" / "RydHQInit.sqf")
    overrides_source = read(ADD / "functions" / "fnc_overrides.sqf")
    attack = read(ADD / "hal" / "GoAttInf.sqf")

    assert "CLASHHALADD | halcore-entered | source=clash_hal_additions" in init
    assert "CLASHHALADD | hal-overrides-applied" in overrides_source
    assert "CLASHHALADD | goattinf-entered" in attack
    assert "CLASHHALADD | paradrop-gate" in attack
    assert "CLASHHALADD | paradrop-decision" in attack
    assert "ITW_CLASH_HALParadropReady" in attack
    assert "ITW_CLASH_HALParadrop_fnc_ShouldUse" in attack
    assert 'missionNamespace getVariable ["ITW_ParamHelisUnload",-999]' in attack
    assert "CLASHHALADD | air-unload-waypoint" in attack
    assert "_clashParaAirCarrier" in attack
    assert "_clashParaInfantry" in attack
    assert "_clashParaCargoPlayer" in attack
    assert "_clashParaCrewPlayer" in attack



def test_air_unload_is_decided_by_role_not_by_who_is_aboard_yet():
    """The air-lift decision cannot depend on the squad already being inside.

    GoAttInf orders boarding with orderGetIn (line ~191) and builds the unload
    waypoint statement (line ~578) with no wait in between, so a physical
    "is anyone aboard" test is false at that moment in the normal case - the
    squad is still walking to the aircraft.

    Gating on it left _sts at its default "deletewaypoint" for every lift: the
    helicopter reached the drop point, deleted the waypoint, and nobody got
    out, not even the land "GET OUT" stock HAL would have issued. Troops rode
    around indefinitely.

    So the decision is role-based, and the physical check lives at execution
    time where it already existed - ITW_CLASH_HALParadrop_fnc_Execute reads the
    cargo group off the carrier and declines when nobody is aboard.
    """
    attack = read(ADD / "hal" / "GoAttInf.sqf")

    # The lift is a role question: an air carrier, distinct from the cargo
    # group, carrying non-crew infantry.
    assert "private _clashAirLift = _clashParaAirCarrier && {_clashParaInfantry};" in attack
    assert "_GDV != _unitG" in attack
    assert 'RydHQ_AirG' in attack

    # And specifically NOT a physical question.
    assert "_clashAirLift = _clashParaAirCarrier && {_clashParaAboard}" not in attack
    assert "_clashParaAboard" in attack, "kept, but only as trace context"
    trace = attack[attack.index("CLASHHALADD | paradrop-gate"):]
    assert "_clashParaAboard" in trace[:600]


def test_the_aboard_check_happens_at_execution_time():
    attack = read(ADD / "hal" / "GoAttInf.sqf")
    unload = attack[attack.index('_sts = ["true","deletewaypoint'):attack.index('_EDPos = _GDV getVariable')]
    # The paradrop statement verifies the squad is in the aircraft and lands
    # for real when the paradrop declines, rather than stranding them airborne.
    assert "vehicle _x == _v" in unload
    assert "air-unload-land-fallback" in unload
    assert "_v land 'GET OUT'" in unload
    # The ordinary branch still lands.
    assert "land 'GET OUT'" in unload


def test_a_declined_paradrop_cannot_strand_the_squad():
    """Execute has several false returns and lands for itself on only one of
    them - the same hole HotDrop was fixed for."""
    attack = read(ADD / "hal" / "GoAttInf.sqf")
    assert "ITW_CLASH_HALParadrop_fnc_Execute" in attack
    # The cargo group is read BEFORE Execute, which clears it on success.
    stmt = attack[attack.index("air-unload-waypoint"):]
    stmt = stmt[:stmt.index("deletewaypoint")]
    assert stmt.index("ITW_CLASH_HALParadropCargoGroup") < stmt.index("fnc_Execute")


def test_recon_airlift_uses_same_paradrop_policy():
    recon = read(ADD / "hal" / "GoRecon.sqf")

    assert "CLASHHALADD | gorecon-entered" in recon
    assert "CLASHHALADD | recon-paradrop-gate" in recon
    assert "CLASHHALADD | recon-paradrop-decision" in recon
    assert "CLASHHALADD | recon-air-unload-waypoint" in recon
    assert "ITW_CLASH_HALParadrop_fnc_ShouldUse" in recon
    assert "ITW_CLASH_HALParadrop_fnc_Execute" in recon
    assert "private _clashParaAboard" in recon
    assert "private _clashAirLift" in recon
    assert "if (_clashAirLift) then" in recon
    assert 'if (_clashAirLift and ((_HQ getVariable ["RydHQ_CargoFind",0]) > 0)' in recon

    unload = recon[recon.index('_sts = ["true","deletewaypoint'):recon.index("_wp = [_gp,_pos")]
    assert 'RydHQ_NCrewInfG' not in unload
    # Same correction as GoAttInf: the lift is a role question, because this
    # runs before boarding completes. And the same land fallback, because
    # Execute lands for itself on only one of its false returns.
    assert "private _clashAirLift = _clashParaAirCarrier && {_clashParaInfantry};" in recon
    assert "_clashAirLift = _clashParaAirCarrier && {_clashParaAboard}" not in recon
    assert "recon-air-unload-land-fallback" in unload
    assert "_v land 'GET OUT'" in unload


def test_gorecon_is_actually_installed():
    """f501841 added GoRecon.sqf but never swapped HAL_GoRecon, so the file
    was dead code and HAL_GoRecon still resolved to stock HAL - the paradrop
    being chased could not execute. 223085b added the swap. This pins it,
    because a HAL override that is not in this list does nothing at all."""
    overrides = read(ADD / "functions" / "fnc_overrides.sqf")
    assert '["HAL_GoRecon","GoRecon.sqf"]' in overrides
    assert (ADD / "hal" / "GoRecon.sqf").exists()

