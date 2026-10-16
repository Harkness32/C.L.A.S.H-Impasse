# C.L.A.S.H. Commander Supports Model

Status: **built; live by default since supports v3.** Phase 0 (per-side air-loss closures, hard-kill
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

Where a contact is placed and when it was last confirmed are kept apart. The
position is the report with the smallest uncertainty **now**, which is not
always the newest: a newer but sloppier sighting does not move it. Any newer
sighting still confirms the contact exists (`confirmedAt`), and existence
confidence and forgetting read that.

A read-only truth diagnostic logs reported against actual positions, never fed
back into any decision. It also confirms that `lastSeen` runs on the `time`
clock; a report whose `lastSeen` lies in the future or below zero is discarded.

Knowledge v3 instruments both, because the run of 2026-10-15 rejected 743
reports on the clock and the truth table could not tell an engine error from a
movement allowance that is too small:

- **Clock rejections** are sampled (up to 300) with the raw `lastSeen` against
  `time`, `serverTime` and `diag_tickTime`, whether the report came from a unit
  or a group, and whether another member of the group held a valid report. The
  periodic `knowledge-clock-anomaly` line gives the spreads, so the next run says
  which clock `targetKnowledge` really uses and whether the rejection loses
  anything.
- **Truth samples** (up to 400 per class bucket, reports at least 10 s old)
  carry the speed the report's error implies, whether the contact was moving,
  whether it fell outside its envelope, and its real speed.
  `knowledge-truth-speed` gives, per bucket, how many broke the envelope while
  moving and while settled, and the spreads of implied and real speed.

The run of 2026-10-15 already showed the engine's own error near zero and the
breaks coming from movement: vehicles above 11 to 12 m/s, infantry above about
2.7 m/s. The allowances (4.3) stay where they are until the speed lines set
them from data.

Knowledge v4, from the run of 2026-10-16:

- **The clock rejections were never clock trouble.** Every one (11 to 93 a
  minute) had `lastSeen` exactly -2147483.648 (-2^31/1000), which is what
  `targetKnowledge` gives for a target the man knows of but has never seen: a
  reveal or a report, not a sighting. None was in the future. They are now
  their own count, `knowledge-never-seen` [rejected, groupmates checked,
  groupmates who had seen it], and the clock line is kept for real anomalies.
  Rejecting them stays right: a revealed target is HAL's own knowledge, and
  taking it as a sighting would feed it back as fresh. In 5 to 12 a window a
  groupmate had seen the target himself; reading the best groupmate's report
  would recover those, and is not done.
- **True speed is a magnitude** (`vectorMagnitude velocity`): `speed` is signed,
  and reversing vehicles read negative in v3.
- That run gave about 96 vehicle samples, 14 armour and 1 infantry, almost all
  from B's side: too thin to set allowances. Vehicle true speed's p90 was 9 to
  15 m/s against the 8 m/s allowance.

### 4.3 Uncertainty

> R = E + v × (age + time ahead)

- **E:** the report's position error.
- **v:** a conservative movement allowance by class: statics 0 m/s, infantry
  2 m/s, ground vehicles 8 m/s. Stationary now is not stationary later; only
  real statics get zero.
- **age:** time since the report.
- **time ahead:** zero for the status; the expected flight time to release when
  a support is weighed.

R never goes below `ITW_CLASH_KnowledgeMinUncertainty` (5 m): a report with zero
error and zero age is still not a point. Without the floor every fresh static
read as R = 0, which made 100% of statics "outside" their envelope in the truth
table for any nonzero engine error.

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
confirmation, falling to zero at 900 s. A fixed MG nest still draws a coordinate
strike for a while, at a falling value.

**Losing the position is not losing the enemy.** Two questions are answered
from two lists:

| Question | Reads | Stale contacts |
|---|---|---|
| Can I hit this position? | `fnc_Contacts`: never a LOST record | Only while the uncertainty meets the weapon's limit |
| Could the enemy still be here? | `fnc_Held`: every record still believed to exist | Counted by presence |

**Presence** of a contact in a place is its existence confidence times the share
of its uncertainty circle (radius R around its reported position) that lies
inside the place: the exact two-circle overlap. Reported strength sums class
worth times presence. A LOST record with presence of at least 0.1 counts as a
lead for the intelligence state, so the place reads Stale contact, never cleared.
One sighting at an objective's centre, error 15 m:

| | 60 s | 120 s | 180 s | 300 s | 450 s |
|---|---|---|---|---|---|
| Armor: strength (of 3) | 3.00 | 0.79 | 0.33 | 0.10 | 0.03 |
| Armor: intel | Stale | Stale | Stale | Unobserved | Unobserved |
| Infantry: strength (of 1) | 1.00 | 1.00 | 0.92 | 0.51 | 0.17 |
| Infantry: intel | Stale | Stale | Stale | Stale | Stale |

**Moving:** a contact whose reported position moved more than 30 m between
reports.

### 4.5 Objective intelligence state

Measured inside `ITW_CLASH_ColossusObjectiveRadius`.

| State | Meaning |
|---|---|
| Unobserved | No observed, fixed or lead contact inside, and nobody has looked recently |
| Recent contact | At least one observed or fixed contact inside |
| Stale contact | Leads only, including LOST records still present there (4.4) |
| Recently cleared | Looked at within 300 s and nothing found |

Recently cleared needs **positive evidence**: an empty contact list never clears
a place. A "look" is stamped per objective and side by our people **on the
ground inside the objective radius** (aircraft overhead and anyone under canopy
do not count) and by the UAV on station. Looks are kept per source, so a friendly
look never refreshes a UAV look. `ITW_CLASH_AirPicture_fnc_Observed` reads only
UAV looks.

### 4.6 COLOSSUS on the layer

- Every objective's picture carries its intelligence state and a second enemy
  strength counted from reported positions, so both are logged side by side.
- `ITW_CLASH_ColossusReportedPositions` (default **false** for the first run)
  switches the verdict onto the reported strength, and makes the recommendation
  treat Unobserved as unknown rather than soft.
- **A push is for ground the commander does not hold** (v6). Each picture entry
  carries `held`, from Impasse's own ownership (`ITW_ObjContestedOwnerIsFriendly`,
  through `ITW_CLASH_Colossus_fnc_HeldBy`, which the supports layer also uses).
  The PUSH ranking runs over unheld objectives only. When the side holds every
  active objective there is nothing to push: the plan carries objective -1, is
  not feasible, logs `colossus-no-push-candidate`, and the order is DEFEND;
  concentration declines with the same reason. Run of 2026-10-15: B planned its
  own objective 8 in 16 assessments of 16 while holding 8 and 14.
- **Concentration waits for held ground to be anchored** (v7, for real). Up to
  v6 the anchor gate's `exitWith` sat inside an if-then, which leaves only that
  block: it logged `holding-unanchored` and carried on. On 2026-10-16 B
  concentrated on 23 83 times while holding 8 and 14 unanchored, each right
  after saying it would not. The gate is now at function scope.
- Concentration is asked on every HAL offer, about once a second per side, so
  its lines are said when the answer changes, each with how many times the
  previous answer repeated (904 lines in 18 minutes before).

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
- Strikes on formations beyond the 2 km influence area (6.2).
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
2. **Where.** The objective biases where supports go; it does not decide which
   enemies exist. Clusters anywhere inside the **influence area** (2000 m) of a
   target objective:
   - the plan objective, when posture is PUSH;
   - any held objective under pressure, in any posture.

   One clustering covers the union of the target objectives' influence areas,
   so a cluster near two objectives is one cluster and enters the pool once per
   flavor, at the objective that values it most.
3. **Candidates.**
   - One strike candidate per eligible flavor and cluster.
   - The UAV launch, when the recon lane is free.
   - One airborne candidate per eligible objective.
   - Save.
4. **Gates first.** Every hard gate (7.1) runs before the roll. Excluded
   candidates are logged with their reason and never enter the pool.

A held objective is **under pressure** when our ratio there is below VULNERABLE
against its **pressure**: every enemy still believed to exist, at class worth
times its presence in the point's influence area times the distance falloff at
its reported position. Pressure is computed per objective: one tank threatening
two points is pressure on both, though it enters the pool once.

### 6.3 Strike weights

Coarse 0 to 3. Zero means physically impossible, nothing else.

| Target class | Bomb pass | Guided pass | Carpet |
|---|---|---|---|
| Armor or vehicles, parked | 3 | 3 | 1, or 2 when three or more are clustered |
| Armor or vehicles, moving | 1 | 3 | 1 |
| Statics or infantry not moving | 3 | 1 | 2 |
| Infantry moving | 2 | 0 (nothing to lock) | 3 |
| Leads only | 0 (needs observed or fixed) | 1 for vehicles, else 0 | 2 |

**Distance falloff.** Each strike weight is multiplied by

> W(d) = 1 inside the objective radius (500 m), 1 − 0.7 × (d − 500) ÷ 1500 out to
> 2000 m, nothing beyond

where d is the cluster's distance from the objective. **Threat proximity:** a
cluster within 1000 m of one of our ground formations committed to that
objective is weighted 1 wherever it stands. Committed follows COLOSSUS's own
rule: the commander's groups, less support, special forces, artillery, naval,
cargo-only, static and exhausted pools, with the leader on the ground within
900 m of the objective. Being that close to our people makes the enemy relevant;
it does not prove it is firing. The 2 km cutoff is hard; the pool line logs how
many contacts crossed it since the last assessment, and a hysteresis band is the
fix if that flaps.

**Uncertainty multiplier.** Each strike weight is multiplied by
`min(1, footprint ÷ R)`, with R projected to release (4.3). Footprints: bomb pass
50 m, carpet 60 m. A cluster whose R exceeds 300 m is excluded
(`TOO_UNCERTAIN`). The guided pass is exempt: its jet acquires the target on
site (9.3).

### 6.4 Family weights

| Candidate | Weight |
|---|---|
| UAV launch | 3 if the plan objective is Unobserved or Stale contact (uncertainty is blocking a decision there); 1 for another objective with Stale contact; 0.5 otherwise |
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
| Objective | Plan objective under PUSH, or a held point under pressure. Not capture-frozen (`ITW_CLASH_fnc_ObjectiveFrozen`). Any other objective is simply not a candidate | `CONSOLIDATING`, `OBJECTIVE_FROZEN` |
| Value | Cluster worth at least 2 | `BELOW_FLOOR` |
| Danger close | Footprint plus 300 m clear of every living friendly: on foot, in vehicles, in aircraft below 300 m, under canopy. 500 m for players | `DANGER_CLOSE` |
| Corridor | UAV and helicopters use the default fighter rule (`HARD_KILL`); jets use `ANY_AA_MISSILE`. `AIR_DENIED` denies | `AIR_DENIED` |
| ETB overlap | Target not already tasked to a busy ETB responder of the side (`ITW_CLASH_Supports_fnc_ETBAnswering` reads `ITW_CLASH_ThreatCoverageTarget` on the commander's groups) | `ETB_ANSWERING` |
| Lane | Recon lane: one UAV. Commitment lane: one strike or drop in flight | `LANE_BUSY` |
| Cooldown | Per flavor and per objective | `COOLDOWN` |
| Budget | The candidate's own price (taking or holding) affordable, checked before the roll so an unaffordable option never wins it | `INSUFFICIENT_FUNDS` |
| Capability | The faction has the aircraft: UAV class (vanilla fallback), an attack plane, a guided anti-armor weapon on it, a transport helicopter, a transport plane | `NO_AIRCRAFT`, `NO_GUIDED_WEAPON` |
| Airfield | Fixed-wing flavors need an owned airfield (`ITW_ObjOwnedAirports`) | `NO_AIRFIELD` |
| Headcount | Airborne only: Impasse's live count of the side plus the squads stays under its cap | `NO_HEADROOM` |
| Drop zone | Airborne only: the point is `RECENT_CONTACT` or `RECENTLY_CLEARED`, and dry open ground is found near it | `DZ_UNASSESSED`, `NO_DZ` |

Dry run (`ITW_CLASH_SupportsDryRun`, off by default since v3) is shadow mode. Everything
decides, admits and reserves exactly as it would live: the money is spent, the
cooldowns start and the lane is held for the support's nominal duration, then
the support settles as `DRY_RUN`. Nothing spawns. Shadow-spending keeps the dry
run's cadence honest: a commander that never spent would pick every
assessment, and the dry run would say nothing about how often supports really
happen.

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
airborne headcount is checked at admission and again at the pre-run check. The
squads are created by the drop executor straight after the pre-run check, before
the aircraft spawns. The window between admission and creation is the setup
delay.

HAL and COLOSSUS never share a wallet. The shared resources are Impasse
headcount (checked twice) and targets (the ETB overlap gate).

### 7.4 Lifecycle

`RESERVED` then `DELAY` then `INBOUND` then one terminal state. Release, the
jump and egress are logged by the executors, not as core states. Every
transition is a `supports-state` line.

| State | When | Money |
|---|---|---|
| `DONE` | Delivered: bombs released (all or part), missiles fired, the UAV's loiter served, troops jumped | Spent |
| `REVOKED` | Pre-run check failed, or the executor could not start (no aircraft, no drop zone, no squads, spawn failed, no executor); nothing flew | Refunded, up to the ceiling |
| `BREAKOFF` | Aircraft alive and nothing delivered: no target found, too uncertain or danger close at release, passed wide, never reached the task, every bomb skipped | Refunded, up to the ceiling |
| `LOST` | Aircraft destroyed or unable to fly before delivering | Spent |
| `DRY_RUN` | Shadow mode | Spent (shadow) |

A refund never lifts the wallet past its ceiling (one big support banked, never
two); the clipped amount is logged on the outcome line. The cooldown stands
whatever the outcome.

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

- Aircraft spawn **after** the setup delay, in flight, on the bearing from the
  side's origin to the task, always the full 4 km (jets) or 5 km (helicopters,
  transport planes) short of it, so a strike has its run-in even when our
  airfield is next to the target. That point lies beyond our airfield, in our own
  airspace. If it would fall off the map, the bearing turns in 15 degree steps up
  to 90 either way, and only then is the point clamped 500 m inside the edge. A
  strike's spawn is computed from its target cluster, not the objective centre. Origins: the rear air base for helicopters and the UAV,
  an owned airfield for fixed-wing.
- Crewed aircraft come from Impasse's own factory (`ITW_AtkSpawnVeh`), so the
  crew is the faction's. The UAV is created with its own AI crew, joined to a
  group of the side.
- CARELESS, autocombat off, combat mode BLUE, one far waypoint, `flyInHeight`,
  and `flyInHeightASL` as a floor for fixed-wing.
- Air-to-air missiles removed from strike aircraft, so a support jet never reads
  as a fighter to the other side and never engages aircraft.
- After the task: flares, then egress. Strike and drop aircraft fly on 2 km past
  the task, turn 120 degrees to whichever side the corridor classifier rates
  colder from the turn point to home (a mirror-image tie is a coin toss), and fly
  home; never an about-face over the target. Despawn 4 km from the task or by
  timeout. A shot-down aircraft is never deleted: it falls where it was hit, and
  the engine's own clean-up takes the wreck.

### 9.2 Orbit: recon UAV

- **Class:** the side's UAV list, air classes only, fixed-wing first, falling
  back to the side's vanilla UAV. A rotary UAV only when the faction has no
  fixed-wing one: on 2026-10-16 A drew an AR-2 Darter at random from its list
  and sent it 5 km out to loiter at 500 m. Weapons removed.
- **Loiter:** 500 m AGL, inside MANPAD reach and above small arms.
- **Each poll (5 s):** reveals to the HQ group what its sensors
  (`getSensorTargets`) and crew have seen in the last 30 s, at 1.5, so HAL
  learns it (HAL counts what its HQ group knows, `HAC_fnc2.sqf:271`). The
  knowledge layer never reads the HQ group, and reads the UAV crew directly as a
  registered sensor group, so nothing is counted twice.
- **On station** (within 1500 m of its task): stamps a `uav` look of 1000 m
  around the task. The air picture accepts only `uav` looks as eyes on a
  destination; friendly presence still stamps objectives for the intelligence
  state.
- **Task, refreshed each assessment without a roll:** the plan objective if
  Unobserved, else an objective with leads only, else overwatch of the plan
  objective. The UAV follows a task that moves more than 300 m.
- **Declared end:** 15 minutes on task from first arrival, then it leaves and
  despawns. Not on station within 600 s: `BREAKOFF`, refunded.
- **Loss:** the recon lane stays blocked for a 300 s relaunch delay. The loss
  feeds AirPicture's side-aware loss counter.

### 9.3 Strike pass

- The jet flies a line through the aim point (bomb pass 250 m, carpet 400 m,
  guided 600 m above it). Unguided release is timed by ballistic fall time from
  where the bomb leaves (5 m under the jet) and the jet's speed, with no drag.
  Every bomb leaves with the jet's velocity and arcs forward like a real stick.
- **Line-up**, about 3 km out: the latest report is read, the uncertainty limit
  and danger close are checked, and the jet's line is pointed through the new
  aim. The aircraft is steered onto the target; bombs are never moved onto it.
- **Final check**, about 600 m before the first release: the report is read
  once more for timing along the line only. Whatever the jet could not fix by
  then is a physical miss, and more than 250 m off the line is a break-off.
- **Release** runs every frame in a mission event handler, outside the
  scheduler, so server load can no longer make a stick late. A bomb whose point
  the jet has already passed by more than 30 m is not dropped. Model: centred
  within 2 to 10 m from 50 down to 8 server FPS, every bomb in the footprint.
- **Impact log.** Each bomb's explosion is logged against where the no-drag
  model said it would land (drag and model error only) and against the pattern
  point it was meant for (that, plus lateness and line error), with release
  height, speed and how late it left. The bomb's ballistic config
  (`simulation`, `airFriction` and the rest) is logged at boot.
  `ITW_CLASH_SupportsStrikeReleaseBias` stays 0 until those logs have separated
  drag from timing. `ITW_CLASH_SupportsStrike_fnc_TestPass` flies a strike from
  the debug console at a chosen height, heading and speed, outside the economy,
  for controlled calibration runs.
- **Bomb pass:** four unguided bombs, scripted under the aircraft at release with
  its velocity (class tunable, `Bo_Mk82` for both sides).
- **Guided pass, with on-site scan:**
  1. Inbound with radar on. Once within 3 km, read the jet's own
     `getSensorTargets` and its crew's known targets for enemy ground vehicles
     inside the scan radius around the reported position. Scan radius = R
     projected to arrival, capped at 500 m.
  2. **Valid:** alive, a vehicle, inside the launch envelope (4), clear of
     danger close, not tasked to an ETB responder. Pick the nearest to the
     report.
  3. **Fire** two shots from the jet's own guided anti-armor weapon, read through
     the rack profile (`ITW_CLASH_RackProfile.sqf`) when it is loaded: a missile
     with a seeker other than air-to-air and the armour flag on the missile or
     its warhead, and the weapon that fires that magazine on that turret or
     pylon (Strike v3 keeps its own reader for when the profile is missing).
     `fireAtTarget`, and if that returns false, the weapon's missile spawned at
     the jet and given the target with `setMissileTarget`. That fallback is
     legitimate only because the jet acquired the target itself.
  4. **Launch envelope**, checked when a target is found and again at the
     instant of each shot: range between the missile's own lock distances
     (`missileLockMinDistance` and `missileLockMaxDistance`, 800 and 5000 m when
     its config has none), within 40 degrees of the nose, terrain line of sight.
     The scan ends once the report is inside minimum range.
  5. **Nothing valid** within a 20 s window, or before minimum range:
     `BREAKOFF`, egress, despawn, refund.
- **Carpet:** 21 bombs, Antistasi's layout centred on the aim point: 15 m
  apart along the line, in five lanes 40 m apart across it.
- **Every bomb:** released only while the aircraft is alive, and given the
  aircraft as its shooter (`setShotParents`) so kills are credited.

### 9.4 Drop run

- **Squads:** created by the drop executor straight after the pre-run check, on
  the ground at the aircraft's origin, through Impasse's unit factory
  (`ITW_AtkUnitToGroup`), protected until they are moved aboard. The template is the archetype of a living
  infantry squad of the side, so the drop matches what Impasse fields. As many
  squads as the cargo holds, capped (helicopter 2, C-130 3). They count against
  Impasse's live cap the moment they exist.
- **Reserved until hand-off:** the squads carry `ITW_CLASH_ReconstitutionTransit`,
  which every sweep (Impasse's infantry manager, FormationAdmission, the BLUFOR
  adoption loop, enemy classification) already treats as hands-off.
- **Drop zone:** dry open ground near the point. Taking a point, 250 m short of
  it on the approach, so the stick lands at the edge of the fight; holding, the
  point itself.
- **Helicopter:** its own routine; HALUnload is untouched. Arrives at 150 m and
  runs in at 50 m, one straight line through the zone to a waypoint 1 km past
  it. Release lead from `ITW_CLASH_HALUnload_fnc_StickLead`, flares from 1200 m
  through Thunder Run's countermeasure primitives.
- **Jump:** Impasse's own, `ITW_AtkUnloadAirplane` called with no crew group and
  no point, so it touches no waypoint and every man goes out through
  `ITW_AtkParachute` at once; then `doFollow`, as every other paradrop caller
  does.
- **C-130:** CARELESS with a `flyInHeightASL` floor at 250 m above the drop zone.
  Same jump.
- **Vehicle add-on:** a crewed light vehicle built at the moment of release with
  `ITW_AtkSpawnVeh` and dropped 80 m past the zone through `ITW_FncVehicleHalo`.
- **Abort before anyone jumps** (passed wide, never reached): the squads never
  touched the ground and are deleted, the aircraft egresses, and the money comes
  back.
- **Aircraft lost before the jump:** spent. Any man who lives through it is
  handed on like a landed squad.
- **Hand-off,** once every living man is out of the aircraft and his chute
  (bounded at 90 s), plus a 10 s settle:
  1. Clear the transit flag and the support stamp.
  2. Impasse's own group callback (`ITW_EnemyGroupCallback` or
     `ITW_AllyGroupCallback`), as the reconstitution hand-off does.
  3. Register with the side's commander through
     `ITW_CLASH_DualHAL_fnc_RegisterGroup` (reason `support-airborne`).
  4. One native HAL order, issued as HAL's own dispatcher issues it: capture on
     the objective when taking (`HQOrders.sqf:815-832`), defend at it when
     holding (the anchor's path). A registered squad that cannot be given the
     order is still HAL's, and HAL tasks it on its next pass.
  5. Registration refused: Impasse's own `ITW_AtkEngageInfantry`.
  6. The vehicle crew registers the same way once the vehicle is down, marked
     as a vehicle crew and tracked as an asset. HAL tasks its own vehicles, so
     it gets no order.

### 9.5 Provenance

`ITW_CLASH_SupportAsset` (the support id) goes on every support vehicle, crew
group and crew unit, and on the airborne squads until hand-off. Support crew
groups also carry `ITW_CLASH_ExcludeHAL` and `ITW_CLASH_VehicleCrewGroup`, which
the lifecycle reservation and FormationAdmission already honour, and
AttackRestore skips support groups.

## 10. Telemetry

Every line goes through `ITW_CLASH_DualHAL_fnc_Log`, which adds its own
`dual-hal-` prefix in the RPT. Prefixes after that: `supports-` for the core,
`supports-strike-`, `supports-uav-`, `supports-airborne-` for the executors,
`knowledge-` for the layer. Only decision-level events (admission, outcome,
releases, hand-offs, the UAV on station and ending, test outcomes) are spoken by
the loud debugger; the pool and ledger lines are too long for chat.

| Line | Content |
|---|---|
| `supports-pool` | Side, posture, plan objective; every candidate in stable order with family, flavor, objective, target key, class, status and weight; every exclusion with its reason (objective -1 for a gate that does not depend on one); draw value; pick; cash; the target objectives with reason, urgency and pressure; influence-cutoff crossings since the last assessment |
| `supports-admission` | Proposal, gate results, reservation or denial reason |
| `supports-state` | Each lifecycle transition |
| `supports-outcome` | Id, flavor, objective, reason, terminal state, detail, refunded or spent, price, cash after, seconds from reservation, refund clipped at the ceiling |
| `supports-egress` | Id, the corridor state of the chosen turn, run heading |
| `supports-strike-lined-up`, `-release-check` | How far the report moved at the 3 km line-up and the final check |
| `supports-strike-released`, `-guided-fired`, `-scan-empty`, `-effect` | What each pass did (bombs released and skipped, mean lateness in metres; shots, fallbacks, envelope refusal; why a scan ended), and how many of the target's entities died after it (log only) |
| `supports-strike-impact` | Per bomb: error against the no-drag model (along, across), error against its pattern point (along, across), release height, speed, lateness in metres |
| `supports-strike-impact-summary` | Per pass: the four mean errors |
| `supports-strike-ammo` | Boot: the bomb class's simulation, air friction, side air friction, max speed, thrust, thrust time, time to live |
| `supports-strike-test-started`, `-test-outcome` | A console test pass |
| `supports-uav-launched`, `-on-station`, `-retasked`, `-ended` | The UAV's life: looks stamped, peak contacts in one sweep, retasks |
| `supports-airborne-boarded`, `-released`, `-handoff`, `-vehicle-*` | The drop: squads and men, release geometry, who took each squad and which order it got |
| `supports-ledger` | Periodic: cash, cap, income, lanes |
| `knowledge-objective` | Periodic per objective: intelligence state, observed, fixed, leads, oldest report |
| `knowledge-truth` | Diagnostic: reported against actual error, by class |
| `knowledge-truth-speed` | Diagnostic, per bucket: samples, moving, outside while moving, outside while settled, implied speed spread, implied speed spread while moving, real speed spread (each spread min, median, p90, max) |
| `knowledge-clock-anomaly` | Rejected reports off the clock (not never-seen): count, samples kept, in the past and in the future, the raw `lastSeen` spread, its spread against `time`, `serverTime` and `diag_tickTime`, how many were unit reports, how many had a valid groupmate report, and the three clocks now |
| `knowledge-never-seen` | Reports rejected as known of but never seen: count, groupmates checked, groupmates who had seen it |
| `colossus-no-push-candidate` | The side holds every active objective: no push this assessment |
| `colossus-concentrate`, `-concentrate-declined` | Said on change: objective and verdict, or the decline reason (and unanchored objectives); last field is how often the previous answer repeated |
| `supports-ready`, `knowledge-ready` | Boot: version, dry run, every switch |

## 11. Rollout

- **Supports v3: everything live** (2026-10-16). `ITW_CLASH_SupportsDryRun`
  defaults to false, and every flavor's switch to true: UAV, bomb pass, guided
  pass, carpet, helicopter airborne, C-130 airborne and the vehicle drop.
- Shadow mode is one variable away: `ITW_CLASH_SupportsDryRun = true` before
  the core loads decides, admits and logs exactly as live, and spawns nothing.
  Each flavor keeps its own switch; with one off nothing on its path runs.
- The staged order (dry run, then UAV and strikes, then helicopter airborne,
  then C-130 and vehicle drop) was skipped by decision. Only the dry run has
  run in engine: on 2026-10-16 it admitted one UAV per side and held each lane
  for its nominal 15 minutes. The first live strikes and drops are their own
  first tests: read `supports-outcome`, the executors' lines and section 13.

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
7. Bomb drag: read `supports-strike-ammo` and the impact lines from test passes
   at two or three heights and speeds, on a quiet server and a loaded one. The
   model error isolates drag; the pattern error adds timing and line error. Fit
   `ITW_CLASH_SupportsStrikeReleaseBias` only after that split.
8. Whether a bomb created 5 m under the jet ever strikes the airframe; whether
   `netId` returns "0:0" in single player (contact keys would collide); whether a
   laser-guided bomb is counted as a guided weapon.
9. How often an unguided pass on vehicles survives the uncertainty limit. With
   vehicles at 8 m/s and about 36 s from spawn to release, a vehicle's R is
   already near 300 m at a fresh report: in practice a bomb pass or carpet on
   vehicles needs the target under continuous observation, and the guided pass
   (exempt) carries vehicle strikes.
10. `moveInCargo` into an aircraft already in flight, the UAV AI on a `LOITER`
   waypoint, and `ITW_AtkUnloadAirplane` called with no crew group.
11. The `Explode` projectile event handler on the game version in use (the impact
   log needs 2.10 or later), and `addMissionEventHandler` with arguments.
12. Movement allowances from `knowledge-truth-speed`: set each class's allowance
   near the p90 of real speed while moving, and check that the settled outside
   count is near zero (it measures the engine's own error).
13. Which clock `lastSeen` uses, from `knowledge-clock-anomaly`: if rejected
   reports line up with `serverTime` or `diag_tickTime`, the rejection is a clock
   mismatch, not bad data.

## 14. Tunables

All placeholders.

| Setting | Value |
|---|---|
| Knowledge poll | 10 s |
| Movement allowance | Statics 0, infantry 2, vehicles 8 m/s |
| Uncertainty floor | 5 m |
| Diagnostic samples | Clock 300; truth 400 per bucket, from 10 s old |
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
| Strike heights | Bomb pass 250 m, carpet 400 m, guided 600 m |
| Bomb pass payload | 4 bombs, 15 m apart |
| Guided pass payload | 2 shots |
| Carpet | 21 bombs, 15 m along, lanes 40 m apart |
| Strike cross limit | 250 m off the line at release |
| UAV on station, look, retask | 1500 m, 1000 m, 300 m; transit timeout 600 s |
| Helicopter heights | Arrives at 150 m, drops from 50 m |
| C-130 drop height | 250 m |
| Drop zone offset when taking | 250 m short on the approach |
| Airborne cross limit | 350 m |
| Squads per drop | Helicopter 2, C-130 3 |
| Airborne far-force threshold | 1500 m |
| Hand-off settle | 10 s, after up to 90 s waiting for the squad to be on its feet |
| Presence floor (stale contact counts toward intel) | 0.1 |
| Influence radius, edge weight | 2000 m, 0.3 |
| Threat proximity (to committed formations) | 1000 m |
| Spawn map margin | 500 m |
| Egress separation, turn | 2000 m, 2000 m at 120 degrees |
| Strike line-up, final check | 3000 m out; 600 m before the first release |
| Release skip distance, drop offset, bias | 30 m, 5 m, 0 m |
| Guided envelope fallbacks, cone | 800 to 5000 m, 40 degrees off the nose |

## 15. Open decisions

From the audit, waiting on a design call; nothing in the build presumes them:

- **Carpet tempo.** In the economy model the carpet almost never happens (0 an
  hour in the dry run, 0.03 live): its price is the wallet's ceiling, and the
  cheaper flavors spend the money first. A bounded savings goal (expires,
  cancels when its target stops qualifying, never blocks a held point in
  trouble) fixes it, once the wanted tempo is set.
- **Carpet width.** Five lanes 160 m wide from one aircraft is the one place
  bombs still appear well off the airframe (up to 80 m). Keep it, narrow it to a
  stick one jet could lay, or fly two or three bombers.
- **Parked vehicles.** At 8 m/s a vehicle never passes the 300 m limit for a bomb
  pass or carpet; guided passes carry all vehicle strikes. A lower allowance for
  vehicles that have not moved for 60 s would make them bombable.

## 16. Implementation

| File | Owns |
|---|---|
| `ITW_CLASH_Knowledge.sqf` (v4) | Reports, uncertainty, statuses, looks, intelligence state, the truth diagnostic, clock, never-seen and speed instrumentation |
| `ITW_CLASH_Colossus.sqf` (v7) | The one call to `ITW_CLASH_Supports_fnc_Assess` after its order; reported strength beside live; a push only for ground not held; concentration gated on anchored holdings |
| `ITW_CLASH_RackProfile.sqf` | What a vehicle can fire, read from its live rack; the guided pass reads its weapon through it (see `CLASH_HALAirEmployment_Model.md`) |
| `ITW_CLASH_Supports.sqf` (v3) | Registry, ledger, pool, pick, admission, lifecycle, settlement, shared flight code; live by default |
| `ITW_CLASH_SupportsStrike.sqf` (v3) | Bomb pass, guided pass with the on-site scan, carpet |
| `ITW_CLASH_SupportsUAV.sqf` | The recon UAV |
| `ITW_CLASH_SupportsAirborne.sqf` | Helicopter and C-130 drops, the vehicle add-on, the hand-off |
| `ITW_CLASH_AirPicture.sqf` | `Observed` also accepts a recent `uav` look |
| `ITW_CLASH_DebugPreflight.sqf` | Lists the five modules |
| `ITW_CLASH_AttackRestore.sqf` | Skips groups carrying `ITW_CLASH_SupportAsset` |

Boot (`init.sqf`): the rack profile, then Knowledge, then COLOSSUS, then the
core and its three executors; the core needs Knowledge and COLOSSUS, and an executor that is
missing revokes its supports with `NO_EXECUTOR`. Static contracts are pinned in
`tests/test_commander_supports.py`. The pure math (pick, overlap, presence,
falloff, spawn point, release timing, economy) is cross-checked in a Python
model. The dry run has run in engine (2026-10-16); no live support has yet. Section 13 is the list to verify.
