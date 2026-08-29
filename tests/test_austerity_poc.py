from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_austerity_poc_rewards_completed_player_hal_jobs_with_1000_cash():
    server = text("ITW_CLASH_Austerity.sqf")

    assert "ITW_CLASH_AusterityVersion = 1;" in server
    assert "ITW_CLASH_AusterityTaskReward = 1000;" in server
    assert "ITW_CLASH_AusterityCash = createHashMap;" in server
    assert "ITW_CLASH_AusterityRewardedJobs = createHashMap;" in server
    assert 'scriptName "ITW_CLASH_AusterityRewardObserver"' in server
    assert 'getOrDefault ["state",""]' in server
    assert '== "COMPLETED"' in server
    assert 'getOrDefault ["participants",[]]' in server
    assert '"hal-task-completed:" + _jobId' in server
    assert "PLAYER_TASK_REWARD_AUTHORIZED" not in server
    assert "cashPerKill" not in server
    assert "xp" not in server.lower()


def test_austerity_cash_is_server_owned_and_projected_to_requesting_client():
    server = text("ITW_CLASH_Austerity.sqf")
    client = text("ITW_CLASH_AusterityClient.sqf")

    assert "allPlayers select" in server
    assert "getPlayerUID _x == _uid" in server
    assert "ITW_CLASH_AusterityClient_fnc_ReceiveCash" in server
    assert "owner _player" in server
    assert "remoteExecutedOwner != owner _player" in server

    assert "ITW_CLASH_AusterityCashLocal = 0;" in client
    assert "remoteExecutedOwner != 2" in client
    assert "ITW_CLASH_Austerity_fnc_RequestSync" in client
    assert '"ITW_CLASH_AUSTERITY_HUD" call BIS_fnc_rscLayer' in client
    assert 'cutRsc ["ITW_CLASH_AusterityHud","PLAIN",0,false]' in client


def test_austerity_hud_uses_existing_rsc_titles_and_koth_style_cash_panel():
    dialogs = text("dialogs.hpp")
    init = text("init.sqf")
    init_player = text("initPlayerLocal.sqf")

    assert "class ITW_CLASH_AusterityHud" in dialogs
    assert "ITW_CLASH_AusterityHudDisplay" in dialogs
    assert "idc = 95503;" in dialogs
    assert 'text = "$0";' in dialogs
    assert "EtelkaMonospaceProBold" in dialogs

    assert "ITW_CLASH_Austerity.sqf" in init
    assert init.index("ITW_CLASH_PlayerTaskSupport.sqf") < init.index(
        "ITW_CLASH_Austerity.sqf"
    )
    assert "ITW_CLASH_AusterityClient.sqf" in init_player

    assert "BN_KOTH_" not in text("ITW_CLASH_Austerity.sqf")
    assert "BN_KOTH_" not in text("ITW_CLASH_AusterityClient.sqf")
