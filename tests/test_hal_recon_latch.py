import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def latch() -> str:
    return text("ITW_CLASH_HALReconLatch.sqf")


def code_only(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def function_body(source: str, name: str) -> str:
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
    raise AssertionError(f"unterminated {name}")


# ------------------------------------------------- the bug this answers

def test_hal_only_scouts_while_blind():
    # The gate that makes the flag unearnable after contact. If HAL ever
    # relaxes it, this latch is no longer needed and this test says so.
    orders = (HAL / "HAL" / "HQOrders.sqf").read_text(encoding="utf-8", errors="replace")
    assert 'if (((count (_HQ getVariable ["RydHQ_KnEnemiesG",[]])) == 0) and' in orders


def test_hal_reset_clears_the_flag_but_not_its_witness():
    # HQReset clears ReconDone and ReconStage and leaves ReconStage2 alone.
    # That asymmetry is how this was diagnosed from the RPT.
    reset = (HAL / "HAL" / "HQReset.sqf").read_text(encoding="utf-8", errors="replace")
    assert '_HQ setVariable ["RydHQ_ReconDone",false];' in reset
    assert '_HQ setVariable ["RydHQ_ReconStage",1];' in reset
    assert '_HQ setVariable ["RydHQ_ReconStage2",1];' not in reset


def test_capture_really_does_depend_on_the_flag():
    orders = (HAL / "HAL" / "HQOrders.sqf").read_text(encoding="utf-8", errors="replace")
    gate = orders[orders.index("_forCapt = ") - 1200:orders.index("_forCapt = ")]
    assert 'RydHQ_ReconDone' in gate
    assert 'RydHQ_RapidCapt' in gate


def test_clash_is_what_makes_the_reset_frequent():
    # 30 against HAL's own 600. Recorded so the interaction is not rediscovered.
    assert "RydHQ_ResetTime = 30;" in text("ITW_CLASH.sqf")
    sitrep = (HAL / "HAL" / "HQSitRepF.sqf").read_text(encoding="utf-8", errors="replace")
    assert 'RydHQF_ResetTime = 600' in sitrep
    source = latch()
    assert "ITW_CLASH.sqf:2337" in source
    assert "HQOrders.sqf:356" in source
    assert "HQReset.sqf:17-18" in source


# ------------------------------------------------------------ the latch

def test_it_only_ever_writes_true():
    source = code_only(latch())
    writes = re.findall(r'setVariable\s*\[\s*"RydHQ_\w+"\s*,\s*(\w+)', source)
    assert writes == ["true"], writes
    # And the only HAL variable it writes is the flag itself.
    names = re.findall(r'setVariable\s*\[\s*"(RydHQ_\w+)"', source)
    assert names == ["RydHQ_ReconDone"], names


def test_it_issues_no_orders():
    source = code_only(latch())
    for forbidden in [
        "doMove", "commandMove", "addWaypoint", "deleteWaypoint", "setBehaviour",
        "setCombatMode", "RYD_Dispatcher", "HAL_GoRecon", "HAL_GoSFAttack",
        "createVehicle", "ITW_CLASH_ETB_fnc_Authorize",
    ]:
        assert forbidden not in source, forbidden


def test_contact_is_counted_the_way_the_gate_counts_it():
    body = function_body(latch(), "ITW_CLASH_HALReconLatch_fnc_Known")
    # Groups, not units: HQOrders.sqf:356 counts RydHQ_KnEnemiesG.
    assert 'RydHQ_KnEnemiesG' in body
    assert "RydHQ_KnEnemies\"" not in body
    assert "select {!isNull _x}" in body


def test_a_blind_commander_gets_the_flag_back():
    # Standing off is what lets HAL's own recon loop run again. Clearing the
    # flag ourselves would be us deciding a commander must rescout.
    body = function_body(latch(), "ITW_CLASH_HALReconLatch_fnc_Hold")
    assert "ITW_CLASH_HALReconLatchKnown" in body
    assert '"blind"' in body
    assert "setVariable" not in body.split('"blind"')[0].split("exitWith")[-1]


def test_it_polls_faster_than_the_reset_it_is_fighting():
    source = latch()
    assert 'ITW_CLASH_HALReconLatchPoll",10' in source
    poll = int(re.search(r'ITW_CLASH_HALReconLatchPoll",(\d+)', source).group(1))
    reset = int(re.search(r"RydHQ_ResetTime = (\d+);", text("ITW_CLASH.sqf")).group(1))
    assert poll < reset, (poll, reset)


def test_a_relatch_every_thirty_seconds_is_not_said_every_thirty_seconds():
    source = latch()
    body = function_body(source, "ITW_CLASH_HALReconLatch_fnc_Hold")
    assert "ITW_CLASH_HALReconLatchReportEvery" in body
    assert 'ITW_CLASH_HALReconLatchReportEvery",300' in source
    # The first latch is immediate; only the repeats are rate limited.
    assert '"latched"' in body
    assert '"holding"' in body


def test_state_is_mutated_in_place_not_through_a_copy():
    # SQF "+" deep copies; writing through one would silently lose every count.
    source = code_only(latch())
    assert "+ITW_CLASH_HALReconLatchState" not in source
    assert "+(ITW_CLASH_HALReconLatchState" not in source
    body = function_body(latch(), "ITW_CLASH_HALReconLatch_fnc_State")
    assert "getOrDefault" in body


def test_it_waits_before_taking_an_interest():
    source = latch()
    assert 'ITW_CLASH_HALReconLatchSettle",120' in source
    assert "sleep ITW_CLASH_HALReconLatchSettle;" in source


def test_it_can_be_switched_off_and_survives_game_over():
    source = latch()
    assert 'ITW_CLASH_HALReconLatchEnabled",true' in source
    assert source.count("ITW_GameOver") >= 3


def test_no_exit_with_inside_a_then_block():
    source = code_only(latch())
    for match in re.finditer(r"then\s*\{", source):
        segment = source[match.end():]
        depth = 1
        i = 0
        while i < len(segment) and depth > 0:
            if segment[i] == "{":
                depth += 1
            elif segment[i] == "}":
                depth -= 1
            i += 1
        assert "exitWith" not in segment[:i], source[max(0, match.start() - 80):match.end()]


# ------------------------------------------------------------- wiring

def test_it_speaks_in_the_loud_debugger():
    loud = text("ITW_CLASH_LoudDebug.sqf")
    for event in ["recon-latch|latched", "recon-latch|holding", "recon-latch|blind"]:
        assert f'case "{event}"' in loud, event
    body = function_body(latch(), "ITW_CLASH_HALReconLatch_fnc_Log")
    assert '["recon-latch",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit' in body


def test_the_preflight_knows_about_it():
    preflight = text("ITW_CLASH_DebugPreflight.sqf")
    assert '["ITW_CLASH_HALReconLatch","recon latch"' in preflight


def test_it_loads_and_warns_when_it_cannot():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_HALReconLatch.sqf"' in init
    assert "hal-recon-latch-missing" in init
