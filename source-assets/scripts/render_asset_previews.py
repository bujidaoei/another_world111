"""Render the authored family in its own Blender session, restoring scene state."""
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
scene=bpy.context.scene
if not scene.get("another_world_dedicated_session"):
    raise RuntimeError("Dedicated production scene required")
names=["survivor_robot","scavenger","guardian","spitter","lightning_rifle_t1","lightning_rifle_t2","conductive_anchor","cargo_crate","barricade","pump_station"]
camera=scene.camera
old_hide={o.name:o.hide_render for o in scene.objects}
old_camera=(camera.matrix_world.copy(),camera.data.ortho_scale)
old_resolution=(scene.render.resolution_x,scene.render.resolution_y)
old_path=scene.render.filepath
lights=[o for o in scene.objects if o.type=="LIGHT"]
old_lights={o.name:(o.matrix_world.copy(),o.data.energy,o.data.size) for o in lights}
try:
    for name in names:
        root=bpy.data.objects[name]
        children=set(root.children_recursive)
        for obj in scene.objects:
            if obj.type=="MESH":
                obj.hide_render=obj not in children
        points=[obj.matrix_world @ Vector(corner) for obj in children if obj.type=="MESH" for corner in obj.bound_box]
        low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
        high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
        center=(high+low)/2
        extent=max((high-low).length,1)
        camera.location=center+Vector((-1,1,0.9))*extent
        camera.rotation_euler=(center-camera.location).to_track_quat("-Z","Y").to_euler()
        camera.data.ortho_scale=extent*1.15
        for light, direction, power in zip(lights,[(1,1,2),(-2,0,1),(0,-1,2)],[85,30,65]):
            light.location=center+Vector(direction)*extent
            light.rotation_euler=(center-light.location).to_track_quat("-Z","Y").to_euler()
            light.data.energy=power*extent*extent
            light.data.size=extent*1.3
        scene.render.resolution_x=600
        scene.render.resolution_y=600
        scene.render.filepath=str(ROOT / "source-assets/previews" / (name+".png"))
        bpy.ops.render.render(write_still=True)
        print("preview",name)
finally:
    for name,value in old_hide.items():
        bpy.data.objects[name].hide_render=value
    camera.matrix_world,camera.data.ortho_scale=old_camera
    for name,(matrix,energy,size) in old_lights.items():
        bpy.data.objects[name].matrix_world=matrix
        bpy.data.objects[name].data.energy=energy
        bpy.data.objects[name].data.size=size
    scene.render.resolution_x,scene.render.resolution_y=old_resolution
    scene.render.filepath=old_path
