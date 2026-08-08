from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tools.parity_gate import BLOCKED, FAIL, PASS, build_report


class ParityGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.baseline = self.root / "baseline"
        self.candidate = self.root / "candidate"
        self.baseline.mkdir()
        self.candidate.mkdir()

        self.artifact = self.root / "baseline.bin"
        self.artifact.write_bytes(b"authoritative baseline")
        digest = hashlib.sha256(self.artifact.read_bytes()).hexdigest()

        self.manifest = self.root / "manifest.json"
        self.manifest.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "baseline": {
                        "artifact_name": self.artifact.name,
                        "expected_file_count": 1,
                        "sha256": digest,
                    },
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_gate(self):
        return build_report(
            self.manifest, self.artifact, self.baseline, self.candidate
        )

    def test_identical_trees_pass(self) -> None:
        (self.baseline / "init.sqf").write_bytes(b"hint 'same';\r\n")
        (self.candidate / "init.sqf").write_bytes(b"hint 'same';\r\n")

        report, exit_code = self.run_gate()

        self.assertEqual(PASS, exit_code)
        self.assertEqual("PASS", report["status"])

    def test_changed_bytes_fail(self) -> None:
        (self.baseline / "init.sqf").write_bytes(b"baseline")
        (self.candidate / "init.sqf").write_bytes(b"candidate")

        report, exit_code = self.run_gate()

        self.assertEqual(FAIL, exit_code)
        self.assertEqual(["init.sqf"], [item["path"] for item in report["comparison"]["changed"]])

    def test_missing_and_extra_files_fail(self) -> None:
        (self.baseline / "missing.sqf").write_bytes(b"baseline")
        (self.candidate / "extra.sqf").write_bytes(b"candidate")

        report, exit_code = self.run_gate()

        self.assertEqual(FAIL, exit_code)
        self.assertEqual(["missing.sqf"], report["comparison"]["missing"])
        self.assertEqual(["extra.sqf"], report["comparison"]["extra"])

    def test_wrong_artifact_hash_is_blocked(self) -> None:
        manifest = json.loads(self.manifest.read_text(encoding="utf-8"))
        manifest["baseline"]["sha256"] = "0" * 64
        self.manifest.write_text(json.dumps(manifest), encoding="utf-8")

        report, exit_code = self.run_gate()

        self.assertEqual(BLOCKED, exit_code)
        self.assertEqual("BLOCKED", report["status"])
        self.assertIn("SHA-256 mismatch", report["reasons"][0])

    def test_same_tree_is_blocked(self) -> None:
        report, exit_code = build_report(
            self.manifest, self.artifact, self.baseline, self.baseline
        )

        self.assertEqual(BLOCKED, exit_code)
        self.assertEqual("BLOCKED", report["status"])
        self.assertIn("same directory", report["reasons"][0])

    def test_empty_baseline_is_blocked(self) -> None:
        report, exit_code = self.run_gate()

        self.assertEqual(BLOCKED, exit_code)
        self.assertIn("file count mismatch", report["reasons"][0])

    def test_case_collision_is_blocked(self) -> None:
        (self.baseline / "Init.sqf").write_bytes(b"one")
        (self.baseline / "init.sqf").write_bytes(b"two")

        report, exit_code = self.run_gate()

        self.assertEqual(BLOCKED, exit_code)
        self.assertIn("case-insensitive path collision", report["reasons"][0])


if __name__ == "__main__":
    unittest.main()
