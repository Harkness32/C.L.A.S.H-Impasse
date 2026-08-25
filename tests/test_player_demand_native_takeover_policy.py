from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def _block(text: str, start: str, end: str) -> str:
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


def test_native_takeover_uses_exact_demand_dispatch_policy():
    text = (MISSION / "ITW_CLASH_PlayerDemandNativeInterceptors.sqf").read_text(
        encoding="utf-8"
    )

    ammo = _block(
        text,
        "ITW_CLASH_PlayerDemandNative_fnc_TakeAmmo = {",
        "// Same handoff rule for severe medical support.",
    )
    assert "ITW_CLASH_PlayerDemand_fnc_Publish" in ammo
    assert "ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup" in ammo
    assert "ITW_CLASH_PlayerDemand_fnc_Reserve" in ammo
    assert "native-takeover-deferred-to-ai" in ammo
    assert "FindCandidate" not in ammo

    med = _block(
        text,
        "ITW_CLASH_PlayerDemandNative_fnc_TakeMedevac = {",
        "ITW_CLASH_PlayerDemandNative_fnc_BlockReservedAmmoRace = {",
    )
    assert "ITW_CLASH_PlayerDemand_fnc_Publish" in med
    assert "ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup" in med
    assert "ITW_CLASH_PlayerDemand_fnc_Reserve" in med
    assert "native-takeover-deferred-to-ai" in med
    assert "FindCandidate" not in med


def test_ai_fallback_and_decline_cooldown_are_enforced_by_find_dispatch_group():
    text = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(
        encoding="utf-8"
    )
    dispatch = _block(
        text,
        "ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup = {",
        "ITW_CLASH_PlayerDemandReservation_fnc_ReleaseBase =",
    )

    assert "playerOfferSuppressedUntil" in dispatch
    assert "declineCooldowns" in dispatch
    assert "ITW_CLASH_PlayerTasks_fnc_CanAcceptJob" in dispatch


def test_supported_arrays_are_native_handoff_cleanup_only():
    text = (MISSION / "ITW_CLASH_PlayerDemandNativeInterceptors.sqf").read_text(
        encoding="utf-8"
    )
    reservation = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(
        encoding="utf-8"
    )

    apply = _block(
        reservation,
        "ITW_CLASH_PlayerDemand_fnc_ApplySuppression = {",
        "ITW_CLASH_PlayerDemand_fnc_RestoreSuppression = {",
    )
    assert "RydHQ_ASupportedG" not in apply
    assert "RydHQ_SupportedG" not in apply
    assert "suppressionMarker" in apply

    assert "native-ASupportedG-cleared-on-handoff" in text
    assert "native-SupportedG-cleared-on-handoff" in text
    assert "sameCycleRaceGuard=true" in text
    assert "exactDemandDispatch=true" in text
