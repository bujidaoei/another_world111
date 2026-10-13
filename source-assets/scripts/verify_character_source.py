"""Read the isolated saved .blend in a clean background Blender process."""
from pathlib import Path
import json
import bpy

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / "source-assets/blender/characters-v1.blend"
with bpy.data.libraries.load(str(path), link=False) as (source, requested):
    names = {"scenes": list(source.scenes), "objects": list(source.objects), "actions": list(source.actions)}
    requested.scenes = ["AnotherWorld_CharacterIdentities"]
scene = requested.scenes[0]
if scene is None or names["scenes"] != ["AnotherWorld_CharacterIdentities"]:
    raise RuntimeError("Character source is not an isolated scene project")
assets = []
for identity in ["thief", "healer"]:
    actor = scene.objects[identity + "_robot"]
    arm = scene.objects[identity + "_robot_Rig"]
    mesh = scene.objects[identity + "_robot_Surface"]
    images = [node.image for node in mesh.data.materials[0].node_tree.nodes if node.type == "TEX_IMAGE"]
    record = {"id": actor.name, "owned": actor.get("character_source_owner") == "character_factory", "bones": len(arm.data.bones),
              "mesh_parent_is_armature": mesh.parent == arm, "uv_layers": [uv.name for uv in mesh.data.uv_layers],
              "clips": [track.name for track in arm.animation_data.nla_tracks], "packed_images": len(images),
              "all_images_packed": all(image.packed_file is not None for image in images)}
    if not record["owned"] or record["bones"] != 17 or not record["mesh_parent_is_armature"] or not record["all_images_packed"] or record["packed_images"] != 3:
        raise RuntimeError("Source rig, ownership or embedded-map gate failed")
    assets.append(record)
report = {"schema_version": 1, "path": str(path), "bytes": path.stat().st_size, "isolated_scene": names["scenes"], "assets": assets, "ok": True}
(ROOT / "source-assets/evidence/character-source-file-validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
