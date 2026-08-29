from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def mission(name: str) -> str:
    return text(MISSION / name)


def test_impasse_reconstitution_queue_is_side_tagged_and_consumed_per_side():
    source = mission("ITW_Attack.sqf")

    assert '["_side",sideUnknown]' in source
    assert "ITW_AtkReconstitutionTransportContexts = createHashMap" in source
    assert "toUpperANSI str _side,_reconstitutionContext" in source
    assert 'private _requestSide = _x param [6,_enemySide];' in source
    assert 'private _request = [_side] call ITW_AtkNextReconstitution;' in source
    assert "private _activeFrontObjective = !(" in source
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in source
    assert '"no-active-front-objective"' in source
    assert '"no-side-forward-fob"' in source

    # A credit on the other commander must not suppress this side's normal spawn.
    spawn_gate = source[source.index("//// Infantry AI Spawner ////"):]
    assert 'private _requestSide = _x param [' in spawn_gate
    assert '_requestSide == _side' in spawn_gate


def test_blufor_hal_groups_capture_original_archetype_and_pause_only_during_recovery():
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    assert 'getVariable ["ITW_CLASH_Archetype",[]]' in dual
    assert '(units _group) apply {toLowerANSI typeOf _x}' in dual
    assert '"ITW_CLASH_Lineage"' in dual
    assert '[_group] call ITW_CLASH_DualHAL_fnc_GroupId' in dual

    sync = dual[dual.index("ITW_CLASH_DualHAL_fnc_SyncIncluded = {"):
                dual.index("ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives = {")]
    assert "ITW_CLASH_DualHALBLUFORGroups select" in sync
    assert "ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup" in sync
    assert 'RydHQB_Included = +_blu;' in sync


def test_blufor_exhaustion_enters_same_withdrawal_and_reconstitution_ledger():
    clash = mission("ITW_CLASH.sqf")

    audit = clash[clash.index("ITW_CLASH_fnc_AuditWithdrawals = {"):
                  clash.index("ITW_CLASH_fnc_CancelWithdrawals = {")]
    assert "ITW_CLASH_DualHALBLUFORGroups" in audit
    assert 'getVariable ["ITW_CLASH_DualHALManaged",false]' in audit
    assert '(_alive findIf {isPlayer _x}) >= 0' in audit
    assert 'vehicle _x != _x' in audit
    assert 'side _group' in audit
    assert 'call ITW_AtkQueueReconstitution;' in audit

    # Vehicle crews are explicitly not converted into infantry reconstitution credits.
    assert 'vehicle _x != _x || {!(_x isKindOf "CAManBase")}' in audit


def test_gtfo_uses_forward_fob_and_persists_commander_b_constraints():
    gtfo = mission("ITW_CLASH_GTFO.sqf")
    native_rest = text(HAL / "GoRest.sqf")

    assert 'getVariable ["ITW_CLASH_DualHALManaged",false]' in gtfo
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in gtfo
    assert '"ITW_CLASH_GTFO_GroupRestDecoy"' in gtfo
    assert "ITW_CLASH_GTFO_fnc_SetPersistentConstraints" in gtfo
    assert 'private _prefix = if (_isPlayerCommander) then {"RydHQB_"} else {"RydHQ_"};' in gtfo
    for token in ['["NoDef","RydHQ_NoDef"]',
                  '["NoAttack","RydHQ_NoAttack"]',
                  '["NoRecon","RydHQ_NoRecon"]',
                  '["Exhausted","RydHQ_Exhausted"]']:
        assert token in gtfo

    assert 'getVariable ["ITW_CLASH_GTFO_GroupRestDecoy",objNull]' in native_rest
    assert '_HQ getVariable ["RydHQ_RestDecoy",objNull]' in native_rest


def test_gtfo_bookkeeping_and_runtime_are_commander_aware_for_blufor():
    bookkeeping = mission("ITW_CLASH_GTFO_Bookkeeping.sqf")
    runtime = mission("ITW_CLASH_GTFO_Runtime.sqf")

    assert "ITW_CLASH_GTFOBookkeepingVersion = 2;" in bookkeeping
    assert "ITW_CLASH_fnc_GetCommanderForGroup" in bookkeeping
    assert "ITW_CLASH_GTFO_fnc_SetPersistentConstraints" in bookkeeping

    assert "ITW_CLASH_GTFORuntimeVersion = 3;" in runtime
    assert "ITW_CLASH_GTFO_fnc_IsTrackedWithdrawal" in runtime
    assert 'getVariable ["ITW_CLASH_DualHALManaged",false]' in runtime
    assert "ITW_CLASH_GTFO_fnc_GetCommander" in runtime
    assert "ITW_CLASH_Withdrawals getOrDefault" in runtime
    assert "} forEach _watchGroups;" in runtime
    assert "[[_group,_hq,true],HAL_GoRest] call RYD_Spawn;" in runtime


def test_casevac_and_ground_medevac_use_casualty_side_context_and_enemy_relationship():
    casevac = mission("ITW_CLASH_CASEVAC.sqf")
    ground = mission("ITW_CLASH_GroundMEDEVAC.sqf")
    manager = mission("ITW_CLASH_GroundMEDEVAC_Manager.sqf")

    assert "ITW_CLASH_CASEVAC_Version = 2;" in casevac
    assert "ITW_AtkReconstitutionTransportContexts" in casevac
    assert 'toUpperANSI str _recoverySide' in casevac
    assert '(_groupSide getFriend (side _x)) < 0.6' in casevac
    assert '"FORWARD_AIR"' in casevac
    assert "ITW_ATTACK_AIR_F" in casevac
    assert "ITW_ATTACK_AIR_E" in casevac

    assert "ITW_CLASH_GroundMEDEVAC_Version = 2;" in ground
    assert "ITW_AtkReconstitutionTransportContexts" in ground
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in ground
    assert '(_groupSide getFriend (side _x)) < 0.6' in ground
    assert '_originalObjective,side _group' in manager
    assert 'count _survivors,_spawnInfo,side _group' in manager


def test_blufor_reconstitution_handoff_returns_to_commander_b_not_enemy_callback():
    runtime = mission("ITW_CLASH_RuntimePatch.sqf")
    transit = mission("ITW_CLASH_ReconstitutionTransitFix.sqf")

    assert "ITW_CLASH_RuntimePatchVersion = 5;" in runtime
    assert 'side _group == ITW_PlayerSide' in runtime
    assert "ITW_CLASH_DualHAL_fnc_RegisterGroup" in runtime
    assert '"reconstitution-handoff-blufor"' in runtime

    callback = transit[transit.index("ITW_CLASH_fnc_AcknowledgeReconstitution"):]
    assert 'side _group == ITW_EnemySide' in callback
    assert "ITW_EnemyGroupCallback" in callback


def test_bootstrap_accepts_the_symmetric_runtime_versions():
    bootstrap = mission("ITW_CLASH_Bootstrap.sqf")
    assert "if (_patchVersion != 5" in bootstrap
    assert "if (_gtfoVersion != 2" in bootstrap
    assert "if (_gtfoBookkeepingVersion != 2" in bootstrap
