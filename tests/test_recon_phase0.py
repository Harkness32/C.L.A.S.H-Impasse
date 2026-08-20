from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def recon() -> str:
    return text("ITW_CLASH_ReconObserver.sqf")


def test_recon_phase0_is_server_wired_and_fail_open():
    init = text("init.sqf")
    source = recon()
    assert 'execVM "ITW_CLASH_ReconObserver.sqf"' in init
    assert "if (!isServer) exitWith {};" in source
    assert 'isNil "HAL_GoRecon"' in source
    assert 'isNil "HAL_GoDefRecon"' in source
    assert "baseline HAL recon retained" in source


def test_recon_phase0_semantic_sof_families_are_explicit():
    source = recon().lower()
    for token in ["ranger", "seal", "fsb", "oss", "viper"]:
        assert f'"{token}"' in source
    assert "itw_clash_reconsofmanual" in source
    assert "itw_clash_reconsofexactclasses" in source
    assert "floor ((count _alive) / 2) + 1" not in source
    assert "ceil ((count _alive) * 0.5)" not in source


def test_recon_phase0_sof_is_presence_based_and_latched():
    source = recon()
    lower = source.lower()

    # Any recognized SOF presence is enough: hunter-killer teams, sniper/spotter
    # pairs, attachments, mixed SOF/conventional elements, and casualty remnants
    # are all allowed to remain dedicated recon assets.
    assert "private _isSOF = _bestCount > 0;" in source
    assert '[true,"exact-class",count _exactMatched,count _alive,_classes]' in source
    assert "presence, not percentage" in lower
    assert '"mixed-sof"' in source

    # Positive identity persists for the group's lifetime. Manual policy is
    # evaluated before the latch so an explicit deny remains authoritative.
    assert '"ITW_CLASH_ReconSOFLatched"' in source
    assert '"ITW_CLASH_ReconSOFLatchedFamily"' in source
    manual_pos = source.index('ITW_CLASH_ReconSOFManual')
    latch_check_pos = source.index('ITW_CLASH_ReconSOFLatched",false')
    assert manual_pos < latch_check_pos


def test_recon_phase0_new_sof_presence_is_removed_from_native_norecon_filter():
    source = recon()
    assert "private _sofManaged = [];" in source
    assert "_sofManaged pushBack _group;" in source
    assert "_noRecon = _noRecon - _sofManaged;" in source


def test_recon_phase0_recognizes_vanilla_csats_viper_class_family():
    source = recon().lower()
    assert "itw_clash_reconsofclassprefixes" in source
    assert '["viper",["o_v_"]]' in source
    assert "(_class find _x) == 0" in source
    # Keep Viper recognition family-based rather than enumerating individual
    # TL/JTAC/medic/etc. classes so both hex and ghex vanilla variants resolve.
    assert "o_v_soldier_tl_hex_f" not in source
    assert "o_v_soldier_jtac_ghex_f" not in source


def test_recon_phase0_wraps_native_hal_recon_instead_of_reimplementing_it():
    source = recon()
    assert "ITW_CLASH_Recon_fnc_NativeGoRecon = HAL_GoRecon;" in source
    assert "ITW_CLASH_Recon_fnc_NativeGoDefRecon = HAL_GoDefRecon;" in source
    assert "HAL_GoRecon = {" in source
    assert "HAL_GoDefRecon = {" in source
    assert "_this call ITW_CLASH_Recon_fnc_NativeGoRecon" in source
    assert "_this call ITW_CLASH_Recon_fnc_NativeGoDefRecon" in source


def test_recon_phase0_hard_blocks_non_sof_and_unwinds_hal_bookkeeping():
    source = recon()
    assert '"blocked-nonsof"' in source
    assert '_group setVariable ["Busy" + str _group,false];' in source
    assert '"RydHQ_RecDefSpot"' in source
    assert '(_hq getVariable ["RydHQ_RecDefSpot",[]]) - [_group]' in source
    assert '"RydHQ_NoRecon"' in source


def test_recon_phase0_does_not_force_sof_into_recon_only_duty():
    source = recon()
    assert "RydHQ_ROnly" not in source
    assert 'setVariable ["RydHQ_ReconG"' not in source
    assert 'setVariable ["RydHQ_SpecForG"' not in source
    assert '"sof-native-specfor-excluded"' in source


def test_recon_phase0_is_observer_only_with_respect_to_impasse_economy():
    source = recon()
    forbidden = [
        "ITW_AtkSpawnVeh",
        "ITW_TICKET_REDUCE",
        "ITW_VEH_COUNT_INCR",
        "ITW_AtkQueueReconstitution",
        "createUnit",
        "createVehicle",
    ]
    for token in forbidden:
        assert token not in source


def test_recon_phase0_emits_assignment_contact_intel_and_outcome_telemetry():
    source = recon()
    for token in [
        '"sof-detected"',
        '"assigned"',
        '"contact"',
        '"intel-gained"',
        '"complete"',
        '"aborted"',
        '"wiped"',
    ]:
        assert token in source
    assert "knowsAbout _target" in source
    assert '"RydHQ_KnEnemies"' in source


def test_recon_phase0_boot_banner_describes_authority_boundary_and_sof_policy():
    source = recon()
    assert "recon-phase0-ready" in source
    assert "sofOnly=true" in source
    assert "nativeHAL=true" in source
    assert "spawning=false" in source
    assert "requisition=false" in source
    assert "presenceBased=true" in source
    assert "latched=true" in source
