from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_front_routing_phase0_is_wired_after_generation_and_commander_parity():
    init = mission("init.sqf")
    source = mission("ITW_CLASH_FrontRouting.sqf")

    assert 'fileExists "ITW_CLASH_FrontRouting.sqf"' in init
    assert 'compile preprocessFileLineNumbers\n                    "ITW_CLASH_FrontRouting.sqf"' in init
    assert init.index('ITW_CLASH_ForceGeneration.sqf') < init.index('ITW_CLASH_FrontRouting.sqf')
    assert 'ITW_CLASH_CommanderParity_fnc_GetCommanderForSide' in source
    assert 'ITW_CLASH_FrontRoutingVersion = 1;' in source
    assert 'ITW_CLASH_FrontRoutingShadowMode = true;' in source


def test_front_routing_uses_side_symmetric_impasse_attack_source_fobs():
    source = mission("ITW_CLASH_FrontRouting.sqf")

    assert 'ITW_ATTACK_LAND_F' in source
    assert 'ITW_ATTACK_LAND_E' in source
    assert 'ITW_OBJ_ATTACKS' in source
    assert 'ITW_CLASH_Generation_fnc_ActiveObjectiveIds' in source
    assert 'ITW_CLASH_Generation_fnc_BaseSpawn' in source
    assert 'forEach [ITW_PlayerSide,ITW_EnemySide]' in source
    assert 'pushBackUnique _candidateBase' in source
    assert '"primaryBase"' in source
    assert '"selectedBase"' in source
    assert '"candidateCount"' in source


def test_front_routing_has_sticky_health_aware_lane_selection():
    source = mission("ITW_CLASH_FrontRouting.sqf")

    for state in ["HEALTHY", "CONTESTED", "DEGRADED", "INTERDICTED"]:
        assert f'"{state}"' in source
    assert 'ITW_CLASH_FrontRouting_fnc_SetRouteState' in source
    assert 'ITW_CLASH_FrontRouting_fnc_SelectCandidate' in source
    assert '!= "INTERDICTED"' in source
    assert '"sticky-alternate"' in source
    assert '"primary-interdicted-alternate-selected"' in source
    assert 'ITW_CLASH_FrontRoutingSelections set [_frontId,_selection];' in source
    assert '_hq setVariable ["ITW_CLASH_FrontRoutingSelections",_published];' in source


def test_front_routing_phase0_has_no_spawn_or_tactical_movement_authority():
    source = mission("ITW_CLASH_FrontRouting.sqf")

    for forbidden in [
        "createGroup",
        "createVehicle",
        "createUnit",
        "ITW_AtkSpawnVeh",
        "addWaypoint",
        "doMove",
        "moveTo",
        "setPosATL",
        "setPosASL",
        "setPos ",
        "HAL_Go",
    ]:
        assert forbidden not in source

    assert "noSpawnAuthority=true" in source
    assert '"shadow",ITW_CLASH_FrontRoutingShadowMode' in source


def test_native_impasse_initial_objective_population_is_untouched():
    attack = mission("ITW_Attack.sqf")

    assert "private _populateSquadCnt = 3;" in attack
    assert "if (_populateObjectives) then {" in attack
    assert "[_group,_obj] call ITW_AtkAddInfantryGroup;" in attack
    assert "ITW_CLASH_InitialSeed" not in attack
