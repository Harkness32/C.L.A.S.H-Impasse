# C.L.A.S.H. / Impasse

Private integration workspace for **C.L.A.S.H.**, the arbitration bridge between the Impasse Total War mission framework and NR6 HAL.

## Status

Tranche 0 is complete: `13715765820790864929_legacy.bin` and its 86-file extraction are the accepted Impasse baseline. Tranche 1 adds a disabled-by-default, server-only observer for dedicated-server testing. It classifies groups and logs ownership seams, but it does not register groups with HAL or change waypoints, spawning, progression, locality, persistence, or cleanup.

## Authority model

- **Impasse** remains the sole strategic authority: campaign progression, objectives, spawning, tickets and budgets, transport, persistence, cleanup, and faction composition.
- **HAL** may control frontline tactics only for explicitly registered, eligible groups after Impasse has completed deployment.
- **C.L.A.S.H.** classifies groups, arbitrates tactical ownership, mirrors objectives, manages handoff and release, and records contract violations.

## Initial implementation path

1. Treat the accepted Altis PBO and 86-file extraction as the inherited Impasse baseline. **Complete.**
2. Validate the disabled-by-default observability bridge on a dedicated server. **Current.**
3. Pilot HAL control of OPFOR-only, fully dismounted infantry.
4. Expand commanders and ground roles only after the ownership contract passes.
5. Add an Impasse-approved requisition adapter; HAL never spawns directly.

Bidirectional fronts, counteroffensives, headquarters disruption, strategic retreat, campaign-failure mechanics, native HAL reinforcement modules, and persistent HAL tactical state are deferred.

## Documentation

- [Implementation audit](docs/CLASH_IMPLEMENTATION_AUDIT.md)
- [Tranche 0 accepted baseline](docs/TRANCHE_0_PARITY.md)
- [Tranche 1 server test](docs/TRANCHE_1_OBSERVABILITY.md)

The accepted Altis mission remains the behavioral oracle. Future C.L.A.S.H. changes are reviewed as explicit descendants of that baseline; repacked PBO container bytes do not need to reproduce the original archive metadata.
