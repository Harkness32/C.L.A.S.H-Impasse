# V6 C.L.A.S.H. Preprocessor Root-Fix Validation

## Root cause isolated

Hosted RPT bisecting showed that only original `ITW_CLASH.sqf` lines 1-339 failed Arma preprocessing. Chunks covering lines 340-2639 all returned non-zero output. Within the failing region, the unique redundant preprocessor construct was the second ACE `#if __has_include(...)` block inside `ITW_CLASH_fnc_IsConscious`.

The established Impasse `defines.hpp` already provides the `CONSCIOUS(unit)` macro with the required ACE/non-ACE behavior. The validation source therefore replaces the local conditional with:

```sqf
ITW_CLASH_fnc_IsConscious = {
    params ["_unit"];
    if (isNull _unit || {!alive _unit}) exitWith {false};
    CONSCIOUS(_unit)
};
```

## Validation load path

The canonical `ITW_CLASH.sqf` is still probed first. If Arma continues returning zero preprocessed characters for that file, `ITW_CLASH_Bootstrap.sqf` preprocesses the controller in independent source segments and concatenates the resulting SQF before compilation.

The first failing region is split into three safe segments around `ITW_CLASH_fnc_IsConscious`; the already-proven chunks 02-08 provide the remainder of the controller. Every segment is individually required to preprocess to non-zero source before compilation.

This segmented path is a validation bridge, not the intended long-term source layout. Once runtime proves the root fix with `READY` and `pilot-ready`, consolidate the fixed `IsConscious` implementation back into the canonical controller and remove the temporary segment files.

## Runtime gate

With `ITW_ParamCLASHObserver=2`, require this sequence before judging V6 combat behavior:

1. `CLASH BOOT | canonical-preprocess-failed | trying segmented-source`
2. ten `CLASH BOOT | segment | ... chars=<non-zero>` lines
3. `CLASH BOOT | source-selected | segmented | ...`
4. `CLASH BOOT | READY | version=6 ... functions=54`
5. `CLASH OBS | observer-start`
6. `CLASH OBS | pilot-ready` reporting V6

If any segment is zero length, bootstrap must fail open and baseline Impasse must remain active.
