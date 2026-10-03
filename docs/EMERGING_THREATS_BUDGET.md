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
- **Decided once.** The corridor is read at boarding and not revisited. A lift
  that launches into a corridor it was allowed to fly keeps the profile even if
  the corridor changes under it.

### The destination is resolved at launch, not at boarding

Claiming at boarding fixed one bug and caused another. At the pickup point the
pilot's `expectedDestination` is still the LZ it just flew to, so the
destination read as **the aircraft's own position**. The only distance check
was a *maximum* - within `ITW_CLASH_HotDropTakeoverRadius` - and zero passes
that, so the profile ran in place: the helicopter landed, flared over the
pickup, lifted, and put the squad out in the air above where it had just
boarded.

The destination is no longer read at boarding at all. The lift is still claimed
there, which is what keeps one owner from wheels-up, and `fnc_Run` opens with a
LAUNCH wait that flies nothing until **all** of:

- the aircraft is above `ITW_CLASH_HotDropBoardingHeight` (actually airborne),
- its destination is at least `ITW_CLASH_HotDropMinRun` (600 m) from where the
  squad boarded, **and** at least that far from where the aircraft is now,
- and it is within `ITW_CLASH_HotDropTakeoverRadius` of that destination, so a
  long lift flies HAL's own route until the last leg rather than crossing the
  map at 25 m.

The corridor is classified there too, because a corridor is a route and there
was no route to classify at boarding. A lift the states exclude is handed back
at that point, untouched.

`ITW_CLASH_HotDropLaunchTimeout` (900 s) covers lift-off, the waypoint being
given and the cruise to the last leg. If no real destination appears by then,
or the squad leaves or is lost while waiting, the lift is handed back with
`NO_RUN` and nothing is flown.

### A clear approach is left to HAL

`ITW_CLASH_HotDropStates` is `CONTESTED`, `HOT`, `AIR_DENIED`.

`COLD` was briefly added, on the reasoning that a paradrop into a quiet corridor
costs nothing and lands the squad sooner. In practice it made HotDrop take
essentially **every troop lift on the map**, which is far more intervention than
the profile is worth when nothing is shooting. Narrowed back: the profile exists
for the approaches that need it.

The decline now fires at launch, on the real corridor read from the real route,
and hands the lift back untouched.

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

## Repair is more urgent than ammo

A group that asks for repair stops being HAL's and either freezes or withdraws.
Both halves of that were already built - `fnc_Claim` sets `Break` to unwind
HAL's running order, takes `Busy` the instant it frees, and clears the group's
HAL roles; `StepResolve` holds an immobilised or dry group in place and brings
the service to it rather than ordering a move it cannot make.

What was missing was urgency. Every need waited the same 120 seconds, and a
damaged vehicle spends that window still taking HAL orders. The single repair
claim in a 70 minute run shows the cost:

```
23:49:26  claim     G71 (Rooikat 120 UP), needed REPAIR for 120s
23:49:32  withdraw  238m to a rendezvous
23:51:16  release   group-lost
23:45:27  earlier:  resupply-dead-recipient-aborted (repair truck inbound)
```

Both repair cases that run ended with the recipient dead.

Patience is now per need, taking the shortest any of them asks for:

| need | window |
| --- | --- |
| ammo, fuel | `ITW_CLASH_ResupplyPatience` — 120 s |
| repair | `ITW_CLASH_ResupplyRepairPatience` — 30 s |
| immobilised or out of fuel | `ITW_CLASH_ResupplyImmobilePatience` — 0 s |

A dry rifle can wait out a native delivery. A vehicle at half damage is losing
the fight it is standing in, and an immobilised one cannot withdraw, cannot
flee, and will not complete anything it is tasked with - so it is taken at once.

Native HAL still gets whichever window applies, and an in-flight native delivery
still restarts the clock in `fnc_Detect` regardless of which one it is.

## Recon contacts stopped flapping

`contact-lost-by-hal` fired 121 times and `contact-returned-to-hal` 105 times in
one run - four contacts lost in the same second and back two seconds later,
eight to eleven times each.

`fnc_KnownGroups` reads `RydHQ_KnEnemiesG` straight off the commander, and HAL
rebuilds that list every cycle. A pass that samples it mid-rebuild sees an empty
or partial list and condemns every tracked contact at once.

It was not only noise. `lostAt` is what gates a contact becoming a player recon
task, and only after `ITW_CLASH_PlayerReconStaleSeconds` (60 s) of staleness.
Every flap reset that clock, so a contact HAL had genuinely lost could keep
being marked found and never mature into a task at all.

Two guards:

- **A grace window.** `ITW_CLASH_PlayerReconLostGrace` (20 s) - absent for one
  pass starts a clock, and only staying absent past it counts as lost.
  Comfortably longer than a rebuild, far shorter than the 124-148 s HAL cycle
  this run measured, and well inside the staleness window so a real loss still
  matures into a task.
- **An empty list is the rebuild itself.** A commander that knows nothing has
  nothing to lose track of, so the sweep is skipped rather than condemning
  every contact together.

Because `lostAt` is now only ever set after the grace, a two second flap never
sets it and so can never reset it.

## The commander tells its troops what it knows

Audited every `knowsAbout` reader and every place C.L.A.S.H. positions or buys
something against a contact. Three real gaps, all the same shape: a decision
made on the commander's knowledge, acted on by a group that was never told.


Two halves, both about an asset going into a fight blind.

### An ETB counter was never told what it was bought to kill

Nothing in C.L.A.S.H. called `reveal` at all. A counter purchased specifically
to answer one threat was pushed into `RydHQ_AttackAv` and handed to
`RYD_Dispatcher` against that threat's group - while knowing nothing about it.
It spawns at the rear base, drives to the objective, and discovers what it is
fighting by being engaged.

`ITW_CLASH_HALThreatCoverage_fnc_Brief` now reveals the threat's own group to
the asset, **before** the dispatcher runs, so HAL's risk assessment and the
group's own behaviour both have it. It runs on every offer, so an idle asset
re-offered later is briefed too, and SPAA is briefed as well even though it is
placed rather than dispatched.

Level 2, which is exactly what HAL's own `Rev.sqf` reveals at - the same brief a
group would get for standing near the contact, delivered to the group that was
bought for it. It reveals only that threat's group and only to that asset; it
reads no commander knowledge pool and nothing map-wide.

### A stationed SPAA was never cued to the tracks it was covering

`fnc_Sector` points an SPAA at the nearest hostile aircraft the commander knows
about and `fnc_Station` drives it there on RED - without telling the group those
aircraft exist. It arrives in the right place, facing the right way, having to
acquire from scratch.

`ITW_CLASH_SPAAOverwatch_fnc_Cue` hands it the air picture's live tracks on
every stationing. The air picture is already built from side-wide observation
(`fnc_Observers` asks every living unit on the side), so giving those tracks to
that side's air defence is the one piece of sharing an air defence network
exists for. Level 2 again - awareness, not a firing solution; range and line of
sight still decide whether it shoots.

### HAL's sharing radius was too short to brief anyone in time

`HAL/Rev.sqf` runs every 20 seconds per commander and reveals, at level 2, every
enemy somebody on that side has actually seen. It is never omniscience - an
enemy nobody observed is revealed to nobody - and both commanders run it.

The limit was `RydxHQ_NEAware`, HAL's default of **500 m**, which C.L.A.S.H.
never changed. A group dispatched two kilometres to an objective learned nothing
until it was already inside engagement range of what was waiting.

`ITW_CLASH_HALAwareRadius` (default `1500`) now sets it in
`ITW_CLASH_fnc_ConfigureHAL`, beside the other HAL tuning. 1500 is the standoff
the SPAA doctrine already treats as behind-the-fight-but-covering-it, which
makes it the natural brief-before-contact distance. Distribution was never the
bottleneck; the radius was.

### Deliberately left alone

- **The rear-base C-RAM.** It cannot move and anything entering its umbrella is
  close enough to detect unaided. Cueing it would help against a fast jet, but
  the case is weaker than for a mobile SPAA and it is not a defect.
- **HotDrop's transport.** It flies an evasive profile *around* air defence
  rather than engaging it; revealing that AA to the pilot would change how it
  flies without making the insertion safer.
- **Impasse's own `knowsAbout` readers** (`ITW_Radio.sqf`, `ITW_Objectives.sqf`,
  `fn_BetterMoveTo.sqf`). Pre-existing, outside this layer, and none of them
  showed a defect under reading.
- **`ITW_CLASH_ReconObserver.sqf`** reads `knowsAbout` only to measure and
  report. Read-only by design and correct.

## Trucks stop driving up to tanks

Only armour ever checked for armour. `RYD_Dispatcher`'s AT-risk resignation is
gated on the chosen group being in `_LArmorG` or `_HArmorG`
(`HAC_fnc.sqf:1650`). A soft-skinned vehicle group dispatched under an `INF`
pattern is in neither pool, so it **never ran the check at all** - sent at a
known tank with no risk assessment, into gun range, and killed. The armour
branch beside it and the `ARM` pattern below it both do the check properly.

The capability match added earlier only governs what the **ETB buys**. What HAL
dispatches from its own order of battle was untouched, which is why soft
vehicles kept going in.

`ITW_CLASH_HALDispatcherSoftArmorFix.sqf` appends one list to that one
expression:

```sqf
if ((_chosen in (_LArmorG + _HArmorG + ITW_CLASH_SoftVehicleGroups)) and ((count _ATthreat) > 0)) then
```

HAL's own resignation - its distances, its recklessness scaling, its random
roll - then applies to soft vehicle groups exactly as it already does to
armour. No new doctrine and no second opinion about whether to go; the smallest
patch surface this could have.

`ITW_CLASH_SoftVehicleGroups` holds groups whose leader rides in something the
air picture grades as unprotected, rebuilt wholesale every 15 s so a group that
dismounts or dies leaves with no bookkeeping. **Dismounted infantry is
deliberately excluded** - the leader must actually be in a vehicle, because an
AT team on foot is a legitimate answer to a tank and a man's own config armour
would grade 0 and sweep in every rifle squad.

The anchor is the one place the two armour pools are added together. It occurs
exactly once, verified against both the raw and whitespace-collapsed forms of
the real dispatcher, and the patch refuses unless there is precisely one pair
with `_chosen` before it and `_ATthreat` after. Any miss logs and leaves stock
HAL compiled, like the AA fix. The global is defined before the patch is
written and never cleared, since a nil global inside the dispatcher would throw
on every dispatch for the rest of the mission.

## A medevac'd squad could never shoot again

Run 2's combat diagnostics logged **345 contact anomalies naming
`group-attack-disabled`**, including an APC cannon crew sitting 180 m from an
enemy AT rifleman, combat mode RED, behaviour COMBAT, not engaging. That is what
walking past the enemy looks like from the inside.

Eight files in the mission call `enableAttack false`. Two call `enableAttack
true`, and both belong to unrelated paths - the GTFO withdrawal's own
completion and the reconstitution transit fix. Everything else disables and
never restores.

For a purpose-spawned CASEVAC helicopter crew or ground ambulance crew that is
correct: they exist to carry casualties and should never stop to fight. But the
same call lands on **the casualty's own squad**:

```
CASEVAC.sqf:764                [_group,_lz]    call fnc_OrderLZ    -> enableAttack false
GroundMEDEVAC_Manager.sqf:112  [_group,_rally] call fnc_OrderRally -> enableAttack false
```

Those are line groups. They get picked up, they get released back to HAL, and
they spend the rest of the mission unable to shoot at anything.

`ITW_CLASH_AttackRestore.sqf` restores the invariant rather than patching each
exit: a group that nothing currently owns should be able to defend itself.
Fixing it at every release path would mean tracing every exit of two large
managers and hoping none was missed - and the misses are precisely the problem.

It is deliberately conservative, because HAL disables attack too and restores it
itself (`GoRest.sqf:74/709`, `GoDefRecon.sqf:59/255`,
`GoAttSniper.sqf:270/286`). Restoring a group mid-rest would break HAL's own
behaviour, so a group is left alone while HAL is running an order on it
(`Busy`), while it is resting, while any service still claims it
(`CASEVAC_State`, `GroundMEDEVAC_State`, `Withdrawing`, `ResupplyClaimed`), and
if it is a dedicated service crew. Players are never touched, and a group must
sit unowned and disarmed for 30 seconds before anything is restored, so a
handover in progress is never raced.

### Also in run 2

- **The recon latch fired for both commanders**, which was the whole point of
  it: `RECON COMPLETE HELD FOR WEST` and `... FOR GUER`, capture orders
  unblocked.
- `close-but-no-unit-knowledge` and `close-but-no-group-knowledge` fired **783
  times each** - units inside 75 m of an enemy with no knowledge of it - and
  **311** of those also reported `hq-knows`: the commander knew and the group
  did not. That is the sharing gap the brief, the cue and the wider radius
  close; run 2 predates all three.

## Spotting speed, raised off the flat value

`setSkill` with a single number sets every sub-skill, so how fast a unit reacts
to something it has seen is tied to how well it shoots. The in-game skill dialog
shows the result exactly: every slider at 60% and Courage at 100%, which is
`ITW_Attack.sqf:1558-1559` - a flat set followed by one override.

A 100 minute run logged **783 contacts inside 75 m where neither unit knew the
other was there**, 472 of them with no commander aware either. Squads walking
past each other at 25 m in heavy vegetation.

`spotTime` - "Spotting Speed" in that dialog - is now **rolled per unit**
across `ITW_CLASH_SpotTimeMin` to `ITW_CLASH_SpotTimeMax` (`0.6` to `0.8`)
after the flat set, at all three spawn paths:

| site | what it spawns |
| --- | --- |
| `ITW_Attack.sqf:1558` | every AI unit, both sides |
| `ITW_Teammates.sqf:94` | the player's own squad |
| `ITW_Functions.sqf:948` | the clone path |

A band rather than one number, so a squad is not uniformly alert: one man
notices before the others do, which a single difficulty value can never
produce. A reversed band (Min above Max) clamps the width to zero rather than
rolling a negative and pushing `spotTime` below the floor.

**Only `spotTime` moves.** `aimingAccuracy`, `aimingSpeed` and `aimingShake`
stay exactly where the difficulty parameter put them, and `spotDistance` is
untouched - units react sooner to what they see without seeing further or
shooting better. It is placed *after* the flat set, because `setSkill` with a
number overwrites every sub-skill and an override before it would be silently
erased. The `courage` override on the next line is the same pattern and has
always been there.

`ITW_Functions.sqf:826` is deliberately left at skill 1: that is the probe logic
whose `skillFinal` derives the server's difficulty coefficients, which the
preflight now reports. Changing it would corrupt the reading.

## HAL drops a capture waypoint on an undefined _wp0

```
Error in expression <...(str _unitG),false])) then
{if (_wp0 isEqualTo []) then {_wp0 = [_unitG,...
Error Undefined variable in expression: _wp0
```

That line (`GoCapture.sqf:342`) is what adds the group's MOVE waypoint onto the
objective. When it throws, the group gets no waypoint and simply does not go -
silently.

It is stock HAL, but C.L.A.S.H. is why it is being hit. Before
`RydHQ_ReconDone` was held up, HAL almost never issued a capture order, so
`GoCapture` almost never ran: the 100 minute run before the latch logged this
**zero** times, and both runs after it logged it.

`GoRest` shows the shape plainly - its `_wp0 = []` sits inside a conditional
block (`GoRest.sqf:236`) while two later reads assume it ran. `GoCapture`'s
initialiser looks top-level, so **why** its read is out of scope is not
something this patch claims to understand. The guard does not depend on
knowing: `isNil` is exactly as true when a variable is missing for a reason
nobody has traced.

Every read of `_wp0 isEqualTo []` becomes
`isNil "_wp0" || {_wp0 isEqualTo []}` in `HAL_GoCapture`, `HAL_GoRecon`,
`HAL_GoAttInf` and `HAL_GoRest` - five guards across the four. That is
identical wherever `_wp0` is defined, and where it is not, an undefined `_wp0`
now takes the same branch an empty one takes: the branch that creates the
waypoint.

The transformation is simulated against the real HAL sources in the tests, so a
malformed rewrite fails there rather than in a mission. A target that is absent
or already guarded is not a failure - a modpack need not ship every order, and
HAL may fix it upstream - but a recompile or verification failure logs a
warning and keeps the stock order.

## Launcher teams fight once a SPAA holds the back line

An AA squad walked to a FOB is a squad not in the fight, and a mobile SPAA on
overwatch covers the same sky far better: it relocates as the front moves, it
re-points at the nearest known hostile every poll, and it is not three riflemen
with a launcher.

`ITW_CLASH_FOBAirDefence_fnc_Candidates` now returns nothing while
`ITW_CLASH_SPAAOverwatch_fnc_Held` reports at least
`ITW_CLASH_FOBAirDefenceSPAAFloor` (1) mobile SPAA for that commander, so the
launcher teams stay available to HAL.

**The rear-base C-RAM does not count.** It is bolted to one spot by design -
gunner, no driver - so it covers the base and nothing else; leaving the FOBs to
it would be covering a different place than the one at risk. The floor matches
the back line's own cap, since requiring more than the doctrine ever keeps
would never release anything.

`ITW_CLASH_FOBAirDefenceYieldToSPAA` turns it off, and a mission without the
overwatch module keeps the old behaviour.

### The over-cap line was lying

`spaa-overwatch-over-cap` logged `["B",1,0,1]` - one refused while holding zero,
against a cap of one. The sweep counted *every* refusal from `fnc_Adopt`, and a
rear-base C-RAM is refused there too. So the emplacement guard doing its job
read as a cap that was broken. Only a genuine capacity refusal counts now.

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

It also reports what the AI can actually see: the two difficulty parameters and
the server's own coefficients. `setSkill` is applied flat at
`ITW_Attack.sqf:1558`, so `spotDistance` and `spotTime` are whatever the
difficulty parameter says - and the server scales the result again.
`ITW_FncGetServerAiDifficultySetting` already computes both from a probe
logic's `skillFinal`, but nothing logged them, which made a run where squads
walk past each other at 25 m impossible to read. A missing reading prints
`unknown` rather than a number that is not true.

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
