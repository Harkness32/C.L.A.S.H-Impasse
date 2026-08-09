# V5 — HAL anchor coverage and Impasse refill handshake

## Purpose

V4 proved that HAL can defend the three active objectives without cross-objective allocation drift. It did not guarantee that any HAL-controlled soldiers remained inside Impasse's actual capture radius.

V5 establishes one squad anchor per held objective while leaving every additional HAL group free for the outer defense. If BLUFOR captures a point before the complete series falls, HAL changes from static defense to native recovery and attempts to retake it.

## Authority model

Impasse remains campaign authority. It owns objectives, ownership, zone progression, AI limits, tickets, spawning cadence, faction selection, transport, garrisoning, merging, cleanup, persistence, and every decision to create a new squad.

HAL remains tactical commander for the existing twelve-group OPFOR dismounted-infantry pilot.

C.L.A.S.H. is the contract layer between them:

- one designated anchor-squad slot exists for each active objective still held by OPFOR;
- the assigned squad is healthy only when at least six of its conscious members are inside that objective's real `ITW_OBJ_SIZE` capture radius;
- the nearest viable HAL-managed squad with matching Impasse objective affinity is preferred; if none has six conscious members, the strongest available partial squad temporarily holds the role;
- all other HAL groups remain available for the outer screen, maneuver, and reserve roles;
- a BLUFOR-captured objective remains in HAL's active objective graph as an untaken recovery target;
- groups associated with a temporarily lost objective remain HAL-managed instead of being handed back to a competing Impasse waypoint loop;
- other OPFOR soldiers inside the radius still count for Impasse capture mechanics and telemetry, but they never satisfy the anchor slot or cancel its refill request.

The anchor is a role, not a permanent squad.

## HAL-native anchor order

NR6 exposes no durable public API for “group X anchors objective Y.” Its defensive planner repeatedly builds positions and assigns the nearest available group.

V5 therefore uses the narrowest available native path:

1. C.L.A.S.H. selects a suitable group from HAL's existing allow-list.
2. C.L.A.S.H. chooses a safe point inside Impasse's capture circle.
3. NR6's own `HAL_GoDef` executes one defensive order.
4. C.L.A.S.H. does not run a waypoint-maintenance loop; HAL retains the group afterward.

This is deliberately not described as HAL independently selecting the anchor. The bridge selects the coverage role because stock NR6 has no stable anchor-assignment interface. HAL executes and maintains the tactical task.

## Coverage lifecycle

The default contract is one designated squad with at least six conscious members inside the radius.

A slot can report:

- `COVERED`: the designated HAL anchor squad has at least six conscious members inside the radius;
- `MOVING`: the anchor has at least six conscious members but fewer than six have reached the radius;
- `DEGRADED`: the anchor squad has fewer than six conscious members;
- `VACANT`: no suitable HAL group is available;
- `UNCOVERED`: no designated anchor coverage exists.

Incidental OPFOR presence is reported separately as total local coverage. It may delay capture in Impasse, but it never changes the anchor state to `COVERED`.

C.L.A.S.H. waits 75 seconds for a viable promoted anchor to reach its point before requesting manpower. Anchor orders have a 60-second cooldown so the audit cannot thrash a squad.

When a group dies, becomes ineligible, is merged, is garrisoned, or is released, its slot is detached immediately. A dead or null group does not enter the ordinary fifteen-second release handshake.

When an objective is captured by BLUFOR, its anchor slot is dissolved and any pending refill is cancelled immediately. The former anchor becomes a maneuver group. If OPFOR recaptures the point, the ordinary audit creates a new anchor slot there.

## Objective-specific refill handshake

A genuine deficit creates one pending request for that objective.

Impasse fulfills it only when its normal population loop has already authorized and spawned an OPFOR squad:

1. the next unassigned OPFOR squad is redirected to the deficient held objective;
2. the squad is positioned through Impasse's existing objective-population path;
3. its normal Impasse objective index is set to the requested objective;
4. C.L.A.S.H. records the assignment and admits it through the ordinary classifier;
5. the anchor audit promotes it when suitable.

The handshake does not increase the AI ceiling, grant tickets, accelerate the spawn loop, choose a faction unit, or bypass Impasse's campaign rules.

If the twelve-group or four-groups-per-objective pilot cap is full, the refill may reclaim one non-anchor HAL slot. That existing group is cleanly released back to Impasse; it is not deleted.

An assigned refill has 120 seconds to establish a designated six-conscious-soldier anchor inside the radius. A partial, dead, or ineffective refill reopens the same objective request.

## Deterministic defend/recovery doctrine

HAL always receives the complete active objective series through `RydHQ_SimpleObjs`. Only points currently held by OPFOR appear in `RydHQ_Taken`.

- If every active objective is OPFOR-held, HAL uses `DEFEND`.
- If any active objective is BLUFOR-held, HAL uses `ATTACK`; stock NR6 derives its recovery targets as `objectives - taken`.
- Surviving anchors are placed in `RydHQ_NoAttack` and `RydHQ_NoRecon` so they remain behind while every non-anchor group is available to recover lost ground.
- On the first ownership loss, stale outer-defense tasks are detached once so those squads can enter HAL's attack pool.
- If a second objective falls during recovery, its former anchor is detached immediately even though HAL is already in `ATTACK`.
- A recaptured point regains an anchor obligation. HAL returns to `DEFEND` when no recovery target remains.

Impasse still publishes ownership and supplies normally authorized forces. It does not issue the recovery waypoints.

V5 locks HAL's commander personality to `COMPETENT`:

- `RydHQ_MAtt = true`
- all six personality scalars = `0.5`

The reserve probability is explicitly `RydHQ_CRDefRes = 0.20`. This makes the configured probability stable, but NR6 still samples individual reserve membership and tactical positions randomly.

The hidden commander moves to a land position 75 metres outside the first OPFOR-held objective's actual capture radius. It therefore cannot count as an immortal defender. HAL still receives the complete `RydHQ_Taken` ownership list; the nearby HQ point becomes an additional outer defense point for a real held objective instead of a wasted point at a player-held flag.

## Telemetry

`doctrine` now reports:

`[order, IdleDef, DefendObjectives, NoDef count, NoAttack count, reserve probability, personality, recovery active, held count, active count]`

`objective-mirror` now reports:

`[zone index, active objectives, OPFOR-held objectives, commander-represented objective]`

`objective-allocation` appends each group's role:

`[group id, assigned objective, HAL state, inferred objective, waypoint type, assigned distance, inferred distance, anchor|reserve|main]`

Its per-objective summary includes ownership state:

`[objective, held|recovery, affinity count, inferred allocation count]`

`anchor-coverage` reports:

`[zone index, [[objective, radius, anchor id, anchor conscious, anchor inside, all OPFOR inside, state, refill state], ...]]`

Lifecycle events include:

- `anchor-promoted`
- `anchor-order-requested`
- `anchor-order-issued`
- `anchor-vacant`
- `anchor-deficit`
- `anchor-refill-assigned`
- `anchor-refill-satisfied`
- `anchor-refill-retry`
- `anchor-refill-cancelled`
- `anchor-capacity-reclaim`
- `anchor-reset`
- `objective-ownership`
- `recovery-start`

## Hosted V5 behavior test

1. Pack the V5 branch and confirm `CLASH OBS | pilot-ready` reports `["version",5]`.
2. Use untouched **NR6 Pack 4.11 / HAL 1.26.2 RC1** exactly once.
3. Select **C.L.A.S.H. control mode = Live OPFOR infantry pilot**.
4. Let all three objectives establish anchors.
5. Attack one objective from the front and one from a flank.
6. Reduce one anchor below six conscious soldiers without capturing the point.
7. Wipe one anchor group completely.
8. Let Impasse's population manager spawn a replacement.
9. Capture one OPFOR objective while at least one other objective remains OPFOR-held.
10. Confirm its anchor and refill dissolve, HAL reports `ATTACK`, and the surviving anchors remain in `RydHQ_NoAttack` / `RydHQ_NoRecon`.
11. Observe non-anchor groups counterattack the lost objective through HAL's native capture behavior.
12. Recapture the point and confirm a new anchor is established there; if it was the only lost point, doctrine returns to `DEFEND`.
13. Continue for at least ten minutes.

### Hosted pass gate

- one designated anchor squad exists per OPFOR-held objective;
- each slot reaches `COVERED` only when at least six conscious members of its designated squad are inside the capture radius;
- incidental OPFOR presence does not satisfy the slot or suppress a required refill;
- the remaining managed groups retain outer-screen, maneuver, and reserve behavior;
- an intact moving anchor does not produce repeated orders inside the cooldown;
- a degraded or wiped anchor produces one objective-specific deficit;
- the next normally authorized OPFOR squad is assigned to the correct objective;
- global and per-objective HAL caps remain intact;
- no duplicate refill, allocation drift, release timeout, commander warning, or SQF error occurs;
- visual behavior retains an outer screen and reserve rather than collapsing all groups into the capture circles.
- a temporarily lost point remains an untaken HAL objective instead of causing its assigned groups to be released;
- HAL, not Impasse, conducts the counterattack;
- surviving anchors do not join the attack, while the lost point's former anchor becomes maneuver-capable;
- recapture restores the anchor contract and clears recovery doctrine when no lost point remains.

## Dedicated transition gate

After the hosted V5 gate passes, run a genuine dedicated server through `ZoneNext 1 >> 2`.

The old zone must show `anchor-reset` before group release. No old-zone refill may be fulfilled after transition begin. After transition end and the 45-second grace period, only the new OPFOR-held objective set may create anchor slots or refill requests.

The dedicated gate fails on stale anchor state, a refill assigned to an old objective, a late HAL order after release, `release-timeout`, `allocation-drift`, `pilot-failed`, or any campaign progression divergence.
