import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def cram() -> str:
    return text("ITW_CLASH_RearBaseCRAM.sqf")


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


def code_only(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def test_the_cram_is_furniture_not_a_purchase():
    source = code_only(cram())
    # Unbilled and uncounted: no Impasse ticket, no ITW_VehDef, no ETB asset.
    for forbidden in [
        "ITW_VehDef",
        "ITW_TICKET_REDUCE",
        "ITW_VEH_COUNT_INCR",
        "ITW_CLASH_ETB_fnc_Authorize",
        "ITW_CLASH_ETBAsset",
    ]:
        assert forbidden not in source, forbidden


def test_hal_is_never_told_about_it():
    source = code_only(cram())
    assert "ITW_CLASH_DualHAL_fnc_RegisterGroup" not in source
    # Held out of the dispatch pools defensively in case something else adopts
    # it. Set in fnc_Crew since v2, so a re-crewed piece is held out too - a
    # replacement crew that HAL could dispatch would walk the gun off its base.
    body = function_body(cram(), "ITW_CLASH_RearBaseCRAM_fnc_Crew")
    assert '"RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"' in body
    for pool in ["RydHQ_AttackAv", "RydHQ_FlankAv", "RydHQ_Garrison"]:
        assert pool not in source, pool


def test_the_class_comes_from_the_faction_not_a_hard_coded_list():
    source = cram()
    body = function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_SelectClass")
    # Impasse already scans each faction's config for static AA weapons.
    assert "va_pStaticAAClasses" in body
    assert "va_eStaticAAClasses" in body
    # A radar piece is preferred, so a real C-RAM wins over a tripod launcher.
    assert '"radar"' in body
    # No Arma classname is hard-coded anywhere in the file.
    assert "B_AAA" not in source
    assert "O_SAM" not in source
    assert "B_SAM" not in source


def test_it_feeds_the_coverage_rule_that_already_exists():
    body = function_body(cram(), "ITW_CLASH_RearBaseCRAM_fnc_Spawn")
    assert 'setVariable ["ITW_CLASH_CRAM",true,true]' in body
    # And the weight it unlocks is the decided one: 1.0 inside a 3 km umbrella,
    # tested ahead of the radar weighting because a C-RAM's reach is short.
    picture = text("ITW_CLASH_AirPicture.sqf")
    profile = function_body(picture, "ITW_CLASH_AirPicture_fnc_AirDefenceProfile")
    assert '["CRAM",1,ITW_CLASH_AirPictureCRAMUmbrella]' in profile
    assert profile.index("ITW_CLASH_CRAM") < profile.index('"RADAR_SAM"')


def test_it_is_destructible_and_comes_back_five_minutes_later():
    source = cram()
    assert 'ITW_CLASH_RearBaseCRAMRespawn",300' in source
    body = function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_Maintain")
    assert "ITW_CLASH_RearBaseCRAMRespawn" in body
    assert '"destroyed"' in body
    assert '"replaced"' in body
    # A dead gunner counts as dead: an unmanned static covers nothing.
    assert "isNull (gunner _veh)" in body


def test_it_is_placed_off_the_spawn_point():
    source = cram()
    body = function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_RearPosition")
    assert "ITW_CLASH_RearBaseCRAMOffset" in body
    assert "BIS_fnc_findSafePos" in body
    assert 'ITW_CLASH_RearBaseCRAMOffset",80' in source


def test_it_loads_behind_the_air_picture():
    init = text("init.sqf")
    assert 'call compile preprocessFileLineNumbers "ITW_CLASH_RearBaseCRAM.sqf"' in init
    assert "rear-base-cram-missing-or-prereq-failed" in init
    assert init.index("ITW_CLASH_AirPicture.sqf") < init.index("ITW_CLASH_RearBaseCRAM.sqf")


# ------------------------------ a faction with no static AA still gets cover

def test_it_falls_back_to_the_factions_own_aa_vehicle():
    # 134 failed polls per side over 70 minutes, zero emplacements: these
    # factions field no StaticAAWeapon at all, so static-only is an outage.
    body = function_body(cram(), "ITW_CLASH_RearBaseCRAM_fnc_SelectClass")
    assert "va_pStaticAAClasses" in body and "va_eStaticAAClasses" in body
    assert "va_pAAClasses" in body and "va_eAAClasses" in body
    # Static is still preferred: the fallback only runs when static came back empty.
    static = body.index("va_pStaticAAClasses")
    mobile = body.index("va_pAAClasses")
    assert static < mobile
    assert "if (_classes isEqualTo []) then {" in body


def test_the_fallback_still_has_to_shoot_at_aircraft():
    body = function_body(cram(), "ITW_CLASH_RearBaseCRAM_fnc_SelectClass")
    assert '([_x] call ITW_CLASH_AirPicture_fnc_ClassProfile) get "antiAir"' in body
    # Guarded, and parenthesised: "call f get x" does not bind as it reads.
    assert 'isNil "ITW_CLASH_AirPicture_fnc_ClassProfile"' in body


def test_a_crammed_vehicle_cannot_be_driven_away():
    source = cram()
    # Crewing moved into fnc_Crew in v2 so an uncrewed piece can be re-crewed
    # in place rather than replaced; the gunner-only rule is unchanged.
    body = function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_Crew")
    assert "moveInGunner _veh" in body
    assert "moveInDriver" not in code_only(source)
    assert '_veh setVariable ["ITW_CLASH_CRAM",true,true]' in source


def test_the_overwatch_sweep_leaves_it_alone():
    overwatch = text("ITW_CLASH_SPAAOverwatch.sqf")
    body = function_body(overwatch, "ITW_CLASH_SPAAOverwatch_fnc_Adopt")
    assert 'getVariable ["ITW_CLASH_CRAM",false]) exitWith {false}' in body
    # And it is refused before the capacity test, so it never costs a slot.
    assert body.index("ITW_CLASH_CRAM") < body.index("AtCapacity")


def test_having_nothing_to_emplace_is_said_once_per_side():
    source = cram()
    body = function_body(source, "ITW_CLASH_RearBaseCRAM_fnc_Spawn")
    assert "ITW_CLASH_RearBaseCRAMSilenced" in body
    assert "if !(_key in ITW_CLASH_RearBaseCRAMSilenced) then {" in body
    assert "ITW_CLASH_RearBaseCRAMSilenced = [];" in source
