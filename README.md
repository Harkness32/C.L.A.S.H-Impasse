# C.L.A.S.H. / Impasse

Private integration workspace for **C.L.A.S.H.**, the arbitration bridge between the Impasse Total War mission framework and NR6 HAL.

## Status

Tranche 0 parity tooling is in progress. Repository-to-baseline parity is **not established** because the buildable current Impasse mission source and frozen baseline artifact are not present in this repository. No runtime integration has been implemented, and no mission or HAL package has been modified or repacked.

## Authority model

- **Impasse** remains the sole strategic authority: campaign progression, objectives, spawning, tickets and budgets, transport, persistence, cleanup, and faction composition.
- **HAL** may control frontline tactics only for explicitly registered, eligible groups after Impasse has completed deployment.
- **C.L.A.S.H.** classifies groups, arbitrates tactical ownership, mirrors objectives, manages handoff and release, and records contract violations.

## Initial implementation path

1. Establish repository-to-baseline parity.
2. Add a disabled-by-default observability bridge.
3. Pilot one-side, fully dismounted infantry control.
4. Expand commanders and ground roles only after the ownership contract passes.
5. Add an Impasse-approved requisition adapter; HAL never spawns directly.

Bidirectional fronts, counteroffensives, headquarters disruption, strategic retreat, campaign-failure mechanics, native HAL reinforcement modules, and persistent HAL tactical state are deferred.

## Documentation

- [Implementation audit](docs/CLASH_IMPLEMENTATION_AUDIT.md)
- [Tranche 0 parity gate](docs/TRANCHE_0_PARITY.md)

The frozen current Impasse mission remains the behavioral parity oracle until the repository build is proven equivalent.
