from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal"

DICE = (
    '(((count ((_HQ getVariable ["RydHQ_AAthreat",[]]) '
    '+ (_HQ getVariable ["RydHQ_Airthreat",[]]))) == 0) '
    'or (random 100 > (85/(0.5 + (2*(_HQ getVariable ["RydHQ_Recklessness",0.5]))))))'
)


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def fix() -> str:
    return text("ITW_CLASH_HALCargoDiceFix.sqf")


def scargo() -> str:
    return (HAL / "HAL" / "SCargo.sqf").read_text(encoding="utf-8", errors="replace")


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


def test_the_dice_are_still_there_and_still_map_wide():
    source = scargo()
    assert source.count(DICE) == 1, "SCargo's lift dice changed upstream"
    # Position never enters it: the test is on the commander's whole threat list.
    assert "RydHQ_AAthreat" in DICE and "RydHQ_Airthreat" in DICE


def test_the_anchor_is_unique_so_the_swap_is_all_or_nothing():
    assert scargo().count(DICE) == 1
    assert fix().count(DICE) == 1


def test_the_route_is_already_in_scope_where_we_patch():
    source = scargo()
    # _posS is where the cargo group stands, _posT where it is going.
    assert "_posS = (getPosATL (vehicle _GL));" in source
    assert "_posT = _this select 2;" in source
    assert '([_HQ,_posS,_posT] call ITW_CLASH_HALCargoDice_fnc_Acceptable)' in fix()


def test_only_a_closed_corridor_refuses_the_lift():
    body = function_body(fix(), "ITW_CLASH_HALCargoDice_fnc_Acceptable")
    assert "ITW_CLASH_AirPicture_fnc_ClassifyCorridor" in body
    assert '_state isNotEqualTo "AIR_DENIED"' in body


def test_without_a_corridor_hals_own_rule_stands():
    source = fix()
    body = function_body(source, "ITW_CLASH_HALCargoDice_fnc_Acceptable")
    # Waving every lift through when the air picture is missing would be a
    # louder change than the one intended.
    assert "ITW_CLASH_HALCargoDice_fnc_NativeRoll" in body
    native = function_body(source, "ITW_CLASH_HALCargoDice_fnc_NativeRoll")
    assert "RydHQ_AAthreat" in native
    assert "RydHQ_Airthreat" in native
    assert "85 / (0.5 + (2 * _recklessness))" in native
    assert 'if (_reason isEqualTo "corridor-unavailable") exitWith {' in body


def test_it_patches_the_native_the_checkbook_hook_holds():
    source = fix()
    # Patching HAL_SCargo after the Checkbook wrapped it would discard the hook.
    assert "ITW_CLASH_CheckbookCargoHookReady" in source
    assert "ITW_CLASH_Checkbook_fnc_NativeSCargo = _compiled;" in source
    assert "HAL_SCargo = _compiled;" in source
    checkbook = text("ITW_CLASH_DualHALCheckbook.sqf")
    assert "ITW_CLASH_Checkbook_fnc_NativeSCargo = HAL_SCargo;" in checkbook


def test_a_missing_or_duplicated_anchor_leaves_hal_alone():
    source = fix()
    for reason in ["signature-missing", "signature-duplicate", "already-fixed"]:
        assert reason in source, reason
    assert "hal-cargo-dice-fix-failed" in source
    assert "SCargo-signature-missing" in source
    assert "recompile-failed" in source


def test_no_nr6_file_is_edited():
    source = fix()
    assert "preprocessFileLineNumbers _path" in source
    assert "compile _source" in source
    # It reads HAL's own source and recompiles; it never writes one.
    assert "copyToClipboard" not in source
    assert "saveProfileNamespace" not in source


def test_it_is_loaded_scheduled():
    init = text("init.sqf")
    assert '[] execVM "ITW_CLASH_HALCargoDiceFix.sqf";' in init
    assert "hal-cargo-dice-fix-missing" in init
