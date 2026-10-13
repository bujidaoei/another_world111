"""Native PBR review stills; explicitly separate from actual-game acceptance."""
from pathlib import Path
import bpy
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "source-assets"


def studio(scene):
    for obj in list(scene.objects):
        if obj.get("character_review_owner"):
            bpy.data.objects.remove(obj, do_unlink=True)
    world = bpy.data.worlds.new("AW_CharacterReviewWorld")
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    background.inputs[0].default_value = (.027, .039, .042, 1)
    background.inputs[1].default_value = .4
    scene.world = world
    bpy.ops.object.camera_add(location=(-3, 4, 2.65))
    camera = bpy.context.object
    camera.name = "CharacterReviewCamera"
    camera["character_review_owner"] = True
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.9
    camera.rotation_euler = (Vector((0, 0, 1.10)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    for name, location, power, size in [("Key", (-3, 4, 5), 330, 4), ("Fill", (3, 2, 2.5), 100, 3), ("Rim", (1, -3, 4), 350, 3)]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = "CharacterReview" + name
        light["character_review_owner"] = True
        light.data.energy = power
        light.data.size = size
        light.rotation_euler = (Vector((0, 0, 1.1)) - light.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.001))
    ground = bpy.context.object
    ground.name = "CharacterReviewGround"
    ground["character_review_owner"] = True
    material = bpy.data.materials.new("AW_CharacterReviewGround")
    material.use_nodes = True
    node = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node.inputs["Base Color"].default_value = (.026, .033, .036, 1)
    node.inputs["Roughness"].default_value = .85
    ground.data.materials.append(material)
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 600, 600
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    return camera


def main(identity):
    scene = bpy.context.scene
    if scene.name != "AnotherWorld_CharacterIdentities" or not scene.get("another_world_dedicated_session"):
        raise RuntimeError("Owned character scene required")
    path = SOURCE / "previews/characters"
    path.mkdir(parents=True, exist_ok=True)
    camera = studio(scene)
    target = identity + "_robot"
    old_hide = {obj.name: obj.hide_render for obj in scene.objects}
    arm = scene.objects[target + "_Rig"]
    mesh = scene.objects[target + "_Surface"]
    for obj in scene.objects:
        if obj.type == "MESH" and not obj.get("character_review_owner"):
            obj.hide_render = obj != mesh
    arm.animation_data.use_nla = False
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    outputs = []
    try:
        for name, location in [("front", (-3, 4, 2.65)), ("back", (3, -4, 2.65))]:
            arm.animation_data.action = None
            for bone in arm.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
            scene.frame_set(1)
            camera.location = location
            camera.rotation_euler = (Vector((0, 0, 1.10)) - camera.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = str(path / (target + "_" + name + ".png"))
            bpy.ops.render.render(write_still=True)
            outputs.append(scene.render.filepath)
        camera.location = (-3, 4, 2.65)
        camera.rotation_euler = (Vector((0, 0, 1.10)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        poses = [("Walk", frame) for frame in [1, 7, 13, 19]]
        if identity == "healer":
            poses += [("SelfHeal", frame) for frame in [1, 16, 31, 46, 61]]
        for clip, frame in poses:
            strip = next(track.strips[0] for track in arm.animation_data.nla_tracks if track.name == clip)
            arm.animation_data.action = strip.action
            arm.animation_data.action_slot = strip.action_slot
            arm.update_tag()
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            scene.render.filepath = str(path / (target + "_" + clip.lower() + "_%02d.png" % frame))
            bpy.ops.render.render(write_still=True)
            outputs.append(scene.render.filepath)
    finally:
        arm.animation_data.action = None
        arm.animation_data.use_nla = True
        for track in arm.animation_data.nla_tracks:
            track.mute = True
        for bone in arm.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        scene.frame_set(1)
        arm.update_tag()
        bpy.context.view_layer.update()
        for name, value in old_hide.items():
            scene.objects[name].hide_render = value
    print("Native review images:\n" + "\n".join(outputs))
    return outputs


if __name__ == "__main__":
    main("thief")
