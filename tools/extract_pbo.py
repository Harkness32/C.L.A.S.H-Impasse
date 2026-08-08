#!/usr/bin/env python3
"""Safely extract the uncompressed Vers PBO subset used by the frozen baseline."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from collections import Counter
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


VERS_METHOD = 0x56657273
HEADER_FIELDS = struct.Struct("<5I")
FOOTER_SIZE = 21


class PboError(RuntimeError):
    """Raised when an archive is invalid or outside the supported PBO subset."""


@dataclass(frozen=True)
class Entry:
    name: str
    output_path: PurePosixPath
    original_size: int
    timestamp: int
    data_size: int
    data_offset: int


def read_cstring(data: bytes, offset: int) -> tuple[str, int]:
    end = data.find(b"\0", offset)
    if end < 0:
        raise PboError("unterminated PBO string")
    try:
        value = data[offset:end].decode("utf-8")
    except UnicodeDecodeError as error:
        raise PboError("PBO path/property is not UTF-8") from error
    return value, end + 1


def read_header(data: bytes, offset: int) -> tuple[tuple[int, ...], int]:
    if offset + HEADER_FIELDS.size > len(data):
        raise PboError("truncated PBO entry header")
    return HEADER_FIELDS.unpack_from(data, offset), offset + HEADER_FIELDS.size


def safe_output_path(name: str) -> PurePosixPath:
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    if (
        not normalized
        or path.is_absolute()
        or any(part in {"", ".", ".."} or ":" in part for part in path.parts)
    ):
        raise PboError(f"unsafe PBO path: {name!r}")
    return path


def parse_archive(data: bytes) -> tuple[dict[str, str], list[Entry], str]:
    offset = 0
    marker_name, offset = read_cstring(data, offset)
    marker, offset = read_header(data, offset)
    if marker_name or marker != (VERS_METHOD, 0, 0, 0, 0):
        raise PboError("archive is not a supported Vers PBO")

    properties: dict[str, str] = {}
    while True:
        key, offset = read_cstring(data, offset)
        if not key:
            break
        value, offset = read_cstring(data, offset)
        properties[key] = value

    pending: list[tuple[str, PurePosixPath, int, int, int]] = []
    while True:
        name, offset = read_cstring(data, offset)
        fields, offset = read_header(data, offset)
        method, original_size, _reserved, timestamp, data_size = fields
        if not name:
            if fields != (0, 0, 0, 0, 0):
                raise PboError("invalid PBO header terminator")
            break
        if method != 0:
            raise PboError(f"compressed/unknown PBO entry is unsupported: {name!r}")
        if original_size != data_size:
            raise PboError(f"uncompressed PBO entry has inconsistent size: {name!r}")
        pending.append(
            (name, safe_output_path(name), original_size, timestamp, data_size)
        )

    folded = Counter(path.as_posix().casefold() for _, path, *_ in pending)
    collisions = sorted(path for path, count in folded.items() if count > 1)
    if collisions:
        raise PboError(
            "case-insensitive PBO path collision: " + ", ".join(collisions)
        )

    entries: list[Entry] = []
    payload_offset = offset
    for name, output_path, original_size, timestamp, data_size in pending:
        end = payload_offset + data_size
        if end > len(data) - FOOTER_SIZE:
            raise PboError(f"PBO payload exceeds archive bounds: {name!r}")
        entries.append(
            Entry(
                name=name,
                output_path=output_path,
                original_size=original_size,
                timestamp=timestamp,
                data_size=data_size,
                data_offset=payload_offset,
            )
        )
        payload_offset = end

    if len(data) - payload_offset != FOOTER_SIZE or data[payload_offset] != 0:
        raise PboError("PBO footer is missing or has an invalid size")

    expected_sha1 = data[payload_offset + 1 :].hex()
    actual_sha1 = hashlib.sha1(data[:payload_offset]).hexdigest()
    if actual_sha1 != expected_sha1:
        raise PboError(
            f"PBO footer SHA-1 mismatch: expected {expected_sha1}, got {actual_sha1}"
        )

    return properties, entries, actual_sha1


def extract_archive(archive: Path, destination: Path) -> dict[str, object]:
    if not archive.is_file():
        raise PboError(f"archive is not a file: {archive}")
    if destination.exists():
        raise PboError(f"destination already exists: {destination}")

    try:
        data = archive.read_bytes()
    except OSError as error:
        raise PboError(f"cannot read archive {archive}: {error}") from error

    properties, entries, footer_sha1 = parse_archive(data)
    destination.mkdir(parents=True)

    try:
        for entry in entries:
            output = destination.joinpath(*entry.output_path.parts)
            output.parent.mkdir(parents=True, exist_ok=True)
            start = entry.data_offset
            output.write_bytes(data[start : start + entry.data_size])
    except OSError as error:
        raise PboError(
            f"extraction failed; partial destination may remain at {destination}: {error}"
        ) from error

    return {
        "archive": str(archive),
        "archive_size": len(data),
        "destination": str(destination),
        "entry_count": len(entries),
        "footer_sha1": footer_sha1,
        "packing": "uncompressed",
        "properties": properties,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("destination", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    try:
        result = extract_archive(arguments.archive, arguments.destination)
    except PboError as error:
        print(json.dumps({"status": "BLOCKED", "reason": str(error)}, indent=2))
        return 2
    print(json.dumps({"status": "EXTRACTED", **result}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
