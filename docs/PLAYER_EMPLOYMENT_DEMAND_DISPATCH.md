# C.L.A.S.H. Player Employment Demand Dispatch Plan

Status: implementation contract for `fix/player-job-cancel-hardening-v1` / draft PR #52

## Decision

**A player's current vehicle never decides whether they are told about subscribed work.**

The five HAL employment subscriptions answer one question only: **what kinds of work is this player group willing to accept?**

Current equipment answers a later question: **can this group execute the next physical step right now?**

The core rule is therefore:

> **Subscription gates dispatch. Capability gates execution.**

A LOGISTICS subscriber may receive an ammunition mission while on foot. A TRANSPORT or MEDEVAC subscriber may receive a pickup while driving an IFV, flying the wrong helicopter, or standing at a base. An ARTILLERY subscriber may receive a fire mission before acquiring or deploying an artillery piece. The player is responsible for acquiring a suitable asset or cancelling the assignment.

This document supersedes the old capability-gated player admission policy that was originally implemented in `ITW_CLASH_PlayerTaskStateHardening.sqf`. The F2/F3 cancellation/admission hardening from PR #51 is already merged into the integration branch; PR #52 is the follow-on demand-first tranche and must build on that landed baseline rather than around an unmerged copy.

## Why the old model fails

The old player employment layer conflated three different concepts:

1. willingness to accept work;
2. temporary physical capability of the currently occupied asset; and
3. native HAL provider eligibility.

Capability-first admission silently misses work. A LOGISTICS subscriber standing beside the base does not see an ammunition requirement because the player has no sling-capable helicopter at the instant HAL searches for a provider. The same flaw affects TRANSPORT, MEDEVAC, and ARTILLERY.

MEDEVAC demonstrates the larger problem. The employment menu exposed a MEDEVAC subscription, but the original player task layer had no friendly evacuation dispatcher/executor. Native HAL `SuppMed.sqf` provides useful friendly medical demand: it publishes `RydHQ_Wounded` and identifies severe casualties when damage is above 0.75 or a casualty cannot stand. Native `GoMedSupp.sqf`, however, is a medical-support mission that sends a medical provider to heal wounded troops; it is not casualty evacuation. C.L.A.S.H. therefore consumes HAL casualty knowledge as demand and owns a distinct player evacuation lifecycle.

## Ownership contract

### HAL owns tactical demand

HAL remains the tactical authority for battlefield need and target selection wherever native state already expresses that need.

Examples:

- ammunition demand: `RydHQ_Hollow`;
- fuel demand: `RydHQ_Dried`;
- repair demand: `RydHQ_damaged`;
- medical demand: `RydHQ_Wounded` plus severe-casualty criteria;
- transport demand: the exact native `HAL_SCargo` request;
- artillery demand: the `RYD_CFF` target-selection/fire-mission request;
- combat demand: native HAL attack/defense/recon task assignment.

C.L.A.S.H. must not create a second tactical commander merely to feed player tasks.

### C.L.A.S.H. owns player demand reservation and task lifecycle

Once HAL exposes a valid need, C.L.A.S.H. may publish a player-facing demand, reserve it for a subscribed player group, present the task, monitor preparation/liveness, and hand execution to the appropriate existing executor or a purpose-built player executor.

Reservation is an arbitration seam, not a second scheduler.

### Impasse retains strategic authority

Impasse continues to own campaign state, active zones, objectives, budgets/tickets, strategic spawning, persistence, and cleanup. Player tasking may request or use assets through existing Impasse mechanisms but may not bypass strategic accounting.

## Native HAL cycle overwrite: identified

The previously unidentified roughly cycle-length "array stripper" is now source-identified for Commander B.

`HQSitRepB.sqf` periodically copies Commander-B globals back onto the HQ object, including:

- `RydHQB_NoRecon -> RydHQ_NoRecon`;
- `RydHQB_NoAttack -> RydHQ_NoAttack`;
- `RydHQB_NoDef -> RydHQ_NoDef`;
- `RydHQB_ASupportedG -> RydHQ_ASupportedG`;
- `RydHQB_SupportedG -> RydHQ_SupportedG`;
- and other Commander-B configuration/state arrays.

C.L.A.S.H. historically changed some HQ-object arrays without changing the corresponding `RydHQB_*` global. The next native SitRep cycle could therefore replace the object-side mutation with the unchanged global value. The long-run quarantine/ferry reconciliation repairs were not random corruption; they were repairing this native projection rewrite.

Consequences for this project:

1. **A player reservation must never depend on a one-time write to one of these HQ arrays.**
2. Long-lived demand ownership lives in the C.L.A.S.H. ledger/markers, not HAL projection arrays.
3. If an existing lifecycle must project state into a HAL planning array, that projection is continuously reconciled and, where appropriate, mirrored into the correct Commander-B source-of-truth global.
4. Demand-first ammo and MEDEVAC will avoid persistent `ASupportedG` / `SupportedG` reservation entirely.
5. No demand-first channel may ship with an unidentified periodic writer capable of defeating its duplicate-execution guard.

This source identification closes the specific "unknown stripper" release blocker, but each channel still has to certify its own suppression seam against the same class of overwrite.

## Two separate eligibility concepts

The implementation must not use one boolean for both player dispatch and native HAL execution.

### Player dispatchability

A group is dispatchable for a channel when:

- it contains a living player;
- it is on `ITW_PlayerSide`;
- it is subscribed to that channel;
- it has no active/reserved player job;
- it is not under `ITW_CLASH_AuthorityHold`;
- it is not in a per-demand decline cooldown for that exact demand.

**No current-vehicle or weapon-capability test belongs here.**

Runtime state includes:

- `ITW_CLASH_PlayerTaskDispatchable`;
- `ITW_CLASH_PlayerHasActiveHALJob`;
- `ITW_CLASH_PlayerDemandJobId`.

### Native HAL executability

Native HAL still needs truthful physical-provider information. A group standing at base must not be advertised to native HAL as a functioning ambulance, transport helicopter, sling-load provider, or artillery battery.

Native executability may inspect:

- current passenger capacity;
- current sling-load capability;
- current artillery capability/deployment;
- native busy/Unable state;
- channel-specific physical requirements.

`Unable` and `BUnable` therefore remain **native-HAL execution controls**, not a statement that the player may or may not receive a C.L.A.S.H. task.

## Demand ledger

The server-owned ledger is:

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
- invalidation/release reason;
- demand-owned native reservation marker/projection metadata;
- `lastProgressAt` and a progress signature/position;
- per-player decline/re-offer cooldowns keyed to this demand ID;
- `bounceCount`;
- `playerOfferSuppressedUntil` when repeated bounces intentionally give native AI a clean servicing window.

Demand states:

`OPEN -> RESERVED -> EXECUTING -> COMPLETED`

Additional transitions:

- `RESERVED -> OPEN` when the player cancels and the underlying need still exists;
- `RESERVED -> OPEN` when the player loses liveness and the underlying need still exists;
- `EXECUTING -> OPEN` only when the specialist executor can safely unwind and return the work;
- any nonterminal state -> `INVALID` when the battlefield requirement no longer exists;
- any nonterminal state -> `FAILED` only when the requirement existed but execution reached an unrecoverable terminal failure.

## Reservation, suppression, and duplicate-execution contract

A player assignment is meaningful only if the same requirement is not immediately consumed by AI.

When a demand enters `RESERVED`:

1. the ledger records the owning player group;
2. C.L.A.S.H. activates the **named channel-specific suppression seam** below;
3. demand-owned suppression/markers are continuously validated for the entire reservation;
4. player liveness/progress is continuously validated;
5. capability is not required until the execution predicate;
6. there is no fixed "you took too long to buy the vehicle" preparation timeout.

### Channel-specific suppression seams

| Channel / subtype | Demand ownership / duplicate-execution seam | Persistence rule |
| --- | --- | --- |
| LOGISTICS / ammo | Demand owns a C.L.A.S.H. ammo-reservation marker on the recipient group. Native `SuppAmmo` arbitration is call-scoped against reserved groups using its existing `RydHQ_ExReAmmo` input exclusion, rather than using `RydHQ_ASupportedG` as a long-lived lock. The final `HAL_GoAmmoSupp` handoff remains a fail-open backstop against a same-cycle race. | Ledger marker is authoritative and checked every demand poll. Any HAL exclusion projection exists only for the duration of the native scan and is restored immediately. No persistent `ASupportedG` mutation is owned by the demand. |
| MEDEVAC / severe casualty | Demand owns a C.L.A.S.H. MEDEVAC-reservation marker on the casualty group (covering all severe evacuees in that group). Native `SuppMed` arbitration is call-scoped against reserved groups using its existing `RydHQ_ExMedic` input exclusion, rather than using `RydHQ_SupportedG` as a long-lived lock. The final `HAL_GoMedSupp` handoff remains a fail-open backstop against a same-cycle race. | Ledger/group marker is authoritative and checked every demand poll. Native exclusion is temporary and restored immediately. No persistent `SupportedG` mutation is owned by the demand. |
| TRANSPORT | Reservation occurs at the `HAL_SCargo` request-entry seam **before carrier selection**. C.L.A.S.H. stores the exact requester/HQ/destination/request flags and defers that native SCargo invocation while a player owns the request. Once the player presents sufficient passenger capacity, the same native request is resumed with `SCargo` remaining sole physical executor. | The deferred-call contract/ledger is authoritative. No HQ supported-array lock is required. Existing cargo-group retask protection (`NoAttack`/`NoRecon`/`NoDef`) is a separate planning projection and must continue its 0.5 s reconciliation for the physical ferry lifecycle. |
| ARTILLERY | Reservation occurs in the existing `RYD_CFF` wrapper before the capability-first `EligibleVehicle` selection. HAL target selection is captured once; while a player owns that fire requirement the corresponding native CFF invocation is withheld from AI. On release, a still-valid stored CFF request is returned to native arbitration or allowed to be regenerated on the next HAL cycle. | Stored CFF demand is authoritative; no persistent HQ planning array is the reservation. Existing artillery busy state begins only when the specialist executor arms. |
| COMBAT | Native HAL remains the physical/tactical task assigner. COMBAT has no equipment-preparation suppression requirement. C.L.A.S.H. observes the native assignment into the common lifecycle and relies on HAL's own Busy/task ownership to prevent duplicate native combat jobs. | No new long-lived suppression array. Existing COMBAT admission projections such as `NoRecon`/`CargoOnly` must be reconciled/mirrored because SitRepB rewrites object arrays. |
| LOGISTICS / fuel, repair | Not authorized to ship until the exact native request/eligibility seam is named and tested. Expected shape is the same as ammo: demand-owned marker plus call-scoped native exclusion, not a persistent supported-array reservation. | Release blocker until implemented and certified. |

### Continuous assertion rule

If a demand owns a durable marker or contract, the main demand poll verifies it every second and reasserts it if some other writer removed it. If a channel requires a HAL planning-array projection during execution, that projection receives the same continuous-reconciliation treatment already used by service quarantine and the ferry retask lock.

A one-time write is never considered a reservation.

### Call-scoped native exclusion

For ammo and MEDEVAC, the safe design is to exploit the native scan's existing exclusion inputs rather than hold `ASupportedG`/`SupportedG` for minutes:

1. collect C.L.A.S.H.-reserved target groups for the HQ;
2. snapshot the native exclusion list (`RydHQ_ExReAmmo` or `RydHQ_ExMedic`);
3. add the reserved groups to that exclusion list;
4. execute the native `SuppAmmo` / `SuppMed` scan;
5. restore the exact snapshot immediately afterward.

The long-lived authority remains the demand ledger/marker. The native array mutation is only a scoped function input and therefore cannot be defeated later by SitRepB.

## Liveness floor: no preparation timeout, but no abandoned reservation

"No arbitrary timeout" means there is no fixed maximum preparation duration merely because the player has not yet acquired the required equipment. It does **not** mean an abandoned reservation can block the battlefield forever.

A reserved demand has a renewable liveness lease. Default policy:

`ITW_CLASH_PlayerDemandLivenessWindow = 600` seconds (10 minutes of no meaningful progress).

The lease is refreshed by meaningful progress, for example:

- the required capability changes from unavailable to available;
- the player changes/acquires an asset relevant to the requirement;
- the reserved group makes meaningful physical progress from its previous progress sample;
- distance to the current pickup/target/preparation objective materially decreases;
- the specialist executor enters `EXECUTING`.

The exact progress signature is channel-aware, but it must not be reset merely because time passed or because a polling loop ran.

Immediate release conditions while `RESERVED`:

- no living player remains in the group / player disconnects;
- the group is destroyed/lost;
- the group unsubscribes from the demand's channel;
- an authority hold makes the reservation invalid;
- the underlying battlefield requirement vanishes.

Inactivity release:

- if the demand remains `RESERVED` and `time - lastProgressAt >= ITW_CLASH_PlayerDemandLivenessWindow`, release it to `OPEN` if still valid with reason `preparation-liveness-expired`;
- native suppression is removed before re-dispatch;
- AI or another player can then take it.

Once a job enters `EXECUTING`, the specialist executor owns terminalization. Generic liveness/demand-array checks must not delete an active sling load or casualties already aboard a vehicle. Player loss during execution requests the specialist's safe cancel/unwind path.

## Re-entry, decline cooldown, and bounce control

Cancellation means **release**, not deletion**, but release must not create an offer loop.**

Default policy:

- `ITW_CLASH_PlayerDemandDeclineCooldown = 120` seconds per `(demand ID, player group)`;
- a group that explicitly cancels/declines a valid demand is ineligible for that exact demand until its cooldown expires;
- liveness expiry/provider loss may use the same cooldown so the dispatcher does not immediately return the abandoned job to the same group;
- cooldown does not affect any other demand or channel;
- cooldown expiry does not force reassignment; it merely makes the group eligible again if the demand still exists.

Every valid return from player ownership to `OPEN` increments `bounceCount`.

Default bounce policy:

- `ITW_CLASH_PlayerDemandBounceLimit = 3`;
- when a valid demand reaches the limit, player offering pauses for `ITW_CLASH_PlayerDemandAIFallbackWindow = 120` seconds;
- during that fallback window there is **no player-owned native suppression**;
- HAL AI receives a clean opportunity to service the requirement;
- if the requirement still exists after the window, player dispatch may resume and the demand remains auditable rather than evaporating.

This preserves the never-evaporates invariant without letting a request ping-pong forever between uninterested or inactive players.

## Assignment and preparation UX

Assignments state the mission before the player has the equipment required to execute it.

Example:

**HAL Logistics: Ammunition Delivery**

- Pickup: rear support node / marked ammunition package
- Recipient: designated HAL formation
- Requirement: acquire a sling-capable helicopter capable of lifting the package

A player standing at base can learn that the work exists, buy or retrieve a suitable aircraft, and perform it. If the player has no interest in doing so, they cancel the job.

The task may expose a preparation status such as `ACQUIRE CAPABILITY` until its execution predicate becomes true. Failure to possess the capability is not itself mission failure.

## Channel implementation plan

### LOGISTICS

Demand sources already exist in HAL:

- ammo: `RydHQ_Hollow`;
- fuel: `RydHQ_Dried`;
- repair: `RydHQ_damaged`.

Phase 1 publishes ammunition sling demand before provider selection. Package creation through `LOGISTICS_PACKAGE_AMMO` remains an Impasse/Checkbook responsibility and can occur independently of whether the player is currently flying a sling-capable helicopter.

Ammo reservation authority is the demand ledger plus recipient-group marker. Native ammo scanning temporarily excludes reserved groups through `RydHQ_ExReAmmo` only while the scan runs. `RydHQ_ASupportedG` remains native HAL bookkeeping, not C.L.A.S.H.'s reservation authority.

Once the assigned player has an appropriate helicopter and a compatible package exists, execution hands off to the existing player ammunition sling job logic. The human-only `assignedVehicle` compatibility fallback in native `SuppAmmo.sqf` remains valid as a fast/native compatibility seam, but it is no longer the mechanism by which a player discovers the mission.

Fuel and repair use the same demand ledger only after their exact native exclusion/request seams are identified and certified.

### MEDEVAC

Native HAL detects friendly wounded personnel in `SuppMed.sqf` and publishes `RydHQ_Wounded`. Severe casualties are those HAL already treats as high priority: alive personnel with damage above 0.75 or who cannot stand.

C.L.A.S.H. publishes a `MEDEVAC` demand for a severe friendly casualty group that is not already player-reserved.

MEDEVAC reservation authority is a C.L.A.S.H. marker on the casualty group, not `RydHQ_SupportedG`. During each native medical scan, reserved casualty groups are temporarily included in `RydHQ_ExMedic` so native AI does not select them; the original exclusion list is restored immediately afterward.

The player may receive the mission with no vehicle. Execution becomes active only when the assigned player arrives with a usable passenger-capable vehicle with enough seats.

Player MEDEVAC remains physical evacuation:

1. reach casualty/pickup;
2. physically embark surviving severe evacuees;
3. transport them to a live friendly service-home/base destination;
4. physically disembark them;
5. complete the task and release the player for further subscribed work.

Native `GoMedSupp` remains available to AI medical-support providers for needs not reserved to a player.

### TRANSPORT

Transport demand is intercepted at native `HAL_SCargo` request entry, before carrier selection.

A subscribed idle player may reserve the exact request while on foot or in an unsuitable vehicle. The stored demand includes requester, HQ, destination, mode/request flags, and seat requirement.

While reserved, the original SCargo invocation is deferred rather than allowed to choose an AI carrier. When the player presents a suitable carrier, the stored native request is resumed and HAL `SCargo` remains the sole physical GET IN / GET OUT and movement-task executor.

Existing carrier-home and terminal RTB hardening remain in force. Existing `NoAttack` / `NoRecon` / `NoDef` ferry retask protection is a separate execution-lifecycle projection and continues to reconcile every 0.5 s against SitRep rewrites.

### ARTILLERY

Current player artillery selection is capability-first: a human group is considered only after `EligibleVehicle` finds an already deployed, player-gunned artillery asset. That causes on-foot or wrong-vehicle subscribers to miss fire missions.

Demand-first interception occurs in the existing `RYD_CFF` wrapper before `EligibleVehicle`. HAL's target selection is captured as the demand. An ARTILLERY subscriber may reserve the target/fire requirement while still in preparation state.

The corresponding native CFF invocation is withheld while the player owns that fire requirement, preventing AI duplicate fire. On cancellation/liveness release, the stored request is returned to native arbitration if still valid or allowed to regenerate on the next HAL CFF cycle.

Only after the execution predicate is met does the existing shot-reporting, ammunition authorization, danger-close, firing-position emission, and impact-completion machinery arm.

### COMBAT

COMBAT is already the least equipment-dependent channel. Native HAL remains the tactical/physical task assigner. C.L.A.S.H. normalizes native assignment observation, occupation, cancellation, and terminal state into the common lifecycle but does not invent a second combat request scheduler.

Recon remains within COMBAT for now.

COMBAT admission projections (`NoRecon`, `CargoOnly`, and any later native exclusions) must be treated as SitRep-rewritten projections, not durable authority. They are reconciled/mirrored accordingly.

## Cancellation and disconnect behavior

The group leader remains the authority for explicit job cancellation.

The generic cancellation path understands the demand job ID before falling through to specialist/native cancellation handlers.

Cancellation must:

- mark the player task `CANCELED`;
- safely unwind execution if already active;
- release demand reservation;
- restore/reopen valid tactical demand;
- clear only C.L.A.S.H.-owned locks/flags/markers;
- add the cancelling group to the per-demand decline cooldown;
- increment the demand bounce count when valid work returns to `OPEN`;
- resynchronize employment state;
- never unsubscribe the player.

Disconnect, group loss, death, channel unsubscribe, and preparation-liveness expiry use the same release machinery where practical. Existing intentional transport carrier-loss behavior is not changed by this project.

## Execution predicates

Execution predicates are evaluated continuously but never erase the assignment merely because the player temporarily lacks capability.

Examples:

- TRANSPORT / MEDEVAC: a living movable vehicle with adequate passenger capacity at the pickup phase;
- LOGISTICS ammo sling: a living movable helicopter with sufficient sling mass capability for the reserved package;
- ARTILLERY: a valid deployed player artillery asset with authorized ammunition and player gunner;
- COMBAT: channel-specific operational conditions.

The current vehicle is therefore an execution input, never a subscription or dispatch input.

## Telemetry

The RPT must make the lifecycle and arbitration visible. Structured markers include:

- `player-demand-published`;
- `player-demand-reserved`;
- `player-demand-preparing`;
- `player-demand-progress`;
- `player-demand-liveness-expired`;
- `player-demand-decline-cooldown`;
- `player-demand-bounced`;
- `player-demand-ai-fallback-window`;
- `player-demand-suppression-asserted`;
- `player-demand-suppression-repaired`;
- `player-demand-native-scan-excluded`;
- `player-demand-native-scan-restored`;
- `player-demand-execution-ready`;
- `player-demand-executing`;
- `player-demand-released`;
- `player-demand-invalidated`;
- `player-demand-completed`.

Employment synchronization logs dispatchability and native executability separately so a line can truthfully show:

`dispatchable=true nativeExecutable=false`

for a subscribed player standing at base.

The SitRep projection audit must also log any detected C.L.A.S.H.-owned planning membership loss with the writer/cycle context so a future overwrite regression is visible immediately rather than inferred from hundreds of repairs.

## Implementation sequence

1. Treat merged PR #51 as the admission/cancellation baseline.
2. Source-identify the periodic HAL array overwrite and document its scope. **Done: Commander-B `HQSitRepB.sqf` projection rewrite identified.**
3. Add/retain `ITW_CLASH_PlayerDemandDispatch.sqf` after the player-task hardening layer.
4. Split dispatchability from native executability and stop using vehicle capability in `CanAcceptJob`.
5. Harden the demand ledger with named suppression metadata, liveness/progress state, per-demand decline cooldowns, bounce count, and AI fallback windows.
6. Convert LOGISTICS ammo to ledger/marker ownership plus call-scoped `ExReAmmo` native exclusion; certify on-foot/wrong-helicopter assignment and later existing sling execution.
7. Convert MEDEVAC to ledger/group-marker ownership plus call-scoped `ExMedic` native exclusion; certify physical evacuation.
8. Move TRANSPORT discovery to the `HAL_SCargo` request-entry seam while preserving SCargo as sole physical executor.
9. Move ARTILLERY assignment upstream of `EligibleVehicle` at the `RYD_CFF` seam while preserving existing artillery execution monitoring.
10. Normalize COMBAT onto the common lifecycle without duplicating HAL combat scheduling.
11. Identify and implement exact fuel/repair native suppression seams before enabling those LOGISTICS subtypes.
12. Add static regressions and hosted-Arma smoke telemetry for every transition and suppression path.

## Certification matrix

The build is not certified until all applicable rows pass.

| Area | Scenario | Expected result / evidence |
| --- | --- | --- |
| Dispatch doctrine | LOGISTICS subscribed, player on foot | Ammo need is assigned; task says acquire sling capability. No vehicle gate appears in dispatch admission. |
| Dispatch doctrine | LOGISTICS subscribed, player in non-sling helicopter | Same assignment; no silent rejection. |
| Execution handoff | Player later acquires valid sling helicopter | Existing `PlayerAmmoJob` arms and can complete the same reserved demand. |
| MEDEVAC dispatch | MEDEVAC subscribed, player on foot | Severe friendly casualty demand is assigned without vehicle requirement. |
| MEDEVAC execution | Player later acquires sufficient passenger vehicle | Casualties physically board, are delivered to live-resolved friendly home, physically disembark, demand completes. |
| Transport dispatch | TRANSPORT subscribed, player has no carrier | Exact native SCargo request is visible/reservable before carrier selection. |
| Transport execution | Player later presents enough passenger seats | Stored native request resumes through SCargo; no parallel GET IN/GET OUT executor runs. |
| Artillery dispatch | ARTILLERY subscribed, player has no gun | HAL fire demand is visible/reserved before `EligibleVehicle`; AI does not fire the same reserved request. |
| Artillery execution | Player later deploys valid artillery | Existing shot authorization/impact validation arms and completes normally. |
| Cancellation | Player cancels a still-valid RESERVED job | Task cancels, demand returns OPEN, subscription remains enabled, cancelling group receives per-demand cooldown. |
| Cancellation | Player cancels EXECUTING job | Specialist executor performs safe unwind before release; no orphaned package/casualty/contract. |
| Re-entry | Same player cancels then dispatcher polls immediately | Same demand is not immediately re-offered to that player. |
| Bounce control | Valid demand bounces three times | Player offers pause for AI fallback window; native suppression is absent; demand does not disappear. |
| Liveness | Player disconnects/dies while RESERVED | Immediate release to OPEN if demand still valid. |
| Liveness | Player unsubscribes from active demand channel | Immediate release to OPEN without modifying other subscriptions. |
| Liveness | Player makes no meaningful preparation progress for 10 minutes | `preparation-liveness-expired`; valid demand reopens and cooldown prevents immediate same-player loop. |
| Liveness | Player continues meaningful preparation beyond 10 total minutes | Lease keeps renewing; job is not cancelled merely because total preparation time is long. |
| Demand validity | Underlying need vanishes while RESERVED | Task invalidates; demand is not requeued. |
| Execution ownership | HAL source array changes after specialist enters EXECUTING | Active physical executor keeps terminal ownership; generic demand loop does not tear it down. |
| Ammo suppression | Ammo demand is player-reserved across multiple SitRep cycles | Native ammo scan excludes reserved recipient via call-scoped `ExReAmmo`; no duplicate AI `GoAmmoSupp`. No persistent C.L.A.S.H. `ASupportedG` lock exists. |
| MEDEVAC suppression | Casualty demand is player-reserved across multiple SitRep cycles | Native med scan excludes reserved casualty group via call-scoped `ExMedic`; no duplicate AI `GoMedSupp`. No persistent C.L.A.S.H. `SupportedG` lock exists. |
| SitRep overwrite | `HQSitRepB` rewrites `NoAttack`/`NoRecon`/`NoDef` during active ferry lock | 0.5 s reconciler restores only C.L.A.S.H.-owned memberships; telemetry proves repair. |
| Employment state | Player has subscribed work but no current capability | RPT shows `dispatchable=true nativeExecutable=false`. |
| Fail-open | No eligible subscribed player exists | Native HAL support/transport/artillery path remains available; player system does not swallow demand. |
| Ownership | AI and player are both candidates | Exactly one owns physical execution of the same request. |
| Persistence | Completed/cancelled demand ends | Only C.L.A.S.H.-owned marker/projection is cleared; unrelated native state is preserved. |

## Release blockers

No demand-first channel ships until:

- its exact native demand source is named;
- its exact duplicate-execution suppression seam is named;
- long-lived authority is outside SitRep-rewritten HQ arrays or is continuously reconciled with an explicit source-of-truth mirror;
- cancel/release restores native eligibility;
- disconnect/death/unsubscribe/liveness expiry return valid work;
- same-player re-offer loops are prevented;
- repeated bounces expose the request to AI rather than starving it;
- fail-open behavior is proven;
- static regression coverage exists;
- hosted RPT telemetry proves no simultaneous AI/player execution.

## Non-goals / preserved behavior

- Do not make C.L.A.S.H. a second battlefield commander.
- Do not bypass Impasse budgets, tickets, or strategic spawning.
- Do not create a second physical HAL transport executor; SCargo remains authoritative.
- Do not reinterpret enemy GroundMEDEVAC/CASEVAC as the player BLUFOR system.
- Do not change the intentionally preserved transport carrier-loss behavior.
- Do not remove native capability checks where HAL needs them to select a physical executor.
- Do not use a persistent `RydHQ_ASupportedG` or `RydHQ_SupportedG` mutation as player-demand ownership.

## Definition of done

The employment menu is considered truthful when selecting a channel means:

> **"Tell me when this kind of work exists."**

and not:

> **"Only tell me if my current vehicle happens to match the job during this polling cycle."**

The battlefield is considered safe when a reserved request cannot be silently stolen by AI, cannot remain abandoned forever, cannot immediately loop back to the same declining player, and cannot disappear merely because ownership changed hands.

That is the contract this implementation must preserve.