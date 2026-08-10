# V6 — Combat-ineffective withdrawal and squad reconstitution

## Purpose

V5 gives HAL one six-conscious-soldier anchor per OPFOR-held objective and keeps the remaining managed squads free to maneuver. It does not resolve the lifecycle of a squad HAL has declared combat ineffective.

V6 rewards force preservation. A persistently exhausted squad breaks contact, reaches an Impasse-authored rear staging point, is absorbed, and returns as one fully stocked squad of the same recorded class composition.

## Authority model

- HAL decides that a managed squad is exhausted through its native `RydHQ_Exhausted` evaluation.
- C.L.A.S.H. confirms the state, removes the squad from anchor and maneuver eligibility, and owns the one-way withdrawal order.
- Impasse publishes the egress geography, accepts the completed-withdrawal credit, creates the replacement, and retains population and spawn-cadence authority.
- CASEVAC is deferred. A later transport implementation may replace the movement leg without changing absorption or reconstitution semantics.

## Exhaustion confirmation

C.L.A.S.H. requires the group to remain in HAL's exhausted list for 20 seconds. This filters a single transient HAL cycle while avoiding indefinite occupation of a combat slot.

Once confirmed:

1. any anchor slot held by the group is vacated immediately;
2. the group is removed from `RydHQ_Included` and every HAL tactical array;
3. the group is marked `ITW_CLASH_Withdrawing`;
4. Impasse infantry, merge, cleanup, and waypoint writers exclude it;
5. attack is disabled and a full-speed withdrawal waypoint is issued;
6. the state is one-way until arrival, wipeout, or fail-closed cancellation.

An exhausted group cannot be selected as an anchor during the confirmation window.

## Egress point

Impasse remains the source of truth for staging geography. C.L.A.S.H. resolves the destination in this order:

1. the squad's assigned objective `ITW_OBJ_V_SPAWN`, while that objective remains OPFOR-held;
2. the nearest OPFOR-held objective in the current active series, using its `ITW_OBJ_V_SPAWN`;
3. the enemy home objective's `ITW_OBJ_V_SPAWN`;
4. the selected objective's `ITW_OBJ_POS` only when its vehicle spawn is undefined.

The controller never uses the hidden HAL HQ or invents a random rear position.

The destination is re-resolved during withdrawal. A zone or ownership transition can therefore redirect a retreating squad to a valid current staging point.

Arrival is the group leader entering 125 metres of the resolved staging point.

## Archetype and lineage

`ITW_AtkAddInfantryGroup` records the full unit-class array before a newly spawned squad enters combat. C.L.A.S.H. also snapshots the current composition when it first registers a legacy group that lacks metadata.

The authoritative replacement archetype is the recorded original array, not the surviving members at egress. The replacement uses fresh default faction loadouts generated through Impasse's existing unit constructor.

Each managed group receives a stable lineage identifier. A reconstituted group keeps the withdrawing group's lineage while receiving a new runtime group ID and one unique reconstitution request ID.

This does not clone damage, ammunition, individual inventory mutations, rank, identity, or transient HAL state.

## Successful withdrawal

When the group reaches egress:

1. C.L.A.S.H. submits the recorded archetype, lineage, and objective affinity to Impasse.
2. Impasse atomically creates one queued reconstitution credit.
3. Only after the credit is accepted are the survivors and old group removed.
4. The next enemy manager cycle consumes at most one credit.
5. Impasse creates every class in the archetype at the current valid rear staging point.
6. A partial creation failure deletes the partial group and requeues the same credit.
7. C.L.A.S.H. registers the complete replacement and returns it to HAL.
8. If the HAL pilot is unavailable, Impasse's ordinary engagement path receives the group instead of leaving it idle.

One withdrawing group can create exactly one credit.

## Population and group caps

A reconstitution credit bypasses Impasse's living-AI headcount ceiling for one complete squad.

Example:

- configured AI ceiling: 100;
- three survivors reach egress, reducing headcount to 97 after absorption;
- the original eight-man archetype is recreated;
- living AI becomes 105;
- ordinary Impasse spawning stops until living headcount falls below 100.

This is a bounded preservation reward, not a new reinforcement stream. Credits are created only by physical arrival and are consumed once.

The C.L.A.S.H. pilot still caps HAL at 12 managed groups and four per objective. A returning reconstitution group is a priority replacement: when the slot was filled during withdrawal, C.L.A.S.H. releases a non-anchor maneuver group back to Impasse rather than rejecting the returned lineage.

## Failure and transition behavior

- Wiped before egress: no credit; normal Impasse attrition replacement applies.
- No valid active OPFOR staging point: keep the squad withdrawing and retry destination resolution.
- Queue unavailable or archetype invalid: do not absorb the survivors.
- Zone transition: preserve the withdrawal and redirect it to current valid staging geography.
- Objective loss: redirect to another OPFOR-held active objective; do not walk into a captured base.
- Pilot failure: cancel uncompleted withdrawals, clear the exclusion marker, and return survivors to Impasse control.
- Replacement spawn failure: delete the partial spawn and requeue the original credit.
- Multiple completed withdrawals: stack credits, but consume no more than one per enemy spawn cycle.

## Telemetry

`pilot-ready` reports version 6 and appends the exhaustion-confirmation grace and egress radius.

Lifecycle events:

- `exhaustion-observed`: HAL first reports the group exhausted.
- `withdrawal-start`: the confirmed group leaves HAL management.
- `withdrawal-order`: destination, source, distance, and survivors.
- `withdrawal-state`: active withdrawals plus queued-credit count.
- `withdrawal-failed`: group wiped before egress.
- `withdrawal-arrived`: group reached the staging radius.
- `reconstitution-queued`: Impasse accepted one credit.
- `reconstitution-absorbed`: survivors were removed after acceptance.
- `reconstitution-deferred`: no current enemy-held active target exists.
- `reconstitution-spawn-failed`: incomplete spawn deleted and requeued.
- `reconstitution-spawned`: full group created, with live count and configured ceiling.
- `reconstitution-acknowledged`: C.L.A.S.H. accepted the new group and lineage.
- `withdrawal-cancelled`: fail-closed return to Impasse control.

## Hosted behavior gate

1. Confirm `pilot-ready` reports version 6.
2. Let V5 establish all anchor slots.
3. Make a non-anchor squad persistently exhausted through casualties, ammunition loss, or wounds.
4. Confirm one `exhaustion-observed` and one `withdrawal-start`.
5. Verify no HAL or Impasse writer changes its egress waypoint.
6. Wipe that squad before arrival and confirm no credit is created.
7. Exhaust a second squad and allow it to reach the staging radius.
8. Record the survivor count, original archetype, objective affinity, and lineage.
9. Confirm one credit and one absorption.
10. Hold living AI at or above the configured ceiling.
11. Confirm the next enemy manager cycle creates the complete original archetype anyway.
12. Confirm ordinary spawning remains stopped while above the ceiling.
13. Confirm the returned group preserves lineage and objective affinity, occupies one HAL group slot, and does not displace an anchor.
14. Repeat with an objective ownership change during withdrawal.
15. Repeat through `ZoneNext 1 >> 2` on a dedicated server.

### Pass criteria

- persistent HAL exhaustion is the only automatic trigger;
- no exhausted group can remain an anchor;
- withdrawal begins once and is not reversed;
- egress always resolves from Impasse-authored objective staging data;
- no pre-arrival wipeout creates a credit;
- arrival creates exactly one credit;
- survivors are removed only after credit acceptance;
- the replacement contains every recorded class and no partial squad;
- the headcount ceiling may be exceeded only by a consumed credit;
- ordinary spawning remains suspended during the overage;
- C.L.A.S.H. group and per-objective caps remain intact;
- lineage and objective affinity survive;
- zone and ownership transitions do not strand or duplicate a withdrawal;
- no SQF, locality, release-timeout, allocation-drift, or duplicate-credit error occurs.
