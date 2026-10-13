"""Prove a QA launch pack only changes its two startup files.

The production PCK is first audited with the same strict distribution auditor.
Unchanged settings are compared as exact serialized Variant bytes, not decoded guesses.
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from inspect_pck import inspect


def payload(path: Path, wanted: str) -> bytes:
    raw = path.read_bytes()
    version = struct.unpack_from("<I", raw, 4)[0]
    base = struct.unpack_from("<Q", raw, 24)[0]
    cursor = struct.unpack_from("<Q", raw, 32)[0] if version >= 3 else 96
    count = struct.unpack_from("<I", raw, cursor)[0]
    cursor += 4
    for _ in range(count):
        size = struct.unpack_from("<I", raw, cursor)[0]
        cursor += 4
        name = raw[cursor:cursor + size].rstrip(b"\0").decode().removeprefix("res://")
        cursor += size
        offset, length = struct.unpack_from("<2Q", raw, cursor)
        cursor += 36
        if name == wanted:
            return raw[base + offset:base + offset + length]
    raise ValueError(f"Missing independently audited payload: {wanted}")


def binary_settings(raw: bytes) -> dict[str, bytes]:
    if raw[:4] != b"ECFG":
        raise ValueError("Invalid project.binary magic")
    count = struct.unpack_from("<I", raw, 4)[0]
    cursor = 8
    result = {}
    for _ in range(count):
        key_size = struct.unpack_from("<I", raw, cursor)[0]
        cursor += 4
        key = raw[cursor:cursor + key_size].decode("utf-8")
        cursor += key_size
        value_size = struct.unpack_from("<I", raw, cursor)[0]
        cursor += 4
        value = raw[cursor:cursor + value_size]
        cursor += value_size
        if key in result or len(value) != value_size:
            raise ValueError("Duplicate or truncated project.binary entry")
        result[key] = value
    if cursor != len(raw):
        raise ValueError("Trailing project.binary data")
    return result


def variant_string(text: str) -> bytes:
    data = text.encode("utf-8")
    return struct.pack("<2I", 4, len(data)) + data + bytes((-len(data)) % 4)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("production", type=Path)
    parser.add_argument("qa", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    prod, qa = inspect(args.production), inspect(args.qa)
    before = {f["path"]: f for f in prod["files"]}
    after = {f["path"]: f for f in qa["files"]}
    if before.keys() != after.keys():
        raise ValueError("QA pack adds or removes a production packed resource")
    differences = sorted(name for name in before if before[name]["sha256"] != after[name]["sha256"])
    expected = [".godot/global_script_class_cache.cfg", "project.binary"]
    if differences != expected:
        raise ValueError(f"Unexpected production payload differences: {differences}")
    settings_before = binary_settings(payload(args.production, "project.binary"))
    settings_after = binary_settings(payload(args.qa, "project.binary"))
    changed_settings = sorted(key for key in settings_before.keys() | settings_after.keys()
                              if settings_before.get(key) != settings_after.get(key))
    if changed_settings != ["application/run/main_loop_type", "application/run/main_scene"]:
        raise ValueError(f"Unexpected project setting differences: {changed_settings}")
    scene_value = settings_after["application/run/main_scene"]
    if len(scene_value) < 8 or struct.unpack_from("<I", scene_value)[0] != 4:
        raise ValueError("QA external startup scene is not a string Variant")
    scene_size = struct.unpack_from("<I", scene_value, 4)[0]
    scene_path = scene_value[8:8 + scene_size].decode("utf-8")
    if not Path(scene_path).is_absolute() or not scene_path.endswith("/external/qa-main.tscn") or scene_value != variant_string(scene_path) or settings_after["application/run/main_loop_type"] != variant_string("AWPerformanceMeasure"):
        raise ValueError("QA startup values are not the expected external SceneTree class")
    report = {
        "ok": True, "production_pck_sha256": prod["pck_sha256"], "qa_pck_sha256": qa["pck_sha256"],
        "production_resource_count": len(before), "unchanged_resource_count": len(before) - 2,
        "modified_paths": differences, "modified_settings": changed_settings,
        "gameplay_resources_byte_identical": True, "debug_test_paths": qa["debug_test_paths"],
        "measurement_scripts_packed": False,
        "external_startup_scene": scene_path,
        "unchanged_resources": [before[name] for name in sorted(before) if name not in differences],
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "unchanged_resources"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
