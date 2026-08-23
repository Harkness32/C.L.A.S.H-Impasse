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
- One active HAL job remains enforced by HAL/C.L.A.S.H. busy and job locks.
- Artillery requires a deployed player-garage artillery asset.
- The current logistics executor requires a sling-capable helicopter and a
  physical Checkbook ammunition package.
- Passenger capacity is the capability seam for transport and MEDEVAC. An IFV
  is not rejected merely because it is unconventional.

## Live job sources

| Channel | v1 source |
|---|---|
| Combat | HAL tactical group tasking |
| Transport | HAL/ITW player ferry and HAL transport classification |
| MEDEVAC | Persistent subscription and passenger-capability seam |
| Logistics | HAL ammo demand plus Checkbook physical sling package |
| Artillery | HAL target selection plus player fire/impact validation |

MEDEVAC deliberately uses the same persistent contract now. Its dedicated
player rescue dispatcher can publish calls into this channel without changing
the menu or inventing another opt-in system.

## Security and authority

Client calls are server validated against remoteExecutedOwner, player identity,
side, and group leadership. Native HAL support purchasing remains disabled.
C.L.A.S.H. changes willingness and admission; HAL chooses targets and tasks;
Checkbook controls fulfillment.
