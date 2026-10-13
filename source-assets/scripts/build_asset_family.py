"""Reproducible original hard-surface study for Another World, Blender 5.2.

Execute this saved script through Blender MCP in the dedicated project session.
Runtime delivery is glTF 2.0; editable sources and measured geometry stay here.
No external meshes, model weights, images, fonts or paid services are used.
"""
from pathlib import Path
import bpy
import math
import json
import hashlib
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "source-assets"
EXPORT = ROOT / "game" / "assets" / "models"
for folder in [SOURCE / "blender", SOURCE / "textures", SOURCE / "previews", SOURCE / "evidence", EXPORT]:
    folder.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
if not scene.get("another_world_dedicated_session"):
    raise RuntimeError("Refusing to replace a scene outside the dedicated asset session")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for mesh in list(bpy.data.meshes):
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
for mat in list(bpy.data.materials):
    if mat.name.startswith("AW_") and mat.users == 0:
        bpy.data.materials.remove(mat)
for image in list(bpy.data.images):
    if image.name.startswith("palette_") and image.users == 0:
        bpy.data.images.remove(image)
for action in list(bpy.data.actions):
    if action.users == 0:
        bpy.data.actions.remove(action)
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 25

PALETTE = {
    "graphite": ((0.045, 0.073, 0.081, 1), 0.72, 0.34, 0),
    "steel": ((0.22, 0.28, 0.29, 1), 0.82, 0.36, 0),
    "orange": ((0.61, 0.235, 0.07, 1), 0.40, 0.46, 0),
    "ivory": ((0.56, 0.59, 0.49, 1), 0.22, 0.59, 0),
    "cyan": ((0.08, 0.66, 0.73, 1), 0.15, 0.24, 1.5),
    "amber": ((1.0, 0.43, 0.10, 1), 0.12, 0.3, 1.1),
    "danger": ((0.66, 0.10, 0.08, 1), 0.38, 0.43, 0),
    "moss": ((0.14, 0.22, 0.10, 1), 0.0, 0.92, 0),
    "concrete": ((0.26, 0.30, 0.28, 1), 0.0, 0.87, 0),
}
MATS = {}
for name, (rgba, metal, rough, emit) in PALETTE.items():
    mat = bpy.data.materials.new("AW_" + name)
    mat.use_nodes = True
    node = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node.inputs["Base Color"].default_value = rgba
    node.inputs["Metallic"].default_value = metal
    node.inputs["Roughness"].default_value = rough
    node.inputs["Emission Color"].default_value = rgba
    node.inputs["Emission Strength"].default_value = emit
    mat.diffuse_color = rgba
    MATS[name] = mat

def linear_to_srgb(value):
    return 12.92*value if value<=.0031308 else 1.055*(value**(1/2.4))-.055

def make_palette_image(name, color_space, channel_values):
    # Three rows/columns of constant 16px cells: UVs sample cell centres.
    # The buffer is saved as raw encoded RGB, then reloaded with its declared space.
    width=48
    image=bpy.data.images.new(name,width=width,height=width,alpha=False)
    image.colorspace_settings.name="Non-Color"
    pixels=[]
    names=list(PALETTE)
    for y in range(width):
        for x in range(width):
            slot=(y//16)*3+(x//16)
            pixels.extend((*channel_values(names[slot]),1.0))
    image.pixels=pixels
    image.filepath_raw=str(SOURCE/"textures"/(name+".png"))
    image.file_format="PNG"
    image.save()
    filepath=image.filepath_raw
    bpy.data.images.remove(image)
    image=bpy.data.images.load(filepath,check_existing=False)
    image.colorspace_settings.name=color_space
    return image

base_atlas=make_palette_image("palette_basecolor","sRGB",lambda name:tuple(linear_to_srgb(v) for v in PALETTE[name][0][:3]))
orm_atlas=make_palette_image("palette_metal_rough","Non-Color",lambda name:(1.0,PALETTE[name][2],PALETTE[name][1]))
emission_atlas=make_palette_image("palette_emission","sRGB",lambda name:tuple(linear_to_srgb(v*PALETTE[name][3]/1.5) for v in PALETTE[name][0][:3]))
atlas_material=bpy.data.materials.new("AW_PalettePBR")
atlas_material.use_nodes=True
atlas_nodes=atlas_material.node_tree.nodes
atlas_links=atlas_material.node_tree.links
bsdf=next(n for n in atlas_nodes if n.type=="BSDF_PRINCIPLED")
uvnode=atlas_nodes.new("ShaderNodeUVMap")
uvnode.uv_map="AW_PaletteUV"
texture_nodes=[]
for image in [base_atlas,orm_atlas,emission_atlas]:
    tex=atlas_nodes.new("ShaderNodeTexImage")
    tex.image=image
    tex.interpolation="Closest"
    atlas_links.new(uvnode.outputs["UV"],tex.inputs["Vector"])
    texture_nodes.append(tex)
atlas_links.new(texture_nodes[0].outputs["Color"],bsdf.inputs["Base Color"])
separate=atlas_nodes.new("ShaderNodeSeparateColor")
atlas_links.new(texture_nodes[1].outputs["Color"],separate.inputs["Color"])
atlas_links.new(separate.outputs["Green"],bsdf.inputs["Roughness"])
atlas_links.new(separate.outputs["Blue"],bsdf.inputs["Metallic"])
atlas_links.new(texture_nodes[2].outputs["Color"],bsdf.inputs["Emission Color"])
bsdf.inputs["Emission Strength"].default_value=1.5

ASSETS = []
ACTIVE = None

def group(name, parent=None, loc=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = loc
    return obj

def finish(obj, name, material, parent, bevel=0):
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("AuthoredEdge", "BEVEL")
        mod.width, mod.segments = bevel, 1
        mod.affect = "EDGES"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(MATS[material])
    obj.parent = parent or ACTIVE
    return obj

def box(name, loc, dims, mat="graphite", parent=None, bevel=.035, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.dimensions = dims
    return finish(obj, name, mat, parent, min(bevel, min(dims) * .16))

def cylinder(name, loc, radius, depth, mat="steel", parent=None, rot=(0, 0, 0), vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    return finish(bpy.context.object, name, mat, parent, min(.015,depth*.16,radius*.16) if radius>.06 else 0)

def sphere(name, loc, scale, mat="steel", parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=1, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    return finish(obj, name, mat, parent)

def bar(name, start, end, radius=.045, mat="steel", parent=None):
    a, b = Vector(start), Vector(end)
    obj = cylinder(name, (a+b)*.5, radius, (b-a).length, mat, parent)
    obj.rotation_euler = (b-a).to_track_quat("Z", "Y").to_euler()
    return obj

def arch(name, center, radius, width, mat="steel", parent=None, start=0, end=math.pi, count=12):
    pts = [(center[0]+radius*math.cos(start+i*(end-start)/count), center[1], center[2]+radius*math.sin(start+i*(end-start)/count)) for i in range(count+1)]
    for i in range(count):
        bar(name+str(i), pts[i], pts[i+1], width, mat, parent)

def vent(prefix, loc, width, height, count=5, parent=None):
    for i in range(count):
        box(prefix+str(i), (loc[0],loc[1],loc[2]-height/2+i*height/(count-1)), (width,.035,.035),"graphite",parent,0)

def asset(name, role, collision, status="authored_prototype"):
    global ACTIVE
    ACTIVE = group(name)
    ACTIVE["asset_id"] = name
    ACTIVE["front_axis"] = "+Y Blender / -Z glTF"
    ACTIVE["collision_role"] = collision
    ACTIVE["source_original"] = True
    ASSETS.append({"id":name,"role":role,"root":ACTIVE,"collision":collision,"status":status})
    return ACTIVE

def walk_track(obj, name, prop, values, frames=(1,7,13,19,25)):
    original = getattr(obj, prop).copy()
    for frame, value in zip(frames, values):
        setattr(obj, prop, value)
        obj.keyframe_insert(data_path=prop, frame=frame)
    action = obj.animation_data.action
    action.name = name+"_"+obj.name
    track = obj.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, action)
    obj.animation_data.action = None
    setattr(obj, prop, original)

def humanoid(name, enemy=False, heavy=False):
    asset(name,"player" if not enemy else "melee_enemy", "capsule")
    body = group(name+"_Body",ACTIVE, (0,0,0))
    color = "danger" if enemy else "orange"
    size = 1.35 if heavy else 1
    box("Pelvis",(0,0,.80),(.54,.35,.25),"graphite",body)
    box("TorsoShell",(0,0,1.22),(.68,.43,.67),color,body,.06)
    box("ChestHarness",(0,.244,1.26),(.39,.07,.43),"graphite",body)
    cylinder("ChestCoil",(0,.30,1.29),.15,.065,"steel",body,(math.pi/2,0,0))
    cylinder("ChestCore",(0,.344,1.29),.085,.022,"amber" if enemy else "cyan",body,(math.pi/2,0,0))
    for side in [-1,1]:
        box("ShoulderPlate",(side*.41,0,1.47),(.24,.47,.24),color,body)
        leg = group(name+("_LeftHip" if side<0 else "_RightHip"),ACTIVE,(side*.20,0,.84))
        cylinder("HipJoint",(0,0,-.04),.12,.25,"steel",leg,(0,math.pi/2,0))
        box("Thigh",(0,0,-.22),(.21,.24,.39),"graphite",leg)
        box("ShinArmor",(0,.01,-.52),(.25,.27,.32),color,leg)
        box("KneePad",(0,.16,-.41),(.20,.07,.15),"ivory",leg)
        box("Sole",(0,.065,-.75),(.32,.49,.16),"graphite",leg)
        box("ToeCap",(0,.25,-.70),(.28,.11,.11),"steel",leg)
        arm = group(name+("_LeftShoulder" if side<0 else "_RightShoulder"),ACTIVE,(side*.44,0,1.42))
        box("UpperArm",(side*.025,0,-.18),(.19,.23,.35),"graphite",arm)
        cylinder("ElbowPin",(side*.035,0,-.40),.10,.22,"steel",arm,(0,math.pi/2,0))
        box("Forearm",(side*.03,.045,-.55),(.23,.26,.29),color,arm)
        box("Hand",(side*.03,.06,-.76),(.17,.19,.15),"graphite",arm)
        if enemy:
            for offset in [-.07,.07]:
                bar("Claw",(offset,.17,-.71),(offset,.38,-.92),.035,"steel",arm)
        sign = side
        walk_track(leg,"Walk","rotation_euler",[(0,0,0),(sign*.42,0,0),(0,0,0),(-sign*.42,0,0),(0,0,0)])
        walk_track(arm,"Walk","rotation_euler",[(0,0,0),(-sign*.25,0,0),(0,0,0),(sign*.25,0,0),(0,0,0)])
    head = group(name+"_Head",ACTIVE,(0,0,1.70))
    cylinder("Neck",(0,0,-.10),.12,.18,"steel",head)
    box("Helmet",(0,0,.11),(.60,.41,.41),color,head,.07)
    box("LensRecess",(0,.22,.11),(.48,.07,.18),"graphite",head)
    box("Visor",(0,.265,.13),(.34,.025,.07),"amber" if enemy else "cyan",head,.009)
    box("HelmetBrow",(0,.225,.26),(.56,.09,.065),"ivory",head)
    box("LeftEarModule",(-.34,0,.12),(.10,.26,.24),"steel",head)
    bar("Antenna",(.20,-.05,.29),(.25,-.07,.61),.025,"steel",head)
    sphere("AntennaSignal",(.25,-.07,.62),(.04,.04,.04),"amber" if enemy else "cyan",head)
    box("Backpack",(0,-.34,1.25),(.43,.25,.54),"graphite",body)
    for side in [-1,1]:
        cylinder("Battery",(side*.26,-.33,1.23),.075,.43,"steel",body)
        cylinder("BatteryCap",(side*.26,-.33,1.47),.084,.065,color,body)
    vent("CoolingFin",(0,-.48,1.28),.27,.30,parent=body)
    walk_track(head,"Idle","rotation_euler",[(0,0,-.06),(0,0,0),(0,0,.06),(0,0,0),(0,0,-.06)])
    walk_track(body,"Idle","location",[(0,0,0),(0,0,.012),(0,0,.018),(0,0,.012),(0,0,0)])
    if heavy:
        ACTIVE.scale = (size,size,size)
        box("GuardianRearShield",(0,-.52,1.40),(1.07,.16,1.02),"danger",body,.09)
        arch("GuardianHalo",(0,-.52,1.89),.70,.06,"steel",body)
    return ACTIVE

humanoid("survivor_robot")
humanoid("scavenger",True)
humanoid("guardian",True,True)

asset("spitter","ranged_enemy","sphere")
cylinder("HoverBase",(0,0,.42),.37,.19,"graphite")
sphere("TankBody",(0,0,.80),(.52,.43,.45),"danger")
box("FrontPlate",(0,.32,.80),(.63,.18,.47),"graphite")
cylinder("EmitterBarrel",(0,.51,.80),.14,.35,"steel",rot=(math.pi/2,0,0))
cylinder("EmitterEye",(0,.70,.80),.09,.025,"amber",rot=(math.pi/2,0,0))
for side in [-1,1]:
    box("SideTank",(side*.44,-.04,.79),(.19,.35,.48),"ivory")
    bar("LandingLeg",(side*.27,0,.38),(side*.46,.18,.14),.065)
    box("Foot",(side*.48,.16,.11),(.26,.25,.11),"graphite")
for y in [-.24,.16]:
    bar("VentRail",(-.30,y,1.19),(.30,y,1.19),.035)

def rifle(name, tier):
    asset(name,"weapon_t"+str(tier),"none")
    box("Receiver",(0,0,.17),(.20,.60,.28),"graphite")
    box("UpperHousing",(0,.10,.36),(.24,.69,.10),"orange")
    box("Grip",(0,-.18,-.04),(.15,.16,.31),"graphite",rot=(.22,0,0))
    box("Stock",(0,-.47,.17),(.23,.34,.21),"ivory")
    cylinder("Barrel",(0,.55,.20),.065,.54,"steel",rot=(math.pi/2,0,0))
    for i in range(4):
        cylinder("CoilFin",(0,.29+i*.10,.20),.102,.035,"orange" if tier==1 else "cyan",rot=(math.pi/2,0,0))
    box("Sight",(0,.04,.46),(.095,.12,.12),"steel")
    box("SightLens",(0,.107,.46),(.06,.012,.055),"cyan")
    for side in [-1,1]:
        box("Capacitor",(side*.13,.12,.22),(.065,.28,.17),"cyan")
        if tier==2:
            bar("AnchorRelayRail",(side*.18,-.17,.34),(side*.18,.62,.34),.04,"steel")
            cylinder("RelayNode",(side*.18,.55,.34),.09,.06,"cyan")
    ACTIVE["attachment_axis"] = "front -Z, grip origin at y 0"
rifle("lightning_rifle_t1",1)
rifle("lightning_rifle_t2",2)

asset("conductive_anchor","conductive_gameplay_anchor","cylinder")
cylinder("Base",(0,0,.12),.42,.24,"graphite")
cylinder("CopperRing",(0,0,.26),.33,.08,"orange")
cylinder("Insulator",(0,0,.54),.16,.49,"ivory")
cylinder("Electrode",(0,0,.86),.20,.17,"steel")
sphere("Core",(0,0,.88),(.14,.14,.17),"cyan")
for angle in [0,2*math.pi/3,4*math.pi/3]:
    tip = (.44*math.cos(angle),.44*math.sin(angle),.04)
    bar("Support",(0,0,.21),tip,.06,"steel")
    box("Foot",tip,(.21,.19,.075),"orange")

asset("cargo_crate","resource_container","box")
box("CrateBody",(0,0,.46),(1.05,.83,.91),"orange",bevel=.06)
box("Lid",(0,0,.94),(1.10,.88,.12),"graphite")
for side in [-1,1]:
    box("EdgeRail",(side*.40,0,.52),(.095,.88,1.0),"steel")
    box("CornerFoot",(side*.43,0,.10),(.19,.90,.20),"graphite")
    box("Handle",(side*.58,0,.67),(.12,.34,.16),"steel")
box("Latch",(0,.46,.63),(.24,.08,.27),"graphite")
box("StatusLamp",(0,.507,.67),(.13,.021,.045),"cyan",bevel=0)

asset("barricade","cover_boundary","box")
box("Footing",(0,0,.13),(2.55,.70,.26),"concrete")
box("CoverPlate",(0,0,.71),(2.32,.28,1.15),"graphite")
box("UpperEdge",(0,0,1.30),(2.55,.36,.12),"steel")
for x in [-.90,-.45,0,.45,.90]:
    box("WarningStripe",(x,.158,.87),(.13,.025,.59),"orange",bevel=0,rot=(0,.31,0))
for side in [-1,1]:
    box("Post",(side*1.10,0,.64),(.16,.39,1.28),"steel")

asset("pump_station","camp_pump_workshop","box_combination")
box("Foundation",(0,0,.16),(7.0,4.8,.32),"concrete",bevel=.06)
box("MainWall",(0,-.10,1.75),(6.7,3.65,3.15),"graphite",bevel=.10)
box("Roof",(0,-.10,3.43),(7.25,4.2,.24),"steel",bevel=.07)
for x in [-3.1,-1.55,0,1.55,3.1]:
    box("WallPillar",(x,1.80,1.74),(.16,.21,3.10),"steel")
box("DoorRecess",(0,1.78,1.32),(1.44,.11,2.48),"concrete")
box("Door",(0,1.89,1.30),(1.24,.07,2.32),"orange")
box("DoorSplit",(0,1.934,1.30),(.025,.011,2.1),"graphite",bevel=0)
box("DoorWindow",(0,1.95,1.75),(.74,.021,.31),"cyan")
box("DoorAwning",(0,2.12,2.80),(2.20,1.0,.18),"orange")
for x in [-2.24,2.24]:
    box("WindowRecess",(x,1.83,1.90),(1.07,.08,.68),"graphite")
    box("Window",(x,1.88,1.90),(.92,.025,.50),"amber")
    for split in [-.24,.24]:
        box("WindowMullion",(x+split,1.91,1.90),(.055,.02,.50),"steel",bevel=0)
    vent("Intake",(x,1.88,.80),1.07,.38,count=6)
for side in [-1,1]:
    cylinder("SideReservoir",(side*3.17,-.16,2.22),.43,2.21,"orange",vertices=16)
    cylinder("TankRim",(side*3.17,-.16,3.36),.46,.13,"steel",vertices=16)
    bar("FeedPipe",(side*3.17,.06,1.10),(side*3.17,1.96,1.10),.13)
    cylinder("Valve",(side*3.17,1.95,1.10),.24,.055,"orange",rot=(math.pi/2,0,0))
for x in [-2.72,-1.36,0,1.36,2.72]:
    box("RoofRib",(x,-.10,3.60),(.045,4.00,.095),"graphite",bevel=0)
box("RoofServiceUnit",(-1.45,-.46,3.94),(1.24,1.4,.66),"ivory")
for i in range(6):
    box("FanFin",(-1.45,-1.05+i*.21,4.30),(1.03,.075,.025),"graphite",bevel=0)
bar("BeaconMast",(2.20,-.97,3.58),(2.20,-.97,4.97),.06)
sphere("Beacon",(2.20,-.97,5.0),(.13,.13,.16),"cyan")
for angle in [0,math.pi/2,math.pi,3*math.pi/2]:
    bar("Antenna",(2.20,-.97,4.77),(2.20+.43*math.cos(angle),-.97+.43*math.sin(angle),4.87),.028)

def descendants(root):
    return [root] + [child for child in root.children_recursive]

def geometry_record(root):
    meshes = [o for o in descendants(root) if o.type=="MESH"]
    points = [o.matrix_world @ vertex.co for o in meshes for vertex in o.data.vertices]
    lower = [min(p[i] for p in points) for i in range(3)]
    upper = [max(p[i] for p in points) for i in range(3)]
    tris, vertices, nonfinite, degenerate = 0,0,0,0
    for obj in meshes:
        mesh = obj.data
        mesh.calc_loop_triangles()
        tris += len(mesh.loop_triangles)
        vertices += len(mesh.vertices)
        nonfinite += sum(not all(math.isfinite(v) for v in vertex.co) for vertex in mesh.vertices)
        degenerate += sum(tri.area < 1e-10 for tri in mesh.loop_triangles)
    return {"triangles":tris,"vertices":vertices,"meshes":len(meshes),"materials":sorted({m.name for o in meshes for m in o.data.materials}),"bounds_blender_m":{"min":lower,"max":upper},"bounds_godot_m":{"min":[lower[0],lower[2],-upper[1]],"max":[upper[0],upper[2],-lower[1]]},"bounds_method":"actual transformed mesh vertices at origin, imported root scale retained; frame 1","nonfinite_vertices":nonfinite,"degenerate_triangles":degenerate}

def atlas_surface(mesh_object):
    mesh=mesh_object.data
    roles=[mesh.materials[poly.material_index].name.removeprefix("AW_") for poly in mesh.polygons]
    original=mesh.uv_layers[0]
    original.name="AW_OriginalUV"
    palette_uv=mesh.uv_layers.new(name="AW_PaletteUV")
    palette_slots=list(PALETTE)
    for poly,role in zip(mesh.polygons,roles):
        slot=palette_slots.index(role)
        uv=((slot%3+.5)/3,(slot//3+.5)/3)
        for loop_index in poly.loop_indices:
            palette_uv.data[loop_index].uv=uv
        poly.material_index=0
    mesh.materials.clear()
    mesh.materials.append(atlas_material)
    mesh.uv_layers.active=palette_uv
    palette_uv.active_render=True
    mesh_object["source_palette_roles"]=sorted(set(roles))

scene.frame_set(1)
bpy.context.view_layer.update()
for entry in ASSETS:
    root = entry["root"]
    # Merge static shapes at each motion pivot. Preserve articulated pivot nodes.
    for pivot in [o for o in descendants(root) if o.type=="EMPTY"]:
        surfaces = [o for o in pivot.children if o.type=="MESH"]
        if len(surfaces)>1:
            bpy.ops.object.select_all(action="DESELECT")
            for obj in surfaces:
                obj.select_set(True)
            bpy.context.view_layer.objects.active=surfaces[0]
            bpy.ops.object.join()
            bpy.context.object.name=pivot.name+"_Surface"
    for obj in descendants(root):
        if obj.type=="MESH":
            atlas_surface(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in descendants(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    record = geometry_record(root)
    if record["nonfinite_vertices"] or record["degenerate_triangles"]:
        raise RuntimeError(f"Geometry validation failed: {entry['id']} {record}")
    outfile = EXPORT / (entry["id"]+".glb")
    # Runtime needs the palette UV only. Keep original editable UVs in source,
    # export from derived mesh copies, and always restore source ownership.
    derived=[]
    try:
        for obj in descendants(root):
            if obj.type=="MESH":
                original=obj.data
                runtime=original.copy()
                runtime.name=obj.name+"_RuntimeMesh"
                runtime.uv_layers.remove(runtime.uv_layers["AW_OriginalUV"])
                obj.data=runtime
                derived.append((obj,original,runtime))
        bpy.ops.export_scene.gltf(filepath=str(outfile),export_format="GLB",use_selection=True,export_extras=True,export_animations=True,export_animation_mode="NLA_TRACKS",export_apply=True,export_tangents=False)
    finally:
        for obj,original,runtime in derived:
            obj.data=original
            bpy.data.meshes.remove(runtime)
    entry["geometry"] = record
    if entry["id"]=="pump_station":
        entry["walkable_intent"]="closed workshop exterior; visual door is closed and no interior is traversable"
        entry["collision_shapes_godot_m"]=[{"type":"box","size":[7.26,3.6,4.8],"local_offset":[0,1.8,0]}]
    entry["runtime_file"] = str(outfile.relative_to(ROOT)).replace("\\","/")
    entry["sha256"] = hashlib.sha256(outfile.read_bytes()).hexdigest()
    entry["bytes"] = outfile.stat().st_size
    entry["source"] = "source-assets/blender/asset_family.blend"
    entry["license"] = "original project-authored geometry and materials; no third-party source assets"
    entry["clips_expected"] = ["Idle","Walk"] if entry["id"] in ["survivor_robot","scavenger","guardian"] else []
    del entry["root"]

# Preserve a readable original source catalog; runtime exports were made at origin.
positions = {"survivor_robot":(-4,0,0),"scavenger":(-2,0,0),"guardian":(0,0,0),"spitter":(2,0,0),"lightning_rifle_t1":(4,0,.1),"lightning_rifle_t2":(5.5,0,.1),"conductive_anchor":(7,0,0),"cargo_crate":(-3,3,0),"barricade":(0,3,0),"pump_station":(3,8,0)}
for name, pos in positions.items():
    bpy.data.objects[name].location = pos

world = bpy.data.worlds.new("AW_Studio")
world.use_nodes = True
next(n for n in world.node_tree.nodes if n.type=="BACKGROUND").inputs[0].default_value = (.075,.095,.11,1)
next(n for n in world.node_tree.nodes if n.type=="BACKGROUND").inputs[1].default_value = .7
scene.world = world
for name,loc,power,size in [("Key",(1,-7,12),1600,7),("Fill",(-8,3,8),1000,6),("Rim",(8,12,10),1800,5)]:
    bpy.ops.object.light_add(type="AREA",location=loc)
    light=bpy.context.object
    light.name=name
    light.data.energy=power
    light.data.shape="DISK"
    light.data.size=size
    light.rotation_euler=(Vector((0,3,1))-light.location).to_track_quat("-Z","Y").to_euler()
bpy.ops.object.camera_add(location=(14,-17,17))
camera=bpy.context.object
camera.name="AssetReviewCamera"
camera.rotation_euler=(Vector((1,4,1.3))-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.type="ORTHO"
camera.data.ortho_scale=19
scene.camera=camera
scene.render.resolution_x,scene.render.resolution_y=1600,1000
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.render.filepath=str(SOURCE / "previews" / "asset_family.png")
for image in [base_atlas,orm_atlas,emission_atlas]:
    image.pack()
    image.filepath="//../textures/"+Path(image.filepath).name
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "blender" / "asset_family.blend"))
manifest={"schema_version":1,"created":"2026-10-13","engine":"Godot 4.7.2","dcc":"Blender "+bpy.app.version_string,"camera":"3D isometric, native desktop + Android later","units":"metres; glTF Y-up, forward -Z","visual_direction":"rain-soaked repair district, warm ochre housings, graphite structure, cyan functional light; enemy amber optics and oxide-red armor","source_code":"source-assets/scripts/build_asset_family.py","pbr_palette":{"original":True,"cell_size":16,"atlas_size":[48,48],"roles":list(PALETTE),"maps":["basecolor(sRGB)","metal/rough(non-color)","emission(sRGB)"],"static_primitives_per_mesh":1,"source_uv_preserved":True},"approval":"source geometry validated; in-engine visual/performance/Android acceptance pending","assets":ASSETS}
(SOURCE / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"exported":len(ASSETS),"total_triangles":sum(e["geometry"]["triangles"] for e in ASSETS),"source_file":str(SOURCE / "blender" / "asset_family.blend"),"export_dir":str(EXPORT)},indent=2))
