import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def etb() -> str:
    return text("ITW_CLASH_EmergingThreatsBudget.sqf")


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


def test_impasse_tickets_are_never_touched():
    source = etb()
    # Invariant 1: Impasse stays the baseline army generator. No ticket is read
    # to spend, reduced, reserved or incremented here.
    for forbidden in [
        "ITW_TICKET_REDUCE",
        "ITW_VEH_COUNT_INCR",
        "ITW_TICKET_SEM_CHECK",
        "ITW_VEH_CURR_TICKETS",
        "set [ITW_VEH",
    ]:
        assert forbidden not in source, forbidden
    # The row is read for its price and its cap only.
    assert "ITW_VEH_REQD_TICKETS" in source
    assert "ITW_VEH_MAX" in source


def test_etb_assets_never_carry_itw_vehdef():
    source = etb()
    # Invariant 9: ETB assets are purely additive, so they must not count
    # against Impasse's caps.
    assert 'setVariable ["ITW_VehDef"' not in source
    commit = function_body(source, "ITW_CLASH_ETB_fnc_Commit")
    assert 'setVariable ["ITW_CLASH_ETBAsset",true,true]' in commit
    assert 'setVariable ["ITW_CLASH_ETBRow"' in commit
    assert 'setVariable ["ITW_CLASH_ETBCost"' in commit


def test_every_vehdef_reader_tolerates_an_asset_without_one():
    # The audit the design asks for, as a test: apart from the Impasse
    # transport-waypoint guard, no reader may hard-skip a vehicle with no def.
    hard_skips = []
    for name in [
        "ITW_CLASH_ServiceAuthority.sqf",
        "ITW_CLASH_ServiceLifecycle.sqf",
        "ITW_CLASH_ServiceStability.sqf",
        "ITW_CLASH_VehicleEchelonPolicy.sqf",
    ]:
        body = text(name)
        for number, line in enumerate(body.splitlines(), 1):
            if "ITW_VehDef" not in line:
                continue
            if re.search(r"(exitWith|continue)", line):
                hard_skips.append(f"{name}:{number}: {line.strip()}")
    assert hard_skips == [], "\n".join(hard_skips)
    # VehicleEchelonPolicy has to classify an ETB tank with no def at all.
    echelon = function_body(
        text("ITW_CLASH_VehicleEchelonPolicy.sqf"),
        "ITW_CLASH_VehicleEchelon_fnc_IsArmoredCombatGroup",
    )
    assert 'isKindOf "Tank"' in echelon
    assert "editorSubcategory" in echelon
    # And the audit itself is recorded beside the code it constrains.
    assert "ITW_CLASH_LogisticsGuard.sqf:280" in etb()


def test_the_decided_defaults():
    source = etb()
    assert 'ITW_CLASH_ETBStartingReserve",40' in source
    assert 'ITW_CLASH_ETBCapacity",80' in source
    assert 'ITW_CLASH_ETBIncomeScale",1' in source
    assert 'ITW_CLASH_ETBRowLimitScale",1' in source
    assert 'ITW_CLASH_ETBGroundInterval",90' in source
    assert 'ITW_CLASH_ETBSafetyLimit",6' in source
    assert 'ITW_CLASH_ETBIdleRelease",480' in source
    assert 'ITW_CLASH_ETBCrewWriteOff",300' in source
    assert 'ITW_CLASH_ETBImmobileWriteOff",600' in source
    assert 'ITW_CLASH_ETBEnabled",true' in source
    assert 'ITW_CLASH_ETBAccrualInterval",5' in source


def test_income_is_impasses_neutral_rate_and_ignores_its_macro_balance():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_IncomeRate")
    assert "TICKETS_PER_MIN" in body
    assert "ITW_ParamVehicleSpawnAdjustment" in body
    assert "ITW_ParamEnemyAiCnt" in body
    assert "+ 70) / 100" in body
    assert "ITW_CLASH_ETBIncomeScale" in body
    # Both commanders earn it at the same rate: no side adjustment, no side-ops
    # bonus, no defend-phase boost, no zone-start boost.
    for forbidden in [
        "ITW_ParamVehicleSideAdjustment",
        "ITW_SideOpsAdvantage",
        "ITW_ParamDefendPhaseIntensity",
        "ITW_ParamDefendVehBoost",
    ]:
        assert forbidden not in body, forbidden


def test_income_stops_while_the_reserve_is_full():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Accrue")
    assert "ITW_CLASH_ETBCapacity - ([_side] call ITW_CLASH_ETB_fnc_Reserve)" in body
    assert "if (_headroom <= 0) exitWith {false};" in body
    assert "_income min _headroom" in body


def test_reserve_counts_cash_plus_living_value_plus_money_in_flight():
    source = etb()
    reserve = function_body(source, "ITW_CLASH_ETB_fnc_Reserve")
    assert "ITW_CLASH_ETB_fnc_Cash" in reserve
    assert "ITW_CLASH_ETB_fnc_LivingValue" in reserve
    living = function_body(source, "ITW_CLASH_ETB_fnc_LivingValue")
    assert '_x get "holdsReserve"' in living
    # A purchase in flight is spent money, or two demands in one pass both buy.
    assert '"reservations"' in living


def test_price_is_the_row_price_over_impasses_attack_spawn_setting():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Price")
    assert "ITW_VEH_REQD_TICKETS" in body
    assert "ITW_CLASH_ETB_fnc_TypeSpawnAdjustment" in body
    assert "if (_adjustment <= 0) exitWith {-1};" in body
    # Dual rows use the attack settings, as Impasse does.
    adjust = function_body(source, "ITW_CLASH_ETB_fnc_TypeSpawnAdjustment")
    for param in ["Plane", "Heli", "Tank", "Apc", "Car", "Ship"]:
        assert f"ITW_ParamAttack{param}SpawnAdjustment" in adjust
        assert f"ITW_ParamTransport{param}SpawnAdjustment" not in adjust


def test_a_price_over_capacity_is_denied_rather_than_reserved_forever():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Authorize")
    assert "_price > ITW_CLASH_ETBCapacity" in body
    assert '"COST_EXCEEDS_CAPACITY"' in body
    assert body.index("COST_EXCEEDS_CAPACITY") < body.index("INSUFFICIENT_ETB")


def test_authorize_checks_every_limit_and_takes_the_money_before_it_returns():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Authorize")
    for reason in [
        "NO_CANDIDATE",
        "COST_EXCEEDS_CAPACITY",
        "SAFETY_LIMIT",
        "ETB_ROW_CAP",
        "ETB_RESERVE_CAP",
        "INSUFFICIENT_ETB",
    ]:
        assert f'"{reason}"' in body, reason
    # Money and the row slot are taken before anything that can pause.
    assert '_ledger set ["cash",_cash - _price];' in body
    assert '["status","APPROVED"]' in body
    assert "sleep" not in body
    assert "spawn" not in body


def test_row_and_safety_limits_are_per_row_and_per_commander():
    source = etb()
    limit = function_body(source, "ITW_CLASH_ETB_fnc_RowLimit")
    assert "ITW_VEH_MAX" in limit
    assert "ITW_CLASH_ETBRowLimitScale" in limit
    living = function_body(source, "ITW_CLASH_ETB_fnc_RowLiving")
    assert '(_x get "rowIndex") == _rowIndex' in living
    assert '(_y get "rowIndex") == _rowIndex' in living


def test_escrow_only_starts_after_a_real_bypass_and_only_while_reachable():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_MarkBypassed")
    assert "ITW_CLASH_ETB_fnc_Reachable" in body
    assert '_ledger set ["escrow",_need];' in body
    reachable = function_body(source, "ITW_CLASH_ETB_fnc_Reachable")
    assert "ITW_CLASH_ETBCapacity - ([_side] call ITW_CLASH_ETB_fnc_LivingValue)" in reachable
    # Held money is unavailable to a younger demand, but only to a younger one.
    authorize = function_body(source, "ITW_CLASH_ETB_fnc_Authorize")
    assert '_escrow isNotEqualTo "" && {_escrow isNotEqualTo _need}' in authorize


def test_a_failed_purchase_returns_the_money_and_does_not_eat_the_pacing():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Cancel")
    assert '_ledger set ["cash",(_ledger get "cash") + (_reservation get "cost")];' in body
    assert '_ledger set ["pacedUntil",0];' in body
    # A reservation whose spawn never completed cannot hold money forever.
    audit = function_body(source, "ITW_CLASH_ETB_fnc_Audit")
    assert "ITW_CLASH_ETBReservationTimeout" in audit


def test_a_loss_is_never_refunded():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Retire")
    assert "no refund" in body
    # Retiring an asset must not touch cash at all.
    assert 'set ["cash"' not in body


def test_write_offs_cover_crewless_stuck_and_stolen_assets():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Audit")
    assert '"destroyed"' in body
    assert '"side-changed"' in body
    assert '"crew-gone"' in body
    assert '"immobile"' in body
    assert "ITW_CLASH_ETBCrewWriteOff" in body
    assert "ITW_CLASH_ETBImmobileWriteOff" in body
    assert "canMove _veh" in body


def test_idle_release_frees_reserve_room_and_nothing_else():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Audit")
    assert "ITW_CLASH_ETBIdleRelease" in body
    assert '_asset set ["holdsReserve",false];' in body
    assert '"idle-release"' in body
    # No cash back, and the asset stays in the registry for row and safety
    # limits and for re-offering.
    release = body[body.index("ITW_CLASH_ETBIdleRelease"):]
    assert 'set ["cash"' not in release
    assert "ITW_CLASH_ETB_fnc_Retire" not in release


def test_every_purchase_can_be_explained_from_the_log():
    source = etb()
    assert "CLASH ETB | %1 | cash=%2 living=%3 reserve=%4/%5 income=%6/min assets=%7 pending=%8" in source
    assert "CLASH ETB DENIED | %1 | %2 | %3 | %4" in source
    assert "CLASH ETB PURCHASE | %1 | %2 | %3 | row=%4 | cost=%5 | cash %6->%7 | living %8->%9 | threat=%10" in source
    assert "CLASH ETB LOSS | %1 | %2 | cost=%3 | living %4->%5 | reserve %6->%7 | no refund | %8" in source


def test_the_denial_vocabulary_is_complete_and_shared():
    source = etb()
    for reason in [
        "NO_CANDIDATE", "PROGRESSION_LOCKED", "AIRPORT_REQUIRED",
        "COST_EXCEEDS_CAPACITY", "INSUFFICIENT_ETB", "ETB_ROW_CAP",
        "ETB_RESERVE_CAP", "SAFETY_LIMIT", "PACING", "ACTIVE_RESPONDER",
        "IDLE_RESPONDER_REOFFERED", "THREAT_GONE", "SPAWN_FAILED",
        "HAL_REGISTRATION_FAILED",
    ]:
        assert f'"{reason}"' in source, reason
    assert "ITW_CLASH_ETBDenialReasons = [" in source


def test_needs_and_capabilities_are_the_decided_four_and_two():
    source = etb()
    assert 'ITW_CLASH_ETBNeeds = ["ANTI_ARMOR","COUNTER_AIR"];' in source
    assert 'ITW_CLASH_ETBCapabilities = ["GROUND_ANTI_ARMOR","ANTI_ARMOR_CAS","CAP_AIRCRAFT","SPAA"];' in source


def test_a_dry_run_decides_everything_and_buys_nothing():
    source = etb()
    body = function_body(source, "ITW_CLASH_ETB_fnc_Authorize")
    assert "if (ITW_CLASH_ETBDryRun) exitWith {" in body
    assert "CLASH ETB DRYRUN" in body
    assert '["status","DRY_RUN"]' in body
    # It runs after every limit has been evaluated, so the log is the real answer.
    assert body.index("INSUFFICIENT_ETB") < body.index("ITW_CLASH_ETBDryRun")
    assert 'ITW_CLASH_ETBDryRun",false' in source


def test_the_ledger_is_never_persisted_so_a_load_starts_at_the_starting_reserve():
    source = etb()
    code = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    code = re.sub(r"//[^\n]*", " ", code)
    assert "profileNamespace" not in code
    assert "ITW_CLASH_ETB_fnc_Reset" in source
    reset = function_body(source, "ITW_CLASH_ETB_fnc_Reset")
    assert "ITW_CLASH_ETBLedgers = createHashMap;" in reset


def test_etb_loads_before_threat_coverage_and_warns_when_it_cannot():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_EmergingThreatsBudget.sqf"' in init
    assert "etb-missing-or-prereq-failed" in init
    assert init.index("ITW_CLASH_EmergingThreatsBudget.sqf") < init.index(
        "ITW_CLASH_HALThreatCoverage.sqf"
    )
