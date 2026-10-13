"""Original skinned mechanical identities; execute in the owned Blender MCP.

This module has no import-time mutations. main(['thief']) and main(['healer'])
produce independent assets without touching the existing 23 model files.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import bpy
import bmesh
from mathutils import Vector, Matrix, Quaternion, Euler

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "source-assets"
SCENE_NAME = "AnotherWorld_CharacterIdentities"
FPS = 60
CLIP_FRAMES = {"Idle": 121, "Walk": 25, "SelfHeal": 61}
RUNTIME_SCALE = .76
STRIDE_HALF = .34


def preserved_models():
    records = []
    for manifest_name in ["manifest.json", "district-manifest.json"]:
        for asset in json.loads((SOURCE / manifest_name).read_text(encoding="utf-8"))["assets"]:
            path = ROOT / asset["runtime_file"]
            records.append({"path": asset["runtime_file"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    return records


class CharacterFactory:
    def __init__(self):
        if not bpy.context.scene.get("another_world_dedicated_session"):
            raise RuntimeError("A project-owned Blender MCP scene is required")
        scene = bpy.data.scenes.get(SCENE_NAME)
        if scene is None:
            scene = bpy.data.scenes.new(SCENE_NAME)
            scene["another_world_dedicated_session"] = True
        elif not scene.get("another_world_dedicated_session"):
            raise RuntimeError("Refusing to reuse a non-owned character scene")
        bpy.context.window.scene = scene
        self.scene = scene
        scene.unit_settings.system = "METRIC"
        scene.unit_settings.scale_length = 1
        scene.render.fps = FPS
        scene.frame_start, scene.frame_end = 1, 121
        self.roles = json.loads((SOURCE / "art-palette.json").read_text(encoding="utf-8"))["roles"]
        self.materials = {}
        for name, values in self.roles.items():
            mat = bpy.data.materials.get("AW_" + name)
            if mat is None:
                mat = bpy.data.materials.new("AW_" + name)
                mat.use_nodes = True
                node = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
                node.inputs["Base Color"].default_value = values["base_color_linear"]
                node.inputs["Metallic"].default_value = values["metallic"]
                node.inputs["Roughness"].default_value = values["roughness"]
                node.inputs["Emission Color"].default_value = values["base_color_linear"]
                node.inputs["Emission Strength"].default_value = values["emission"]
            self.materials[name] = mat
        self.atlas = bpy.data.materials.get("AW_PalettePBR")
        if self.atlas is None:
            with bpy.data.libraries.load(str(SOURCE / "blender/asset_family.blend"), link=False) as (available, requested):
                if "AW_PalettePBR" not in available.materials:
                    raise RuntimeError("Original PBR palette not available")
                requested.materials = ["AW_PalettePBR"]
            self.atlas = requested.materials[0]
        self.parts = []

    def new_character(self, identity):
        self.identity = identity
        self.asset_id = identity + "_robot"
        existing = self.scene.objects.get(self.asset_id)
        if existing:
            if existing.get("character_source_owner") != "character_factory":
                raise RuntimeError("Character object name belongs to another source")
            owned = [existing] + list(existing.children_recursive)
            if any(len(obj.users_scene) != 1 for obj in owned):
                raise RuntimeError("Character objects shared outside this scene")
            for obj in reversed(owned):
                bpy.data.objects.remove(obj, do_unlink=True)
        self.root = bpy.data.objects.new(self.asset_id, None)
        self.scene.collection.objects.link(self.root)
        self.root["character_source_owner"] = "character_factory"
        self.root["identity"] = identity
        self.root["front_axis"] = "+Y Blender / -Z glTF"
        self.root["original_geometry"] = True
        self.root["runtime_scale"] = RUNTIME_SCALE
        self.parts = []
        self.create_skeleton()

    def create_skeleton(self):
        data = bpy.data.armatures.new(self.asset_id + "_Skeleton")
        arm = bpy.data.objects.new(self.asset_id + "_Rig", data)
        self.scene.collection.objects.link(arm)
        arm.parent = self.root
        arm.show_in_front = True
        bpy.ops.object.select_all(action="DESELECT")
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        entries = [("Pelvis", (0, 0, .90), (0, 0, 1.10), None),
                   ("Spine", (0, 0, 1.10), (0, 0, 1.88), "Pelvis"),
                   ("Head", (0, 0, 1.94), (0, 0, 2.23), "Spine")]
        for side, sign in [("L", -1), ("R", 1)]:
            entries += [("Clavicle_" + side, (sign * .18, 0, 1.79), (sign * .46, 0, 1.79), "Spine"),
                        ("UpperArm_" + side, (sign * .46, 0, 1.79), (sign * .46, .12, 1.42), "Clavicle_" + side),
                        ("Forearm_" + side, (sign * .46, .12, 1.42), (sign * .46, .28, 1.15), "UpperArm_" + side),
                        ("Hand_" + side, (sign * .46, .28, 1.15), (sign * .46, .42, 1.15), "Forearm_" + side),
                        ("Thigh_" + side, (sign * .24, 0, .99), (sign * .24, .055, .56), "Pelvis"),
                        ("Shin_" + side, (sign * .24, .055, .56), (sign * .24, .02, .16), "Thigh_" + side),
                        ("Foot_" + side, (sign * .24, .02, .16), (sign * .24, .30, .16), "Shin_" + side)]
        for name, head, tail, parent in entries:
            bone = data.edit_bones.new(name)
            bone.head, bone.tail = head, tail
            bone.use_deform = True
            if parent:
                bone.parent = data.edit_bones[parent]
            bone.use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
        self.arm = arm
        self.bones = [entry[0] for entry in entries]
        for bone in arm.pose.bones:
            bone.rotation_mode = "QUATERNION"

    def finish_part(self, obj, name, material, bone, bevel=0):
        obj.name = self.asset_id + "_" + name
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bevel > 0:
            modifier = obj.modifiers.new("OriginalEdge", "BEVEL")
            modifier.width, modifier.segments = bevel, 1
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.data.materials.append(self.materials[material])
        # World-space source vertices at a normalized object transform.
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        obj.parent = self.root
        obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        self.parts.append(obj)
        return obj

    def box(self, name, loc, size, material="graphite", bone="Spine", bevel=.018, rotation=(0, 0, 0)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rotation)
        obj = bpy.context.object
        obj.dimensions = size
        return self.finish_part(obj, name, material, bone, min(bevel, min(size) * .14))

    def cylinder(self, name, loc, radius, depth, material="steel", bone="Spine", rotation=(0, 0, 0), sides=12, bevel=.008):
        bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=depth, location=loc, rotation=rotation)
        return self.finish_part(bpy.context.object, name, material, bone, min(bevel, depth * .14, radius * .14))

    def segment(self, name, a, b, width, depth, material, bone):
        a, b = Vector(a), Vector(b)
        return self.box(name, (a + b) * .5, (width, depth, (b - a).length * .82), material, bone,
                        rotation=(b - a).to_track_quat("Z", "Y").to_euler())

    def pipe(self, name, a, b, radius, material="steel", bone="Spine", sides=8):
        a, b = Vector(a), Vector(b)
        return self.cylinder(name, (a + b) * .5, radius, (b - a).length, material, bone,
                             rotation=(b - a).to_track_quat("Z", "Y").to_euler(), sides=sides, bevel=0)

    def wedge_head(self):
        # The x-extruded profile has an angled front brow, not a recolored box.
        yz = [(-.22, 1.98), (.24, 1.99), (.26, 2.13), (.10, 2.24), (-.22, 2.28)]
        count = len(yz)
        vertices = [(-.28, y, z) for y, z in yz] + [(.28, y, z) for y, z in yz]
        faces = [tuple(range(count - 1, -1, -1)), tuple(range(count, count * 2))]
        faces += [(i, (i + 1) % count, (i + 1) % count + count, i + count) for i in range(count)]
        mesh = bpy.data.meshes.new(self.asset_id + "_WedgeHead")
        mesh.from_pydata(vertices, [], faces)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(self.asset_id + "_WedgeHead", mesh)
        self.scene.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        self.finish_part(obj, "WedgeHelmet", "ivory", "Head", .022)

    def common_body(self):
        healer = self.identity == "healer"
        shell = "ivory" if healer else "orange"
        self.box("PelvisShell", (0, 0, 1.00), (.55, .34, .23), "graphite", "Pelvis")
        self.box("TorsoShell", (0, -.005, 1.51), (.73 if healer else .63, .42, .75), shell, "Spine", .042)
        self.box("FrontHarness", (0, .225, 1.52), (.50 if healer else .35, .072, .55), "graphite")
        for x in [-.17, .17]:
            self.box("ChestRail", (x, .281, 1.53), (.035, .023, .50), "steel", bevel=0)
        self.cylinder("ChestCoil", (0, .29, 1.55), .13, .060, "steel", rotation=(math.pi * .5, 0, 0))
        self.cylinder("ChestCore", (0, .326, 1.55), .070, .020, "cyan", rotation=(math.pi * .5, 0, 0), bevel=0)
        self.cylinder("Neck", (0, 0, 1.945), .11, .15, "steel", "Head")
        if healer:
            self.box("RoundedHelmet", (0, 0, 2.105), (.54, .41, .32), "ivory", "Head", .042)
            self.box("ForeheadBar", (0, .23, 2.224), (.41, .075, .06), "graphite", "Head", .006)
        else:
            self.wedge_head()
            self.box("BrowBar", (0, .197, 2.178), (.48, .085, .058), "graphite", "Head", .009, rotation=(-.15, 0, 0))
        self.box("VisorRecess", (0, .246, 2.09), (.44, .052, .16), "graphite", "Head")
        self.box("Visor", (0, .277, 2.10), (.31, .018, .049), "cyan", "Head", .004)
        for side, sign in [("L", -1), ("R", 1)]:
            thigh, shin, foot = "Thigh_" + side, "Shin_" + side, "Foot_" + side
            self.cylinder("HipPin" + side, (sign * .24, 0, .98), .10, .24, "steel", thigh, (0, math.pi * .5, 0))
            self.segment("Thigh" + side, (sign * .24, .007, .95), (sign * .24, .05, .60), .215, .235, "graphite", thigh)
            self.cylinder("Knee" + side, (sign * .24, .055, .56), .089, .23, "steel", shin, (0, math.pi * .5, 0))
            self.segment("Shin" + side, (sign * .24, .05, .53), (sign * .24, .02, .20), .24, .255, shell, shin)
            self.box("KneePad" + side, (sign * .24, .193, .55), (.18, .052, .135), "ivory" if not healer else "orange", shin, .008)
            self.cylinder("Ankle" + side, (sign * .24, .02, .19), .068, .20, "steel", foot, (0, math.pi * .5, 0))
            self.box("Sole" + side, (sign * .24, .093, .067), (.30, .43, .134), "graphite", foot, .011)
            self.box("Toe" + side, (sign * .24, .252, .095), (.269, .135, .12), "steel", foot, .012)
            self.box("FootMarker" + side, (sign * .24, .218, .160), (.14, .060, .015), "ivory", foot, 0)
            upper, lower, hand = "UpperArm_" + side, "Forearm_" + side, "Hand_" + side
            self.cylinder("ShoulderPin" + side, (sign * .44, 0, 1.78), .105, .205, "steel", "Clavicle_" + side, (0, math.pi * .5, 0))
            self.box("ShoulderShell" + side, (sign * .43, -.01, 1.80), (.24, .31, .23), shell, "Clavicle_" + side, .032)
            self.segment("UpperArm" + side, (sign * .46, .02, 1.73), (sign * .46, .108, 1.47), .19, .20, "graphite", upper)
            self.cylinder("Elbow" + side, (sign * .46, .12, 1.42), .08, .20, "steel", lower, (0, math.pi * .5, 0))
            self.segment("Forearm" + side, (sign * .46, .135, 1.39), (sign * .46, .26, 1.19), .21, .21, shell, lower)
            self.box("Palm" + side, (sign * .46, .33, 1.15), (.15, .18, .15), "graphite", hand, .012)
            self.box("Grip" + side, (sign * .46, .407, 1.155), (.15, .065, .13), "steel", hand, .01)

    def identity_details(self):
        if self.identity == "thief":
            for i in range(2):
                self.box("SortingBox" + str(i), (-.22, -.298, 1.39 + i * .26), (.32, .23, .205), "graphite", bevel=.019)
                self.box("BoxPanel" + str(i), (-.22, -.43, 1.39 + i * .26), (.255, .037, .128), "orange", bevel=.008)
                self.box("BoxLatch" + str(i), (-.13, -.454, 1.39 + i * .26), (.065, .019, .07), "steel", bevel=0)
            self.box("WaistSorter", (.29, -.13, 1.12), (.19, .27, .28), "orange", "Pelvis")
            for x in [-.06, .06]:
                self.box("ChestToolRail", (x, .27, 1.30), (.027, .026, .19), "ivory", bevel=0)
            self.pipe("FoldedTool", (-.31, -.30, 1.15), (-.31, -.33, 1.61), .038, "steel")
            self.box("WristSorter", (-.46, .16, 1.29), (.245, .205, .17), "graphite", "Forearm_L")
            self.box("OriginalDoubleBar", (-.46, .26, 1.29), (.14, .018, .020), "amber", "Forearm_L", 0)
        else:
            self.cylinder("MaintenanceDisc", (0, -.323, 1.53), .283, .235, "graphite", rotation=(math.pi * .5, 0, 0), sides=16)
            self.cylinder("DiscShell", (0, -.449, 1.53), .229, .035, "ivory", rotation=(math.pi * .5, 0, 0), sides=16)
            self.cylinder("DiscInset", (0, -.475, 1.53), .111, .018, "steel", rotation=(math.pi * .5, 0, 0), bevel=0)
            for sign in [-1, 1]:
                points = [(sign * .28, -.29, 1.24), (sign * .38, -.27, 1.32), (sign * .38, -.25, 1.70), (sign * .30, -.23, 1.82)]
                for i in range(len(points) - 1):
                    self.pipe("ClosedReturnPipe", points[i], points[i + 1], .034, "steel")
                self.box("ShoulderBrace", (sign * .40, -.13, 1.89), (.115, .145, .36), "ivory", bevel=.017)
            self.box("BraceLink", (0, -.145, 2.036), (.77, .14, .10), "ivory", bevel=.017)
            self.box("BracedInset", (0, -.224, 2.03), (.46, .031, .060), "graphite", bevel=.006)
            self.box("MaintenanceWrist", (-.46, .16, 1.28), (.255, .25, .195), "ivory", "Forearm_L", .022)
            self.cylinder("RepairEmitter", (-.46, .299, 1.28), .072, .031, "cyan", "Forearm_L", (math.pi * .5, 0, 0), bevel=0)
            for x in [-.055, .055]:
                self.box("OpenBracket", (x, .275, 1.28), (.025, .022, .10), "orange", bevel=0)

    def combine_and_skin(self):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in self.parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = self.parts[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name, obj.data.name = self.asset_id + "_Surface", self.asset_id + "_SourceMesh"
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=.02)
        bpy.ops.object.mode_set(mode="OBJECT")
        mesh = obj.data
        mesh.uv_layers.active.name = "AW_SourceUV"
        uv = mesh.uv_layers.new(name="AW_PaletteUV")
        roles = list(self.roles)
        for poly in mesh.polygons:
            role = mesh.materials[poly.material_index].name.removeprefix("AW_").split(".")[0]
            slot = roles.index(role)
            for loop in poly.loop_indices:
                uv.data[loop].uv = ((slot % 3 + .5) / 3, (slot // 3 + .5) / 3)
            poly.material_index = 0
        mesh.materials.clear()
        mesh.materials.append(self.atlas)
        mesh.uv_layers.active = uv
        uv.active_render = True
        modifier = obj.modifiers.new("AuthoredSkeleton", "ARMATURE")
        modifier.object = self.arm
        modifier.use_vertex_groups = True
        obj.parent = self.arm
        self.mesh = obj
        bpy.context.view_layer.update()

    def pose_segment(self, name, head, tail):
        rest = self.arm.data.bones[name]
        delta = (rest.tail_local - rest.head_local).rotation_difference(Vector(tail) - Vector(head))
        matrix = delta.to_matrix().to_4x4() @ rest.matrix_local
        matrix.translation = Vector(head)
        self.arm.pose.bones[name].matrix = matrix
        bpy.context.view_layer.update()

    @staticmethod
    def solve_limb(start, end, upper, lower, preferred):
        start, end = Vector(start), Vector(end)
        axis = end - start
        distance = axis.length
        if not abs(upper - lower) + 1e-5 < distance < upper + lower - 1e-5:
            raise ValueError("Unreachable authored limb target")
        axis /= distance
        along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
        height = math.sqrt(max(0, upper * upper - along * along))
        bend = Vector(preferred) - axis * Vector(preferred).dot(axis)
        bend.normalize()
        return start + axis * along + bend * height

    def author_pose(self, clip, t):
        for bone in self.arm.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        phase = t * math.tau
        walk = clip == "Walk"
        heal = clip == "SelfHeal"
        heal_amount = math.sin(math.pi * t) ** 2 if heal else 0
        offset = Vector((.006 * math.sin(phase) if walk else 0, 0, -.09 + .003 * math.sin(phase * 2) if walk else .003 * math.sin(phase)))
        pelvis = self.arm.pose.bones["Pelvis"]
        pelvis.matrix = Matrix.Translation(offset) @ self.arm.data.bones["Pelvis"].matrix_local
        bpy.context.view_layer.update()
        spine = self.arm.data.bones["Spine"]
        spine_rotation = Euler((-.01 * math.sin(phase) if walk else -.035 * heal_amount, .012 * math.sin(phase) if walk else 0, .011 * math.sin(phase) if walk else 0)).to_matrix().to_4x4()
        spine_matrix = spine_rotation @ spine.matrix_local
        spine_matrix.translation = spine.head_local + offset
        self.arm.pose.bones["Spine"].matrix = spine_matrix
        bpy.context.view_layer.update()
        delta_spine = spine_matrix @ spine.matrix_local.inverted()
        head = self.arm.data.bones["Head"]
        head_matrix = delta_spine @ head.matrix_local @ Euler((-.15 * heal_amount, 0, .045 * math.sin(phase) if not walk and not heal else .012 * math.sin(phase))).to_matrix().to_4x4()
        self.arm.pose.bones["Head"].matrix = head_matrix
        bpy.context.view_layer.update()
        for side, sign in [("L", -1), ("R", 1)]:
            clavicle = self.arm.data.bones["Clavicle_" + side]
            self.arm.pose.bones["Clavicle_" + side].matrix = delta_spine @ clavicle.matrix_local
            bpy.context.view_layer.update()
            shoulder = delta_spine @ self.arm.data.bones["UpperArm_" + side].head_local
            wrist = self.arm.data.bones["Hand_" + side].head_local.copy()
            if side == "L":
                wrist += Vector((0, .040 * math.sin(phase) if walk else 0, .015 * math.cos(phase) if walk else .003 * math.sin(phase)))
                if heal:
                    wrist = wrist.lerp(Vector((-.06, .34, 1.54)), heal_amount)
            upper = self.arm.data.bones["UpperArm_" + side].length
            lower = self.arm.data.bones["Forearm_" + side].length
            elbow = self.solve_limb(shoulder, wrist, upper, lower, (sign * .5, .15, -.3))
            self.pose_segment("UpperArm_" + side, shoulder, elbow)
            self.pose_segment("Forearm_" + side, elbow, wrist)
            palm_direction = Vector((0, .14, 0)) if side == "R" or not heal else Vector((.01 * heal_amount, .14 * (1 - heal_amount), .14 * heal_amount)).normalized() * .14
            self.pose_segment("Hand_" + side, wrist, wrist + palm_direction)
            hip = self.arm.data.bones["Thigh_" + side].head_local + offset
            ankle = self.arm.data.bones["Foot_" + side].head_local.copy()
            if walk:
                leg_phase = (t + (.5 if side == "R" else 0)) % 1.0
                if leg_phase <= .5:
                    ankle.y += STRIDE_HALF * (1 - leg_phase * 4)
                else:
                    swing = (leg_phase - .5) * 2
                    eased = swing * swing * (3 - 2 * swing)
                    ankle.y += STRIDE_HALF * (-1 + 2 * eased)
                    ankle.z += .16 * math.sin(math.pi * swing)
            else:
                # Feet stay fixed while torso and arms breathe above them.
                ankle.z = .16
            knee = self.solve_limb(hip, ankle, self.arm.data.bones["Thigh_" + side].length, self.arm.data.bones["Shin_" + side].length, (0, 1, 0))
            self.pose_segment("Thigh_" + side, hip, knee)
            self.pose_segment("Shin_" + side, knee, ankle)
            self.pose_segment("Foot_" + side, ankle, ankle + Vector((0, .28, 0)))

    def animations(self):
        self.arm.animation_data_create()
        records = {}
        clips = ["Idle", "Walk"] + (["SelfHeal"] if self.identity == "healer" else [])
        for clip in clips:
            self.arm.animation_data.action = None
            for track in self.arm.animation_data.nla_tracks:
                track.mute = True
            frames = CLIP_FRAMES[clip]
            foot_samples = []
            for frame in range(1, frames + 1):
                active_action = self.arm.animation_data.action
                self.arm.animation_data.action = None
                self.scene.frame_set(frame)
                self.author_pose(clip, (frame - 1) / (frames - 1))
                local_poses = {bone.name: bone.matrix_basis.copy() for bone in self.arm.pose.bones}
                foot_samples.append({"frame": frame, "left": list(self.arm.pose.bones["Foot_L"].head), "right": list(self.arm.pose.bones["Foot_R"].head)})
                self.arm.animation_data.action = active_action
                for bone in self.arm.pose.bones:
                    bone.matrix_basis = local_poses[bone.name]
                    bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
                    bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=bone.name)
                    bone.keyframe_insert(data_path="scale", frame=frame, group=bone.name)
            action = self.arm.animation_data.action
            action.name = self.asset_id + "_" + clip
            action["source_owner"] = "character_factory"
            # Blender5 layered Action channels, rather than deprecated fcurves.
            for layer in action.layers:
                for strip in layer.strips:
                    for bag in strip.channelbags:
                        for curve in bag.fcurves:
                            for key in curve.keyframe_points:
                                key.interpolation = "LINEAR"
            track = self.arm.animation_data.nla_tracks.new()
            track.name = clip
            strip = track.strips.new(clip, 1, action)
            strip.extrapolation = "NOTHING"
            track.mute = True
            self.arm.animation_data.action = None
            records[clip] = {"duration_s": (frames - 1) / FPS, "samples": frames, "loop_intent": clip != "SelfHeal", "foot_samples_source": foot_samples}
        self.clip_records = records
        self.scene.frame_set(1)
        for bone in self.arm.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()

    def audit_and_export(self):
        mesh = self.mesh.data
        mesh.calc_loop_triangles()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        geometry = {"triangles": len(mesh.loop_triangles), "vertices": len(mesh.vertices), "meshes": 1, "materials": 1,
                    "nonmanifold_edges": sum(not edge.is_manifold for edge in bm.edges),
                    "loose_vertices": sum(not v.link_edges for v in bm.verts),
                    "degenerate_triangles": sum(tri.area < 1e-10 for tri in mesh.loop_triangles),
                    "nonfinite_vertices": sum(not all(math.isfinite(c) for c in vertex.co) for vertex in mesh.vertices)}
        bm.free()
        if any(geometry[key] for key in ["nonmanifold_edges", "loose_vertices", "degenerate_triangles", "nonfinite_vertices"]):
            raise RuntimeError("Character geometry gate failed: " + str(geometry))
        unweighted = sum(not vertex.groups or abs(sum(g.weight for g in vertex.groups) - 1) > 1e-6 for vertex in mesh.vertices)
        if unweighted:
            raise RuntimeError("Invalid normalized bone weights")
        points = [self.mesh.matrix_world @ vertex.co - self.root.matrix_world.translation for vertex in mesh.vertices]
        low = [min(p[i] for p in points) for i in range(3)]
        high = [max(p[i] for p in points) for i in range(3)]
        original = self.mesh.data
        runtime = original.copy()
        runtime.name = self.asset_id + "_RuntimeMesh"
        runtime.uv_layers.remove(runtime.uv_layers["AW_SourceUV"])
        outfile = ROOT / "game/assets/models" / (self.asset_id + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        self.root.select_set(True)
        self.arm.select_set(True)
        self.mesh.select_set(True)
        bpy.context.view_layer.objects.active = self.arm
        try:
            self.mesh.data = runtime
            bpy.ops.export_scene.gltf(filepath=str(outfile), export_format="GLB", use_selection=True, export_extras=True,
                                     export_animations=True, export_animation_mode="NLA_TRACKS", export_apply=False,
                                     export_skins=True, export_rest_position_armature=True, export_force_sampling=True,
                                     export_anim_slide_to_zero=True, export_frame_range=False, export_tangents=False)
        finally:
            self.mesh.data = original
            bpy.data.meshes.remove(runtime)
        for track in self.arm.animation_data.nla_tracks:
            track.mute = True
        self.arm.animation_data.action = None
        for bone in self.arm.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        return {"id": self.asset_id, "identity": self.identity, "runtime_file": str(outfile.relative_to(ROOT)).replace("\\", "/"),
                "source": "source-assets/blender/characters-v1.blend", "source_code": "source-assets/scripts/character_factory.py",
                "status": "authored_and_exported_engine_review_pending", "sha256": hashlib.sha256(outfile.read_bytes()).hexdigest(),
                "bytes": outfile.stat().st_size, "geometry": geometry,
                "bounds_godot_m": {"min": [low[0], low[2], -high[1]], "max": [high[0], high[2], -low[1]]},
                "rig": {"bones": len(self.arm.data.bones), "names": self.bones, "unweighted_vertices": unweighted, "weights": "rigid single-bone mechanical islands, normalized"},
                "clips_expected": list(self.clip_records), "animations_authored": self.clip_records,
                "runtime_scale": RUNTIME_SCALE, "walk_nominal_speed_m_s": 4 * STRIDE_HALF * RUNTIME_SCALE / ((CLIP_FRAMES["Walk"] - 1) / FPS),
                "weapon_mount_godot_source_m": [.42, 1.15, -.28],
                "collision": {"type": "existing gameplay capsule", "radius": .38, "height": 1.7, "center_y": .85},
                "license": "original project-authored geometry, materials and skeletal animation; no third-party source assets"}

    def save_source(self, entries):
        for obj in self.scene.objects:
            if obj.type == "ARMATURE" and obj.parent and obj.parent.get("character_source_owner") == "character_factory":
                obj.animation_data.action = None
                obj.animation_data.use_nla = True
                for track in obj.animation_data.nla_tracks:
                    track.mute = True
                for bone in obj.pose.bones:
                    bone.matrix_basis = Matrix.Identity(4)
                obj.update_tag()
        self.scene.frame_set(1)
        bpy.context.view_layer.update()
        for node in self.atlas.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image:
                node.image.pack()
        self.scene["source_code"] = "source-assets/scripts/character_factory.py"
        path = SOURCE / "blender/characters-v1.blend"
        # Save only this self-contained owned scene; legacy production scenes
        # stay in memory and their original source files are never overwritten.
        bpy.data.libraries.write(str(path), {self.scene}, path_remap="RELATIVE_ALL", fake_user=True, compress=True)
        manifest_path = SOURCE / "character-manifest.json"
        assets = json.loads(manifest_path.read_text(encoding="utf-8"))["assets"] if manifest_path.exists() else []
        replacements = {entry["id"]: entry for entry in entries}
        assets = [entry for entry in assets if entry["id"] not in replacements] + entries
        manifest = {"schema_version": 1, "feature": "003-character-builds", "task": "TASK-222", "engine": "Godot4.7.2",
                    "dcc": bpy.app.version_string, "source_file": str(path.relative_to(ROOT)).replace("\\", "/"),
                    "units": "metres; runtime Y-up, forward -Z", "pbr_palette": {"atlas_size": [48, 48], "maps": 3, "materials": 1},
                    "approval": "source technical gates and exported data only; actual game, motion, performance, Android and final art pending",
                    "assets": assets}
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def main(identities=None):
    identities = ["thief", "healer"] if identities is None else identities
    if any(identity not in ["thief", "healer"] for identity in identities):
        raise ValueError("Unknown character identity")
    preserved = preserved_models()
    factory = CharacterFactory()
    entries = []
    for identity in identities:
        factory.new_character(identity)
        factory.common_body()
        factory.identity_details()
        factory.combine_and_skin()
        factory.animations()
        entries.append(factory.audit_and_export())
    factory.save_source(entries)
    if preserved != preserved_models():
        raise RuntimeError("Existing model family was changed")
    (SOURCE / "evidence/character-original-family-preserved.json").write_text(json.dumps({"ok": True, "models": preserved}, indent=2), encoding="utf-8")
    print(json.dumps({"exported": [{"id": e["id"], "triangles": e["geometry"]["triangles"], "bounds": e["bounds_godot_m"], "clips": e["clips_expected"]} for e in entries], "source": "source-assets/blender/characters-v1.blend", "preserved_models": len(preserved)}, indent=2))
    return entries


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", nargs="+", choices=["thief", "healer"], default=["thief", "healer"])
    main(parser.parse_args().identity)
