# C.L.A.S.H. Ownership Contract

> **No system stores another system's answer; it stores the question, and asks at use time.**

This is the primary architectural rule for C.L.A.S.H.-Impasse. Any change that copies a position, count, ownership flag, task state, or role across an authority boundary must explain why the copied value cannot become stale before it is consumed.

## Authority map

### Impasse owns
- campaign progression
- objective/base ownership and the `ITW_Bases` graph
- tickets/economics
- physical vehicle accounting (`ITW_VEH_COUNT` / `ITW_VEH_MAX`)
- force generation and materialization

### HAL owns
- battlefield planning
- tactical task selection
- attack/defense/recon/support employment
- HAL `SCargo` transport execution for HAL-originated transport requests
- tactical support demand such as ammunition need and wounded personnel

### C.L.A.S.H. owns
- authority transitions between Impasse and HAL
- compatibility and lifecycle state neither system natively understands
- explicit service leases
- temporary retask/quarantine locks
- player-demand reservation and player-facing task lifecycle
- reconstitution transit handoff
- observation and telemetry across ownership seams
- terminal task-state assertions when native HAL exposes a task with no live completion path

## The rule in practice

- `vehDef` stores class/configuration and native accounting state, not per-deployment service state.
- `ITW_CLASH_ServiceLease` stores an explicit runtime grant, not an inferred vehicle role.
- HAL transport contracts store task identity and destination, not a cached interpretation of boarding state.
- `baseHint` stores which Impasse base should be asked first, not a frozen coordinate returned by that base earlier.
- service RTB resolves its destination against live `ITW_Bases` ownership at order time and periodically while returning.
- transient player HAL carriers ask the same service-home resolver for the `START + str group` compatibility value; they are not registered into the persistent service pool.
- a virtual service pool entry is a paid entitlement, not an invisible reserved Impasse vehicle slot.
- HAL planning arrays are lossy metadata. If an authority invariant depends on membership, the owning lifecycle continuously reconciles that projection rather than assuming a one-time write is durable.
- A player employment subscription stores **willingness to accept a category of work**, not a cached answer about the player's present vehicle.
- Current player equipment is resolved at the physical execution step. When native HAL consumes a legacy AI bookkeeping field such as `assignedVehicle`, C.L.A.S.H. may provide a player-only compatibility fallback to the actual current asset; native AI semantics remain unchanged.

## Player employment demand contract

The player employment rule is:

> **Subscription gates dispatch. Capability gates execution.**

A subscribed player can receive a LOGISTICS, TRANSPORT, MEDEVAC, ARTILLERY, or COMBAT assignment while on foot or while occupying an unsuitable asset. The task tells the player what the battlefield needs and what capability must be acquired. The player may then acquire the required asset or explicitly cancel the job.

C.L.A.S.H. keeps two different runtime answers because HAL and the player dispatcher are asking different questions:

- **player dispatchability**: is this living human group subscribed, idle, and free of an authority hold?
- **native HAL executability**: does the group currently possess the physical capability HAL needs for native provider execution?

A valid state is therefore `dispatchable=true nativeExecutable=false`. `ITW_CLASH_PlayerTaskDispatchable` and `ITW_CLASH_PlayerNativeExecutable` expose those answers separately.

`Unable` and `BUnable` remain native-HAL physical execution controls. They must not be used as the reason a C.L.A.S.H. subscriber never learns that work exists.

### Demand ownership

HAL remains the tactical source of truth for whether support is needed and, where native logic already selects a target, which target HAL chose. C.L.A.S.H. does not clone that target-selection logic merely to create a player task.

When HAL exposes or selects a valid requirement, C.L.A.S.H. may publish it into `ITW_CLASH_PlayerDemands` and reserve that exact requirement for a subscribed player. Reservation is an arbitration seam:

- the demand ledger records the player owner;
- long-lived reservation authority is a C.L.A.S.H.-owned ledger entry/marker or deferred native-call contract, not a HAL HQ-array membership;
- any native exclusion projection used to keep AI from consuming a reserved demand is either call-scoped and restored immediately or continuously reconciled if it truly must persist;
- the player may remain in preparation state without a fixed equipment-acquisition deadline, but the reservation must satisfy a progress/liveness lease;
- capability is re-evaluated at the execution step;
- completion consumes the reservation;
- explicit cancellation releases a still-valid requirement without changing employment subscriptions;
- disconnect/death/unsubscribe/authority loss or preparation-liveness expiry releases still-valid work;
- a per-demand decline cooldown prevents immediate same-player re-offer;
- repeated bounces deliberately expose the request to native AI for a fallback window so demand cannot be starved by player arbitration;
- if the underlying battlefield requirement vanishes, the demand is invalidated rather than requeued.

For native support paths such as ammunition and medical support, the preferred seam is the native scan and final assignment handoff. If no player owns the request, native execution remains fail-open. If a player owns the request, C.L.A.S.H. excludes that exact target from the synchronous native support scan and restores the original exclusion input immediately afterward. A final `Go*Supp` marker check blocks a same-cycle race without turning supported arrays into long-lived reservation state.

### Player logistics demand

HAL ammunition need is discovered through its native ammo-support logic and `RydHQ_Hollow`. A demand-first LOGISTICS assignment may be delivered to a player before the player has a sling-capable helicopter.

- The preparation task states the recipient and required sling capability.
- The durable player reservation is `ITW_CLASH_PlayerAmmoDemandReservation` on the recipient group plus the demand ledger entry.
- While the player reservation exists, native `HAL_SuppAmmo` is called with the reserved group temporarily included in `RydHQ_ExReAmmo`; the exact pre-call exclusion list is restored immediately afterward.
- `RydHQ_ASupportedG` remains native HAL assignment bookkeeping. If C.L.A.S.H. intercepts an already-selected native assignment, it may clear only the assignment marker HAL just wrote as takeover cleanup; it is not the durable player lock.
- Because `ExReAmmo` suppresses native `RydHQ_Hollow` publication for that reserved target, reserved ammo validity is resolved directly from the selected group's ammo state using the equivalent native need criteria rather than treating absence from `Hollow` as cancellation.
- Impasse/Checkbook may materialize the ammunition package through the existing `LOGISTICS_PACKAGE_AMMO` provider.
- When the assigned player later presents a compatible sling-capable helicopter and package, execution hands off to the existing `ITW_CLASH_PlayerTasks_fnc_PlayerAmmoJob` physical sling executor.
- C.L.A.S.H. does not add a second sling movement executor.
- Cancelling before or during recoverable execution releases the valid ammo need rather than deleting it.

The legacy human-only `assignedVehicle` compatibility fallback remains useful for already-capable player providers, but it is no longer the mechanism by which a subscriber discovers that logistics work exists.

### Player MEDEVAC demand

Native HAL `SuppMed` provides friendly casualty knowledge in `RydHQ_Wounded` and treats living personnel with damage above `0.75` or who cannot stand as severe casualties. Native `GoMedSupp` is medical assistance/healing, not casualty evacuation.

C.L.A.S.H. may reserve a severe HAL medical requirement for a MEDEVAC subscriber and replace that one native medical-support execution with a player casualty-extraction lifecycle:

- the durable reservation is `ITW_CLASH_PlayerMedevacDemandReservation` on the casualty group plus the demand ledger entry;
- while the reservation exists, native `HAL_SuppMed` is called with that group temporarily added to `RydHQ_ExMedic`, then the original list is restored immediately;
- `RydHQ_SupportedG` remains native assignment bookkeeping rather than C.L.A.S.H. reservation authority;
- a same-cycle final handoff guard prevents duplicate native `GoMedSupp` if a native selection raced the new player marker;
- the player receives the casualty mission regardless of current vehicle;
- execution waits until the player reaches the casualty with a grounded/stopped passenger-capable vehicle with sufficient seats;
- severe casualties are physically loaded for evacuation;
- the destination is resolved against the live friendly service-home/base graph at use time;
- casualties are physically unloaded at that live friendly destination;
- the demand completes and native medical support becomes available again for any continuing treatment need.

Enemy GroundMEDEVAC/CASEVAC remains the OPFOR withdrawal/reconstitution system and is not reinterpreted as the BLUFOR player MEDEVAC system.

## Service-home contract

Registration may store or refresh:
- `baseHint`
- `baseHintSource`
- physical vehicle/group references
- `deploymentOrigin` for local lifecycle heuristics

Registration must not replace a resolver-owned home with a raw position snapshot.

Only the service-home resolver writes authoritative RTB-home state:
- `homeBaseIndex`
- `homeMethod`
- `homeResolvedPos`
- `homeResolvedAt`
- compatibility `home`
- `ITW_CLASH_ServiceHome`
- `START + str group`

`START` is compatibility output, never the source of truth for selecting a base. This applies both to leased service crews and to transient player-flown HAL transport carriers.

RTB resolution order:
1. Validate `baseHint` against current side ownership and `ITW_BASE_SPAWNED`.
2. If valid, resolve that live base (`request-base`).
3. Otherwise choose the nearest currently friendly spawned base (`nearest-base`).
4. For ships, project the resolved base through SeaGuard's bounded local-water resolver (`water-node`). SeaGuard answers where a hull can float; it does not own home selection.
5. If no friendly spawned base can be resolved, preserve a valid compatibility `START` only as `fallback-start`; never invent `[0,0,0]`.

`homeResolvedAt` is load-bearing. An RTB asset is re-resolved on a time cadence even when it is making progress, because progress toward a base that has fallen is still wrong. A new waypoint is issued only when the newly resolved physical destination moves by the configured change threshold; otherwise metadata is refreshed without resetting AI pathing.

## Player HAL transport RTB

Native `SCargo` remains the sole movement executor. C.L.A.S.H. may make its RTB input honest and may supply the missing terminal task transition, but it must not issue player movement, waypoint, or landing commands.

- Both native terminal shapes are covered: `Abort Pick Up, RTB` and post-delivery `Return To Base`.
- The task marker/RTB coordinate comes from resolver-owned `START + str group`.
- Terminal completion requires the contracted cargo to be physically unlinked and the carrier to satisfy HAL's intended landed/stopped semantics at the RTB destination.
- HAL's original stopped-timeout behavior is preserved so an unsatisfiable RTB task cannot remain permanently assigned.
- After terminalization, persistent employment subscriptions are re-synchronized; RTB completion does not unsubscribe the player.

## Player HAL logistics provider compatibility

Native `SuppAmmo` historically re-resolves providers with `assignedVehicle`, which is reliable for AI-assigned crews but may be null for a player who manually entered a purchased aircraft.

- Native AI providers continue to use `assignedVehicle` exactly as before.
- Only a provider group containing a human may fall back from null `assignedVehicle` to `vehicle leader _group`.
- This compatibility seam does not select a logistics target, manufacture an ammo demand, or bypass HAL's tactical arbitration.
- Once HAL selects an already-capable player ammo-drop provider, `HAL_GoAmmoSupp` is intercepted into the existing C.L.A.S.H. player sling job; native HAL movement execution is not run for that player job.
- `provider-current-vehicle-fallback` telemetry proves when the compatibility path was required during a hosted smoke.

## Planning-array contract

Commander-B `HQSitRepB.sqf` periodically reprojects `RydHQB_*` globals onto the HQ object. This is the source of the previously observed roughly cycle-length loss of object-side memberships such as:

- `RydHQ_NoAttack`;
- `RydHQ_NoRecon`;
- `RydHQ_NoDef`;
- `RydHQ_ASupportedG`;
- `RydHQ_SupportedG`.

Therefore these arrays are **projections of authority, not the authority itself**.

- Durable player ammo/MEDEVAC reservation does not live in `ASupportedG`/`SupportedG`; it lives in demand markers and the ledger.
- Ammo/medical native exclusions are call-scoped through `ExReAmmo`/`ExMedic` and restored synchronously.
- If an already-selected native support assignment is taken over, clearing the just-written supported-array membership is assignment-handoff cleanup only.
- A live ferry retask lock owns explicit C.L.A.S.H. lock state and continuously reasserts `NoAttack`/`NoRecon`/`NoDef` because those memberships must remain visible to HAL during the physical ferry lifecycle.
- Any future long-lived projection that depends on a Commander-B array must either mirror the correct `RydHQB_*` source or continuously reconcile the HQ-object membership with explicit ownership telemetry.
- Cleanup removes only memberships/markers recorded as C.L.A.S.H.-owned.

A one-time object-array write is never accepted as durable cross-system authority.

## Review test

For every future patch that crosses Impasse/HAL/C.L.A.S.H. authority, ask:

> Are we storing the authority's question/reference and resolving the answer when it is needed, or are we caching an answer that can stop being true?

The DUAL service misclassification, shadow vehicle-count model, player-ferry ownership abort, stale service RTB home, hanging native player RTB task, player logistics `assignedVehicle` mismatch, capability-gated player dispatch, and SitRep-overwritten planning locks were all variants of the latter failure mode.
