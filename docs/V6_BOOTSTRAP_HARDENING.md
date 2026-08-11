# V6 C.L.A.S.H. Bootstrap Hardening

## Purpose

This patch makes C.L.A.S.H. startup deterministic and fail-open. The controller is no longer compiled during `preInit.sqf`; preInit installs no-op observer hook shims so baseline Impasse remains safe even if the C.L.A.S.H. controller cannot load. The server compiles the controller exactly once from `init.sqf`, after mission parameters are ready, through `ITW_CLASH_Bootstrap.sqf`.

## Startup contract

A valid V6 startup must emit:

1. `CLASH BOOT | preInit | fail-open hooks installed; controller deferred to init`
2. `CLASH BOOT | begin | init-server`
3. `CLASH BOOT | file | exists=true path=ITW_CLASH.sqf`
4. `CLASH BOOT | source | chars=<non-zero>`
5. `CLASH BOOT | READY | version=6 ... functions=54`
6. `CLASH OBS | observer-start` when lobby mode is `1` or `2`
7. `CLASH OBS | pilot-ready` with version 6 when lobby mode is `2`

Do not evaluate V6 withdrawal/reconstitution behavior unless both the bootstrap `READY` line and the V6 `pilot-ready` line are present.

## Failure behavior

Any bootstrap validation failure emits one `CLASH BOOT | FAILED | ...` line followed by `CLASH BOOT | fallback | ...`. The three unguarded Impasse integration hooks become no-ops:

- `ITW_CLASH_fnc_ObserveGroup` returns `false`
- `ITW_CLASH_fnc_ObserveWriter` returns `false`, allowing the normal Impasse waypoint writer to proceed
- `ITW_CLASH_fnc_ObserveLifecycle` returns `false`

The fallback also marks observer/live startup as already handled, preventing a partially compiled controller from activating through its scheduled startup thread. Refill, reconstitution, and logging integration points already guard their C.L.A.S.H. calls with `isNil` checks.

## Regression checks

- `preInit.sqf` no longer compiles `ITW_CLASH.sqf`.
- `init.sqf` routes server startup only through `ITW_CLASH_Bootstrap.sqf`.
- `ITW_CLASH_Bootstrap.sqf` performs the sole controller compile and validates all 54 V6 functions before publishing `ITW_CLASH_BootstrapReady = true`.
- A second bootstrap call exits without recompiling or resetting controller state.
- No bootstrap failure should produce repeated `Undefined variable in expression: itw_clash_fnc_observe*` errors.
