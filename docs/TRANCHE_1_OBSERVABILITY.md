# Tranche 1 — Dedicated-server observability test

## Purpose

This build instruments the Impasse/HAL ownership seams without granting HAL control. It must behave like the accepted Altis baseline while producing enough RPT evidence to design the live OPFOR pilot.

## Enable the observer

In the mission lobby, set:

`C.L.A.S.H. Tranche 1 observer = On (RPT logging only)`

The default is Off. When Off, observer hooks return immediately.

## Expected scope

When enabled, the observer:

- runs on the server only;
- watches both Impasse group-discovery callbacks;
- treats OPFOR as the only future pilot side;
- classifies ordinary, alive, server-local, fully dismounted infantry;
- rejects players, vehicles, crews, cargo, assigned or waiting transport, delivery groups, garrisons, support specialists, headless-owned groups, unassigned groups, and transition/reset states;
- records would-register and would-release decisions;
- records candidate groups touched by Impasse waypoint writers;
- records defend-phase, objective-publication, and zone-transition seams.

It does not:

- populate `RydHQ_Included`;
- call HAL;
- add, delete, or alter waypoints;
- change group locality or `noHeadless`;
- spawn, delete, move, merge, garrison, or transport units;
- change tickets, objectives, campaign progression, save data, or cleanup.

## Test run

1. Start a dedicated server with both Impasse and NR6 HAL loaded.
2. Enable the observer lobby parameter.
3. Play through one complete zone containing all three active objectives.
4. Include at least one defend phase if the mission settings permit it.
5. Let infantry spawn, dismount, request/use transport, garrison, fight, lose members, and cross the zone transition.
6. After the new objective set appears, run `call ITW_CLASH_fnc_DiagnosticSnapshot;` on the server if a server-side debug console is available.
7. Save the server RPT.

## Required RPT evidence

Search for `CLASH OBS |`. A passing run should contain:

- `observer-start`
- `would-register` for eligible OPFOR foot groups
- `classified` rejection reasons for excluded groups
- `candidate-waypoint-writer` at Impasse tactical writers
- `would-release` / `release-scan` before reset and defend lifecycle passes
- `objective-state-published` and `contested-state-published`
- `zone-transition-begin` and `zone-transition-end`
- a `snapshot` if the diagnostic function was called

## Pass gate

Tranche 1 passes only if:

- mission behavior matches the accepted baseline;
- HAL receives no groups and issues no orders;
- every eligible group is classified consistently after dismount and assignment;
- transport, delivery, garrison, support, player, vehicle, and HC-owned groups remain rejected;
- every zone/defend reset logs would-release before Impasse mutates or deletes groups;
- no undefined-variable, type, locality, scheduler, or remote-execution errors appear in the RPT.

If behavior diverges, stop before Tranche 2 and attach the RPT with the approximate mission time of the divergence.
