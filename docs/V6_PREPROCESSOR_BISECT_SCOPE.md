Temporary diagnostic scope only.

- `ITW_CLASH.sqf` is not modified.
- HAL behavior is not modified.
- Withdrawal/reconstitution behavior is not modified.
- Impasse spawning, budgets, objective ownership, persistence, and AI caps are not modified.
- Eight source mirrors are preprocessed only; none are compiled or executed.
- The existing fail-open bootstrap still governs the actual controller.
- Remove the diagnostic files and three-line `init.sqf` hook after the failing region is isolated.
