# C.L.A.S.H. Integration Seams

This document records the ownership boundary used while C.L.A.S.H. remains mission-side and prepares the codebase for a later addon extraction.

## Rule

**Native systems expose facts. C.L.A.S.H. owns policy.**

Impasse and HAL should receive the smallest practical source edits needed to expose a semantic fact or interception point. Recovery, logistics, arbitration, parity, and specialist doctrine belong in C.L.A.S.H. modules.

Avoid:
- copying C.L.A.S.H. policy into large native ITW/HAL functions;
- late runtime monkey patches when a compile-time/source seam is available;
- inferring provenance after the native system already discarded it.

Prefer:
- explicit provenance stamped at the point where ITW creates or transforms an entity;
- narrow preInit authority only for functions Impasse compiles before normal C.L.A.S.H. startup;
- compatibility aliases with a documented removal path.

## Formation recovery

There are two different concepts and they must never overlap.

### Shattered formation

A legitimate combat formation entered service at viable strength and was later reduced to 1–2 survivors by casualties.

C.L.A.S.H. owns the policy:
1. classify it as `ITW_CLASH_Shattered`;
2. force HAL GTFO / CASEVAC through the existing withdrawal path;
3. require physical rear recovery;
4. queue the original archetype for full, free reconstitution.

`ITW_CLASH_FormationRecovery.sqf` is the canonical shattered-formation detector.

`ITW_CLASH_RemnantEvac.sqf` is retained temporarily as a compatibility bootstrap because CASEVAC v5 and existing mission startup still consume the old `ITW_CLASH_RemnantEvac*` projection.

### Deployment remnant

A 1–2 man group manufactured by Impasse deployment packing or partial squad construction is not a shattered combat formation.

The authoritative fact must be stamped by native Impasse at the exact creation/split site, e.g. `ITW_CLASH_DeploymentRemnant = true`. C.L.A.S.H. must not infer this later from group size alone.

Planned recovery policy:
1. withdraw the marked deployment remnant;
2. require physical rear recovery;
3. bank the exact recovered personnel/classes by side;
4. when four are banked, create a free four-man consolidation formation.

A legitimate two-man configured formation is never a deployment remnant merely because its size is two.

## Existing accounting seam

`ITW_CLASH_fnc_AuditWithdrawals` remains the physical rear-arrival transaction. No recovery credit is created at classification time.

- Shattered formations use the existing full-archetype reconstitution queue.
- Deployment remnants will branch at this same arrival seam into the remnant bank.

## Future addon extraction

The mission implementation should evolve toward a small adapter contract:

```text
Impasse facts/hooks ─┐
                     ├─> C.L.A.S.H. policy/core
HAL facts/hooks ─────┘
```

Once the semantic seam list stabilizes, these mission-side adapters can become an `@CLASH` addon bootstrap without rewriting the core behavior.
