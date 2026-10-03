import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def preflight() -> str:
    return text("ITW_CLASH_DebugPreflight.sqf")


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


def array_body(source: str, name: str) -> str:
    start = source.index(f"{name} = [")
    depth = 0
    i = source.index("[", start)
    while i < len(source):
        if source[i] == "[":
            depth += 1
        elif source[i] == "]":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1
    raise AssertionError(f"unterminated {name}")


def test_the_report_changes_nothing():
    # A diagnostic that can alter a run is worse than no diagnostic: every
    # number it prints would then be suspect.
    source = code_only(preflight())
    for forbidden in [
        "doMove", "commandMove", "addWaypoint", "deleteWaypoint", "setBehaviour",
        "setCombatMode", "setSkill", "createVehicle", "deleteVehicle",
        "RYD_Dispatcher", "ITW_CLASH_ETB_fnc_Authorize", "ITW_CLASH_ETB_fnc_Commit",
        "ITW_CLASH_fnc_RequestCapability",
    ]:
        assert forbidden not in source, forbidden
    # No setVariable at all: not on a HAL pool, not anywhere.
    assert "setVariable" not in source


def test_every_shipped_module_is_in_the_manifest():
    source = preflight()
    body = array_body(source, "ITW_CLASH_DebugPreflightManifest")
    for prefix in [
        "ITW_CLASH_AirPicture",
        "ITW_CLASH_ETB",
        "ITW_CLASH_HALThreatCoverage",
        "ITW_CLASH_SPAAOverwatch",
        "ITW_CLASH_RearBaseCRAM",
        "ITW_CLASH_FOBAirDefence",
        "ITW_CLASH_HALFront",
        "ITW_CLASH_HALDispatcherAAFix",
        "ITW_CLASH_HALCargoDiceFix",
        "ITW_CLASH_HotDrop",
        "ITW_CLASH_ThunderRunAirTiers",
        "ITW_CLASH_CounterBattery",
        "ITW_CLASH_ArtilleryScoot",
        "ITW_CLASH_Colossus",
    ]:
        assert f'["{prefix}"' in body, prefix


def test_each_manifest_row_states_a_consequence():
    body = array_body(preflight(), "ITW_CLASH_DebugPreflightManifest")
    rows = re.findall(r'\["ITW_CLASH_\w+","([^"]+)","([^"]+)"\]', body)
    assert len(rows) == 17, len(rows)
    for label, consequence in rows:
        assert label.strip()
        # The consequence is the line worth reading; an empty one is useless.
        assert len(consequence.split()) >= 3, (label, consequence)


def test_every_manifest_prefix_is_a_flag_a_module_really_publishes():
    body = array_body(preflight(), "ITW_CLASH_DebugPreflightManifest")
    prefixes = re.findall(r'\["(ITW_CLASH_\w+)","', body)
    published = set()
    for path in MISSION.glob("ITW_CLASH_*.sqf"):
        published.update(
            re.findall(r"(ITW_CLASH_\w+)Ready\s*=", path.read_text(encoding="utf-8", errors="replace"))
        )
    for prefix in prefixes:
        assert prefix in published, f"{prefix}Ready is never assigned by any module"


def test_missing_is_distinguished_from_still_binding():
    # The two runtime patches bind against HAL's own schedule, so "loaded but
    # not ready yet" must not read the same as "never loaded".
    body = function_body(preflight(), "ITW_CLASH_DebugPreflight_fnc_State")
    assert '"READY"' in body
    assert '"WAITING"' in body
    assert '"MISSING"' in body
    assert '_prefix + "Started"' in body
    assert '_prefix + "Ready"' in body


def test_it_reports_hal_cycle_length_first():
    # Every corridor timer is measured in HAL cycles, so the cycle length is
    # what makes the rest of the numbers legible.
    body = function_body(preflight(), "ITW_CLASH_DebugPreflight_fnc_Commander")
    assert "ITW_CLASH_AirPicture_fnc_HALCycleSeconds" in body
    assert "halCycle=" in body
    for field in ["front=", "groups=", "known=", "artillery=", "airDenials="]:
        assert field in body, field


def test_it_asks_the_etb_rather_than_recomputing_a_balance():
    body = function_body(preflight(), "ITW_CLASH_DebugPreflight_fnc_Commander")
    assert "ITW_CLASH_ETB_fnc_Status" in body
    # Two sources for one balance would eventually disagree.
    assert "ITW_CLASH_ETB_fnc_Cash" not in body
    assert "ITW_CLASH_ETB_fnc_Reserve" not in body


def test_optional_readers_are_guarded_both_ways():
    source = preflight()
    body = function_body(source, "ITW_CLASH_DebugPreflight_fnc_Commander")
    # isNil on the function AND a defaulted read of the flag: a bare
    # ITW_CLASH_ETBReady would throw when the ETB never loaded.
    assert 'missionNamespace getVariable ["ITW_CLASH_ETBReady",false]' in body
    assert 'missionNamespace getVariable ["ITW_CLASH_ColossusReady",false]' in body
    assert "ITW_CLASH_ETBReady isEqualTo" not in source
    assert "ITW_CLASH_ColossusReady isEqualTo" not in source


def test_one_greppable_prefix():
    source = preflight()
    body = function_body(source, "ITW_CLASH_DebugPreflight_fnc_Log")
    assert '"CLASH PREFLIGHT | %1"' in body
    # And the reading instructions live in the file itself.
    assert "CLASH PREFLIGHT" in source


def test_chat_stays_quiet_unless_loud_debug_is_on():
    body = function_body(preflight(), "ITW_CLASH_DebugPreflight_fnc_Report")
    index = body.index("remoteExecCall")
    guard = body[:index]
    assert 'getVariable ["ITW_CLASH_LoudDebugEnabled",false]' in guard
    assert '["systemChat",0]' in body


def test_there_is_a_manual_trigger():
    source = preflight()
    assert "ITW_CLASH_DebugPreflight_fnc_Now" in source
    assert '"on-demand"' in source


def test_the_loop_survives_game_over():
    source = preflight()
    assert source.count("ITW_GameOver") >= 4
    assert 'ITW_CLASH_DebugPreflightRepeat",600' in source
    assert 'ITW_CLASH_DebugPreflightDelay",180' in source


def test_it_can_be_switched_off():
    source = preflight()
    assert 'ITW_CLASH_DebugPreflightEnabled",true' in source
    assert '"disabled | no preflight report this run"' in source


def test_it_loads_last_and_warns_when_it_cannot():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_DebugPreflight.sqf"' in init
    assert "debug-preflight-missing" in init
    # Loaded after the modules it reports on, or its flags are all MISSING.
    for earlier in [
        "ITW_CLASH_Colossus.sqf",
        "ITW_CLASH_ArtilleryScoot.sqf",
        "ITW_CLASH_HotDrop.sqf",
        "ITW_CLASH_HALCargoDiceFix.sqf",
    ]:
        assert init.index(earlier) < init.index("ITW_CLASH_DebugPreflight.sqf"), earlier


def test_no_exit_with_inside_a_then_block():
    # The trap that has bitten this codebase three times.
    source = code_only(preflight())
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


def test_the_mission_parameter_exists_and_auto_converts():
    ext = text("description.ext")
    block = ext[ext.index("class CLASHDebug"):]
    # The class ends at a closing brace on its own indented line, not at the
    # first "};" which belongs to values[].
    block = block[:re.search(r"\n\t\};", block).end()]
    assert 'values[] = {0,1,2}' in block
    assert "default = 0" in block
    # Three texts for three values, or the lobby entry is broken.
    texts = re.search(r"texts\[\] = \{([^}]*)\}", block).group(1)
    assert len(re.findall(r'"[^"]*"', texts)) == 3
    # params.sqf converts every Params class into ITW_Param<ClassName>, so the
    # global the modules read is a consequence of the class name.
    params = text("params.sqf")
    assert 'ITW_Param%1 = %2;' in params
    assert 'configClasses getMissionConfig "Params"' in params


def test_the_parameter_is_read_before_any_module_needs_it():
    init = text("init.sqf")
    # params.sqf runs first and init waits for it, so ITW_ParamCLASHDebug is
    # set by the time the loud debugger or the preflight load.
    assert init.index('preprocessFileLineNumbers "params.sqf"') < init.index(
        'preprocessFileLineNumbers "ITW_CLASH_LoudDebug.sqf"'
    )
    assert 'waitUntil {!isNil "ITW_Params_complete"}' in init


def test_chat_is_asked_for_by_the_parameter_or_the_loud_debugger():
    source = preflight()
    body = function_body(source, "ITW_CLASH_DebugPreflight_fnc_Speaks")
    assert "ITW_CLASH_DebugPreflightParamLevel >= 1" in body
    assert 'getVariable ["ITW_CLASH_LoudDebugEnabled",false]' in body
    # And the report asks the helper rather than re-deriving the condition.
    report = function_body(source, "ITW_CLASH_DebugPreflight_fnc_Report")
    assert "call ITW_CLASH_DebugPreflight_fnc_Speaks" in report


def test_a_missing_parameter_defaults_to_quiet_not_to_an_error():
    source = preflight()
    assert 'getVariable ["ITW_ParamCLASHDebug",0]' in source
    # A param read back as something other than a number must not poison a
    # comparison later.
    assert "isEqualType 0" in source


def test_the_rpt_report_does_not_depend_on_the_parameter():
    # Level 0 still writes the full report; the parameter only controls chat.
    source = preflight()
    report = function_body(source, "ITW_CLASH_DebugPreflight_fnc_Report")
    index = report.index("ITW_CLASH_DebugPreflight_fnc_Modules")
    assert "fnc_Speaks" not in report[:index]


def test_the_report_says_what_the_ai_can_actually_see():
    # setSkill is applied flat, so spotDistance and spotTime are the difficulty
    # param - and the server's coefficients scale the result again. Without
    # both numbers a run where squads walk past each other is unreadable.
    source = preflight()
    body = function_body(source, "ITW_CLASH_DebugPreflight_fnc_Report")
    assert "ITW_FncGetServerAiDifficultySetting" in body
    assert "SERVER_AI_DIFFICULTY_SETTING" in body
    assert "ITW_ParamDifficulty" in body
    assert "ITW_ParamFriendlySquadSkill" in body
    assert "serverSkill=%3" in body


def test_a_missing_difficulty_reading_says_unknown_rather_than_lying():
    body = function_body(preflight(), "ITW_CLASH_DebugPreflight_fnc_Report")
    assert '{"unknown"}' in body
    assert 'isNil "ITW_FncGetServerAiDifficultySetting"' in body


def test_the_ai_line_is_still_read_only():
    # It asks for a value the mission already computes; it must not set one.
    # Code only - the comment above it legitimately names setSkill.
    body = code_only(function_body(preflight(), "ITW_CLASH_DebugPreflight_fnc_Report"))
    assert "SERVER_AI_DIFFICULTY_SETTING =" not in body
    assert "setSkill" not in body
