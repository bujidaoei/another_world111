"""Native Blender authoring helpers for the original district module library."""
from pathlib import Path
import bpy
import bmesh
import math
import json
import hashlib
from mathutils import Vector


class ModuleLibrary:
    def __init__(self, root: Path, scene_name: str):
        if not bpy.context.scene.get("another_world_dedicated_session"):
            raise RuntimeError("Refusing work outside a project-owned Blender session")
        self.root=root
        self.source=root/"source-assets"
        self.output=root/"game/assets/models"
        self.output.mkdir(parents=True,exist_ok=True)
        scene=bpy.data.scenes.get(scene_name)
        if scene:
            if not scene.get("another_world_dedicated_session"):
                raise RuntimeError("Existing scene is not project-owned")
            for obj in list(scene.objects):
                if len(obj.users_scene)!=1:
                    raise RuntimeError("Module scene has externally shared objects")
                bpy.data.objects.remove(obj,do_unlink=True)
        else:
            scene=bpy.data.scenes.new(scene_name)
        scene["another_world_dedicated_session"]=True
        scene.unit_settings.system="METRIC"
        scene.unit_settings.scale_length=1.0
        bpy.context.window.scene=scene
        self.scene=scene
        self.roles=json.loads((self.source/"art-palette.json").read_text(encoding="utf-8"))["roles"]
        self.materials={}
        for name,values in self.roles.items():
            mat=bpy.data.materials.get("AW_"+name)
            if mat is None:
                mat=bpy.data.materials.new("AW_"+name)
                mat.use_nodes=True
                bsdf=next(n for n in mat.node_tree.nodes if n.type=="BSDF_PRINCIPLED")
                bsdf.inputs["Base Color"].default_value=values["base_color_linear"]
                bsdf.inputs["Metallic"].default_value=values["metallic"]
                bsdf.inputs["Roughness"].default_value=values["roughness"]
                bsdf.inputs["Emission Color"].default_value=values["base_color_linear"]
                bsdf.inputs["Emission Strength"].default_value=values["emission"]
            self.materials[name]=mat
        self.atlas=bpy.data.materials.get("AW_PalettePBR")
        if self.atlas is None:
            source=self.source/"blender/asset_family.blend"
            with bpy.data.libraries.load(str(source),link=False) as (data_from,data_to):
                if "AW_PalettePBR" not in data_from.materials:
                    raise RuntimeError("Original PBR palette missing in source library")
                data_to.materials=["AW_PalettePBR"]
            self.atlas=data_to.materials[0]
        self.assets=[]
        self.active=None

    def asset(self,name,role,collision_shapes,walkable_intent):
        root=bpy.data.objects.new(name,None)
        self.scene.collection.objects.link(root)
        root["asset_id"]=name
        root["source_original"]=True
        root["front_axis"]="+Y Blender / -Z Godot"
        self.active=root
        self.assets.append({"id":name,"role":role,"collision_shapes_godot_m":collision_shapes,"walkable_intent":walkable_intent,"root":root,"status":"authored_prototype_for_engine_review"})
        return root

    def _finish(self,obj,name,material,bevel=0):
        obj.name=self.active.name+"_"+name
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        if bevel:
            mod=obj.modifiers.new("AuthoredEdge","BEVEL")
            mod.width=bevel
            mod.segments=1
            bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.data.materials.append(self.materials[material])
        obj.parent=self.active
        return obj

    def box(self,name,loc,dims,mat="steel",bevel=.025,rot=(0,0,0)):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc,rotation=rot)
        obj=bpy.context.object
        obj.dimensions=dims
        return self._finish(obj,name,mat,min(bevel,min(dims)*.16))

    def cylinder(self,name,loc,radius,depth,mat="steel",rot=(0,0,0),vertices=12):
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc,rotation=rot)
        return self._finish(bpy.context.object,name,mat,min(.012,depth*.16,radius*.16))

    def bar(self,name,a,b,radius=.035,mat="steel",vertices=10):
        start,end=Vector(a),Vector(b)
        obj=self.cylinder(name,(start+end)*.5,radius,(end-start).length,mat,vertices=vertices)
        obj.rotation_euler=(end-start).to_track_quat("Z","Y").to_euler()
        return obj

    def profile(self,name,xz_points,depth,mat="concrete",y=0,bevel=.025):
        n=len(xz_points)
        verts=[(x,y-depth*.5,z) for x,z in xz_points]+[(x,y+depth*.5,z) for x,z in xz_points]
        faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
        faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
        mesh=bpy.data.meshes.new(self.active.name+"_"+name)
        mesh.from_pydata(verts,[],faces)
        mesh.update()
        bm=bmesh.new();bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(mesh);bm.free()
        obj=bpy.data.objects.new(name,mesh)
        self.scene.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True);bpy.context.view_layer.objects.active=obj
        return self._finish(obj,name,mat,bevel)

    def leaf(self,name,center,width,length,angle=0):
        # Opaque double-sided closed leaf prism avoids alpha overdraw and dangling edges.
        obj=self.profile(name,[(-width*.5,0),(0,length), (width*.5,0),(0,-length*.12)],.018,"moss",bevel=0)
        obj.location=center
        obj.rotation_euler=(.80,angle*.2,angle)
        return obj

    def vent(self,name,loc,width,height,count=7):
        for i in range(count):
            self.box(name+str(i),(loc[0],loc[1],loc[2]-height*.5+i*height/(count-1)),(width,.045,.045),"graphite",0)

    def export(self,ids=None):
        exported=[]
        for entry in self.assets:
            if ids and entry["id"] not in ids:
                continue
            root=entry["root"]
            bpy.context.view_layer.update()
            surfaces=[o for o in root.children_recursive if o.type=="MESH"]
            bpy.ops.object.select_all(action="DESELECT")
            for obj in surfaces:obj.select_set(True)
            bpy.context.view_layer.objects.active=surfaces[0]
            bpy.ops.object.join()
            obj=bpy.context.object
            obj.name=root.name+"_Surface"
            obj.data.name=root.name+"_Mesh"
            mesh=obj.data
            uv=mesh.uv_layers.get("AW_PaletteUV") or mesh.uv_layers.new(name="AW_PaletteUV")
            roles=list(self.roles)
            for poly in mesh.polygons:
                role=mesh.materials[poly.material_index].name.removeprefix("AW_").split(".")[0]
                slot=roles.index(role)
                for loop in poly.loop_indices:uv.data[loop].uv=((slot%3+.5)/3,(slot//3+.5)/3)
                poly.material_index=0
            for layer in list(mesh.uv_layers):
                if layer!=uv:mesh.uv_layers.remove(layer)
            mesh.uv_layers.active=uv
            uv.active_render=True
            mesh.materials.clear();mesh.materials.append(self.atlas)
            mesh.calc_loop_triangles()
            bpy.context.view_layer.update()
            bm=bmesh.new();bm.from_mesh(mesh)
            audit={"triangles":len(mesh.loop_triangles),"vertices":len(mesh.vertices),"meshes":1,"materials":1,"nonmanifold_edges":sum(not edge.is_manifold for edge in bm.edges),"loose_vertices":sum(not vertex.link_edges for vertex in bm.verts),"degenerate_triangles":sum(t.area<1e-10 for t in mesh.loop_triangles),"nonfinite_vertices":sum(not all(math.isfinite(v) for v in vertex.co) for vertex in mesh.vertices)}
            bm.free()
            if any(audit[k] for k in ["nonmanifold_edges","loose_vertices","degenerate_triangles","nonfinite_vertices"]):
                raise RuntimeError(f"Geometry audit failed for {entry['id']}: {audit}")
            points=[obj.matrix_world@vertex.co for vertex in mesh.vertices]
            low=[min(p[i] for p in points) for i in range(3)]
            high=[max(p[i] for p in points) for i in range(3)]
            entry["bounds_blender_m"]={"min":low,"max":high}
            entry["bounds_godot_m"]={"min":[low[0],low[2],-high[1]],"max":[high[0],high[2],-low[1]]}
            entry["geometry"]=audit
            path=self.output/(entry["id"]+".glb")
            root.select_set(True)
            bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,export_animations=False,export_extras=True,export_apply=True,export_tangents=False)
            entry["runtime_file"]=str(path.relative_to(self.root)).replace("\\","/")
            entry["sha256"]=hashlib.sha256(path.read_bytes()).hexdigest()
            entry["bytes"]=path.stat().st_size
            exported.append(entry)
        return exported

    def save(self,exported):
        for i,entry in enumerate(self.assets):
            entry["root"].location=(i%4*10,i//4*9,0)
        path=self.source/"blender/district_modules.blend"
        for node in self.atlas.node_tree.nodes:
            if node.type=="TEX_IMAGE" and node.image:
                node.image.pack()
        self.scene["module_source"]="source-assets/scripts/build_district_modules.py"
        bpy.ops.wm.save_as_mainfile(filepath=str(path))
        records=[]
        for entry in exported:
            record={k:v for k,v in entry.items() if k!="root"}
            record["source"]="source-assets/blender/district_modules.blend"
            record["license"]="original project-authored geometry; existing original PBR palette"
            record["clips_expected"]=[]
            records.append(record)
        manifest={"schema_version":1,"created":"2026-10-13","source_code":"source-assets/scripts/build_district_modules.py","engine":"Godot 4.7.2","dcc":bpy.app.version_string,"units":"metres; Godot Y-up / forward -Z","pbr_palette":{"atlas_size":[48,48],"maps":3,"materials":1},"approval":"authored source and technical geometry gates; actual game, mobile and final art acceptance pending","assets":records}
        (self.source/"district-manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
        print(json.dumps({"exported":len(records),"triangles":sum(r["geometry"]["triangles"] for r in records),"source":str(path)},indent=2))
