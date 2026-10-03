# Emerging Threats Budget

HAL's threat purchases almost never succeeded: in the 81-minute peer run of
2026-09-25, commander B asked for a counter 80 times and got 2, and 4 of 117
threat purchases went through across both commanders. CLASH's checkbook shared
Impasse's per-row tickets with Impasse's own vehicle spawner, and the spawner
spends every affordable ticket first. Each commander now has a separate
Emerging Threats Budget (ETB) on top; Impasse's economy is untouched.

Design and decisions: the CLASH Checkbook Problem and Emerging Threats Budget
document. This file records what shipped and what to look for in an RPT.

## What shipped, in build order

Each phase is its own commit and can be shipped on its own.

| Phase | File | What it does |
| --- | --- | --- |
| 1 | `ITW_CLASH_HALDispatcherAAFix.sqf` | Runtime text patch of `RYD_Dispatcher` so the AIR branch measures AA risk against `_AAthreat`, not the nearest tank (`HAC_fnc.sqf:1730`). Nothing under `NR6 Hal/` changes. |
| 2 | `ITW_CLASH_AirPicture.sqf` | Observation only, on a 5-second clock, using HAL's own `knowsAbout >= 0.05` test. Also owns every classification from the vehicle: armored threat, combat aircraft, SPAA, air defence weight and umbrella, helicopter threat tier, corridor state. |
| 3 | `ITW_CLASH_EmergingThreatsBudget.sqf` | The ledger: income, prices, reserve, row and safety limits, reservations, escrow, living assets, write-offs, idle release, authorization, logging. |
| 4 | `ITW_CLASH_HALThreatCoverage.sqf` (rewritten), plus the ETB section of `ITW_CLASH_ForceGeneration.sqf` | Demand, coverage and the purchase transaction. |
| 5 | `ITW_CLASH_SPAAOverwatch.sqf` | Every SPAA on a side, the ETB's and Impasse's alike, stays behind the front. |
| follow-on | `ITW_CLASH_RearBaseCRAM.sqf` | One static air defence piece per side at the rear base, outside HAL and unbilled, replaced 5 minutes after it dies. |
| follow-on | `ITW_CLASH_FOBAirDefence.sqf` | Walks an idle AA squad to each FOB and hands it to HAL's own garrison routine on arrival. |
| tiers | `ITW_CLASH_ThunderRunAirTiers.sqf` | Only a hard-kill system closes a resupply corridor; relaxes Thunder Run's blunt air denial, never tightens it. |
| tiers | `ITW_CLASH_HALCargoDiceFix.sqf` | Replaces HAL's map-wide lift coin flip (`SCargo.sqf:186`) with the route's own corridor verdict. |
| tiers | `ITW_CLASH_HotDrop.sqf` | The troop-insertion profile: low, fast, pop up, put the infantry out, egress. Separate from the logistics run. |
| debug | `ITW_CLASH_LoudDebug.sqf` | Mirrors air and budget decisions to in-game chat in plain language. Off by default. |

A helicopter is never `HARD_KILL`, whatever it carries: an enemy gunship opens
counter-air demand like any other combat aircraft, but it is treated as a CAS
jet and never closes a corridor. Only fixed-wing interceptors do that.

Not built, and deliberately: the one-purchase overdraft on a full reserve
(decision 7), which is still Hark's call. Follow-on work — AA teams garrisoning FOBs, the rear-base C-RAM,
the aircraft sortie fix, troop helicopters on the Thunder Run profile — ships
separately. The air picture already classifies and weights a C-RAM and the
tiers, so those land on rules that exist.

## What the ETB is not

- It never reads, spends, reserves or edits an Impasse ticket.
- Its assets never carry `ITW_VehDef`, so they never count against Impasse's
  caps. Every reader of `ITW_VehDef` is audited in the ledger file's header and
  in `tests/test_emerging_threats_budget.py`.
- It never decides that a commander should own something: HAL creates the
  demand, through threat coverage.
- It never employs anything. The one exception is SPAA, which CLASH places in
  overwatch and never sends forward.
- Logistics and transport keep using Impasse's cheap transport rows, which
  worked in the test run (70 approved to 2 denied).

## Settings

| Setting | Default |
| --- | --- |
| `ITW_CLASH_ETBEnabled` | `true` |
| `ITW_CLASH_ETBDryRun` | `false` |
| `ITW_CLASH_ETBIncomeScale` | `1` |
| `ITW_CLASH_ETBStartingReserve` | `40` |
| `ITW_CLASH_ETBCapacity` | `80` |
| `ITW_CLASH_ETBRowLimitScale` | `1` |
| `ITW_CLASH_ETBSafetyLimit` | `6` |
| `ITW_CLASH_ETBGroundInterval` | `90` s |
| `ITW_CLASH_ETBIdleRelease` | `480` s |
| `ITW_CLASH_ETBCrewWriteOff` | `300` s |
| `ITW_CLASH_ETBImmobileWriteOff` | `600` s |
| `ITW_CLASH_AirPicturePoll` | `5` s |
| `ITW_CLASH_AirPictureSightingGrace` | `15` s |
| `ITW_CLASH_AirPictureIgnoreFront` | `true` |
| `ITW_CLASH_ThreatCoverageGroundPersistence` | `90` s |
| `ITW_CLASH_ThreatCoverageFailureMemory` | `600` s |
| `ITW_CLASH_SPAAOverwatchStandoff` | `1500` m |
| `ITW_CLASH_RearBaseCRAMEnabled` | `true` |
| `ITW_CLASH_RearBaseCRAMRespawn` | `300` s |
| `ITW_CLASH_FOBAirDefenceEnabled` | `true` |
| `ITW_CLASH_FOBAirDefenceArrival` | `75` m |
| `ITW_CLASH_FOBAirDefenceIncludeRear` | `true` |
| `ITW_CLASH_HALFrontIncludeForward` | `false` |
| `ITW_CLASH_HALFrontIncludeRear` | `false` |
| `ITW_CLASH_HALFrontIncludeArtillery` | `false` |
| `ITW_CLASH_ThunderRunAirTiersEnabled` | `true` |
| `ITW_CLASH_HALCargoDiceEnabled` | `true` |
| `ITW_CLASH_HotDropEnabled` | `true` |
| `ITW_CLASH_HotDropStates` | `["CONTESTED","HOT","AIR_DENIED"]` |
| `ITW_CLASH_HotDropTakeoverRadius` | `3000` m |
| `ITW_CLASH_HotDropIngressHeight` | `25` m |
| `ITW_CLASH_HotDropDropHeight` | `130` m |
| `ITW_CLASH_AirPictureDenialMobileCycles` | `3` HAL cycles |
| `ITW_CLASH_AirPictureDenialMobileFloor` | `480` s |
| `ITW_CLASH_AirPictureDenialStaticValve` | `1200` s |
| `ITW_CLASH_AirPictureDenialFighterSeconds` | `180` s |
| `ITW_CLASH_AirPictureLossRadius` | `2500` m |
| `ITW_CLASH_AirPictureLossClosure` | `600` s, doubling to `2400` |
| `ITW_CLASH_LoudDebugEnabled` | `false` |
| `ITW_CLASH_LoudDebugSources` | `[]` (all) |
| `ITW_CLASH_LoudDebugRepeat` | `8` s |

`ITW_CLASH_ETBDryRun = true` runs the whole economy and every decision and buys
nothing: each authorization logs the purchase it would have made. Use it for the
first live run of phase 3.

## The front decides what the ETB may answer

HAL's dispatcher scores any threat outside a commander's front zero
(`HAC_fnc.sqf:1485`), so a counter bought for an out-of-front threat is never
tasked. Anti-armor demand is therefore filtered by the front; counter-air demand
is not, because aircraft cross a front in seconds and the coverage count and the
helicopter corridors need all of them — instead the provider choice narrows to
SPAA, the one provider CLASH places itself.

The front now anchors on the contested objectives alone (plus
`ITW_CLASH_HALFrontMargin`). That is deliberate: our own artillery inside our own
front meant the main force answered enemy SF raids on the gun line, and HAL's SF
routine ignores the front entirely. The consequence for the ETB is direct — a
tighter front means fewer answerable armor threats and less spending. If a run
shows the ETB idle with armor on the field, check whether those threats are
outside the front before looking at the ledger.

## Corridor timers run on HAL's clock, not the wall's

A corridor stays shut after a hard-kill system was last seen, and those timers
are measured in **HAL cycles** rather than minutes. The corridor reads HAL's own
knowledge list, and HAL refreshes it exactly once per cycle — `(groups × 5) +
((10 + groups) / (0.5 + reflex)) × commDelay` seconds, about 2.2 minutes at 20
groups and 4.2 at 40. A flat three-minute timer would be *shorter than one
cycle* in a large game, so a route could reopen before HAL had a chance to look
again. HAL publishes the figure as `RydHQ_myDelay`; that is what gets read,
so the timers follow the commander's reflex and comms delay too.

| Threat | Rule |
| --- | --- |
| Mobile hard-kill AA | 3 HAL cycles **and** never under 8 minutes |
| Static SAM site | closed until the site is dead; a 20-minute valve covers one that died unseen |
| Fighter | 3 minutes while the air picture scans faster than a cycle, otherwise one full cycle |
| Loss counter | 2 losses within 2.5 km inside 10 minutes; closure doubles on a repeat inside 30 minutes, to a 40-minute cap |

Seeing a threat again resets its timer, a threat known dead reopens its corridor
at once, and flights already under way are never recalled.

## Watching a run from inside the game

The RPT is the record afterwards and useless while you are standing in the field
watching a corridor close, so every air and budget decision can also be spoken
in plain language to in-game chat:

```
CLASH: AIR CORRIDOR CLOSED BY B_APC_Tracked_01_AA_F (MOBILE_AA) at 4821,7190 - commander A, holds 480s
CLASH: AIR CORRIDOR OPENED - O_SAM_System_04_F (STATIC_SAM) dead after 12s unseen - commander B
CLASH: HELICOPTER LIFT REFUSED - route 3100,6050 to 4790,7210 is AIR_DENIED (recent-losses) - commander B
CLASH: B_APC_Tracked_01_AA_F RESERVED FOR BACKLINE AA - overwatch, never dispatched - commander B
CLASH: ETB REFUSED CAP_AIRCRAFT - ETB_RESERVE_CAP - commander B
```

Turn it on with `ITW_CLASH_LoudDebugEnabled = true`, or mid-mission from the
debug console with `[true] call ITW_CLASH_LoudDebug_fnc_Toggle`. Narrow it to
one subsystem with `ITW_CLASH_LoudDebugSources = ["air-picture"]`. It is a
formatter on the tail of logging that already happened — it cannot change a
decision, and every line is mirrored to the RPT prefixed `CLASH LOUD |` so a
screenshot and the log line up afterwards.

An event with no written sentence is still spoken, in a generic uppercase form,
rather than silently dropped.

## Reading a run

Boot lines, one per phase:

```
CLASH BOOT | hal-dispatcher-aa-fix-ready | patched=true ...
CLASH BOOT | air-picture-ready | poll=5 grace=15 ...
CLASH BOOT | etb-ready | dryRun=false start=40 capacity=80 rate=...
CLASH BOOT | hal-threat-coverage-ready | needs=ANTI_ARMOR,COUNTER_AIR ...
CLASH BOOT | spaa-overwatch-ready | standoff=1500 ...
```

Every purchase can be explained from four lines:

```
CLASH ETB | B | cash=31 living=38 reserve=69/80 income=1.20/min assets=1 pending=CAP_AIRCRAFT
CLASH ETB DENIED | B | CAP_AIRCRAFT | INSUFFICIENT_ETB | [27.8,42,14.2,11.8]
CLASH ETB PURCHASE | B | CAP_AIRCRAFT | B_Plane_Fighter_01_F | row=PLANE/ATTACK | cost=42 | cash 53->11 | living 0->42 | threat=G145
CLASH ETB LOSS | B | B_Plane_Fighter_01_F | cost=42 | living 42->0 | reserve 53->11 | no refund | destroyed
```

Denial reasons are one closed vocabulary: `NO_CANDIDATE`, `PROGRESSION_LOCKED`,
`AIRPORT_REQUIRED`, `COST_EXCEEDS_CAPACITY`, `INSUFFICIENT_ETB`, `ETB_ROW_CAP`,
`ETB_RESERVE_CAP`, `SAFETY_LIMIT`, `PACING`, `ACTIVE_RESPONDER`,
`IDLE_RESPONDER_REOFFERED`, `THREAT_GONE`, `SPAWN_FAILED`,
`HAL_REGISTRATION_FAILED`.

A warning rather than a failure on any of these is expected and harmless: the
dispatcher patch reporting `already-fixed`, or any module logging
`...-missing-or-prereq-failed`, which leaves the previous behaviour in place.

## Why nothing was attacking: RydHQ_ReconDone

Found in the first real run, and the reason a commander could sit on 29 groups
with two attack-available and almost never push.

HAL will not issue a capture order unless `RydHQ_ReconDone` is true
(`HQOrders.sqf:775-777`). The only alternative branch is a dice roll -
`RapidCapt` (10, `HQSitRepF.sqf:389`) times `Recklessness + 0.01` (0.5, set by
`ITW_CLASH.sqf:418`) - about **5.1% per HAL cycle**. GUER ran ten cycles in
twenty minutes, so roughly a 40% chance of a single capture order in the whole
run.

Three things hold the flag down, and only the third is ours:

1. **HAL only scouts while completely blind.** `HQOrders.sqf:356` gates the
   entire recon dispatch block - every tier, `RAirG`, `reconG`, `FOG`,
   `snipersG` - on `count RydHQ_KnEnemiesG == 0`. After first contact,
   `RydHQ_ReconStage` can never climb, so `GoRecon.sqf:732` can never set the
   flag.
2. **`HAL_HQReset` clears it unconditionally** (`HQReset.sqf:17-18`). It resets
   `ReconStage` but *not* `ReconStage2`, which is the fingerprint this was
   diagnosed by.
3. **C.L.A.S.H. runs that reset every 30 seconds** (`ITW_CLASH.sqf:2337`)
   against HAL's own default of 600 (`HQSitRepF.sqf:434`).

The run's own timeline, from `CLASH DIAG | hq-state`:

```
23:17:38  stage 1, 0 known    recon starts
23:18:44  stage 4, 0 known    recon complete, flag earned
23:22:56  stage 1, 5 known    reset wiped it; contact made; gate now shut
23:25:37+ stage 1, 5-6 known  dead for the rest of the run
```

`ReconStage2` stays pinned at 4 from 23:18 onward while `ReconStage` sits at 1.
Nothing in HAL but `HQReset` does that.

`ITW_CLASH_HALReconLatch.sqf` holds the flag up while a commander has contact.
The rule is the flag's own meaning - `ReconDone` says "I have scouted enough to
attack", and a commander that knows where five enemy groups are has scouted
enough by any reading. It counts `RydHQ_KnEnemiesG`, the same thing the gate
counts, so it cannot disagree with the gate it is reasoning about.

It is a latch, not a controller: it **only ever writes true**, which is
asserted. When a commander goes blind again it stands off and leaves the flag
as HAL left it, so HAL's own recon loop can run and set it the ordinary way - a
commander that has genuinely lost the enemy should scout again, and clearing
the flag ourselves would be us making that call instead of HAL.

It polls every 10 s, which has to stay under `RydHQ_ResetTime`, and that
relationship is asserted rather than assumed. The first latch is announced at
once; the relatches (one every 30 s, forever, because the reset keeps coming)
are summarised every 5 minutes instead of twice a minute.

**`RydHQ_ResetTime = 30` has deliberately not been changed.** Raising it would
widen the window in which a pre-contact recon still counts, but it cannot fix
the trap - after first contact the flag is unearnable at any interval. Whoever
set it to 30 did so for a reason worth knowing before moving it.

## HotDrop claims at boarding, not in the air

The first run flew a full contested-corridor profile for an empty helicopter
and reported success. The cause was the acquisition model, not a missing
check.

v1 polled every helicopter on the map every 10 seconds, took any that was
airborne, had someone aboard and was within 3 km of a destination, and never
asked whose lift it was:

```
23:26:49  B Alpha 3-3 dispatched        AAInf
23:28:36  native SF paradrop SELECTED   carrier + Alpha 3-3 -> [4014,12391]
23:28:49  HotDrop CLAIMED the same pair -> [4891,10511]   (2.1 km away, 13s later)
23:30:57  put-out LAND_FALLBACK, nobody aboard
23:30:58  handback COMPLETE after 129s
```

`ITW_CLASH_HALNativeSFFix.sqf:147` had already selected that carrier and cargo
pair for an SF insertion. Thirteen seconds later a map-wide scan found the same
aircraft airborne and flew it somewhere else. DROP to EGRESS took zero seconds,
which is the tell: the drop phase's own occupancy test exited immediately.

v2 claims on the ground, before takeoff, and decides once:

- **Boarding window.** Only aircraft at or below `ITW_CLASH_HotDropBoardingHeight`
  (3 m) are considered. v1's altitude test was the exact inverse - it skipped
  anything on the ground as "still loading or already finished".
- **One owner.** A crew group that already carries
  `ITW_CLASH_HALParadropCargoGroup` belongs to someone else and is left alone.
  That marker answers for the native SF insertion path and for HotDrop itself.
- **Loaded, not assigned.** The claim now runs the same occupancy test the DROP
  phase uses, so an empty aircraft can never be taken. Still boarding is the one
  rejection that does *not* mark the lift declined.
- **Declined is final.** The corridor is read once at boarding. A lift that
  launches into a quiet corridor stays HAL's even if it sours, and one that
  launches into a bad corridor flies the profile even if the corridor clears.
  Air defence is identified reactively, so a cautious profile flown into a
  corridor that turns out to be cold costs nothing worth a second decision.

Two defects found alongside it:

- **`LAND_FALLBACK` did not land.** `ITW_CLASH_HALParadrop_fnc_Execute` returns
  false from five places and lands for itself in exactly one of them - too low,
  at `HALParadrop.sqf:110`. HotDrop called every false a fallback landing and
  returned success, so troops could fly home still aboard with the log saying
  they were delivered. It now lands for real unless they are already out.
- **The put-out sentence was misindexed**, printing `at m`: the format string
  referenced `%4` with three arguments. The `LAND` branch also logged the
  unload *setting* in the slot the sentence labels as metres; both paths now
  report a real altitude.

## One mobile AA in the back line

The first run left one commander holding two Cheetahs behind the front and the
other holding one, all three idle. Neither of the pair was bought - the ETB
made no SPAA purchase at all that run. Both came from Impasse's own spawner and
`ITW_CLASH_SPAAOverwatch_fnc_Sweep` adopted every SPAA it found, with no limit.

A second one adds no cover the first did not already have.
`ITW_CLASH_SPAAOverwatch_fnc_Sector` re-points the held SPAA at the nearest
known hostile aircraft every poll, so one vehicle already tracks the air
picture; a second just parks.

`ITW_CLASH_SPAAOverwatchMaxPerSide` (default `1`) is now the limit, enforced
inside `fnc_Adopt` so the sweep and a purchase cannot disagree about it.
Capacity is counted from the live roster rather than tracked, so a loss frees
the slot at the next sweep with nothing to go stale, and re-adopting a group
already held is not treated as a new hold.

`ITW_CLASH_HALThreatCoverage_fnc_ChooseProvider` drops SPAA from its options at
capacity and denies with `spaa-at-capacity`, since money spent on a vehicle the
doctrine would refuse to adopt buys an asset nothing employs. The gate runs
before the out-of-front branch, which would otherwise still buy one - that
branch exits early with SPAA as its only option.

**The trade is real.** Over the cap, a vehicle is left with HAL, and HAL has no
SPAA doctrine - it will dispatch it as armor. Raise the cap if spares are seen
dying forward. `over-cap` is logged once per change rather than once per poll,
so a side that permanently owns a spare says so once instead of every thirty
seconds for the whole mission.

## Capability match: price is not suitability

Over a 70 minute run the ETB made nine purchases. All nine were
`GROUND_ANTI_ARMOR`, and eight were the same `B_LSV_01_AT_F` - an unarmoured AT
buggy. Seven died. Average life was about eight minutes; the shortest was 28
seconds, bought at 23:43:18 and destroyed at 23:43:46. Roughly 43% of the run's
income went into vehicles that traded once at best.

`ITW_CLASH_Generation_fnc_ETBCandidates` sorted candidates cheapest first and
the buy took the first affordable one, so the ETB had a notion of price and
none of suitability. Lethality was never the problem - an AT missile kills a
tank from any chassis. Survival was.

`ITW_CLASH_AirPicture_fnc_ProtectionGrade` now grades a class 0 soft, 1
protected, 2 heavy, read from the vehicle like every other classification here:
`Tank` covers the tracked armour family, `Wheeled_APC_F` the wheeled carriers,
and the config `armor` value is the fallback for anything inheriting from
neither. Cached per class.

`ITW_CLASH_AirPicture_fnc_RequiredGrade` asks for one grade below the threat's
own. An IFV may answer a tank; a soft vehicle may not. Demanding a match would
price most factions out of answering armour at all.

The filter applies **only to `GROUND_ANTI_ARMOR`**. An aircraft's survival is
its corridor, which the air picture already rules on, and SPAA sits behind the
front by doctrine.

Price still decides *within* what is suitable - the sort is unchanged, and a
price above the reserve still falls back to a cheaper vehicle. It simply can no
longer fall back past the grade floor.

When the faction can field an AT vehicle but none that survives the threat, the
denial is `NO_SUITABLE_COUNTER` rather than `NO_CANDIDATE`, so the two cases
read differently in the log. Saying so beats spending the money on a vehicle
that trades once and leaves the armour alive - and the budget has the room:
the reserve sat at its 80/80 ceiling in 53 of 146 status lines that run.

## Rear-base C-RAM: static if the faction has one, its own AA vehicle if not

The module never worked. Over a 70 minute run it logged
`rear-cram-no-candidate` **134 times for each side - every poll from 23:17:13 to
0:24:15 - and emplaced nothing at all**. At 268 lines it was a third of
everything the loud debugger printed, drowning the instrument being used to
debug everything else.

It was not the startup race first suspected. `va_pStaticAAClasses` and
`va_eStaticAAClasses` are filtered by `isKindOf "StaticAAWeapon"`
(`VehicleArrays.sqf:712`), and these factions field none, so the pool was empty
permanently rather than briefly.

Static AA is still preferred. When there is none, the selection now falls back
to the faction's own AA vehicle from `va_pAAClasses` / `va_eAAClasses` - the
same substitution Impasse makes for itself at `VehicleArrays.sqf:734` - and
keeps only classes whose config says they can actually shoot at aircraft.

The vehicle is crewed exactly as a static is: **a gunner and no driver**. It
cannot be driven anywhere, so it behaves as the emplacement it is meant to be.
`ITW_CLASH_CRAM` then keeps `ITW_CLASH_SPAAOverwatch_fnc_Adopt` from taking it,
which matters twice over - an adopted C-RAM would consume one of the back
line's capped mobile-AA slots and be ordered to a sector it can never drive to.
The refusal is placed before the capacity test so it never costs a slot even
transiently.

Having nothing to emplace is now said **once per side**. The class pools do not
change mid-mission, so neither does the answer.

## COLOSSUS v2: CONSOLIDATE, still advisory

A commander that is drastically outnumbered should not be naming the next
objective to feed groups into one at a time - that is the slugfest COLOSSUS
exists to name. v2 adds a posture above the push ranking: **PUSH** or
**CONSOLIDATE**.

`ITW_CLASH_Colossus_fnc_Theatre` measures the whole theatre rather than an
objective, because the per-objective numbers already drive the push ranking and
this is the question the ranking cannot answer - whether to be pushing at all.
Everything the commander knows about, against everything it could send, counted
once per vehicle so an infantry squad in a truck does not inflate either side,
and excluding the same pools a push excludes.

`fnc_Posture` enters consolidation at `ITW_CLASH_ColossusConsolidateAt` (`1.5`)
and only leaves below `ITW_CLASH_ColossusReleaseAt` (`1.1`). **Two thresholds,
not one**: a commander sitting on a single line would consolidate and release on
alternate assessments and never do either. Knowing nothing is not a reason to
consolidate - a zero on either side is PUSH.

`fnc_RallyPoint` picks the objective the commander already holds most strongly,
so consolidating thickens a position rather than abandoning everything to start
again somewhere new.

**It still issues no orders.** The recommendation becomes `would-consolidate`
instead of `would-push`, and the only thing written anywhere is COLOSSUS's own
`ITW_CLASH_ColossusPosture` on the commander - never a HAL pool, which is
asserted. The posture change is logged once when it moves rather than every
assessment, so the moment it flips is visible instead of buried.

That staging is deliberate and matches the original plan: watch the trigger
fire on a real run before anything acts on it. Executing a consolidation is v1's
job and needs the hold lever (`RydHQ_Garrison`, verified as the only reliable
one - the capture pool at `HQOrders.sqf:778` subtracts `Garrison` but not
`NoAttack`).

## The preflight report

Fourteen modules publish their own boot line among roughly two hundred
`CLASH BOOT` lines, which makes "did it all load" an archaeology exercise.
`ITW_CLASH_DebugPreflight.sqf` collapses that into one block under a single
prefix. Grep the RPT for `CLASH PREFLIGHT`.

It runs three times: once at `ITW_CLASH_DebugPreflightDelay` seconds (default
`180`, long enough for the two scheduled runtime patches to have bound against
HAL), then every `ITW_CLASH_DebugPreflightRepeat` seconds (default `600`) so a
long run has checkpoints to diff, and on demand from the debug console via
`call ITW_CLASH_DebugPreflight_fnc_Now`.

Each module reads as one of three states:

- **READY** — loaded and bound. Ready modules are collapsed onto one line,
  because a healthy stack should not cost thirty lines of RPT.
- **WAITING** — loaded but not bound yet. The dispatcher AA fix and the cargo
  dice fix are scheduled against HAL's own bind, so WAITING is expected for the
  first minute or two and a problem after that.
- **MISSING** — never loaded. Printed with the consequence beside it, which is
  the line actually worth reading.

Then, per commander: HAL's cycle length first, because every corridor timer is
measured in it and a 90-second cycle and a 20-second cycle are different games;
then the front, group and known-enemy counts, the artillery count, the number
of live air denials, the ETB's own ledger line, and how many objectives COLOSSUS
has in its picture.

It is read-only and asserted to be: no `setVariable` anywhere in the file, no
dispatcher call, no purchase, no order. A diagnostic that can alter a run makes
every number it prints suspect. Set `ITW_CLASH_DebugPreflightEnabled = false`
to silence it entirely.

## Turning the debug output on from the lobby

**C.L.A.S.H. debug output**, in the mission parameters, next to the existing
HAL control mode:

| Level | What speaks |
| --- | --- |
| 0 — Off (RPT only) | Default. Everything still goes to the RPT. |
| 1 — Preflight summary in chat | One line per preflight pass: all modules ready, or how many are not. |
| 2 — Full | Level 1, plus the loud debugger's live decision chat - corridors opening and closing, SPAA reservations, ETB denials, the scoot and counter-battery exchange. |

`params.sqf` converts every class in the `Params` block into an
`ITW_Param<ClassName>` global and `init.sqf` waits for it before loading
anything, so `ITW_ParamCLASHDebug` is set before either reader needs it. Both
readers default it to `0` and type-check it, so a mission running without the
parameter stays quiet rather than erroring.

Nothing is lost by using the console instead: setting
`ITW_CLASH_LoudDebugEnabled` before `init.sqf` still overrides the parameter,
and `[true] call ITW_CLASH_LoudDebug_fnc_Toggle` still works mid-mission.

## What to check before trusting a run

- `hal-front-ready` reports `anchors=objectives`, and the armor demands you
  expect are inside it.
- `hal-dispatcher-aa-fix-ready` says `patched=true`. If it says
  `hal-dispatcher-aa-fix-failed`, HAL's dispatcher text changed and the anchor
  needs revisiting; stock HAL is still compiled and nothing else is affected.
- Both commanders open demands, and the anti-armor threat count matches what is
  actually on the field. If a Rhino or a Bobcat is counted wrongly, the
  classification in `ITW_CLASH_AirPicture.sqf` is what to look at, not HAL.
- Income is roughly `1.2` tickets/min at the test run's settings.
- `etb-class-rejected` lines mean a faction class promised a capability in
  config and did not deliver it on the ground; that class is skipped for the
  rest of the run.
- An `ETB_RESERVE_CAP` denial on a counter-air demand while armor counters are
  alive is the known open decision, not a bug.

## The artillery block: planned, not built

Nothing in this section exists in code yet. It is recorded so the decisions
behind it are not re-litigated when it is built.

### Two pots, and what each one buys

Artillery is not free today: `ITW_CLASH_ForceGeneration.sqf:571` debits Impasse
row tickets and counts the gun against its row max, and the provider re-checks
affordability after the spawn and deletes the gun if the budget moved. The
problem is that the price never binds. The default budget sits at maximum and
artillery has its own Impasse row, so the ticket a gun spends was never
competing with anything the commander wanted. The cost is idle, not absent.

The fix is an alternative use for the money, not a higher price:

- **Gun #1 per side stays Impasse-funded.** It is order of battle. Every side
  has artillery. This also keeps ETB invariant 3 intact, because a gun bought
  at boot against no observed enemy is exactly the speculative purchase the
  ETB refuses.
- **Guns past the first, and tier upgrades, draw on the ETB reserve.** A second
  gun now costs SPAA when the enemy brings jets, or an armor counter when they
  bring tanks. The trade is real and the ledger is genuinely scarce.
- **Replacing a crew the enemy killed is reactive**, so it funds from the ETB
  under the `COUNTER_ARTILLERY` need without straining invariant 3.

Two pots with different rules is the planning surface: the Impasse budget
fields the army, the ETB answers what the enemy actually did, and artillery
expansion is the first decision that makes the commander choose between them.

### Crew quality: randomised now, veterancy pinned

Quality is **rolled**, three tiers onto AI skill — poor `0.3`, good `0.6`,
elite `1.0`. Skill is the single derived source: the scoot odds and settle
delay in `ITW_CLASH_ArtilleryScoot.sqf` read from it, so an elite crew
displaces almost every time with no delay and a poor crew usually sits still.

The roll fires when a gun group **first appears in `RydHQ_ArtG` with no tier
stamped**, not at the moment of purchase. Two paths put guns in that pool:
`ITW_CLASH_ForceGeneration.sqf:395` for guns CLASH buys, and `HAC_fnc2.sqf:551`
where HAL sorts groups itself, which catches mission-start guns. Rolling at
purchase would miss every gun a side starts with. Stamp the tier on the group
and `setSkill` the crew; the group survives crew churn and scoot reads the
stamp.

The roll is not a lottery the AI can farm, because the purchase is gated on gun
count rather than on money. `ITW_CLASH_ForceGeneration.sqf:637` tops a side up
to `ITW_CLASH_ArtilleryMinimumPerSide` and buys nothing further, so a side
lives with the crews it drew. The full default budget does not let it re-roll;
only losing a gun does.

Rejected funding models, for the record:

- **Zone progression.** Time-based, not tactical. A side gets better guns for
  the clock running, which is not a decision anyone made.
- **Price tiers.** With the default budget at maximum, paying more is not a
  trade-off; the AI would always buy the best tier available.

**Pinned, not built: veterancy.** Crew quality earned by surviving the
counter-battery exchange instead of rolled — a crew that fires and lives until
the fix against it goes cold steps up, a crew that dies takes its skill with
it, and a crew that survives its gun carries veterancy to the next one. That
makes displacement a scored choice rather than a flavour setting. It is pinned
because it snowballs: the side winning the artillery duel compounds its lead.
Its counterplay is the SF counter-battery raid, which is designed and unbuilt —
a raid that kills a veteran crew forces a fresh roll. Revisit veterancy once
the raid exists.

### Two guns per side

`ITW_CLASH_ArtilleryMinimumPerSide` moves to `2`. Not for firepower: one gun
per side means a side either drew elite or it did not, so the tier system is
invisible in any single run, and two independent draws is the minimum that
shows a spread. It also means losing a gun degrades the battery instead of
deleting the capability, so the duel keeps running while a rebuy is pending,
and it gives the SF raid a choice of target instead of an on/off switch.

The setting's name lies — it is documented as a minimum and used as a hard cap.
Rename it when the block is built.

### Two rebuy defects to fix with it

- **The rebuy cooldown starts at the purchase, not at the loss.** A successful
  buy sets `retryAt = time + 300`, so a gun killed thirty seconds after it
  arrives leaves the side with no artillery for about four and a half minutes,
  while a late attrition kill is replaced at once. That is backwards from the
  counter-battery design, which should reward a successful raid rather than
  punish an early loss. The `+90` retry only applies after a *failed* request.
- **A bailed crew blocks the rebuy entirely.** `ITW_CLASH_Generation_fnc_UsableGroups`
  (`:604`) tests `vehicle leader _x`; with the crew dismounted that is the
  *man*, who is alive and `canMove`, so the group still counts as usable. The
  side has a wrecked gun, a crew standing beside it, and no rebuy.
  Immobilised guns are caught by `canMove`, abandoned ones are not.
