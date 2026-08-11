# V6 canonical preprocessor fix

## Root cause

Hosted runtime bisecting isolated the C.L.A.S.H. preprocessor failure to the first controller region. The redundant local ACE `#if __has_include(...)` block inside `ITW_CLASH_fnc_IsConscious` caused both `preprocessFile` and `preprocessFileLineNumbers` to return an empty string for the canonical controller.

## Permanent fix

`ITW_CLASH_fnc_IsConscious` now retains its null/dead guard and delegates consciousness detection to Impasse's existing `CONSCIOUS(unit)` macro from `defines.hpp`.

The temporary segmented validation loader and all source mirrors are removed. `ITW_CLASH_Bootstrap.sqf` is restored to the deterministic canonical-source path: raw/preprocessor telemetry, one controller compile, V6/54-function validation, and fail-open observer shims.

## Hosted validation gate

With `ITW_ParamCLASHObserver = 2`, require:

1. `CLASH BOOT | raw | chars=<non-zero>`
2. `CLASH BOOT | preprocess | chars=<non-zero>`
3. `CLASH BOOT | preprocess-lines | chars=<non-zero>`
4. `CLASH BOOT | READY | version=6 ... functions=54`
5. `CLASH OBS | observer-start`
6. `CLASH OBS | pilot-ready`

Only after `READY` and `pilot-ready` should V6 withdrawal/reconstitution behavior be judged.
