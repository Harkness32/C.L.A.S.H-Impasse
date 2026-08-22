from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def gtfo() -> str:
    return text(MISSION / "ITW_CLASH_GTFO.sqf")


def bookkeeping() -> str:
    return text(MISSION / "ITW_CLASH_GTFO_Bookkeeping.sqf")


def runtime() -> str:
    return text(MISSION / "ITW_CLASH_GTFO_Runtime.sqf")


def bootstrap() -> str:
    return text(MISSION / "ITW_CLASH_Bootstrap.sqf")


def test_gtfo_is_a_bridge_to_native_hal_withdrawal_rally_point():
    source = gtfo()
    native = text(HAL / "GoRest.sqf")

    assert '"RydHQ_RestDecoy"' in source
    assert '"RydHQ_RDChance",100' in source
    assert '"Land_HelipadEmpty_F"' in source
    assert "HAL_GoRest = {" not in source

    assert '"HQ_ord_withdraw"' in native
    assert "RYD_Smoke" in native
    assert "enableAttack false" in native
    assert "if (_attackAllowed) then {_unitG enableAttack true}" in native


def test_gtfo_replaces_direct_clash_tactical_withdrawal_with_state_and_constraints():
    source = gtfo()
    start = source.index("ITW_CLASH_fnc_OrderWithdrawal = {")
    end = source.index("ITW_CLASH_fnc_StartWithdrawal = {", start)
    order = source[start:end]

    for forbidden in [
        "addWaypoint",
        "setWaypointType",
        'setCombatMode "BLUE"',
        "enableAttack false",
        "setBehaviourStrong",
        "setSpeedMode",
        "ITW_CLASH_fnc_ClearGroupWaypoints",
    ]:
        assert forbidden not in order

    assert '"RydHQ_Exhausted"' in order
    assert "ITW_CLASH_GTFO_fnc_ApplyConstraints" in order
    assert '"hal-withdrawal"' in order


def test_gtfo_start_keeps_group_hal_managed_and_never_uses_old_release_preemption():
    source = gtfo()
    start = source.index("ITW_CLASH_fnc_StartWithdrawal = {")
    end = source.index("ITW_CLASH_fnc_CancelWithdrawals = {", start)
    start_fn = source[start:end]

    assert 'setVariable ["ITW_CLASH_GTFO",true]' in start_fn
    assert 'setVariable ["ITW_CLASH_GTFO_State","HAL_WITHDRAWAL"]' in start_fn
    assert "ITW_CLASH_Withdrawals set" in start_fn
    assert "ITW_CLASH_fnc_BeginRelease" not in start_fn
    assert "ITW_CLASH_fnc_FinishRelease" not in start_fn
    assert 'setVariable ["Break",true]' not in start_fn
    assert 'setVariable ["RydHQ_MIA",true]' not in start_fn


def test_gtfo_bookkeeping_retires_only_stale_defense_state_after_successful_transition():
    source = bookkeeping()
    assert "ITW_CLASH_fnc_StartWithdrawal_GTFOStateBase = ITW_CLASH_fnc_StartWithdrawal" in source
    base_call = source.index("private _result = _this call ITW_CLASH_fnc_StartWithdrawal_GTFOStateBase;")
    retire_call = source.index("ITW_CLASH_GTFO_fnc_RetirePreviousTaskState", base_call)
    assert base_call < retire_call
    assert 'setVariable ["Defending",false]' in source
    for token in ["RydHQ_DefSpot", "RydHQ_Def", "RydHQ_DefRes", "RydHQ_RecDefSpot"]:
        assert token in source
    for forbidden in [
        "addWaypoint",
        "setWaypoint",
        'setCombatMode "BLUE"',
        "enableAttack false",
        "setBehaviourStrong",
        "setSpeedMode",
        'setVariable ["Break",true]',
    ]:
        assert forbidden not in source


def test_gtfo_support_corridor_is_captured_per_group_and_immutable_during_foot_withdrawal():
    source = gtfo()
    assert '"ITW_CLASH_GTFO_Destination"' in source
    assert '"ITW_CLASH_GTFO_EgressObjective"' in source
    assert '"ITW_CLASH_GTFO_Source"' in source
    assert "each GTFO squad keeps the immutable support" in source
    assert '"corridor-divergence"' in source


def test_gtfo_constraints_keep_withdrawing_groups_out_of_hal_task_pools():
    source = gtfo()
    for token in [
        '"RydHQ_NoDef"',
        '"RydHQ_NoAttack"',
        '"RydHQ_NoRecon"',
        '"RydHQ_Exhausted"',
    ]:
        assert token in source
    assert '"gtfo-hal-managed"' in source


def test_recovery_takes_hal_ownership_only_after_shared_boarding_reports_success():
    source = runtime()
    assert "ITW_CLASH_GTFO_fnc_BoardBase = ITW_CLASH_EvacBoarding_fnc_Board" in source
    assert "private _result = _this call ITW_CLASH_GTFO_fnc_BoardBase;" in source
    result_pos = source.index("private _result = _this call ITW_CLASH_GTFO_fnc_BoardBase;")
    handoff_pos = source.index("ITW_CLASH_GTFO_fnc_RecoveryOwned", result_pos)
    assert result_pos < handoff_pos
    assert '"gtfo-recovery-handoff-ready"' in source
    assert "ownership=postBoarding" in source


def test_gtfo_runtime_hard_blocks_recon_without_reimplementing_recon():
    source = runtime()
    assert "ITW_CLASH_GTFO_fnc_ReconBase = HAL_GoRecon" in source
    assert "ITW_CLASH_GTFO_fnc_DefReconBase = HAL_GoDefRecon" in source
    assert '"recon-blocked-gtfo"' in source
    assert '_group getVariable ["ITW_CLASH_GTFO",false]' in source
    assert "_this call ITW_CLASH_GTFO_fnc_ReconBase" in source
    assert "_this call ITW_CLASH_GTFO_fnc_DefReconBase" in source


def test_gtfo_arrival_radius_covers_native_restdecoy_jitter_and_logs_native_rest_owner():
    source = runtime()
    assert "ITW_CLASH_GTFO_ArrivalRadius = 160;" in source
    assert "ITW_CLASH_WithdrawalArrivalRadius max ITW_CLASH_GTFO_ArrivalRadius" in source
    assert '"native-rest-active"' in source
    assert '"Resting" + str _group' in source
    assert "waypointPosition [_group,_wpIndex]" in source


def test_gtfo_runtime_removes_stale_hal_defensive_memberships_while_withdrawing():
    source = runtime()
    assert "ITW_CLASH_GTFORuntimeVersion = 2;" in source
    assert "ITW_CLASH_GTFO_fnc_ClearStaleHALRoles" in source
    for token in [
        '"RydHQ_Garrison"',
        '"RydHQ_DefSpot"',
        '"RydHQ_Def"',
        '"RydHQ_DefRes"',
        '"RydHQ_RecDefSpot"',
    ]:
        assert token in source
    assert '"hal-role-cleanup"' in source


def test_gtfo_restart_uses_native_break_and_gorest_without_blind_busy_clear():
    source = runtime()
    restart_start = source.index("ITW_CLASH_GTFO_fnc_RequestNativeRestRestart = {")
    recon_start = source.index('[] spawn {\n    scriptName "ITW_CLASH_GTFO_ReconGuard";', restart_start)
    restart = source[restart_start:recon_start]

    assert 'setVariable ["Break",true]' in restart
    assert "HAL_GoRest" in restart
    assert "RYD_Spawn" in restart
    assert '"rest-restart-dispatched"' in restart
    assert 'setVariable ["Busy" + str _group,false]' not in restart
    assert "ITW_CLASH_GTFO_RestRestartBreakWait = 45;" in source


def test_gtfo_stall_sampler_persists_first_sample_before_timing_a_stall():
    source = runtime()
    assert "ITW_CLASH_GTFORuntimeProgress = createHashMap;" in source
    assert 'private _sample = ITW_CLASH_GTFORuntimeProgress getOrDefault [_id,[]];' in source
    assert 'if (_sample isEqualTo []) then {' in source
    assert 'ITW_CLASH_GTFORuntimeProgress set [_id,[time,_distance]];' in source
    assert "ITW_CLASH_GTFO_RestRestartGrace = 90;" in source
    assert "ITW_CLASH_GTFO_RestRestartProgress = 25;" in source


def test_bootstrap_keeps_only_gtfo_authority_surface_mutable_until_bridge_install():
    source = bootstrap()
    assert "ITW_CLASH_PersistentDeferredFinalizers" in source
    for token in [
        '"ITW_CLASH_fnc_ClassifyGroup"',
        '"ITW_CLASH_fnc_ApplyObjectiveDoctrine"',
        '"ITW_CLASH_fnc_GetEgressPoint"',
        '"ITW_CLASH_fnc_OrderWithdrawal"',
        '"ITW_CLASH_fnc_StartWithdrawal"',
        '"ITW_CLASH_fnc_CancelWithdrawals"',
    ]:
        assert token in source
    assert 'private _gtfoPath = "ITW_CLASH_GTFO.sqf";' in source
    assert 'private _gtfoBookkeepingPath = "ITW_CLASH_GTFO_Bookkeeping.sqf";' in source
    assert "ITW_CLASH_PersistentDeferredFinalizers = [];" in source
    assert '"ITW_CLASH_fnc_StartWithdrawal_GTFOStateBase"' in source
    assert '"CLASH BOOT | gtfo-bridge-loaded' in source


def test_init_wires_late_gtfo_runtime_only_after_successful_bootstrap():
    source = text(MISSION / "init.sqf")
    assert 'missionNamespace getVariable ["ITW_CLASH_BootstrapReady",false]' in source
    assert 'execVM "ITW_CLASH_GTFO_Runtime.sqf"' in source
