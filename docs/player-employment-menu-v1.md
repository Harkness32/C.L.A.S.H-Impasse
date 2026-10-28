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
- The MEDEVAC channel is **presented as Combat Search and Rescue** ("Accept
  Combat Search and Rescue Missions"). It carries three demand kinds:
  `MEDEVAC_SEVERE`, the casualty extraction it always carried; `CSAR_CREW`,
  the recovery of a crew that survived its vehicle (the survivors walk to a
  carrier grounded within 300 m and climb in, as AI CASEVAC's survivors do;
  until v3 of `ITW_CLASH_CSAR.sqf` they had to be standing within 35 m
  already, were never told to move, and were put straight into their
  seats); and `MEDEVAC_SQUAD`
  (2026-10-27, `ITW_CLASH_PlayerSquadEvac.sqf`), the extraction of one of our
  AI squads that is withdrawing combat-ineffective. That last one is players
  first, with the squad behaving exactly as it does for an AI pilot: it
  withdraws, and when AI CASEVAC's own checks pass (disengaged, clear of the
  objective and the enemy, a landing zone found) it calls for pickup, holds
  that landing zone, pops smoke when the carrier is within 700 m, and moves on
  if contact closes in, calling again from the next safe spot. The call goes
  to a free CSAR player first; AI CASEVAC and ground MEDEVAC stay off the
  squad while a player holds it, and take it as before when no player can. `MEDEVAC_SEVERE` alone fired only for a man
  alive above 75% damage or unable to stand, which vanilla AI almost never
  is, so in play the channel was nearly silent. One tick accepts all three,
  which is why rescue did not become a sixth subscription. The channel name,
  `ITW_CLASH_PlayerJobTypes` and the stored subscription array are unchanged,
  so nothing is migrated and the capability seam stays passenger capacity.
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

HAL never sends a player group on reconnaissance (2026-10-27, Hark: combat
employment means attack tasks, and combat players were being handed recon).
A player who wants recon work requests it (the RECON task request).

- Every player group is in HAL's `RydHQ_NoRecon`, COMBAT ticked or not. The
  entry is also written to the BLUFOR commander's `RydHQB_NoRecon` global,
  because HQSitRepB rewrites the commander's array from that global every
  cycle; written to the commander only, the exclusion lasted one cycle, which
  is why recon reached combat players "sometimes".
- A group with COMBAT disabled is also excluded from HAL's attack and reserve
  pools through a C.L.A.S.H.-owned `RydHQ_CargoOnly` entry, and from HAL's
  defend pool through a `RydHQ_NoDef` entry. CargoOnly alone does not keep a
  transport crew out of defense: `HQOrdersDef.sqf` adds `RydHQ_NCCargoG` back
  into the defend pool after the CargoOnly exclusion, and only NoDef is
  subtracted after that. A player helicopter crew was handed "Defend Position"
  (a SENTRY waypoint) once its transport contract ended, the moment the
  contract's own NoDef entry lapsed (2026-10-27).
- All three exclusions go through `CommanderParity_fnc_SetConstraintMembership`,
  which writes the commander's array and the `RydHQB_*` global together, so
  the SitRep rewrite keeps them. C.L.A.S.H. only removes exclusions it
  previously added; ticking COMBAT removes its CargoOnly and NoDef entries.
- The native GoRecon/GoDefRecon seam refuses every player group as the
  guarantee: HAL's Busy reservation is released and the recon never starts.

## Cancellation

The employment menu's Cancel Current Job command is group-leader authority
and is validated again on the server. Specialist C.L.A.S.H. jobs retain their
own cancellation flags, while native HAL jobs are canceled through HAL's own
stored `Action1ct` denial function. Cancellation is idempotent: no active job
returns a clean no-op, and accepted requests emit request/accepted/settled (or
pending) telemetry before availability is recomputed.

## Live job sources

| Channel | v1 source |
|---|---|
| Combat | HAL tactical group tasking; never native reconnaissance |
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
