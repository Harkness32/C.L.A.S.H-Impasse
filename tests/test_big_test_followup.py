from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_bootstrap_defers_and_finalizes_affinity_only_allocation_audit():
    bootstrap = mission("ITW_CLASH_SOFDoctrineBootstrap.sqf")

    assert '"ITW_CLASH_fnc_AuditAllocations"' in bootstrap
    assert "ITW_CLASH_InfantryAuthorityAllocationFix.sqf" in bootstrap
    assert "ITW_CLASH_InfantryAuthorityAllocationFix_fnc_SetAffinity" in bootstrap
    assert "allocationDriftReleases=false" in bootstrap
    assert "ITW_CLASH_FieldHardening.sqf" in bootstrap
    assert "field-hardening-scheduled" in bootstrap


def test_allocation_drift_repairs_affinity_without_releasing_hal_infantry():
    allocation = mission("ITW_CLASH_InfantryAuthorityAllocationFix.sqf")

    assert "ITW_CLASH_InfantryAuthorityAllocationFixVersion = 2" in allocation
    assert 'VAR_SET_OBJ_IDX(_group,_newObjective);' in allocation
    assert '"unassigned-adopted"' in allocation
    assert '"invalid-affinity-repaired"' in allocation
    assert '"waypoint-drift"' in allocation
    assert '"anchor"' in allocation
    assert '"ITW_CLASH_Withdrawing"' in allocation
    assert '"ITW_CLASH_CASEVAC_State"' in allocation
    assert '"ITW_CLASH_GroundMEDEVAC_State"' in allocation

    # Persistent tactical authority means allocation is metadata only.
    assert "ITW_CLASH_fnc_ReleaseGroup" not in allocation
    assert "ITW_CLASH_ReeligibleAt" not in allocation
    assert '"objective-allocation-drift"' not in allocation


def test_casevac_abort_clears_only_on_foot_assignment_to_failed_aircraft():
    hardening = mission("ITW_CLASH_FieldHardening.sqf")

    assert "ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal_FieldHardeningBase" in hardening
    assert "assignedVehicle _unit" in hardening
    assert "_assigned == _heli" in hardening
    assert "vehicle _unit == _unit" in hardening
    assert "unassignVehicle _unit;" in hardening
    assert "[_unit] orderGetIn false;" in hardening
    assert '"casevac-abort-assignment-cleared"' in hardening


def test_reconstitution_stale_assignment_repair_preserves_canonical_handoff():
    hardening = mission("ITW_CLASH_FieldHardening.sqf")

    assert "ITW_AtkReconstitutionTransits" in hardening
    assert "ITW_ManagedVehs" in hardening
    assert "assignedVehicles _group" in hardening
    assert "_group leaveVehicle _x" in hardening
    assert "unassignVehicle _x;" in hardening
    assert "[_x] orderGetIn false;" in hardening
    assert '"reconstitution-stale-assignment-cleared"' in hardening

    # The hardening observer may repair assignment state, but must never perform
    # the authoritative reconstitution acknowledgement itself.
    assert "ITW_CLASH_fnc_AcknowledgeReconstitution" not in hardening


def test_recon_saved_native_handles_are_nil_safe():
    hardening = mission("ITW_CLASH_FieldHardening.sqf")

    for name in [
        "ITW_CLASH_Recon_fnc_NativeGoRecon",
        "ITW_CLASH_Recon_fnc_NativeGoDefRecon",
        "ITW_CLASH_ReconPlanning_fnc_NativeHQOrders",
        "ITW_CLASH_ReconPlanning_fnc_NativeHQOrdersDef",
    ]:
        assert f"{name}_FieldHardeningBase" in hardening

    assert "field-hardening-recon-nil-guard-ready" in hardening
    assert hardening.count("nativeResultDiscarded=true") == 1


def test_contact_diagnostics_only_pair_conscious_ace_valid_infantry():
    hardening = mission("ITW_CLASH_FieldHardening.sqf")

    assert '_unit isKindOf "CAManBase"' in hardening
    assert "ALIVE(_unit)" in hardening
    assert "CONSCIOUS(_unit)" in hardening
    assert "ITW_CLASH_CombatDiagnosticsContactRadius = -1;" in hardening
    assert '"ace-aware"' in hardening
    assert '"expected-recovery-nonengagement"' in hardening
    assert 'lifeState _unit' in hardening
    assert '_unit getVariable ["ACE_isUnconscious",false]' in hardening


def test_gtfo_busy_stall_is_observer_only():
    hardening = mission("ITW_CLASH_FieldHardening.sqf")

    assert "ITW_CLASH_GTFO_BusyStallGrace = 90;" in hardening
    assert "ITW_CLASH_GTFO_BusyStallProgress = 25;" in hardening
    assert '"gtfo-hal-busy-stall"' in hardening
    assert '"RydHQ_Exhausted"' in hardening
    assert '"RydHQ_AttackAv"' in hardening
    assert '"RydHQ_CombatAv"' in hardening

    # This tranche diagnoses HAL's stale Busy state; it does not seize movement.
    assert "ITW_CLASH_fnc_OrderWithdrawal =" not in hardening
    assert "addWaypoint" not in hardening
    assert "setVariable [_busyName,false]" not in hardening
