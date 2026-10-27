"""Who gets a commander-assigned job: a shuffle bag per channel.

2026-10-27, Hark: random first pick among the groups that want work, each
removed from the pool until everyone has had a turn, then refresh. Agreed rules:
a group joining mid-round is due at once; a busy group keeps its turn; a cancel
or lapse counts as the turn; a group that unticks leaves the pool; one pool per
channel. Ready groups (already in a vehicle that can do the job) go first.
"""

import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
RAW = (MISSION / "ITW_CLASH_PlayerDemandReservationHardening.sqf").read_text(encoding="utf-8")
CODE = re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", RAW, flags=re.S))


def body_of(name: str) -> str:
    start = CODE.index(f"{name} = {{")
    depth = 0
    i = CODE.index("{", start)
    while i < len(CODE):
        if CODE[i] == "{":
            depth += 1
        elif CODE[i] == "}":
            depth -= 1
            if depth == 0:
                return CODE[start:i + 1]
        i += 1
    raise AssertionError(name)


def test_version_and_boot():
    assert "ITW_CLASH_PlayerDemandReservationHardeningVersion = 2;" in RAW
    assert "dispatch=shuffle-bag-per-channel readyFirst=%7 turnTakenOnReserve=true" in RAW
    assert 'ITW_CLASH_PlayerDispatchReadyFirst",true' in CODE


def test_the_picker_is_the_bag_not_the_first_in_list():
    find = body_of("ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup")
    # Every eligible group is collected; the old first-match exit is gone.
    assert "(+ITW_CLASH_PlayerTaskGroups) select {" in find
    assert "exitWith {\n                _found = _x;" not in find
    assert "[_channel,_eligible] call ITW_CLASH_PlayerDemandReservation_fnc_Pick" in find
    # The per-job decline cooldown and the willingness test still gate it.
    assert "declineCooldowns" in find
    assert "ITW_CLASH_PlayerTasks_fnc_CanAcceptJob" in find


def test_pick_rules():
    pick = body_of("ITW_CLASH_PlayerDemandReservation_fnc_Pick")
    # Untick leaves the round.
    assert "[_x,_channel] call ITW_CLASH_PlayerTasks_fnc_IsSubscribed" in pick
    # Due = eligible minus those who had a turn; empty -> new round.
    assert "private _due = _eligible select {!(_x in _served)};" in pick
    assert "_served = [];" in pick and "_due = +_eligible;" in pick
    # Ready first, random within.
    assert "if (_ready isNotEqualTo []) then {_due = _ready};" in pick
    assert "selectRandom _due" in pick
    # Per channel.
    assert "ITW_CLASH_PlayerDispatchServed getOrDefault [_channel,[]]" in pick


def test_the_turn_is_taken_on_reservation():
    take = body_of("ITW_CLASH_PlayerDemandReservation_fnc_TakeTurn")
    assert "_served pushBackUnique _group;" in take
    reserve = CODE[CODE.index("ITW_CLASH_PlayerDemand_fnc_Reserve = {"):]
    ok = reserve.index("private _ok = _this call ITW_CLASH_PlayerDemandReservation_fnc_ReserveBase;")
    turn = reserve.index("call\n            ITW_CLASH_PlayerDemandReservation_fnc_TakeTurn;")
    assert ok < reserve.index("if (!_ok) exitWith {false};") < turn


def test_readiness_by_channel():
    ready = body_of("ITW_CLASH_PlayerDemandReservation_fnc_Ready")
    assert 'case "MEDEVAC";' in ready and 'case "TRANSPORT": {' in ready
    assert "ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity" in ready
    assert "ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle" in ready
    assert "ITW_CLASH_PlayerTasks_fnc_HasArtilleryCapability" in ready


# ------------------------------------------------------------ the model


class Bag:
    """The SQF Pick/TakeTurn pair, for one channel."""

    def __init__(self, ready_first=True, seed=1):
        self.served = []
        self.ready_first = ready_first
        self.rng = random.Random(seed)

    def pick(self, eligible, subscribed, ready=()):
        if not eligible:
            return None
        self.served = [g for g in self.served if g in subscribed]
        due = [g for g in eligible if g not in self.served]
        if not due:
            self.served = []
            due = list(eligible)
        if self.ready_first:
            r = [g for g in due if g in ready]
            if r:
                due = r
        return self.rng.choice(due)

    def take(self, group):
        if group not in self.served:
            self.served.append(group)


def run_jobs(bag, groups, jobs, busy=lambda n: set(), ready=()):
    got = []
    for n in range(jobs):
        eligible = [g for g in groups if g not in busy(n)]
        g = bag.pick(eligible, set(groups), ready)
        if g is not None:
            bag.take(g)
        got.append(g)
    return got


def test_everyone_gets_one_before_anyone_gets_two():
    for seed in range(20):
        got = run_jobs(Bag(seed=seed), ["A", "B", "C"], 9)
        for start in (0, 3, 6):
            assert sorted(got[start:start + 3]) == ["A", "B", "C"]


def test_the_first_to_sign_up_no_longer_wins_everything():
    got = run_jobs(Bag(seed=3), ["A", "B", "C", "D"], 40)
    assert {g: got.count(g) for g in "ABCD"} == {"A": 10, "B": 10, "C": 10, "D": 10}


def test_a_busy_group_keeps_its_turn():
    bag = Bag(seed=5)
    # B is busy for the first two jobs; A and C take them.
    got = run_jobs(bag, ["A", "B", "C"], 2, busy=lambda n: {"B"})
    assert sorted(got) == ["A", "C"]
    # Free again: B is the only one still due this round.
    assert bag.pick(["A", "B", "C"], {"A", "B", "C"}) == "B"


def test_a_cancel_counts_as_the_turn():
    bag = Bag(seed=2)
    g = bag.pick(["A", "B"], {"A", "B"})
    bag.take(g)  # reserved, then cancelled: the turn stands
    assert bag.pick(["A", "B"], {"A", "B"}) != g


def test_joining_mid_round_is_due_at_once():
    bag = Bag(seed=4)
    run_jobs(bag, ["A", "B"], 1)
    taken = bag.served[0]
    other = "B" if taken == "A" else "A"
    # C ticks in: due alongside the one who has not had a turn.
    picks = {bag.pick(["A", "B", "C"], {"A", "B", "C"}) for _ in range(30)}
    assert picks == {other, "C"}


def test_unticking_leaves_the_round():
    bag = Bag(seed=6)
    bag.take("A")
    # A unticks: it drops out of the served list; ticking back makes it due.
    bag.pick(["B"], {"B"})
    assert "A" not in bag.served


def test_ready_groups_first_but_everyone_still_gets_a_turn():
    bag = Bag(seed=7)
    got = run_jobs(bag, ["walker", "flyer"], 2, ready={"flyer"})
    assert got == ["flyer", "walker"]


def test_pure_random_option():
    firsts = {Bag(ready_first=False, seed=s).pick(["walker", "flyer"], {"walker", "flyer"}, {"flyer"}) for s in range(30)}
    assert firsts == {"walker", "flyer"}
