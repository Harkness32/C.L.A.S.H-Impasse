from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def coverage() -> str:
    return (MISSION / "ITW_CLASH_HALThreatCoverage.sqf").read_text(encoding="utf-8")


def function(source: str, name: str) -> str:
    start = source.index(name + " = {")
    return source[start:source.index("\n};", start)]


def test_every_purchase_goes_through_cover():
    # Live run: seven kinds each bought CAS on their own 45s cooldown, and
    # usable coverage is sampled once per pass, so one pass could buy several.
    source = coverage()
    evaluate = function(source, "ITW_CLASH_HALThreatCoverage_fnc_Evaluate")
    assert "fnc_Request" not in evaluate
    assert evaluate.count("ITW_CLASH_HALThreatCoverage_fnc_Cover;") == 2
    assert source.count("ITW_CLASH_HALThreatCoverage_fnc_Request;") == 1


def test_idle_purchases_are_reoffered_to_hal_before_buying():
    cover = function(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Cover")
    idle = cover.index("_idle isNotEqualTo []")
    interval = cover.index('"ITW_CLASH_ThreatCoverageBuyAt_" + _capability')
    request = cover.index("ITW_CLASH_HALThreatCoverage_fnc_Request;")
    assert idle < interval < request
    reoffer = cover[idle:interval]
    assert '"idle-reoffer"] call' in reoffer
    assert "ITW_CLASH_HALThreatCoverage_fnc_Offer" in reoffer


def test_fresh_and_idle_purchases_share_one_hal_offer_path():
    source = coverage()
    dispatch = function(source, "ITW_CLASH_HALThreatCoverage_fnc_DispatchPurchased")
    assert "ITW_CLASH_HALThreatCoverage_fnc_Offer" in dispatch
    offer = function(source, "ITW_CLASH_HALThreatCoverage_fnc_Offer")
    assert "call RYD_Dispatcher;" in offer
    assert "call CLASH_fnc_HALAdd_Respond;" in offer
    assert "_attackAv pushBackUnique _group;" in offer
    assert "_reply" not in offer


def test_buy_interval_is_per_capability_not_per_threat_kind():
    cover = function(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Cover")
    assert '"ITW_CLASH_ThreatCoverageBuyAt_" + _capability' in cover
    assert '"ITW_CLASH_ThreatCoverageBuyAt_" + _kind' not in cover
    assert "ITW_CLASH_ThreatCoverageBuyInterval" in coverage()


def test_idle_never_takes_a_busy_resting_or_resupplying_unit():
    idle = function(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Idle")
    assert '"Busy" + str _x' in idle
    assert '"Resting" + str _x' in idle
    assert '"ITW_CLASH_ResupplyClaimed"' in idle
    assert "RYD_AmmoCount" in idle
    resupply = (MISSION / "ITW_CLASH_Resupply.sqf").read_text(encoding="utf-8")
    assert '_group setVariable ["ITW_CLASH_ResupplyClaimed",true];' in resupply


def test_bought_reads_the_markers_force_generation_writes():
    bought = function(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Bought")
    assert '"ITW_CLASH_CheckbookAsset"' in bought
    assert '"ITW_CLASH_GenerationCapability"' in bought
    generation = (MISSION / "ITW_CLASH_ForceGeneration.sqf").read_text(encoding="utf-8")
    assert '_group setVariable ["ITW_CLASH_CheckbookAsset",true];' in generation
    assert '_group setVariable ["ITW_CLASH_GenerationCapability",_capability];' in generation


def test_clash_keeps_no_cap_of_its_own_itw_caps_are_the_authority():
    # ITW's vehicle caps are mission params; a second hard-coded CLASH cap
    # would silently override whatever the host configured.
    assert "MaxLive" not in coverage()


def test_combat_buys_bill_only_itw_attack_or_dual_rows():
    # Live run: 136/140 GROUND_ATTACK_LIGHT buys billed the transport car row
    # (max 99) and 69/115 CAS buys the transport heli row, so ITW's attack
    # caps and spawn-adjustment params never bound.
    generation = (MISSION / "ITW_CLASH_ForceGeneration.sqf").read_text(encoding="utf-8")
    fn = function(generation, "ITW_CLASH_Generation_fnc_SelectBillingDefs")
    assert '_combatOnly = _capabilityKey in ["GROUND_ATTACK_LIGHT","CAS_AIRCRAFT"]' in fn
    row_filter = fn[:fn.index("[_defs,[],{")]
    assert "&& {_def#ITW_VEH_COUNT < _def#ITW_VEH_MAX}" in row_filter
    assert "&& {!_combatOnly || {(_def#ITW_VEH_ROLE) in [ITW_VEH_ROLE_ATTACK,ITW_VEH_ROLE_DUAL]}}" in row_filter


def test_itw_role_rows_and_param_scaling_still_exist():
    enemy = (MISSION / "ITW_Enemy.sqf").read_text(encoding="utf-8", errors="replace")
    assert "ITW_TYPE_VEH_HELI    ,ITW_VEH_ROLE_ATTACK" in enemy
    assert "ITW_TYPE_VEH_HELI    ,ITW_VEH_ROLE_TRANSPORT" in enemy
    attack = (MISSION / "ITW_Attack.sqf").read_text(encoding="utf-8", errors="replace")
    assert "ITW_ParamAttackHeliSpawnAdjustment" in attack
    assert "_x set [ITW_VEH_MAX,_newMax];" in attack


def test_aa_infantry_does_not_count_as_air_cover():
    # Live peer run: an enemy jet killed BLUFOR's helicopters and no air
    # request was raised; AA infantry does not hold air parity.
    evaluate = function(coverage(), "ITW_CLASH_HALThreatCoverage_fnc_Evaluate")
    assert "_aaInfUsable" not in evaluate
    assert "if (count _airDemand > 0 && {count _airCapUsable <= 0}) then {" in evaluate
