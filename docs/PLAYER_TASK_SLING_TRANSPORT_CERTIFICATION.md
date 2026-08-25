# Player Task, Sling Logistics, and Transport Certification

Run this certification on the feature branch with a dedicated server, at least two player clients, both HAL commanders active, and RPT logging enabled.

## Required setup

- Enable the current Dual-HAL/Checkbook stack.
- Use a theater with valid forward and rear bases for both sides.
- Place or purchase one sling-capable helicopter for a player.
- Ensure at least one friendly HAL group can become ammunition-depleted.
- Enable the existing CLASH diagnostic logging.
- Do not enable Zeus/High Command workarounds during the test.

## 1. Boot and binder health

Pass criteria:

- Both HAL commanders initialize once.
- The RPT contains:
  - `player-transport-authority-ready`
  - `player-task-support-ready`
  - `hal-logistics-ready` with `physicalAmmoPackage=true`
- No undefined-variable, type, remote-execution, or script errors name the new modules.
- Commander B include synchronization continues after both players join and after JIP.

## 2. Native HAL player toggle

1. Join two players into one group.
2. Leave HAL tasking disabled.
3. Verify the group does not enter Commander B's included set.
4. Use HAL's native context-menu Enable action.
5. Verify the group enters the include set and may receive an ordinary HAL task.
6. Use Disable and verify removal.
7. Re-enable, accept a task, then use Deny.

Pass criteria:

- Enable/Disable/Deny use HAL's existing menu.
- The whole group participates; there is no TL-only CLASH job.
- No player receives Arma High Command groups.
- Deny cancels a CLASH sling job without canceling unrelated server jobs.

Repeat with the group operating as infantry and then from a tank. HAL must remain the source of the combat objective.

## 3. ITW player ferry regression

### Standing delivery

1. Cause ITW to generate a delivery squad at a FOB.
2. Inspect the squad at creation.
3. Land or park a player transport within native ITW pickup conditions.
4. Allow boarding and carry the squad to a valid field drop.
5. Unload normally.

### Side-operation transport

Repeat with ITW's side-operation transport squad.

Pass criteria:

- `itwDelivery` or the CLASH ferry lease exists before the group reaches the HAL observation callback.
- HAL does not issue a competing waypoint while the squad is waiting, boarding, or embarked.
- The lease remains during the native dismount thread.
- The lease releases only after units are physically out.
- A valid standing-delivery squad is then admitted to the correct HAL commander.
- A failed boarding attempt releases an ordinary squad or preserves a still-pending delivery squad as appropriate.
- Native ITW radio messages, hints, boarding, paradrop, and unload behavior remain intact.

## 4. Player sling ammunition job

1. Put a player group leader in a sling-capable helicopter.
2. Keep HAL tasking disabled and create ammo demand.
3. Verify no player logistics assignment occurs.
4. Enable HAL tasking.
5. Allow Checkbook to fulfill `LOGISTICS_PACKAGE_AMMO`.
6. Observe the physical crate at the resolved rear air/logistics node.
7. Accept HAL's sling task, attach the crate, fly to the HAL-selected recipient, and release it safely.

Pass criteria:

- The crate does not spawn at an arbitrary theater-near point.
- It resolves through the correct side's rear generation node.
- HAL selects the recipient and player provider.
- The task destination changes from the crate to the recipient after pickup.
- Completion requires attachment followed by a grounded, detached, slow release within 100 m.
- Both original group members appear in the locked participant ledger.
- The package reaches `DELIVERED`; the job reaches `COMPLETED`.
- No economy payout occurs in this patch.

## 5. Negative sling cases

Test each case separately:

- fly through the destination without detaching;
- detach outside the radius;
- drop from altitude;
- abandon the crate after leaving the rear node;
- deny before pickup;
- destroy the helicopter;
- use a helicopter that cannot sling the selected box.

Pass criteria:

- No false completion.
- A never-moved package returns to the rear pool.
- A genuinely lost package becomes `LOST`.
- An incompatible carrier is rejected, HAL's support reservation is cleared, and the crate is recoverable.
- Outstanding packages never exceed the configured per-HQ cap.

## 6. AI ammo delivery regression

With no opted-in player provider, create ammo demand and allow an AI air provider to respond.

Pass criteria:

- HAL uses its native `HAL_GoAmmoSupp` executor.
- CLASH observes package state without replacing AI waypoints.
- Successful AI delivery reaches `DELIVERED`.
- Failure returns or loses the package according to whether it left the rear node.

## 7. Symmetry

Repeat sections 3–6 with the opposing side configured as the observed side.

Pass criteria:

- The same resolver and state rules apply.
- Package class and rear node match side.
- No player-side-only coordinate, marker, or Commander B shortcut affects opposing AI fulfillment.

## 8. RPT acceptance gate

The run passes only if:

- no Binder/Checkbook error recurs;
- no repeated provider-request storm appears;
- no group alternates rapidly between ITW and HAL authority;
- no package is approved without a resolved generation node;
- no player group is silently opted in;
- no native HC assignments survive;
- each completed ferry or sling job produces exactly one completion event.

Archive the mission RPT with the branch commit SHA and record each section as PASS, FAIL, or NOT RUN.
