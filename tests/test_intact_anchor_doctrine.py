from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_anchor_functions_are_in_bootstrap_finalization_window():
    bootstrap = text("ITW_CLASH_Bootstrap.sqf")
    assert '"ITW_CLASH_fnc_SelectAnchorGroup"' in bootstrap
    assert '"ITW_CLASH_fnc_AuditAnchors"' in bootstrap
    assert "_patchVersion != 4" in bootstrap


def test_weak_anchor_fallback_is_rejected_without_rewriting_strong_scoring():
    patch = text("ITW_CLASH_RuntimePatch.sqf")
    assert "ITW_CLASH_fnc_SelectAnchorGroup_V6Base" in patch
    assert "_this call ITW_CLASH_fnc_SelectAnchorGroup_V6Base" in patch
    assert "_conscious < ITW_CLASH_MinAnchorSoldiers" in patch
    assert '"anchor-weak-candidate-rejected"' in patch
    assert "grpNull" in patch


def test_existing_anchor_below_six_is_demoted_and_refill_requested():
    patch = text("ITW_CLASH_RuntimePatch.sqf")
    assert "ITW_CLASH_fnc_AuditAnchors_V6Base" in patch
    assert '[_objectiveIndex,"below-minimum-strength"] call ITW_CLASH_fnc_ClearAnchorSlot;' in patch
    assert '[_objectiveIndex,"vacant",ITW_CLASH_MinAnchorSoldiers] call ITW_CLASH_fnc_RequestAnchorRefill;' in patch
    assert '"anchor-degraded-demoted"' in patch


def test_anchor_patch_preserves_audit_grace_and_transition_guards():
    patch = text("ITW_CLASH_RuntimePatch.sqf")
    assert "ITW_CLASH_Transitioning" in patch
    assert "ITW_CLASH_AnchorAuditReadyAt" in patch
    assert "ITW_CLASH_RegistrationFrozenUntil" in patch


def test_anchor_overrides_are_finalized_after_patch():
    patch = text("ITW_CLASH_RuntimePatch.sqf")
    assert '"ITW_CLASH_fnc_SelectAnchorGroup_V6Base"' in patch
    assert '"ITW_CLASH_fnc_SelectAnchorGroup"' in patch
    assert '"ITW_CLASH_fnc_AuditAnchors_V6Base"' in patch
    assert '"ITW_CLASH_fnc_AuditAnchors"' in patch
    assert "ITW_CLASH_RuntimePatchVersion = 4;" in patch
