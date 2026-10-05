"""HotDrop must not take a helicopter CASEVAC is flying.

Hark, after four bad helicopter runs: "i worry that our CASEVAC helo's have
also been affected."

They were. HotDrop has carried an ownership guard since it was written, but it
read the wrong variable:

    (_crewGroup getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo ""

ITW_CLASH_CASEVAC_State is stamped on the CASUALTY's squad - CASEVAC.sqf:552,
726, 751; EvacBoardingFix.sqf:204, 215, 345, 357; GroundMEDEVAC_Manager.sqf:82,
104; GroundMEDEVAC_Extraction.sqf:159 - and never on the carrier's crew group.
Read off a crew group it is always "", so the guard could not fire.

That was inert while HotDrop only claimed aircraft already airborne: a CASEVAC
helicopter airborne with casualties is above the claim window. d7f99da
(2026-10-03) moved the claim to the ground, which is exactly where a CASEVAC
helicopter sits while it loads - land "GET IN" at CASEVAC.sqf:499, touching
ground, squad boarding - and HotDrop's poll sweeps every helicopter below 3m
ATL with a crew. A dead guard, then the window moved onto it.

The correct marker already existed: ITW_CLASH_CASEVAC on both the helicopter
and its crew group (CASEVAC.sqf:268-269, CASEVAC_AirOpsFix.sqf:105-106), read
by ITW_CLASH_DualHAL_fnc_IsLifecycleReserved along with GroundMEDEVAC,
reconstitution transit and transport, recovery, and Impasse deliveries.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def read(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace")


def hotdrop() -> str:
    return read("ITW_CLASH_HotDrop.sqf")


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
    """Comments explain the defect by name, so every assertion below has to see
    executable text only or it passes on the explanation."""
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return re.sub(r"//[^\n]*", "", body)


# ----------------------------------------------- the marker that actually exists

def test_casevac_stamps_the_airframe_and_its_crew():
    for name in ("ITW_CLASH_CASEVAC.sqf", "ITW_CLASH_CASEVAC_AirOpsFix.sqf"):
        source = read(name)
        assert '_heli setVariable ["ITW_CLASH_CASEVAC",true,true];' in source, name
        assert '_crewGroup setVariable ["ITW_CLASH_CASEVAC",true];' in source, name


def test_the_state_variable_lives_on_the_casualty_squad_not_the_carrier():
    """The premise of the fix. If a writer ever starts stamping CASEVAC_State
    on a crew group this test should fail and the guard can go back to being
    simple."""
    for name in ("ITW_CLASH_CASEVAC.sqf", "ITW_CLASH_EvacBoardingFix.sqf",
                 "ITW_CLASH_GroundMEDEVAC_Manager.sqf",
                 "ITW_CLASH_GroundMEDEVAC_Extraction.sqf"):
        source = read(name)
        for line in source.splitlines():
            if 'setVariable ["ITW_CLASH_CASEVAC_State"' not in line:
                continue
            assert "_crewGroup setVariable" not in line, (name, line.strip())
            assert "_heli setVariable" not in line, (name, line.strip())


def test_the_lifecycle_oracle_reads_the_airframe_marker():
    body = function_body(
        read("ITW_CLASH_DualHALCheckbook.sqf"),
        "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved",
    )
    assert 'params ["_group",["_veh",objNull]]' in body
    # Group side.
    assert '_group getVariable ["ITW_CLASH_CASEVAC",false]' in body
    assert '_group getVariable ["ITW_CLASH_GroundMEDEVAC",false]' in body
    assert '_group getVariable ["ITW_CLASH_ReconstitutionTransit",false]' in body
    assert '_group getVariable ["ITW_CLASH_RecoveryOwned",false]' in body
    assert '_group getVariable ["itwDelivery",false]' in body
    # Vehicle side, which is why the carrier is passed in below.
    assert '_veh getVariable ["ITW_CLASH_CASEVAC",false]' in body
    assert '_veh getVariable ["ITW_CLASH_ReconstitutionTransport",false]' in body


# --------------------------------------------------------------- the carrier gate

def test_eligibility_asks_the_oracle_about_the_carrier():
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    assert "[_crewGroup,_veh] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" in body
    assert "declined-reserved-carrier" in body


def test_the_airframe_is_passed_not_just_the_group():
    """A CASEVAC helicopter whose crew group was re-formed still carries
    ITW_CLASH_CASEVAC on the hull, so the vehicle argument is the one that
    cannot be dropped."""
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    call = re.search(
        r"\[([^\]]*)\] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved", body
    )
    assert call is not None
    assert "_veh" in call.group(1), call.group(1)


def test_the_broken_variable_is_gone_from_the_executable_text():
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    assert "ITW_CLASH_CASEVAC_State" not in body
    assert "ITW_CLASH_GroundMEDEVAC_State" not in body


def test_a_missing_oracle_fails_closed_on_the_carrier():
    """The opposite of this layer's usual fail-open posture, deliberately: a
    hot drop not flown costs one insertion, a CASEVAC flown to an objective
    costs the squad it was sent for."""
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    guard = body.index('isNil "ITW_CLASH_DualHAL_fnc_IsLifecycleReserved"')
    tail = body[guard:guard + 400]
    assert "declined-no-lifecycle-oracle" in tail
    assert "false" in tail
    assert "true" not in tail.split("exitWith")[1][:120]


def test_the_ownership_gate_runs_before_the_claim_window():
    """Ordering matters: the altitude window is what accidentally protected
    CASEVAC before, and it must not be what protects it now."""
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_IsEligible"))
    assert (
        body.index("ITW_CLASH_DualHAL_fnc_IsLifecycleReserved")
        < body.index("ITW_CLASH_HotDropBoardingHeight")
    )


# ----------------------------------------------------------------- the cargo gate

def test_reserved_passengers_are_declined_even_in_an_unmarked_airframe():
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Consider"))
    assert "[_cargoGroup,_veh] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved" in body
    assert "declined-reserved-cargo" in body


def test_the_cargo_gate_runs_before_anything_is_claimed():
    body = code_only(function_body(hotdrop(), "ITW_CLASH_HotDrop_fnc_Consider"))
    assert (
        body.index("declined-reserved-cargo")
        < body.index("ITW_CLASH_HotDrop_fnc_Claim")
    )


# ------------------------------------------------------------- scope of the sweep

def test_the_poll_is_still_a_map_wide_sweep_of_grounded_helicopters():
    """Why the guard has to be right rather than merely present: nothing about
    the poll limits it to HAL's own transports."""
    source = hotdrop()
    sweep = source[source.index("forEach ("):source.index("sleep ITW_CLASH_HotDropPoll")]
    assert "vehicles select" in sweep
    assert 'isKindOf "Helicopter"' in sweep
    assert "ITW_CLASH_HotDropBoardingHeight" in sweep


def test_ground_medevac_has_no_aircraft_to_lose():
    """Asserted so the claim in the module header stays true. GroundMEDEVAC is
    ground-only, so the air hole never reached it."""
    for name in ("ITW_CLASH_GroundMEDEVAC.sqf",
                 "ITW_CLASH_GroundMEDEVAC_Extraction.sqf",
                 "ITW_CLASH_GroundMEDEVAC_Manager.sqf",
                 "ITW_CLASH_GroundMEDEVAC_VehiclePolicy.sqf"):
        source = read(name)
        assert "flyInHeight" not in source, name
        assert re.search(r'\bland\s+"', source) is None, name


def test_casevac_releases_its_own_landings():
    """The sticky-landing class of bug that hit four other files this week does
    not reach CASEVAC: the ingress land "GET IN" is cancelled by SendHeliHome's
    land "NONE" before the egress waypoint, and the terminal land "GET OUT" is
    followed by deletion rather than reuse."""
    source = read("ITW_CLASH_CASEVAC.sqf")
    home = function_body(source, "ITW_CLASH_CASEVAC_fnc_SendHeliHome")
    assert '_heli land "NONE";' in home
    assert "addWaypoint" in home
    assert home.index('land "NONE"') < home.index("addWaypoint")
    cleanup = function_body(source, "ITW_CLASH_CASEVAC_fnc_CleanupHeli")
    assert "deleteVehicle _heli" in cleanup
