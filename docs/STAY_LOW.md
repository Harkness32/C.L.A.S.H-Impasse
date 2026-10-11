# Staying low: why HAL's helicopters balloon, and the schedule that stops it

Status: on `agent/paradrop-run-in`. Static tests green. Not flown.

Files: `ITW_CLASH_HALStayLow.sqf` (new, version 1), `ITW_CLASH_HALUnload.sqf`
(version 6), `tools/approach_sim.py` (the model).

Evidence: `Arma3_x64_2026-10-10_23-22-36.rpt`, the first flight of the
paradrop run-in.

---

## 1. What that flight lost

Four lifts. Three aircraft lost.

| Time | Aircraft | Height | What it was doing |
|---|---|---|---|
| 23:28:23 | Littlebird | 101 m | 4 s after its drop, climbing to the 120 m egress height |
| 23:29:59 | Littlebird | 118 m | 12 s after its drop, at egress height. Killed by an SPAA. |
| 23:40:16 | Huron | 197 m, 20 s before | braking for a landing in a COLD corridor |

The first two were C.L.A.S.H.'s own number: `fnc_Egress` asked for 120 m.

The third is the one Hark described. Its last snapshot has it at 197 m and
90 km/h, 385 m from its waypoint. The loss is logged at ground level 20 s
later. The pilot takes 35 s or more to land from that height, so it did not
land. What hit it is not in the log.

## 2. The balloon, measured

Hark: "we land on clear corridors, that causes our helos to raise in the air to
slow themselves down."

It is not only landings on delivery. It is every leg that ends at a waypoint.
A Huron flying to a pickup, 23:37:

| Metres out | km/h | Height |
|---|---|---|
| 892 | 251 | 102 |
| 603 | 169 | 281 |
| 407 | 102 | 291 |
| 280 | 67 | 262 |
| 134 | 32 | 188 |

Two facts, the same in all five such legs in the log:

1. **The arrival law.** Once braking, speed is 0.07 times distance. Both
   airframes, 0.065 to 0.078. This is the engine arriving at a last waypoint.
   At 250 km/h it is a 0.45 g stop that starts about 900 m out.
2. **The zoom.** The stop is a nose-up flare, and the speed shed becomes
   height. 251 to 102 km/h is 207 m of kinetic energy. The aircraft climbed
   189 m. The second Huron pickup: 203 m shed, 190 m climbed.

Afterwards the pilot descends at 8 to 10 m/s and no faster. So each balloon is
about half a minute above 100 m.

The same zoom is how the pilot climbs when asked. Told 120 m after a drop, the
Huron went from 60 m to 115 m in two seconds.

## 3. The simulation

`python tools/approach_sim.py`. Three parts, each fitted to that RPT: the
arrival law, zoom = decel x speed / g, and a height hold that pushes back
toward `flyInHeight` at up to 9 m/s.

It reproduces the measured balloon: 270 m modelled against 291 m.

**What the RPT pins down:** the arrival law, the energy conversion, the 9 m/s
descent limit.

**What it does not:** how hard the pilot corrects a *small* height error.
Every brake in the log is a hard one. So each schedule is flown by three
pilots, soft, middle and firm, and has to hold for all of them. The fit
prefers soft.

Huron, 4.4 km leg from a standstill. Peak height, metres:

| Schedule | Soft | Middle | Firm | Leg time |
|---|---|---|---|---|
| None (as flown) | 222 | 184 | 154 | 95 s |
| ITW's last rungs, inside 1.2 km | 220 | 189 | 164 | 102 s |
| ITW's full ladder | 148 | 104 | 77 | 110 s |
| Constant power, P = 35 | 109 | 69 | 50 | 105 s |
| **Constant power, P = 20** | **72** | **51** | **50** | **115 s** |
| Constant power, P = 15 | 60 | 50 | 50 | 121 s |

Findings:

- **Starting inside 1.2 km does not work.** That was the option first put to
  Hark as the recommended one. A Huron still has two thirds of its speed to
  lose in the last kilometre. The slow-down has to begin kilometres out.
- **ITW's ladder helps and is not the best shape.** Its rungs fall on a
  straight line in distance, which sheds energy fastest where the aircraft is
  fastest. It also steps.
- **Constant power is the better shape.** `v^3 = v_end^3 + 3 P (d - d_end)`
  makes decel x speed equal to P everywhere, so the zoom rate is P / g at every
  point and never steps.
- **There is no knee.** Every step of P is paid for in height under the soft
  pilot and bought back in seconds:

| P | Peak, soft pilot | Added to a 4.4 km leg |
|---|---|---|
| 10 | 50 m | 36 s |
| 15 | 60 m | 26 s |
| 20 | 72 m | 20 s |
| 25 | 84 m | 16 s |
| 35 | 109 m | 10 s |

P = 20 is shipped: a third of today's peak in the worst case, no rise in the
other two, for 10 s on a 2 km leg and 20 s on a 4.4 km one.

## 4. What was built

`ITW_CLASH_HALStayLow.sqf` sets `flyInHeight` and `limitSpeed` on HAL troop
lift helicopters and nothing else. HAL sets neither on a transport, and still
owns the route and every waypoint.

- **Cruise at 30 m** instead of the engine's 50.
- **On any leg that ends by arriving**, the schedule above. The last rung is
  ITW's: 80 km/h and 10 m inside 300 m, which is the arrival law's own speed
  there, so the aircraft joins the law without braking. Height follows ITW's
  line, 0.18 m per km/h.
- **A lift that will paradrop is not slowed.** It asks the unload owner, with
  the function the run-in decides by.

What a leg is, read off HAL's waypoint statement:

| Statement | Leg | Schedule |
|---|---|---|
| `land 'GET IN'` | pickup | yes |
| `land 'LAND'` | return | yes |
| unload seam, LAND or NO_LAND | delivery | yes |
| unload seam, PARADROP or HOT | delivery | no, cruise only |
| anything else | transit | no, cruise only |

Speed the schedule allows:

| Metres out | km/h | Height asked |
|---|---|---|
| 4400 | 229 | 30 |
| 2000 | 174 | 27 |
| 1000 | 135 | 20 |
| 500 | 102 | 14 |
| 300 and in | 80 | 10 |

In `ITW_CLASH_HALUnload.sqf`:

- **Egress height is the cruise height,** 30 m, not 120.
- **HOT drops from 45 m,** not 130. The 130 was HotDrop's, chosen to clear a
  55 m minimum that is now 45. HotDrop's own profile keeps its own number.
- **The handback keys on the engine's waypoint,** not on distance (section 6).

## 5. Who owns height and speed

One at a time:

1. Stay-low, from the moment SCargo picks the aircraft.
2. The unload owner, from arming a run-in to writing the egress route.
   Stay-low writes nothing while `DropRunArmed` is set.
3. Stay-low again, through the egress and the flight home.
4. Nobody, 15 s after SCargo has let it go and it has no leg.

Stay-low stops at once for a player crew, Thunder Run or HotDrop.

Every way out of an approach clears the speed limit and restores cruise height.

## 6. Other things that RPT showed

**The run-in works.** Speed armed to speed at release: 206 to 210, 220 to 215,
206 to 257 km/h. No braking. This was the main untested item.

**The break waypoint does become current** after HAL's statement deletes
waypoint 0. Also untested before.

**The handback waited a minute for nothing.** It wanted the aircraft within
250 m of the break. The Huron arced round it at 250 km/h, never closer than
390 m. The engine completed the waypoint; the handback timed out at 60 s with
the aircraft already flying home. Fixed: the break is passed when its waypoint
is no longer the current one.

**Drops finish 52, 135 and 178 m from the point,** nearly all of it sideways:
24, 121 and 165 m cross-track. The pilot flies 10 to 15 degrees off the bearing to its
waypoint and curves in late. With the waypoint a kilometre past the drop zone,
it is still curving when it crosses. Not fixed. A shorter through leg would
reduce it.

**The stick runs longer than planned.** 0.3 to 0.45 s per jumper against the
0.19 planned. About 30 m long of centre. Small next to the cross-track.
`ITW_CLASH_HALUnloadReleaseBias` moves it.

## 7. Cost and risk

- **Legs take 10 to 20 s longer.** That is time in the air, though low.
- **10 m at 80 km/h for the last 300 m,** on every pickup, delivery and return.
  ITW and CASEVAC both already do this. Trees and buildings are the risk.
  `ITW_CLASH_HALStayLowFinalHeight` raises it.
- **30 m cruise at 250 km/h.** In the log the pilot undershoots its height by
  up to 8 m over broken ground. Thunder Run and HotDrop already ingress at 25.
- **45 m HOT drops** put the aircraft lower over a hot corridor, and the men
  under canopy for less time.
- **If the pilot is soft,** the aircraft will sit near 70 m for most of an
  approach instead of following the height asked. Better than 290, not low.
- **If the pilot brakes hard for any overspeed,** small steps matter. The limit
  moves under 2 km/h per pass for that reason.
- **Other systems inherit 30 m.** An aircraft that has flown a HAL lift keeps
  cruise height afterwards. CASEVAC sets its own.
- **An aborted run-in is still a v4 arrival,** hard brake and all. It has to
  be at 45 m for the seam drop, so it is not slowed.

## 8. Certifying from an RPT

Boot:

- `hal-stay-low-ready | version=1 enabled=true cruise=30 power=20 ... at1000=135kmh/20m`
- `hal-unload-ready | version=6 ... egressHeight=30 hotDropHeight=45`

Per approach, one line when it ends:

    hal-stay-low-approach | [type, crew group, leg, why, from m, to m,
                             peak m, fastest km/h, seconds, power]

`peak m` is the number. Read against section 3:

| Peak on a 3 to 4 km Huron leg | Pilot | Then |
|---|---|---|
| about 30 to 40 | firm | P can go up to 35 or more |
| about 50 | middle | leave it |
| about 70 | soft | P down to 15, or accept |
| over 120 | the model is wrong | send the RPT |

`CLASH SCARGO AIR DIAG | snapshot` still gives height and speed every 5 s for
pickup and delivery legs, and is what the model was fitted to.

Also: no `air-picture-air-loss` above 100 m within 15 s of a `lift` line, and
`hal-unload-handback` with `break-passed` inside about 30 s.

## 9. Switches

| Variable | Default | |
|---|---|---|
| `ITW_CLASH_HALStayLow` | true | false releases every aircraft and stops |
| `ITW_CLASH_HALStayLowPower` | 20 | lower is gentler and slower |
| `ITW_CLASH_HALStayLowCruiseHeight` | 30 | also the egress height |
| `ITW_CLASH_HALStayLowFinalHeight` | 10 | last 300 m |
| `ITW_CLASH_HALUnloadHotDropHeight` | 45 | |

## 10. Still open

- Cross-track on the run-in (section 6).
- Takeoff: the pilot climbs straight up to cruise height before it moves.
  Lower now, since cruise is, but not addressed.
- Idle transports hover at about 48 m. Not HAL's lift, not touched.
- HotDrop's own profile still pops to 130 m. It declines every HAL-busy
  carrier, so it did not fly on this log.
