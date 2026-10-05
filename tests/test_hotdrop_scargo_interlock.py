"""One helicopter, one owner.

run8, measured: HotDrop claimed a Littlebird at 3:34:35 for a destination
1684m away and flew its own profile -

    INGRESS pos=[3998,14124] alt=4
    POPUP   pos=[3537,14059] alt=58   (+120s, the phase TIMEOUT)
    DROP    pos=[3523,14013] alt=1    (+120s again, 48m further, on the ground)
    put-out LAND_FALLBACK

- while SCargo's own tracer showed the SAME carrier cycling BOARDING(alt 50)
-> EMBARKED(alt 0) -> BOARDING(alt 0) underneath it. 487m of 1684m in four
minutes, every phase ending on a timeout rather than an arrival. Hark saw it
as "travels half the distance and then fucking LANDS for no goddamn reason."

SCargo.sqf:265 sets Busy on the carrier's group when a lift begins and clears
it at its four exits. HotDrop neither checked nor took it.
"""

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


def hotdrop() -> str:
    return read(MISSION / "ITW_CLASH_HotDrop.sqf")


def test_hotdrop_declines_a_carrier_hal_is_already_flying():
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    assert '_crewGroup getVariable [("Busy" + str _crewGroup),false]' in body
    assert "declined-busy" in body


def test_the_busy_lock_is_really_hals_carrier_signal():
    """Read from HAL's source so this fails if SCargo stops using it."""
    scargo = read(HAL / "SCargo.sqf")
    assert '_GD setVariable [("Busy" + (str _GD)), true]' in scargo
    # And it is released, so the interlock cannot wedge HotDrop permanently.
    assert scargo.count('_GD setVariable [("Busy" + (str _GD)), false]') >= 2


def test_the_interlock_sits_with_the_other_ownership_checks():
    """It is an ownership question, not a corridor or geometry one, so it
    belongs beside the paradrop and recovery interlocks rather than after the
    corridor classification."""
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    assert body.index("ITW_CLASH_HALParadropCargoGroup") < body.index('"Busy" + str _crewGroup')
    assert body.index("ITW_CLASH_ThunderRunActive") < body.index('"Busy" + str _crewGroup')


def test_existing_ownership_interlocks_are_intact():
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    for other in ("ITW_CLASH_HotDropActive", "ITW_CLASH_ThunderRunActive",
                  "ITW_CLASH_CASEVAC_State", "ITW_CLASH_GroundMEDEVAC_State",
                  "ITW_CLASH_HALParadropCargoGroup"):
        assert other in body, other


def test_the_remaining_hole_is_written_down():
    """HotDrop still does not TAKE Busy for lifts it does claim, so HAL can
    dispatch a carrier mid-profile from the other direction. Taking it means
    going through HAL's Break first, as fnc_Claim does in the resupply layer.
    Recorded rather than silently left."""
    source = hotdrop()
    assert "does not TAKE" in source
    assert "Break" in source


def test_hotdrop_version_moved_to_seven():
    assert "ITW_CLASH_HotDropVersion = 7;" in hotdrop()
