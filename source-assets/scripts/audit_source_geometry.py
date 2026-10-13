"""Inspect all original closed surface components without changing their meshes."""
from pathlib import Path
import bpy
import bmesh
import json

ROOT=Path(__file__).resolve().parents[2]
if not bpy.context.scene.get("another_world_dedicated_session"):
    raise RuntimeError("Dedicated project scene required")
manifest=json.loads((ROOT/"source-assets/manifest.json").read_text(encoding="utf-8"))
report=[]
for asset in manifest["assets"]:
    root=bpy.data.objects[asset["id"]]
    surfaces=[]
    for obj in root.children_recursive:
        if obj.type!="MESH":
            continue
        bm=bmesh.new()
        bm.from_mesh(obj.data)
        surfaces.append({"mesh":obj.name,"nonmanifold_edges":sum(not e.is_manifold for e in bm.edges),"loose_vertices":sum(not v.link_edges for v in bm.verts),"uv_layers":len(obj.data.uv_layers),"negative_scale":any(s<0 for s in obj.scale),"remaining_modifiers":len(obj.modifiers)})
        bm.free()
    if any(s["nonmanifold_edges"] or s["loose_vertices"] or not s["uv_layers"] or s["negative_scale"] or s["remaining_modifiers"] for s in surfaces):
        raise RuntimeError(f"Source geometry audit failed for {asset['id']}: {surfaces}")
    report.append({"id":asset["id"],"surface_checks":surfaces,"composite_note":"Closed intersecting hard-surface components are intentionally separate topology islands; visual mesh is not collision geometry."})
out=ROOT/"source-assets/evidence/source-geometry-audit.json"
out.write_text(json.dumps({"date":"2026-10-13","source":"source-assets/blender/asset_family.blend","assets":report},indent=2),encoding="utf-8")
print("source_geometry_audit_pass",len(report))
