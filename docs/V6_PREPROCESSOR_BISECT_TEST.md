Smoke test procedure:

1. Merge the diagnostic PR.
2. Deploy the resulting mission tree without merging into an older runtime folder.
3. Launch hosted multiplayer with `ITW_ParamCLASHObserver=2`.
4. Run only long enough to capture all eight `CLASH PP | chunk=` lines and the following `CLASH BOOT` fallback.
5. Upload the RPT.

Do not judge withdrawal/reconstitution behavior during this diagnostic build unless the normal full-controller bootstrap unexpectedly reaches `READY` and `pilot-ready`.
