"""Native PBR previews of the current module manifest, separate from game evidence."""
from pathlib import Path
import bpy
import json
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
scene=bpy.context.scene
if scene.name!="AnotherWorld_DistrictModules" or not scene.get("another_world_dedicated_session"):
    raise RuntimeError("Dedicated module scene required")
manifest=json.loads((ROOT/"source-assets/district-manifest.json").read_text(encoding="utf-8"))
if scene.world is None:
    scene.world=bpy.data.worlds.new("AW_DistrictStudio")
    scene.world.use_nodes=True
    background=next(n for n in scene.world.node_tree.nodes if n.type=="BACKGROUND")
    background.inputs[0].default_value=(.075,.095,.11,1)
    background.inputs[1].default_value=.70
if scene.camera is None:
    bpy.ops.object.camera_add()
    scene.camera=bpy.context.object
    scene.camera.name="DistrictReviewCamera"
scene.camera.data.type="ORTHO"
lights=[o for o in scene.objects if o.type=="LIGHT"]
if not lights:
    for name in ["ModuleKey","ModuleFill","ModuleRim"]:
        bpy.ops.object.light_add(type="AREA")
        lamp=bpy.context.object
        lamp.name=name
        lamp.data.shape="DISK"
        lights.append(lamp)
scene.render.resolution_x=600
scene.render.resolution_y=600
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
old_hide={o.name:o.hide_render for o in scene.objects}
for asset in manifest["assets"]:
    root=bpy.data.objects[asset["id"]]
    children=set(root.children_recursive)
    for obj in scene.objects:
        if obj.type=="MESH":obj.hide_render=obj not in children
    points=[o.matrix_world@Vector(corner) for o in children if o.type=="MESH" for corner in o.bound_box]
    low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center=(low+high)*.5
    extent=max((high-low).length,1)
    scene.camera.location=center+Vector((-1,1,.85))*extent
    scene.camera.rotation_euler=(center-scene.camera.location).to_track_quat("-Z","Y").to_euler()
    scene.camera.data.ortho_scale=extent*1.1
    for light,direction,power in zip(lights,[(1,1,2),(-2,0,1),(0,-1,2)],[85,30,65]):
        light.location=center+Vector(direction)*extent
        light.rotation_euler=(center-light.location).to_track_quat("-Z","Y").to_euler()
        light.data.energy=power*extent*extent
        light.data.size=extent*1.3
    folder=ROOT/"source-assets/previews/district"
    folder.mkdir(parents=True,exist_ok=True)
    scene.render.filepath=str(folder/(asset["id"]+".png"))
    bpy.ops.render.render(write_still=True)
    print("module_preview",asset["id"])
for name,value in old_hide.items():bpy.data.objects[name].hide_render=value
