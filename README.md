# C.L.A.S.H. / Impasse

Private integration workspace for **C.L.A.S.H.**, the arbitration bridge between the Impasse Total War mission framework and NR6 HAL.

## Status

Tranche 0 is complete: `13715765820790864929_legacy.bin` and its 86-file extraction are the accepted Impasse baseline. Tranche 1 adds a disabled-by-default, server-only observer for dedicated-server testing. It classifies groups and logs ownership seams, but it does not register groups with HAL or change waypoints, spawning, progression, locality, persistence, or cleanup.

## Authority model

- **Impasse** remains the sole strategic authority: campaign progression, objectives, spawning, tickets and budgets, transport, persistence, cleanup, and faction composition.
- **HAL** may control frontline tactics only for explicitly registered, eligible groups after Impasse has completed deployment.
- **C.L.A.S.H.** classifies groups, arbitrates tactical ownership, mirrors objectives, manages handoff and release, records contract violations, and supplies narrow compatibility shims where HAL's AI bookkeeping does not represent a player-operated asset.

Player employment is capability-driven from the asset the player is actually operating. A legacy HAL field such as `assignedVehicle` may be used for AI unchanged, while a player-only compatibility path may fall back to the actual current vehicle when HAL would otherwise discard a valid subscribed player provider.

## Initial implementation path

1. Treat the accepted Altis PBO and 86-file extraction as the inherited Impasse baseline. **Complete.**
2. Validate the disabled-by-default observability bridge on a dedicated server. **Current.**
3. Pilot HAL control of OPFOR-only, fully dismounted infantry.
4. Expand commanders and ground roles only after the ownership contract passes.
