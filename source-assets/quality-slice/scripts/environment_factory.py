"""Author and bake the original repair-district visual slice in the owned Blender scene.

This module never runs production on import. Call an explicit stage after Spec Kit approval.
Sources stay editable; runtime objects, UVs, maps and evidence are derived and audited.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import time

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "source-assets" / "quality-slice"
RUNTIME = ROOT / "game" / "assets" / "quality"
OWNER = "another_world_quality_environment_v1"
SCENE_NAME = "AnotherWorld_AssetProduction"
COLLECTIONS = {"source": "AWQ_Source", "runtime": "AWQ_Runtime", "presentation": "AWQ_Presentation"}
IDS = ["repair_paving_a", "repair_paving_b", "repair_paving_c", "repair_paving_d", "rain_reclaim_facade"]


def scope(path: Path, base: Path) -> Path:
    resolved = path.resolve()
    if not resolved.is_relative_to(base.resolve()):
        raise RuntimeError(f"Output escaped its owned directory: {resolved}")
    return resolved


def owned_scene() -> bpy.types.Scene:
    scene = bpy.context.scene
    if scene.name != SCENE_NAME or scene.get("another_world_dedicated_session") is not True:
        raise RuntimeError("The dedicated production scene marker is required; no other scene is modified.")
    if bpy.context.mode != "OBJECT":
        raise RuntimeError("Production requires Object mode; preserve the user's edit operation.")
    return scene


def collection(role: str) -> bpy.types.Collection:
    scene = owned_scene()
    name = COLLECTIONS[role]
    result = bpy.data.collections.get(name)
    if result is not None and result.get("aw_owner") != OWNER:
        raise RuntimeError(f"Refusing an unowned collection: {name}")
    if result is None:
        result = bpy.data.collections.new(name)
        result["aw_owner"] = OWNER
        scene.collection.children.link(result)
    return result


def select(objects: list[bpy.types.Object], active: bpy.types.Object | None = None) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active or objects[0]


def tagged(obj: bpy.types.Object, asset_id: str, role: str) -> bpy.types.Object:
    obj["aw_owner"] = OWNER
    obj["aw_asset_id"] = asset_id
    obj["aw_role"] = role
    for item in list(obj.users_collection):
        item.objects.unlink(obj)
    collection(role).objects.link(obj)
    return obj


def assert_new(asset_id: str) -> None:
    if any(obj.get("aw_owner") == OWNER and obj.get("aw_asset_id") == asset_id for obj in bpy.data.objects):
        raise RuntimeError(f"Asset already exists; inspect and explicitly retire its owned generation first: {asset_id}")


def source_material(role: str) -> bpy.types.Material:
    name = "AWQ_SourceMaterial_" + role
    existing = bpy.data.materials.get(name)
    if existing is not None:
        if existing.get("aw_owner") != OWNER:
            raise RuntimeError(f"Unowned material name: {name}")
        if existing.get("aw_material_revision") == 2:
            return existing
    palette = {
        "stone": ((0.16, 0.145, 0.11), (0.34, 0.315, 0.25), 0.0, 0.79),
        "mortar": ((0.095, 0.12, 0.10), (0.22, 0.23, 0.18), 0.0, 0.86),
        "paint": ((0.11, 0.18, 0.18), (0.28, 0.33, 0.29), 0.22, 0.49),
        "copper": ((0.20, 0.11, 0.045), (0.43, 0.26, 0.11), 0.73, 0.40),
        "steel": ((0.075, 0.105, 0.11), (0.31, 0.34, 0.30), 0.82, 0.37),
        "glass": ((0.055, 0.10, 0.12), (0.13, 0.19, 0.20), 0.15, 0.20),
        "foliage": ((0.10, 0.15, 0.07), (0.29, 0.32, 0.13), 0.0, 0.72),
        "rubber": ((0.018, 0.028, 0.025), (0.06, 0.07, 0.055), 0.0, 0.81),
        "warm_light": ((0.62, 0.34, 0.09), (0.94, 0.67, 0.28), 0.0, 0.32),
    }
    if role not in palette:
        raise ValueError(f"Unknown material role: {role}")
    low, high, metallic, roughness = palette[role]
    mat = existing or bpy.data.materials.new(name)
    mat["aw_owner"] = OWNER
    mat["aw_material_role"] = role
    mat["aw_material_revision"] = 2
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    geometry = nodes.new("ShaderNodeNewGeometry")
    macro = nodes.new("ShaderNodeTexNoise")
    macro.inputs["Scale"].default_value = 2.4 if role == "stone" else 4.7
    macro.inputs["Detail"].default_value = 3.0
    links.new(geometry.outputs["Position"], macro.inputs["Vector"])
    color = nodes.new("ShaderNodeValToRGB")
    color.color_ramp.elements[0].position = 0.22
    color.color_ramp.elements[0].color = (*low, 1.0)
    color.color_ramp.elements[1].position = 0.81
    color.color_ramp.elements[1].color = (*high, 1.0)
    links.new(macro.outputs["Fac"], color.inputs["Fac"])
    links.new(color.outputs["Color"], shader.inputs["Base Color"])
    wet = nodes.new("ShaderNodeTexNoise")
    wet.inputs["Scale"].default_value = 0.56
    wet.inputs["Detail"].default_value = 2.0
    links.new(geometry.outputs["Position"], wet.inputs["Vector"])
    dark = nodes.new("ShaderNodeMixRGB")
    if "MULTIPLY" not in {item.identifier for item in dark.bl_rna.properties["blend_type"].enum_items}:
        raise RuntimeError("Installed MixRGB does not expose the required multiply mode.")
    dark.blend_type = "MULTIPLY"
    dark.inputs[2].default_value = (0.47, 0.54, 0.51, 1.0)
    wet_strength = nodes.new("ShaderNodeMapRange")
    wet_strength.inputs["From Min"].default_value = 0.38
    wet_strength.inputs["From Max"].default_value = 0.71
    wet_strength.inputs["To Min"].default_value = 0.0
    wet_strength.inputs["To Max"].default_value = 0.73 if role in {"stone", "mortar"} else 0.31
    links.new(wet.outputs["Fac"], wet_strength.inputs["Value"])
    links.new(wet_strength.outputs["Result"], dark.inputs[0])
    links.new(color.outputs["Color"], dark.inputs[1])
    links.new(dark.outputs["Color"], shader.inputs["Base Color"])
    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["From Min"].default_value = 0.34
    rough.inputs["From Max"].default_value = 0.74
    rough.inputs["To Min"].default_value = roughness
    rough.inputs["To Max"].default_value = max(0.16, roughness - 0.37)
    links.new(wet.outputs["Fac"], rough.inputs["Value"])
    links.new(rough.outputs["Result"], shader.inputs["Roughness"])
    shader.inputs["Metallic"].default_value = metallic
    fine = nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 75.0 if role in {"stone", "mortar"} else 140.0
    fine.inputs["Detail"].default_value = 2.0
    links.new(geometry.outputs["Position"], fine.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.32 if role == "stone" else 0.18
    bump.inputs["Distance"].default_value = 0.008 if role == "stone" else 0.002
    links.new(fine.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    if role == "warm_light":
        shader.inputs["Emission Color"].default_value = (*high, 1.0)
        shader.inputs["Emission Strength"].default_value = 1.4
    return mat


def box(name: str, center: tuple, dimensions: tuple, role: str, asset_id: str,
        bevel: float = 0.02, rotation: tuple = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    if min(dimensions) <= 0.0 or bevel < 0.0:
        raise ValueError("Finite positive dimensions and nonnegative bevel are required.")
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.object
    obj.name = "AWQ_" + asset_id + "_" + name
    obj.dimensions = dimensions
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(source_material(role))
    if bevel > 0.0:
        modifier = obj.modifiers.new("AuthoredEdge", "BEVEL")
        modifier.width = min(bevel, min(dimensions) * 0.19)
        modifier.segments = 3
    return tagged(obj, asset_id, "source")


def slab(name: str, bounds: tuple, seed: int, asset_id: str, top: float = 0.01) -> bpy.types.Object:
    x, y, width, length = bounds
    rng = random.Random(seed)
    x0, x1 = x - width * 0.5, x + width * 0.5
    y0, y1 = y - length * 0.5, y + length * 0.5
    cut = min(width, length) * rng.uniform(0.035, 0.095)
    polygon = [(x0 + cut, y0), (x1 - cut * 0.65, y0), (x1, y0 + cut),
               (x1, y1 - cut * 0.8), (x1 - cut, y1), (x0 + cut * 0.6, y1),
               (x0, y1 - cut), (x0, y0 + cut * 0.7)]
    bottom = -0.10
    vertices = [(px, py, bottom) for px, py in polygon] + [(px, py, top) for px, py in polygon]
    n = len(polygon)
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new("AWQ_" + name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("AWQ_" + asset_id + "_" + name, mesh)
    collection("source").objects.link(obj)
    obj["aw_owner"], obj["aw_asset_id"], obj["aw_role"] = OWNER, asset_id, "source"
    mesh.materials.append(source_material("stone"))
    edge = obj.modifiers.new("DressedStoneEdges", "BEVEL")
    edge.width, edge.segments = 0.008, 3
    return obj


def pipe(name: str, a: tuple, b: tuple, radius: float, role: str, asset_id: str) -> bpy.types.Object:
    va, vb = Vector(a), Vector(b)
    delta = vb - va
    if delta.length <= 0.001 or radius <= 0.0:
        raise ValueError("Pipe endpoints and radius must be valid.")
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=delta.length, location=(va + vb) * 0.5)
    obj = bpy.context.object
    obj.name = "AWQ_" + asset_id + "_" + name
    obj.rotation_euler = delta.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(source_material(role))
    return tagged(obj, asset_id, "source")


def parts(asset_id: str, role: str) -> list[bpy.types.Object]:
    return [obj for obj in collection(role).objects if obj.get("aw_asset_id") == asset_id]


def derive_runtime(asset_id: str) -> bpy.types.Object:
    source = parts(asset_id, "source")
    if not source:
        raise RuntimeError(f"No authored source objects for {asset_id}")
    if parts(asset_id, "runtime"):
        raise RuntimeError(f"Runtime generation already exists: {asset_id}")
    runtime = []
    for src in source:
        obj = src.copy()
        obj.data = src.data.copy()
        obj.name = src.name + "_Runtime"
        collection("runtime").objects.link(obj)
        obj["aw_role"] = "runtime"
        for modifier in obj.modifiers:
            if modifier.type == "BEVEL":
                modifier.segments = 1
        runtime.append(obj)
    select(runtime)
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = "AWQ_Runtime_" + asset_id
    cursor = bpy.context.scene.cursor.location.copy()
    try:
        bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    finally:
        bpy.context.scene.cursor.location = cursor
    select([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    try:
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.010,
                                 margin_method="FRACTION", correct_aspect=True, scale_to_bounds=True)
    finally:
        bpy.ops.object.mode_set(mode="OBJECT")
    obj.data.uv_layers.active.name = "QualityUV"
    return obj


def build_paving(variant: int = 0) -> dict:
    owned_scene()
    if variant not in range(4):
        raise ValueError("Paving variants are exactly 0–3.")
    asset_id = IDS[variant]
    assert_new(asset_id)
    box("MortarBed", (0.0, 0.0, -0.115), (4.0, 4.0, 0.045), "mortar", asset_id, 0.0)
    rows = [(-1.63, 0.70), (-0.94, 0.62), (-0.20, 0.84), (0.61, 0.72), (1.48, 1.00)]
    widths = [[0.62, 1.17, 0.81, 1.32], [1.19, 0.67, 1.37, 0.69], [0.86, 1.51, 0.63, 0.92],
              [1.41, 0.77, 0.58, 1.16], [0.97, 0.66, 1.26, 1.03]]
    gap = 0.020
    drain_x = -1.29 + variant * 0.76
    drain_bounds = (drain_x - 0.19, drain_x + 0.19, -0.92, 0.56)
    for row, (center_y, height) in enumerate(rows):
        values = widths[(row + variant) % len(widths)]
        scale = 3.98 / sum(values)
        cursor = -1.99
        for index, raw in enumerate(values):
            width = raw * scale
            x = cursor + width * 0.5
            cursor += width
            rectangles = cut_rectangle((x, center_y, width - gap, height - gap), drain_bounds)
            for piece, rectangle in enumerate(rectangles):
                slab(f"Stone_{row}_{index}_{piece}", rectangle,
                     4100 + variant * 71 + row * 11 + index + piece * 17, asset_id,
                     0.009 + ((index + row) % 3) * 0.003)
    box("DrainBed", (drain_x, -0.17, -0.056), (0.32, 1.43, 0.024), "mortar", asset_id, 0.008)
    for index in range(14):
        box(f"GrateBar_{index}", (drain_x, -0.80 + index * 0.095, 0.011),
            (0.29, 0.038, 0.032), "steel", asset_id, 0.007)
    for side in [-1, 1]:
        box(f"GrateRail_{side}", (drain_x + side * 0.153, -0.18, 0.008),
            (0.029, 1.43, 0.04), "copper", asset_id, 0.006)
    patch_x, patch_y = 0.72 - variant * 0.28, 0.63 + variant * 0.11
    box("RepairPlate", (patch_x, patch_y, 0.029), (0.91, 0.55, 0.032), "paint", asset_id, 0.02,
        (0.0, 0.0, 0.09 * (variant - 1)))
    for x in [-0.34, 0.34]:
        for y in [-0.19, 0.19]:
            box(f"PlateFastener_{x}_{y}", (patch_x + x, patch_y + y, 0.052),
                (0.033, 0.033, 0.017), "steel", asset_id, 0.004)
    for index in range(3 + variant):
        box(f"StoneStaple_{index}", (-0.73 + index * 0.19, 1.00, 0.027),
            (0.030, 0.20, 0.017), "steel", asset_id, 0.003, (0.0, 0.0, -0.20))
    runtime = derive_runtime(asset_id)
    return audit_object(runtime)


def cut_rectangle(rectangle: tuple, opening: tuple) -> list[tuple]:
    """Cut a real rectangular drain opening without placing fake dark caps over stone."""
    x, y, width, height = rectangle
    x0, x1, y0, y1 = x - width * 0.5, x + width * 0.5, y - height * 0.5, y + height * 0.5
    ix0, ix1 = max(x0, opening[0]), min(x1, opening[1])
    iy0, iy1 = max(y0, opening[2]), min(y1, opening[3])
    if ix0 >= ix1 or iy0 >= iy1:
        return [rectangle]
    bounds = [(x0, ix0, y0, y1), (ix1, x1, y0, y1), (ix0, ix1, y0, iy0), (ix0, ix1, iy1, y1)]
    return [((a + b) * 0.5, (c + d) * 0.5, b - a, d - c)
            for a, b, c, d in bounds if b - a > 0.035 and d - c > 0.035]


def build_facade() -> dict:
    owned_scene()
    asset_id = "rain_reclaim_facade"
    assert_new(asset_id)
    box("StructuralMass", (0.0, 1.35, 3.09), (6.0, 3.10, 6.18), "mortar", asset_id, 0.075)
    box("FoundationCourse", (0.0, 1.29, 0.22), (6.12, 3.23, 0.44), "stone", asset_id, 0.034)
    for row in range(11):
        for column in range(8):
            x = -2.60 + column * 0.74 + (0.16 if row % 2 else 0.0)
            if -0.85 < x < 0.90 and row < 5:
                continue
            box(f"FacadeMasonry_{row}_{column}", (x, -0.246, 0.54 + row * 0.47),
                (0.70 if column < 7 else 0.47, 0.20, 0.44), "stone", asset_id, 0.022)
    for x in [-2.84, -0.98, 1.04, 2.85]:
        box(f"Upright_{x}", (x, -0.42, 3.18), (0.14, 0.19, 5.98), "steel", asset_id, 0.014)
    for z in [0.45, 3.11, 6.07]:
        box(f"FloorRail_{z}", (0.0, -0.37, z), (6.13, 0.16, 0.18), "paint", asset_id, 0.022)
    box("ServiceDoorFrame", (0.0, -0.47, 1.43), (1.79, 0.24, 2.42), "copper", asset_id, 0.027)
    box("ClosedServiceDoor", (0.0, -0.614, 1.43), (1.60, 0.09, 2.23), "paint", asset_id, 0.018)
    for x in [-0.42, 0.0, 0.42]:
        box(f"DoorPanel_{x}", (x, -0.673, 1.43), (0.31, 0.035, 1.72), "steel", asset_id, 0.009)
    box("DoorHandle", (0.56, -0.731, 1.28), (0.052, 0.083, 0.30), "copper", asset_id, 0.012)
    for cx, z, width in [(-1.93, 4.34, 1.48), (1.91, 4.70, 1.38), (1.91, 1.51, 0.98)]:
        box(f"WindowFrame_{cx}_{z}", (cx, -0.45, z), (width, 0.24, 1.15), "copper", asset_id, 0.025)
        box(f"WindowGlass_{cx}_{z}", (cx, -0.593, z), (width - 0.16, 0.038, 0.97), "glass", asset_id, 0.006)
        for side in [-1, 1]:
            box(f"Mullion_{cx}_{z}_{side}", (cx + side * width * 0.22, -0.627, z),
                (0.033, 0.035, 1.01), "steel", asset_id, 0.005)
        if cx < 0.0:
            box("ControlRoomInteriorLight", (cx, -0.666, z - 0.39), (width - 0.29, 0.034, 0.067),
                "warm_light", asset_id, 0.004)
    roof_slope = math.radians(11.0)
    for index in range(8):
        box(f"RoofPan_{index}", (-2.76 + index * 0.79, 1.31, 6.39),
            (0.76, 3.55, 0.095), "paint", asset_id, 0.017, (roof_slope, 0.0, 0.0))
        box(f"StandingSeam_{index}", (-2.39 + index * 0.79, 1.31, 6.48),
            (0.033, 3.55, 0.049), "copper", asset_id, 0.007, (roof_slope, 0.0, 0.0))
    box("GutterBed", (0.0, -0.51, 6.12), (6.48, 0.22, 0.10), "copper", asset_id, 0.014)
    for offset in [-0.115, 0.115]:
        box(f"GutterLip_{offset}", (0.0, -0.51 + offset, 6.21), (6.48, 0.033, 0.17),
            "copper", asset_id, 0.008)
    for x in [-2.43, 2.49]:
        pipe(f"DownPipe_{x}", (x, -0.73, 0.49), (x, -0.73, 6.12), 0.065, "copper", asset_id)
        for z in [0.92, 2.39, 4.21, 5.78]:
            box(f"PipeClamp_{x}_{z}", (x, -0.72, z), (0.19, 0.19, 0.050), "steel", asset_id, 0.009)
    box("FilterHousing", (-1.97, -0.95, 1.55), (0.95, 0.66, 1.71), "paint", asset_id, 0.065)
    for index in range(8):
        box(f"FilterVent_{index}", (-1.97, -1.29, 1.01 + index * 0.126), (0.69, 0.054, 0.035),
            "steel", asset_id, 0.005)
    box("MaintenanceCanopy", (0.11, -1.12, 2.97), (2.93, 1.22, 0.082), "paint", asset_id, 0.019,
        (math.radians(8.0), 0.0, 0.0))
    for x in [-1.05, 1.19]:
        pipe(f"CanopyBrace_{x}", (x, -0.60, 2.58), (x, -1.61, 2.92), 0.030, "steel", asset_id)
    for x in [1.59, 2.06]:
        box(f"Planter_{x}", (x, -0.71, 5.87), (0.39, 0.44, 0.36), "stone", asset_id, 0.035)
        for branch in range(5):
            z = 5.83 - branch * 0.34
            pipe(f"VineStem_{x}_{branch}", (x, -0.78, z), (x + 0.08, -0.88, z - 0.34),
                0.009, "foliage", asset_id)
            for side in [-1, 1]:
                box(f"VineLeaf_{x}_{branch}_{side}", (x + side * 0.094, -0.93, z - 0.12),
                    (0.17, 0.019, 0.095), "foliage", asset_id, 0.004,
                    (0.17, side * 0.31, side * 0.37))
    runtime = derive_runtime(asset_id)
    return audit_object(runtime)


def audit_object(obj: bpy.types.Object) -> dict:
    mesh = obj.data
    mesh.calc_loop_triangles()
    coords = [obj.matrix_world @ vertex.co for vertex in mesh.vertices]
    if not coords or any(not math.isfinite(component) for coordinate in coords for component in coordinate):
        raise RuntimeError(f"Invalid/nonfinite geometry: {obj.name}")
    minimum = [min(p[axis] for p in coords) for axis in range(3)]
    maximum = [max(p[axis] for p in coords) for axis in range(3)]
    uv = mesh.uv_layers.active
    if uv is None:
        raise RuntimeError(f"No runtime UV: {obj.name}")
    invalid_uv = sum(1 for item in uv.data if not all(math.isfinite(v) for v in item.uv))
    if invalid_uv:
        raise RuntimeError(f"Nonfinite UVs: {obj.name}")
    return {"id": obj["aw_asset_id"], "object": obj.name, "triangles": len(mesh.loop_triangles),
            "vertices": len(mesh.vertices), "materials": len(mesh.materials), "uv": uv.name,
            "bounds_blender_xyz": {"min": minimum, "max": maximum},
            "bounds_godot_xyz": {"min": [minimum[0], minimum[2], -maximum[1]],
                                  "max": [maximum[0], maximum[2], -minimum[1]]},
            "pivot": [float(v) for v in obj.location], "nonfinite_uv": invalid_uv,
            "source_objects": len(parts(obj["aw_asset_id"], "source")),
            "status": "authored_geometry_runtime_uv_only_not_baked_or_game_accepted"}


def save_source() -> Path:
    owned_scene()
    destination = scope(SOURCE / "blender" / "repair_district.blend", SOURCE)
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(destination), check_existing=False)
    return destination


def write_geometry_evidence(stage: str, records: list[dict]) -> Path:
    destination = scope(SOURCE / "evidence" / f"{stage}-geometry.json", SOURCE)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({"kind": "actual_blender_authored_geometry", "blender": bpy.app.version_string,
        "scene": bpy.context.scene.name, "owner": OWNER, "records": records, "bake_executed": False,
        "engine_acceptance": False}, ensure_ascii=False, indent=2), encoding="utf-8")
    return destination


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=["sample", "variants", "building"], required=True)
    import sys
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    start = time.perf_counter()
    if args.stage == "sample":
        records = [build_paving(0)]
    elif args.stage == "variants":
        records = [build_paving(index) for index in [1, 2, 3]]
    else:
        records = [build_facade()]
    saved = save_source()
    evidence = write_geometry_evidence(args.stage, records)
    print(json.dumps({"stage": args.stage, "records": records, "blend": str(saved),
                      "evidence": str(evidence), "seconds": time.perf_counter() - start}))


if __name__ == "__main__":
    main()
