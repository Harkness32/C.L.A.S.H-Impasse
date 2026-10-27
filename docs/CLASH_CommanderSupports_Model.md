# C.L.A.S.H. Commander Supports Model

Status: **built; live by default since supports v3; v4 lets the bomb pass take lone targets and acquire on site; v5 doubles the strike tempo and fixes what the first live strikes showed; v6 gives the guided missile its own danger margin, and the recon UAV (v4) reports everything in its footprint that no building covers; v7 splits the drops into their own families and wallet, makes vehicle delivery its own support carried by a Blackfish, adds bite-back waves for points being lost, and console tests for all of it; v8 fixes what the first console tests showed (the carrier, what is delivered, the troop plane, passengers leaving early); strike v6 and a v8 hotfix (2026-10-18) put the commanders back in the air and keep bombs out of the guided pass.** Phase 0 (per-side air-loss closures, hard-kill
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
- The UAV's footprint (knowledge v6, UAV v4): every enemy under it that no
  building covers, as a UAV report (9.2).
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

Knowledge v5, from 36 minutes of contact on 2026-10-16 (05:11 session):

| Class | Allowance before | Broke it while moving | True speed p90 | Allowance now |
|---|---|---|---|---|
| Infantry | 2 m/s | 10 of 53 (19%) | 3.9 to 5.1 m/s | 4 m/s |
| Armour | 8 m/s (the vehicle value) | 81 of 174 (47%) | to 29.5 m/s (wheeled AFVs on roads) | 15 m/s, its own |
| Vehicles | 8 m/s | 10 of 152 (7%) | to 15 m/s | 8 m/s |
| Statics | 0 | 0 of 91 | 0 | 0 |

- The cost: a moving armoured contact's envelope reaches the 300 m strike limit
  in about 20 s, so bomb passes and carpets on armour need very fresh reports;
  the guided pass, which acquires on site, is exempt.
- **A groupmate's sighting speaks for the group.** 3411 reports were rejected
  as never-seen in that run, and in 626 of the 3346 checked (19%) another man
  of the same group had seen the target himself. When the leader never saw it,
  the group's report is now that groupmate's most recent sighting. Still one
  report per group, never merged. `knowledge-never-seen` is now [leader never
  saw it, groups checked, groupmate sightings used].

Knowledge v6, from the second 2026-10-17 run: **the UAV's footprint is a
report.** Through the engine's sensors and its crew, no UAV at 2000 m ever had
more than 2 contacts at once in 12 sorties. The UAV now looks at its footprint
itself (9.2) and leaves each sighting in `ITW_CLASH_KnowledgeUAVSightings`: the
entity, where the camera saw it, when, and a 10 m error. Each update makes those
entities candidates and weighs the UAV's report against every observer's on the
same target by the same rule (error plus allowance times age, smallest now
wins); nothing is merged, and the record's observer reads `uav:<support id>`.
A UAV report is never refreshed on its own: it ages from the look, and a target
that leaves the footprint keeps only what was seen of it then. Stale or dead
entries are dropped where they are read. The position is read once, at the
look, as a strike jet's own sensor track is: the camera's measurement, not a
standing view of the truth.

### 4.3 Uncertainty

> R = E + v × (age + time ahead)

- **E:** the report's position error.
- **v:** a conservative movement allowance by class, from the truth diagnostic
  (v5): statics 0 m/s, infantry 4 m/s, ground vehicles 8 m/s, armour 15 m/s.
  Stationary now is not stationary later; only real statics get zero.
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
| Land | Helicopter airborne | Drop run | Drop zone Recent contact or Recently cleared | On |
| Land | Plane troops | Drop run | As above | On |
| Deliver | Vehicle delivery (v7: its own support, carried inside a Blackfish) | Delivery run | As above | On |

Three delivery routines carry seven flavors, in three families since v7: strikes
and the UAV; paradrops; vehicle delivery (6.7). A new flavor is a registry row
plus, where needed, a payload function.

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
(`TOO_UNCERTAIN`). The bomb pass and the guided pass are exempt
(`ITW_CLASH_SupportsAcquireFlavors`, v4): their jets acquire the target on site
(9.3), and R only sizes the scan. The bomb pass's fallback onto the report, when
it acquires nothing, is still held to the 300 m limit at release. Carpet is not
exempt.

### 6.4 Family weights

| Candidate | Weight |
|---|---|
| UAV launch | 3 if the plan objective is Unobserved or Stale contact (uncertainty is blocking a decision there); 1 for another objective with Stale contact; 0.5 otherwise |
| Airborne | Base 1. +1 if the push is short by more than the best strike could remove. +1 if our nearest available ground force is more than 1500 m out. 3 for a held point under pressure with no anchor |
| Save | 3 with the bank below a third of its cap, 2 below two thirds, 1 below full, 0.5 at the cap, times 0.5 since v5 (`ITW_CLASH_SupportsSaveScale`) |

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

### 6.7 Three families, three picks (v7)

Hark, 2026-10-17: "I don't want the commander to have to pick between the two."
No drop had ever been bought: the helicopter drop cost 36, the C-130 with its
vehicle add-on the whole 90 cap, and both shared the bank, the pick and the
commitment lane with the strikes, which spent the money first.

Each assessment now makes up to three picks, each with its own SAVE:

| Family | Flavors | Lane | Wallet | Pool line |
|---|---|---|---|---|
| Strikes and the UAV | UAV, bomb, guided, carpet | RECON, COMMIT | Main bank | `supports-pool` |
| Paradrops | Helicopter, plane | DROP | Drop wallet | `supports-drop-pool` |
| Vehicle delivery | Vehicle drop | VEHICLE | Drop wallet | `supports-vehicle-pool` |

A strike never waits on a drop, and a paradrop never on a vehicle. The two drop
families share the drop wallet, which holds one paradrop and one vehicle at its
cap, so they compete only for its money, never in a roll. A drop pool with
nothing offered and nothing refused is not logged.

### 6.8 Bite-back (v7)

Hark: "when a point he owns is threatened or getting capped, he has a small
budget to send paradrop and vehicle drop waves." After the three picks, each
point the side holds (and that is not capture-frozen) is read for why it wants
a wave:

| Why | Rule | Rank |
|---|---|---|
| `enemy-flag-up` | The enemy's flag is going up on a point still counted as ours (Impasse flips the flag before it flips the ownership) | 5 + the enemy flag's height |
| `flag-down` | Our flag is below half-mast (`FlagFloor`, 0.5) and not rising (falling, stuck, or the first look) | 5 − our flag's height |

The point nearest to falling ranks first, and any enemy flag outranks any of
ours. The flag is Impasse's own (`ITW_FlagIsPlayer`, `ITW_FlagPhase`), the bar
every player sees on screen, so reading it is no omniscience. A rising flag
(the side retaking it) wakes nothing.

v9 (Hark, 2026-10-27): bite-back is the reflex and COLOSSUS the judgment. Until
v8 a wave also went for a point whose flag had merely dipped (`flag-falling`),
or whose flag was up but which was under pressure with nobody anchoring it
(`unanchored`) or with its defenders outnumbered (`outnumbered`). Pressure with
the flag still up now belongs to COLOSSUS's HOLD picks, and bite-back
answers only a point that is actually going. Half-mast rather than the bottom
of the flag, because a wave needs two to four minutes to land: at default
capture speed, against fifteen or more attackers, a flag at half-mast has
about four minutes left and a bare one about two and a half.

The most urgent point gets one wave, if all of these hold, else it says once
why not (`supports-biteback-held`): the pot holds a wave; both wave lanes are
free; the point was not answered in the last 20 minutes; it is not Impasse's
defend-phase point while the defend phase runs (Impasse's own counterattack;
the two do not stack).

A wave is a helicopter drop of two squads (each cut so both fit the aircraft)
and one vehicle delivery, both to hold the point, out after a 15 to 45 s
scramble, in lanes of their own (BITE_DROP, BITE_VEHICLE). The pot counts waves:
it holds one, starts full and earns one back in 20 minutes. A wave costs one,
split between the parts that go; a part the side cannot fly stays home and costs
nothing, and the refund rules are the drops' own. Headroom is checked for the
whole wave.

### 6.9 JTAC (v10)

Hark, 2026-10-27: COLOSSUS is the supreme commander; a JTAC is a special forces
team calling a strike on what it sees itself. The third decider beside
COLOSSUS's picks and bite-back, in its own file (`ITW_CLASH_SupportsJTAC.sqf`),
polling every 10 s per side:

- bomb and guided only; it never generates or directs forces;
- one call per side every 10 minutes (the ledger's `jtac` cooldown), started on
  admission and read before any work;
- its own lane (`JTAC`), the `FREE` wallet, no objective: no COLOSSUS cooldown
  is read or started, and nor is the per-objective one;
- a controller is a team on `RydHQ_SpecForG`, on foot, not withdrawing, settled
  60 s; it must itself have seen a member of the cluster within 30 s, within
  2 km, with a line of sight; the pre-run check asks again (`NO_SIGHT`);
- the strike pipeline's own gates (class weights, `NO_CONTACT`, the acquiring
  floor, `ETB_ANSWERING`, `DANGER_CLOSE`, `AIR_DENIED`), and the best option
  wins outright by class weight × worth × corridor;
- danger close at one margin of its own, 150 m past the footprint for every
  flavor and every friendly, players included
  (`ITW_CLASH_SupportsDangerMarginJTAC`), at the call, the pre-run check and
  every check in the executor.

Logs: `supports-jtac-call` (the call, the team and its range, the cluster) and
`supports-jtac-held` (when it could not call, counted by reason, said on
change). The design and what a run should answer are in
`docs/CLASH_SOFEmployment_Model.md` §5 and §6.

## 7. Admission and commitment

### 7.1 Hard gates

| Gate | Rule | Denial |
|---|---|---|
| Switch | Flavor enabled | `DISABLED` |
| Knowledge | The flavor's statuses, rechecked at admission | `NO_CONTACT`, `TOO_UNCERTAIN` |
| Objective | Plan objective under PUSH, or a held point under pressure. Not capture-frozen (`ITW_CLASH_fnc_ObjectiveFrozen`). Any other objective is simply not a candidate | `CONSOLIDATING`, `OBJECTIVE_FROZEN` |
| Value | Cluster worth at least 2; the bomb and guided passes 1.5 (`ITW_CLASH_SupportsValueFloorAcquire`; v4 the bomb, v5 the guided pass too: a lone vehicle, a lone tank or two riflemen, and a static once its gunner is tracked too; never one rifleman). Carpet also needs three contacts or more | `BELOW_FLOOR`, `NOT_CLUSTERED` |
| Danger close | Footprint plus a margin clear of every living friendly: on foot, in vehicles, in aircraft below 300 m, under canopy. The bomb and guided passes 150 m, players included (v10; were 300/500 and 100/200); the carpet 300 m, 500 m for players; a JTAC's call 150 m. Each denial logs the friendly that caused it (`supports-danger-close`) | `DANGER_CLOSE` |
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

Six lanes per side (v7; two before):

- **Recon lane:** one UAV on station or relaunching.
- **Commitment lane:** one strike from reservation until done.
- **Drop lane:** one paradrop (v7).
- **Vehicle lane:** one vehicle delivery (v7).
- **Bite-back lanes:** a wave's paradrop and its vehicle (v7).

A loitering UAV never blocks strikes or drops; since v7 no family blocks
another. A console test holds a lane of its own (`TEST-...`) and blocks nothing.

### 7.3 The transaction

1. COLOSSUS's roll produces a proposal.
2. Admission reruns every gate.
3. In one unscheduled block, so no other script can interleave: recheck the
   money and the lane, reserve the price, take the lane slot, start the
   cooldowns.
4. Setup delay. Nothing exists yet, so cancelling costs nothing.
5. **Pre-run check**, before anything spawns: knowledge recomputed with the real
   age, the hard limit, danger close, the corridor, and for airborne the
   headcount. Failing any revokes and refunds. The bomb and guided passes skip
   the hard limit and go while the target is still believed to exist, even if
   its position has gone stale (LOST): they look for it themselves (v4). Before
   v4 a vehicle unseen for about 37 s went LOST during the setup delay and the
   strike was revoked before it spawned.
6. Spawn and fly.
7. **Release check:** the latest report, danger close, and for the bomb and
   guided passes the on-site scan. Failing breaks off and, with the aircraft
   alive, refunds.

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
- **Cap:** the price of the most expensive enabled flavor that spends from the
  bank. Income stops at the cap. Since v7 that is the carpet (24); it was the
  C-130 with its vehicle (90).
- **Drop wallet (v7):** a second ledger entry, `dropCash`, with its own income
  (the bank's times `ITW_CLASH_SupportsDropIncomeScale`, 1), starting empty, and
  a cap of one paradrop plus one vehicle (48 at 1.2 a minute).
- **Bite-back pot (v7):** `biteCash`, counted in waves: holds 1, starts full,
  earns one back in 20 minutes.
- **Prices:** set from the intended cadence. Price = income per minute times the
  intended interval:

  | Flavor | Intended cadence |
  |---|---|
  | UAV | Every 4 minutes |
  | Bomb pass, guided pass | Every 10 minutes (v5; was 20) |
  | Carpet | Every 20 minutes (v5; was 40) |
  | Helicopter airborne | Every 15 minutes of the drop wallet (v7; was 30 of the bank) |
  | Plane troops | Every 25 minutes of the drop wallet (v7; was 50, times 1.5 with the vehicle) |
  | Vehicle delivery | Every 15 minutes of the drop wallet (v7; its own support) |

- **Holding discount:** supports at a held point cost 0.75 of the price.
- **v5 tempo** (Hark, 2026-10-17: "supports are just crazy rare"). In 33
  minutes of one session B flew three strikes and A none: A spent everything on
  UAVs dying at one spot, and SAVE won most picks for both. Halving the strike
  prices opens the money gate twice as often; halving SAVE's pull adds a little
  more (a strike of weight 1 against UAV 3 and an empty bank: 14% of picks to
  18%).
- **Starting cash:** one UAV.
- **Persistence:** reset on load. Nothing is written to `profileNamespace`.

## 9. Execution

### 9.1 Common flight rules

- Aircraft spawn **after** the setup delay, in flight, on the bearing from the
  side's origin to the task, always the full 8 km (jets, since 2026-10-18; 4 km
  before, 6 km for the bomb pass) or 5 km (helicopters, transport planes) short of it, so a strike has its run-in even when our
  airfield is next to the target. That point lies beyond our airfield, in our own
  airspace. If it would fall off the map, the bearing turns in 15 degree steps up
  to 90 either way, and only then is the point clamped 500 m inside the edge. A
  strike's spawn is computed from its target cluster, not the objective centre. Origins: the side's rear base for helicopters and the UAV (`REAR_AIR`, the same base as its armour since 2026-10-17),
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
- **Loiter:** fixed-wing UAVs at 2000 m AGL (v2), set on the spawn, the flight
  height and the loiter waypoint's altitude; a rotary one, used only when the
  faction has no fixed-wing UAV, at 500 m. v1 flew all of them at 500 m: on
  2026-10-16 a Greyhawk died 5 s after reaching its station on each side, over
  objectives covered by Cheetahs.
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
- **Killbox (UAV v3, supports v5):** a UAV lost within 60 s of reaching its
  station marks where it died for its side. For 15 minutes no UAV is tasked,
  launched or retasked within 1.5 km of it: the task falls to an objective with
  leads elsewhere, or none (`UAV_KILLBOX` in the pool). On 2026-10-17 four of
  A's five UAVs died 5 to 10 s after reaching the same station with no killer
  recorded, so the air picture, which weighs a loss by its killer, never
  closed it.
- **Footprint (UAV v4):** each poll it also takes every enemy man on foot,
  vehicle with anyone alive in it, and static within 1200 m of the point under
  it, unless a building covers it (a ray straight up 40 m from the target's aim
  point that meets a building's geometry; `ITW_CLASH_SupportsUAVCoverAny` true
  makes any overhead geometry count, canopy and nets included) or the terrain
  hides it from the UAV itself. At most 80 a poll. They are revealed to the HQ group with the rest and reported to the
  knowledge layer (4.2). This is the camera's look, which the engine does not
  model from a loiter ring: on a 700 m ring at 2000 m the objective sits 70
  degrees below the horizon, and across 12 sorties the sensors and crew peaked
  at 2 contacts (Hark: "why don't we just reveal all targets below the UAV that
  aren't inside?"). The cost is plain: a man in the open under a UAV is seen
  wherever he is in its footprint unless the ground itself is in the way, and
  a vehicle under trees is seen unless CoverAny is on.
- **Camera (UAV v4):** pointed at the station every poll (`lockCameraTo`), so
  the turret's own sensors and crew look at the ground; left alone while a
  player is connected to the UAV.
- **What players see:** a UAV's reveals go to its HQ group, which is how HAL
  learns them; they never reached the players. Since 2026-10-17 the players'
  map shows every enemy group their HAL commander knows of
  (`RydHQ_KnEnemiesG`), so what a UAV finds shows up there once HAL takes it
  in. First HAL's own Info Markers drew it (`ITW_CLASH_PlayerInfoMarkers`,
  `RydHQB_InfoMarkers`); later the same day (Hark: "untick HAL's ... and leave
  Impasse's by default on, but ... wire HAL's knows about to Impasse's") those
  went off by default and Impasse's own group markers read HAL's list instead
  of the side's `knowsAbout` (`ITW_CLASH_MapKnowledge.sqf` publishes it every
  5 s as `ITW_CLASH_MapKnownEnemyGroups`; an empty read is held 15 s, since HAL
  empties the list at the start of each cycle). The enemy commander's
  knowledge is never shown.

### 9.3 Strike pass

- The jet flies a line through the aim point (bomb pass 250 m, carpet 400 m,
  guided 600 m above it). Unguided release is timed by ballistic fall time from
  where the bomb leaves (5 m under the jet) and the jet's speed, with no drag,
  times 1.08 since v5 (`ITW_CLASH_SupportsStrikeReleaseScale`). Every bomb
  leaves with the jet's velocity and arcs forward like a real stick.
- **v5, the bomb pass:** spawns 6 km out (other jets 4 km; every strike 8 km since
  2026-10-18) and is held to 550 km/h, so an acquisition has time to become a line the jet can fly.
- **Line-up**, about 3 km out: the latest report is read, the uncertainty limit
  and danger close are checked, and the jet's line is pointed through the new
  aim. The aircraft is steered onto the target; bombs are never moved onto it.
  A bomb pass that has already acquired a target lines up on that instead and
  does not apply the limit to the report.
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
- **Bomb pass, on-site acquisition (Strike v4).** The report brings the jet to
  the area; the jet picks what it bombs. Carpet and console test passes fly the
  report as before.
  1. **At spawn:** radar on; the ground's contacts in the target are revealed to
     the crew (value 1.5) so they know where to look; the crew's `AUTOTARGET`
     is enabled so they also watch for what they were not told about. The group
     stays CARELESS and BLUE: it looks, it never engages. `AUTOTARGET` goes off
     again when the approach ends, however it ends.
  2. **A reveal is never a sighting.** `targetKnowledge` gives a revealed,
     unseen target no sighting time (the never-seen case in 4.2), and only a
     sighting time after the pass began (one second after the reveal) counts.
  3. **Look**, once a second from spawn: the jet's own `getSensorTargets`
     (enemy) and its crew's known enemies, a man in a vehicle counted as the
     vehicle. A candidate needs a **fix** of the jet's own: a track on its
     sensors (the object's position: the sensor's measurement, as the guided
     pass uses it) or its crew's own sighting (the engine's perceived position
     and error). Valid: inside the scan radius around the report (R, 150 to
     500 m, as the guided pass), clear of danger close, not answered by an ETB
     responder. Ranked by the bomb's weights (parked vehicles, armour and
     statics 3, infantry 2), then the ground's own contacts first, then nearest
     the report.
  4. **Track:** new fixes are kept for 10 s. Velocity comes from two fixes at
     least 4 s apart, clamped to the class's movement allowance (4.3), so a
     jumpy fix cannot fling the aim. The aim is the latest fix moved on by that
     velocity until the bombs arrive (the fix's age plus the run left over the
     jet's ground speed), never more than 250 m.
  5. **Re-line:** with at least 10 s of flight left before the final check, at
     the speed it is flying (v5; v4 used 1800 m of run, 2 s at 200 m/s), and the
     aim moved more than 25 m, the jet is steered onto the new aim (at most
     every 3 s). After that only the timing follows.
  6. **Held to its footprint (v5):** a bomb pass more than 50 m off its line at
     the final check breaks off, and the line is checked once more on the frame
     the first bomb would leave: off by more, nothing drops (`wide`), and the
     money comes back. Carpet keeps 250 m; a console test pass keeps 250 m so a
     drifting calibration run still gives impacts.
  7. **Final check:** an acquired target that is alive is bombed where the jet
     has it, led to impact. Nothing acquired, or the target died: the report,
     only if it is inside the 300 m limit with a contact not LOST; otherwise
     `BREAKOFF` (`no-target-found`), egress, refund.
- **How this differs from Antistasi.** Antistasi's airstrike and carpet acquire
  nothing: the aim is the target's true position at the call, scattered by up
  to 100 − 20 × knowsAbout metres, and never updated. Its CAS dive bomb rolls
  a spotting chance each second (line of sight, camouflage, distance, how far
  the target moved from its last-known position) and then dives on the true
  position. Ours uses the engine's own detection: the jet's sensors and crew.
  That is generic across modded aircraft and never reads a position the jet
  did not get itself, but it is only as good as each jet's sensors and crew
  (13, item 14).
- **Guided pass, with on-site scan:**
  1. Inbound with radar on. Once within 5 km (3 km before 2026-10-18), read the jet's own
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
     **v6: and a motor** (`thrust` or `thrustTime` above 0). Arma simulates a
     bomb as a missile without thrust (`Bo_Mk82`: `shotMissile`, 0, 0), so on
     2026-10-18 the Black Wasp and Wipeout cluster variants qualified and
     launched CBU-85s from missile range at 600 m: the Rooikat lived. Which
     jets qualify, and on which magazine, is logged once per class
     (`supports-strike-guided-class`); a side whose jets carry no powered
     guided anti-armour round has no guided pass (`NO_GUIDED_WEAPON`).
     `fireAtTarget`, and if that returns false, the weapon's missile spawned at
     the jet and given the target with `setMissileTarget`. That fallback is
     legitimate only because the jet acquired the target itself.
  4. **Launch envelope**, checked when a target is found and again at the
     instant of each shot: range between the missile's own lock distances
     (`missileLockMinDistance` and `missileLockMaxDistance`, 800 and 5000 m when
     its config has none), within 40 degrees of the nose, terrain line of sight.
     The scan ends once the report is inside minimum range.
  5. **Nothing valid** before minimum range (a 60 s ceiling; 20 s before 2026-10-18):
     `BREAKOFF`, egress, despawn, refund.
- **First live releases (2026-10-17):** the Black Wasp acquired the ground's
  IFV by sight 203 m from a stale report (R 1245 m), re-lined 2.37 km out at
  200 m/s and released all four bombs on time (5.5 m late), but about 250 m to
  the side: it never settled on the new line in the 5 s it had, and the 250 m
  limit let it drop. All four landed 112 to 119 m long of the no-drag model
  and within 3 m of each other: Arma's Mk82 carries further than a plain drop.
  v5 answers both: the footprint limit and later re-line rule above, and the
  1.08 lead.
- **Break-off (v5):** a pass that breaks off turns away from the side the
  target is on, from where it is (track plus or minus 100 degrees), then takes
  the colder turn home. It no longer flies on 2 km past the aim: the A-10 that
  broke off on 2026-10-17 passed 460 m from the Cheetah it was meant to bomb
  and was lost. Delivered passes still go on past the target. Every break-off
  logs `supports-strike-breakoff-geometry`.
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
- **Aboard until the jump (airborne v3):** Hark, the first helicopter test: "the
  huron lands, drops two dudes off and then goes forward into the zone". An AI
  pilot lands for a passenger of another group who has been told to get out, so
  from boarding to the jump the squads ride CARELESS with their own combat
  reaction off, the aircraft does not unload in combat, and a passenger anyone
  unassigns is assigned back at once. Each is said once: `passenger-reassigned`
  (who, his group's waypoints and behaviour), `passenger-out-early` (who, the
  aircraft's height, distance, speed, whether it was on the ground),
  `touched-down` (the aircraft on the ground before the jump, and the crew's
  waypoint). Their behaviour comes back at the jump; `released` carries the
  three counts. Boarding cannot overfill: a man without a seat is deleted at the
  base.
- **Plane:** CARELESS with a `flyInHeightASL` floor at 250 m above the drop zone.
  Same jump. No vehicle add-on since v7. A side that lists no troop plane flies
  `ITW_CLASH_SupportsPlaneTroopClasses` (v8, Hark 3A: the Blackfish's infantry
  variant, `B_T_VTOL_01_infantry_F`); neither side here lists one.
- **Vehicle delivery (airborne v2, its own support):**
  - **Carrier:** `ITW_CLASH_SupportsVehicleCarrierClasses` first (the
    Blackfish, `B_T_VTOL_01_vehicle_F`) for both sides, whether or not the side
    lists it (v8, Hark 1A); else the side's own aircraft that carry vehicles
    inside (config `VehicleTransport >> Carrier`), the strongest lifter. Neither
    side lists the Blackfish, so v7 flew GUER's Ghost Hawk and would have flown
    WEST's Huron. An empty list goes back to the side's own. From the side's rear
    base: a VTOL needs no runway.
  - **Vehicle (v8, Hark 2B):** the side's armed and dual-role cars, then its
    APCs, then its tanks, in a random order within each, each only if the
    engine can carry it at all (`VehicleTransport >> Cargo >>
    canBeTransported`). Built crewed by `ITW_AtkSpawnVeh` at the origin and
    loaded with `setVehicleCargo`; the first of up to four that fits goes, one
    that does not fit is removed with its crew. Locked and undamageable until it
    is down. A side with nothing that can be carried is never offered a delivery
    (`NO_VEHICLE_FIT` at the gate and on a direct pick); in v7 GUER, which
    fields no cars, was refused all four console tests before anything spawned,
    and its commander would have picked, been refused and refunded on every
    assessment.
  - **Run:** one straight line through the zone at 200 m. The vehicle goes 2.5 s
    of flight short of the zone (about 175 m at 70 m/s) with
    `objNull setVehicleCargo`. The engine gives a vehicle unloaded in the air
    its own cargo parachute; if a second later nothing holds it, Impasse's
    vehicle parachute does, from where it is (`ITW_FncVehicleHalo`).
  - **Ends:** delivered or lost is spent; passed wide, never reached or failed
    to unload is refunded and the vehicle, never down, removed. A carrier lost
    with the vehicle alive inside lets it go; whatever lands is handed on.
  - **Hand-off:** down (or 180 s), a settle, damage and the lock back, then the
    crew to HAL as below (step 6).
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
| `supports-strike-lined-up`, `-release-check` | How far the aim moved at the 3 km line-up and the final check, its uncertainty or fix error, and (v4) what it was: `report`, `SENSOR` or `SIGHT` |
| `supports-strike-bomb-scan-start` | v4: id, sign, ground contacts revealed to the crew, scan radius, distance to the report at spawn |
| `supports-strike-bomb-acquired` | v4: id, sign, type, class, how (`SENSOR` or `SIGHT`), distance from the report, scan radius, run left, seconds since the pass began, looks taken, whether it was one of the ground's contacts, candidates looked at |
| `supports-strike-bomb-relined`, `-bomb-target-lost` | v4: how far the aim moved and the run left; an acquired target that died before release |
| `supports-strike-bomb-release-fix` | v4: at the final check: type, class, how, fix age, fixes held, lead in metres, estimated speed, distance from the report |
| `supports-strike-released`, `-guided-fired`, `-scan-empty`, `-effect` | What each pass did (bombs released and skipped, mean lateness in metres; shots, fallbacks, envelope refusal; why a scan ended: for the bomb pass `bomb-report` or `bomb-breakoff`, with looks taken and the report's R), and how many of the target's entities died after it (log only) |
| `supports-strike-impact` | Per bomb: error against the no-drag model (along, across), error against its pattern point (along, across), release height, speed, lateness in metres. The model is the raw no-drag one, without the release scale, so the scale can be refitted from it |
| `supports-strike-breakoff-geometry` | v5: id, flavor, reason, metres to the aim along the line, metres off it, line heading, track heading, missiles that came at it during the pass, height, speed |
| `supports-uav-killbox` | v5: side, where a UAV died within a minute of arriving, how long the area is closed |
| `supports-danger-close` | v6: side, flavor, target key (assessment) or support id (pre-run), where (`assess` or `pre-run`), and the friendly deepest inside its line: [metres, player, line] |
| `supports-drop-pool`, `supports-vehicle-pool` | v7: as `supports-pool`, for the paradrops and for delivery, with the drop wallet's cash |
| `supports-biteback-wave` | v7: side, objective, why, flag phase, pressure, wave id, [flavor, support id] for each part that went, refused parts, pot after, `live` or `test` |
| `supports-biteback-held`, `-refused` | v7: a point that wants a wave and may not have one (why, phase, pressure, the hold: `DEFEND_PHASE`, `COOLDOWN`, `INSUFFICIENT_FUNDS`, `LANE_BUSY`, `REFUSED`; pot), said once per change; a wave nothing could fly |
| `supports-airborne-vehicle-loaded`, `-released`, `-handoff`, `-unfit`, `-unload-failed`, `-lost` | v7: the delivery: carrier, vehicle, crew, zone, how many classes were tried; release speed, height, distance, whose parachute (`engine` or `impasse`); where it landed from the point |
| `supports-test-launched`, `-test-filled` | v7: a console test: side, flavor, objective, reason, support id, aircraft; a wallet filled |
| `supports-strike-impact-summary` | Per pass: the four mean errors |
| `supports-strike-ammo` | Boot: the bomb class's simulation, air friction, side air friction, max speed, thrust, thrust time, time to live |
| `supports-strike-test-started`, `-test-outcome` | A console test pass |
| `supports-uav-launched`, `-on-station`, `-retasked`, `-ended` | The UAV's life: looks stamped, peak contacts in one sweep, retasks; v4 adds the footprint's peak, the most it found covered in one poll, and footprint reports made |
| `supports-airborne-passenger-reassigned`, `-passenger-out-early`, `-touched-down` | v8: anyone leaving before the jump, said once each (above) |
| `supports-airborne-boarded`, `-released`, `-handoff`, `-vehicle-*` | The drop: squads and men, release geometry, who took each squad and which order it got |
| `supports-ledger` | Periodic: cash, cap, income, lanes; v7 adds the drop wallet, its cap and its two lanes, the bite-back pot and its two lanes |
| `supports-admission`, `-outcome` | v7 add the wallet and lane (admission) and the wallet and wave (outcome); `test` beside `live` and `dry-run` |
| `knowledge-objective` | Periodic per objective: intelligence state, observed, fixed, leads, oldest report |
| `knowledge-truth` | Diagnostic: reported against actual error, by class |
| `knowledge-truth-speed` | Diagnostic, per bucket: samples, moving, outside while moving, outside while settled, implied speed spread, implied speed spread while moving, real speed spread (each spread min, median, p90, max) |
| `knowledge-clock-anomaly` | Rejected reports off the clock (not never-seen): count, samples kept, in the past and in the future, the raw `lastSeen` spread, its spread against `time`, `serverTime` and `diag_tickTime`, how many were unit reports, how many had a valid groupmate report, and the three clocks now |
| `knowledge-never-seen` | Reports rejected as known of but never seen: count, groupmates checked, groupmates who had seen it |
| `colossus-no-push-candidate` | The side holds every active objective: no push this assessment |
| `colossus-concentrate`, `-concentrate-declined` | Said on change: objective and verdict, or the decline reason (and unanchored objectives); last field is how often the previous answer repeated |
| `supports-ready`, `knowledge-ready` | Boot: version, dry run, every switch |

## 11. Rollout

- **Supports v8 / Airborne v3** (2026-10-17, Hark, after the first console
  tests): the Blackfish first, cars then APCs then tanks, the Blackfish's
  infantry variant for a side without a troop plane, and passengers held aboard
  until the jump.
- **Supports v7 / Airborne v2 / console tests** (2026-10-17, Hark): three
  families and the drop wallet, vehicle delivery by Blackfish, bite-back, the
  console tests (section 17). Not yet run in engine; no drop has ever flown.

- **Supports v6 / UAV v4 / Knowledge v6** (2026-10-17, second run, Hark): the
  guided missile's danger margin is 100 m (200 m for players); every
  DANGER_CLOSE is logged with its cause; the UAV reports its footprint and
  points its camera. Not yet run in engine.
- **Supports v5 / Strike v5 / UAV v3** (2026-10-17, Hark): strikes twice as
  often, guided on lone vehicles, the UAV killbox, and the bomb pass held to
  its footprint with the first fitted release scale. Ran once (second
  2026-10-17 run, 27 minutes): no strike was bought. Both banks could afford a
  bomb from five minutes in and ended with two bombs' worth; two clusters came
  up near a plan objective, one a side, and both were DANGER_CLOSE. Three of
  four UAVs died within 10 s of arriving; A's killbox expired and its next UAV
  died 120 m from the first wreck. The one that loitered 15 minutes revealed
  nothing.
- **Supports v4 / Strike v4: lone targets for the bomb, on-site acquisition**
  (2026-10-16, Hark). The bomb pass's floor is 1.5, carpet needs three
  contacts, and the bomb pass acquires its own target like the guided pass
  (9.3). Not yet run in engine.
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
9. How often carpet on vehicles survives the uncertainty limit. With vehicles at
   8 m/s, armour at 15 m/s and about 36 s from spawn to release, a vehicle's R
   is already near 300 m at a fresh report and armour's is 545 m: carpet on
   vehicles needs the target under continuous observation. The bomb pass no
   longer depends on it (v4), except for its report fallback.
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
14. Whether the bomber acquires at all (v4): `bomb-acquired` against
   `scan-empty` per pass, and by how (`SENSOR`, `SIGHT`) and class. Unknowns: how
   well a CARELESS crew with `AUTOTARGET` on spots a lone vehicle, and infantry
   at all, from 250 m up and 1.5 to 4 km out; whether sensor tracks also refresh
   the crew's `lastSeen`; and whether `reveal` ever sets `lastSeen` (if it did, a
   reveal would still not count, being before the pass's start time). If the
   jets almost never acquire, an Antistasi-style spotting roll is the fallback
   to consider (9.3); it was left out because it reads the true position after
   a dice roll.
15. The lead (v4): `bomb-release-fix` speed and lead against the impact lines
   on a moving target.
16. v5 release scale: the impact lines' aim error along should now sit near
   zero at 550 km/h (the model error stays near +8% of the lead). An A-10 pass
   is the second speed that tells a fraction from a fixed distance.
17. v5 line: how often a bomb pass ends `passed-wide` or `nothing-released-wide`
   against `released`, with `breakoff-geometry` saying how far off and whether
   missiles were coming. If most acquisitions still end wide, the jet needs a
   second run (Antistasi's CAS repositions to 3 km and comes round).
18. v5 tempo: strikes per side per hour, against UAVs and SAVE in the pool.
19. v5 killbox: `supports-uav-killbox` lines, and UAV losses within a minute
   of arrival dropping after the first.
20. Info Markers: the players' map shows their own groups and the enemy groups
   their commander knows of, updated each HAL cycle; nothing of the enemy
   commander's picture.
21. v4 footprint: `supports-uav-ended` footprint peak and reports against the
   old peak, and the objectives under a UAV reading `OBSERVED` in
   `knowledge-objective`. Then whether strikes follow: candidates in
   `supports-pool` near a UAV's station.
22. v4 cover: whether `lineIntersectsSurfaces` with `GEOM` from a man's aim
   point meets the floors and roofs of Altis's buildings (the covered peak);
   whether `isKindOf "Building"` holds for terrain buildings, ruins and walls.
23. v4 camera: whether `lockCameraTo` on a UAV with an AI gunner holds, and
   whether the Greyhawk's own `getSensorTargets` then sees the ground.
24. v6 danger close: `supports-danger-close` distances, and how many were
   players; whether guided passes now run where bombs are still refused.
25. v7, every drop, first by console test (section 17): boarding, the run, the
   jump, the hand-off and HAL's order (`supports-airborne-*`).
26. v7 delivery: whether `setVehicleCargo` loads a crewed car into a Blackfish in
   flight; whether `objNull setVehicleCargo` lets it go in the air and the
   engine's parachute takes it (`vehicle-released` says `engine` or `impasse`);
   where it lands from the point; whether the crew stays aboard while carried.
27. v7 drop tempo: drop and vehicle pools per side per hour, and drops bought,
   now that they have their own wallet.
28. v7 bite-back: waves per hour, by why; how often a wave saves the point;
   and `biteback-held` reasons. v9: whether a wave launched at half-mast lands
   before the enemy flag tops out, and how often COLOSSUS's HOLD picks reach a
   point before bite-back has to.
29. v8: whether any `passenger-reassigned`, `passenger-out-early` or
   `touched-down` appears, and if so whose order it was (the group's waypoint
   and behaviour); `released` should show every man boarded jumping.
30. v8: WEST's delivery carrier is the Blackfish (`vehicle-loaded`), and GUER's
   delivery is `NO_VEHICLE_FIT` at the gate, never launched.

## 14. Tunables

All placeholders.

| Setting | Value |
|---|---|
| Knowledge poll | 10 s |
| Movement allowance | Statics 0, infantry 4, vehicles 8, armour 15 m/s |
| Uncertainty floor | 5 m |
| Diagnostic samples | Clock 300; truth 400 per bucket, from 10 s old |
| Observed | Age 60 s, R 100 m |
| Fixed | Error 100 m, age 900 s |
| Lead | R 300 m |
| Existence confidence | Full to 120 s, zero at 900 s |
| Moving threshold | 30 m between reports |
| Recently cleared window | 300 s |
| Cluster radius | 150 m |
| Value floor | 2; bomb and guided passes 1.5 |
| Carpet minimum contacts | 3 |
| Footprints | Bomb pass 50 m, carpet 60 m |
| Hard uncertainty limit | 300 m |
| Danger close margin | bomb and guided 150 m, players included (v10); carpet 300 m, 500 m for players; JTAC 150 m |
| Corridor HOT or CONTESTED multiplier | 0.5 |
| Holding discount | 0.75 |
| Setup delay | 45 to 120 s |
| Spawn distance | Jets 8 km, the bomb pass included (2026-10-18; 4 and 6 km before), helicopters and transport planes 5 km |
| Flight-time projection | Jets 150 m/s (2026-10-18; 110 before), what they fly: the Wipeout 555 km/h, the bomb pass held to 550 |
| Save pull | 0.5 times its weight by bank fill |
| UAV killbox | Lost within 60 s of arriving; 1.5 km; 15 min |
| UAV altitude, loiter, relaunch | 2000 m AGL (rotary 500 m), 15 min, 300 s |
| UAV footprint | 1200 m under it; cover ray 40 m, buildings only; report error 10 m; 80 a poll; camera on the station |
| Drop wallet | Income 1 times the bank's; starts empty; cap one paradrop plus one vehicle |
| Drop cadences | Helicopter 15 min, plane 25 min, vehicle 15 min; cooldowns 600, 900, 600 s |
| Vehicle delivery | Carrier `B_T_VTOL_01_vehicle_F` first for both sides; cars, APCs, tanks that can be carried; 200 m; 70 m/s; release 2.5 s short; 4 vehicles tried; crew counted 3 |
| Troop plane | `B_T_VTOL_01_infantry_F` for a side that lists none |
| Bite-back | Pot of 1 wave, starts full, 20 min a wave; 20 min a point; flag floor 0.9; 2 squads and a vehicle; 15 to 45 s scramble |
| Guided scan | Within 5 km down to the missile's minimum range, radius cap 500 m, 60 s ceiling (2026-10-18; 3 km and 20 s before) |
| Bomb acquisition | Reveal 1.5; a look every 1 s from spawn; scan radius R, 150 to 500 m; re-line with 10 s or more to the final check when the aim moved over 25 m; velocity from fixes 4 to 10 s apart; lead cap 250 m |
| Bomb pass speed, release scale | 550 km/h; lead times 1.08 |
| Strike heights | Bomb pass 250 m, carpet 400 m, guided 600 m |
| Bomb pass payload | 4 bombs, 15 m apart |
| Guided pass payload | 2 shots |
| Carpet | 21 bombs, 15 m along, lanes 40 m apart |
| Strike cross limit | Bomb pass 50 m (its footprint), at the final check and the first release frame; carpet and console tests 250 m |
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
- **Parked vehicles.** At 8 m/s a vehicle never passes the 300 m limit for
  carpet. Since v4 the bomb pass acquires on site and no longer needs it. A
  lower allowance for vehicles that have not moved for 60 s would make carpet
  on parked vehicles possible too, but carpet is for clusters of three or more
  anyway.

## 16. Implementation

| File | Owns |
|---|---|
| `ITW_CLASH_Knowledge.sqf` (v6) | Reports (a groupmate's sighting when the leader has none; the UAV's footprint reports), uncertainty, statuses, looks, intelligence state, the truth diagnostic, clock, never-seen and speed instrumentation |
| `ITW_CLASH_Colossus.sqf` (v7) | The one call to `ITW_CLASH_Supports_fnc_Assess` after its order; reported strength beside live; a push only for ground not held; concentration gated on anchored holdings |
| `ITW_CLASH_RackProfile.sqf` | What a vehicle can fire, read from its live rack; the guided pass reads its weapon through it (see `CLASH_HALAirEmployment_Model.md`) |
| `ITW_CLASH_Supports.sqf` (v8) | Registry, ledger and its three wallets, the three pools and picks, bite-back, direct picks, admission, lifecycle, settlement, shared flight code; live by default; the bomb's own floor, carpet's cluster minimum, the acquiring flavors, the guided danger margin |
| `ITW_CLASH_SupportsDebug.sqf` (v1) | Console tests: a drop, a delivery, a wave, the wallets, filling a wallet (section 17) |
| `ITW_CLASH_SupportsStrike.sqf` (v6) | Bomb pass with on-site acquisition, guided pass with the on-site scan, carpet; the break-off turn and its geometry |
| `ITW_CLASH_SupportsUAV.sqf` (v4) | The recon UAV; marks a killbox on a quick loss; the footprint, its cover test and its reports; the camera |
| `ITW_CLASH_DualHALCheckbook.sqf` | The players' commander's Info Markers |
| `ITW_CLASH_SupportsAirborne.sqf` (v3) | Helicopter and plane drops, passengers held aboard until the jump, vehicle delivery carried inside its aircraft, the hand-offs |
| `ITW_CLASH_AirPicture.sqf` | `Observed` also accepts a recent `uav` look |
| `ITW_CLASH_DebugPreflight.sqf` | Lists the five modules |
| `ITW_CLASH_AttackRestore.sqf` | Skips groups carrying `ITW_CLASH_SupportAsset` |

Boot (`init.sqf`): the rack profile, then Knowledge, then COLOSSUS, then the
core and its three executors; the core needs Knowledge and COLOSSUS, and an executor that is
missing revokes its supports with `NO_EXECUTOR`. Static contracts are pinned in
`tests/test_commander_supports.py`, `tests/test_bomb_acquisition.py` (v4), `tests/test_supports_v5.py` (v5) and `tests/test_supports_v6.py` (v6), `tests/test_supports_v7.py` (v7, the console tests and the rear-base C-RAM), `tests/test_supports_v8.py` (v8). The pure math (pick, overlap, presence,
falloff, spawn point, release timing, economy) is cross-checked in a Python
model. The dry run has run in engine (2026-10-16); no live support has yet. Section 13 is the list to verify.

## 17. Console tests (v7)

`ITW_CLASH_SupportsDebug.sqf`. From the debug console with **Server Exec** (on a
hosted game Local Exec is the server too). Each flies the real thing through
the real executor, with every normal log line, and says what it did in chat. A
test pays nothing, holds a lane of its own so it never blocks a commander, and
skips the map's gates (a frozen point, the drop zone's intelligence, headroom, a
denied corridor). The aircraft, its route and the squads are found exactly as a
commander's would be.

Where: an objective index, a position, an object, or nothing for the objective
nearest the first player. Side: `west`, `independent`, `east`; nothing for the
players' side; `"BOTH"` (v8) runs the test once for each side, each with its own
commander (Hark: "for parity reasons").

```sqf
["AIRBORNE_HELI"] call ITW_CLASH_SupportsDebug_fnc_Drop;                  // helicopter drop, nearest objective
["AIRBORNE_PLANE",23] call ITW_CLASH_SupportsDebug_fnc_Drop;              // plane drop on objective 23
["VEHICLE_DROP",player,independent] call ITW_CLASH_SupportsDebug_fnc_Drop; // the enemy's Blackfish delivery
["AIRBORNE_HELI",23,west,"TAKE"] call ITW_CLASH_SupportsDebug_fnc_Drop;    // force TAKE or HOLD
[] call ITW_CLASH_SupportsDebug_fnc_BiteBack;                              // a wave to your side's nearest held point
[23,independent] call ITW_CLASH_SupportsDebug_fnc_BiteBack;
[] call ITW_CLASH_SupportsDebug_fnc_Status;                                // wallets, lanes, held points' flags
[west,"DROP"] call ITW_CLASH_SupportsDebug_fnc_Fill;                       // fill a wallet: the commander's own next pick
["BOMB"] call ITW_CLASH_SupportsDebug_fnc_Strike;                          // v8: a bomb pass near the first player
["GUIDED",player,independent] call ITW_CLASH_SupportsDebug_fnc_Strike;     // GUER's guided pass near you
["CARPET",23,"BOTH"] call ITW_CLASH_SupportsDebug_fnc_Strike;              // each side's carpet near objective 23
["AIRBORNE_HELI",nil,"BOTH"] call ITW_CLASH_SupportsDebug_fnc_Drop;        // any test, both sides
```

**Strike tests (v8).** Hark: "can we build debugs for strike and guided as
well?", then 1A and 2A. The target is the commander's own pick: the pool's own
clustering and scoring (`StrikeCandidates`) centred on the point instead of an
objective, for that one flavor, and the best candidate goes. A context marked
`test` skips only the economic questions (lane, relaunch, cooldown, funds, the
price at each objective, the crossing count) and the denied corridor. Every
other gate is asked as it is of a real strike: the bomb's sighting, carpet's
cluster, the floors, uncertainty, an ETB answer, and danger close, at the pool
and again before the run. A test that would hit its own side's men is refused
and says so; a side that knows of nothing there says what it was refused on
(`supports-test-refused`: point, contacts known within the influence radius,
reasons counted). `supports-test-launched` names the target: its key, class,
size, worth, aim and distance from the point, how many candidates there were,
and the weight. Only the striking side's troops count as friendlies, so a GUER
test near you can hit you.

**The v8 regression (2026-10-18 run).** The strike test first passed its
point as a target's fourth element. In a commander's own assessment that slot
is the objective's picture entry, a hashmap, so the first assessment failed
("Type HashMap, expected Array", `ITW_CLASH_Supports.sqf:1323`) and the error
ended COLOSSUS's loop for both sides: no commander support of any kind, and no
COLOSSUS order after the first, for the whole 90 minutes. The point now rides
on the test context (`at`). A refused test also names a cluster a flavor
values at zero (`NOT_FOR_LEAD_ONLY`: a bomb takes no lead-only cluster), where
it used to say only "nothing it could strike".

`Fill` is the test of the real decision: the next assessment's drop and vehicle
pools can afford everything, so what the commander picks, and why the rest is
refused, shows in `supports-drop-pool` and `supports-vehicle-pool`. The strike
pass keeps its own test (`ITW_CLASH_SupportsStrike_fnc_TestPass`).
