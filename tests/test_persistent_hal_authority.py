from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
NR6 = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def mission(name: str) -> str:
    return text(MISSION / name)


def test_preinit_filters_hal_managed_opfor_from_impasse_infantry_manager():
    preinit = mission("preInit.sqf")
    authority_preinit = mission("ITW_CLASH_InfantryAuthorityPreInit.sqf")

    assert '"ITW_AtkGetInfantryGroups"' in preinit
    assert "ITW_CLASH_InfantryAuthorityPreInit.sqf" in preinit
    assert "ITW_CLASH_AtkGetInfantryGroups_Baseline = ITW_AtkGetInfantryGroups;" in authority_preinit
    assert 'missionNamespace getVariable ["ITW_CLASH_LiveEnabled",false]' in authority_preinit
    assert '_group getVariable ["ITW_CLASH_Managed",false]' in authority_preinit
    assert '["ITW_AtkGetInfantryGroups"] call SKL_fnc_CompileFinal' in authority_preinit
    assert "ITW_AtkGetInfantryGroups = ITW_CLASH_AtkGetInfantryGroups_Baseline;" in authority_preinit


def test_persistent_authority_suppresses_impasse_tactical_writers_but_not_merge_handoff():
    authority = mission("ITW_CLASH_InfantryAuthority.sqf")

    for writer in [
        "engage-infantry",
        "stuck-handler",
        "infantry-manager-garrison",
        "infantry-manager-waypoints",
        "infantry-manager-move-up",
        "infantry-move-up",
    ]:
        assert f'"{writer}"' in authority

    # Merge destroys the source group immediately, so it remains a legitimate
    # lifecycle handoff instead of a suppressed tactical writer.
    assert '"infantry-manager-merge"' not in authority
    assert "ITW_CLASH_fnc_ObserveWriter_InfantryAuthorityBase" in authority
    assert '"writer-suppressed"' in authority


def test_defend_phase_keeps_hal_ownership_while_zone_transition_keeps_base_lifecycle():
    authority = mission("ITW_CLASH_InfantryAuthority.sqf")
    start = authority.index("ITW_CLASH_fnc_ObserveLifecycle = {")
    end = authority.index("ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints", start)
    lifecycle = authority[start:end]

    assert '"defend-start"' in lifecycle
    assert '"defend-done"' in lifecycle
    assert "ITW_CLASH_fnc_ResetAnchors" in lifecycle
    assert "ITW_CLASH_fnc_WouldReleaseAll" in lifecycle
    assert "ITW_CLASH_fnc_ReleaseAll" not in lifecycle
    assert "ITW_CLASH_fnc_ObserveLifecycle_InfantryAuthorityBase" in lifecycle


def test_native_hal_sf_fix_matches_the_three_known_source_defects_and_recompiles_runtime_globals():
    fix = mission("ITW_CLASH_HALNativeSFFix.sqf")
    idle = text(NR6 / "SFIdleOrd.sqf")
    attack = text(NR6 / "GoSFAttack.sqf")

    # Keep the hotpatch tied to the exact vendored NR6 source we audited. If the
    # upstream source changes, this test forces the runtime signatures to be
    # reviewed instead of silently patching a different HAL build.
    assert "while {((_isWater) or (_cnt > 100))} do" in idle
    assert '_obj = _HQ getVariable ["RydHQ_Obj",_ldr];' in attack
    assert "_posXWP3 = (_posXWP4 + (_BEnemyPos select 0))/2;" in attack
    assert "_posYWP3 = (_posYWP4 + (_BEnemyPos select 1))/2;" in attack

    assert "while {_isWater && {_cnt < 100}} do" in fix
    assert '_obj = _HQ getVariable [""RydHQ_Obj"",leader _HQ];' in fix
    assert "_posXWP4 = (_posXWP4 + (_BEnemyPos select 0))/2;" in fix
    assert "_posYWP4 = (_posYWP4 + (_BEnemyPos select 1))/2;" in fix
    assert "HAL_SFIdleOrd = compile _idleSource;" in fix
    assert "HAL_GoSFAttack = compile _attackSource;" in fix
    assert "native-sf-fix-ready" in fix


def test_sof_bootstrap_keeps_observer_surfaces_mutable_and_gates_full_authority_on_preinit():
    bootstrap = mission("ITW_CLASH_SOFDoctrineBootstrap.sqf")

    assert '"ITW_CLASH_fnc_ObserveWriter"' in bootstrap
    assert '"ITW_CLASH_fnc_ObserveLifecycle"' in bootstrap
    assert '"ITW_CLASH_fnc_ObserveWriter_InfantryAuthorityBase"' in bootstrap
    assert '"ITW_CLASH_fnc_ObserveLifecycle_InfantryAuthorityBase"' in bootstrap
    assert '"ITW_CLASH_InfantryAuthorityPreInitReady"' in bootstrap
    assert "if (_infPreInitReady && {_infExists && {_infChars > 0}})" in bootstrap
    assert "ITW_CLASH_HALNativeSFFix.sqf" in bootstrap
    assert "native-sf-fix-scheduled" in bootstrap
