# Who was standing around, 2026-10-10 23:22 to 00:19

Read from `CLASH DIAG | group-state` (18,858 samples, 229 groups) in the full
RPT of the first run-in flight. Build: unload owner v5, before stay-low.

Asked by Hark: "alpha 3-3, what is happening. I'm noticing some units just
sitting and standing around. Also some squads are not following their SL's."

Nothing in this file is fixed except where it says so.

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

It cannot reach the second step:

1. The loop walks `ITW_CLASH_DualHALBLUFORGroups` and
   `ITW_CLASH_DualHALOPFORExtraGroups` (lines 77 to 84).
2. Quarantine calls `ITW_CLASH_Service_fnc_RemoveHALOwnership`, which removes
   the group from both lists (`ITW_CLASH_ServiceLifecycle.sqf:134`).
3. The group is never visited again.

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
within seconds. The log does not say why.

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
