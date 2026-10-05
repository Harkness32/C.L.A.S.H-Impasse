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


def test_air_denied_and_unsafe_no_chute_corridors_refuse_before_launch():
    body = function_body(fix(), "ITW_CLASH_HALCargoDice_fnc_Acceptable")
    assert "ITW_CLASH_AirPicture_fnc_ClassifyCorridor" in body
    assert '_state isNotEqualTo "AIR_DENIED"' in body
    assert '_state in ["HOT","UNKNOWN"]' in body
    assert "ITW_ParamHelisUnload" in body
    assert "ITW_CLASH_HALParadropReady" in body
    assert "ITW_AllyParadropCargo" in body
    assert "_unsafeWithoutDrop" in body
    assert '"unsafe-without-paradrop"' in body


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



def test_same_live_impasse_base_can_fast_embark_ai_infantry():
    source = fix()
    body = function_body(source, "ITW_CLASH_HALCargoDice_fnc_BaseEmbark")
    resolver = function_body(source, "ITW_CLASH_HALCargoDice_fnc_BaseAtPosition")

    assert "ITW_CLASH_HALCargoDiceFixVersion = 5;" in source
    # The resolver was rewritten to walk every friendly base index and test
    # each one's anchors, instead of asking for a single nearest base. Same
    # rule - a live Impasse base, not a cached coordinate - via a wider test.
    assert "ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices" in resolver
    assert "_base#ITW_BASE_POS" in resolver
    assert "ITW_CLASH_BaseEmbarkRadius" in resolver
    assert "_carrierBase != _troopBase" in body
    assert '(_vehicle emptyPositions "Cargo") < count _troops' in body
    assert "_x assignAsCargo _vehicle;" in body
    assert "_x moveInCargo _vehicle;" in body
    assert "isPlayer _x" in body
    assert 'ITW_CLASH_Withdrawing' in body


def test_scargo_fastpath_is_only_for_normal_crewed_transport_and_falls_back_cleanly():
    source = fix()
    assert 'not (_withdraw) and not (_request) and not (_emptyV)' in source
    assert 'SCargo-base-embark-post-pickup' in source
    assert 'SCargo-base-embark-entry' not in source
    # Falling back cleanly means re-emitting native HAL's own seat-assignment
    # condition verbatim, so a declined fast embark walks the troops in.
    assert 'if (((_ChosenOne emptyPositions "Cargo") > 0) and not (_request)) then' in source
    assert 'not (_clashBaseEmbarked) and (((_ChosenOne emptyPositions "Cargo") > 0)' in source
    assert 'remoteExecCall ["RYD_MP_unassignVehicle",0]' in source
    assert 'base-embark-fastpath' in source


def test_scargo_fastpath_cannot_publish_embark_before_native_pickup_reset():
    source = fix()
    native = scargo().replace("\r", "")
    reset = '[_GD] call RYD_WPdel;'
    pickup = '_wp = [_GD,_Lpos,"MOVE","STEALTH","YELLOW","FULL"'
    assign = 'if (((_ChosenOne emptyPositions "Cargo") > 0) and not (_request)) then'

    # The hook now targets native seat assignment, which is downstream of
    # SCargo's carrier waypoint reset and pickup waypoint. GoAttInf/GoRecon
    # therefore cannot observe assignedVehicle and publish a delivery waypoint
    # until SCargo is finished with the destructive pickup setup.
    assert native.index(reset) < native.index(pickup) < native.index(assign)
    assert 'SCargo-base-embark-post-pickup' in source
    assert 'SCargo-base-embark-entry' not in source
    assert "private _exitLine" not in source


def test_base_embark_uses_live_base_arrays_not_cached_coordinates():
    source = fix()
    resolver = function_body(source, "ITW_CLASH_HALCargoDice_fnc_BaseAtPosition")
    # Read out of ITW_Bases live, each time. The point is that no coordinate
    # is remembered: ServiceBaseHint must never be the source of truth here.
    assert "ITW_Bases" in resolver
    assert "_base#ITW_BASE_POS" in resolver
    assert "ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices" in resolver
    assert "ServiceBaseHint" not in resolver



def test_scargo_runtime_source_normalizes_crlf_before_multiline_patch():
    source = fix()
    assert '_source = (_source splitString (toString [13])) joinString "";' in source
    # The patch that needs the normalization is the base-embark one: its
    # replacement spans lines, so a stray CR would stop the anchor matching.
    assert "SCargo-base-embark-post-pickup" in source
    assert "(toString [10]) + (toString [10])" in source


def test_base_embark_recognizes_impasse_staging_anchors():
    source = fix()
    resolver = function_body(source, "ITW_CLASH_HALCargoDice_fnc_BaseAtPosition")
    assert "ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices" in resolver
    assert "ITW_BASE_POS" in resolver
    assert "ITW_BASE_A_SPAWN" in resolver
    assert "ITW_BASE_GARAGE_POS" in resolver
    assert "ITW_CLASH_BaseEmbarkRadius" in resolver


# ------------------------------------------------ one lift, one squad

def test_the_fastpath_refuses_a_carrier_that_already_has_a_squad():
    """emptyPositions counts occupied seats, so this path would never OVERFILL
    a carrier - it would add a second group into whatever was spare. That is
    how one vehicle ends up with two squads, which Hark hit on the air side
    ("alpha 2-5 has two different groups in his helo") and which was reachable
    here for ground vehicles by the same route."""
    source = text("ITW_CLASH_HALCargoDiceFix.sqf")
    body = source[source.index("ITW_CLASH_HALCargoDice_fnc_BaseEmbark = {"):]
    body = body[:body.index("\n};")]
    assert '["already-carrying"] call _decline' in body
    assert "group _x isNotEqualTo _carrierG" in body
    assert "group _x isNotEqualTo _unitG" in body


def test_the_carriers_own_crew_is_not_mistaken_for_a_squad():
    source = text("ITW_CLASH_HALCargoDiceFix.sqf")
    body = source[source.index("private _riders ="):]
    body = body[:body.index("];")]
    assert "_carrierG" in body
    assert '"Turret"' in body, "a door gunner is not a passenger"


def test_the_check_runs_before_anyone_is_moved():
    source = text("ITW_CLASH_HALCargoDiceFix.sqf")
    body = source[source.index("ITW_CLASH_HALCargoDice_fnc_BaseEmbark = {"):]
    assert body.index('["already-carrying"]') < body.index("_x moveInCargo _vehicle")


def test_the_fastpath_line_names_the_vehicle_not_just_its_class():
    """Two B_Truck_01_transport_F lines in one run could be two trucks or one
    truck twice, and the class alone cannot tell them apart - which is exactly
    the shape of the bug above."""
    source = text("ITW_CLASH_HALCargoDiceFix.sqf")
    assert "base-embark-fastpath | group=%1 vehicle=%2 id=%3" in source
    assert "BIS_fnc_netId" in source
