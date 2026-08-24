# C.L.A.S.H. Player Employment Demand Dispatch Plan

Status: implementation contract for `fix/player-job-cancel-hardening-v1`

## Decision

**A player's current vehicle never decides whether they are told about subscribed work.**

The five HAL employment subscriptions answer one question only: **what kinds of work is this player group willing to accept?**

Current equipment answers a later question: **can this group execute the next physical step right now?**

The core rule is therefore:

> **Subscription gates dispatch. Capability gates execution.**

A LOGISTICS subscriber may receive an ammunition mission while on foot. A TRANSPORT or MEDEVAC subscriber may receive a pickup while driving an IFV, flying the wrong helicopter, or standing at a base. An ARTILLERY subscriber may receive a fire mission before acquiring or deploying an artillery piece. The player is responsible for acquiring a suitable asset or cancelling the assignment.

This document supersedes the current capability-gated player admission policy in `ITW_CLASH_PlayerTaskStateHardening.sqf`.

## Why the current model fails

The current player employment layer conflates three different concepts:

1. willingness to accept work;
2. temporary physical capability of the currently occupied asset; and
3. native HAL provider eligibility.

`CanAcceptJob` and `HasExecutableSubscription` currently inspect passenger seats, sling capability, or artillery capability before a player can be considered available. `SyncEmploymentState` then maps that answer onto `ITW_CLASH_PlayerTaskAvailable`, `Unable`, and `BUnable`.

This creates silent missed work. A LOGISTICS subscriber standing beside the base does not see an ammunition requirement because the player has no sling-capable helicopter at the instant HAL searches for a provider. The same flaw affects TRANSPORT, MEDEVAC, and ARTILLERY.

MEDEVAC demonstrates the larger problem. The employment menu exposes a MEDEVAC subscription, but the current player task layer has no friendly evacuation dispatcher/executor. Native HAL `SuppMed.sqf` does provide useful friendly medical demand: it publishes `RydHQ_Wounded` and identifies severe casualties when damage is above 0.75 or a casualty cannot stand. Native `GoMedSupp.sqf`, however, is a medical-support mission that drives an ambulance to a wounded unit and heals nearby troops; it is not a casualty evacuation mission. C.L.A.S.H. will consume HAL's casualty knowledge as demand and provide a distinct player evacuation lifecycle.

## Ownership contract

### HAL owns tactical demand

HAL remains the tactical authority for battlefield need and target selection wherever native state already expresses that need.

Examples:

- ammunition demand: `RydHQ_Hollow`;
- fuel demand: `RydHQ_Dried`;
- repair demand: `RydHQ_damaged`;
- medical demand: `RydHQ_Wounded` plus severe-casualty criteria;
- transport demand: HAL cargo/transport planning state;
- artillery target selection: HAL's known-enemy/fire-mission logic.

C.L.A.S.H. must not create a second tactical commander merely to feed player tasks.

### C.L.A.S.H. owns player demand reservation and task lifecycle

Once HAL exposes a valid need, C.L.A.S.H. may publish a player-facing demand, reserve it for a subscribed player group, present the task, monitor preparation, and hand execution to the appropriate existing executor or a purpose-built player executor.

Reservation is an arbitration seam, not a second scheduler.

### Impasse retains strategic authority

Impasse continues to own campaign state, active zones, objectives, budgets/tickets, strategic spawning, persistence, and cleanup. Player tasking may request or use assets through existing Impasse mechanisms but may not bypass strategic accounting.

## Two separate eligibility concepts

The implementation must stop using one boolean for both player dispatch and native HAL execution.

### Player dispatchability

A group is dispatchable for a channel when:

- it contains a living player;
- it is on `ITW_PlayerSide`;
- it is subscribed to that channel;
- it has no active/reserved player job;
- it is not under `ITW_CLASH_AuthorityHold`.

**No current-vehicle or weapon-capability test belongs here.**

Proposed runtime state:

- `ITW_CLASH_PlayerTaskDispatchable`
- `ITW_CLASH_PlayerHasActiveHALJob`
- `ITW_CLASH_PlayerDemandJobId`

### Native HAL executability

Native HAL still needs truthful physical-provider information. A group standing at base must not be advertised to native HAL as a functioning ambulance, transport helicopter, sling-load provider, or artillery battery.

Native executability may continue to inspect:

- current passenger capacity;
- current sling-load capability;
- current artillery capability/deployment;
- native busy/Unable state;
- channel-specific physical requirements.

`Unable` and `BUnable` therefore remain **native-HAL execution controls**, not a statement that the player may or may not receive a C.L.A.S.H. task.

## Demand ledger

Introduce a server-owned demand ledger:

`ITW_CLASH_PlayerDemands = createHashMap`

Each demand contains, at minimum:

- stable demand ID;
- channel: `COMBAT`, `TRANSPORT`, `MEDEVAC`, `LOGISTICS`, or `ARTILLERY`;
- kind/subtype;
- owning HQ/source system;
- target/requester/reference object or group;
- pickup/target position where appropriate;
- requirement description and machine-readable requirement data;
- creation/update time;
- state;
- reserving player group;
- reservation time;
- execution job ID when handed to a specialist executor;
- invalidation/release reason.

Demand states:

`OPEN -> RESERVED -> EXECUTING -> COMPLETED`

Additional terminal/state transitions:

- `RESERVED -> OPEN` when the player cancels and the underlying need still exists;
- `EXECUTING -> OPEN` when cancellation can safely return the work to the pool;
- any nonterminal state -> `INVALID` when the battlefield requirement no longer exists;
- any nonterminal state -> `FAILED` only when the requirement existed but execution reached an unrecoverable terminal failure.

## Reservation rules

A player assignment is meaningful only if the same requirement is not immediately consumed by AI.

When a demand enters `RESERVED`:

1. the demand records the owning player group;
2. C.L.A.S.H. applies the narrowest available native reservation/suppression needed to prevent duplicate execution;
3. the reservation is continuously validated;
4. the player may prepare for as long as the underlying requirement remains valid;
5. there is no arbitrary short preparation timeout.

Cancellation means **release**, not deletion.

When the group leader uses `Cancel Current HAL Job`:

- the player-facing task is cancelled;
- execution-specific locks are unwound;
- the demand returns to `OPEN` if it is still valid;
- AI or another subscribed player may then service it;
- the player's employment subscriptions remain unchanged.

If the casualty recovers/dies, requester is destroyed, target disappears, or the tactical requirement otherwise vanishes, the demand becomes `INVALID` instead of being requeued.

## Assignment and preparation UX

Assignments must state the mission before the player has the equipment required to execute it.

Example:

**HAL Logistics: Ammunition Delivery**

- Pickup: rear support node / marked ammunition package
- Recipient: designated HAL formation
- Requirement: acquire a sling-capable helicopter capable of lifting the package

A player standing at base can now learn that the work exists, buy or retrieve a suitable aircraft, and perform it. If the player has no interest in doing so, they cancel the job.

The task may expose a preparation status such as `ACQUIRE CAPABILITY` until its execution predicate becomes true. Failure to possess the capability is not itself mission failure.

## Channel implementation plan

### LOGISTICS

Demand sources already exist in HAL:

- ammo: `RydHQ_Hollow`;
- fuel: `RydHQ_Dried`;
- repair: `RydHQ_damaged`.

Phase 1 will publish ammunition sling demands before native provider selection. Package creation through `LOGISTICS_PACKAGE_AMMO` remains an Impasse/Checkbook responsibility and can occur independently of whether the player is currently flying a sling-capable helicopter.

Once the assigned player has an appropriate helicopter and a compatible package exists, execution hands off to the existing player ammunition sling job logic. The existing human-only `assignedVehicle` compatibility fallback in native `SuppAmmo.sqf` remains valid as a fast/native compatibility seam, but it is no longer the mechanism by which a player discovers the mission.

Fuel and repair will use the same demand ledger after the ammunition path is certified.

### MEDEVAC

Native HAL already detects friendly wounded personnel in `SuppMed.sqf` and publishes `RydHQ_Wounded`. Severe casualties are those HAL already treats as high priority: alive personnel with damage above 0.75 or who cannot stand.

C.L.A.S.H. will publish a `MEDEVAC` demand for a severe friendly casualty/group that is not already serviced/reserved.

The player may receive the mission with no vehicle. The task identifies casualty pickup and evacuation destination and states that passenger capacity is required before extraction can begin.

Execution becomes active only when the assigned player arrives with a usable passenger-capable vehicle. Player MEDEVAC is an evacuation workflow, not native `GoMedSupp` magic healing:

1. reach casualty/pickup;
2. physically embark surviving evacuees/casualties;
3. transport them to a live friendly service-home/base destination;
4. physically disembark them;
5. complete the task and release the player for further subscribed work.

Native `GoMedSupp` remains available to AI medical-support providers for needs not reserved to a player.

### TRANSPORT

Transport demand must be visible before a player carrier has already been selected.

A subscribed idle player can reserve the request while on foot or in an unsuitable vehicle. The task identifies the waiting formation, pickup point, destination, and passenger requirement.

When the player presents a suitable carrier, native HAL `SCargo` remains the sole physical GET IN / GET OUT and movement-task executor. C.L.A.S.H. must not reintroduce a parallel transport movement system.

Existing carrier-home and terminal RTB hardening remain in force.

### ARTILLERY

Current player artillery selection is capability-first: a human group is considered only after `EligibleVehicle` finds an already deployed, player-gunned artillery asset. That causes on-foot or wrong-vehicle subscribers to miss fire missions.

The target/fire requirement will instead be published first. An ARTILLERY subscriber may reserve the mission in preparation state. The task tells the player to acquire/deploy a valid artillery asset and any fire restrictions.

Only after the execution predicate is met will the existing shot-reporting, ammunition authorization, danger-close, firing-position emission, and impact-completion machinery arm.

### COMBAT

COMBAT is already the least equipment-dependent channel. It will adopt the same demand/reservation vocabulary so occupation, cancellation, and invalidation are consistent across all channels. Recon remains within COMBAT for now.

## Cancellation and disconnect behavior

The group leader remains the authority for explicit job cancellation.

The generic cancellation path must understand the new demand job ID before falling through to specialist/native cancellation handlers.

Cancellation must:

- mark the player task `CANCELED`;
- release demand reservation;
- restore/reopen valid tactical demand;
- clear only C.L.A.S.H.-owned locks/flags;
- resynchronize employment state;
- never unsubscribe the player.

Disconnect, group loss, or death will use the same release logic where practical. Existing intentional transport carrier-loss behavior is not changed by this project.

## Execution predicates

Execution predicates are evaluated continuously but never erase the assignment merely because the player temporarily loses capability.

Examples:

- TRANSPORT / MEDEVAC: a living movable vehicle with adequate passenger capacity at the pickup phase;
- LOGISTICS ammo sling: a living movable helicopter with sufficient sling mass capability for the reserved package;
- ARTILLERY: a valid deployed player artillery asset with authorized ammunition and player gunner;
- COMBAT: channel-specific operational conditions.

The current vehicle is therefore an execution input, never a subscription or dispatch input.

## Telemetry

The RPT must make the new lifecycle obvious. Add structured markers for:

- `player-demand-published`
- `player-demand-reserved`
- `player-demand-preparing`
- `player-demand-execution-ready`
- `player-demand-executing`
- `player-demand-released`
- `player-demand-invalidated`
- `player-demand-completed`
- `player-demand-native-suppressed`
- `player-demand-native-restored`

Employment synchronization should log dispatchability and native executability separately so a line can truthfully show:

`dispatchable=true nativeExecutable=false`

for a subscribed player standing at base.

## Implementation sequence

1. Add `ITW_CLASH_PlayerDemandDispatch.sqf` and load it after the existing player-task hardening layer is ready.
2. Split dispatchability from native executability and stop using vehicle capability in `CanAcceptJob`.
3. Add the demand ledger, reservation lifecycle, generic task ownership, and cancellation/release primitives.
4. Publish LOGISTICS ammo demand before provider selection; certify on-foot/wrong-helicopter assignment and later sling execution.
5. Publish MEDEVAC from HAL's severe-friendly-wounded state and add physical player evacuation execution.
6. Move TRANSPORT discovery upstream of carrier selection while preserving SCargo as sole physical executor.
7. Move ARTILLERY assignment upstream of `EligibleVehicle` while preserving existing artillery execution monitoring.
8. Normalize COMBAT onto the same demand/reservation state vocabulary.
9. Add static regression coverage and hosted-Arma smoke telemetry for every transition.

## Certification matrix

The build is not certified until these cases work:

| Scenario | Expected result |
| --- | --- |
| LOGISTICS subscribed, player on foot | Ammo need is assigned; task tells player to acquire required asset. |
| LOGISTICS subscribed, player in non-sling Hummingbird | Same assignment; no silent rejection. |
| Player later acquires valid sling helicopter | Existing sling execution arms and can complete the reserved demand. |
| MEDEVAC subscribed, player on foot | Severe friendly casualty demand is assigned. |
| Player later acquires passenger vehicle | Pickup/extraction execution becomes available without re-subscribing. |
| TRANSPORT subscribed, player has no carrier | Waiting troop transport need is visible/reservable. |
| ARTILLERY subscribed, player has no gun | Fire mission is visible; execution remains in preparation until valid artillery appears. |
| Player cancels a still-valid job | Player task cancels, demand returns to OPEN, subscription remains enabled. |
| Underlying need vanishes while reserved | Task invalidates; demand is not requeued. |
| Player has subscribed work but no current capability | RPT shows dispatchable true and nativeExecutable false. |

## Non-goals / preserved behavior

- Do not make C.L.A.S.H. a second battlefield commander.
- Do not bypass Impasse budgets, tickets, or strategic spawning.
- Do not create a second physical HAL transport executor; SCargo remains authoritative.
- Do not reinterpret enemy GroundMEDEVAC/CASEVAC as the player BLUFOR system.
- Do not change the intentionally preserved transport carrier-loss behavior.
- Do not remove native capability checks where HAL needs them to select a physical executor.

## Definition of done

The employment menu is considered truthful when selecting a channel means:

> **"Tell me when this kind of work exists."**

and not:

> **"Only tell me if my current vehicle happens to match the job during this polling cycle."**

That distinction is the contract this implementation must preserve.