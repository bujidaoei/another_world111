"""Read and verify Godot PCK directory/data using the pinned engine's format.

Official format: Godot 4.7.2 core/io/pck_packer.cpp and file_access_pack.cpp.
Only unencrypted, non-sparse, standalone production packs are accepted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path, PurePosixPath


def inspect(path: Path) -> dict:
    raw = path.read_bytes()
    if len(raw) < 96 or raw[:4] != b"GDPC":
        raise ValueError("Not a standalone Godot PCK")
    version, major, minor, patch, flags = struct.unpack_from("<5I", raw, 4)
    if version not in (2, 3, 4) or (major, minor, patch) != (4, 7, 2):
        raise ValueError("Pack format or engine version differs from the pinned toolchain")
    if flags & 1 or flags & 4:
        raise ValueError("Encrypted directories or sparse bundles cannot be audited by this pipeline")
    file_base = struct.unpack_from("<Q", raw, 24)[0]
    cursor = struct.unpack_from("<Q", raw, 32)[0] if version >= 3 else 96
    if cursor + 4 > len(raw):
        raise ValueError("Invalid pack directory offset")
    file_count = struct.unpack_from("<I", raw, cursor)[0]
    cursor += 4
    if not 0 < file_count < 100000:
        raise ValueError("Invalid pack file count")
    files = []
    seen = set()
    forbidden_paths = []
    forbidden_payload_markers = []
    project_settings_checked = False
    for _ in range(file_count):
        if cursor + 4 > len(raw):
            raise ValueError("Truncated pack directory")
        length = struct.unpack_from("<I", raw, cursor)[0]
        cursor += 4
        if not 0 < length <= 65536 or cursor + length + 36 > len(raw):
            raise ValueError("Invalid pack path length")
        name = raw[cursor:cursor + length].rstrip(b"\0").decode("utf-8")
        cursor += length
        offset, size = struct.unpack_from("<2Q", raw, cursor)
        digest = raw[cursor + 16:cursor + 32]
        file_flags = struct.unpack_from("<I", raw, cursor + 32)[0]
        cursor += 36
        pure = PurePosixPath(name.removeprefix("res://"))
        normalized = str(pure)
        if pure.is_absolute() or ".." in pure.parts or "\\" in normalized or normalized in seen:
            raise ValueError("Unsafe or duplicate packed path")
        seen.add(normalized)
        if file_flags:
            raise ValueError(f"Unsupported production file flags: {normalized}")
        start = file_base + offset
        if start + size > len(raw):
            raise ValueError(f"Truncated payload: {normalized}")
        payload = raw[start:start + size]
        if hashlib.md5(payload, usedforsecurity=False).digest() != digest:
            raise ValueError(f"PCK file digest mismatch: {normalized}")
        lowered = normalized.lower()
        if lowered.startswith(("addons/godot_ai/", "addons/gdunit4/", "tests/", "reports/")) or "game_helper" in lowered:
            forbidden_paths.append(normalized)
        if normalized == "project.binary" or lowered.endswith((".gd", ".gdc", ".cfg", ".remap")):
            for marker in (b"godot_ai", b"gdunit4", b"_mcp_game_helper", b"res://tests/"):
                if marker in payload.lower():
                    forbidden_payload_markers.append({"path": normalized, "marker": marker.decode()})
        if normalized == "project.binary":
            project_settings_checked = True
        files.append({"path": normalized, "bytes": size, "md5": digest.hex(), "sha256": hashlib.sha256(payload).hexdigest()})
    if forbidden_paths or forbidden_payload_markers or not project_settings_checked:
        raise ValueError("Production pack includes debug/test content or lacks checked project.binary")
    for required in ("config/rules.json", "config/presentation.json"):
        if required not in seen:
            raise ValueError(f"Required production config missing: {required}")
    if not any(name.startswith("presentation/main.tscn") for name in seen):
        raise ValueError("Production main scene missing")
    return {"ok": True, "pack_format": version, "engine_version": f"{major}.{minor}.{patch}", "files": files, "file_count": file_count,
            "pck_sha256": hashlib.sha256(raw).hexdigest(), "pck_bytes": len(raw), "verified_md5_files": len(files),
            "debug_test_paths": forbidden_paths, "debug_settings_markers": forbidden_payload_markers, "project_binary_checked": project_settings_checked}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pack", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = inspect(args.pack)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "files"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
