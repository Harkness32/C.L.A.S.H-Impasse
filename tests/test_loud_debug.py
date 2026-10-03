import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"

# Every module that reports air or budget decisions, and the source name it
# reports under. The loud debugger's sentences are keyed on these.
FEEDERS = {
    "ITW_CLASH_AirPicture.sqf": ("ITW_CLASH_AirPicture_fnc_Log", "air-picture"),
    "ITW_CLASH_ThunderRunAirTiers.sqf": ("ITW_CLASH_ThunderRunAirTiers_fnc_Log", "air-tiers"),
    "ITW_CLASH_HALCargoDiceFix.sqf": ("ITW_CLASH_HALCargoDice_fnc_Log", "hal-cargo-dice"),
    "ITW_CLASH_SPAAOverwatch.sqf": ("ITW_CLASH_SPAAOverwatch_fnc_Log", "spaa-overwatch"),
    "ITW_CLASH_RearBaseCRAM.sqf": ("ITW_CLASH_RearBaseCRAM_fnc_Log", "rear-cram"),
    "ITW_CLASH_FOBAirDefence.sqf": ("ITW_CLASH_FOBAirDefence_fnc_Log", "fob-air-defence"),
    "ITW_CLASH_EmergingThreatsBudget.sqf": ("ITW_CLASH_ETB_fnc_Log", "etb"),
    "ITW_CLASH_HALThreatCoverage.sqf": ("ITW_CLASH_HALThreatCoverage_fnc_Log", "hal-threat-coverage"),
    "ITW_CLASH_HotDrop.sqf": ("ITW_CLASH_HotDrop_fnc_Log", "hot-drop"),
}


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def loud() -> str:
    return text("ITW_CLASH_LoudDebug.sqf")


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


def test_it_is_off_by_default():
    # A debug surface must not ship loud.
    assert 'ITW_CLASH_LoudDebugEnabled",false' in loud()
    body = function_body(loud(), "ITW_CLASH_LoudDebug_fnc_Emit")
    assert "if (!ITW_CLASH_LoudDebugEnabled) exitWith {false};" in body


def test_every_feeder_is_hooked_into_its_own_logger():
    for name, (logger, source) in FEEDERS.items():
        body = function_body(text(name), logger)
        assert "ITW_CLASH_LoudDebug_fnc_Emit" in body, name
        assert f'["{source}",_event,_payload]' in body, name


def test_it_never_changes_a_decision():
    source = loud()
    # A formatter on the tail of logging: it must not task, buy, move or deny.
    code = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    code = re.sub(r"//[^\n]*", " ", code)
    for forbidden in [
        "doMove", "addWaypoint", "deleteWaypoint", "setVariable",
        "ITW_CLASH_ETB_fnc_Authorize", "RYD_Dispatcher", "createVehicle",
        "flyInHeight", "deleteVehicle",
    ]:
        assert forbidden not in code, forbidden


def test_the_events_the_tester_asked_for_have_plain_sentences():
    body = function_body(loud(), "ITW_CLASH_LoudDebug_fnc_Sentence")
    assert "AIR CORRIDOR CLOSED BY %1" in body
    assert "AIR CORRIDOR OPENED" in body
    assert "AIR CORRIDOR CLOSED BY LOSSES" in body
    assert "RESERVED FOR BACKLINE AA" in body
    assert "HELICOPTER LIFT REFUSED" in body


def test_every_sentence_keys_on_a_source_a_feeder_actually_reports():
    body = function_body(loud(), "ITW_CLASH_LoudDebug_fnc_Sentence")
    keyed = set(re.findall(r'case "([a-z-]+)\|', body))
    known = {source for _, source in FEEDERS.values()}
    assert keyed, "no sentences found"
    assert keyed <= known, keyed - known


def test_every_sentence_names_an_event_its_module_really_emits():
    # A sentence keyed on an event nobody emits is dead code that reads as
    # coverage. Check each one against its module's own log calls.
    body = function_body(loud(), "ITW_CLASH_LoudDebug_fnc_Sentence")
    by_source = {source: name for name, (_, source) in FEEDERS.items()}
    missing = []
    for source, event in re.findall(r'case "([a-z-]+)\|([a-z-]+)"', body):
        module = by_source.get(source)
        assert module is not None, source
        if f'"{event}"' not in text(module):
            missing.append(f"{source}|{event}")
    assert missing == [], missing


def test_an_unknown_event_is_still_spoken():
    # A debugger that hides what it does not recognise is worse than a noisy one.
    body = function_body(loud(), "ITW_CLASH_LoudDebug_fnc_Emit")
    assert 'if (_text isEqualTo "") then {' in body
    assert "toUpperANSI _source" in body


def test_repeats_and_the_noisy_events_are_damped():
    source = loud()
    assert 'ITW_CLASH_LoudDebugRepeat",8' in source
    assert "ITW_CLASH_LoudDebugMuted" in source
    say = function_body(source, "ITW_CLASH_LoudDebug_fnc_Say")
    assert "ITW_CLASH_LoudDebugLastSaid" in say
    # The muted defaults must name events that actually exist, or the mute is
    # dead and the noise arrives anyway.
    muted = re.search(r'ITW_CLASH_LoudDebugMuted",\[(.*?)\]', source).group(1)
    for entry in re.findall(r'"([a-z-]+)\|([a-z-]+)"', muted):
        source_name, event = entry
        module = {s: n for n, (_, s) in FEEDERS.items()}[source_name]
        assert f'"{event}"' in text(module), entry


def test_it_reaches_players_and_mirrors_to_the_log():
    body = function_body(loud(), "ITW_CLASH_LoudDebug_fnc_Say")
    assert 'remoteExecCall ["systemChat",0]' in body
    assert "CLASH LOUD | " in body


def test_it_can_be_toggled_mid_mission():
    source = loud()
    assert "ITW_CLASH_LoudDebug_fnc_Toggle" in source
    body = function_body(source, "ITW_CLASH_LoudDebug_fnc_Toggle")
    assert "ITW_CLASH_LoudDebugEnabled = _on;" in body


def test_the_cargo_dice_rate_limiter_actually_suppresses():
    # It used to exitWith inside a then block, which only leaves the block, so
    # the limiter never fired and SCargo spammed once per group per HAL cycle.
    body = function_body(text("ITW_CLASH_HALCargoDiceFix.sqf"), "ITW_CLASH_HALCargoDice_fnc_Log")
    assert "_muted = true;" in body
    assert "if (_muted) exitWith {};" in body
    assert body.index("_muted = true;") < body.index("if (_muted) exitWith {};")


def test_it_loads_before_the_modules_that_feed_it():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_LoudDebug.sqf"' in init
    assert "loud-debug-missing" in init
    position = init.index('"ITW_CLASH_LoudDebug.sqf"')
    for name in ["ITW_CLASH_AirPicture.sqf", "ITW_CLASH_HotDrop.sqf", "ITW_CLASH_HALThreatCoverage.sqf"]:
        assert position < init.index(f'"{name}"'), name
