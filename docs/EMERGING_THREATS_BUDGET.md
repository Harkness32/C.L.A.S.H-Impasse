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
