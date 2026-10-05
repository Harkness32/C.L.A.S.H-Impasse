"""Two defects run5 proved, both of them mine.

1. ITW_CLASH_HALCargoDiceFix failed closed every boot:
       CLASH BOOT | WARNING | hal-cargo-dice-fix-failed |
         reason=SCargo-base-embark-entry:signature-missing
   The multi-line anchors were written with \\n escapes, and SQF has no
   backslash escapes in string literals - so the search string contained a
   literal backslash and n, which cannot match HAL's source. The replacement
   carried the same literals, so even a match would have injected them into the
   compiled source and failed the recompile. The base-embark fast path had
   therefore never executed.

2. ITW_CLASH_HALTaxonomy classified trucks as light armour. Config `armor` in
   Arma is structural hitpoints, not protection, so a heavy truck outscores a
   small hard vehicle. run5 put truck_01_transport, truck_01_covered, three
   MRAPs and the armed Prowler in LArmor alongside the Rooikat.
"""

import io
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


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


def code_only(body: str) -> str:
    body = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)
    return re.sub(r"//[^\n]*", " ", body)


# --- 1. the SCargo anchors --------------------------------------------------

def test_no_anchor_relies_on_a_backslash_escape():
    """SQF string literals have no escapes, so a \\n in one is two characters."""
    source = code_only(read(MISSION / "ITW_CLASH_HALCargoDiceFix.sqf"))
    assert "\\n" not in source


def test_the_newline_comes_from_tostring():
    source = read(MISSION / "ITW_CLASH_HALCargoDiceFix.sqf")
    assert "private _nl = toString [10];" in source
    assert "_exitLine + _nl + _nl" in source


def test_every_scargo_anchor_matches_hals_real_source_exactly_once():
    """The test the original anchors would have failed.

    Reproduces what the patch does - read HAL's SCargo, strip CR, then look for
    each signature - and requires exactly one match each. Zero means the patch
    fails closed; more than one means it would edit the wrong place.
    """
    src = read(HAL / "SCargo.sqf").replace("\r", "")
    exit_line = (
        'if ((_enmyNrb) and not (_request)) exitwith '
        '{_unitG setVariable ["CargoChosen",false,true];'
        '_unitG setVariable [("CC" + (str _unitG)), true, true]};'
    )
    anchors = {
        "air-lift-dice": (
            '(((count ((_HQ getVariable ["RydHQ_AAthreat",[]]) + '
            '(_HQ getVariable ["RydHQ_Airthreat",[]]))) == 0) or '
            '(random 100 > (85/(0.5 + (2*(_HQ getVariable ["RydHQ_Recklessness",0.5]))))))'
        ),
        "base-embark-entry": exit_line + "\n\n_lz = objNull;",
        "base-embark-physical-fallback":
            'if (((_ChosenOne emptyPositions "Cargo") > 0) and not (_request)) then',
    }
    for name, anchor in anchors.items():
        assert src.count(anchor) == 1, (name, src.count(anchor))


def test_the_old_escaped_anchor_really_could_not_match():
    """Guards the diagnosis itself, so nobody reintroduces the escape form."""
    src = read(HAL / "SCargo.sqf").replace("\r", "")
    broken = (
        'if ((_enmyNrb) and not (_request)) exitwith '
        '{_unitG setVariable ["CargoChosen",false,true];'
        '_unitG setVariable [("CC" + (str _unitG)), true, true]};'
        '\\n\\n_lz = objNull;'
    )
    assert src.count(broken) == 0


def test_the_cr_strip_is_still_needed():
    """NR6 ships CRLF; the anchors are authored with LF."""
    raw = io.open(HAL / "SCargo.sqf", "rb").read()
    assert b"\r\n" in raw
    source = read(MISSION / "ITW_CLASH_HALCargoDiceFix.sqf")
    assert "splitString (toString [13])" in source


# --- 2. light armour needs corroboration -----------------------------------

def test_light_armour_needs_more_than_a_grade():
    body = code_only(function_body(read(MISSION / "ITW_CLASH_HALTaxonomy.sqf"),
                                   "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert '_grade >= 1 && {_armouredChassis || {_antiArmor}}' in body
    # The bare form that put trucks in LArmor is gone.
    assert "case (_grade >= 1): {\"LArmor\"}" not in body


def test_the_corroboration_is_chassis_or_anti_armour():
    body = code_only(function_body(read(MISSION / "ITW_CLASH_HALTaxonomy.sqf"),
                                   "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert '_armouredChassis = _class isKindOf "Tank"' in body
    assert 'isKindOf "Wheeled_APC_F"' in body


def test_the_rooikat_still_reaches_the_at_armour_pool():
    """Why the anti-armour half of the corroboration has to be there.

    run5: b_afv_wheeled_01_cannon_f and _up_cannon_f both came back grade 1
    with LArmorAT, and HAL cannot reach that verdict itself - its AT test is
    guided-only (irLock + laserLock) and a tank gun carries no lock. Requiring
    only an armoured chassis would have risked losing it, so anti-armour
    capability corroborates on its own.
    """
    body = code_only(function_body(read(MISSION / "ITW_CLASH_HALTaxonomy.sqf"),
                                   "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert "{_antiArmor}" in body
    # And the promotion still requires the primary to be LArmor, so a soft
    # hull with a launcher cannot slip into the armour response.
    assert 'if (_primary isEqualTo "LArmor" && {_antiArmor}) then {' in body


def test_heavy_armour_still_requires_a_tank():
    # Components rather than one exact line: the branch gained an anti-armour
    # clause and spans several lines now. Both conditions still hold.
    body = code_only(function_body(read(MISSION / "ITW_CLASH_HALTaxonomy.sqf"),
                                   "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    harmor = body[:body.index('{"HArmor"}')]
    assert "_grade >= 2" in harmor
    assert 'isKindOf "Tank"' in harmor


def test_taxonomy_version_moved():
    # Exact number pinned in test_taxonomy_version_moved_again below.
    version = int(__import__("re").search(r"ITW_CLASH_HALTaxonomyVersion = (\d+);", read(MISSION / "ITW_CLASH_HALTaxonomy.sqf")).group(1))
    assert version >= 2, version


# --- 3. a tank-killer pool needs tank-killers -------------------------------

def test_harmor_requires_the_ability_to_kill_armour():
    """Hark: "namers should not be sent against armor, they are heavily armored
    but their gun cannot do at stuff."

    HArmor is not a description of protection, it is the dispatch pool HAL
    sends at tanks (HAC_fnc.sqf:1382). run6 showed the fault on two more
    classes: b_apc_tracked_01_crv_f (an engineering vehicle) and
    b_apc_tracked_01_aa_f both landed in HArmor with no LArmorAT, so a repair
    vehicle and an air defence vehicle were being dispatched against armour.
    """
    body = code_only(function_body(read(MISSION / "ITW_CLASH_HALTaxonomy.sqf"),
                                   "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    harmor = body[body.index('{"HArmor"}') - 320:body.index('{"HArmor"}')]
    assert "_antiArmor" in harmor
    assert 'isKindOf "Tank"' in harmor
    assert "_grade >= 2" in harmor


def test_demotion_to_larmor_costs_nothing_but_the_armour_pool():
    """Why LArmor is the right home rather than Cars.

    In HAL's dispatch pools, LArmorG appears everywhere HArmorG does - Inf,
    Cars, Art, Static - except Armor. So a heavily armoured vehicle that cannot
    fight armour keeps every role it can perform and loses only the one it
    cannot. This reads HAL's own source so it fails if those pools change.
    """
    hal = read(ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAC_fnc.sqf")
    pools = {}
    for case, pool in re.findall(r'case \("(\w+)"\) :\s*\{\s*_pool = (\[\[.*?\]\])', hal, re.S):
        pools[case] = re.sub(r"\s+", "", pool)
    assert pools, "could not parse HAL's dispatch pools"
    # The pool that matters: HArmor is in it, LArmor is not.
    assert "_HArmorG" in pools["Armor"]
    assert "_LArmorG" not in pools["Armor"]
    # And everywhere else HArmor appears, LArmor does too.
    for case, pool in pools.items():
        if case == "Armor":
            continue
        if "_HArmorG" in pool:
            assert "_LArmorG" in pool, case


def test_an_mbt_is_still_heavy_armour():
    """The rule must not demote actual tanks: an MBT has AT ammo, so it still
    satisfies the capability requirement."""
    body = code_only(function_body(read(MISSION / "ITW_CLASH_HALTaxonomy.sqf"),
                                   "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    # Capability is read from the weapon profile, not a class list.
    assert "ITW_CLASH_AirPicture_fnc_ClassProfile" in body
    assert '_antiArmor = _profile get "antiArmor"' in body
    assert not re.search(r'"[boi]_[a-z0-9_]+_f"', body, re.I), "hard-coded classname"


def test_taxonomy_version_moved_again():
    assert "ITW_CLASH_HALTaxonomyVersion = 3;" in read(MISSION / "ITW_CLASH_HALTaxonomy.sqf")


# --- 4. the base-embark fast path says why it declined -----------------------

def test_every_base_embark_gate_names_itself():
    """Hark wired a fast path to teleport chalks in at base instead of landing
    to board. It is correct and it had never executed - the SCargo anchor it
    installs through could not match (see above), so run6 contains exactly one
    base-embark string and it is the failure line.

    It also had twelve silent false-returns and logged only on success, so a
    helicopter still landing told us nothing about which gate refused. Each
    decline now names itself.
    """
    source = read(MISSION / "ITW_CLASH_HALCargoDiceFix.sqf")
    body = function_body(source, "ITW_CLASH_HALCargoDice_fnc_BaseEmbark")
    # No gate may return a bare false any more.
    assert "exitWith {false}" not in body
    # A floor, not an exact count: the point is that no gate is silent, and
    # the assertion above already proves that. Pinning the number meant a
    # NEW gate ("already-carrying") failed a test about old ones.
    assert body.count("call _decline") >= 12, body.count("call _decline")
    for reason in (
        "disabled", "null-or-dead", "withdrawing", "no-living-troops",
        "player-in-squad", "not-all-on-foot", "no-assigned-driver",
        "carrier-is-cargo", "side-mismatch", "not-enough-seats",
        "troops-not-at-a-base", "different-bases",
    ):
        assert f'"{reason}"' in body, reason


def test_declines_do_not_spam_the_log():
    """SCargo asks again every HAL cycle and the answer rarely changes, so only
    a CHANGE of reason is reported."""
    body = function_body(read(MISSION / "ITW_CLASH_HALCargoDiceFix.sqf"),
                         "ITW_CLASH_HALCargoDice_fnc_BaseEmbark")
    decline = body[body.index("private _decline = {"):body.index("private _troops")]
    assert "ITW_CLASH_BaseEmbarkDeclined" in decline
    assert "isNotEqualTo _reason" in decline


def test_the_decline_logger_still_returns_false():
    """It is used as the gate's return value, so it must be falsy."""
    body = function_body(read(MISSION / "ITW_CLASH_HALCargoDiceFix.sqf"),
                         "ITW_CLASH_HALCargoDice_fnc_BaseEmbark")
    decline = body[body.index("private _decline = {"):body.index("private _troops")]
    assert decline.rstrip().rstrip(";").rstrip().endswith("false\n    }") or "false" in decline.split("};")[-2]


def test_the_fast_path_still_teleports_rather_than_lands():
    """The point of the whole thing: moveInCargo at the base, no boarding run."""
    body = function_body(read(MISSION / "ITW_CLASH_HALCargoDiceFix.sqf"),
                         "ITW_CLASH_HALCargoDice_fnc_BaseEmbark")
    assert "_x assignAsCargo _vehicle;" in body
    assert "_x moveInCargo _vehicle;" in body
    # Both ends must be at the SAME base, or it is a teleport across the map.
    assert "_carrierBase != _troopBase" in body
    # And a partial embarkation rolls back rather than handing SCargo a split squad.
    assert "_failed" in body
