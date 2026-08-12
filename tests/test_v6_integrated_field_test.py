from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_integrated_build_wires_preinit_reconstitution_and_runtime_recovery_layers():
    pre = text("preInit.sqf")
    init = text("init.sqf")
    for hook in [
        "ITW_CLASH_ReconstitutionDispatchFix.sqf",
        "ITW_CLASH_ReconstitutionTransitFix.sqf",
        "ITW_CLASH_SpawnArchetypePreInit.sqf",
    ]:
        assert hook in pre
    for hook in [
        "ITW_CLASH_LogisticsGuard.sqf",
        "ITW_CLASH_CASEVAC.sqf",
        "ITW_CLASH_CASEVAC_AirOpsFix.sqf",
        "ITW_CLASH_CASEVAC_HomeRTB.sqf",
        "ITW_CLASH_CASEVAC_LZPadFix.sqf",
        "ITW_CLASH_GroundMEDEVAC.sqf",
    ]:
        assert hook in init

    bootstrap = text("ITW_CLASH_Bootstrap.sqf")
    runtime_patch = text("ITW_CLASH_RuntimePatch.sqf")
    assert "_patchVersion != 4" in bootstrap
    assert "ITW_CLASH_RuntimePatchVersion = 4;" in runtime_patch
    assert '"ITW_CLASH_fnc_SelectAnchorGroup"' in bootstrap
    assert '"ITW_CLASH_fnc_AuditAnchors"' in bootstrap


def test_integrated_build_preserves_physical_logistics_contracts():
    dispatch = text("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    transit = text("ITW_CLASH_ReconstitutionTransitFix.sqf")
    casevac = text("ITW_CLASH_CASEVAC.sqf")
    air_ops = text("ITW_CLASH_CASEVAC_AirOpsFix.sqf")
    lz_pad = text("ITW_CLASH_CASEVAC_LZPadFix.sqf")
    ground = "\n".join([
        text("ITW_CLASH_GroundMEDEVAC.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_Extraction.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_Manager.sqf"),
    ])

    assert "ITW_CLASH_ReconstitutionHandoffBuffer = 250;" in transit
    assert 'ITW_CLASH_CASEVAC_SmokeClass = "SmokeShell";' in casevac
    assert "assignAsCargo _heli" in casevac
    assert "orderGetIn true" in casevac
    assert "moveInAny" not in casevac
    assert '"inbound-route"' in air_ops
    assert '"reconstitution-dispatch-return"' in dispatch
    assert 'ITW_CLASH_CASEVAC_HelipadClass = "Land_HelipadEmpty_F";' in lz_pad
    assert "landAt [_pad" in lz_pad
    assert "ITW_CLASH_CASEVAC_InfantryPadOffset = 30;" in lz_pad
    assert '"reconstitution-dispatch-state"' in transit
    assert "assignAsCargo _veh" in ground
    assert "forceFollowRoad true" in ground
    assert "moveInAny" not in ground


def test_integrated_build_has_single_reconstitution_credit_authority():
    casevac = text("ITW_CLASH_CASEVAC.sqf")
    ground = "\n".join([
        text("ITW_CLASH_GroundMEDEVAC.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_Extraction.sqf"),
        text("ITW_CLASH_GroundMEDEVAC_Manager.sqf"),
    ])
    clash = text("ITW_CLASH.sqf")
    assert "ITW_AtkQueueReconstitution" not in casevac
    assert "ITW_AtkQueueReconstitution" not in ground
    assert "ITW_AtkQueueReconstitution" in clash
