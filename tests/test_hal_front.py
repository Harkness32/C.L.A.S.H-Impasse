from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal"
ADD = ROOT / "CLASH HAL Additions" / "addons" / "clash_hal_additions"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def front() -> str:
    return text(MISSION / "ITW_CLASH_HALFront.sqf")


def function(source: str, name: str) -> str:
    start = source.index(name + " = {")
    return source[start:source.index("\n};", start)]


def test_hal_uses_the_front_the_way_the_module_relies_on():
    # Dispatcher skips threats outside the front, chases are recalled, and
    # artillery targets are filtered to it and sorted by distance.
    hac = text(NR6 / "HAC_fnc.sqf")
    assert '_fr = _HQ getvariable ["RydHQ_Front",locationNull];' in hac
    assert "if not ((getPosATL (vehicle (leader _x))) in _fr) then {_sum = 0}" in hac
    assert "if not ((getPosATL _wtgt) in _fr) then" in hac
    assert '"ASCEND",{((getPosATL (vehicle _x)) in _fr)}] call BIS_fnc_sortBy;' in hac
    # The SF raid routine never reads the front, so SOF still go deep.
    hac2 = text(NR6 / "HAC_fnc2.sqf")
    raid = hac2[hac2.index("_SFcount = {"):hac2.index('"RydHQ_LRelocating"')]
    assert "RydHQ_Front" not in raid
    # HAL's own Front.sqf (trigger -> location) runs before the HQ loops start.
    init = text(ADD / "hal" / "RydHQInit.sqf")
    assert init.index('(RYD_Path + "Front.sqf")') < init.index("A_HQSitRep] call RYD_Spawn")


def test_front_is_loaded_after_force_generation():
    init = text(MISSION / "init.sqf")
    load = init.index('call compile preprocessFileLineNumbers "ITW_CLASH_HALFront.sqf"')
    assert init.index('"ITW_CLASH_ForceGeneration.sqf"') < load
    assert '_forceGenerationReady isEqualTo true && {fileExists "ITW_CLASH_HALFront.sqf"}' in init


def test_front_covers_everything_a_side_has_in_play():
    source = front()
    points = function(source, "ITW_CLASH_HALFront_fnc_Points")
    assert "call ITW_CLASH_Generation_fnc_ActiveObjectiveIds" in points
    assert '[_side,"FRONT","FORWARD",_objectivePos] call ITW_CLASH_Generation_fnc_Resolve;' in points
    assert '"forwardPosition"' in points
    assert 'if (ITW_CLASH_HALFrontIncludeRear) then {' in points
    assert '"rearPosition"' in points
    assert '_hq getVariable ["RydHQ_ArtG",[]]' in points
    box = function(source, "ITW_CLASH_HALFront_fnc_Box")
    assert "} forEach (_objectives + _forward + _rear + _artillery);" in box
    assert "ITW_CLASH_HALFrontMargin" in box
    assert 'missionNamespace getVariable ["ITW_CLASH_HALFrontMargin",1500]' in source
    assert 'missionNamespace getVariable ["ITW_CLASH_HALFrontIncludeRear",true]' in source


def test_front_leashes_dispatch_but_keeps_enemy_knowledge():
    source = front()
    update = function(source, "ITW_CLASH_HALFront_fnc_Update")
    assert '_hq setVariable ["RydHQ_Front",_front];' in update
    assert "_front setRectangular true;" in update
    assert "FrontA" not in source.replace("RydHQ_FrontA stays off", "")
    # Self-check with the engine's `in`; a front that misses its own points is dropped.
    assert "select {!(_x in _front)};" in update
    assert '_hq setVariable ["RydHQ_Front",locationNull];' in update
    assert update.index("select {!(_x in _front)};") < update.index('_hq setVariable ["RydHQ_Front",_front];')


def test_front_waits_for_hal_to_finish_its_own_front_setup():
    source = front()
    loop = source[source.index('scriptName "ITW_CLASH_HALFront";'):]
    assert '(_hq getVariable ["RydHQ_Cyclecount",0]) >= 1' in loop
    assert '} forEach ["ITW_CLASH_HALHQ","ITW_CLASH_BLUFORHQ"];' in loop
