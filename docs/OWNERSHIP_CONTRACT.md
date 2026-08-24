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

### C.L.A.S.H. owns
- authority transitions between Impasse and HAL
- compatibility and lifecycle state neither system natively understands
- explicit service leases
- temporary retask/quarantine locks
- reconstitution transit handoff
- observation and telemetry across ownership seams

## The rule in practice

- `vehDef` stores class/configuration and native accounting state, not per-deployment service state.
- `ITW_CLASH_ServiceLease` stores an explicit runtime grant, not an inferred vehicle role.
- HAL transport contracts store task identity and destination, not a cached interpretation of boarding state.
- `baseHint` stores which Impasse base should be asked first, not a frozen coordinate returned by that base earlier.
- service RTB resolves its destination against live `ITW_Bases` ownership at order time and periodically while returning.
- a virtual service pool entry is a paid entitlement, not an invisible reserved Impasse vehicle slot.

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

`START` is compatibility output for leased service crews, never the source of truth for selecting a base.

RTB resolution order:
1. Validate `baseHint` against current side ownership and `ITW_BASE_SPAWNED`.
2. If valid, resolve that live base (`request-base`).
3. Otherwise choose the nearest currently friendly spawned base (`nearest-base`).
4. For ships, project the resolved base through SeaGuard's bounded local-water resolver (`water-node`). SeaGuard answers where a hull can float; it does not own home selection.
5. If no friendly spawned base can be resolved, preserve a valid compatibility `START` only as `fallback-start`; never invent `[0,0,0]`.

`homeResolvedAt` is load-bearing. An RTB asset is re-resolved on a time cadence even when it is making progress, because progress toward a base that has fallen is still wrong. A new waypoint is issued only when the newly resolved physical destination moves by the configured change threshold; otherwise metadata is refreshed without resetting AI pathing.

## Review test

For every future patch that crosses Impasse/HAL/C.L.A.S.H. authority, ask:

> Are we storing the authority's question/reference and resolving the answer when it is needed, or are we caching an answer that can stop being true?

The DUAL service misclassification, shadow vehicle-count model, player-ferry ownership abort, and stale service RTB home were all variants of the latter failure mode.
