# C.L.A.S.H. Commander Supports Model

Status: **design, being built.** Phase 0 (per-side air-loss closures, hard-kill
fighter denial) shipped in `448324b`; see `COMMANDER_SUPPORTS_PHASE0.md`.

Every number in this document is a placeholder for calibration, not a decision.

## 1. Purpose

COLOSSUS becomes the layer that invokes commander-level supports: reconnaissance,
air strikes and airborne insertions. HAL keeps the fight going. Supports change
the numbers COLOSSUS already decides with:

- **Look** turns an unknown objective into a real count.
- **Hit** removes enemy strength.
- **Land** adds our strength.

At a 2:1 push ratio, every point of enemy a strike removes cuts the force a push
needs by two points. That leverage is why supports belong to the strategic layer.

## 2. Authority

### 2.1 Who owns what

| Layer | Owns | Never |
|---|---|---|
| COLOSSUS | The picture, posture and plan objective; which effect is wanted and what to spend; the weighted pick | Orders a HAL group, moves a unit, flies anything |
| Knowledge layer | Reported contacts, their uncertainty and status; per-objective intelligence state | Uses a live enemy position in a decision |
| Supports admission | Gates, ledger, lanes, reservations | Chooses objectives or targets |
| Support executors | Spawn, flight, release, egress and despawn of support assets | Hands a support aircraft to HAL |
| Impasse | Its unit factory (`ITW_AtkUnitToGroup`, `ITW_AtkSpawnVeh`) and the unit cap the airborne squad counts against | |
| HAL | The airborne squad after landing, through one native order | Flies a support asset |
| Checkbook, ETB | HAL's procurement, unchanged | Spends support money |

### 2.2 Kill criterion

COLOSSUS's header is amended to read:

> If COLOSSUS ever issues an order to a HAL group, moves a unit, or duplicates
> HAL's dispatcher, it has failed and should be deleted. Supports it requests run
> on assets that exist only for that support.

### 2.3 Units and abilities

A support is an **ability**: it declares a fixed end at request time (ordnance,
passes or loiter time), Supports owns it from spawn to despawn, and it never
joins HAL. Anything that persists and picks its own targets is a **unit** and
belongs to the Checkbook or the ETB.

The executor owns the support's flight path and weapons release. That is the
point of an ability: AI aircraft handed a target circle, waste passes and choose
their own.

## 3. Invariants

1. COLOSSUS proposes; it never executes.
2. No support aircraft or crew enters a HAL pool or `RydHQ_Included`.
3. Every support entity carries `ITW_CLASH_SupportAsset` from the moment it is
   created.
4. No support acts on a position nobody reported. Supports read reported
   positions, never the live position of a known object.
5. A roll is a proposal. Money and the lane are reserved together in one
   unscheduled block, and every reservation ends in a launch or a release.
6. Money is spent only when a support delivers or its aircraft is lost. Anything
   that ends without delivering, with the aircraft alive, is refunded in full.
   The cooldown stands either way.
7. Danger close is checked at release, not only at request.
8. No on-screen warning of any support, for either side. Tells are in the world.
9. Weights, prices, cooldowns and income are identical for both sides.
10. With a support switched off, every existing code path it touches behaves
    exactly as before.
11. Every assessment logs its pool, exclusions, weights, draw and result.
12. HAL source is never edited.

## 4. Knowledge layer

Built first; every support decision reads from it. It observes only.

### 4.1 Sensors

All feed one picture per side:

- HAL groups, players and every other group of the side: what they see.
- HAL's own recon.
- Support crews: the UAV, and a strike jet's own sensors while on station.
- Counter-battery fixes, as leads.

There is no "gunfire heard" sensor. Squads see units and report them.

The **candidates** are HAL's known enemies (`RydHQ_KnEnemies`) plus anything a
support crew knows about. The **observers** are the side's groups, never the HQ
group: HAL's `Rev.sqf` reveals every known enemy to the HQ, which would refresh
its timestamps without anyone looking.

### 4.2 Reports

For each candidate, each observing group's leader gives one report from
`targetKnowledge`: perceived position, time last seen and position error. Reports
are never merged. Each is projected on its own (4.3) and the contact keeps the
single best one.

A read-only truth diagnostic logs reported against actual positions, never fed
back into any decision. It also confirms that `lastSeen` runs on the `time`
clock; a report whose `lastSeen` lies in the future or below zero is discarded.

### 4.3 Uncertainty

> R = E + v × (age + time ahead)

- **E:** the report's position error.
- **v:** a conservative movement allowance by class: statics 0 m/s, infantry
  2 m/s, ground vehicles 8 m/s. Stationary now is not stationary later; only
  real statics get zero.
- **age:** time since the report.
- **time ahead:** zero for the status; the expected flight time to release when
  a support is weighed.

This is a movement envelope, not a confidence interval: where the target could
have gone, not where it probably went.

### 4.4 Contact status

| Status | Rule | Meaning |
|---|---|---|
| Observed | Age within 60 s, R within 100 m | Seen recently, small uncertainty |
| Fixed | Static, error within 100 m, age within 900 s | Precise historical location, existence unconfirmed |
| Lead | R within 300 m, or a counter-battery fix | Rough position |
| Lost | Anything else | Not enough to act on |

**Existence confidence** scales a contact's worth: full for 120 s after the last
sighting, falling to zero at 900 s. A fixed MG nest still draws a coordinate
strike for a while, at a falling value.

**Moving:** a contact whose reported position moved more than 30 m between
reports.

### 4.5 Objective intelligence state

Measured inside `ITW_CLASH_ColossusObjectiveRadius`.

| State | Meaning |
|---|---|
| Unobserved | No observed, fixed or lead contact inside, and nobody has looked recently |
| Recent contact | At least one observed or fixed contact inside |
| Stale contact | Leads only |
| Recently cleared | Looked at within 300 s and nothing found |

A "look" is stamped per objective and side by friendly units within
`ITW_CLASH_AirPictureObservedRadius` and by the UAV's footprint.
`ITW_CLASH_AirPicture_fnc_Observed` reads the stamp, so a place the UAV looked at
and found empty counts as observed.

### 4.6 COLOSSUS on the layer

- Every objective's picture carries its intelligence state and a second enemy
  strength counted from reported positions, so both are logged side by side.
- `ITW_CLASH_ColossusReportedPositions` (default **false** for the first run)
  switches the verdict onto the reported strength, and makes the recommendation
  treat Unobserved as unknown rather than soft.

## 5. The menu

### 5.1 Verbs and flavors

| Verb | Flavor | Routine | Knowledge needed | Default |
|---|---|---|---|---|
| Look | Recon UAV | Orbit | None | On |
| Hit a point | Bomb pass | Strike pass | Observed or fixed | On |
| Hit a point | Guided pass | Strike pass with on-site scan | A vehicle that is observed, fixed or a lead | On |
| Hit an area | Carpet | Strike pass (bomber) | Any status but lost | On |
| Land | Helicopter airborne | Drop run | Drop zone Recent contact or Recently cleared | Off |
| Land | C-130 troops | Drop run | As above | Off |
| Land | Vehicle drop (add-on to C-130) | Drop run | As above | Off |

Three delivery routines carry seven flavors. A new flavor is a registry row plus,
where needed, a payload function.

### 5.2 Registry row

Each flavor declares: verb, routine, the statuses it accepts, eligible target
classes, the faction aircraft that can fly it, cadence (and from it the price),
flavor cooldown, footprint radius, its weights (6.3) and its enable switch.

### 5.3 Deferred

- Smoke screen (a flavor air defence cannot stop).
- UAV laser designation for laser-guided bombs.
- The on-site scan for the bomb pass.
- An outer shaping ring for overwatch positions and reinforcements.
- Strikes on formations away from the plan objective.
- Players flying or marking supports through the employment system.

## 6. Decision: the weighted pool

### 6.1 When

Once per COLOSSUS assessment per side, after the plan and order are committed.
One roll, at most one proposal.

### 6.2 The pool

1. **Targets.** Contacts within 150 m of each other are clustered. A cluster's
   worth is the sum of COLOSSUS's own weights (infantry 1, vehicle 1.5, armor 3,
   static 0.5), each times its existence confidence. Its aim point is the
   worth-weighted mean of the members' reported positions, and its class for the
   weight table is its dominant composition.
2. **Where.** Clusters inside the objective radius of:
   - the plan objective, when posture is PUSH;
   - any held objective under pressure, in any posture.
3. **Candidates.**
   - One strike candidate per eligible flavor and cluster.
   - The UAV launch, when the recon lane is free.
   - One airborne candidate per eligible objective.
   - Save.
4. **Gates first.** Every hard gate (7.1) runs before the roll. Excluded
   candidates are logged with their reason and never enter the pool.

A held objective is **under pressure** when it has known enemy inside and our
ratio there is below VULNERABLE.

### 6.3 Strike weights

Coarse 0 to 3. Zero means physically impossible, nothing else.

| Target class | Bomb pass | Guided pass | Carpet |
|---|---|---|---|
| Armor or vehicles, parked | 3 | 3 | 1, or 2 when three or more are clustered |
| Armor or vehicles, moving | 1 | 3 | 1 |
| Statics or infantry not moving | 3 | 1 | 2 |
| Infantry moving | 2 | 0 (nothing to lock) | 3 |
| Leads only | 0 (needs observed or fixed) | 1 for vehicles, else 0 | 2 |

**Uncertainty multiplier.** Each strike weight is multiplied by
`min(1, footprint ÷ R)`, with R projected to release (4.3). Footprints: bomb pass
50 m, carpet 60 m. A cluster whose R exceeds 300 m is excluded
(`TOO_UNCERTAIN`). The guided pass is exempt: its jet acquires the target on
site (9.3).

### 6.4 Family weights

| Candidate | Weight |
|---|---|
| UAV launch | 3 if the plan objective is Unobserved; 1 if it or a held point is Stale contact; 0.5 otherwise |
| Airborne | Base 1. +1 if the push is short by more than the best strike could remove. +1 if our nearest available ground force is more than 1500 m out. 3 for a held point under pressure with no anchor |
| Save | 3 with the bank below a third of its cap, 2 below two thirds, 1 below full, 0.5 at the cap |

Modifiers:

- **Urgency.** Candidates at a held point are multiplied by 1 to 3. The further
  our ratio there has fallen below VULNERABLE, the higher, with the maximum when
  the point has no anchor.
- **Corridor.** Candidates whose route reads HOT or CONTESTED are multiplied by
  0.5.

### 6.5 The pick

`selectRandomWeighted` over the pool in a stable order: family, flavor, objective
index, target key. The draw value is logged so any pick can be recomputed offline
from the log.

### 6.6 Shape, then decide

Strikes go in while the push is still short and the order is still DEFEND.
COLOSSUS's order logic is unchanged: it counts what actually died on the next
assessment. It never orders ATTACK on a strike that has not landed.

Under CONSOLIDATE only candidates at held points enter the pool.

## 7. Admission and commitment

### 7.1 Hard gates

| Gate | Rule | Denial |
|---|---|---|
| Switch | Flavor enabled | `DISABLED` |
| Knowledge | The flavor's statuses, rechecked at admission | `NO_CONTACT`, `TOO_UNCERTAIN` |
| Objective | Plan objective under PUSH, or a held point under pressure. Not capture-frozen (`ITW_CLASH_fnc_ObjectiveFrozen`) | `NOT_PLAN_OBJECTIVE`, `CONSOLIDATING`, `OBJECTIVE_FROZEN` |
| Value | Cluster worth at least 2 | `BELOW_FLOOR` |
| Danger close | Footprint plus 300 m clear of every living friendly: on foot, in vehicles, in aircraft below 300 m, under canopy. 500 m for players | `DANGER_CLOSE` |
| Corridor | UAV and helicopters use the default fighter rule (`HARD_KILL`); jets use `ANY_AA_MISSILE`. `AIR_DENIED` denies | `AIR_DENIED` |
| ETB overlap | Target not already tasked to an ETB responder (`ITW_CLASH_HALThreatCoverage_fnc_TaskedAgainst`) | `ETB_ANSWERING` |
| Lane | Recon lane: one UAV. Commitment lane: one strike or drop in flight | `LANE_BUSY` |
| Cooldown | Per flavor and per objective | `COOLDOWN` |
| Budget | Price affordable | `INSUFFICIENT_FUNDS` |
| Capability | The faction has the aircraft: UAV class (vanilla fallback), an attack plane, a guided anti-armor weapon on it, a transport helicopter, a transport plane | `NO_AIRCRAFT`, `NO_GUIDED_WEAPON` |
| Airfield | Fixed-wing flavors need an owned airfield (`ITW_ObjOwnedAirports`) | `NO_AIRFIELD` |
| Headcount | Airborne only: Impasse's live count of the side plus the squads stays under its cap | `NO_HEADROOM` |

In dry run (`ITW_CLASH_SupportsDryRun`) admission runs every gate, logs the full
result and stops before reserving.

### 7.2 Lanes

Two lanes per side, one shared budget:

- **Recon lane:** one UAV on station or relaunching.
- **Commitment lane:** one strike or drop from reservation until done.

A loitering UAV never blocks strikes or drops.

### 7.3 The transaction

1. COLOSSUS's roll produces a proposal.
2. Admission reruns every gate.
3. In one unscheduled block, so no other script can interleave: recheck the
   money and the lane, reserve the price, take the lane slot, start the
   cooldowns.
4. Setup delay. Nothing exists yet, so cancelling costs nothing.
5. **Pre-run check**, before anything spawns: knowledge recomputed with the real
   age, the hard limit, danger close, the corridor, and for airborne the
   headcount. Failing any revokes and refunds.
6. Spawn and fly.
7. **Release check:** the latest report, danger close, and for guided the
   on-site scan. Failing breaks off and, with the aircraft alive, refunds.

Impasse's unit cap cannot be reserved without editing Impasse's spawner, so
airborne headcount is checked at admission and again at the pre-run check, where
the squad is created. The window between is the setup delay.

HAL and COLOSSUS never share a wallet. The shared resources are Impasse
headcount (checked twice) and targets (the ETB overlap gate).

### 7.4 Lifecycle

`PROPOSED` then `RESERVED` then `DELAY` then `INBOUND` then `RELEASED` (or
`DROPPED`) then `EGRESS` then `DONE`.

Terminal alternatives:

| State | When | Money |
|---|---|---|
| `REVOKED` | Pre-run check failed; nothing spawned | Refunded |
| `BREAKOFF` | No target found, danger close or line of sight blocked at release; aircraft alive | Refunded |
| `LOST` | Aircraft destroyed or crew killed before delivering | Spent |

The setup delay is varied per request (45 to 120 s) and never announced.

## 8. Budget

- **Ledger:** one per side, separate from Impasse tickets, the Checkbook and the
  ETB.
- **Income:** flat over time, the ETB's formula with its own scale, identical for
  both sides. Nothing is earned from kills or captures.
- **Cap:** the price of the most expensive enabled flavor. Income stops at the
  cap.
- **Prices:** set from the intended cadence. Price = income per minute times the
  intended interval:

  | Flavor | Intended cadence |
  |---|---|
  | UAV | Every 4 minutes |
  | Bomb pass, guided pass | Every 20 minutes |
  | Carpet | Every 40 minutes |
  | Helicopter airborne | Every 30 minutes |
  | C-130 troops | Every 50 minutes |

- **Holding discount:** supports at a held point cost 0.75 of the price.
- **Starting cash:** one UAV.
- **Persistence:** reset on load. Nothing is written to `profileNamespace`.

## 9. Execution

### 9.1 Common flight rules

- Aircraft spawn **after** the setup delay, in flight, on the line from the
  side's origin to the task, at most 4 km (jets) or 5 km (helicopters, transport
  planes) short of it. Origins: the rear air base for helicopters and the UAV,
  an owned airfield for fixed-wing.
- Crewed aircraft come from Impasse's own factory (`ITW_AtkSpawnVeh`), so the
  crew is the faction's. The UAV is created with its own AI crew, joined to a
  group of the side.
- CARELESS, autocombat off, combat mode BLUE, one far waypoint, `flyInHeight`,
  and `flyInHeightASL` as a floor for fixed-wing.
- Air-to-air missiles removed from strike aircraft, so a support jet never reads
  as a fighter to the other side and never engages aircraft.
- After the task: flares, egress, despawn at distance or by timeout.

### 9.2 Orbit: recon UAV

- **Class:** the side's UAV list, air classes only, falling back to the side's
  vanilla UAV. Weapons removed.
- **Loiter:** 500 m AGL, inside MANPAD reach and above small arms.
- **Each poll:** reveals to the HQ group what its sensors (`getSensorTargets`)
  and crew see, so HAL learns it, and stamps a look on every objective inside
  its footprint.
- **Task, refreshed each assessment without a roll:** the plan objective if
  Unobserved, else an objective with leads only, else overwatch of the plan
  objective.
- **Declared end:** 15 minutes of loiter, then it leaves and despawns.
- **Loss:** the recon lane stays blocked for a 300 s relaunch delay. The loss
  feeds AirPicture's side-aware loss counter.

### 9.3 Strike pass

- The jet flies a line through the aim point. Unguided release is timed by
  ballistic fall time from the jet's height and speed, aimed at the latest
  reported position.
- **Bomb pass:** four unguided bombs, scripted under the aircraft at release with
  its velocity (class tunable, `Bo_Mk82` for both sides).
- **Guided pass, with on-site scan:**
  1. Inbound with radar on. Once within 3 km, read the jet's own
     `getSensorTargets` and its crew's known targets for enemy ground vehicles
     inside the scan radius around the reported position. Scan radius = R
     projected to arrival, capped at 500 m.
  2. **Valid:** alive, a vehicle, terrain line of sight from the jet, clear of
     danger close, not tasked to an ETB responder. Pick the nearest to the
     report.
  3. **Fire** two shots from the jet's own guided anti-armor weapon:
     `fireAtTarget`, and if that returns false, the weapon's missile spawned at
     the jet and given the target with `setMissileTarget`. That fallback is
     legitimate only because the jet acquired the target itself.
  4. **Nothing valid** within a 20 s window: `BREAKOFF`, egress, despawn,
     refund.
- **Carpet:** 21 bombs in a 300 by 160 m pattern laid relative to the aim point,
  released along the bomber's line.
- **Every bomb:** released only while the aircraft is alive, and given the
  aircraft as its shooter (`setShotParents`) so kills are credited.

### 9.4 Drop run

- **Squads:** created at the pre-run check by C.L.A.S.H. through Impasse's unit
  factory (`ITW_AtkUnitToGroup`). The template is the archetype of a living
  infantry squad of the side, so the drop matches what Impasse fields. As many
  squads as the cargo holds, capped (helicopter 2, C-130 3). They count against
  Impasse's live cap the moment they exist.
- **Reserved until hand-off:** the squads carry `ITW_CLASH_ReconstitutionTransit`,
  which every sweep (Impasse's infantry manager, FormationAdmission, the BLUFOR
  adoption loop, enemy classification) already treats as hands-off.
- **Helicopter:** its own routine; HALUnload is untouched. Run-in at the hot-drop
  height (45 m), release lead from `ITW_CLASH_HALUnload_fnc_StickLead`, flares
  through Thunder Run's countermeasure primitives, jumpers out through
  `ITW_AtkParachute`, then a lateral break and egress.
- **C-130:** CARELESS with a `flyInHeightASL` floor at 250 m above the drop zone.
  Same jumper exit.
- **Vehicle add-on:** a crewed light vehicle from `ITW_AtkSpawnVeh`, released
  after the troops through `ITW_FncVehicleHalo`.
- **Abort before anyone jumps:** the aircraft turns home, the squads are deleted
  with it, and the money comes back.
- **Hand-off,** once each squad leader is down plus a 10 s settle:
  1. Clear the transit flag.
  2. Register with the side's commander through
     `ITW_CLASH_DualHAL_fnc_RegisterGroup`; FormationAdmission's minimum size
     applies.
  3. One native HAL order, issued as HAL's own dispatcher issues it: capture on
     the plan objective, defend on a held point.
  4. Refused: the squad is left on foot for Impasse's own infantry manager.
  5. The vehicle crew registers the same way, marked as a vehicle crew.

### 9.5 Provenance

`ITW_CLASH_SupportAsset` (the support id) goes on every support vehicle, crew
group and crew unit, and on the airborne squads until hand-off. Support crew
groups also carry `ITW_CLASH_ExcludeHAL` and `ITW_CLASH_VehicleCrewGroup`, which
the lifecycle reservation and FormationAdmission already honour, and
AttackRestore skips support groups.

## 10. Telemetry

Prefixes: `supports-core`, `supports-uav`, `supports-strike`,
`supports-airborne`, `knowledge`.

| Line | Content |
|---|---|
| `supports-pool` | Side, posture, plan objective; every candidate in stable order with family, flavor, objective, target key, class, status and weight; every exclusion with its reason; draw value; pick |
| `supports-admission` | Proposal, gate results, reservation or denial reason |
| `supports-state` | Each lifecycle transition |
| `supports-outcome` | Worth destroyed, aircraft lost, squads handed off, refunded or spent |
| `supports-ledger` | Periodic: cash, cap, income, lanes |
| `knowledge-objective` | Periodic per objective: intelligence state, observed, fixed, leads, oldest report |
| `knowledge-truth` | Diagnostic: reported against actual error, by class |
| `supports-ready`, `knowledge-ready` | Boot: version, dry run, every switch |

## 11. Rollout

- `ITW_CLASH_SupportsDryRun` starts true: everything decides, admits and logs,
  nothing spawns.
- Each flavor has its own switch. Airborne starts off, and with it off nothing
  on the drop path runs.
- Test order on one build:
  1. Dry run. Tunes cadence and validates the knowledge layer.
  2. UAV and strikes live.
  3. Helicopter airborne live.
  4. C-130 and vehicle drop live.

## 12. Parity

Weights, prices, cooldowns and income are identical for both sides. What a side
can fly follows its faction's aircraft, as with the ETB: a side without the
class goes without that flavor.

## 13. To verify in engine

1. `targetKnowledge`: its clock, its position error, and whether `reveal`
   refreshes last-seen (the truth diagnostic answers both).
2. `setMissileTarget` on the game version in use.
3. What the UAV's and a strike jet's `getSensorTargets` actually detect over
   Altis terrain.
4. Unguided release accuracy against the ballistic estimate.
5. A C-130 drop height that clears terrain and survives.
6. Whether `EntityKilled` fires for the UAV's AI crew, so its loss is attributed
   to a side.

## 14. Tunables

All placeholders.

| Setting | Value |
|---|---|
| Knowledge poll | 10 s |
| Movement allowance | Statics 0, infantry 2, vehicles 8 m/s |
| Observed | Age 60 s, R 100 m |
| Fixed | Error 100 m, age 900 s |
| Lead | R 300 m |
| Existence confidence | Full to 120 s, zero at 900 s |
| Moving threshold | 30 m between reports |
| Recently cleared window | 300 s |
| Cluster radius | 150 m |
| Value floor | 2 |
| Footprints | Bomb pass 50 m, carpet 60 m |
| Hard uncertainty limit | 300 m |
| Danger close margin | 300 m, 500 m for players |
| Corridor HOT or CONTESTED multiplier | 0.5 |
| Holding discount | 0.75 |
| Setup delay | 45 to 120 s |
| Spawn distance | Jets 4 km, helicopters and transport planes 5 km |
| UAV altitude, loiter, relaunch | 500 m AGL, 15 min, 300 s |
| Guided scan | Within 3 km, radius cap 500 m, window 20 s |
| Bomb pass payload | 4 bombs |
| Guided pass payload | 2 shots |
| Carpet | 21 bombs, 300 by 160 m |
| Helicopter drop height | 45 m |
| C-130 drop height | 250 m |
| Squads per drop | Helicopter 2, C-130 3 |
| Airborne far-force threshold | 1500 m |
| Hand-off settle | 10 s |
