from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def tiers() -> str:
    return text("ITW_CLASH_ThunderRunAirTiers.sqf")


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


def test_the_defect_is_real_an_unarmed_transport_closes_a_route():
    # RydHQ_Airthreat comes from RydHQ_EnAir, and HAL's non-combat air list is
    # only the unarmed SUBSET of its air list, not a removal from it.
    hal2 = (HAL / "HAC_fnc2.sqf").read_text(encoding="utf-8", errors="replace")
    air = hal2.index("RHQ_Air pushBackUnique _veh;")
    nc = hal2.index("RHQ_NCAir pushBackUnique _veh;", air)
    assert "if not (_isArmed) then" in hal2[air:nc]
    orders = (HAL / "HAL" / "HQOrders.sqf").read_text(encoding="utf-8", errors="replace")
    assert '_HQ setVariable ["RydHQ_Airthreat",_Airthreat];' in orders
    # And Thunder Run denies on any of them within the deny radius.
    core = text("ITW_CLASH_ThunderRun_Core.sqf")
    assert 'RydHQ_Airthreat' in core
    assert "if (_airDistance < ITW_CLASH_ThunderRunAirDenyRadius) exitWith {" in core
    assert 'ITW_CLASH_ThunderRunAirDenyRadius",5000' in core


def test_air_denied_really_does_cancel_rather_than_caution():
    # Which is why relaxing it matters: these are the consumers.
    assert '== "AIR_DENIED") then {continue};' in text("ITW_CLASH_Resupply.sqf")
    interceptors = text("ITW_CLASH_PlayerDemandNativeInterceptors.sqf")
    assert '_airDecisionState == "AIR_DENIED"' in interceptors
    assert '"AIR_DENIED"] call ITW_CLASH_ThunderRun_fnc_Dispose;' in interceptors


def test_the_layer_wraps_rather_than_edits_the_classifier():
    source = tiers()
    assert "ITW_CLASH_ThunderRun_fnc_ClassifyTierBase = ITW_CLASH_ThunderRun_fnc_Classify;" in source
    body = function_body(source, "ITW_CLASH_ThunderRun_fnc_Classify")
    assert "call ITW_CLASH_ThunderRun_fnc_ClassifyTierBase" in body
    # Nothing under NR6 Hal/ and no edit to the core or enhancement files.
    assert "RYD_Path" not in source
    assert "preprocessFileLineNumbers" not in source


def test_it_only_ever_relaxes_and_only_an_air_or_aa_denial():
    source = tiers()
    body = function_body(source, "ITW_CLASH_ThunderRun_fnc_Classify")
    # A state that is not AIR_DENIED, or a ground-driven denial, passes through.
    assert 'if (_state isNotEqualTo "AIR_DENIED") exitWith {_result};' in body
    assert "if !(_reason in ITW_CLASH_ThunderRunAirTiersCauses) exitWith {_result};" in body
    assert 'ITW_CLASH_ThunderRunAirTiersCauses = [' in source
    for cause in ["enemy-air-corridor", "aa-concentration", "aa-no-countermeasures"]:
        assert f'"{cause}"' in source, cause
    # The ground causes are never listed, so they are never re-examined.
    for ground in ["ground-hot-corridor", "ground-contested-corridor"]:
        assert ground not in source, ground


def test_hard_kill_and_recent_losses_still_close_the_route():
    source = tiers()
    body = function_body(source, "ITW_CLASH_ThunderRun_fnc_Classify")
    assert "ITW_CLASH_AirPicture_fnc_ClassifyCorridor" in body
    assert 'if (_tierState isEqualTo "AIR_DENIED") exitWith {' in body
    assert '"upheld"' in body
    # The corridor's own AIR_DENIED reasons are hard kill, fighters and losses.
    corridor = function_body(
        text("ITW_CLASH_AirPicture.sqf"),
        "ITW_CLASH_AirPicture_fnc_ClassifyCorridor",
    )
    assert '"enemy-fighter-corridor"' in corridor
    assert '"recent-losses"' in corridor


def test_no_information_means_no_change():
    body = function_body(tiers(), "ITW_CLASH_ThunderRun_fnc_Classify")
    assert 'if (_tierReason isEqualTo "corridor-unavailable") exitWith {_result};' in body


def test_a_clear_corridor_is_reported_contested_not_safe():
    source = tiers()
    # The base had already denied it, so its ground verdict for this route was
    # never computed: claiming SAFE would assert something unevaluated.
    assert 'ITW_CLASH_ThunderRunAirTiersClearState","CONTESTED"' in source
    body = function_body(source, "ITW_CLASH_ThunderRun_fnc_Classify")
    assert 'if (_tierState isEqualTo "COLD") then {' in body
    assert "ITW_CLASH_ThunderRunAirTiersClearState" in body
    assert '"SAFE"' not in body


def test_it_loads_after_the_enhancement_layer_and_the_air_picture():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_ThunderRunAirTiers.sqf"' in init
    assert "thunder-run-air-tiers-missing-or-prereq-failed" in init
    assert "_thunderRunLoaded isEqualTo true" in init
    assert init.index('"ITW_CLASH_ThunderRun.sqf"') < init.index(
        '"ITW_CLASH_ThunderRunAirTiers.sqf"'
    )
    assert init.index('"ITW_CLASH_AirPicture.sqf"') < init.index(
        '"ITW_CLASH_ThunderRunAirTiers.sqf"'
    )
