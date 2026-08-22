# Player HAL Tasks, Sling Logistics, and ITW Ferry Authority

## Decision

This patch restores native HAL player task participation and native ITW player ferrying without transferring tactical authority into CLASH.

- **HAL** decides that support or combat work is required, selects the recipient, selects an eligible provider, and owns the task/route.
- **CLASH** exposes opted-in player groups to HAL, translates a physical ammunition-package request through Checkbook, supplies a human-safe sling task executor, and prevents HAL from reclaiming ITW ferry cargo mid-delivery.
- **ITW** remains the force-generation and campaign-state authority. Its existing delivery and player transport behavior is retained.

The implementation is hook-first. HAL's AI executor and ITW's transport manager remain canonical.

## Authority contract

| Concern | Owner | CLASH hook |
|---|---|---|
| Recon, target selection, task priority | HAL | None |
| Player accepts/denies HAL tasking | Player through HAL's native context menu | Mirror native toggle into the Commander B include set |
| Supply recipient and route | HAL | Human-safe task presentation only |
| Budget/capability approval | ITW through Checkbook | `LOGISTICS_PACKAGE_AMMO` provider |
| Package generation point | ITW generation-node resolver | Symmetric `REAR_AIR` profile |
| AI ammo delivery execution | HAL | Native `HAL_GoAmmoSupp` retained |
| Player sling delivery execution | Player | CLASH task/ledger wrapper after HAL assignment |
| AI squad waiting for a player ferry | ITW | Pre-registration authority reservation |
| AI squad after physical unload | HAL | Release and re-admit only after dismount completes |
| Player High Command | Disabled under CLASH | HAL/CLASH task participation replaces it |

## State machines

### Player task exposure

`NOT_EXPOSED -> EXPOSED -> ASSIGNED -> ACTIVE -> COMPLETED`

- Default is **not exposed**.
- HAL's native Enable action exposes the player's entire group.
- HAL's native Disable action removes the group from HAL availability.
- HAL's native Deny action cancels the current CLASH-backed player logistics job.
- A group may receive ordinary HAL combat tasks in any suitable vehicle once exposed.
- A group is also advertised as an ammunition air-logistics provider only while its leader occupies a live sling-capable helicopter.

### Ammunition package

`AVAILABLE_AT_REAR -> RESERVED -> IN_TRANSIT -> DELIVERED`

Failure branches:

- Never left the rear node: return to `AVAILABLE_AT_REAR`.
- Left the node and was abandoned/destroyed: `LOST`.
- Incompatible helicopter: reject the assignment, return the package, and clear HAL's support reservation.

Completion requires all of the following:

1. the package was physically attached or sling-loaded;
2. it is detached within the configured delivery radius;
3. it is on or immediately above the ground; and
4. it is nearly stationary.

Dropping a crate from altitude or merely flying through the destination does not complete the job.

### ITW player ferry authority

`HAL_ELIGIBLE -> ITW_RESERVED -> BOARDING -> EMBARKED -> PHYSICAL_UNLOAD_PENDING -> HAL_ELIGIBLE`

The delivery flag/lease is acquired **before** `ITW_AtkAddInfantryGroup` calls the CLASH/HAL observation seam. Release is blocked while:

- `itwDelivery` remains true;
- `ITW_getInState` is boarding or embarked; or
- the native dismount thread has not cleared the physical-unload barrier.

This closes both observed races: premature admission on creation and premature re-admission while soldiers are still inside the player's vehicle.

## Checkbook package contract

Request capability: `LOGISTICS_PACKAGE_AMMO`

Requirements:

- `hq`
- `side`
- `mode = AIR`
- `profile = REAR_AIR`
- `reference`

Approved result:

- one physical ammunition box in `assets`;
- generation metadata from the symmetric node resolver;
- package metadata identifying payload and class;
- explicit prototype billing metadata.

The v1 package uses an outstanding-package cap rather than inventing a fictional ITW currency price. The carrier remains governed by the existing budgeted `LOGISTICS_AMMO` capability. A later economy patch can replace the package quota with a real consumable debit without changing HAL or the player task contract.

## Shared participation ledger

The human roster is locked when HAL assigns the task. All members of that player group are recorded in the completion event, matching the agreed shared-reward doctrine. This patch records auditable events but intentionally performs no payout.

Recorded seams include:

- job assigned/active/completed/failed/canceled;
- package state transitions;
- player ferry completion with carrier roster.

## Configuration

| Variable | Default | Purpose |
|---|---:|---|
| `ITW_CLASH_PlayerAmmoDeliveryRadius` | 100 m | Valid package release radius |
| `ITW_CLASH_PlayerAmmoJobTimeout` | 1800 s | Player/AI package job timeout |
| `ITW_CLASH_AmmoPackageMaxOutstandingPerHQ` | 1 | Prevents rear-node crate spam |
| `ITW_CLASH_PlayerAmmoPackageClasses` | side default | Player-side package override |
| `ITW_CLASH_EnemyAmmoPackageClasses` | side default | Opposing-side package override |

Defaults are NATO, CSAT, and AAF vehicle-ammunition boxes according to side.

## Fail-open and failure behavior

- Missing CLASH ferry helpers preserve ITW's native delivery flag and route.
- Non-player HAL ammo providers use the untouched native executor.
- A failed package spawn returns a structured Checkbook failure.
- An unresolved rear node returns a structured deferral.
- A ferry lease intentionally fails closed if physical unload cannot be proven; HAL does not receive ambiguous cargo.
- Native player High Command is suppressed under CLASH to avoid parallel tactical authority.
