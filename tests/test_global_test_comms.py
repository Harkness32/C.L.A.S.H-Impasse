from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def comms() -> str:
    return text("ITW_CLASH_TestComms.sqf")


def test_global_test_comms_is_wired_synchronously_and_fail_soft():
    init = text("init.sqf")
    assert 'fileExists "ITW_CLASH_TestComms.sqf"' in init
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_TestComms.sqf"' in init
    assert "test-comms-failed | continuing silently" in init
    assert "test-comms-missing | continuing silently" in init


def test_global_test_comms_uses_global_chat_and_global_radio_only():
    source = comms()
    assert 'remoteExecCall ["globalChat",0]' in source
    assert 'remoteExecCall ["globalRadio",0]' in source
    assert "globalChat _text" in source
    assert "globalRadio _sentence" in source
    assert "sideChat" not in source
    assert "sideRadio" not in source


def test_global_test_comms_reuses_hal_radio_assets_without_copying_audio():
    source = comms()
    assert "RydxHQ_AIC_MedReq" in source
    assert "RydxHQ_AIC_OrdConf" in source
    assert '"HAC_MedReq1"' in source
    assert '"HAC_OrdConf1"' in source
    assert 'configFile >> "CfgRadio"' in source
    assert ".ogg" not in source.lower()
    assert "playSound" not in source
    assert "say3D" not in source


def test_global_test_comms_is_observer_only_not_an_authority_wrapper():
    source = comms()
    assert "ITW_CLASH_Withdrawals getOrDefault" in source
    assert "ITW_CLASH_ReconActiveGroups getOrDefault" in source
    assert 'getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]' in source
    assert 'getVariable ["ITW_CLASH_CASEVAC_State",""]' in source
    forbidden = [
        "ITW_CLASH_fnc_OrderWithdrawal =",
        "ITW_CLASH_GroundMEDEVAC_fnc_Dispatch =",
        "ITW_CLASH_CASEVAC_fnc_Dispatch =",
        "HAL_GoRecon =",
        "HAL_GoDefRecon =",
        "createVehicle",
        "createUnit",
        "setWaypoint",
        "addWaypoint",
    ]
    for token in forbidden:
        assert token not in source


def test_recovery_request_announces_only_committed_inbound_states_with_cooldown():
    source = comms()
    assert "ITW_CLASH_TestCommsRecoveryRequestCooldown = 90;" in source
    assert 'if (_groundState isEqualTo "inbound" || {_casevacState isEqualTo "ground-inbound"})' in source
    assert 'if (_casevacState isEqualTo "inbound") then {_mode = "air"};' in source
    assert '"ground-inbound"' in source
    assert '"recovery-request"' in source
    assert "Command, requesting %2" in source
    assert "Survivors: %3" in source


def test_recon_tasking_announces_phase0_active_missions_and_viper_family():
    source = comms()
    recon_source = text("ITW_CLASH_ReconObserver.sqf").lower()
    assert "ITW_CLASH_ReconActiveGroups" in source
    assert 'getVariable ["ITW_CLASH_ReconSOFFamily","sof"]' in source
    assert "HAL: RECON TASKING" in source
    assert '"recon-tasking"' in source
    assert '["viper",["o_v_"]]' in recon_source


def test_test_comms_boot_banner_exposes_temporary_global_surface():
    source = comms()
    assert "test-comms-ready" in source
    assert "global=true" in source
    assert "halRadio=true" in source
    assert "observerOnly=true" in source
    assert "events=recovery-request,recon-tasking" in source
