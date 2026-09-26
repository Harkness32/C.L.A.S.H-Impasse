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

Not built, and deliberately: the helicopter threat tiers beyond classification,
and the one-purchase overdraft on a full reserve (decision 7). Both are still
Hark's call. Follow-on work — AA teams garrisoning FOBs, the rear-base C-RAM,
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

`ITW_CLASH_ETBDryRun = true` runs the whole economy and every decision and buys
nothing: each authorization logs the purchase it would have made. Use it for the
first live run of phase 3.

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

## What to check before trusting a run

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
