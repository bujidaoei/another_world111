"""Audit an actual development APK ZIP and its direct Godot assets."""
from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path, PurePosixPath


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    files, seen, assets = [], set(), set()
    markers = (b"gdunit4", b"godot_ai", b"_mcp_game_helper", b"res://tests/")
    with zipfile.ZipFile(args.apk) as archive:
        if archive.testzip() is not None:
            raise ValueError("APK ZIP CRC verification failed")
        for info in archive.infolist():
            name = info.filename
            pure = PurePosixPath(name)
            if pure.is_absolute() or ".." in pure.parts or "\\" in name or name in seen:
                raise ValueError("Unsafe or duplicated APK ZIP entry")
            seen.add(name)
            if info.is_dir():
                continue
            raw = archive.read(info)
            if name.startswith("assets/"):
                resource = name.removeprefix("assets/")
                assets.add(resource)
                lower = resource.lower()
                if lower.startswith(("addons/godot_ai/", "addons/gdunit4/", "tests/", "reports/")) or "game_helper" in lower or lower.endswith((".keystore", ".jks")):
                    raise ValueError(f"Developer helper, tests or signing key packed: {resource}")
                if resource == "project.binary" or lower.endswith((".gd", ".gdc", ".cfg", ".remap")):
                    if any(marker in raw.lower() for marker in markers):
                        raise ValueError(f"Debug helper/test reference packed: {resource}")
            files.append({"path": name, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
    if not {"config/rules.json", "config/presentation.json", "project.binary"}.issubset(assets) or not any(name.startswith("presentation/main.tscn") for name in assets):
        raise ValueError("APK lacks audited direct Godot assets/config/main scene")
    native = sorted(name for name in seen if name.startswith("lib/") and name.endswith(".so"))
    if not native or any(not name.startswith("lib/arm64-v8a/") for name in native):
        raise ValueError("Development APK must contain only actual arm64 native libraries")
    report = {"ok": True, "apk_sha256": hashlib.sha256(args.apk.read_bytes()).hexdigest(), "apk_bytes": args.apk.stat().st_size,
              "zip_files": len(files), "godot_asset_files": len(assets), "all_zip_crc_valid": True, "native_libraries": native,
              "debug_helper_test_content": [], "signing_keys_packed": False, "files": files}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "files"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
