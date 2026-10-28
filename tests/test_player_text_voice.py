"""One voice for player text (2026-10-28, Hark).

"Can we homogenise some of the text amongst all the job descriptions and player
facing stuff? alot of it has a bunch of different tones", with the model line
"Location is marked. Destroy the contact, crew liquidation is not necessary.
Friendlies near the target may engage." And: "\\n doesn't work for arma text".
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"

PLAYER_TEXT = [
    "ITW_CLASH_CSAR.sqf",
    "ITW_CLASH_PlayerArtilleryTasks.sqf",
    "ITW_CLASH_PlayerDemandDispatch.sqf",
    "ITW_CLASH_PlayerDemandNativeInterceptors.sqf",
    "ITW_CLASH_PlayerEmploymentMenu.sqf",
    "ITW_CLASH_PlayerGarageDeployment.sqf",
    "ITW_CLASH_PlayerSquadEvac.sqf",
    "ITW_CLASH_PlayerTaskRequestArtillery.sqf",
    "ITW_CLASH_PlayerTaskRequestMenu.sqf",
    "ITW_CLASH_PlayerTaskRequestRecon.sqf",
    "ITW_CLASH_PlayerTaskRequestStrike.sqf",
    "ITW_CLASH_PlayerTaskRequestTransport.sqf",
    "ITW_CLASH_PlayerTaskRequests.sqf",
    "ITW_CLASH_PlayerTaskStateHardening.sqf",
    "ITW_CLASH_PlayerTaskSupport.sqf",
]


def code(name: str) -> str:
    text = (MISSION / name).read_text(encoding="utf-8")
    return re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


def player_strings(name: str) -> list[str]:
    strings = []
    for line in code(name).splitlines():
        if re.search(r"diag_log|_fnc_Log\b|\"CLASH [A-Z]+ \|", line):
            continue
        strings += re.findall(r'"((?:[^"]|"")*)"', line)
    return strings


def test_no_sqf_string_carries_a_backslash_n():
    # SQF has no escapes: "\n" reaches the player as backslash-n.
    for path in sorted(MISSION.glob("ITW_CLASH_*.sqf")):
        for literal in re.findall(r'"((?:[^"]|"")*)"', code(path.name)):
            assert "\\n" not in literal, path.name


def test_task_text_breaks_lines_with_br():
    dispatch = code("ITW_CLASH_PlayerDemandDispatch.sqf")
    assert '_description + "<br/><br/>Requires: " + _requirement +' in dispatch
    assert '"<br/>Get one, or use Cancel Current Job to pass."' in dispatch


def test_the_commander_and_the_internals_are_never_named():
    banned = re.compile(r"\bHAL\b|\bETB\b|generation node|adapter|source-certified|locality|Acquire any living")
    for name in PLAYER_TEXT:
        for text in player_strings(name):
            if " " not in text or text.startswith(("ITW_", "Ryd")) or "call " in text:
                continue
            assert not banned.search(text), (name, text)


def test_chat_carries_one_prefix():
    for name in PLAYER_TEXT:
        for text in player_strings(name):
            if text.startswith("C.L.A.S.H.") and " " in text and not text.startswith(("C.L.A.S.H. REQUEST", "C.L.A.S.H. JOB", "C.L.A.S.H. Job")):
                assert text.startswith("C.L.A.S.H.: "), (name, text)


def test_titles_are_category_and_thing():
    titles = {
        "ITW_CLASH_PlayerTaskRequestStrike.sqf": ['"Strike: Heavy Armour"', '"Strike: Light Armour"', '"Strike: Soft Target"', '"Strike: Squad"'],
        "ITW_CLASH_PlayerTaskRequestRecon.sqf": ['"Recon: Reacquire Contact"'],
        "ITW_CLASH_PlayerArtilleryTasks.sqf": ['"Artillery: Fire Mission"'],
        "ITW_CLASH_CSAR.sqf": ['"CSAR: Downed Crew"'],
        "ITW_CLASH_PlayerDemandDispatch.sqf": ['"CSAR: Casualties"', '"Logistics: Ammunition"'],
        "ITW_CLASH_PlayerSquadEvac.sqf": ['"CSAR: Squad Extraction"'],
        "ITW_CLASH_PlayerTaskSupport.sqf": ['"Logistics: Ammunition Sling"'],
        "ITW_CLASH_PlayerTaskRequestTransport.sqf": ['format ["Transport: Lift %1",groupId _squad]'],
    }
    for name, expected in titles.items():
        source = code(name)
        for title in expected:
            assert title in source, (name, title)


def test_the_model_line_is_the_strike_brief():
    strike = code("ITW_CLASH_PlayerTaskRequestStrike.sqf")
    assert "Location is marked and follows the latest report." in strike
    assert "crew liquidation is not necessary." in strike
    assert '" Friendlies near the target may engage."' in strike


def test_no_classname_reaches_a_player():
    recon = code("ITW_CLASH_PlayerTaskRequestRecon.sqf")
    assert 'getText (configFile >> "CfgVehicles" >> _type >> "displayName")' in recon
    assert 'if (_type isKindOf "Man") then {"enemy infantry"}' in recon
    support = code("ITW_CLASH_PlayerTaskSupport.sqf")
    assert 'getText (configOf _target >> "displayName")' in support
    garage = code("ITW_CLASH_PlayerGarageDeployment.sqf")
    assert '"C.L.A.S.H.: Artillery not deployed. " + (createHashMapFromArray [' in garage
    assert "deployment deferred: %1" not in garage
