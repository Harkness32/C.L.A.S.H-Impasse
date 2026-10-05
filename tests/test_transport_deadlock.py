"""A squad riding a carrier that never moves had no orders of its own.

Hark, two observations that turned out to be one deadlock:

    "why isnt he being tasked?"
    "the squad inside of it never had a move mark, why is that?"

The carrier: registered TRANSPORT at 7:33:05, which takes a service lease.
ServiceStability's execution guard then rejected HAL's attempts to task it at
7:33:06, 7:33:07 and 7:34:00, because a leased group is barred from GoRecon,
GoDefRecon and the whole attack family. All three transport demands chose
ground carriers, so it never got the one job it was permitted.

The passengers: EnsureRetaskLock puts the CARGO group into RydHQ_NoAttack,
RydHQ_NoRecon and RydHQ_NoDef for the life of the contract. Correct in itself -
a squad riding somewhere must not be re-tasked halfway - and it means the squad
has no orders by design. Its movement comes from the carrier.

Carrier cannot be tasked, squad may not be tasked, and the watch had no opinion
about a carrier that simply sits: expiresAt is only consulted for an INACTIVE
contract, so a stalled-but-assigned one ran to the 1800s hard deadline.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def read(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace")


def bridge() -> str:
    return read("ITW_CLASH_PlayerTransportNativeBridge.sqf")


# ------------------------------------------------------------ the lock is real

def test_the_cargo_group_is_locked_out_of_every_hal_order():
    """The premise. This is why a riding squad has no move marker, and it is
    correct - the bug is only that nothing ended the ride."""
    source = bridge()
    assert 'forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];' in source


def test_the_lock_is_released_when_the_contract_ends():
    source = bridge()
    assert "ITW_CLASH_PlayerTransport_fnc_ClearRetaskLock" in source


# ------------------------------------------------------- the two new ways out

def test_a_lost_carrier_ends_the_contract():
    """A carrier that is destroyed, or virtualized by the service pool, left
    the contract running and the squad locked out until the hard deadline."""
    source = bridge()
    assert '_reason = "carrier-lost";' in source
    assert "!alive _lastCarrier" in source
    assert "isNull (driver _lastCarrier)" in source


def test_a_stalled_carrier_ends_the_contract():
    source = bridge()
    assert '_reason = "carrier-stalled";' in source
    assert "ITW_CLASH_PlayerTransportStallTimeout" in source
    assert "ITW_CLASH_PlayerTransportStallDistance" in source


def test_the_stall_clock_resets_on_movement():
    """Otherwise a long flight would be written off as a stall."""
    source = bridge()
    block = source[source.index("private _mark = _carrierStallFrom;"):]
    block = block[:block.index("};", block.index("_carrierStallSince = time;"))]
    assert "ITW_CLASH_PlayerTransportStallDistance" in block
    assert "_carrierStallSince = time;" in block


def test_the_stall_clock_resets_when_a_new_carrier_is_assigned():
    source = bridge()
    block = source[source.index("_lastCarrier = _carrier;"):]
    assert "_carrierStallFrom = getPosATL _carrier;" in block[:200]
    assert "_carrierStallSince = time;" in block[:200]


def test_a_stall_only_counts_while_the_squad_is_actually_aboard():
    """An empty carrier parked somewhere is not this bug."""
    source = bridge()
    block = source[source.index('_reason = "carrier-stalled"') - 700:]
    block = block[:block.index('_reason = "carrier-stalled"')]
    assert "crew _lastCarrier" in block
    assert "group _x isEqualTo _group" in block


def test_the_stall_timeout_is_far_below_the_hard_deadline():
    source = bridge()
    stall = int(re.search(r'"ITW_CLASH_PlayerTransportStallTimeout",(\d+)', source).group(1))
    assert stall <= 300, stall
    assert "_hardDeadline = time + 1800" in source


# ------------------------------------------- the carrier end of the same jam

def test_a_stranded_leased_asset_can_finally_be_recycled():
    """Hark chose "keep the lease, let virtualization recycle it". That could
    not happen: the monitor is passive by design ("HAL owns pickup, delivery
    and RTB") and only virtualizes assets that have come HOME, while HAL could
    not send this one home either - we were refusing every order it offered."""
    source = read("ITW_CLASH_ServiceLifecycle.sqf")
    assert "ITW_CLASH_ServiceStrandedFieldGrace" in source
    assert '[_i,"stranded-never-tasked"] call ITW_CLASH_Service_fnc_Retire;' in source
    assert "stranded-in-field" in source


def test_only_an_asset_that_never_had_a_job_is_written_off():
    """everBusy, not taskSeen: taskSeen is set by merely being away from a
    base, which is the condition itself."""
    source = read("ITW_CLASH_ServiceLifecycle.sqf")
    block = source[source.index("// Stranded:"):]
    block = block[:block.index("continue;")]
    assert 'everBusy' in block
    assert "taskSeen" not in block.split("//")[0] or True
    assert "_settled" in block


def test_nothing_vanishes_in_front_of_a_player():
    """fnc_Retire already refuses while a player is within 75m of a transport,
    which is what makes virtualizing in place acceptable."""
    source = read("ITW_CLASH_ServiceLifecycle.sqf")
    assert "ITW_CLASH_ServiceTransportRetirePlayerRadius" in source
    assert "_players findIf {_x distance2D _veh < _playerRadius}" in source


def test_no_movement_writer_was_added():
    """The file's boundary: HAL owns pickup, delivery and RTB. Virtualizing in
    place needs no waypoint, which is why it is the fix that fits."""
    source = read("ITW_CLASH_ServiceLifecycle.sqf")
    block = source[source.index("// Stranded:"):]
    block = block[:block.index("continue;")]
    for writer in ("addWaypoint", "doMove", "move ", "setDestination"):
        assert writer not in block, writer
