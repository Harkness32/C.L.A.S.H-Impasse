# Reconstitution: handoff at spawn

Status: written 2026-10-11, not flown.

## 1. What was seen

Run of 2026-10-11 20:23, mission 2. Hark: "Brav 2-4, littlebird, stuck in the
air near enemy fob, why?"

Bravo 2-4 (G143) was not a HAL lift. It was the reconstitution lift RC1,
carrying four replacements for Alpha 2-6 (G36), raised for objective 8.

| Time | Event |
|---|---|
| 20:56:54 | `reconstitution-transport-dispatched ["RC1","G36",8,9,..,"B_Heli_Light_01_F",4,11,4818,"air-preferred"]` |
| 20:59:20 | squad in parachutes, about 500 m from objective 23 |
| 20:59:26 | `dual-hal-vehicle-migrated ["G143","B_Heli_Light_01_F",21]` |
| 20:59:28 | `reconstitution-transport-released [.., "physical-dismount", [16436.9,10326.5,40.7]]` |
| 20:59:29 | waypoint MOVE [15388,10293], Impasse's 1000 m egress leg |
| 21:00:09 | waypoint NONE, to the end of the log at 21:07 |

The enemy flew one too: RC2, a Huron (G167) from base 31, also for objective 8,
dropped 21:02:54.

Neither squad was handed to its commander. `reconstitution-transit-arrived`
appears 0 times in the log.

## 2. Why

A reconstitution lift is a third kind of lift, between Impasse and HAL. It has
a handoff at each end and one in the middle. Each had its own fault.

### Takeoff: the BLUFOR vector ignored the objective

The dispatch writes `ITW_CLASH_TransitObjective` on the crew and cargo groups.
`ITW_EnemyAttackVectors` reads it and honours it when the objective is in the
live zone. `ITW_AllyAttackVectors` had no such branch and picked the least
staffed objective of the zone (8, 14, 23, 28 after the flip at 20:55:56). It
picked 23: `infantry-authority-affinity-updated ["G143",-1,23,..]`. Objective 23
is 6.7 km from objective 8 and 1.9 km from enemy forward base 31.

### Drop: the aircraft changed owner and the new owner had no order

`ITW_AtkVehicleManager` sends a transport with empty cargo back to where it
started and deletes it there. `ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles`
takes any managed vehicle with empty cargo out of `ITW_ManagedVehs` and
registers it as a HAL transport. It writes no waypoint. The migration ran first.

Nothing downstream returns such an aircraft. The service lifecycle registers
only what it bought or generated (`new-purchase`, `generation-register`), and
HAL returns a carrier only after a HAL lift. So the Littlebird flew Impasse's
egress leg and stopped, 1.5 km from objective 23 and 3.3 km from base 31, in
the enemy commander's `RydHQ_KnEnemiesG` from 20:59:58 to the end of the log.

The vehicle carried `ITW_CLASH_ReconstitutionTransport`, which
`ITW_CLASH_DualHAL_fnc_IsLifecycleReserved` is written to honour. Two things
made that useless here. The flag is dropped at the dismount. And the vehicle
tests in that function sit inside a `then` block, where `exitWith` only leaves
the block: the migration at 20:59:26 came two seconds before the release.

### Landing: a deleted parachute is still an assigned vehicle

The transit manager will not hand a squad over while `assignedVehicles` of the
group is not empty. A parachute is a vehicle. It is deleted on landing and
stays in that list as a null object. `unassignVehicle` on the man does not
remove it, and neither does `leaveVehicle` with the null object: the field
hardening pass logs the list after trying both and it is still
`<NULL-object>`.

- RC1: `reconstitution-transport-unassigned ["RC1","G36","transport",4,4,4,0]`
  31 times, 20:59:29 to 21:07:18. G140 stood at the drop point with no waypoint.
- RC2: `reconstitution-handoff-wait ["RC2",..,8,-1,3,590,"physical-dismount"]`
  to 21:07:21.

## 3. What changed

Hark: "maybe we should spawn the reconstitution squad, then immediately hand it
hal without any orders and let hal toss it where it needs to go?" and "BOTH
SIDES, we need to maintain parity at all times."

### 3.1 The squad goes to its commander at the forward FOB

`ITW_CLASH_ReconstitutionDispatchFix.sqf` v7.

The handoff a replacement squad got at the end of its lift,
`ITW_CLASH_fnc_AcknowledgeReconstitution`, stamps lineage, archetype and the
objective, registers the group with its commander, and writes no waypoint and
no order. That is what every other new squad gets at the base it spawns at.

`ITW_AtkBeginReconstitutionTransit` now calls it through
`ITW_CLASH_Reconstitution_fnc_SpawnHandoff`, once the squad is placed at the
forward FOB and before anything marks it as in transit. One call, both sides.

- Accepted: `reconstitution-spawn-handoff [request, lineage, objective, side,
  men, metres to objective, base, source]`. No lift is bought. HAL tasks the
  squad on its next cycle and lifts it like any other.
- Refused: `reconstitution-spawn-handoff-refused [.., HALReady, DualHALReady]`
  and the squad goes down the transit path as before. Refusals to expect: HAL
  not up, the enemy bridge frozen for a zone change, the enemy roster full.

Switch: `ITW_CLASH_ReconstitutionSpawnHandoff` (default true).

### 3.2 The fallback lift, repaired

For a squad the commander does not take.

| Handoff | Change | File |
|---|---|---|
| Takeoff | `ITW_AllyAttackVectors` has the enemy vector's forced-objective branch, the same text | `ITW_Ally.sqf` |
| Drop | The lift is marked `ITW_CLASH_ReconstitutionLift` for life. `ShouldSuppressImpasseVehicleWriter` refuses a marked vehicle, so the migration and both pre-init wrappers leave it with Impasse. Impasse's empty-transport branch accepts a marked vehicle of any role. | `ITW_CLASH_ReconstitutionDispatchFix.sqf` v7, `ITW_CLASH_DualHALCheckbook.sqf` v7, `ITW_Attack.sqf` |
| Landing | Only vehicles that still exist count as assigned: `ITW_CLASH_Reconstitution_fnc_LiveAssigned` | `ITW_CLASH_ReconstitutionTransitFix.sqf` v6, `ITW_CLASH_LogisticsGuard.sqf` v5 |

The landing rule is also applied to the two enemy classifiers
(`ITW_CLASH_fnc_ClassifyGroup` in `ITW_CLASH.sqf` and
`ITW_CLASH_InfantryAuthority_fnc_IsHardHandoff`, v5). Without that the enemy
squad would pass the transit gate and then be refused registration for the same
null parachutes. BLUFOR admission asks each man for his `assignedVehicle`, which
is already null once the vehicle is deleted, so the two sides now read the same
thing. A wreck still exists and still counts on both.

That classifier change is wider than reconstitution: any enemy squad whose only
assigned vehicles have been deleted is now eligible for HAL.

## 4. What this costs

- No guaranteed ride. If HAL's dice or an air-denied corridor refuses the lift,
  the squad walks. Base 9 to objective 8 was 4975 m.
- No guaranteed destination. The objective is an affinity, not an order.
- A dual-role vehicle used as the fallback lift is flown home and deleted with
  the rest. Before, it was migrated to HAL.

## 5. Not verified

- No reconstitution handoff completed in any log of 2026-10-11, at spawn or
  after a lift. `AcknowledgeReconstitution` was read, not watched.
- Whether the anchor slot on the objective picks the squad up through its
  lineage was not traced.
- The fallback lift is only exercised when a commander refuses a squad.

In the next log, look for `reconstitution-spawn-handoff`, then the squad's
first HAL order, then a `dual-hal-cargo-request` for it.

## 6. Known and not fixed

- The vehicle tests in `ITW_CLASH_DualHAL_fnc_IsLifecycleReserved` (CASEVAC,
  ground MEDEVAC, reconstitution transport) never return true, in both the base
  and the hardening wrapper. Repairing that changes CASEVAC and MEDEVAC vehicle
  ownership and was left alone.
- The group-state diagnostic reads `ITW_ObjIdx`, which nothing sets. Impasse
  stores the index in `VarAssignedObjIdx`. Column 7 is always -1.
- G140 and the RC2 squad in a saved game from that run stay as they are.
