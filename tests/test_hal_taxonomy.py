"""CLASH authors the class buckets HAL reads.

HAL composes every bucket as

    RHQ_<b> + RYD_WS_<b>_class - RHQs_<b>
    autofill   curated seed      exclusion

(HQSitRep.sqf:116 onward, HAC_fnc.sqf:5483). All three are plain
mission-namespace arrays and RHQs_* starts empty, so seeding and excluding is a
sanctioned interface rather than a mod edit.

The curated lists are vanilla-era: 15 of the 61 classes run4 fielded were
absent, including both Rooikat variants, the AT Prowler, the LAT rifleman and
the Littlebird. HAL's autofill does cover them, so this is not a rescue - it is
a better-informed source for the part CLASH already decides, since
ProtectionGrade is a concept HAL has no equivalent of.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def taxonomy() -> str:
    return text("ITW_CLASH_HALTaxonomy.sqf")


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


# --- the interface -------------------------------------------------------

def test_it_writes_hals_own_arrays_and_never_the_mod():
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Apply"))
    assert '"RYD_WS_" + _bucket + "_class"' in body
    assert '"RHQs_" + _bucket' in body


def test_hal_is_not_edited():
    hal = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL" / "HQSitRep.sqf"
    assert "ITW_CLASH" not in hal.read_text(encoding="utf-8", errors="ignore")


def test_a_bucket_is_never_both_seeded_and_excluded():
    """RHQs_* subtracts from the composed list, so doing both cancels our seed."""
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Apply"))
    start = body.index("if (_bucket in _mine) then {")
    mine = body[start:body.index("} else {", start)]
    assert "_exclude = _exclude - [_class]" in mine
    assert "_seed pushBack _class" in mine
    other = body[body.index("} else {", start):]
    assert "_seed = _seed - [_class]" in other
    assert "_exclude pushBack _class" in other


def test_it_only_speaks_for_the_buckets_it_declares():
    source = taxonomy()
    body = code_only(function_body(source, "ITW_CLASH_HALTaxonomy_fnc_Apply"))
    assert "ITW_CLASH_HALTaxonomyPrimaries + ITW_CLASH_HALTaxonomyCapabilities" in body
    # Recon, SpecFor, Cargo and Crew are semantic or outside what CLASH reads,
    # so they stay with the autofill and must not appear in either list.
    declared = source[source.index("ITW_CLASH_HALTaxonomyPrimaries ="):
                      source.index("ITW_CLASH_HALTaxonomy_fnc_Log")]
    for untouched in ("recon", "specFor", "Cargo", "Crew", "Support", "Other"):
        assert untouched not in declared, untouched


# --- the autofill interaction -------------------------------------------

def test_every_primary_is_one_of_the_eleven_that_suppress_autofill():
    """RYD_PresentRHQ only classifies classes absent from RYD_WS_AllClasses.

    AllClasses is built from Inf + Art + HArmor + MArmor + LArmor + Cars + Air
    + Naval + Static + Support + Other (HAC_fnc2.sqf:2177). A primary bucket
    outside that set would not suppress the autofill, so the class would be
    classified twice and could land in two contradictory buckets.
    """
    hal = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAC_fnc2.sqf").read_text(
        encoding="utf-8", errors="ignore")
    line = [l for l in hal.splitlines() if "RYD_WS_AllClasses = RYD_WS_Inf_class" in l][0]
    suppressing = set(re.findall(r"RYD_WS_(\w+?)_class", line))

    source = taxonomy()
    primaries = re.search(r'ITW_CLASH_HALTaxonomyPrimaries = \[([^\]]*)\]', source).group(1)
    for bucket in re.findall(r'"(\w+)"', primaries):
        assert bucket in suppressing, f"{bucket} does not suppress the autofill"


def test_capability_buckets_are_knowingly_not_suppressing():
    # LArmorAT, ATinf, AAinf, StaticAA and StaticAT are NOT in AllClasses, which
    # is exactly why every class also gets a primary bucket.
    hal = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAC_fnc2.sqf").read_text(
        encoding="utf-8", errors="ignore")
    line = [l for l in hal.splitlines() if "RYD_WS_AllClasses = RYD_WS_Inf_class" in l][0]
    suppressing = set(re.findall(r"RYD_WS_(\w+?)_class", line))
    source = taxonomy()
    caps = re.search(r'ITW_CLASH_HALTaxonomyCapabilities = \[([^\]]*)\]', source).group(1)
    for bucket in re.findall(r'"(\w+)"', caps):
        assert bucket not in suppressing, bucket


def test_a_classified_class_always_gets_a_primary():
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert 'if (_primary isEqualTo "") exitWith {[]}' in body


# --- the classification itself ------------------------------------------

def test_armour_is_decided_by_grade_plus_corroboration():
    """Grade alone was not enough, and this test used to say it was.

    run5 disproved it: config `armor` in Arma is structural hitpoints rather
    than protection, so grade 1 held the Rooikat and Marshall together with
    truck_01_transport, truck_01_covered, three MRAPs and the armed Prowler.
    HAL's own autofill puts those Car-based classes in RHQ_Cars correctly, so
    the module was overriding a right answer with a worse one.

    Light armour now needs grade AND either a chassis the engine itself calls
    armour or the ability to fight armour. Note isKindOf is inheritance, not a
    name list, so the no-hardcoded-classnames rule still holds - that part of
    the old name was right.
    """
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert "ITW_CLASH_AirPicture_fnc_ProtectionGrade" in body
    assert '_grade >= 2 && {_class isKindOf "Tank"}): {"HArmor"}' in body
    assert '_grade >= 1 && {_armouredChassis || {_antiArmor}}): {"LArmor"}' in body
    assert 'default {"Cars"}' in body
    # The form that admitted trucks is gone for good.
    assert '_grade >= 1): {"LArmor"}' not in body


def test_larmorat_is_a_promotion_for_light_armour_only():
    """HAL's anti-armour pool is [airCAS, HArmorG, LArmorATG, ATInfG]
    (HAC_fnc.sqf:1382). LArmorG is absent, so plain light armour is never sent
    at tanks and LArmorAT is the exception that promotes a light hull which can
    kill armour into the response.

    A tank is already in HArmor, which is already in that pool at the same
    weight, so adding it to LArmorAT as well would enter the same vehicle twice
    and double its dispatch weight against armour.
    """
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert 'if (_primary isEqualTo "LArmor" && {_antiArmor}) then {' in body
    # The grade-only form double-counted tank destroyers.
    assert 'if (_grade >= 1 && {_antiArmor}) then {_capabilities pushBack "LArmorAT"}' not in body


def test_a_soft_vehicle_with_a_launcher_is_not_promoted():
    # A grade-0 hull gets primary Cars, so it can never reach the LArmor arm.
    # That pool is what HAL dispatches at armour; a Prowler AT in it is the
    # "AT truck drives at a tank" behaviour we removed once already.
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    promotion = body.index('_primary isEqualTo "LArmor" && {_antiArmor}')
    primary = body.index('default {"Cars"}')
    assert primary < promotion, "the primary must be settled before promoting"


def test_the_promotion_is_what_hal_cannot_reach_on_its_own():
    """The substantive difference, and the reason this module exists.

    HAL decides AT by guidance:
        _isAT = ((irLock + laserLock) > 0) and ...      HAC_fnc2.sqf
    CLASH decides it by role, from BI's own AI usage hint:
        (floor (_flags / 512)) mod 2 == 1               aiAmmoUsageFlags

    A tank gun firing APFSDS has no irLock and no laserLock, so a gun-armed
    wheeled AFV is not AT to HAL, is therefore never promoted into LArmorAT,
    and sits in LArmor - which is not in the anti-armour pool at all. HAL will
    not send it against tanks. This module will.
    """
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert "ITW_CLASH_AirPicture_fnc_ClassProfile" in body
    # Which routes to IsAntiArmourAmmo, not to any lock test.
    profile = code_only(function_body(text("ITW_CLASH_AirPicture.sqf"),
                                      "ITW_CLASH_AirPicture_fnc_ClassProfile"))
    assert "ITW_CLASH_DualHAL_fnc_IsAntiArmourAmmo" in profile
    assert "irLock" not in profile and "laserLock" not in profile


def test_artillery_is_decided_by_its_scanner():
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert "artilleryScanner" in body
    assert body.index("artilleryScanner") < body.index('"HArmor"')


def test_no_hard_coded_class_lists():
    """The whole point: this has to survive the port to a new faction."""
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert not re.search(r'"[boi]_[a-z0-9_]+_f"', body, re.I), "hard-coded classname"
    assert "ITW_CLASH_AirPicture_fnc_ClassProfile" in body


def test_infantry_at_and_aa_come_from_the_weapon_profile():
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    start = body.index("if (_isMan) then {")
    man = body[start:body.index("} else {", start)]
    assert '_capabilities pushBack "ATinf"' in man
    assert '_capabilities pushBack "AAinf"' in man
    assert '_primary = "Inf"' in man


def test_guided_versus_unguided_at_is_not_faked_here():
    """Hark's portability requirement, deliberately deferred rather than
    half-answered: HAL's ATinf bucket cannot express the distinction, so
    asserting it here would hide the problem."""
    source = taxonomy()
    assert "Guided versus unguided" in source
    body = code_only(function_body(source, "ITW_CLASH_HALTaxonomy_fnc_Classify"))
    assert "antiAirMissile" not in body
    assert "AmmoIsGuided" not in body


# --- cost and safety ----------------------------------------------------

def test_a_class_costs_its_config_walk_once():
    sweep = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Sweep"))
    assert "if (_class in ITW_CLASH_HALTaxonomyDecided) then {continue}" in sweep
    # Including the ones we decline, or they are retried every poll forever.
    assert 'ITW_CLASH_HALTaxonomyDecided set [_class,["<autofill>",[],-1]]' in sweep


def test_an_unconfident_class_is_left_to_the_autofill():
    sweep = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Sweep"))
    deferred = sweep[sweep.index("_verdict isEqualTo []"):]
    assert "fnc_Apply" not in deferred[:400]
    assert "deferred" in deferred


def test_every_decision_is_logged():
    # Authority without a record is what cost four runs of inference.
    sweep = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Sweep"))
    assert '"classified"' in sweep
    assert '"deferred"' in sweep
    assert "_seeded,_excluded" in sweep


def test_advisory_mode_writes_nothing():
    sweep = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Sweep"))
    advisory = sweep[sweep.index("ITW_CLASH_HALTaxonomyAdvisoryOnly"):]
    gated = advisory[:advisory.index("fnc_Apply")]
    assert "would-classify" in gated
    assert "continue" in gated


def test_the_taxonomy_is_global_not_per_side():
    """The arrays are classname lists every commander reads, so there is no
    per-side taxonomy to build and attempting one would be incoherent."""
    body = code_only(function_body(taxonomy(), "ITW_CLASH_HALTaxonomy_fnc_Present"))
    assert "vehicles + allUnits" in body
    assert "side" not in body
    assert "ITW_PlayerSide" not in body


def test_it_is_wired_in_behind_the_usual_guard():
    init = text("init.sqf")
    assert 'fileExists "ITW_CLASH_HALTaxonomy.sqf"' in init
    assert "hal-taxonomy-missing-or-prereq-failed" in init
    # Needs the air picture: ClassProfile and ProtectionGrade live there.
    block = init[init.index("ITW_CLASH_HALTaxonomy.sqf") - 300:]
    assert "_airPictureLoaded" in block[:400]


def test_it_appears_in_the_preflight_manifest():
    assert '["ITW_CLASH_HALTaxonomy","hal taxonomy"' in text("ITW_CLASH_DebugPreflight.sqf")
