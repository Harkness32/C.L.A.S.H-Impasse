"""The reward HUD (2026-10-31, Hark).

"I'd like to have their point rewards pop up as a plus and a money tab in the
bottom right", then concept A from the CLASH Reward HUD canvas with the centre
text "a bit smaller so they don't block any important info from the players".

The server owns the money and pays the draft Austerity prices: a flat bonus for
a finished job, a bounty for a kill. The client only draws what it is sent.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def code(name: str) -> str:
    text = (MISSION / name).read_text(encoding="utf-8")
    return re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


def body_of(source: str, name: str) -> str:
    start = source.index(f"{name} = {{")
    depth = 0
    i = source.index("{", start)
    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1
    raise AssertionError(name)


SERVER = code("ITW_CLASH_Austerity.sqf")
CLIENT = code("ITW_CLASH_AusterityClient.sqf")
DIALOGS = (MISSION / "dialogs.hpp").read_text(encoding="utf-8")


def test_both_halves_load():
    init = code("init.sqf")
    assert init.index('"ITW_CLASH_PlayerTaskSupport.sqf";') < init.index('"ITW_CLASH_Austerity.sqf";')
    assert '[] execVM "ITW_CLASH_AusterityClient.sqf";' in code("initPlayerLocal.sqf")


def test_job_pay_matches_the_draft_ranking():
    pay = {
        "TRANSPORT_LIFT": 1000,
        "LOGISTICS_AMMO_SLING": 500,
        "RECON_REACQUIRE_CONTACT": 300,
        "ARTILLERY_FIRE_MISSION": 100,
    }
    for job, amount in pay.items():
        assert f'["{job}",{amount}]' in SERVER, job
    assert "ITW_CLASH_AusterityRescuePay = 1500;" in SERVER
    assert '["CSAR_CREW","MEDEVAC_SEVERE","MEDEVAC_SQUAD"]' in SERVER


def test_every_finished_job_says_task_complete():
    # Hark: "finished jobs shouldn't say rescue, it should only say Task Complete"
    assert 'ITW_CLASH_AusterityJobLabel = "TASK COMPLETE";' in SERVER
    once = body_of(SERVER, "ITW_CLASH_Austerity_fnc_PayOnce")
    assert 'ITW_CLASH_AusterityJobLabel,"job"' in once
    for word in ["RESCUE COMPLETE", "TRANSPORT COMPLETE", "STRIKE COMPLETE", "AMMO DELIVERED"]:
        assert word not in SERVER


def test_each_job_pays_once_and_a_finished_job_is_the_only_trigger():
    once = body_of(SERVER, "ITW_CLASH_Austerity_fnc_PayOnce")
    assert once.index("getOrDefault [_key,false]") < once.index("ITW_CLASH_AusterityPaid set [_key,true];")
    jobs = body_of(SERVER, "ITW_CLASH_Austerity_fnc_SweepJobs")
    assert '(_job getOrDefault ["state",""]) != "COMPLETED"' in jobs
    rescues = body_of(SERVER, "ITW_CLASH_Austerity_fnc_SweepRescues")
    assert '(_demand getOrDefault ["state",""]) != "COMPLETED"' in rescues
    assert '_demand getOrDefault ["reservedGroup",grpNull]' in rescues


def test_a_finished_demand_keeps_the_group_that_gets_paid():
    complete = body_of(code("ITW_CLASH_PlayerDemandDispatch.sqf"), "ITW_CLASH_PlayerDemand_fnc_Complete")
    assert '_demand set ["reservedGroup",grpNull];' not in complete


def test_kills_pay_only_for_an_enemy_shot_by_a_player():
    killed = body_of(SERVER, "ITW_CLASH_Austerity_fnc_OnKilled")
    assert "ITW_CLASH_Austerity_fnc_WasEnemy" in killed
    assert "ITW_CLASH_Austerity_fnc_Shooter" in killed
    assert 'addMissionEventHandler ["EntityKilled",{_this call ITW_CLASH_Austerity_fnc_OnKilled}];' in SERVER
    enemy = body_of(SERVER, "ITW_CLASH_Austerity_fnc_WasEnemy")
    assert "side _owner == ITW_EnemySide" in enemy
    shooter = body_of(SERVER, "ITW_CLASH_Austerity_fnc_Shooter")
    assert "side group _shooter != ITW_PlayerSide" in shooter


def test_a_tracked_kill_is_tank_only_when_the_editor_says_so():
    bounty = body_of(SERVER, "ITW_CLASH_Austerity_fnc_Bounty")
    assert bounty.index("EdSubcat_Tanks") < bounty.index('isKindOf "Tank"')
    assert bounty.index("EdSubcat_APCs") < bounty.index('isKindOf "Car"')


def test_the_server_owns_the_money():
    assert "remoteExecutedOwner != owner _player" in body_of(SERVER, "ITW_CLASH_Austerity_fnc_RequestSync")
    receive = body_of(CLIENT, "ITW_CLASH_AusterityClient_fnc_ReceiveCash")
    assert "isRemoteExecuted && {remoteExecutedOwner != 2}" in receive
    assert "ITW_CLASH_AusterityCash" not in CLIENT.replace("ITW_CLASH_AusterityClientCash", "")


def test_the_tab_sits_bottom_right_and_only_after_the_server_answers():
    assert "class ITW_CLASH_RewardHud" in DIALOGS
    assert "#define ITW_CLASH_HUD_X (safezoneX + safezoneW - ITW_CLASH_HUD_W" in DIALOGS
    assert "#define ITW_CLASH_HUD_Y (safezoneY + safezoneH - ITW_CLASH_HUD_H" in DIALOGS
    assert 'font = "EtelkaMonospaceProBold";' in DIALOGS
    assert "colorText[] = {0.96,0.84,0.34,1};" in DIALOGS
    assert "ITW_CLASH_AusterityClient_fnc_ShowTab" in body_of(CLIENT, "ITW_CLASH_AusterityClient_fnc_ReceiveCash")
    startup = CLIENT[CLIENT.index('scriptName "ITW_CLASH_AusterityHudStartup"'):]
    assert "cutRsc" not in startup


def test_popups_stay_small_and_off_the_crosshair():
    assert "class ITW_CLASH_RewardPopup" in DIALOGS
    assert 'size = "0.01 * safeZoneH";' in DIALOGS
    kill = body_of(CLIENT, "ITW_CLASH_AusterityClient_fnc_KillPopup")
    assert "if (_big) then {3.6} else {2.9}" in kill
    assert "safezoneY + safezoneH * 0.535" in kill
    job = body_of(CLIENT, "ITW_CLASH_AusterityClient_fnc_JobPopup")
    assert "size='4.9'" in job
    assert "safezoneY + safezoneH * 0.233" in job


def test_a_display_name_cannot_break_the_structured_text():
    receive = body_of(CLIENT, "ITW_CLASH_AusterityClient_fnc_ReceiveCash")
    assert '_label regexReplace ["[<>&]",""]' in receive


def test_large_balances_do_not_turn_into_scientific_notation():
    assert "toFixed 0" in body_of(CLIENT, "ITW_CLASH_AusterityClient_fnc_FormatNumber")
