import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAC_FNC2 = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAC_fnc2.sqf"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def fix() -> str:
    return text(MISSION / "ITW_CLASH_HALNativeSFFix.sqf")


def status_quo() -> str:
    source = text(HAC_FNC2)
    return source[source.index("RYD_StatusQuo ="):source.index("RYD_isInside =")]


def test_statusquo_patch_targets_lines_that_exist_once_in_hal():
    # The runtime patch refuses missing or duplicate signatures, so each one
    # must appear exactly once in the vendored RYD_StatusQuo.
    quo = status_quo()
    for bad in [
        "_HQ = group _x;",
        "if (_HQ in _knownEG) then",
        "_SFTgts pushBack _HQ",
        "_SFcount = {",
    ]:
        assert quo.count(bad) == 1, bad


def test_raid_loop_no_longer_overwrites_the_commander():
    # HQSitRep sets _HQ once and calls StatusQuo each cycle, so the native
    # `_HQ = group _x;` swapped the commander for the enemy's for good.
    source = fix()
    assert '["_HQ = group _x;","private _clashSFTargetHQ = group _x;"' in source
    assert '["if (_HQ in _knownEG) then","if (_clashSFTargetHQ in _knownEG) then"' in source
    assert '["_SFTgts pushBack _HQ","_SFTgts pushBack _clashSFTargetHQ"' in source
    assert 'if (_ok && {(_quo find "_HQ = group _x;") < 0}) then {' in source
    assert "RYD_StatusQuo = compile _quo;" in source
    assert "ITW_CLASH_HALStatusQuoSFPatched = true;" in source
    sitrep = text(ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "HQSitRep.sqf")
    assert sitrep.startswith('_SCRname = "SitRep";\n_HQ = _this select 0;') or "\n_HQ = _this select 0;" in sitrep
    assert "call RYD_StatusQuo" in sitrep


def test_raid_routine_reads_the_commanders_specfor_list():
    # The recon bridge adds C.L.A.S.H. SOF to RydHQ_SpecForG inside
    # HQOrders/HQOrdersDef, which StatusQuo calls just before the raid block.
    quo = status_quo()
    raid = quo.index("_SFcount = {")
    assert quo.index("[_HQ] call HAL_HQOrders") < raid
    assert quo.index("[_HQ] call HAL_HQOrdersDef") < raid
    assert '"_SpecForG = _HQ getVariable [""RydHQ_SpecForG"",_SpecForG]; _SFcount = {"' in fix()
    bridge = text(MISSION / "ITW_CLASH_ReconPlanningBridge.sqf")
    assert '[_hq,"offensive"] call ITW_CLASH_ReconPlanning_fnc_SyncSpecFor;' in bridge
    assert '[_hq,"defensive"] call ITW_CLASH_ReconPlanning_fnc_SyncSpecFor;' in bridge


def test_sof_loader_expects_the_doctrine_files_version():
    doctrine = text(MISSION / "ITW_CLASH_SOFDoctrine.sqf")
    version = re.search(r"ITW_CLASH_SOFDoctrineVersion = (\d+);", doctrine).group(1)
    loader = text(MISSION / "ITW_CLASH_SOFDoctrineBootstrap.sqf")
    assert f'(missionNamespace getVariable ["ITW_CLASH_SOFDoctrineVersion",-1]) == {version} && {{' in loader


def test_sf_air_insertion_can_parachute_the_team():
    # GoSFAttack's air carrier lands to let the team out; C.L.A.S.H. swaps in
    # its paradrop with the same rules as GoAttInf, counting SF as threatened.
    attack = text(ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "GoSFAttack.sqf")
    native = (
        'if (((group (assigneddriver _AV)) in (_HQ getVariable ["RydHQ_AirG",[]])) and '
        '(_unitG in (_HQ getVariable ["RydHQ_NCrewInfG",[]]))) then '
        '{_sts = ["true","(vehicle this) land \'GET OUT\';deletewaypoint [(group this), 0]"]};'
    )
    assert attack.count(native) == 1
    source = fix()
    assert '"GoSFAttack-air-insertion-paradrop"' in source
    assert "_sts = [_AV,_GDV,_unitG,_sts] call ITW_CLASH_HALNativeSF_fnc_ParadropStatement;" in source
    decide = source[source.index("ITW_CLASH_HALNativeSF_fnc_ParadropStatement = {"):]
    decide = decide[:decide.index("\n};")]
    assert "((_statement#1) find \"land 'GET OUT'\") < 0" in decide
    assert "[_carrier,true] call ITW_CLASH_HALParadrop_fnc_ShouldUse" in decide
    assert '_carrierGroup setVariable ["ITW_CLASH_HALParadropCargoGroup",_team];' in decide
    assert "spawn ITW_CLASH_HALParadrop_fnc_Execute" in decide
    assert "isPlayer _x" in decide
    # the paradrop step sits with the other GoSFAttack repairs, before compile
    assert source.index('"GoSFAttack-air-insertion-paradrop"') < source.index(
        "ITW_CLASH_HALNativeSF_fnc_GoSFAttackPatched = compile _attackSource;"
    )
