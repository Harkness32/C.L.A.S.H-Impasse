from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_integrated_build_wires_logistics_casevac_and_anchor_doctrine():
    init = text("init.sqf")
    for hook in [
        "ITW_CLASH_ReconstitutionDispatchFix.sqf",
        "ITW_CLASH_ReconstitutionTransitFix.sqf",
        "ITW_CLASH_LogisticsGuard.sqf",
        "ITW_CLASH_CASEVAC.sqf",
        "ITW_CLASH_CASEVAC_AirOpsFix.sqf",
        "ITW_CLASH_CASEVAC_LZPadFix.sqf",
        "ITW_CLASH_CASEVAC_HomeRTB.sqf",
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

    assert "ITW_CLASH_ReconstitutionHandoffBuffer = 250;" in transit
    assert "ITW_CLASH_ReconstitutionTransitFixVersion = 2;" in transit
    assert '"reconstitution-dispatch-state"' in transit
    assert "private _dispatched =" not in transit
    assert 'ITW_CLASH_CASEVAC_SmokeClass = "SmokeShell";' in casevac
    assert "assignAsCargo _heli" in casevac
    assert "orderGetIn true" in casevac
    assert "moveInAny" not in casevac
    assert '"casevac-inbound-route"' in air_ops
    assert '"Land_HelipadEmpty_F"' in lz_pad
    assert "ITW_CLASH_CASEVAC_InfantryRallyOffset = 30;" in lz_pad
    assert '_heli landAt [_pad,"GetIn",_wait,true]' in lz_pad
    assert '"reconstitution-dispatch-return"' in dispatch


def test_integrated_build_has_single_credit_authority():
    casevac = text("ITW_CLASH_CASEVAC.sqf")
    clash = text("ITW_CLASH.sqf")
    assert "ITW_AtkQueueReconstitution" not in casevac
    assert "ITW_AtkQueueReconstitution" in clash
