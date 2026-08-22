# Checkbook V2 artillery, logistics, SOF and interdiction certification

## Purpose

This mission gate certifies the production architecture rather than a scripted
showcase:

- HAL remains the only tactical commander.
- C.L.A.S.H. normalizes capability requests and results.
- Impasse supplies faction pools, tickets, caps and generation nodes.
- Both campaign sides use the same resolver and provider code.
- AI artillery appears between distinct rear and forward ITW FOBs.
- Player-garage artillery stays pending until its first friendly player boards.
- HAL can consume budgeted ground logistics and ammo-drop helicopter capacity.
- Enemy artillery becomes a legitimate HAL SOF/interdiction target away from the
  protected rear generation base.

## Restore point and branch

- Restore branch: `archive/pre-checkbook-v2-a054afd`
- Implementation branch: `feat/checkbook-generation-logistics-v2`
- Baseline commit: `a054afd92324b06bde2ab0ceea7b8ab1d86c5367`

Keep the certification run on the feature branch. Do not merge to `main` until
the RPT gates below pass.

## Mission setup

Use a dedicated or hosted MP test with:

1. One valid ITW player faction and enemy faction, each with at least one mobile
   artillery class.
2. At least two distinct usable land generation nodes per side in the current
   theater graph.
3. At least one HAL-recognizable SOF group per side.
4. Vehicle spawning and ticket accrual enabled.
5. One player-accessible ITW garage.
6. `ITW_CLASH_CertificationMode = true` set before `init.sqf` executes.

The certification script is production-dormant unless that flag is true.

## Automated gates

`ITW_CLASH_ArtilleryCertification.sqf` writes one line per gate:

```text
CLASH CERT | PASS | <gate> | <details>
CLASH CERT | FAIL | <gate> | <details>
```

The suite verifies:

| Gate | Required result |
|---|---|
| `BOOT_READY` | Dual HAL, capability pools and Force Generation are ready. |
| `NO_SYSTEM_GROUP_ADMISSION` | No Logic/virtual system group entered HAL field ownership. |
| `CHECKBOOK_V2_TYPED_DENIAL` | Even an unknown request returns the V2 result schema. |
| `GENERATION_NODE_FRIENDLY/ENEMY` | Both sides resolve distinct rear/forward nodes. |
| `AI_ARTILLERY_FULFILLED_FRIENDLY/ENEMY` | Both HAL commanders receive budgeted artillery. |
| `ARTILLERY_OUTSIDE_NODE_SANCTUARIES_*` | The batteries are outside both base sanctuaries. |
| `ENEMY_ARTILLERY_RECOGNIZED_*` | Each HAL commander sees the opposing battery in `RydHQ_EnArtG`. |
| `SOF_INTERDICTION_ELIGIBLE_*` | Enemy artillery and friendly SOF coexist in HAL's native planning state. |

The final line is:

```text
CLASH CERT | COMPLETE | passed=true pass=<n> fail=0
```

This certifies eligibility and state flow. It deliberately does not order SOF,
select an artillery target, issue a fire mission or choose a logistics route.
Those actions must remain native HAL decisions.

## Player-garage artillery check

1. Spawn a mobile artillery vehicle from an ITW garage.
2. Confirm the client message says it is pending deployment.
3. Before boarding, confirm it remains at the garage and is not HAL-managed.
4. Board it with the owning friendly player.
5. Confirm one server RPT line:

   ```text
   CLASH GARAGE | player-artillery-deployment-approved
   ```

6. Confirm the vehicle moves once to the interstitial deployment point and its
   local state becomes `DEPLOYED`.
7. Get out and re-enter. Confirm it does not teleport again.

## Logistics check

For each commander, create ordinary native HAL demand without directing the
support asset manually:

1. Deplete ammunition on a HAL-managed group.
2. Reduce a vehicle below HAL's fuel threshold.
3. Damage a repair-eligible vehicle.
4. Confirm V2 approvals for ground ammo, ammo helicopter, fuel and repair when
   their matching faction pools and ITW tickets are available.
5. Confirm the next native HAL support cycle selects recipients and routes.
6. Confirm C.L.A.S.H. created no waypoints and issued no movement orders.

## RPT rejection gates

Reject the run if the final mission section contains any of:

- `Undefined variable in expression: _result`
- `Type Bool, expected Number`
- a `dual-hal-group-admitted` record whose vehicle/unit type is `Logic`
- `dual-hal-core-wrapper-missing`
- artillery inside a rear or forward node sanctuary
- player-garage artillery admitted to HAL
- cross-side Checkbook denial caused only by the other side's active lease

Also record approval/denial counts by capability and side. Symmetry means equal
rules, not guaranteed equal outcomes: different faction pools and available
tickets may legitimately produce different results.

## Rollback

If an engine gate fails, keep `main` unchanged and compare against
`archive/pre-checkbook-v2-a054afd`. Fix forward on the feature branch; do not
erase the failing RPT or rewrite the restore branch.
