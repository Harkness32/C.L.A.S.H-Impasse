import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")


def doctrine() -> str:
    return text(MISSION / "ITW_CLASH_SOFDoctrine.sqf")


def function(source: str, name: str) -> str:
    start = source.index(name + " = {")
    return source[start:source.index("\n};", start)]


def sqf_list(source: str, name: str) -> list:
    body = source[source.index(name + " = ["):]
    body = body[:body.index("];")]
    return re.findall(r'"([^"]*)"', body)


def sqf_families(source: str, name: str) -> list:
    body = source[source.index(name + " = ["):]
    body = body[:body.index("\n];")]
    return [
        (family, re.findall(r'"([^"]*)"', words))
        for family, words in re.findall(r'\["([^"]+)",\[([^\]]*)\]\]', body)
    ]


def families(source: str, class_name: str, display: str, faction: str, subcategory: str, vehicle_class: str) -> set:
    # Python mirror of ITW_CLASH_SOF_fnc_ClassFamilies, fed from the SQF's own lists.
    key = class_name.lower()
    identity = " ".join([class_name, display, faction, subcategory, vehicle_class]).lower()
    words = [w for w in re.split(r"[ _\-/\\.:()\[\]{},]+", identity) if w]
    words += [a + b for a, b in zip(words, words[1:]) if len(a) >= 3 and len(b) >= 3]
    found = set()
    for family, prefixes in sqf_families(source, "ITW_CLASH_SOFClassPrefixes"):
        if any(key.startswith(p) for p in prefixes):
            found.add(family)
    for family, aliases in sqf_families(source, "ITW_CLASH_SOFTokenFamilies"):
        if any(a in words for a in aliases):
            found.add(family)
    generic = sqf_list(source, "ITW_CLASH_SOFGenericWords")
    snipers = sqf_list(source, "ITW_CLASH_SOFSniperWords")
    if any(w in words for w in generic) and not any(w in words for w in snipers):
        found.add("special-forces")
    return found


# Real config identities read from the vanilla and Workshop PBOs
# (class, displayName, faction, editorSubcategory, vehicleClass). Vanilla
# display names are $STR keys, left blank: the rule must not need them.
SOF_UNITS = [
    ("B_recon_F", "", "BLU_F", "EdSubcat_Personnel_SpecialForces", "MenRecon"),
    ("B_recon_M_F", "", "BLU_F", "EdSubcat_Personnel_SpecialForces", "MenRecon"),
    ("O_R_recon_AR_F", "", "OPF_R_F", "EdSubcat_Personnel_SpecialForces", "MenRecon"),
    ("O_T_Recon_TL_F", "", "OPF_T_F", "EdSubcat_Personnel_SpecialForces", "MenRecon"),
    ("B_CTRG_Soldier_AR_tna_F", "", "BLU_CTRG_F", "EdSubcat_Personnel_Pacific", "Men"),
    ("O_V_Soldier_hex_F", "", "OPF_F", "EdSubcat_Personnel_Viper", "Men"),
    ("rhsusf_usmc_recon_marpat_wd_rifleman", "", "rhs_faction_usmc_wd", "rhs_EdSubcat_infantry_recon", "rhs_vehclass_infantry_recon"),
    ("rhsusf_socom_marsoc_cso", "", "rhs_faction_socom", "rhs_EdSubcat_MARSOC", "rhs_vehclass_MARSOC"),
    ("CUP_B_GER_Soldier", "", "CUP_B_GER", "EdSubcat_Personnel_KSK_DES", "CUP_B_Men_GER"),
    ("CUP_B_FR_Soldier_TL", "", "CUP_B_USMC", "CUP_EdSubcat_Personel_ForceRecon", "CUP_B_Men_USMC_FR"),
    ("CUP_B_US_SpecOps", "Operator", "CUP_B_US_Army", "EdSubcat_Personnel_SpecialForces", "CUP_B_Men_US_DeltaForce"),
]

LINE_UNITS = [
    ("B_Soldier_F", "", "BLU_F", "EdSubcat_Personnel", "Men"),
    ("B_Soldier_SL_F", "", "BLU_F", "EdSubcat_Personnel", "Men"),
    ("O_Soldier_F", "", "OPF_F", "EdSubcat_Personnel", "Men"),
    ("I_soldier_F", "", "IND_F", "EdSubcat_Personnel", "Men"),
    ("O_R_Soldier_AR_F", "", "OPF_R_F", "EdSubcat_Personnel", "Men"),
    ("B_soldier_UAV_F", "", "BLU_F", "EdSubcat_Personnel", "Men"),
    ("B_Patrol_Soldier_UAV_F", "", "BLU_F", "EdSubcat_Personnel_CombatPatrol", "Men"),
    ("CUP_B_US_Soldier_AA_UCP", "", "CUP_B_US_Army", "CUP_EdSubcat_Personel_UCP", "CUP_B_Men_US_Army_UCP"),
    ("rhs_vdv_rifleman", "", "rhs_faction_vdv", "rhs_EdSubcat_infantry_emr", "rhs_vehclass_infantry_emr"),
    # Snipers share the SF subcategory but keep HAL's native sniper role.
    ("B_sniper_F", "", "BLU_F", "EdSubcat_Personnel_SpecialForces", "MenSniper"),
    ("B_spotter_F", "", "BLU_F", "EdSubcat_Personnel_SpecialForces", "MenSniper"),
    ("B_ghillie_ard_F", "", "BLU_F", "EdSubcat_Personnel_SpecialForces", "MenSniper"),
]


def test_vanilla_and_mod_special_forces_classify_without_manual_flags():
    source = doctrine()
    for row in SOF_UNITS:
        assert families(source, *row), row
    assert families(source, *SOF_UNITS[5]) == {"viper"}


def test_line_infantry_snipers_and_drone_operators_stay_conventional():
    source = doctrine()
    for row in LINE_UNITS:
        assert not families(source, *row), row


def test_class_identity_comes_from_config_and_is_cached():
    source = doctrine()
    assert "ITW_CLASH_SOFClassifierVersion = 3;" in source
    body = function(source, "ITW_CLASH_SOF_fnc_ClassFamilies")
    for field in ['"displayName"', '"faction"', '"editorSubcategory"', '"vehicleClass"']:
        assert f"getText (_cfg >> {field})" in body
    assert "CfgFactionClasses" not in body
    assert "ITW_CLASH_SOFClassFamilyCache set [_key,_families];" in body
    assert "(count _first) >= 3 && {(count _second) >= 3}" in body
    classify = function(source, "ITW_CLASH_SOF_fnc_Classify")
    assert "} forEach ([_x] call ITW_CLASH_SOF_fnc_ClassFamilies);" in classify
    # Named families label a group over the generic one.
    assert 'private _named = _qualifying select {(_x#0) != "special-forces"};' in classify


def test_each_side_keeps_line_infantry_when_its_faction_is_mostly_sof():
    source = doctrine()
    assert 'missionNamespace getVariable ["ITW_CLASH_SOFMaxShare",0.25]' in source
    assert 'missionNamespace getVariable ["ITW_CLASH_SOFMinTeams",4]' in source
    slot = function(source, "ITW_CLASH_SOF_fnc_SideSlot")
    assert "(ITW_CLASH_SOFMinTeams max (floor (ITW_CLASH_SOFMaxShare * _total))) min (floor (_total / 2))" in slot
    assert '_x != _group && {_x getVariable ["ITW_CLASH_ReconSOFLatched",false]}' in slot
    for pool in ["ITW_CLASH_ManagedGroups", "ITW_CLASH_DualHALBLUFORGroups", "ITW_CLASH_DualHALOPFORExtraGroups"]:
        assert pool in slot

    classify = function(source, "ITW_CLASH_SOF_fnc_Classify")
    held = classify.index("call ITW_CLASH_SOF_fnc_SideSlot;")
    assert held < classify.index('_group setVariable ["ITW_CLASH_ReconSOFLatched",true];', held)
    assert '_anchorObjective >= 0' in classify
    assert '_family = "held-conventional";' in classify
    assert '"sof-doctrine-held-conventional"' in classify
    # Manual policy still wins before any cap.
    assert classify.index('"ITW_CLASH_ReconSOFManual"') < held


def test_new_sof_functions_are_finalized_with_the_doctrine():
    loader = text(MISSION / "ITW_CLASH_SOFDoctrineBootstrap.sqf")
    finalize = loader[loader.index("if (_sofLoaded) then {\n        _finalizers append"):]
    for name in ["ITW_CLASH_SOF_fnc_ClassFamilies", "ITW_CLASH_SOF_fnc_SideSlot", "ITW_CLASH_SOF_fnc_Classify"]:
        assert f'"{name}"' in finalize[:finalize.index("];")]
