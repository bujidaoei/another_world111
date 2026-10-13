"""Validate exported glTF documents and provenance; engine validation is separate."""
from pathlib import Path
import struct
import json
import hashlib
import argparse

ROOT = Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--manifest",type=Path,default=ROOT/"source-assets/manifest.json")
parser.add_argument("--report",type=Path,default=ROOT/"source-assets/evidence/glb-validation.json")
args=parser.parse_args()
manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
reports = []
for entry in manifest["assets"]:
    path = ROOT / entry["runtime_file"]
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError(f"Invalid GLB container: {path}")
    chunk_size, chunk_type = struct.unpack_from("<II",data,12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"No glTF JSON chunk: {path}")
    doc = json.loads(data[20:20+chunk_size])
    if doc["asset"]["version"] != "2.0":
        raise ValueError(f"Invalid asset version: {path}")
    if any("uri" in buf for buf in doc.get("buffers",[])):
        raise ValueError(f"External buffer dependency: {path}")
    if any("uri" in image for image in doc.get("images",[])):
        raise ValueError(f"External image dependency: {path}")
    actual_hash = hashlib.sha256(data).hexdigest()
    if actual_hash != entry["sha256"]:
        raise ValueError(f"Manifest checksum mismatch: {path}")
    clips = [a.get("name", "unnamed") for a in doc.get("animations",[])]
    if "pbr_palette" in manifest:
        if len(doc.get("materials",[]))!=1 or len(doc.get("textures",[]))!=3:
            raise ValueError(f"Expected shared PBR palette in {path}")
        if any(len(mesh["primitives"])!=1 for mesh in doc["meshes"]):
            raise ValueError(f"Palette must produce one primitive per motion mesh: {path}")
        mat=doc["materials"][0]
        if not all(key in mat.get("pbrMetallicRoughness",{}) for key in ["baseColorTexture","metallicRoughnessTexture"]) or "emissiveTexture" not in mat:
            raise ValueError(f"Missing PBR palette map in {path}")
        bin_start=20+chunk_size+8
        for embedded in doc["images"]:
            view=doc["bufferViews"][embedded["bufferView"]]
            start=bin_start+view.get("byteOffset",0)
            png=data[start:start+view["byteLength"]]
            if png[:8]!=b"\x89PNG\r\n\x1a\n" or struct.unpack_from(">II",png,16)!=(48,48):
                raise ValueError(f"Unexpected atlas format or dimensions in {path}")
    for expected in entry["clips_expected"]:
        if expected not in clips:
            raise ValueError(f"Expected clip {expected} missing in {path}: {clips}")
    report = {"id":entry["id"],"container":"glTF 2.0 GLB","sha256":actual_hash,"bytes":len(data),"nodes":len(doc.get("nodes",[])),"meshes":len(doc.get("meshes",[])),"primitives":sum(len(m["primitives"]) for m in doc.get("meshes",[])),"materials":len(doc.get("materials",[])),"textures":len(doc.get("textures",[])),"palette_map_size":[48,48] if "pbr_palette" in manifest else None,"animations":clips,"animation_channels":{a.get("name","unnamed"):len(a["channels"]) for a in doc.get("animations",[])},"external_dependencies":0,"geometry_validation":entry["geometry"],"in_engine_acceptance":"pending"}
    reports.append(report)
out = args.report
out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps({"schema":1,"date":"2026-10-13","assets":reports},ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"validated":len(reports),"clips":{r["id"]:r["animations"] for r in reports},"output":str(out)},ensure_ascii=False,indent=2))
