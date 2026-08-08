# Tranche 0 — Accepted Altis baseline

## Current result

**COMPLETE — the Altis upload is the source of truth.**

The authoritative inherited Impasse state is:

- artifact: `13715765820790864929_legacy.bin`
- readable mission seed: `13715765820790864929_legacy/`
- extracted entries: 86
- SHA-256: `c0221d9ed4291c1293985808b438754198848b54987f50a9877ef15e83c16401`

The PBO is not a candidate that must be re-proven against another source. It is the accepted baseline. The readable extraction is its editable descendant for C.L.A.S.H. work.

## What the tooling is for

`tools/parity_gate.py` and `tools/extract_pbo.py` remain useful for:

- verifying that a retained baseline artifact is the pinned upload;
- regenerating or checking the 86-file extraction;
- detecting accidental source-tree drift;
- reviewing explicit changes made after C.L.A.S.H. integration begins.

They do not block Tranche 1. A clean repack must be loadable and behaviorally correct, but it does not need to reproduce the original PBO container bytes or packing metadata.

## Authority and scope

- Impasse remains the sole strategic and campaign authority.
- HAL remains an external dependency and receives no runtime control in Tranche 1.
- The extracted Altis mission is the only mission tree modified by the observer patch.
- NR6 HAL source, release binaries, signatures, keys, and unrelated faction assets remain unchanged.

## Exit gate

Tranche 0 is closed. Future review compares intentional C.L.A.S.H. changes against this accepted baseline; it does not reopen baseline provenance.
