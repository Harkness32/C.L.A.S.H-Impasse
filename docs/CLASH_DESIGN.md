# C.L.A.S.H. — design and feature breakdown

**Status:** living document. Generated against the tree at the commit that added
it; module versions and line counts move, the architecture and the invariants
do not.

**Scope:** what each part of C.L.A.S.H. does and how it does it. 104 modules,
~40k lines, under `13715765820790864929_legacy/ITW_CLASH_*.sqf`.

**How to read it:** the Architecture and Invariants sections are the parts worth
reading end to end — almost every design decision in the catalogue follows from
them. The catalogue is reference material; use it to find the owner of a
behaviour, then read that module's own header, which is authoritative.

**Honesty note on sourcing.** Every module description below is taken from that
module's own in-source header, not from memory. Where a module has no header,
the catalogue says so rather than guessing: that is documentation debt, listed
in §7 so it is visible instead of papered over.

---

## 1. What C.L.A.S.H. is

Three systems own the mission, and C.L.A.S.H. is the third.

| | owns | does not own |
|---|---|---|
| **Impasse** | the map, zones, the campaign, the baseline army, tickets and economy, force generation geography | tactical decisions |
| **NR6 HAL** | tactical command — who attacks what, dispatch, waypoints, movement, garrison, resupply execution | strategy, economy, the zone model |
| **C.L.A.S.H.** | the seams between them, and the doctrines neither has | anything either of the other two already does well |

C.L.A.S.H. is deliberately not a commander. It is a **bridge plus a set of
doctrines**. The recurring shape of a C.L.A.S.H. module is:

> notice a gap, express it in the other system's own vocabulary, hand the work
> back.

Three examples of that shape, all real:

- `HALFront` does not write a front-tracking system. HAL already has
  `RydHQ_Front` and already ignores threats outside it, recalls squads whose
  target leaves it, and aims artillery inside it. C.L.A.S.H. computes the
  rectangle and sets the variable.
- `FOBAirDefence` does not reimplement garrisoning. HAL garrisons a group
  wherever it already stands, so the only missing step is *walking the AA squad
  to the FOB first*. C.L.A.S.H. does that step and then puts the group in
  `RydHQ_Garrison`, and HAL digs it in.
- `Colossus` does not dispatch anything. It computes which objective is worth
  taking and writes HAL's own `RydHQ_Order`; HAL's dispatchers, group selection
  and Busy locks do the rest.

---

## 2. Invariants

These are not style preferences. Each exists because violating it broke a run.

### 2.1 Never edit `NR6 Hal/`

Tests run against the **public Workshop HAL**, so an edit in the repo copy never
executes. Worse, it looks like it should. HAL is changed at runtime instead:

```
toString / preprocessFileLineNumbers  →  exact text swap  →  compile  →  reassign
```

Every such patch **verifies its anchor and falls back to stock HAL if the anchor
misses**, logging a warning. All-or-nothing: a partial patch is never applied.
`HALDispatcherAAFix`, `HALDispatcherSoftArmorFix`, `HALCargoDiceFix` and
`HALWaypointGuardFix` all work this way.

Where HAL exposes a variable for something, that is used instead of a patch —
that is the whole mechanism behind `HALFront`, `Colossus`'s order, and
`HALTaxonomy`.

### 2.2 One owner per concern

Every behaviour has exactly one file that may decide it. Two files writing the
same state is how you get a run nobody can diagnose. The catalogue below is
organised by owner for this reason, and several modules exist *only* to be that
owner (`Resupply` for "HAL let this unit run dry", `HALTaxonomy` for "what does
HAL think this vehicle is").

### 2.3 Reuse HAL and Impasse primitives before writing new ones

`ThunderRun_Core`: *"This deliberately does not create another contact model; it
asks a different doctrinal question of the picture HAL already maintains."*
`AirPicture` runs **HAL's own** `knowsAbout >= 0.05` test on a faster clock
rather than inventing a detection model. `ArtilleryScoot` uses HAL's existing
`Fired` handler and `RydHQ_ShotFired2` counter instead of adding one.

### 2.4 Classification is config-driven, never a class list

A hardcoded classname list does not survive a faction port. Classification reads
config: `isKindOf`, `armor`, `artilleryScanner`, `aiAmmoUsageFlags`,
`SensorsManagerComponent`. Faction hardware comes from Impasse's own
`va_p*Classes` / `va_e*Classes` arrays, never from a literal.

### 2.5 No cheat vision

A commander may only act on what it actually knows. `AirPicture` publishes only
aircraft someone has seen. `CounterBattery` is explicitly an **acquisition
model** rather than a lookup: *"the server knows which gun fired every round,
and using that directly would hand each commander a perfect map of the other's
batteries — which is both a cheat and bad play."*

### 2.6 Advisory first

A doctrine that will mutate the war ships observing first, writing nothing, and
is read from a real run before it is allowed to act. `Colossus` ran advisory for
three versions. Every such module keeps its `...AdvisoryOnly` flag afterwards as
the kill switch.

### 2.7 Fail open

If a module cannot load or its prerequisite is missing, the mission runs as
baseline Impasse plus HAL. `init.sqf` guards every load with `fileExists` plus a
prerequisite check and a `CLASH BOOT | WARNING` line naming **the consequence**,
not just the failure.

### 2.8 The SQF trap that keeps costing us

`exitWith` inside a `then` block leaves **only that block**, not the function.
This has caused at least two real bugs, one of which gave every handed-off
vehicle a search-and-destroy order and sent empty transports to the front. The
fix pattern is a flag set inside the block and an exit at function scope.

---

## 3. Integration techniques

Five mechanisms cover nearly every module.

**Runtime function patching** (§2.1) — for HAL logic with no variable hook.

**Sanctioned globals** — HAL reads certain mission-namespace variables every
cycle. Writing them is not a hack, it is the interface. Examples:
`RydHQ_Front`, `RydHQ_Order` (and its per-commander `RydHQ<Sign>_Order` form),
`RydHQ_Garrison`, `RYD_WS_*_class` / `RHQs_*`, `RydxHQ_NEAware`.
Note `RydHQ_Order` is **not a decision HAL makes** — `HQSitRep` copies it from
a global every cycle, so whoever sets that global decides whether a side fights.

**The lease** — C.L.A.S.H. takes a group off HAL using HAL's own `Busy` lock
(after HAL's `Break` unwinds the running order), strips it from HAL's role
lists, runs a doctrine, then hands it back and audits that HAL took it. Used by
`Resupply`, `SPAAOverwatch`, `HotDrop`, `GTFO`, `FOBAirDefence`. The hazard is
the one-way door: eight files call `enableAttack false` and only two restore,
which is why `AttackRestore` exists as a safety net.

**Observation-only layers** — publish a signal and nothing else.
`AirPicture`, `CombatDiagnostics`, `FrontRouting` (shadow), `ReconObserver`,
`DebugPreflight`. Several are asserted read-only by tests.

**Two-threshold hysteresis** — any state that could flap on a boundary gets
separate enter and leave thresholds. `Colossus` posture (enter 1.5, leave 1.1),
recon contact tracking, the `Colossus` order dwell.

---

## 4. Boot sequence

```
preInit.sqf
  PreInit seams: DualHALCheckbookPreInit, InfantryAuthorityPreInit,
  PhysicalMovementPreInit, SpawnArchetypePreInit
      ↳ compiled before Impasse finalises its writers; fail open to untouched
        Impasse if the runtime layer is not up

init.sqf
  1  SOFDoctrineBootstrap   → Bootstrap → ITW_CLASH.sqf (the controller),
                              RuntimePatch, GTFO bridge, then SOFDoctrine,
                              InfantryAuthority(+AllocationFix), HALNativeSFFix,
                              FieldHardening
  2  Economy    DualHALCheckbook(+Hardening), CheckbookAPI, ForceGeneration
  3  Utility    RoadDistance, HALLogistics, LoudDebug
  4  Air/threat AirPicture → EmergingThreatsBudget → HALThreatCoverage
  5  Doctrine   Colossus, CounterBattery, ArtilleryScoot, SPAAOverwatch,
                HALTaxonomy, RearBaseCRAM, FOBAirDefence, HALFront,
                InfantryDemand, HotDrop, ThunderRunAirTiers
  6  Player     PlayerGarageDeployment, PlayerDemandDispatch,
                PlayerDemandNativeInterceptors
  7  Sustain    Resupply, HALReconLatch, AttackRestore
  8  Debug      DebugPreflight, TestComms
```

Ordering is load-bearing in two places: the **bootstrap finalization window**
(`Bootstrap` → `SOFDoctrineBootstrap`) holds a set of public functions mutable
for exactly one synchronous pass so authority wrappers can be installed, and it
closes before scheduled startup runs. And the air chain is strictly
`AirPicture → ETB → ThreatCoverage`: the picture only observes, the budget only
funds, the coverage layer decides.

All 104 modules are reachable from some loader; the ones not listed above are
loaded by the bootstraps, by `ThunderRun.sqf`, by
`PlayerTaskRequestBootstrap.sqf`, by `PlayerTaskRequests.sqf`, by
`PlayerDemandNativeInterceptors.sqf`, or by `RemnantEvac.sqf`.

---

## 5. The subsystems

### 5.1 Economy — the two wallets

**`DualHALCheckbook`** (v6, 1422 lines) is the state boundary between HAL intent
and Impasse resources, and the symmetric-commander layer: HAL exposes two
commanders through separate global projections, and this is what makes both real.
**`CheckbookAPI`** (v2) is its public face — *"HAL supplies a capability request.
A provider may consult ITW faction pools, tickets, caps and generation geography,
but it may not choose targets, routes, fire missions or recipients."* Every
result is a typed HashMap with one schema, denials included.

**`EmergingThreatsBudget`** (ETB) exists because the Checkbook lost a race it
could not win. Impasse's own vehicle spawner shares the same per-row tickets and
always goes first, emptying every affordable row moments after it fills, while
HAL only evaluates threats every 45–90s. Result in the 81-minute peer run:
**4 of 117 threat purchases went through**, and what each side fielded was
Impasse's random pick rather than HAL's decision. The ETB is a **second, separate
wallet per commander**, on top of Impasse and never inside it — no Impasse ticket
is taken, reserved, borrowed or edited.

**`ForceGeneration`** (v2) resolves the same ITW base graph for either side:
active objective → side attack-source FOB → upstream rear FOB. It also owns
`ETBFulfil`, the one-transaction purchase path: resolve candidate, check
progression and reserve, **reserve money and the row slot before anything that
can pause**, re-check the threat still exists, spawn, verify the real class
fulfils the capability or refund and blacklist, register with HAL.

### 5.2 The air war

**`AirPicture`** (v2) is the foundation and it only observes. HAL refreshes enemy
lists once per cycle (3–6 min), far too slow for a jet over the rear — in one
peer run a Black Wasp worked BLUFOR's helicopters and no air request was ever
raised. This runs **HAL's own** known-enemy test (`knowsAbout >= 0.05`) on a
5-second clock, for enemy aircraft only. It also owns the shared classification
primitives the rest of the stack uses: `ClassProfile` (cached config walk over
magazines, ammo and sensors), `ProtectionGrade` (0 soft / 1 protected / 2 heavy),
`IsSPAA`, `IsFighter`, `IsArmoredThreat`, and `ClassifyCorridor`.

`ClassifyCorridor` returns `COLD`, `CONTESTED`, `HOT`, `AIR_DENIED` or
`UNKNOWN`. `UNKNOWN` is decided **last**, so any measured threat wins, and means
*nobody has looked* — a distinction that did not exist until an unobserved
corridor reporting `COLD / corridor-clear` was traced to Littlebirds flying
landing approaches into unseen defences.

**`HALThreatCoverage`** (v6) turns the picture into demand. It answers exactly
two needs — anti-armour and counter-air — *"the gaps the baseline army
structurally cannot close."* Enemy infantry, cars, statics, artillery and cargo
never open ETB demand on purpose. It also briefs threats to the dispatcher
(`reveal` level 2) before `RYD_Dispatcher` runs, excludes crewless hulls from
`ArmorThreats`, and gates on SPAA capacity.

**`SPAAOverwatch`** is *"the one exception to 'HAL owns employment'."* An air
defence vehicle is only worth what it denies; HAL treats one as another armoured
group and sends it forward. The doctrine covers **every** SPAA on a side, not
just ETB purchases, because coverage counting cannot trust an Impasse-spawned
Cheetah that might wander off.

**`RearBaseCRAM`** (v2) puts one static AA piece at each rear base, outside HAL
and unbilled, to make one thing true: *an enemy aircraft circling a rear base
should not be what makes that commander buy a fighter.* Counter-air coverage
already counts it at weight 1.0 inside a 3 km umbrella, so the demand does not
open until the aircraft moves over the front. It is also the readable half of the
air war for players — a fixed, learnable no-go zone.

v2 separates **crew loss from vehicle loss**. v1 treated a dead gunner as a dead
emplacement, so killing the crew deleted an intact gun and built a new one five
minutes later, and the uncrewed hull in between took its *config* side — which
made GUER's NATO-classed AA read as a BLUFOR asset in GUER's own base. An
uncrewed-but-intact piece is now re-crewed in place, and a replacement stands
where the original did rather than re-resolving the base graph.

**`FOBAirDefence`** walks an idle AA squad to a FOB and then hands it to HAL's
garrison routine. It yields entirely when overwatch already holds a mobile SPAA
on that side's back line — the C-RAM deliberately does not count toward that,
because it is bolted to one spot and covers the base, not the FOBs.

**`ThunderRunAirTiers`** replaces Thunder Run's three blunt denial rules with
graded ones. The old rules closed a corridor on *any* known enemy aircraft within
5 km — and "any" was literal, because HAL's `RHQ_NCAir` is the unarmed *subset*
of `RHQ_Air` rather than a removal from it, so an unarmed enemy transport five
kilometres off the route grounded a resupply run.

**`HALCargoDiceFix`** removes a coin flip. HAL rejects an air transport for a
cargo request on a dice roll in which **position never appears** — the moment a
commander knows of any air or AA threat anywhere on the map, every helicopter
lift becomes roughly a 57% rejection for the rest of the mission.

**`HALDispatcherAAFix`** corrects a wrong variable: HAL's AIR branch gates on
"do we know of any AA" but then measures the distance to the nearest **AT**
threat. So it flew aircraft past real SPAA and resigned from clear routes that
merely passed a tank.

**`HotDrop`** (v5) is the troop-insertion profile — fly low and fast, pop up at
the last moment, put infantry out, leave. A clear (`COLD`) approach is left to
HAL deliberately: including it once made HotDrop take essentially every troop
lift on the map. `UNKNOWN` **is** included, and `HotDropNoLandStates`
(`HOT`, `AIR_DENIED`, `UNKNOWN`) makes a refused paradrop abort and hand the
lift back rather than put the aircraft down forward.

### 5.3 The ground war

**`Colossus`** (v3) is the strategy layer, and the reason it exists is stated in
its own header: *"Strategy has had no owner at all — HAL's own Big Boss is off
and does not fit Impasse's zone model — so the war is a slugfest: every HAL
cycle, whatever groups happen to be free get sent, they arrive one at a time and
they die one at a time."*

It builds a **ground picture**: per contested objective, what the commander knows
is there, what it has there, what is free to send, what a push would cost at the
planned force ratio, and a verdict (`OPEN` / `EMPTY` / `VULNERABLE` /
`CONTESTED` / `HELD`). Then a theatre posture (`PUSH` / `CONSOLIDATE`, with
hysteresis) and a recommendation — the softest objective it could actually mass
against, not the nearest.

v3 is where it started acting. It writes HAL's `RydHQ_Order`, replacing this,
which had been deciding the war:

```sqf
if ((count _held) < (count _active)) then {"ATTACK"} else {"DEFEND"}
```

That never looked at the enemy. In run4 both active objectives read `held`, so it
said `DEFEND` for all 88 samples with zero attack dispatches, while Colossus was
reporting an objective `VULNERABLE` with force available. Now: `CONSOLIDATE` →
defend; `PUSH` with sufficient force → attack; `PUSH` but short → defend, because
attacking while short is what feeds groups in one at a time. An order holds for
120 s before it may change again. **It still never touches a group** — HAL
carries out the order with its own dispatchers and locks.

**`HALFront`** (v2) bounds where a commander reacts. Each cycle HAL's dispatcher
answers every known enemy *on the map*, so a far contact pulls squads off the
objectives and two commanders feed each other. Setting `RydHQ_Front` makes HAL
itself ignore outside threats, recall squads whose target leaves, and aim
artillery inside. `RydHQ_FrontA` stays off so HAL still *knows* every enemy, and
the SF raid routine never reads the front — only special forces go deep.

**`HALReconLatch`** holds `RydHQ_ReconDone` true while a commander has contact.
HAL will not issue a capture order without it; the fallback is a ~5%-per-cycle
dice roll. Three things combined to hold the flag down — HAL dispatches recon
only while *completely blind*, `HQReset` clears the flag while rebuilding only
part of its fingerprint, and C.L.A.S.H. shortens `RydHQ_ResetTime` — and only the
third was ours. A 20-minute run showed 29 friendly groups, 37 included, two
attack-available, nothing moving.

**`HALWaypointGuardFix`** guards five `_wp0 isEqualTo []` sites against the
variable being undefined. Stock HAL bug, but C.L.A.S.H. is why it is hit: before
the recon latch, HAL almost never issued a capture order, so `GoCapture` almost
never ran. When it throws, the group silently gets no waypoint and does not go.

**`HALDispatcherSoftArmorFix`** — *"Trucks drive up to tanks because only armour
ever checks for armour."* HAL's AT-risk resignation is gated on the group being
in `_LArmorG` or `_HArmorG`; a soft-skinned group under an INF pattern is in
neither, so it is sent at a known tank with **no risk assessment at all**. The
fix appends one list to one expression, and HAL's own distances, recklessness
scaling and dice then apply unchanged.

**`HALTaxonomy`** authors the class buckets HAL reads, via
`RYD_WS_*_class` (seed) and `RHQs_*` (exclusion). HAL's own autofill
(`RYD_PresentRHQ`, on by default) already classifies unknown classes from
config, so this is not a rescue — it is a better-informed source for the part
C.L.A.S.H. already decides, since `ProtectionGrade` has no equivalent in HAL.
The substantive difference is that **HAL decides AT by guidance**
(`irLock + laserLock > 0`) while **C.L.A.S.H. decides it by role**
(`aiAmmoUsageFlags`): a tank gun firing APFSDS has no lock, so a gun-armed
wheeled AFV is not AT to HAL, is never promoted into `LArmorAT`, and sits in
`LArmor` — which is absent from HAL's anti-armour pool.

`LArmorAT` is a **promotion for light armour**, not a label for tank destroyers:
HAL's Armor pool is `[airCAS, HArmorG, LArmorATG, ATInfG]`, so a tank is already
in it via `HArmor` and adding it to `LArmorAT` too would double its weight.

**`ArtilleryScoot`** displaces a gun after it has fired, between missions and
never during one. *"An AI gun line fires from the same grid square for the whole
mission. That is free information for anyone who can count."*

**`CounterBattery`** is its counterplay, and an acquisition model rather than a
lookup: a side earns a fix the way a real counter-battery radar does — by being
shot at. Rounds are followed to impact; if they landed near that side's own
people, it acquires a fix with an error radius that shrinks as more rounds of the
same mission are observed. **Shelling nobody tells nobody anything.**

**`SOFDoctrine`** — conventional infantry holds ground, SOF screens the rear and
does special operations, and a positively identified SOF formation is never
eligible for an objective anchor. The classifier prefers Impasse's immutable
spawn archetype, requires a **majority** of the formation template to resolve to
the same SOF family (one embedded specialist must not convert a conventional
squad), and reads the identity modpacks already declare.
`ReconPlanningBridge` adds only C.L.A.S.H.-recognised SOF to HAL's native
SpecFor snapshot, per commander, because Impasse faction classes are not
guaranteed to appear in HAL's stock table.

**`InfantryAuthority`** (+`AllocationFix`) makes HAL's ownership of fielded
infantry persistent. Objective allocation is **affinity metadata, never tactical
ownership**, and the allocation audit deliberately **never releases** a group for
waypoint drift — it only updates affinity. Zero `allocation-drift` events in a
run is correct behaviour, not a missing arm.

**`RuntimePatch`** (v5) is the V6 integrity correction surface, applied inside
the bootstrap finalization window: C.L.A.S.H. owns point defence and Impasse
garrison writes are suppressed; mixed squads stay eligible when they merely
contain embedded specialists; exhausted squads egress through the base that
supports their objective; reconstituted squads are handed back only after
physical return; and objective anchors must hold at six conscious soldiers.

That last one now relaxes. A flat floor of 6 deadlocked objective 3 for an entire
24-minute run — the only group clearing it was SOF, which the doctrine excludes
from anchoring, and the three that offered themselves had 4, 4 and 1 men,
rejected 45, 43 and 20 times against an unchanging number. The floor steps down
per interval of waiting toward a minimum of 3, **only while a refill is
pending**, and a group accepted under a relaxed floor is stamped with the floor it
was accepted at so the audit cannot demote it next poll.

### 5.4 Sustainment

**`Resupply`** (v2, 1750 lines) owns *"HAL let this unit run dry and nothing is
coming."* Native HAL resupply always gets first chance; a group is claimed only
after staying in need past a patience window with no native delivery in flight.
Patience is need-dependent: 120 s default, 30 s for repair (*"a dry rifle can
wait out a native delivery; a vehicle at half damage is losing the fight it is
standing in"*), 0 s when immobilised.

v2 is **GFR**, and it changes what a claimed *vehicle* group does while it waits.
v1 sent it to a threat-screened rally, which in one run ordered a damaged Namer
to withdraw 1250 m — far enough that HAL reads the tank as off the line and asks
for a replacement. v2 holds it where it stands, and lets it move for exactly two
reasons: a short break to cover (≤300 m, max 2) when it is **actually being hit**
— judged by lost clearance *or* hull damage climbing, so an unspotted shooter
still counts — and a bounded run toward a dispatched truck, 35% of the gap capped
at 600 m, so the two meet part way. The weight sits below half on purpose: the
damaged side should move less. Infantry keeps the v1 rally.

**`GTFO`** is the withdrawal authority bridge. Its header states the division
plainly: HAL owns `GoRest`, routes, movement, smoke, speed and withdrawal radio;
Impasse supplies the corridor, recovery hardware and reconstitution; C.L.A.S.H.
marks a formation combat-ineffective, translates Impasse's rear corridor into
HAL's native Withdrawal Rally Point, blocks recommitment, and hands authority to
recovery **only after physical boarding**. It deliberately does *not* create a
withdrawal waypoint, force BLUE, or call `enableAttack false`.

**`AttackRestore`** is the net under the one-way door. Eight files call
`enableAttack false`; two call `true`, both on unrelated paths. For a
purpose-spawned CASEVAC crew that is correct — but the same call is made on the
**casualty's own squad**, which is a line unit that should fight again. 345
anomalies in one run, 0 after.

**`CASEVAC`** (v5) and **`GroundMEDEVAC`** handle casualty recovery.
`GroundMEDEVAC_VehiclePolicy` defines the *requirement* and lets the faction
supply the hardware, with no classname hardcoded: 1–3 survivors LIGHT, 4–6
MEDIUM, 7+ HEAVY, as a continuous preference rather than a bucket lock, with
post-spawn cargo validation authoritative.

**`ThunderRun`** / `_Core` / `_Tuning` is the logistics insertion profile —
visibly slingloaded package, detach and stage at takeover for `RYD_AmmoDrop`,
dry AI vehicles able to use the same air-ammo doctrine, crew sensors live and
`Busy` as the HAL retask lock.

**`Service*`** (`Authority`, `Lifecycle`, `Stability`, `CapacityPolicy`,
`ExecutionGuards`, `HomeResolver`) govern service-vehicle enrollment and leases.
Two constraints worth knowing: a live lease is *"identity/accounting metadata
only — we deliberately do not rewrite HAL planning arrays here: HAL owns live
disposition and SitRep"*, and the live Impasse base resolver stays the **sole
writer** of HAL's `START+str(group)` RTB input, because transient player-flown
carriers are not pool assets but HAL still consumes that answer.

### 5.5 Player-facing

A large block (`PlayerTaskRequest*`, `PlayerDemand*`, `PlayerTransport*`,
`PlayerEmploymentMenu`, `PlayerArtilleryTasks`, `PlayerGarageDeployment`) lets
players request recon, strikes, artillery, transport and support through the same
Checkbook/HAL machinery the AI uses.

The governing constraint is in `PlayerTransportNativeBridge`: *"`HAL_SCargo` is a
complete transport executor, not merely a carrier selector… Therefore C.L.A.S.H.
observes and protects that lifecycle but never starts a second physical GET IN /
GET OUT executor for the same HAL request."*

`PlayerTaskRequestRecon` carries a representative fix: HAL rebuilds
`RydHQ_KnEnemiesG` every cycle, so a pass sampling it mid-rebuild sees a partial
list and declares every tracked contact lost at once — 121 losses and 105 returns
in a 70-minute run, four contacts lost in the same second and back two seconds
later. Because `lostAt` gates a contact maturing into a player task, every flap
reset the clock and a genuinely lost contact could never become a task.

### 5.6 Diagnostics

**`DebugPreflight`** collapses ~200 scattered `CLASH BOOT` lines into one
greppable block: a per-module READY/WAITING/MISSING manifest, per-commander HAL
cycle, front, group and known-enemy counts, artillery and air denials, ETB
status, COLOSSUS picture size, and the AI skill line. Read-only, asserted by
test — *"if this file is deleted mid-campaign nothing else changes behaviour."*

**`CombatDiagnostics`** (v4) is the observer built to explain close-range
pass-through and non-engagement. Deliberately **detection-independent**: it finds
physically hostile groups first and only then records what Arma and HAL believe —
side friendliness, captive state, `attackEnabled`, AI features, behaviour and
combat mode, `knowsAbout` / `targetKnowledge` / `targets` / `findNearestEnemy`.

**`LoudDebug`** mirrors a whitelist of decisions to in-game chat in plain
language, so a tester can see *why* something happened without alt-tabbing. Off
by default, a formatter on the tail of logging that already happened, and
changes no decision. Controlled by the `CLASHDebug` mission parameter
(0 off / 1 preflight chat / 2 full).

**`TestComms`** mirrors a small event whitelist to GLOBAL so a BLUFOR tester can
hear what an OPFOR formation is doing, reusing HAL's own `CfgRadio` recordings.
Explicitly temporary.

---

## 6. Module catalogue

Generated from each module's own header and boot line, not written from
memory. `v` is the module's self-reported version, `lines` its size, and
`ready flag` the `CLASH BOOT | <flag>` line it publishes — that flag is
what `DebugPreflight` reads and what to grep for when a module seems
absent. A dash in `ready flag` means the module publishes no boot line of
its own, usually because a parent loads and reports it.

### Controller and bootstrap

| module | v | lines | ready flag | what it does (its own words) |
|---|---|---|---|---|
| `Bootstrap` | – | 386 | `–` | C.L.A.S.H. |
| `SOFDoctrineBootstrap` | – | 220 | `–` | Narrow bootstrap wrapper for post-V6 doctrine. |
| `RuntimePatch` | 5 | 529 | `runtime-patch-ready` | V6 runtime integrity correction, applied during the bootstrap finalization window before observer/live startup: - C.L.A.S.H. |
| `FieldHardening` | 3 | 445 | `field-hardening-recon-nil-guard-ready` | _no in-source header_ |
| `OneZeroHardening` | 1 | 270 | `one-zero-recovery-handback-ready` | Recovery failure handback sequencing. |
| `DualHALCheckbookPreInit` | 2 | 144 | `dual-hal-checkbook-preinit-ready` | PreInit compatibility seam for the symmetric C.L.A.S.H. |
| `InfantryAuthorityPreInit` | 2 | 71 | `infantry-authority-preinit-ready` | Impasse's infantry manager is strategic scaffolding once C.L.A.S.H. |
| `PhysicalMovementPreInit` | 5 | 123 | `physical-movement-ready` | _no in-source header_ |
| `SpawnArchetypePreInit` | 1 | 70 | `spawn-archetype-preinit-ready` | _no in-source header_ |

### Economy and generation

| module | v | lines | ready flag | what it does (its own words) |
|---|---|---|---|---|
| `DualHALCheckbook` | 6 | 1422 | `checkbook-cargo-hook-ready` | _no in-source header_ |
| `DualHALCheckbookHardening` | 5 | 230 | `dual-hal-checkbook-hardening-ready` | Commander B is a real HAL HQ but also an invisible compatibility object. |
| `CheckbookAPI` | 2 | 277 | `checkbook-api-ready` | Checkbook V2 is the single state boundary between HAL intent and Impasse resources. |
| `EmergingThreatsBudget` | 1 | 786 | `etb-ready` | The Emerging Threats Budget. |
| `ForceGeneration` | 2 | 1144 | `force-generation-ready` | Resolve the same ITW base graph for either side: active objective -> side attack-source FOB -> upstream rear FOB. |
| `VehicleEchelonPolicy` | 2 | 224 | `vehicle-echelon-policy-ready` | _no in-source header_ |
| `SeaGenerationGuard` | 3 | 247 | `sea-generation-guard-ready` | _no in-source header_ |
| `FrontRouting` | 1 | 445 | `front-routing-ready` | Front Routing Phase 0 This is the commander-facing operational FOB selector for both sides. |
| `RoadDistance` | 2 | 182 | `road-distance-ready` | Genuinely honest distance between two points, not straight-line. |

### Air and threat

| module | v | lines | ready flag | what it does (its own words) |
|---|---|---|---|---|
| `AirPicture` | 2 | 1099 | `air-picture-ready` | The air picture: observation only. |
| `HALThreatCoverage` | 6 | 1109 | `hal-threat-coverage-ready` | Threat coverage, on the Emerging Threats Budget. |
| `SPAAOverwatch` | 1 | 427 | `spaa-overwatch-ready` | SPAA overwatch: the one exception to "HAL owns employment". |
| `RearBaseCRAM` | 2 | 382 | `rear-base-cram-ready` | Rear-base C-RAM. |
| `FOBAirDefence` | 1 | 322 | `fob-air-defence-ready` | AA teams garrison FOBs. |
| `HotDrop` | 5 | 637 | `hot-drop-ready` | HotDrop: the troop-insertion profile. |
| `HALParadrop` | 1 | 143 | `hal-paradrop-ready` | _no in-source header_ |
| `ThunderRunAirTiers` | 1 | 147 | `thunder-run-air-tiers-ready` | Helicopter threat tiers, applied to Thunder Run's air denial. |
| `HALCargoDiceFix` | 1 | 226 | `hal-cargo-dice-fix-ready` | HAL's troop-lift dice, replaced by the helicopter threat tiers. |
| `HALDispatcherAAFix` | 1 | 198 | `hal-dispatcher-aa-fix-ready` | RYD_Dispatcher weighs an aircraft's AA risk against the wrong threat list. |

### Ground doctrine

| module | v | lines | ready flag | what it does (its own words) |
|---|---|---|---|---|
| `Colossus` | 3 | 576 | `colossus-ready` | COLOSSUS - the strategy layer. |
| `HALFront` | 2 | 266 | `hal-front-ready` | HAL front for both commanders. |
| `HALReconLatch` | 1 | 193 | `hal-recon-latch-ready` | RydHQ_ReconDone, latched. |
| `HALWaypointGuardFix` | 1 | 160 | `hal-waypoint-guard-ready` | HAL drops a capture waypoint when _wp0 is not defined. |
| `HALDispatcherSoftArmorFix` | 1 | 244 | `hal-soft-armor-fix-ready` | Trucks drive up to tanks because only armour ever checks for armour. |
| `HALTaxonomy` | 1 | 294 | `hal-taxonomy-ready` | One owner for "what does HAL think this vehicle is". |
| `ArtilleryScoot` | 1 | 252 | `artillery-scoot-ready` | Shoot and scoot. |
| `CounterBattery` | 1 | 281 | `counter-battery-ready` | Counter-battery: working out where the shelling came from. |
| `ArtilleryCertification` | 1 | 158 | `–` | _no in-source header_ |
| `SOFDoctrine` | 1 | 355 | `sof-doctrine-ready` | Shared SOF identity + C.L.A.S.H. |
| `ReconPlanningBridge` | 4 | 199 | `recon-planning-bridge-ready` | C.L.A.S.H. |
| `ReconObserver` | 6 | 400 | `recon-observer-ready` | C.L.A.S.H. |
| `HALNativeSFFix` | 4 | 495 | `native-sf-fix-ready` | _no in-source header_ |
| `InfantryAuthority` | 4 | 323 | `infantry-authority-ready` | Persistent infantry authority doctrine HAL owns tactical behavior for every server-local, fielded enemy infantry formation. |
| `InfantryAuthorityAllocationFix` | 2 | 338 | `infantry-allocation-authority-ready` | Persistent allocation authority correction. |
| `InfantryDemand` | 2 | 220 | `infantry-demand-ready` | _no in-source header_ |
| `FormationRecovery` | 1 | 148 | `formation-recovery-ready` | _no in-source header_ |
| `AttackRestore` | 1 | 152 | `attack-restore-ready` | Give a squad its weapons back after the medics are done with it. |

### Sustainment and recovery

| module | v | lines | ready flag | what it does (its own words) |
|---|---|---|---|---|
| `Resupply` | 2 | 1750 | `resupply-ready` | One owner for "HAL let this unit run dry and nothing is coming". |
| `GTFO` | 4 | 555 | `gtfo-hal-withdrawal-ready` | GTFO authority doctrine HAL = tactical commander. |
| `GTFO_Bookkeeping` | 3 | 169 | `gtfo-bookkeeping-ready` | GTFO does not cancel HAL tactics. |
| `GTFO_Runtime` | 4 | 473 | `gtfo-recon-guard-ready` | Late-bound GTFO adapters. |
| `CASEVAC` | 5 | 840 | `casevac-ready` | _no in-source header_ |
| `CASEVAC_AirOpsFix` | 3 | 194 | `casevac-air-ops-fix-ready` | _no in-source header_ |
| `CASEVAC_HomeRTB` | – | 101 | `casevac-home-rtb-ready` | _no in-source header_ |
| `CASEVAC_LZPadFix` | 2 | 133 | `casevac-lz-pad-fix-ready` | _no in-source header_ |
| `GroundMEDEVAC` | 3 | 362 | `ground-medevac-ready` | _no in-source header_ |
| `GroundMEDEVAC_Extraction` | – | 228 | `–` | _no in-source header_ |
| `GroundMEDEVAC_Manager` | – | 205 | `–` | _no in-source header_ |
| `GroundMEDEVAC_VehiclePolicy` | 3 | 328 | `ground-medevac-vehicle-policy-ready` | Ground MEDEVAC vehicle policy C.L.A.S.H. |
| `EvacBoardingFix` | 1 | 427 | `evac-boarding-fix-ready` | _no in-source header_ |
| `RemnantEvac` | – | 12 | `–` | _no in-source header_ |
| `CrewRemnantCleanup` | 1 | 158 | `crew-remnant-cleanup-ready` | _no in-source header_ |
| `ReconstitutionDispatchFix` | 6 | 333 | `reconstitution-dispatch-fix-ready` | _no in-source header_ |
| `ReconstitutionTransitFix` | 5 | 373 | `reconstitution-transit-fix-ready` | _no in-source header_ |
| `ThunderRun` | 4 | 441 | `thunder-run-enhancements-core-not-ready` | Enhancement layer over the proven Thunder Run core. |
| `ThunderRun_Core` | 2 | 1452 | `thunder-run-ready` | Use HAL's intelligence lists and HAL's own point-to-segment geometry. |
| `ThunderRun_Tuning` | 1 | 356 | `thunder-run-tuning-ready` | Live-burn tuning layer. |
| `HALLogistics` | 10 | 586 | `hal-logistics-ready` | _no in-source header_ |
| `LogisticsGuard` | 4 | 319 | `logistics-guard-ready` | _no in-source header_ |
| `AmmoDispatch` | 1 | 113 | `ammo-dispatch-ready` | Call-site provenance is explicit. |
| `ServiceAuthority` | 3 | 241 | `service-authority-ready` | _no in-source header_ |
| `ServiceLifecycle` | 4 | 414 | `service-lifecycle-ready` | Field transport enrollment is installed by ServiceAuthority after the DualHAL handoff. |
| `ServiceStability` | 5 | 336 | `service-stability-ready` | Compatibility shim for callers from older service-authority revisions. |
| `ServiceCapacityPolicy` | 1 | 189 | `service-capacity-policy-ready` | _no in-source header_ |
| `ServiceExecutionGuards` | 1 | 167 | `service-execution-guards-ready` | _no in-source header_ |
| `ServiceHomeResolver` | 3 | 449 | `service-home-resolver-ready` | Transient groups such as player-flown HAL carriers are not service-pool assets, but HAL still consumes START+str(group) as its RTB input. |

### Player-facing

| module | v | lines | ready flag | what it does (its own words) |
|---|---|---|---|---|
| `PlayerTaskRequests` | 3 | 398 | `player-task-request-router-ready` | _no in-source header_ |
| `PlayerTaskRequestBootstrap` | 3 | 64 | `player-task-request-bootstrap-ready` | _no in-source header_ |
| `PlayerTaskRequestMenu` | 2 | 208 | `player-task-request-menu-ready` | _no in-source header_ |
| `PlayerTaskRequestRecon` | 1 | 475 | `player-task-request-recon-ready` | How long a contact must be absent from HAL's knowledge before it counts as lost. |
| `PlayerTaskRequestStrike` | 3 | 473 | `player-task-request-strike-ready` | _no in-source header_ |
| `PlayerTaskRequestStrikeClassifierV2` | 2 | 249 | `strike-classifier-v2-ready` | _no in-source header_ |
| `PlayerTaskRequestArtillery` | 2 | 417 | `player-task-request-artillery-ready` | _no in-source header_ |
| `PlayerTaskClient` | – | 260 | `–` | _no in-source header_ |
| `PlayerTaskSupport` | 2 | 1185 | `player-task-support-ready` | _no in-source header_ |
| `PlayerTaskStateHardening` | 3 | 473 | `player-task-state-admission-ready` | _no in-source header_ |
| `PlayerDemandDispatch` | 1 | 944 | `player-demand-dispatch-ready` | _no in-source header_ |
| `PlayerDemandNativeInterceptors` | 10 | 408 | `player-demand-native-interceptors-ready` | _no in-source header_ |
| `PlayerDemandReservationHardening` | 1 | 499 | `player-demand-reservation-hardening-ready` | _no in-source header_ |
| `PlayerDemandExecutionHardening` | 1 | 113 | `player-demand-execution-hardening-ready` | _no in-source header_ |
| `PlayerDemandAmmoValidityHardening` | 2 | 102 | `player-demand-ammo-validity-hardening-ready` | _no in-source header_ |
| `PlayerTransportAuthority` | 4 | 292 | `player-transport-authority-ready` | _no in-source header_ |
| `PlayerTransportNativeBridge` | 7 | 516 | `player-transport-native-bridge-ready` | HAL_SCargo is a complete transport executor, not merely a carrier selector: it reserves the carrier, moves it to pickup, assigns cargo seats, waits for embarkation, owns the transport… |
| `PlayerTransportRTB` | 3 | 322 | `player-transport-rtb-ready` | _no in-source header_ |
| `PlayerCarrierHome` | 3 | 164 | `player-carrier-home-ready` | _no in-source header_ |
| `PlayerEmploymentMenu` | 2 | 290 | `player-employment-menu-ready` | _no in-source header_ |
| `PlayerGarageDeployment` | 3 | 382 | `player-garage-artillery-ready` | _no in-source header_ |
| `PlayerArtilleryTasks` | 1 | 635 | `player-artillery-tasks-ready` | _no in-source header_ |
| `PlayerArtillerySideMarker` | 1 | 147 | `player-artillery-side-marker-ready` | _no in-source header_ |
| `CommanderParity` | 2 | 818 | `commander-parity-ready` | C.L.A.S.H. |
| `HALTransportAudio` | 2 | 154 | `hal-transport-audio-ready` | _no in-source header_ |

### Diagnostics

| module | v | lines | ready flag | what it does (its own words) |
|---|---|---|---|---|
| `DebugPreflight` | 1 | 324 | `debug-preflight-ready` | The preflight report. |
| `CombatDiagnostics` | 4 | 589 | `combat-diagnostics-ready` | Temporary C.L.A.S.H. |
| `LoudDebug` | 1 | 259 | `loud-debug-ready` | The loud debugger. |
| `TestComms` | 1 | 237 | `test-comms-ready` | Temporary testing comms surface. |


---

## 7. Documentation debt

50 of 104 modules carry no in-source design header, so
this document cannot describe them without guessing, and does not try.
They are listed here so the gap is visible rather than implied. Several
are large and load-bearing — `DualHALCheckbook` at 1422 lines and
`HALLogistics` at v10 are the two that most deserve a header.

- `ArtilleryCertification`
- `CASEVAC`
- `CASEVAC_AirOpsFix`
- `CASEVAC_HomeRTB`
- `CASEVAC_LZPadFix`
- `CrewRemnantCleanup`
- `DualHALCheckbook`
- `EvacBoardingFix`
- `FieldHardening`
- `FormationRecovery`
- `GroundMEDEVAC`
- `GroundMEDEVAC_Extraction`
- `GroundMEDEVAC_Manager`
- `HALLogistics`
- `HALNativeSFFix`
- `HALParadrop`
- `HALTransportAudio`
- `InfantryDemand`
- `LogisticsGuard`
- `PhysicalMovementPreInit`
- `PlayerArtillerySideMarker`
- `PlayerArtilleryTasks`
- `PlayerCarrierHome`
- `PlayerDemandAmmoValidityHardening`
- `PlayerDemandDispatch`
- `PlayerDemandExecutionHardening`
- `PlayerDemandNativeInterceptors`
- `PlayerDemandReservationHardening`
- `PlayerEmploymentMenu`
- `PlayerGarageDeployment`
- `PlayerTaskClient`
- `PlayerTaskRequestArtillery`
- `PlayerTaskRequestBootstrap`
- `PlayerTaskRequestMenu`
- `PlayerTaskRequestStrike`
- `PlayerTaskRequestStrikeClassifierV2`
- `PlayerTaskRequests`
- `PlayerTaskStateHardening`
- `PlayerTaskSupport`
- `PlayerTransportAuthority`
- `PlayerTransportRTB`
- `ReconstitutionDispatchFix`
- `ReconstitutionTransitFix`
- `RemnantEvac`
- `SeaGenerationGuard`
- `ServiceAuthority`
- `ServiceCapacityPolicy`
- `ServiceExecutionGuards`
- `SpawnArchetypePreInit`
- `VehicleEchelonPolicy`

---

## 8. Kill switches and key settings

Every doctrine that mutates the war can be turned off without a revert. Set any
of these in `description.ext` `class Params` or the mission namespace.

| variable | effect when set |
|---|---|
| `ITW_CLASH_ColossusAdvisoryOnly = true` | COLOSSUS logs `would-order` and stops issuing orders; the parity layer's own ternary resumes ownership |
| `ITW_CLASH_HALTaxonomyAdvisoryOnly = true` | taxonomy logs `would-classify` and writes no bucket; HAL's autofill keeps authority |
| `ITW_CLASH_ColossusEnabled = false` | no ground picture at all |
| `ITW_CLASH_RearBaseCRAMEnabled = false` | no rear-base air defence |
| `ITW_CLASH_RearBaseCRAMRespawn = 0` | a rear base cleared of air defence stays cleared |
| `ITW_CLASH_ResupplyGFRHold = false` | claimed vehicle groups withdraw to a rally (v1 behaviour) instead of holding |
| `ITW_CLASH_FOBAirDefenceYieldToSPAA = false` | FOB air defence stops deferring to mobile overwatch |
| `ITW_CLASH_HotDropStates` | which corridor verdicts HotDrop will claim a lift for |
| `ITW_CLASH_HotDropNoLandStates` | corridors where a refused paradrop aborts rather than landing |
| `CLASHDebug` (param) | 0 off, 1 preflight to chat, 2 full loud debug |

Tuning worth knowing about:

| variable | default | why that value |
|---|---|---|
| `ITW_CLASH_MinAnchorSoldiers` | 6 | relaxes toward `ITW_CLASH_AnchorFloorMinimum` (3) per `AnchorFloorRelaxInterval` (120 s) while a refill is pending |
| `ITW_CLASH_ResupplyPatience` | 120 s | 30 s for repair, 0 s when immobilised |
| `ITW_CLASH_ColossusOrderDwell` | 120 s | twice the poll, so feasibility cannot flap the order |
| `ITW_CLASH_SpotTimeMin/Max` | 0.6 / 0.8 | rolled per unit, so a side's reaction time is a spread rather than a constant |
| `RydxHQ_NEAware` | 1500 | set by C.L.A.S.H.; widens what a commander counts as a near enemy |
| `ITW_CLASH_RoadDistanceMaxNodes` | 300 | a floor now; the budget scales at `NodesPerMetre` (0.35) capped at 2000, because 300 could not reach 2.2 km |
| `ITW_CLASH_AirPictureObservedRadius` | 800 | decides whether a corridor is honestly `UNKNOWN` |

---

## 9. Open work

Carried deliberately, with the reason.

**Artillery block.** Tier purchasing mapped to AI skill, two-pot funding (gun #1
from Impasse, extras from the ETB), two guns per side. Two known rebuy defects:
the cooldown anchors to the *purchase* rather than the loss, so a gun killed
thirty seconds after it arrives leaves the side without artillery for ~4.5
minutes while a late attrition kill is replaced at once; and a bailed crew blocks
the rebuy entirely because `UsableGroups` tests `vehicle leader`, which for a
dismounted crew is the man, who is alive and `canMove`. Veterancy randomisation
is pinned pending the SF counter-battery raid as its counterplay. Recorded in
`docs/EMERGING_THREATS_BUDGET.md`.

**SF counter-battery raid.** Designed, unbuilt. The counterplay that would
unpin artillery veterancy.

**AT teams as an ETB provider.** Pinned, with the design and the reasoning in
`docs/EMERGING_THREATS_BUDGET.md`. Two decisions made (two-man team, price
derived from the cheapest AT vehicle row), three triggers rejected, and two open
items: persistent-pain scoring, which should be settled by an observation-only
tracker before anything mutates; and guided-versus-unguided AT, which must be
config-derived because the requirement came from porting to a new faction.

**AT overwatch on terrain.** The doctrine that would counter armour sitting on
elevation interdicting a corridor. Sized at ~200 lines advisory (score terrain,
log `would-place`, mutate nothing) then ~450–550 to act. Not started; the
advisory half should go first because the hard question is whether a ridgeline
C.L.A.S.H. picks is actually a ridgeline.

**Unexplained in run 4.** Artillery moved to the front and nothing we own
accounts for it — `ArtilleryScoot` and `AttackRestore` both logged only `ready`,
and the `ITW_ObjIdx` mirror in `InfantryAuthority` is bookkeeping that moves
nothing. Not diagnosed.

**Unverified classification.** Whether `B_AFV_Wheeled_01_cannon_F` resolves to
`Wheeled_APC_F` or `Car`, which decides whether the Rooikat reads grade 1 and is
promoted into HAL's anti-armour pool or grade 0 and correctly left alone. Arma
config inheritance is not readable outside the game; the
`hal-taxonomy-classified` log answers it on the next run.

**Five groups awaiting orders 3–5 km back** (run 4). Not an audit bug — the live
allocation audit never releases by design. They were free, unassigned and never
tasked, which makes it a tasking question that COLOSSUS v3 may already have
changed.

---

## 10. Testing

`python -m pytest -q tests` — ~900 tests, source-level: they read the SQF and
assert structure, ordering and invariants rather than executing it. There is a
standing baseline of pre-existing failures; the discipline is that a change adds
none, checked by diffing the failure list against a stashed baseline rather than
by eyeballing a count.

Tests here are written to **track intent, not text**. When a change invalidates
one, the test is updated to assert the new intent and the old reasoning is kept
in its docstring — several carry the specific run and number that motivated them,
which is why they are worth reading alongside this document.
