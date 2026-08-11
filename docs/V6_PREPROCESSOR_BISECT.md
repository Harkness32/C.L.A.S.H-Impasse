# V6 C.L.A.S.H. Preprocessor Bisect

## Purpose

The current runtime can read all 93,705 raw characters of `ITW_CLASH.sqf`, while both `preprocessFile` and `preprocessFileLineNumbers` return empty strings. This diagnostic pass isolates the content-specific preprocessor failure without executing any controller fragment.

## Method

`ITW_CLASH.sqf` is mirrored into eight diagnostic-only files at whole-function boundaries. Each chunk includes the same `defines.hpp` environment used by the real controller. `ITW_CLASH_PP_Bisect.sqf` preprocesses and measures each chunk with both preprocessor commands but never compiles or executes any chunk.

The original controller remains untouched. The normal validated bootstrap runs immediately after the bisect and therefore retains the existing fail-open behavior.

## Chunk map

- 01: original lines 1-339
- 02: original lines 340-667
- 03: original lines 668-1009
- 04: original lines 1010-1360
- 05: original lines 1361-1596
- 06: original lines 1597-1980
- 07: original lines 1981-2310
- 08: original lines 2311-2639

## Runtime evidence

The next hosted RPT should contain eight lines beginning with:

`CLASH PP | chunk=`

A healthy chunk reports non-zero `preprocess` and `lineNumbers` counts. Any chunk reporting raw source greater than zero while both preprocessor counts are zero contains the failing region.

After the bisect lines, the existing full-controller bootstrap is expected to fail open until the offending construct is repaired.

## Cleanup

These diagnostic chunk files and the `init.sqf` bisect call are temporary. Remove them once the failing source region is isolated and a targeted controller fix is validated.
