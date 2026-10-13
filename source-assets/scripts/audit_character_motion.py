"""Measure evaluated source skin motion, not merely named animation channels."""
from pathlib import Path
import json
import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "source-assets"


def main():
    scene = bpy.context.scene
    if scene.name != "AnotherWorld_CharacterIdentities" or not scene.get("another_world_dedicated_session"):
        raise RuntimeError("Owned character scene required")
    manifest = json.loads((SOURCE / "character-manifest.json").read_text(encoding="utf-8"))
    reports = []
    for asset in manifest["assets"]:
        arm = scene.objects[asset["id"] + "_Rig"]
        mesh = scene.objects[asset["id"] + "_Surface"]
        for track in arm.animation_data.nla_tracks:
            track.mute = True
        clips = {}
        for track in arm.animation_data.nla_tracks:
            strip = track.strips[0]
            # Explicit action playback avoids a just-exported NLA cache hiding
            # poses; the GLB binary sampler audit is a separate downstream gate.
            arm.animation_data.use_nla = False
            arm.animation_data.action = strip.action
            arm.animation_data.action_slot = strip.action_slot
            arm.update_tag()
            frame_count = asset["animations_authored"][track.name]["samples"]
            samples = []
            endpoint_vertices = []
            foot_indices = {}
            for side in ["L", "R"]:
                group = mesh.vertex_groups["Foot_" + side].index
                foot_indices[side] = [v.index for v in mesh.data.vertices if any(g.group == group and g.weight > .99 for g in v.groups)]
            for frame in range(1, frame_count + 1):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                dg = bpy.context.evaluated_depsgraph_get()
                dg.update()
                rig = arm.evaluated_get(dg)
                evaluated = mesh.evaluated_get(dg)
                geometry = evaluated.to_mesh()
                points = [evaluated.matrix_world @ v.co for v in geometry.vertices]
                sample = {"frame": frame, "min_z": min(v.z for v in points),
                          "left_foot": list(rig.pose.bones["Foot_L"].head), "right_foot": list(rig.pose.bones["Foot_R"].head),
                          "left_knee": list(rig.pose.bones["Shin_L"].head), "right_knee": list(rig.pose.bones["Shin_R"].head),
                          "left_wrist": list(rig.pose.bones["Hand_L"].head), "right_wrist": list(rig.pose.bones["Hand_R"].head),
                          "left_sole_z": min(points[i].z for i in foot_indices["L"]), "right_sole_z": min(points[i].z for i in foot_indices["R"])}
                samples.append(sample)
                if frame in [1, frame_count]:
                    endpoint_vertices.append(points)
                evaluated.to_mesh_clear()
            spans = {key: [max(s[key][axis] for s in samples) - min(s[key][axis] for s in samples) for axis in range(3)] for key in ["left_foot", "right_foot", "left_knee", "right_knee", "left_wrist", "right_wrist"]}
            endpoint_error = max((a - b).length for a, b in zip(*endpoint_vertices))
            issues = []
            if min(s["min_z"] for s in samples) < -.001:
                issues.append("Evaluated geometry crosses the source floor")
            if track.name == "Walk":
                if any(spans[key][1] < .60 or spans[key][2] < .12 for key in ["left_foot", "right_foot"]):
                    issues.append("No measured independent swing/plant foot motion")
                if any(spans[key][1] < .20 for key in ["left_knee", "right_knee"]):
                    issues.append("Knee articulation is not visible in measured motion")
                if endpoint_error > .001:
                    issues.append("Locomotion loop endpoints differ")
            if track.name == "SelfHeal" and spans["left_wrist"][2] < .30:
                issues.append("Repair wrist does not reach the chest")
            clips[track.name] = {"samples": samples, "spans_metres": spans, "max_loop_endpoint_vertex_error_m": endpoint_error,
                                "min_floor_z_m": min(s["min_z"] for s in samples), "issues": issues, "ok": not issues}
        arm.animation_data.action = None
        arm.animation_data.use_nla = True
        for track in arm.animation_data.nla_tracks:
            track.mute = True
        for bone in arm.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        scene.frame_set(1)
        arm.update_tag()
        bpy.context.view_layer.update()
        reports.append({"id": asset["id"], "clips": clips, "ok": all(c["ok"] for c in clips.values())})
    report = {"schema_version": 1, "scope": "Blender evaluated skin and bone pose; real engine acceptance separate", "assets": reports, "ok": all(r["ok"] for r in reports)}
    (SOURCE / "evidence/character-source-motion.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "assets": [{"id": r["id"], "clips": {k: {"ok": v["ok"], "spans": v["spans_metres"], "floor_z": v["min_floor_z_m"], "issues": v["issues"]} for k, v in r["clips"].items()}} for r in reports]}, indent=2))
    if not report["ok"]:
        raise RuntimeError("Character source motion gate failed")


if __name__ == "__main__":
    main()
