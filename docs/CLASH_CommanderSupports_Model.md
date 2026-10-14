# C.L.A.S.H. Commander Supports Model

Status: **design, not built.** Phase 0 (per-side air-loss closures, hard-kill
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
| Supports admission | Gates, ledger, lanes, reservations | Chooses objectives or targets |
| Support executors | Spawn, flight, release, egress and despawn of support assets | Hands a support asset to HAL |
| Impasse | Spawning the airborne squad; the unit cap it counts against | |
| HAL | The airborne squad after landing, through one native order | Flies a support asset |
| Checkbook, ETB | HAL's procurement, unchanged | Spends support money |

### 2.2 Kill criterion

COLOSSUS's header is amended in the build to read:

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
2. No support asset enters a HAL pool or `RydHQ_Included`.
3. Every support entity carries `ITW_CLASH_SupportAsset` from the moment it is
   created.
4. No support acts on a position nobody reported. Supports read reported
   positions, never the live position of a known object.
5. A roll is a proposal. Money, lane and headcount are reserved together or not
   at all, and every reservation ends in a launch or a release.
6. Revoked before anything spawns: refunded. Abandoned after spawn: spent.
7. Danger close is checked at release, not only at request.
8. No on-screen warning of any support, for either side. Tells are in the world.
9. Weights, prices, cooldowns and income are identical for both sides.
10. With a support switched off, every existing code path it touches behaves
    exactly as before.
11. Every assessment logs its pool, exclusions, weights, draw and result.
12. HAL source is never edited.

## 4. Knowledge layer

Built first; every support decision reads from it.

### 4.1 Sensors

All feed one picture per side:

- HAL groups and players: what they see enters HAL's known-enemy list.
- HAL's own recon.
- The recon UAV: its sensors and crew reveal into the HQ group (section 9.2).
- Counter-battery fixes, as leads only.

There is no "gunfire heard" sensor. Squads see units and report them.

### 4.2 Per-contact record

For each known enemy entity:

- reported position;
- time last seen;
- error margin;

all read from `targetKnowledge` of the groups that actually saw it.

HAL's `Rev.sqf` reveals known enemies to the HQ group, which may refresh the HQ's
own timestamps. The layer therefore keeps its own first-seen and last-seen per
contact, taken from the observing groups, and does not trust the HQ group's
times. Moving: a contact whose reported position changed more than 30 m between
reports.

### 4.3 Grades

| Grade | Rule | Used by |
|---|---|---|
| Contact | Seen within 60 s, error within 50 m | Every support |
| Lead | Seen within 600 s, or error within 300 m, or a counter-battery fix | Carpet, UAV tasking |
| Expired | Anything older or vaguer | No support (HAL may still know it) |

### 4.4 Objective intelligence state

Measured inside `ITW_CLASH_ColossusObjectiveRadius`, the radius COLOSSUS already
counts strength in.

| State | Meaning |
|---|---|
| Unobserved | No contact or lead inside, and nobody has looked recently |
| Recent contact | At least one contact inside |
| Stale contact | Leads only |
| Recently cleared | Looked at within 300 s and nothing found |

A "look" is stamped per objective by friendly units within
`ITW_CLASH_AirPictureObservedRadius` and by the UAV's sensor footprint.
`ITW_CLASH_AirPicture_fnc_Observed` reads the stamp, so a place the UAV looked at
and found empty counts as observed.

### 4.5 COLOSSUS moves onto the layer

- `EnemyStrength` counts contacts and leads at their reported positions instead
  of `getPosATL` on the live object.
- Each objective's picture carries its intelligence state alongside the verdict.
- The recommendation treats Unobserved as unknown, not soft, so unscouted
  objectives stop ranking as the easiest.

This changes COLOSSUS's behaviour on its own, so it ships behind
`ITW_CLASH_ColossusReportedPositions` (default true, false restores the live
reads).

## 5. The menu

### 5.1 Verbs and flavors

| Verb | Flavor | Routine | Knowledge needed | Default |
|---|---|---|---|---|
| Look | Recon UAV | Orbit | None | On |
| Hit a point | Bomb pass | Strike pass | Contact | On |
| Hit a point | Guided pass | Strike pass | Contact on a lockable target, line of sight at release | On |
| Hit an area | Carpet | Strike pass (bomber) | Lead or contact | On |
| Land | Helicopter airborne | Drop run | Drop zone Recent contact or Recently cleared | Off |
| Land | C-130 troops | Drop run | As above | Off |
| Land | Vehicle drop (add-on to C-130) | Drop run | As above | Off |

Three delivery routines carry seven flavors. A new flavor is a registry row plus,
where needed, a payload function.

### 5.2 Registry row

Each flavor declares: verb, routine, knowledge grade, eligible target classes,
the faction aircraft that can fly it, price, flavor cooldown, its weights
(section 6.3) and its enable switch.

### 5.3 Deferred

- Smoke screen (a flavor air defence cannot stop).
- UAV laser designation for laser-guided bombs.
- An outer shaping ring for overwatch positions and reinforcements.
- Strikes on formations away from the plan objective.
- Players flying or marking supports through the employment system.

## 6. Decision: the weighted pool

### 6.1 When

Once per COLOSSUS assessment per side, after the plan and order are committed.
One roll, at most one proposal.

### 6.2 The pool

1. **Targets.** Contacts and leads within 150 m of each other are clustered. A
   cluster's worth is the sum of COLOSSUS's own weights (infantry 1, vehicle 1.5,
   armor 3, static 0.5). Its class for the weight table is its dominant
   composition.
2. **Where.** Clusters inside the objective radius of:
   - the plan objective, when posture is PUSH;
   - any held objective under pressure, in any posture.
3. **Candidates.**
   - One strike candidate per eligible flavor and cluster.
   - The UAV launch, when the recon lane is free.
   - One airborne candidate per eligible objective.
   - Save.
4. **Gates first.** Every hard gate (section 7.1) runs before the roll. Excluded
   candidates are logged with their reason and never enter the pool.

### 6.3 Strike weights

Coarse 0 to 3. Zero means physically impossible, nothing else.

| Target class | Bomb pass | Guided pass | Carpet |
|---|---|---|---|
| Armor or vehicles, parked | 3 | 3 | 1, or 2 when three or more are clustered |
| Armor or vehicles, moving | 1 | 3 | 1 |
| Statics, compound, dug-in infantry | 3 | 1 | 2 |
| Infantry mass in the open | 2 | 0 (nothing to lock) | 3 |
| Lead only | 0 (needs a contact) | 0 | 2 |

### 6.4 Family weights

| Candidate | Weight |
|---|---|
| UAV launch | 3 if the plan objective is Unobserved; 1 if it or a held point is Stale contact; 0.5 otherwise |
| Airborne | Base 1. +1 if the push is short by more than the best strike could remove. +1 if our nearest available ground force is more than 1500 m out. 3 for a held point under pressure with no anchor |
| Save | 3 with the bank below a third of its cap, 2 below two thirds, 1 below full, 0.5 at the cap |

Modifiers:

- **Urgency.** Candidates at a held point are multiplied by 1 to 3. The more our
  ratio there has fallen through CONTESTED, the higher the multiplier, with the
  maximum when the point has no anchor.
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
| Switch | Flavor enabled. In dry run, admission logs the full result and stops here | `DISABLED`, `DRY_RUN` |
| Knowledge | The flavor's grade, rechecked at admission | `NO_CONTACT`, `LEAD_NOT_ENOUGH` |
| Objective | Plan objective under PUSH, or a held point under pressure. Not capture-frozen (`ITW_CLASH_fnc_ObjectiveFrozen`) | `NOT_PLAN_OBJECTIVE`, `CONSOLIDATING`, `OBJECTIVE_FROZEN` |
| Value | Cluster worth at least 2 | `BELOW_FLOOR` |
| Danger close | Footprint plus 300 m clear of every living friendly: on foot, in vehicles, in aircraft below release height, under canopy. 500 m for players | `DANGER_CLOSE` |
| Corridor | UAV and helicopters use the default fighter rule (`HARD_KILL`); jets use `ANY_AA_MISSILE`. `AIR_DENIED` denies | `AIR_DENIED` |
| ETB overlap | Target not already tasked to an ETB responder (`ITW_CLASH_HALThreatCoverage_fnc_TaskedAgainst`) | `ETB_ANSWERING` |
| Lane | Recon lane: one UAV. Commitment lane: one strike or drop in flight | `LANE_BUSY` |
| Cooldown | Per flavor and per objective | `COOLDOWN` |
| Budget | Price affordable | `INSUFFICIENT_FUNDS` |
| Capability | The faction has the aircraft: UAV class, a plane for strikes, a guided anti-armor weapon on that plane, a transport helicopter, a transport plane | `NO_AIRCRAFT`, `NO_GUIDED_WEAPON` |
| Airfield | Fixed-wing flavors need an owned airfield (`ITW_ObjOwnedAirports`) | `NO_AIRFIELD` |
| Headcount | Airborne only: Impasse's unit cap has room for the squad | `NO_HEADROOM` |
| Target | Rechecked at the end of the delay and at release | `TARGET_GONE` |

### 7.2 Lanes

Two lanes per side, one shared budget:

- **Recon lane:** one UAV on station or relaunching.
- **Commitment lane:** one strike or drop from reservation until done.

A loitering UAV never blocks strikes or drops.

### 7.3 The transaction

1. COLOSSUS's roll produces a proposal.
2. Admission reruns every gate.
3. In one unscheduled block, so no other script can interleave: reserve the
   price, take the lane slot, start the cooldowns, and for airborne reserve the
   squad's headcount.
4. Launch.
5. If the spawn fails or the reservation times out before anything exists,
   release everything and refund.

This mirrors the ETB's reservations and escrow, on a separate ledger. HAL and
COLOSSUS never share a wallet; the shared resources are Impasse headcount
(reserved in step 3) and targets (the ETB overlap gate).

### 7.4 Lifecycle

`PROPOSED` then `RESERVED` then `DELAY` then `INBOUND` then `RELEASED` (or
`DROPPED`) then `EGRESS` then `DONE`.

Terminal alternatives: `REVOKED` (before anything spawned; refunded) and
`ABANDONED` (after; spent).

The setup delay is varied per request and never announced.

## 8. Budget

- **Ledger:** one per side, separate from Impasse tickets, the Checkbook and the
  ETB.
- **Income:** flat over time, the ETB's formula family with its own scale,
  identical for both sides. Nothing is earned from kills or captures.
- **Cap:** one big support (the price of a carpet or a heavy drop, whichever is
  higher). Income stops at the cap.
- **Prices:** set from the intended cadence. Price = income per minute times the
  intended interval:

  | Flavor | Intended cadence |
  |---|---|
  | UAV | Every few minutes |
  | Bomb pass, guided pass | A few per hour |
  | Carpet | Once or twice an hour |
  | Airborne | About once per zone |

- **Holding discount:** supports at a held point cost 0.75 of the price.
- **Persistence:** reset on load. Nothing is written to `profileNamespace`.

## 9. Execution

### 9.1 Common flight rules

- Spawn in flight (`setPosATL`, then `setVelocityModelSpace`) on the line from
  the side's origin to the task.
- CARELESS, autocombat off, combat mode BLUE until release, one far waypoint,
  `flyInHeight`, and `flyInHeightASL` as a floor for fixed-wing.
- Air-to-air missiles removed from strike aircraft, so a support jet never reads
  as a fighter to the other side and never engages aircraft.
- After the task: flares, egress, despawn at distance or by timeout.

### 9.2 Orbit: recon UAV

- **Class:** `va_eUavClasses` or `va_pUavClasses`, falling back to the side's
  vanilla UAV.
- **Launch:** from the rear base. Loiters at an altitude inside MANPAD reach and
  above small-arms reach (500 m AGL).
- **Each poll:** reveals into the HQ group what its sensors (`getSensorTargets`)
  and crew see, and stamps a look on every objective in its sensor footprint.
- **Task, refreshed each assessment without a roll:** the plan objective if
  Unobserved, else objectives with leads only, else overwatch of the plan
  objective.
- **Declared end:** 15 minutes of loiter, then it leaves and despawns. Launching
  again is a new pool candidate.
- **Loss:** the recon lane stays blocked for a 300 s relaunch delay. The loss
  feeds AirPicture's side-aware loss counter. It never reveals its killer.

### 9.3 Strike pass

- The jet flies a line through the target from its airfield's direction.
  Release is timed by distance over speed, aimed at the contact's latest
  reported position.
- **Bomb pass:** four unguided bombs, scripted under the aircraft at release with
  its velocity (class tunable, `Bo_Mk82` for both sides).
- **Guided pass:** two shots from the jet's own guided anti-armor weapon.
  1. Reveal the target to the crew, then `fireAtTarget`.
  2. If that returns false, spawn the weapon's missile at the pylon and
     `setMissileTarget`.
  3. A terrain line-of-sight check at release. Blocked: abort, spent.
- **Carpet:** 21 bombs in a 300 by 160 m pattern laid relative to the target,
  released 0.35 s apart along the bomber's line.
- **Every bomb:** released only while the aircraft is alive, and given the
  aircraft as its shooter (`setShotParents`) so kills are credited.

### 9.4 Drop run

- **Squad:** requested from Impasse's spawner at the reconstitution spawn site,
  counted against Impasse's unit cap. It carries the transit flag from spawn, so
  Impasse's infantry manager (`ITW_AtkGetInfantryGroups`) never adopts it, and is
  moved into the support aircraft's cargo.
- **Helicopter:** flies the stay-low run-in through a new entry point into
  `ITW_CLASH_HALUnload` that takes the same inputs a HAL lift provides. The HAL
  lift path is unchanged. Release at the hot-drop height (45 m). Jumpers exit
  through `ITW_AtkParachute` at about 11 m spacing. The aircraft despawns after
  egress.
- **C-130:** CARELESS with a `flyInHeightASL` floor. Drop height to be set in
  engine. Same jumper exit.
- **Vehicle add-on:** released after the troops. Flat drop zone search, damage
  off during descent and briefly after touchdown, upright correction on landing
  (`ITW_FncVehicleHalo` as the reference).
- **Hand-off:** once the squad leader is on the ground plus a settle delay:
  1. Clear the transit flag.
  2. Hand the squad to its commander through the reconstitution spawn hand-off
     (`ITW_CLASH_Reconstitution_fnc_SpawnHandoff`); FormationAdmission's minimum
     size applies.
  3. Give one native HAL order: capture on the plan objective, defend on a held
     point.

### 9.5 Provenance

`ITW_CLASH_SupportAsset` and the support id go on every support vehicle, crew
group and crew unit, and on the airborne squad until hand-off. Before each live
phase, every sweep over `allGroups` or vehicles is audited for adopting support
entities: Impasse's infantry manager, the service lifecycle, crew remnant
cleanup, vehicle migration and field hardening.

## 10. Telemetry

Prefixes: `supports-core`, `supports-uav`, `supports-strike`,
`supports-airborne`, `supports-knowledge`.

| Line | Content |
|---|---|
| `supports-pool` | Side, posture, plan objective; every candidate in stable order with family, flavor, objective, target key, class, grade and weight; every exclusion with its reason; draw value; pick |
| `supports-admission` | Proposal, gate results, reservation or denial reason |
| `supports-state` | Each lifecycle transition |
| `supports-outcome` | Worth destroyed, aircraft lost, squad handed off, refunded or spent |
| `supports-ledger` | Periodic: cash, cap, income, reservations |
| `supports-knowledge` | Periodic per objective: intelligence state, contacts, leads, oldest report |
| `supports-ready` | Boot: version, dry run, every switch |

## 11. Rollout

- `ITW_CLASH_SupportsDryRun` starts true: everything decides, admits and logs,
  nothing spawns.
- Each flavor has its own switch. Airborne starts off, and with it off the
  Impasse spawner and the run-in behave exactly as before.
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

1. `targetKnowledge` from observing groups against the HQ group, and whether
   `reveal` refreshes last-seen.
2. `setMissileTarget` on the game version in use.
3. What the UAV's `getSensorTargets` actually detects at orbit altitude over
   Altis terrain.
4. How long Impasse takes to spawn an on-demand squad.
5. A C-130 drop height that clears terrain and survives.
6. Whether `EntityKilled` fires for the UAV's AI crew, so its loss is attributed
   to a side.

## 14. Tunables

All placeholders.

| Setting | Value |
|---|---|
| Contact age, error | 60 s, 50 m |
| Lead age, error | 600 s, 300 m |
| Moving threshold | 30 m between reports |
| Recently cleared window | 300 s |
| Cluster radius | 150 m |
| Value floor | 2 |
| Danger close margin | 300 m, 500 m for players |
| Corridor HOT or CONTESTED multiplier | 0.5 |
| Holding discount | 0.75 |
| UAV altitude, loiter, relaunch | 500 m AGL, 15 min, 300 s |
| Bomb pass payload | 4 bombs |
| Guided pass payload | 2 shots |
| Carpet | 21 bombs, 300 by 160 m, 0.35 s |
| Helicopter drop height | 45 m |
| Airborne far-force threshold | 1500 m |
