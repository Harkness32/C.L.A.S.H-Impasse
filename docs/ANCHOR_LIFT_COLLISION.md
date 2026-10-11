# Loaded helicopters that never leave: the anchor, not the addon

Status: fix on `agent/anchor-lift-collision`, cut from
`agent/formation-admission-transactional` (`f1e6060`). Static tests green. Not
yet flown.

Written against two RPTs from 2026-10-10 and the audit handoff of 2026-10-11
that attributes the fault to `CLASH HAL Additions` owning `NR6_fnc_HALcore`.

---

## 1. What the logs show

Run A, 20:53, Additions v0.1 loaded. BLUFOR lifts:

| Squad | Anchor promotion | Lift |
|---|---|---|
| G30 | 20:56:50, 5 s before its lift request | embarked 20:57:41, `POST-EMBARK-NO-OUTBOUND-MOVE` to end of log |
| G34 | 20:57:43, same second as its lift request | embarked 20:58:17, same |
| G32 | 20:58:18, while walking to its carrier | recon aborted, lift cancelled |
| G29 | none during its lift | embarked 21:01:39, flew, `result=PARADROP` 21:03:33 |

Run B, 20:14, Additions not loaded. Four lifts (G28, G31, G34, G40), all
launched. The only anchor all run was G29 with fifteen men, promoted once at
20:22:11 and never lifted.

Eight lifts across both runs. "Anchor `Break` landed on the squad while its
order was in the cargo loop" predicts all eight outcomes. "Additions loaded"
gets G29 in run A wrong: that lift flew and dropped with the addon's own
`GoRecon` compiled in (`order=GoRecon`, sources listed as
`\clash_hal_additions\hal\GoRecon.sqf` in the `hal-unload-ready` line).

## 2. Mechanism

1. `Anchor_fnc_Order` sets `Break` on the squad it has chosen, waits 6 s, then
   spawns `HAL_GoDef`. It did this to squads HAL had just tasked.
2. In a HAL cargo loop `Break` does not abort the order. It sets
   `_endThis = true`, `_alive` is reset two lines later, and `HAL_SCargo` is
   still spawned in that pass (`GoRecon.sqf:320, 328, 344`; same shape at
   `GoAttInf.sqf:270` and `GoCapture.sqf:283`).
3. The loop exits after that one pass. `Busy` is still true, so the order goes
   on to its foot phase and gives the squad a MOVE waypoint to the objective
   (`GoRecon.sqf:449, 542`). Both stuck squads show that waypoint about 6 s
   after the lift request.
4. `SCargo` has no link back to the order. It flies the pickup, the base embark
   seats the squad, and it waits on `CargoM` for an outbound waypoint that no
   thread will write.
5. A squad aboard a vehicle is not a valid anchor, so the audit released it,
   deleted its waypoints, and promoted the next eight-man squad at the base,
   which was the next one HAL was about to lift.

`HAL_GoDef` exits at once on a `Busy` group (`GoDef.sqf:31`), so the promotion
achieved nothing for what it broke.

## 3. The handoff, claim by claim

Holds:

- **Do not ship PR #59.** Correct, for the dependency reasons it lists. Checked
  against source:
  - `ITW_CLASH_GTFO_GroupRestDecoy` is written by `ITW_CLASH_GTFO.sqf:311` and
    read only by the addon's `GoRest.sqf`. Native `GoRest` ignores it.
  - `_preloadedSling` exists only in the addon's `GoAmmoSupp.sqf`, and
    `PrimeExactAmmoSling` is live (`ITW_CLASH_HALLogistics.sqf:182`, called
    from the native interceptors and Thunder Run).
  - The addon's `SuppAmmo`, `SuppFuel`, `SuppRep` call
    `ITW_CLASH_HALLogistics_fnc_ProviderVehicle`. Native ones do not.
  - The addon's `TaskInitNR6.sqf` passes dispatch provenance in slot 8.
- **Wrapper order is a race.** Correct, and run B already contains two
  instances (section 4).

Does not hold:

- **"Strong A/B evidence that loading Additions breaks transport."** The A/B
  changed three things at once: the addon, which squad the anchor took, and
  whether the paradrop unload bound at all. Run A contains a successful lift
  with the addon loaded.
- **"Additions owning HALcore is the likely transport root cause."** No
  mechanism is given, and none is visible:
  - the addon's `GoRecon.sqf` and `GoAttInf.sqf` are stock plus a ten-line
    trace block (diffed);
  - its responder dispatched nothing in run A (zero `CLASHHALADD | dispatch`
    lines);
  - apart from the swaps and the forked `TaskInitNR6`, its `RydHQInit.sqf`
    differs from stock in one behaviour: `VarInit` and the overrides run inside
    one `isNil` block.
- **"The carrier can sit indefinitely."** `SCargo.sqf:645` bounds it at 600 s
  of accumulated standstill. Run A ended 7 minutes after the first embark, so
  the timeout was not reached.

Unresolved items it lists, now resolved:

- **`GoCaptureNaval` ("blocker, not audited").** The addon copy differs from
  stock in one way: the `Capturing...` read takes a default at five sites.
  Nothing else. One-Zero hardening repairs that state for `HAL_GoCapture` only,
  so naval capture loses the guard under native mode.
- **`GoCapture`.** Same single delta at eleven sites. One-Zero repairs a
  missing or malformed value at entry, which is the case the burn-in hit. A
  value that goes missing mid-order is not covered. No run has shown one.

## 4. What it missed

**The addon's atomic init was doing useful work.** Stock `RydHQInit` runs
`VarInit` scheduled, so `HAL_*` globals appear one at a time and other threads
run in between. The addon ran it inside `isNil`, so they appeared together.
Run B shows the difference:

- `hal-waypoint-guard-ready ... HAL_GoRecon:absent ... HAL_GoRest:absent`. The
  guard woke on `HAL_GoCapture` (`VarInit.sqf:1098`) before `HAL_GoRecon`
  (`:1109`) and `HAL_GoRest` (`:1111`) existed, and never guarded them.
- `service-execution-guards-ready ... optionalAttack=["GoFlank"]`.
  `HAL_GoSFAttack` (`:1112`) did not exist yet, so it got no service guard.
  Run A lists both.

Under native HALcore every binder that waits on one early global has this
exposure. `ITW_CLASH_HALUnload.sqf` waits for `GoAttInf`, `GoCapture` and
`GoRecon`, then installs seven globals including `GoRest` and `GoSFAttack`,
which `VarInit` assigns after `GoRecon`. If it installs first, `VarInit`
overwrites those two with stock. Not observed, same class as the two above.
A binder that waits for `A_HQSitRep` (`VarInit.sqf:1130`, the last compile in
the file) cannot wake mid-init.

**Run B had no paradrop at all.** `hal-unload-failed |
reason=hal-runtime-bind-timeout` at 20:23:09. `HALUnload` requires
`CLASH_HALAdd_SourcePaths` to exist, so without the addon the seven order files
keep stock landing. Run B's lifts are evidence about stock unload only.

**The new responder filter removes most of the responder.** PR #59 reserves
`RydHQ_CargoG`. HAL's autofill puts every crewed vehicle with passenger seats
in that list (`HAC_fnc2.sqf:2370, 2672`), which covers APCs, IFVs, MRAPs and trucks,
so the `ARM` and `cars` pools are close to empty. `Busy` and `CargoM` already
protect a carrier that is mid-lift.

## 5. The fix

`ITW_CLASH_CommanderParity.sqf` (version 3):

- `Anchor_fnc_IsHALCommitted`: `Busy`, `CargoChosen`, `CargoCheckPending`,
  the transport retask lock, or any living member aboard a vehicle.
- `Anchor_fnc_Select` skips a committed squad.
- `Anchor_fnc_Order` checks again at the write and logs `order-deferred`
  instead of setting `Break`.
- `Anchor_fnc_Clear` releases a committed squad by bookkeeping only. It no
  longer deletes its waypoints or clears its `Break`.
- `Anchor_fnc_IsEligible` is unchanged. A holding anchor is under `GoDef`,
  which never sets `Busy`, so it is not evicted.

`ITW_CLASH_HALCargoDiceFix.sqf` (version 6):

- At the base-embark seam, a squad whose current waypoint is more than 300 m
  from both itself and the carrier, on two readings 6 s apart, is treated as
  no longer waiting. The carrier's `CargoM` is cleared and nobody is seated.
  `SCargo` then takes its own abort (`SCargo.sqf:470, 492`): it releases the
  squad's cargo flags, cancels the landing, sends the carrier home and frees
  it.
- The `SCargo` source patch text is unchanged.

Cost:

- An objective can stay unanchored until a free squad or the Impasse refill
  exists, because the anchor no longer pre-empts HAL orders.
- A cancelled lift is a squad that walks. In run A that would have been a
  3.9 km march for G30.
- The 300 m rule is a heuristic on HAL's parking behaviour. Measured margin:
  seven healthy lifts had nothing past 60 m, both orphans had 3.9 km.
- Not covered: an order that ended outright and left the squad idle. There is
  no route to read, and no run has shown it.

## 6. How to certify from an RPT

Boot:

- `commander-parity-ready | version=3 ... anchorSkipsHALCommitted=true`
- `hal-cargo-dice-fix-ready | version=6 ... orphanLiftGuard=true`

In play:

- no `POST-EMBARK-NO-OUTBOUND-MOVE`;
- no `commander-parity-anchor-promoted` naming a squad within the minute after
  that squad's `recon-assigned`;
- `commander-parity-anchor-order-deferred` and `orphan-lift-cancelled` should
  be rare. Each one is a collision that was caught, and worth reading.

The test that separates the two explanations: fly this branch with Additions
v0.1 loaded. If lifts launch, the addon was not the cause.

## 7. Still open

- After a paradrop the carrier keeps three waypoints with `Busy` and `CargoM`
  true. `ITW_AtkParachute` unassigns each jumper (`ITW_Attack.sqf:4244`), so
  the order file can no longer find the carrier to clear `CargoM`
  (`GoCapture.sqf:637, 656, 715`). Run A's one paradrop showed exactly that
  state 62 s after the drop, then the aircraft was lost. One sample.
- The anchor re-issues its order every 60 s while the squad is outside the
  objective. Run B's anchor covered about 1.8 km in 22 minutes and was vacated
  358 m short. Not investigated.
