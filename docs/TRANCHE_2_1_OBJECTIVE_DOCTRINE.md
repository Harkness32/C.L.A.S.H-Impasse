# Tranche 2.1 — Objective defense doctrine

## Purpose

Tranche 2 proved that Impasse can hand tactical waypoint authority to HAL safely. It did not prove that HAL was using that authority to defend Impasse's active objectives.

The source audit found two doctrine defects in the live pilot:

- `RydHQ_Order = "ATTACK"` allowed HAL to select offensive behavior.
- every managed group was copied into `RydHQ_NoDef`, which NR6 subtracts from all defense pools.

Tranche 2.1 corrects those semantics without expanding HAL beyond the existing OPFOR dismounted-infantry pilot.

## Authority model

Impasse remains the campaign authority. It owns objective state, zone progression, budgets, spawning, transport, garrisoning, merging, cleanup, saving, and the decision to register or reclaim a group.

HAL remains a tactical subordinate. It may choose defensive positions and waypoints only for explicitly managed groups.

## Defensive doctrine

The bridge now enforces these NR6 settings globally and on the hidden HAL HQ:

- `RydHQ_Order = "DEFEND"`
- `RydHQ_Berserk = false`
- `RydHQ_AttackAlways = false`
- `RydHQ_IdleDef = true`
- `RydHQ_DefendObjectives = 1`
- `RydHQ_CRDefRes = 0`
- `RydHQ_NoDef = []`

NR6 simple mode receives every objective flag in the current Impasse zone. `RydHQ_Taken` contains only the objectives Impasse reports as OPFOR-held, so those flags become HAL's defense points.

The bridge reapplies this doctrine during allow-list synchronization. A later HAL reset therefore cannot silently restore the old attacking or no-defense configuration.

## Objective affinity

A group is eligible only when its Impasse objective:

- belongs to the current active zone; and
- is still held by OPFOR.

Registration stores that objective index as `ITW_CLASH_AssignedObjective`. If Impasse reassigns the group, or the point is captured, the ordinary classification/release path reclaims it.

The existing four-group-per-objective cap reserves pilot capacity across the accepted three-objective campaign structure. It does not invent defenders: an objective with no eligible Impasse squad can still have zero HAL-managed groups.

## Allocation guard

NR6 does not expose a durable per-group “defend objective X” variable. The bridge therefore infers HAL's allocation from each defensive waypoint:

1. Read the group's current waypoint.
2. Find the nearest OPFOR-held Impasse objective.
3. Compare it with `ITW_CLASH_AssignedObjective`.
4. Ignore near-ties within 150 metres.
5. If HAL clearly allocates the group to another objective, log `allocation-drift`, release it to Impasse, and block re-registration for 60 seconds.

This is a safety tether, not bridge-authored tactical movement. C.L.A.S.H. does not replace HAL's waypoint or choose its fighting position.

## Telemetry

`objective-mirror` now reports:

`[zone index, active objective indexes, OPFOR-held objective indexes]`

`doctrine` reports:

`["DEFEND", defense enabled, DefendObjectives, NoDef count]`

`objective-allocation` reports:

- per held objective: `[objective index, Impasse-affined managed groups, HAL-inferred allocations]`;
- per group: `[group id, assigned objective, HAL state, inferred objective, waypoint type, distance to assigned objective, distance to inferred objective]`.

Distances are diagnostic only and do not participate in the log signature, so moving squads do not spam the RPT.

## Hosted combat test

1. Pack the latest mission from this branch as an Altis PBO.
2. Load untouched **NR6 Pack 4.11 / HAL 1.26.2 RC1** exactly once.
3. Do not load the repository's `NR6 Hal/` reference source.
4. Select **C.L.A.S.H. control mode = Live OPFOR infantry pilot**.
5. Let all three objectives field infantry and fight for at least ten minutes.
6. Capture or contest one objective so the held-objective set changes.
7. Save the complete RPT.

## Pass conditions

- exactly one `doctrine` line reports `DEFEND` and a `NoDef` count of zero;
- `objective-mirror` matches Impasse's active and held objective state;
- only groups assigned to OPFOR-held active objectives register;
- `objective-allocation` shows HAL assigning defenders to the expected points;
- no objective's available pilot capacity is consumed by another objective;
- no `allocation-drift`, `release-timeout`, `pilot-failed`, commander warning, or SQF error appears;
- capturing a point removes it from the held set and reclaims its managed groups.

An `allocation-drift` followed by a clean release proves the safety tether worked, but it fails the doctrine test because HAL still chose the wrong point.

## Next gate

After this hosted behavior test passes, run the genuine dedicated-server `ZoneNext 1 >> 2` transition using the complete Tranche 2 procedure.
