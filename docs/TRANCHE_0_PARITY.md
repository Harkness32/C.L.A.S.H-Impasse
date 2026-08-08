# Tranche 0 — Repository and parity gate

## Current result

**BLOCKED — parity has not been established.**

The authoritative baseline artifact has been recovered and verified locally. Its SHA-256 matches the pinned value; its PBO footer SHA-1 is valid; its header contains 86 uncompressed entries and no case-insensitive path collisions. The repository still does not contain the buildable current Impasse mission source or its known-good build command. Passing tests for the harness and extracting the baseline do not prove candidate parity.

## Authority and exclusions

| Input | Disposition |
|---|---|
| `13715765820790864929_legacy.bin` | Required authoritative baseline; SHA-256 is pinned in `baseline/manifest.json` |
| Current buildable Impasse source | Required candidate source; mission root is not yet identified |
| `mission(1).pbo` | Rejected as a seed because it is outdated |
| 26th USMC PBOs/configs | Separate faction assets; excluded from C.L.A.S.H. parity |
| NR6 HAL 1.26.2 RC1 | Later integration input; excluded from the pre-C.L.A.S.H. mission parity comparison |

Do not reconstruct the repository from the old PBO. Do not label a source tree “current” merely because it builds. The consequence of being wrong is subtle regression: missing objective, attack, base, save, side-operation, or SKULL behavior can be misdiagnosed later as a HAL integration defect.

## What must be supplied

1. The source tree that builds the current Impasse Altis mission.
2. The known-good mission build command, including tool name and version.
3. Any intentional source-to-baseline divergences, each documented by path and reason.

The mission root and build command must be identified from those inputs. This tranche deliberately does not invent a `src/mission` layout or a new packing toolchain.

## Local working layout

Authoritative binaries and extracted trees stay local and are ignored by Git:

```text
.local/
  baseline/
    13715765820790864929_legacy.bin
    extracted/
  candidate/
    extracted/
```

Extract the verified baseline with the repository's constrained reader:

```powershell
python tools/extract_pbo.py `
  .local/baseline/13715765820790864929_legacy.bin `
  .local/baseline/extracted
```

The extractor supports only the validated `Vers` PBO subset used here: uncompressed entries with a valid footer checksum. It refuses unknown packing methods, unsafe paths, path collisions, a bad footer, or a pre-existing output directory.

After building and extracting the candidate with the known-good project toolchain, run:

```powershell
python tools/parity_gate.py `
  --manifest baseline/manifest.json `
  --baseline-artifact .local/baseline/13715765820790864929_legacy.bin `
  --baseline-dir .local/baseline/extracted `
  --candidate-dir .local/candidate/extracted `
  --report .local/parity-report.json
```

The same invocation works in Bash without PowerShell backticks.

## Gate semantics

The comparator is deny-by-default:

- the baseline artifact must match the pinned SHA-256;
- the extracted baseline must contain the audited 86 files;
- both extracted roots must exist and be different directories;
- symlinks and case-insensitive path collisions are rejected;
- missing, extra, and byte-changed files fail the gate;
- file timestamps and directory timestamps are ignored; and
- no default path or line-ending exceptions are hidden in the tool.

Exit codes:

| Code | Meaning |
|---:|---|
| `0` | `PASS`: artifact verified and extracted file trees are byte-identical |
| `1` | `FAIL`: valid inputs compared, but file trees differ |
| `2` | `BLOCKED`: input, manifest, hash, path, symlink, or case-collision problem |

An intentional divergence does not become parity by fiat. Resolve it or document it in a reviewed exception mechanism before relaxing the gate.

## Tranche 0 exit gate

Tranche 0 closes only when:

1. the current source and its mission root are identified;
2. the baseline checksum and extracted structure are verified;
3. a clean candidate build is reproducible;
4. extracted-tree comparison passes, or every divergence is reviewed and recorded; and
5. the exact build, extraction, and comparison commands are committed.

Until then, C.L.A.S.H. runtime SQF and HAL inclusion remain out of scope.
