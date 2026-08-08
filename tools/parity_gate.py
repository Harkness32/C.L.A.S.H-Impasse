#!/usr/bin/env python3
"""Verify an unpacked Impasse candidate against the frozen mission baseline."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


PASS = 0
FAIL = 1
BLOCKED = 2
CHUNK_SIZE = 1024 * 1024


class GateBlocked(RuntimeError):
    """Raised when parity inputs are missing, ambiguous, or untrusted."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise GateBlocked(f"manifest is not a file: {path}")

    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise GateBlocked(f"cannot read manifest {path}: {error}") from error

    if manifest.get("schema_version") != 1:
        raise GateBlocked("manifest schema_version must be 1")

    baseline = manifest.get("baseline")
    if not isinstance(baseline, dict):
        raise GateBlocked("manifest baseline object is missing")

    expected = baseline.get("sha256")
    if not isinstance(expected, str) or len(expected) != 64:
        raise GateBlocked("manifest baseline.sha256 must be a 64-character digest")

    try:
        int(expected, 16)
    except ValueError as error:
        raise GateBlocked("manifest baseline.sha256 is not hexadecimal") from error

    expected_file_count = baseline.get("expected_file_count")
    if not isinstance(expected_file_count, int) or expected_file_count < 1:
        raise GateBlocked("manifest baseline.expected_file_count must be a positive integer")

    return manifest


def verify_artifact(path: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    if not path.is_file():
        raise GateBlocked(f"baseline artifact is not a file: {path}")

    expected = manifest["baseline"]["sha256"].lower()
    actual = sha256_file(path)
    if actual != expected:
        raise GateBlocked(
            f"baseline artifact SHA-256 mismatch: expected {expected}, got {actual}"
        )

    return {
        "path": str(path),
        "sha256": actual,
        "size": path.stat().st_size,
        "verified": True,
    }


def collect_tree(root: Path) -> dict[str, dict[str, Any]]:
    if not root.is_dir():
        raise GateBlocked(f"extracted tree is not a directory: {root}")

    files: dict[str, dict[str, Any]] = {}
    casefolded: dict[str, str] = {}

    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        relative = path.relative_to(root).as_posix()

        if path.is_symlink():
            raise GateBlocked(f"symlink is not permitted in extracted tree: {relative}")
        if not path.is_file():
            continue

        folded = relative.casefold()
        previous = casefolded.get(folded)
        if previous is not None and previous != relative:
            raise GateBlocked(
                "case-insensitive path collision in extracted tree: "
                f"{previous!r} and {relative!r}"
            )
        casefolded[folded] = relative
        files[relative] = {
            "sha256": sha256_file(path),
            "size": path.stat().st_size,
        }

    return files


def compare_trees(
    baseline: dict[str, dict[str, Any]],
    candidate: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    baseline_paths = set(baseline)
    candidate_paths = set(candidate)
    shared_paths = baseline_paths & candidate_paths

    missing = sorted(baseline_paths - candidate_paths)
    extra = sorted(candidate_paths - baseline_paths)
    changed = [
        {
            "path": path,
            "baseline": baseline[path],
            "candidate": candidate[path],
        }
        for path in sorted(shared_paths)
        if baseline[path] != candidate[path]
    ]

    return {
        "baseline_file_count": len(baseline),
        "candidate_file_count": len(candidate),
        "missing": missing,
        "extra": extra,
        "changed": changed,
        "identical": not missing and not extra and not changed,
    }


def build_report(
    manifest_path: Path,
    artifact_path: Path,
    baseline_root: Path,
    candidate_root: Path,
) -> tuple[dict[str, Any], int]:
    try:
        manifest = load_manifest(manifest_path)
        artifact = verify_artifact(artifact_path, manifest)

        resolved_baseline = baseline_root.resolve(strict=True)
        resolved_candidate = candidate_root.resolve(strict=True)
        if resolved_baseline == resolved_candidate:
            raise GateBlocked("baseline and candidate roots resolve to the same directory")

        baseline_tree = collect_tree(resolved_baseline)
        expected_file_count = manifest["baseline"]["expected_file_count"]
        if len(baseline_tree) != expected_file_count:
            raise GateBlocked(
                "baseline extracted file count mismatch: "
                f"expected {expected_file_count}, got {len(baseline_tree)}"
            )

        candidate_tree = collect_tree(resolved_candidate)
        comparison = compare_trees(baseline_tree, candidate_tree)
    except (GateBlocked, FileNotFoundError, OSError) as error:
        return {
            "schema_version": 1,
            "status": "BLOCKED",
            "reasons": [str(error)],
        }, BLOCKED

    status = "PASS" if comparison["identical"] else "FAIL"
    return {
        "schema_version": 1,
        "status": status,
        "manifest": str(manifest_path),
        "artifact": artifact,
        "baseline_root": str(resolved_baseline),
        "candidate_root": str(resolved_candidate),
        "comparison": comparison,
    }, PASS if comparison["identical"] else FAIL


def write_report(report: dict[str, Any], path: Path | None) -> None:
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if path is None:
        sys.stdout.write(rendered)
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"{report['status']}: report written to {path}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--baseline-artifact", required=True, type=Path)
    parser.add_argument("--baseline-dir", required=True, type=Path)
    parser.add_argument("--candidate-dir", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_args(argv)
    report, exit_code = build_report(
        manifest_path=arguments.manifest,
        artifact_path=arguments.baseline_artifact,
        baseline_root=arguments.baseline_dir,
        candidate_root=arguments.candidate_dir,
    )
    write_report(report, arguments.report)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
