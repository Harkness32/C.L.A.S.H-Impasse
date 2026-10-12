# Who was standing around, 2026-10-10 23:22 to 00:19

Read from `CLASH DIAG | group-state` (18,858 samples, 229 groups) in the full
RPT of the first run-in flight. Build: unload owner v5, before stay-low.

Asked by Hark: "alpha 3-3, what is happening. I'm noticing some units just
sitting and standing around. Also some squads are not following their SL's."

Nothing in this file is fixed except where it says so. Sections 3 and 4 are
fixed in source and not yet flown.

---

## 1. Alpha 3-3

Two different groups carried that name.

| Group | When | What |
|---|---|---|
| G44 | 23:25 to 00:03 | four-man squad |
| G170 | 00:04 to end | Ghost Hawk and its crew of four |

G44 was never stuck:

- 23:25 recon order, rode a truck for six minutes
- 23:33 dismounted, searched the recon point
- 23:38 defended; 23:41 attack order
- 23:51 lost two men; 23:52 withdrew
- 00:02 CASEVAC by Huron; 00:03 absorbed into reconstitution

G170 took the name a minute later and sat at base for the remaining 13
minutes, never chosen for a lift.

## 2. BLUFOR on foot and idle at the end

| Group | Men | Idle | Why |
|---|---|---|---|
| G30 | 4 | 53 min | SOF. Never given an order. |
| G41 | 2 | 53 min | SOF. Never given an order. |
| G36 | 3 | 48 min | APC crew on foot, quarantined |
| G57 | 3 | 16 min | armed LSV crew on foot, quarantined |
| G163 | 1 | 4 min | MRAP crew on foot, quarantined |
| G40 | 1 | 30 min | last man of the anchor squad, stuck withdrawing |

Fourteen men. Three causes, below. The squads paradropped on this flight were a
fourth, and that one is fixed (`PARADROP_RUN_IN.md` section 13).

## 3. Quarantined crews are never cleaned up

`ITW_CLASH_CrewRemnantCleanup.sqf` is meant to quarantine a crew whose vehicle
is lost, then delete it after 20 s if no player is within 300 m.

Version 1 could not reach the second step, for two reasons that were each
enough alone:

1. The loop walks `ITW_CLASH_DualHALBLUFORGroups` and
   `ITW_CLASH_DualHALOPFORExtraGroups`. Quarantine calls
   `ITW_CLASH_Service_fnc_RemoveHALOwnership`, which removes the group from
   both (`ITW_CLASH_ServiceLifecycle.sqf:134`).
2. The loop skips any group `ITW_CLASH_DualHAL_fnc_IsLifecycleReserved`. That
   function's first test is `ITW_CLASH_ExcludeHAL`
   (`ITW_CLASH_DualHALCheckbook.sqf:82`), and quarantine sets that flag. The
   module read its own flag as somebody else's reservation.

The first write-up of this section named only the first. Fixing that alone
would have changed nothing.

| RPT | Quarantined | Cleaned |
|---|---|---|
| 20:14 | 16 | 0 |
| 20:53 | 3 | 0 |
| 23:22, full | 24 | 0 |

So every crew that loses its vehicle stands where it got out, marked `Unable`
and out of HAL, for the rest of the mission. Ten BLUFOR and fourteen enemy
crews on this flight.

Two of them are odd. G36 left a Panther 16 s after its first order, at base.
G57 left an armed LSV 25 s after its first. The module only quarantines when
the vehicle is gone, dead or cannot move, so both vehicles were unusable
within seconds. The log does not say why. For G36 the order of events is
known: in the vehicle with a MOVE waypoint at 23:25:41, leader on foot with
`GET OUT` at 23:25:48, quarantined at 23:25:49 with the vehicle type still
readable. So the crew bailed first and the vehicle was alive and immobile,
which is what a track or wheel lost in a collision on the way out of base
looks like. That is a guess until a log line says it.

**Fixed, version 2** (`tests/test_crew_remnant_cleanup.py`):

- The module keeps `ITW_CLASH_CrewRemnantQuarantined` and walks it as well.
- For a quarantined crew it no longer counts its own `ITW_CLASH_ExcludeHAL`.
  CASEVAC, ground MEDEVAC, reconstitution transit, recovery and deliveries
  still protect the crew.
- 20 s, 300 m and four survivors are unchanged.
- A man still in a seat is removed with `deleteVehicleCrew`.
- The quarantine line now ends with why: `vehicle-null`, `vehicle-dead` or
  `cannot-move`, the hit points at or above 0.5, and how many of the crew are
  still mounted. That settles G36 and G57 from the next RPT.

**Flown 2026-10-11 20:23.** Eight quarantined, six cleaned, each 20 s after
its quarantine. The reason on the line answers the G36 and G57 question in
part: two of the eight were at base in the first 90 s with nothing broken.

| Group | Vehicle | Reason | Hit points at 0.5 or more | Still mounted |
|---|---|---|---|---|
| G9 | Rhino MGS UP | `cannot-move` | none | 0 |
| G43 | Cheetah AA | `cannot-move` | lights only | 2 of 3 |

A vehicle that cannot move with nothing damaged is not a damaged vehicle. On
its side or roof at spawn is the likely reading, and it is still a guess: the
line does not log attitude. Both crews were then deleted, so each of these
costs the side a vehicle in the first two minutes.

Two things this does, on purpose, that are worth knowing:

- A crew still sitting in an immobilised vehicle is deleted with the rest. The
  module never distinguished mounted from dismounted; it just never ran.
- Quarantine is one way. A crew whose vehicle is repaired afterwards is
  neither deleted nor given back to HAL.

## 4. HAL's garrison flag has no owner

When an objective is taken and has no garrison, HAL picks the nearest free
infantry group within 500 m, sets its `Busy` flag by hand and adds it to
`RydHQ_Garrison` (`HQReset.sqf:239` to 307). No order thread stands behind that
flag, and nothing clears it.

- HAL will not task the group: it is `Busy`.
- `Garrison.sqf` will not place it: both branches require not `Busy`.
- GTFO will not rest it: it sets `Break`, waits 45 s for `Busy` to clear, and
  gives up (`ITW_CLASH_GTFO_Runtime.sqf:96`). It will not clear `Busy` by hand,
  correctly for an order, but there is no order here.

G40, the 15-man anchor for objective 6:

- 23:43:05 arrives. HAL makes it the garrison. `Busy` true from here on.
- 23:44 to 23:47 loses eleven men.
- 23:47 to 23:53 four survivors, no waypoint, standing.
- 23:53 one survivor. GTFO starts a withdrawal.
- `gtfo-rest-restart-deferred [G40, ..., busy=true, resting=false, break=true, 45]`
  every 90 s to the end of the log. He never moves.

G37 was taken the same way 16 s after its order died on landing.

HAL's garrison and the C.L.A.S.H. anchor are two owners of one job, holding a
taken objective. The anchor reads the garrison's `Busy` as a HAL order and
stands off (`commander-parity-anchor-order-deferred`, seven times for G40).

There is a second defect under the first. The garrison list has two names:
every SitRep does `_HQ setVariable ["RydHQ_Garrison",RydHQB_Garrison]`
(`HQSitRepB.sqf:319`), and HAL's pick pushes onto that same array. GTFO
removed the squad from the HQ's copy only, so the next SitRep put it back.

| Group | `gtfo-hal-role-cleanup [RydHQ_Garrison]` | `rest-restart-deferred` |
|---|---|---|
| G37 | 14 | 1 |
| G40 | 10 | 16 |

And a third: `HAL_GoRest` does not check `Busy` before it starts. It sets
`Break` and waits for it to be read (`GoRest.sqf:76` to 79). HAL sends an
exhausted group a rest order every cycle, so each cycle left one more rest
thread waiting on a `Break` nobody would read.

**Fixed** (`tests/test_garrison_busy_release.py`), in
`ITW_CLASH_CommanderParity.sqf` version 4 and `ITW_CLASH_GTFO_Runtime.sqf`
version 5. HAL source is not edited or patched.

- `ITW_CLASH_CommanderParity_fnc_ReleaseGarrison` removes a squad from both
  names of the list, writes one array to both, and resets the `Garrisoned`
  flags. If the squad is `Busy` it marks that `Busy` as the garrison's.
- `ITW_CLASH_CommanderParity_fnc_SettleGarrisonBusy` sets `Break`, which is
  HAL's own cancel, and waits `ITW_CLASH_GarrisonBusyProbeWait` (20 s, a
  placeholder). An order that owns `Busy` reads `Break` and releases `Busy`
  itself. Only if `Break` is still unread at the end, `Busy` unchanged and no
  rest begun, are `Busy` and `Break` cleared by hand.
- A squad in a lift is never probed.
- GTFO's role cleanup calls both for a withdrawing squad. HAL's own rest
  order then runs: the waiting thread wakes, or the next cycle sends one.
- The Commander B anchor order calls both before it asks whether HAL has the
  squad, then issues `HAL_GoDef` as usual.

What it does not do:

- **HAL's pick is untouched.** A garrison squad that is neither withdrawing
  nor wanted by its anchor is still pinned: never tasked, never placed in
  buildings. Whether HAL's garrison should exist at all next to the anchor is
  a design question, below.
- **HAL will pick the anchor again.** After the anchor takes its squad back
  and orders it, HAL sees no garrison within 500 m and takes the nearest free
  infantry, usually the same squad. That is harmless while the anchor is
  covered, and costs one release (about 20 s) each time the anchor needs to
  order. While an anchor is degraded that is every order.
- **The one unsafe case.** `Busy` is cleared by hand on a live order if that
  order is on a garrison squad and goes 20 s without reading `Break`. HAL only
  picks squads that are not `Busy`, so this needs HAL's own 60 s race timeout
  (`HQReset.sqf:281` to 291) and then a long wait inside the order.
- **Same gaps elsewhere, by source, not seen in a log and not changed:**
  `ITW_CLASH_fnc_ReleaseLockedGarrison` (`ITW_CLASH.sqf:319`) writes the HQ
  copy only and leaves `Busy`, so the squads it gives back cannot be sent
  anywhere; the OPFOR anchor order (`ITW_CLASH.sqf:1136`) sets `Break` on a
  garrison squad and `HAL_GoDef` then exits on `Busy`.

Design question: both sides now have anchors holding taken objectives. HAL's
garrison pins a second squad for the same job and never places it. Removing
the pick would need a HAL patch; making it real would mean clearing `Busy` on
every pick so `Garrison.sqf` digs the squad in, and deciding what that does to
an anchor that is also the garrison.

## 5. SOF waits for a raid that did not come

G30 and G41 are detected as special forces. Doctrine keeps them out of
anchoring and line tasks. HAL gave BLUFOR nine recon orders, all to line squads
and vehicle crews, and no SF raid. Six men sat at base for 53 minutes. Working as
written; whether that is what is wanted is a design question.

## 6. Not following the leader

The RPT has no per-man positions, so it cannot show it. Two things in source:

- **Paradrops.** No `doFollow` after the drop. Fixed.
- **HAL has no `doFollow` at all.** The one in `SCargo.sqf:781` is commented
  out. `RYD_GarrS` moves and `doStop`s each man into a building and never
  releases him. BLUFOR's two garrison squads were `Busy`, so it never placed
  them on this flight, but it will leave men behind whenever it does.

A line per squad with its widest leader-to-member distance would settle this
from the next RPT.
