# Persistent player HAL employment menu v1

## Doctrine

C.L.A.S.H. owns the player-facing employment surface. HAL remains the tactical
commander, and ITW/Checkbook remains the resource authority. The native HAL
support-request menu stays disabled because it can bypass the Checkbook seam.

A subscription means the group is willing to receive that kind of HAL job.
It does not grant equipment, fabricate capability, or reset when the group
changes vehicles.

## Contract

- The menu is available through the Communication menu, a self scroll action,
  and an ACE self action.
- All five channels are always visible: combat, transport, MEDEVAC, logistics,
  and artillery.
- The group leader changes group-level subscriptions because HAL assigns work
  to groups and the eventual payout ledger is group-shared.
- Subscriptions persist until the leader changes them. Vehicle changes and task
  completion never write the subscription array.
- Current physical capability changes only ITW_CLASH_PlayerTaskAvailable.
  It never changes ITW_CLASH_PlayerJobSubscriptions.
- `ITW_CLASH_PlayerTaskAvailable` means the group has at least one subscribed,
  physically executable channel **and is not currently occupied by another HAL
  job**. HAL's native `Busy` reservation and C.L.A.S.H. specialist job IDs are
  authoritative occupancy inputs.
- One active HAL job remains enforced by HAL/C.L.A.S.H. busy and job locks.
- Artillery requires a deployed player-garage artillery asset.
- The current logistics executor requires a sling-capable helicopter and a
  physical Checkbook ammunition package.
- Passenger capacity is the capability seam for transport and MEDEVAC. An IFV
  is not rejected merely because it is unconventional.

## Tactical admission

Reconnaissance is a COMBAT-channel task, not a sixth subscription. A player
group with COMBAT disabled remains eligible for its subscribed specialist jobs
but is excluded from HAL's generic reconnaissance/attack/reserve pools through
C.L.A.S.H.-owned `RydHQ_NoRecon` and `RydHQ_CargoOnly` entries. C.L.A.S.H. only
removes exclusions it previously added; native HAL classifications are never
blindly erased when COMBAT is re-enabled.

The native GoRecon/GoDefRecon execution seam also validates COMBAT admission as
a defense-in-depth check. If HAL selected a player during the short interval
before the planning exclusions synchronized, C.L.A.S.H. releases HAL's Busy
reservation and rejects the unsolicited recon before native execution begins.

## Cancellation

The employment menu's Cancel Current HAL Job command is group-leader authority
and is validated again on the server. Specialist C.L.A.S.H. jobs retain their
own cancellation flags, while native HAL jobs are canceled through HAL's own
stored `Action1ct` denial function. Cancellation is idempotent: no active job
returns a clean no-op, and accepted requests emit request/accepted/settled (or
pending) telemetry before availability is recomputed.

## Live job sources

| Channel | v1 source |
|---|---|
| Combat | HAL tactical group tasking, including native reconnaissance |
| Transport | HAL/ITW player ferry and HAL transport classification |
| MEDEVAC | Persistent subscription and passenger-capability seam |
| Logistics | HAL ammo demand plus Checkbook physical sling package |
| Artillery | HAL target selection plus player fire/impact validation |

MEDEVAC deliberately uses the same persistent contract now. Its dedicated
player rescue dispatcher can publish calls into this channel without changing
the menu or inventing another opt-in system.

## Checkbook interaction

Transport requisition already asks HAL whether a non-busy, non-`Unable` cargo
provider with sufficient seats exists before requesting Checkbook capacity.
The player-state hardening therefore fixes that purchasing behavior by making
availability truthful; it does not add a second transport-purchase policy.

## Security and authority

Client calls are server validated against remoteExecutedOwner, player identity,
side, and group leadership. Native HAL support purchasing remains disabled.
C.L.A.S.H. changes willingness and admission; HAL chooses targets and tasks;
Checkbook controls fulfillment.
