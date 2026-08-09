# Tranche 2 — Live OPFOR infantry pilot

## Purpose

This is the first contained live C.L.A.S.H. test. Impasse remains the campaign authority; HAL receives temporary tactical waypoint authority over a small allow-list of eligible enemy infantry groups.

This build is a pilot, not a production integration. The lobby default remains Off.

## Prerequisites

- Use an actual dedicated server.
- Pack the modified `13715765820790864929_legacy/` mission as an Altis mission PBO.
- Load the untouched **NR6 Pack 4.11 / HAL 1.26.2 RC1** exactly once.
- Do not load the repository's trimmed `NR6 Hal/` reference folder.
- Do not place or initialize another HAL commander. The pilot fails closed if it detects an existing HAL commander or `leaderHQ`.
- Use the latest mission source from `main`; the Tranche 1 hardening and Tranche 2 pilot are already merged.

## Enable the pilot

In the mission lobby, set:

`C.L.A.S.H. control mode = Live OPFOR infantry pilot`

The three modes are:

- **Off (baseline):** all observer and live bridge work is inert.
- **Observer only (RPT logging):** Tranche 1 behavior; HAL receives no groups.
- **Live OPFOR infantry pilot:** the observer runs and the contained HAL bridge activates.

## Authority split

Impasse continues to own:

- objectives, zone progression, budgets, spawning, vehicles, transport fulfillment, garrisoning, merging, cleanup, saving, and campaign state;
- defend-phase and zone-transition lifecycle;
- the decision to register or reclaim a group.

HAL owns only tactical waypoint decisions for groups currently marked `ITW_CLASH_Managed`.

The bridge:

- creates one hidden, invulnerable, simulation-disabled enemy HAL commander;
- excludes that commander from C.L.A.S.H. classification, HAL's managed allow-list, Impasse's infantry manager, and Impasse's stuck handler;
- suppresses any instrumented Impasse tactical writer that nevertheless reaches the commander;
- runs a commander-health watchdog after HAL initialization and fails closed if the HQ or leader becomes invalid;
- mirrors the current Impasse objectives into HAL simple-mode objectives;
- uses an explicit allow-list with `RydHQ_SubAll = false`;
- disables HAL transport assignment with `RydHQ_CargoFind = 0`;
- manages no more than 12 groups total and no more than four groups per objective;
- changes no group locality and performs no bridge remote execution;
- does not alter spawning, tickets, budgets, save schema, or mission assets.

## Eligible groups

Only server-local, alive, fully dismounted enemy infantry assigned to a current objective may enter the pilot.

The classifier rejects the hidden C.L.A.S.H. commander, player groups, vehicles and crews, cargo, assigned or pending transport, delivery groups, garrisons, support specialists, headless-owned groups, unassigned groups, objective-reset groups, transition states, and dead or empty groups.

## Handoff behavior

On registration, the bridge clears the group's old Impasse waypoints, marks it managed, and adds it to HAL's explicit allow-list.

While managed:

- ordinary Impasse infantry movement and engagement writers are suppressed;
- stuck recovery, garrison assignment, and group merging reclaim the group for Impasse;
- a classification change, defend lifecycle event, or zone transition also reclaims it.

Release is a quiescence barrier:

1. The group is removed from HAL's allow-list and marked `RydHQ_MIA`.
2. The bridge waits for HAL's busy script to acknowledge, with a 15-second upper bound.
3. The bridge clears the final HAL waypoint and returns ownership to Impasse.

A `release-timeout` line is a test failure requiring RPT review.

## Dedicated-server test

1. Start a clean dedicated-server session with the prerequisites above.
2. Select **Live OPFOR infantry pilot** in the lobby.
3. Confirm the RPT reports `observer-start` with mode 2 and then exactly one `pilot-ready`.
4. Let ordinary enemy infantry spawn, dismount, fight, lose members, request transport, garrison, merge, and trigger stuck recovery.
5. Complete all active objectives in one zone and transition into the next zone.
6. Include a defend phase if the selected mission settings permit it.
7. After the new objective set appears, run this on the server if a server-side debug console is available:

   `call ITW_CLASH_fnc_DiagnosticSnapshot;`

8. Save and attach the complete server RPT.

## Expected RPT evidence

Search for `CLASH OBS |`. A useful run should include:

- `observer-start` with mode 2;
- `objective-mirror`;
- exactly one `pilot-ready`;
- no `register` line for `CLASH HAL OPFOR`;
- `register` for eligible enemy foot groups;
- `impasse-writer-suppressed` while HAL owns a group;
- `release` when Impasse reclaims a group;
- `actual-release-scan` before defend and zone-transition mutation;
- `zone-transition-begin` and `zone-transition-end`;
- a post-transition `snapshot`, if requested.

A `commander-writer-suppressed` line means the last-resort writer shield worked, but it also identifies an Impasse path that bypassed the manager exclusions and must be reviewed. A `pilot-failing` / `pilot-failed` pair with reason `commander-invalid` confirms the watchdog released all managed groups and disabled live mode; it is an intentional fail-closed response, not a passing run.

## Pass gate

Tranche 2 passes only if:

- the run reports `isDedicated = true`;
- the pilot initializes once without detecting another HAL commander;
- the `CLASH HAL OPFOR` group remains valid, is never registered, and never appears in HAL's managed allow-list;
- no `commander-writer-suppressed`, `pilot-failing`, or `pilot-failed` line appears;
- no more than 12 groups are managed and no more than four belong to one objective;
- no player, vehicle, transport, garrison, support, headless-owned, transitional, or unassigned group is registered;
- Impasse tactical writers do not overwrite HAL waypoints while a group is managed;
- every reclaimed group leaves HAL's allow-list before Impasse mutates, merges, garrisons, or deletes it;
- no late HAL waypoint lands after release;
- no `release-timeout`, undefined-variable, null-object, locality, scheduler, or remote-execution error appears;
- the complete zone transition and post-transition save behave like the accepted Impasse baseline.

## Abort conditions

Stop the run and retain the RPT if:

- `pilot-failed`, `pilot-init-timeout`, or `commander-writer-suppressed` appears;
- the watchdog reports `commander-invalid`;
- HAL controls an excluded group;
- a managed group keeps receiving HAL orders after release;
- Impasse progression stalls or diverges from baseline;
- more than one HAL commander exists.

For a controlled server-console abort, release managed groups before disabling live mode:

`["manual-abort"] call ITW_CLASH_fnc_ReleaseAll; ITW_CLASH_LiveEnabled = false;`

Do not continue into broader group types until this dedicated-server pilot passes.
