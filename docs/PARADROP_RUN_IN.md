# Paradrops flown ITW's way, and the aircraft handed back afterwards

Status: on `agent/paradrop-run-in`, cut from `agent/anchor-lift-collision`
(`bc3271c`). Static tests green. Not flown. Nothing here has run in the engine.

Files: `ITW_CLASH_HALUnload.sqf` (version 5), `ITW_CLASH_HALParadrop.sqf`
(version 5).

---

## 1. What was wrong

Hark: "we set the waypoint on the ground, helo paths to transport place, slows,
lowers, gets there, then raises, then paradrops, then leaves. its stupid
clunky."

One cause. v4 decided LAND or PARADROP when HAL's insertion waypoint completed,
so the aircraft had to arrive at it first. An AI helicopter arrives at its last
waypoint by braking for it. Run A, 20:53, the one paradrop:

| Time | Event | Speed | Height |
|---|---|---|---|
| 21:02:47 | climb thread asks for 45 m, 1594 m out | | |
| 21:03:28 | seam fires, drop run armed | 24 km/h | 45 m |
| 21:03:33 | chalk out, egress written | 89 km/h | 50 m |

Five seconds over the point at walking pace, then an acceleration away.

## 2. What ITW does

`ITW_AtkUnloadAirplane` (`ITW_Attack.sqf:4157`):

1. Deletes the aircraft's waypoints and adds one 1500 m ahead, past the
   objective.
2. Polls distance to the objective every quarter second.
3. Ejects each man through `ITW_AtkParachute` as the aircraft passes.
4. Adds a waypoint 1000 m further on.

There is never a waypoint on the drop, so the aircraft is never arriving.

## 3. What v5 does

About 1200 m from HAL's insertion waypoint, and airborne, a watcher asks the
same question the seam asks, with the same corridor and mode functions.

**LAND or NO_LAND:** nothing. HAL's waypoint, HAL's height, HAL's speed. The
v4 en-route climb no longer runs on these lifts.

**PARADROP or HOT_PARADROP:**

1. Drop height (45 m, or 130 m for HOT), full speed, CARELESS.
2. HAL's own waypoint is moved 1000 m beyond the drop zone along the line the
   aircraft is already flying. Nothing is deleted. Nothing is added.
3. The chalk goes out as the aircraft crosses the drop zone, through
   `ITW_CLASH_HALParadrop_fnc_Execute` as before.
4. `fnc_Egress`, unchanged, appends the 600 m lateral break and home.

Why move HAL's waypoint instead of replacing it, as ITW does:

- HAL's order thread waits in `RYD_Wait` until the carrier has no waypoints
  (`HAC_fnc.sqf:2143`). Deleting the waypoint, even for an instant, can end
  that wait while the chalk is aboard.
- HAL's statement on that waypoint is the unload seam. Kept, it is the
  fallback for every failure below.

## 4. Where the chalk lands

The release is measured along the approach line, not as a radius, so a pass
that is wide still triggers and one that turns away does not.

Lead, in metres short of the drop zone:

    half the stick, less 30, plus half a second of flight

- `ITW_AtkParachute` spaces jumpers 40/kph seconds apart, held between 0.1 and
  0.5. From 80 to 400 km/h that is 11 m of track per man at any speed.
- Each chute opens 30 m behind the aircraft.
- Eight men at 200 km/h: 89 m stick, 42 m lead.

This is an estimate and it will be short. `moveOut` costs frames the arithmetic
does not see. The `release` line logs planned lead and distance flown.
`ITW_CLASH_HALUnloadReleaseBias` shifts it, positive for earlier.

## 5. Handing the aircraft back

This was the open item in `ANCHOR_LIFT_COLLISION.md` section 7. Run A showed it
62 s after the drop: three waypoints, `Busy` and `CargoM` both true.

HAL ends a lift in two places and a paradrop reached neither:

| HAL's step | Why a paradrop missed it |
|---|---|
| Order thread leaves `RYD_Wait` when the carrier has no waypoints | The egress route is waypoints |
| Order thread clears `CargoM` on `group (assignedDriver (assignedVehicle _UL))` | `ITW_AtkParachute` unassigns every jumper (`ITW_Attack.sqf:4244`), so that is `grpNull` |

v5 uses HAL's own input for each:

- **`RydHQ_MIA` on the carrier group.** `RYD_Wait` reads it and clears it
  (`HAC_fnc.sqf:1946`). The order thread carries on with the squad on the
  ground. Set once per squad that was aboard, because one read clears one flag.
  Taken back after 15 s if nobody read it.
- **`CargoM` false at the break point.** `SCargo` reads it every 5 s, sends the
  carrier home and frees `Busy` with its own code (`SCargo.sqf:645` onward).

`CargoM` waits for the break because `SCargo`'s return leg replaces every
waypoint the aircraft has.

Two order files differ. `GoFlank.sqf` and `GoSFAttack.sqf` clear `CargoM` on
the carrier group they already hold, on the line after their wait. Released at
the drop they would turn the aircraft home over the drop zone. They are
released at the break instead. Their squad waits the length of the egress,
about 30 s, for its next order.

The handback also runs after a seam paradrop, so the v4 path is cured too.

## 6. How it fails

| Failure | Result |
|---|---|
| Watcher never finds HAL's waypoint, or the lift ends first | Nothing touched. v4 lift. |
| Fault while arming | The waypoint move is the last line. Before it, only height and speed changed. v4 lift. |
| Aircraft below 18 m at the drop zone, chalk still aboard | HAL's waypoint goes back to the drop zone. Aircraft returns. v4 drop at the seam. |
| Never crosses the drop zone within 120 s | Same. |
| Passes more than 350 m wide | Same. |
| HAL's waypoint completes before the watcher releases | The seam takes the lift where the aircraft is. Logged `seam-took-over` with the distance from the drop zone. |
| `SCargo` thread gone | Break and home waypoints stand. Aircraft flies home and holds. |

The seam and the watcher cannot both act. Ownership moves through one
uninterruptible step (`fnc_Claim`, inside `isNil`).

## 7. Cost

- **Lower drops.** At the seam the paradrop owner waited up to 45 s for 45 m.
  On a fly-by it waits 1 s, then drops from anything at or above the existing
  18 m floor. Height at release is in the `release` and `executed` lines.
- **A longer stick.** The men leave over roughly 90 to 180 m of track instead
  of over a point.
- **Flares start earlier on HOT runs,** at 1.2 km instead of over the drop
  zone. The existing budget still bounds them.
- **Second pass on a miss.** An aircraft that fails its run-in comes back
  through the same air for a v4 drop.
- **`GoFlank` and `GoSFAttack` squads wait about 30 s** on the ground.
- **`GoAttSniper` is not released early.** Its wait is on the squad, not the
  carrier. The flag goes unread and is taken back. Logged
  `order-release-unread`. Not harmful, and not investigated further.
- **Two squads, one aircraft, mixed order types:** the release timing follows
  the order that built the lift last.

## 8. Not verified, because it needs the engine

- That an AI helicopter flies through a moved waypoint as smoothly as ITW's
  replaced one. This is the point of the change and it is untested.
- That the break waypoint becomes current after HAL's statement deletes
  waypoint 0 at the through point. HAL's own chained routes depend on the same
  behaviour. If it does not, the aircraft skips the break and the handback
  fires on its 60 s timeout.
- The stick lead.
- With a headless client owning the squad, `unassignVehicle` runs remotely. If
  it lags the order thread's lookup, HAL finishes the lift its own way and
  replaces the egress route.

## 9. Certifying from an RPT

Boot:

- `hal-unload-ready | version=5 ... runIn=true runInDistance=1200 handback=true`
- `hal-paradrop-ready | version=5`

Per lift, in order:

| Line | Reads as |
|---|---|
| `hal-unload-run-in` | type, crew group, order, corridor, mode, metres out, km/h, height, reason |
| `hal-unload-run-in-armed` | type, crew group, mode, bearing, metres out, km/h, height, height asked |
| `hal-unload-release` | type, crew group, planned lead, along-track, cross-track, km/h, height, jumpers, groups dropped, still aboard, metres from drop zone after, seconds |
| `hal-paradrop-executed` | per group, as before |
| `hal-unload-egress` | as before; dwell is now release to egress |
| `CLASH HAL UNLOAD \| lift \| ... via=run-in` | the one-line result |
| `hal-unload-seam-after-run-in` | HAL's statement at the through point, doing nothing |
| `hal-unload-handback` | type, crew group, order, why, seconds, waypoints, Busy before, released at break, squads |

A good drop: speed at `release` at or above speed at `run-in-armed`, and
`why=break` on the handback within about 30 s. The same carrier taking a later
lift is the proof that `SCargo` freed it.

Worth reading when they appear: `run-in-aborted`, `seam-took-over`,
`order-release-unread`, `handback ... timeout`, `via=seam` with a paradrop
result.

## 10. Switches

All read from `missionNamespace` at load.

| Variable | Default | Effect |
|---|---|---|
| `ITW_CLASH_HALUnloadRunIn` | true | false restores the v4 approach and seam decision |
| `ITW_CLASH_HALUnloadHandback` | true | false restores the v4 post-drop state |
| `ITW_CLASH_HALUnloadRunInDistance` | 1200 | where the mode is decided |
| `ITW_CLASH_HALUnloadReleaseBias` | 0 | metres earlier |
| `ITW_CLASH_HALUnloadReleaseWait` | 1 | seconds the drop may wait for height |
| `ITW_CLASH_HALUnloadMaxOffset` | 350 | cross-track limit |

Both switches false is v4.

## 11. Still open

- `HALUnload` still needs `CLASH_HALAdd_SourcePaths`, so without the addon
  there is no paradrop at all. Unchanged here.
- `ITW_AllyParadropCargo` holds one global lock. Two aircraft dropping at the
  same moment go one after the other, and the second releases late by the
  length of the first stick.
