# C.L.A.S.H. / Supermod Implementation Audit

**Status:** First-pass implementation audit  
**Date:** 2026-08-08  
**Scope:** Impasse Total War mission integration with NR6 HAL 1.26.2 RC1  
**Audit mode:** Read-only source inspection; no mission or HAL package was modified or repacked

## Executive conclusion

C.L.A.S.H. is feasible, but it is not safe as a module-only or direct “add every group to HAL” integration.

Impasse and HAL are both tactical order writers. Impasse currently assigns objectives, replaces waypoints, garrisons units, teleports stalled groups, merges groups, owns transport, and destroys or resets forces during phase changes. HAL performs many of the same tactical actions for its included groups. If both systems retain tactical authority over the same group, waypoint tug-of-war and stale state are guaranteed.

The safest design is a small server-side **C.L.A.S.H. arbitration bridge** with a strict ownership contract:

- Impasse remains the campaign director, authority for capture/progression, spawner, ticket and budget owner, transport controller, save/load owner, cleanup owner, and source of truth for factions.
- HAL controls tactics only for explicitly registered, eligible frontline ground groups after deployment.
- The bridge classifies groups, performs delayed handoff, mirrors the active Impasse objectives into HAL, unregisters groups before Impasse resets them, and records enough telemetry to prove that neither system violates the contract.

The first implementation should be a disabled-by-default observability tranche, followed by a one-side, dismounted-infantry pilot. Vehicles, native HAL reinforcements, bidirectional fronts, persistent HAL tactical state, and HAL-driven requisitions should remain out of the initial release.

## Audit inputs and source of truth

| Input | Role | Audit disposition |
|---|---|---|
| `13715765820790864929_legacy.bin` | Current Impasse mission baseline | Authoritative frozen parity oracle |
| `mission(1).pbo` | Earlier Impasse mission | Provenance/diff only; rejected as a build base |
| `NR6 Hal.zip` / `nr6_hal.pbo` | HAL source under evaluation | HAL 1.26.2 RC1 integration target |
| NR6 Reinforcements / Air Reinforcements | Optional HAL companion systems | Inspected; excluded from C.L.A.S.H. runtime |
| 26th USMC asset PBOs and faction configs | Separate faction inputs | Excluded from this integration audit |

The current mission contains 86 extracted files versus 75 in the old PBO. The current baseline adds or changes major systems including objectives, attacks, bases, bombardment, rally points, side operations, targets, saving, factions, and several SKULL helpers. Building from `mission(1).pbo` would discard substantial current functionality.

The repository should become the implementation source of truth when access is restored. The frozen current mission remains the behavioral parity oracle until the repository build is proven equivalent.

### Baseline checksums

| Artifact | SHA-256 |
|---|---|
| Current Impasse baseline | `c0221d9ed4291c1293985808b438754198848b54987f50a9877ef15e83c16401` |
| Old Impasse PBO | `1d1026cee91ad9c7627e2f967115e3f66acfe4d3b119fec2cbbef53e4afb8019` |
| NR6 HAL archive | `5443bb459a056c58b755ffaf9784b658f1dcd004bc3f259373f0ed92fbacdfef` |

## Recovered design baseline

The prior feasibility work established these constraints for the first implementation:

- Preserve Impasse’s current one-way campaign structure: three active objectives, OPFOR defending, BLUFOR advancing, and captured zones becoming bases/FOBs.
- Preserve current spawning, tickets, save/load, cleanup, transport, faction selection, and phase progression.
- Keep bidirectional fronts, counteroffensives, HQ disruption, strategic retreat, and campaign-failure mechanics for a later layer.
- Disable HAL auto-subordination with `RydHQ_SubAll = false`; include only approved groups.
- Start server-only, without handing HAL-managed groups to an Impasse headless-client path.
- Exclude player and teammate groups, base groups, garrisons, aircraft, artillery/CAS, logistics and transports, empty vehicles, garage/construction forces, and any undeployed cargo group.
- Hand infantry to HAL only after delivery and dismount are complete.
- Rebuild HAL’s tactical objective set whenever the active Impasse zone changes.
- HAL may eventually request force capabilities, but Impasse must approve, substitute, defer, or deny the request and perform all spawning and ticket/budget accounting.

Two decisions are still open and must not be silently invented:

1. The first live commander topology: OPFOR-only pilot or simultaneous BLUFOR/OPFOR commanders.
2. Whether special forces should be the only reconnaissance-capable groups. HAL’s classifications make that a deliberate policy implementation, not a single safe switch.

## Ownership contract

| Capability | Impasse | HAL | C.L.A.S.H. bridge |
|---|---:|---:|---:|
| Campaign phase and active zone | **Owner** | Mirror only | Synchronize |
| Objective capture and progression | **Owner** | Never authoritative | Mirror state and reset |
| Spawning and force composition | **Owner** | No direct spawn | Validate requests later |
| Tickets, weights, and budgets | **Owner** | Read-only | Audit invariants |
| Transport selection and movement | **Owner** | Disabled for managed groups | Detect completed handoff |
| Save/load schema | **Owner** | No tactical persistence initially | Rehydrate derived state |
| Cleanup, deletion, merging, phase reset | **Owner** | Must release first | Unregister and reconcile |
| Frontline ground tactics | Suppressed only after handoff | **Owner for registered groups** | Enforce exclusivity |
| Air, artillery, CAS, logistics, bases, garrisons | **Owner** | Excluded | Enforce exclusions |
| Player/teammate command | **Owner/current behavior** | Excluded | Enforce exclusions |
| Tactical telemetry and contract violations | Source events | Source events | **Owner** |

The bridge must never become a second campaign system. It is an adapter and arbitrator.

## Confirmed integration seams

### 1. Startup and locality

`preInit.sqf` compiles the mission systems. `init.sqf` waits for parameters/pre-init, may start the existing Impasse headless-client handler, and then launches `ITW_Start.sqf`. On the server, `ITW_Start.sqf` initializes vehicles, loads or creates objectives, starts enemy and ally managers, starts cleanup, sets game-ready state, and saves the start state.

The bridge should be compiled in `preInit.sqf` and initialized from the server path in `ITW_Start.sqf` only after the mission’s initial load/objective setup is complete. HAL group control should remain server-local for the first implementation. Existing Impasse HC distribution must not relocate HAL-managed groups.

### 2. Group creation and classification

`ITW_EnemyInit` and `ITW_AllyInit` each start `ITW_AtkManager` with side-specific data and a group callback. The attack manager invokes those callbacks for several materially different group types:

- ordinary on-foot squads;
- delivery squads;
- zone-population squads;
- vehicle crews;
- vehicle cargo groups; and
- other phase-specific forces.

Therefore, the existing callback is a useful **discovery event**, but it is too broad to be a direct HAL-registration hook. The bridge must classify every discovered group and retain an explicit reason when it is excluded or waiting.

Recommended group states:

| State | Meaning |
|---|---|
| `DISCOVERED` | Impasse callback observed the group |
| `WAITING_TRANSPORT` | Cargo/delivery is still controlled by Impasse |
| `ELIGIBLE` | Group passes all current policy checks |
| `HAL_MANAGED` | Registered and HAL is the sole tactical waypoint writer |
| `QUIESCING` | HAL orders are being stopped before reset/cleanup |
| `RELEASED` | Returned to Impasse or no longer eligible |
| `DELETED` | Group no longer exists; all HAL references removed |

### 3. Transport handoff

Impasse creates cargo groups before moving them and calls the group callback at vehicle population time. That callback is too early for HAL.

`ITW_AtkVehicleManager` provides the clean handoff seam. It detects when a transport has no cargo remaining and clears its tracked cargo groups after the relevant land, helicopter, ship, or airplane unload path. A group becomes eligible only when all of the following are true:

- it is no longer assigned as tracked transport cargo;
- its living units are physically out of transport;
- it is not a delivery, player, teammate, garrison, base, support, logistics, air, artillery, construction, or vehicle-crew group;
- its group is local to the server; and
- the active objective generation has not begun a transition.

HAL cargo tasking should be disabled for managed groups with the appropriate `NoCargo` policy. Impasse remains the sole transport authority.

### 4. Tactical waypoint ownership

`ITW_AtkInfantryManager` runs periodically and performs tactical work on eligible foot infantry. It assigns or reassigns objective variables, replaces waypoints, garrisons units, moves stalled/far forces, and merges small groups. HAL also assigns tactical orders and waypoints.

This is the primary release blocker. The bridge cannot merely append groups to `RydHQ_Included`. Impasse’s group selection must be split into two concepts:

- **Lifecycle inventory:** groups Impasse still owns for accounting, cleanup, merging policy, and phase transitions.
- **Impasse tactical eligibility:** lifecycle groups that are not currently HAL-managed and may receive Impasse tactical orders.

Removing HAL groups from `ITW_AtkGetInfantryGroups` globally would be unsafe because that function is also used by cleanup and transition paths. Either add an explicit selection mode or create a separate lifecycle-inventory function. All tactical order-writing paths must respect `ITW_CLASH_Managed`; lifecycle paths must continue to see those groups.

### 5. Objective authority and zone transitions

`ITW_ObjFlagCapture` calculates capture from conscious units. When the current objective set is complete, it raises `ITW_ObjZonesUpdating`, calls `ITW_ObjNext`, then clears the transition state. `ITW_ObjNext` is the authoritative campaign seam: it marks captured objectives, converts prior zones into bases, invokes `ITW_AtkNext`, rebuilds contested state and mission objects, and saves the new zone.

HAL simple objectives (`RydHQ_SimpleObjs`) can represent Impasse’s three active objectives, but HAL also maintains its own `SetTaken*` and `RydHQ_Taken` state and can independently infer capture from nearby units. That state must be treated as a mirror only. It may never trigger `ITW_ObjNext` or other campaign progression.

Required transition order:

1. Observe `ITW_ObjZonesUpdating` and stop new registrations.
2. Quiesce and unregister all managed groups.
3. Allow Impasse’s `ITW_AtkNext` cleanup/reset to complete.
4. Remove old HAL objective, taken, capturing, and order state.
5. Create three new simple objective objects at Impasse’s active objective positions.
6. Mirror `ITW_ObjContestedState` into HAL ownership fields.
7. Execute a tested HAL reset protocol.
8. Re-evaluate and register only surviving eligible groups.

HAL reset behavior requires a targeted runtime test. In this package, `RydHQ_ResetOnDemand = true` causes the main cycle to wait for `RydHQ_ResetNow`; it is not a harmless “permit manual reset” flag. The integration must not blindly toggle it.

### 6. Save/load

Impasse persists objectives, bases, captured state, airfield, rally point, warships, teammates, fortifications, stored vehicles, side operations, date, and selected parameters in `profileNamespace`. It does not persist live frontline tactical groups.

This is useful: the first bridge should persist no HAL tactical state and should not change the save schema. On load, it should rebuild the three HAL objective mirrors from the loaded Impasse zone and rediscover eligible groups after mission readiness. This reduces compatibility risk and keeps existing saves valid.

### 7. HAL inclusion and excluded companion systems

HAL defaults `RydHQ_SubAll` to true and builds its controlled force list from subordinate groups plus `RydHQ_Included`, minus exclusions. C.L.A.S.H. must set `RydHQ_SubAll = false` before HAL initialization and make `RydHQ_Included` a bridge-managed allow-list.

NR6 Reinforcements and Air Reinforcements directly use `createGroup`, `createUnit`, `BIS_fnc_spawnGroup`, `createVehicle`, and `createVehicleCrew`. Enabling them would bypass Impasse tickets, force weights, budget rules, cleanup metadata, and transport ownership. They are not part of the C.L.A.S.H. runtime.

HAL secondary tasks should be disabled to avoid duplicating Impasse tasks. HAL transport/cargo control should be disabled for bridge-managed groups.

## Risk register

| Severity | Risk | Failure mode | Required control |
|---|---|---|---|
| Blocker | Dual waypoint ownership | Impasse and HAL continuously replace each other’s orders | Split lifecycle from tactical selection; assert one writer |
| Blocker | Premature transport handoff | HAL orders cargo before Impasse unload is complete | State-machine handoff after physical dismount and cargo unlink |
| Blocker | Objective split-brain | HAL and Impasse disagree on taken/current objectives | Impasse-only authority; mirrored HAL state; ordered reset |
| Blocker | Locality/HC collision | HAL commands non-local groups or groups migrate mid-order | Server-only pilot; exclude HAL-managed groups from HC transfer |
| Blocker | Stale/deleted group references | HAL retains groups destroyed by cleanup or phase reset | Unregister before reset; periodic reconciliation |
| High | Incorrect HAL reset semantics | HQ loop stalls or old orders survive a zone change | Isolated reset harness and explicit quiesce protocol |
| High | Native HAL spawning | Tickets/budgets diverge from Impasse | Do not enable HAL reinforcement modules |
| High | Group merge/identity mutation | HAL tracks a deleted group while Impasse creates/merges another | Disable Impasse tactical merges for HAL-managed groups or bridge-aware merge transaction |
| High | Category contamination | Players, garrisons, transports, support, air, or base groups enter HAL | Central policy classifier, deny by default, auditable reasons |
| High | Save/load race | HAL registers before Impasse restores the active zone | Initialize after mission-ready/load and rebuild derived state |
| Medium | Duplicate tasks/radio | HAL creates competing player-facing objectives | Disable HAL secondary tasks and player task creation |
| Medium | Performance | HAL repeatedly scans more mission entities than necessary | Explicit allow-list, capped cadence, telemetry |
| Medium | Recon policy mismatch | Ordinary or SOF groups receive unintended recon roles | Defer policy; test `NoRecon`/`ROnly` classification explicitly |

## Recommended implementation sequence

### Tranche 0 — Repository and parity gate

- Restore repository access and identify its buildable mission root.
- Create a feature branch such as `feature/clash-phase-0`.
- Build the repository without C.L.A.S.H. changes and compare its unpacked output to the current baseline.
- Resolve differences before integration. Do not use the old PBO to seed the repository.
- Record the current baseline checksum in the repository’s audit/test documentation.

**Exit gate:** the repository is demonstrably the source for the current mission or every intended difference is documented.

### Tranche 1 — Disabled observability bridge

Add an `ITW_CLASH.sqf`-style server component, compiled during pre-init and guarded by a disabled-by-default mission parameter. It should not include any group in HAL yet.

It should:

- observe group discovery callbacks;
- classify every group with a single eligibility function;
- track transport and dismount state;
- mirror active objective metadata without enabling orders;
- observe zone transitions, deletions, and group merges;
- report would-register/would-release events;
- report any candidate that receives a conflicting Impasse tactical order; and
- expose a compact diagnostic snapshot for server logs/admin testing.

**Exit gate:** a full zone can be played with zero behavioral difference from the baseline, while the audit log correctly explains every group decision.

### Tranche 2 — One-side, dismounted-infantry pilot

Recommendation: start with the defending OPFOR commander because that limits the pilot to the current one-way campaign’s defensive side. This is a recommendation, not a recovered final decision.

- Set `RydHQ_SubAll = false` before HAL starts.
- Register only ordinary, server-local, fully dismounted OPFOR infantry.
- Exclude vehicles, crews, garrisons, delivery groups, players, teammates, support, logistics, air, artillery, bases, and construction.
- Disable HAL cargo behavior and player-facing secondary tasks.
- Suppress only Impasse’s tactical waypoint-writing for `ITW_CLASH_Managed` groups.
- Keep the groups visible to Impasse lifecycle, ticket, cleanup, and zone-transition paths.
- Quiesce/unregister on death, deletion, re-embarkation, category change, and phase transition.

**Exit gate:** no double waypoint writes, no stale HAL groups, no ticket or force-count divergence, and deterministic zone transitions across repeated dedicated-server runs.

### Tranche 3 — Second commander and expanded ground roles

After a commander-topology decision, add a second namespace/commander if both sides are to use HAL. Repeat objective mirroring and inclusion state separately per side. Expand role coverage one category at a time. Armor should follow infantry only after locality, crew, recovery, transport, and cleanup policies are proven.

### Tranche 4 — Requisition adapter

HAL must not create reinforcements directly. Add a capability request API with a small vocabulary such as infantry, anti-armor, armor, reconnaissance, transport, or air defense. Impasse evaluates current phase, tickets, weights, availability, faction pools, and cooldowns, then approves, substitutes, defers, or denies. Approved forces are spawned by existing Impasse paths and enter the same discovery/handoff state machine.

### Deferred campaign layer

Do not combine the initial HAL integration with reversible fronts, counteroffensives, strategic retreat, HQ disruption, or campaign defeat. Those mechanics change Impasse’s campaign authority and save schema and should be designed after the tactical contract is stable.

## Proposed bridge surface

The exact names can follow repository conventions, but responsibilities should remain small and explicit:

| Function | Responsibility |
|---|---|
| `ITW_CLASH_InitServer` | Configure HAL and start bridge after Impasse load/setup |
| `ITW_CLASH_DiscoverGroup` | Record group callback without assuming eligibility |
| `ITW_CLASH_ClassifyGroup` | Return state, eligibility, and one or more exclusion reasons |
| `ITW_CLASH_RegisterGroup` | Add eligible group to the correct explicit HAL include list |
| `ITW_CLASH_ReleaseGroup` | Stop HAL ownership and clear bridge/HAL references |
| `ITW_CLASH_OnTransportComplete` | Re-evaluate a physically dismounted group |
| `ITW_CLASH_BeginZoneTransition` | Freeze admission and quiesce managed groups |
| `ITW_CLASH_SyncObjectives` | Rebuild three HAL mirrors from Impasse state |
| `ITW_CLASH_EndZoneTransition` | Reconcile survivors and resume admission |
| `ITW_CLASH_Reconcile` | Remove null/stale groups and detect policy violations |
| `ITW_CLASH_Diagnostics` | Emit counts, states, reasons, and invariant failures |

All registration should be idempotent. All release operations should tolerate null/deleted groups. Classification should deny by default when a category is unknown.

## Verification matrix

### Required scenarios

- Fresh new campaign start.
- Load an existing save.
- Dedicated server with no HC.
- Join-in-progress before and after mission-ready.
- No-player pause/unpause behavior.
- Land, helicopter, ship, and airplane troop delivery.
- Cargo group death or vehicle loss before unload.
- One objective captured; all three captured; full zone transition.
- Defend-phase transition and return to attack progression.
- Group casualties, deletion, re-embarkation, and small-group merge conditions.
- Player recruit/teammate, base, garrison, construction, logistics, air, artillery, and vehicle-crew exclusions.
- Mission restart and saved-game rehydration.

### Instrumented invariants

1. Every HAL-controlled group has `ITW_CLASH_Managed = true` and a current objective-generation ID.
2. No managed group appears in an Impasse tactical-order pass.
3. Every managed group remains visible to Impasse lifecycle accounting.
4. No excluded-category group appears in a HAL include/friend/order array.
5. No group is registered while it or its living units are transport cargo.
6. No HAL native reinforcement path creates a group or vehicle.
7. HAL objective count equals the active Impasse objective count for the current zone.
8. HAL taken state equals the bridge’s mapping of `ITW_ObjContestedState`.
9. A zone transition leaves no previous-generation objective or group reference in HAL.
10. Tickets, force weights, objective progression, save keys, and cleanup outcomes remain parity-compatible with the baseline.

## Go/no-go criteria for the first live pilot

The first HAL-controlled build is a **go** only when all of the following pass:

- repository baseline parity is established;
- the bridge can run disabled with no baseline behavior change;
- a complete zone produces zero dual-waypoint violations;
- all transport types hand off only after physical dismount;
- excluded categories produce zero false registrations;
- zone reset removes all stale HAL objective and group state;
- mission tickets, spawning weights, campaign progression, and save format remain owned by Impasse; and
- repeated dedicated-server runs are deterministic enough to diagnose any remaining variance.

If any blocker fails, HAL group registration should stay disabled. The observability bridge can still ship as a diagnostic tool.

## Immediate next action

Once repository access works, begin Tranche 0 in Git rather than modifying or repacking the frozen PBOs. The first code change should be the disabled observability bridge and classification state machine—not live HAL inclusion. That establishes the contracts needed to integrate safely and gives the project a rollback switch from its first commit.
