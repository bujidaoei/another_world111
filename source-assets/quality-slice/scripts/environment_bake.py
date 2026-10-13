"""Actual Cycles baking and glTF material assembly for owned environment assets."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import time

import bpy
import numpy as np


FACTORY_PATH = Path(__file__).with_name("environment_factory.py")
_spec = importlib.util.spec_from_file_location("aw_quality_environment", FACTORY_PATH)
factory = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(factory)
CHANNELS = {"albedo": "EMIT", "normal": "NORMAL", "ao": "AO", "roughness": "ROUGHNESS", "metallic": "EMIT"}


def _enum_set(owner, name: str, value: str) -> None:
    prop = owner.bl_rna.properties[name]
    values = {item.identifier for item in prop.enum_items}
    if values and value not in values:
        raise RuntimeError(f"Unsupported installed enum {name}={value}; available {sorted(values)}")
    try:
        setattr(owner, name, value)
    except TypeError as error:
        raise RuntimeError(f"Installed property rejected {name}={value}: {error}") from error


def configure_cycles(device: str = "CPU", samples: int = 16) -> dict:
    scene = factory.owned_scene()
    _enum_set(scene.render, "engine", "CYCLES")
    devices = []
    if device == "GPU":
        prefs = bpy.context.preferences.addons["cycles"].preferences
        _enum_set(prefs, "compute_device_type", "CUDA")
        prefs.get_devices()
        for item in prefs.devices:
            item.use = item.type == "CUDA"
            if item.use:
                devices.append({"name": item.name, "type": item.type})
        if not devices:
            raise RuntimeError("No actual CUDA device; do not report a GPU bake.")
    elif device != "CPU":
        raise ValueError("Device must be CPU or GPU.")
    _enum_set(scene.cycles, "device", device)
    scene.cycles.samples = samples
    return {"device": device, "devices": devices, "samples": samples}


def _runtime(asset_id: str) -> bpy.types.Object:
    objects = factory.parts(asset_id, "runtime")
    if len(objects) != 1:
        raise RuntimeError(f"Exactly one runtime mesh is required: {asset_id}")
    return objects[0]


def _directory(asset_id: str) -> Path:
    if asset_id not in factory.IDS:
        raise ValueError("Unknown asset ID.")
    path = factory.scope(factory.SOURCE / "materials" / asset_id, factory.SOURCE)
    path.mkdir(parents=True, exist_ok=True)
    return path


def _image_name(asset_id: str, channel: str, resolution: int) -> str:
    return f"AWQ_{asset_id}_{channel}_{resolution}"


def _source_materials(asset_id: str) -> list[bpy.types.Material]:
    unique = {}
    for obj in factory.parts(asset_id, "source"):
        for mat in obj.data.materials:
            unique[mat.name] = mat
    return list(unique.values())


def _emission_override(materials: list[bpy.types.Material], field: str) -> list[tuple]:
    restore = []
    for mat in materials:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
        original = [(link.from_socket, link.to_socket) for link in output.inputs["Surface"].links]
        emission = nodes.new("ShaderNodeEmission")
        socket = shader.inputs["Base Color" if field == "albedo" else "Metallic"]
        if socket.is_linked:
            links.new(socket.links[0].from_socket, emission.inputs["Color"])
        elif field == "albedo":
            emission.inputs["Color"].default_value = socket.default_value
        else:
            value = float(socket.default_value)
            emission.inputs["Color"].default_value = (value, value, value, 1.0)
        emission.inputs["Strength"].default_value = 1.0
        links.new(emission.outputs["Emission"], output.inputs["Surface"])
        restore.append((mat, emission, original))
    return restore


def bake_channel(asset_id: str, channel: str, resolution: int = 1024, device: str = "CPU") -> dict:
    if channel not in CHANNELS or resolution not in [512, 1024, 2048]:
        raise ValueError("A supported actual bake channel and resolution are required.")
    scene = factory.owned_scene()
    runtime = _runtime(asset_id)
    source = factory.parts(asset_id, "source")
    if not source:
        raise RuntimeError("Source geometry is required for selected-to-active baking.")
    settings = configure_cycles(device)
    materials = _source_materials(asset_id)
    name = _image_name(asset_id, channel, resolution)
    if bpy.data.images.get(name):
        raise RuntimeError(f"A baked generation already exists: {name}")
    image = bpy.data.images.new(name, width=resolution, height=resolution, alpha=False, float_buffer=False)
    _enum_set(image.colorspace_settings, "name", "sRGB" if channel == "albedo" else "Non-Color")
    targets, restored_outputs = [], []
    visibility = {obj.name: (obj.hide_render, obj.hide_get()) for obj in scene.objects if obj.type == "MESH"}
    start = time.perf_counter()
    try:
        allowed = {obj.name for obj in source + [runtime]}
        for obj in scene.objects:
            if obj.type == "MESH":
                obj.hide_render = obj.name not in allowed
                obj.hide_set(obj.name not in allowed)
        for mat in materials:
            node = mat.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = image
            mat.node_tree.nodes.active = node
            targets.append((mat, node))
        if channel in ["albedo", "metallic"]:
            restored_outputs = _emission_override(materials, channel)
        factory.select(source + [runtime], runtime)
        bpy.ops.object.bake(type=CHANNELS[channel], use_selected_to_active=True,
                            cage_extrusion=0.075, max_ray_distance=0.16, margin=12,
                            normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y", normal_b="POS_Z",
                            use_clear=True)
        destination = _directory(asset_id) / f"{asset_id}_{channel}_{resolution}.png"
        image.filepath_raw = str(destination)
        _enum_set(image, "file_format", "PNG")
        image.save()
        image.pack()
        values = np.empty(resolution * resolution * 4, dtype=np.float32)
        image.pixels.foreach_get(values)
        pixels = values.reshape((-1, 4))[:, :3]
        if not np.isfinite(pixels).all():
            raise RuntimeError("The actual baked image contains nonfinite pixels.")
        record = {"asset_id": asset_id, "channel": channel, "image": name,
                  "path": str(destination.relative_to(factory.ROOT)).replace("\\", "/"),
                  "resolution": [resolution, resolution], "color_space": image.colorspace_settings.name,
                  "settings": settings, "seconds": time.perf_counter() - start,
                  "rgb_min": pixels.min(axis=0).tolist(), "rgb_max": pixels.max(axis=0).tolist(),
                  "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "bytes": destination.stat().st_size,
                  "actual_cycles_selected_to_active": True, "engine_acceptance": False}
        evidence = factory.scope(factory.SOURCE / "evidence" / f"{asset_id}-{channel}-bake.json", factory.SOURCE)
        evidence.parent.mkdir(parents=True, exist_ok=True)
        evidence.write_text(json.dumps(record, indent=2), encoding="utf-8")
        return record
    finally:
        for mat, emission, original in restored_outputs:
            mat.node_tree.nodes.remove(emission)
            for left, right in original:
                mat.node_tree.links.new(left, right)
        for mat, node in targets:
            mat.node_tree.nodes.remove(node)
        for name, (hidden, viewport_hidden) in visibility.items():
            obj = bpy.data.objects.get(name)
            if obj is not None:
                obj.hide_render = hidden
                obj.hide_set(viewport_hidden)


def _baked_image(asset_id: str, channel: str, resolution: int) -> bpy.types.Image:
    image = bpy.data.images.get(_image_name(asset_id, channel, resolution))
    if image is None or tuple(image.size) != (resolution, resolution):
        raise RuntimeError(f"Missing real bake: {asset_id}/{channel}/{resolution}")
    return image


def assemble_runtime_material(asset_id: str, resolution: int = 1024) -> dict:
    runtime = _runtime(asset_id)
    images = {kind: _baked_image(asset_id, kind, resolution) for kind in CHANNELS}
    rgba = np.ones((resolution * resolution, 4), dtype=np.float32)
    for channel, kind in enumerate(["ao", "roughness", "metallic"]):
        values = np.empty(resolution * resolution * 4, dtype=np.float32)
        images[kind].pixels.foreach_get(values)
        rgba[:, channel] = values.reshape((-1, 4))[:, 0]
    orm_name = _image_name(asset_id, "orm", resolution)
    if bpy.data.images.get(orm_name):
        raise RuntimeError("Refusing to replace an existing packed ORM generation.")
    orm = bpy.data.images.new(orm_name, width=resolution, height=resolution, alpha=False, float_buffer=False)
    _enum_set(orm.colorspace_settings, "name", "Non-Color")
    orm.pixels.foreach_set(rgba.ravel())
    orm.update()
    orm.filepath_raw = str(_directory(asset_id) / f"{asset_id}_orm_{resolution}.png")
    _enum_set(orm, "file_format", "PNG")
    orm.save()
    orm.pack()
    material = bpy.data.materials.new("AWQ_RuntimeMaterial_" + asset_id)
    material["aw_owner"], material["aw_asset_id"] = factory.OWNER, asset_id
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    maps = {"albedo": images["albedo"], "normal": images["normal"], "orm": orm}
    textures = {}
    runtime_directory = factory.scope(factory.RUNTIME / "textures", factory.RUNTIME)
    runtime_directory.mkdir(parents=True, exist_ok=True)
    for kind, image in maps.items():
        destination = factory.scope(runtime_directory / Path(image.filepath_raw).name, factory.RUNTIME)
        destination.write_bytes(Path(image.filepath_raw).read_bytes())
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        textures[kind] = node
    links.new(textures["albedo"].outputs["Color"], shader.inputs["Base Color"])
    normal = nodes.new("ShaderNodeNormalMap")
    _enum_set(normal, "space", "TANGENT")
    links.new(textures["normal"].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    split = nodes.new("ShaderNodeSeparateColor")
    _enum_set(split, "mode", "RGB")
    links.new(textures["orm"].outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], shader.inputs["Roughness"])
    links.new(split.outputs["Blue"], shader.inputs["Metallic"])
    group = bpy.data.node_groups.get("glTF Material Output")
    if group is None:
        group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    if "Occlusion" not in [socket.name for socket in group.interface.items_tree]:
        raise RuntimeError("glTF occlusion hook has an incompatible interface.")
    hook = nodes.new("ShaderNodeGroup")
    hook.node_tree = group
    links.new(split.outputs["Red"], hook.inputs["Occlusion"])
    runtime.data.materials.clear()
    runtime.data.materials.append(material)
    for polygon in runtime.data.polygons:
        polygon.material_index = 0
    material["aw_uv"] = runtime.data.uv_layers.active.name
    material["aw_maps"] = json.dumps({key: image.filepath_raw for key, image in maps.items()})
    return {"asset_id": asset_id, "runtime_materials": 1, "uv": material["aw_uv"],
            "maps": {key: str(Path(image.filepath_raw).relative_to(factory.ROOT)).replace("\\", "/")
                     for key, image in maps.items()}, "orm": "R=AO; G=roughness; B=metallic",
            "bake_source_channels": list(CHANNELS), "engine_acceptance": False}


def export(asset_id: str) -> dict:
    runtime = _runtime(asset_id)
    if len(runtime.data.materials) != 1 or not runtime.data.materials[0].get("aw_maps"):
        raise RuntimeError("Only the assembled real PBR material may be exported.")
    factory.RUNTIME.mkdir(parents=True, exist_ok=True)
    destination = factory.scope(factory.RUNTIME / f"{asset_id}.glb", factory.RUNTIME)
    factory.select([runtime])
    bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB", use_selection=True,
                              export_yup=True, export_texcoords=True, export_normals=True,
                              export_tangents=True, export_apply=True, export_materials="EXPORT",
                              export_animations=False, export_cameras=False, export_lights=False)
    data = destination.read_bytes()
    if data[:4] != b"glTF" or int.from_bytes(data[4:8], "little") != 2 or int.from_bytes(data[8:12], "little") != len(data):
        raise RuntimeError("The actual export is not a valid complete GLB2 container.")
    record = factory.audit_object(runtime)
    record.update({"path": "res://assets/quality/" + destination.name, "sha256": hashlib.sha256(data).hexdigest(),
                   "bytes": len(data), "maps": json.loads(runtime.data.materials[0]["aw_maps"]),
                   "status": "source_baked_and_exported_engine_acceptance_pending"})
    evidence = factory.scope(factory.SOURCE / "evidence" / f"{asset_id}-export.json", factory.SOURCE)
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    factory.save_source()
    return record
