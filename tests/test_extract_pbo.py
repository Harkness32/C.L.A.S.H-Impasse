from __future__ import annotations

import hashlib
import struct
import tempfile
import unittest
from pathlib import Path

from tools.extract_pbo import PboError, VERS_METHOD, extract_archive


HEADER = struct.Struct("<5I")


def build_pbo(
    entries: list[tuple[str, bytes, int]],
    *,
    corrupt_footer: bool = False,
) -> bytes:
    archive = bytearray(b"\0" + HEADER.pack(VERS_METHOD, 0, 0, 0, 0) + b"\0")
    payload = bytearray()
    for name, content, method in entries:
        archive.extend(name.encode("utf-8") + b"\0")
        archive.extend(HEADER.pack(method, len(content), 0, 123, len(content)))
        payload.extend(content)
    archive.extend(b"\0" + HEADER.pack(0, 0, 0, 0, 0))
    archive.extend(payload)
    digest = hashlib.sha1(archive).digest()
    if corrupt_footer:
        digest = b"\0" * len(digest)
    archive.extend(b"\0" + digest)
    return bytes(archive)


class ExtractPboTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.archive = self.root / "mission.pbo"
        self.destination = self.root / "extracted"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_archive(self, entries, **options) -> None:
        self.archive.write_bytes(build_pbo(entries, **options))

    def test_extracts_nested_uncompressed_files(self) -> None:
        self.write_archive(
            [("init.sqf", b"init", 0), ("functions\\start.sqf", b"start", 0)]
        )

        result = extract_archive(self.archive, self.destination)

        self.assertEqual(2, result["entry_count"])
        self.assertEqual(b"init", (self.destination / "init.sqf").read_bytes())
        self.assertEqual(
            b"start", (self.destination / "functions" / "start.sqf").read_bytes()
        )

    def test_rejects_compressed_entry(self) -> None:
        self.write_archive([("init.sqf", b"data", 0x43707273)])

        with self.assertRaisesRegex(PboError, "compressed/unknown"):
            extract_archive(self.archive, self.destination)

    def test_rejects_bad_footer(self) -> None:
        self.write_archive([("init.sqf", b"data", 0)], corrupt_footer=True)

        with self.assertRaisesRegex(PboError, "SHA-1 mismatch"):
            extract_archive(self.archive, self.destination)

    def test_rejects_path_traversal(self) -> None:
        self.write_archive([("../escape.sqf", b"data", 0)])

        with self.assertRaisesRegex(PboError, "unsafe PBO path"):
            extract_archive(self.archive, self.destination)

    def test_rejects_case_collision(self) -> None:
        self.write_archive([("Init.sqf", b"one", 0), ("init.sqf", b"two", 0)])

        with self.assertRaisesRegex(PboError, "case-insensitive"):
            extract_archive(self.archive, self.destination)

    def test_rejects_existing_destination(self) -> None:
        self.write_archive([("init.sqf", b"data", 0)])
        self.destination.mkdir()

        with self.assertRaisesRegex(PboError, "already exists"):
            extract_archive(self.archive, self.destination)
