"""Generate self-contained runtime art/collision/layout data from verified sources.

The game reads only game/config/world_assets.json, never these source manifests.
"""
from pathlib import Path
import json
import math

ROOT=Path(__file__).resolve().parents[2]
original=json.loads((ROOT/"source-assets/manifest.json").read_text(encoding="utf-8"))
district=json.loads((ROOT/"source-assets/district-manifest.json").read_text(encoding="utf-8"))
occluders={"pump_station","ruin_wall_full","ruin_wall_broken","conduit_gateway","district_facade","maintenance_shelter","reservoir_tank"}
definitions={}
for asset in original["assets"]+district["assets"]:
    bounds=asset.get("bounds_godot_m",asset["geometry"].get("bounds_godot_m"))
    collision=asset.get("collision_shapes_godot_m",[])
    if asset["id"]=="cargo_crate":collision=[{"type":"box","size":[1.28,1.02,.98],"local_offset":[0,.51,-.034]}]
    if asset["id"]=="barricade":collision=[{"type":"box","size":[2.55,1.36,.70],"local_offset":[0,.68,0]}]
    if asset["id"]=="pump_station":collision=[{"type":"box","size":[7.26,3.60,4.80],"local_offset":[0,1.80,0]}]
    definitions[asset["id"]]={"path":"res://"+asset["runtime_file"].removeprefix("game/"),"bounds_m":bounds,"collision_shapes":collision,"camera_occluder":asset["id"] in occluders,"walkable_intent":asset.get("walkable_intent","external visual; collision supplied by owning gameplay entity")}

def place(name,asset,position,yaw=0,scale=(1,1,1),collision=True):
    return {"id":name,"asset":asset,"position":list(position),"yaw":yaw,"scale":list(scale),"collision":collision}

common=[place("RealmGate","conduit_gateway",(0,0,-16),math.pi),place("WestPump","pump_station",(-10,0,-14),math.pi),place("EastPump","pump_station",(11,0,-14),math.pi),place("CampShelter","maintenance_shelter",(-8,0,12),-math.pi/2),place("MaintenanceBench","cargo_crate",(-3,0,12)),place("CenterCoverWest","barricade",(-2,0,-5),.10),place("CenterCoverEast","barricade",(5,0,1),-.50),place("RealmAnchor","conductive_anchor",(0,.03,-13),0,collision=False)]
for side in [-1,1]:
    for i,z in enumerate(range(-14,15,4)):
        common.append(place(f"SideWall_{side}_{i}","ruin_wall_broken" if i in [1,5] else "ruin_wall_full",(side*16,0,z),side*math.pi/2))
    for i,z in enumerate(range(-12,14,4)):
        common.append(place(f"Drain_{side}_{i}","drain_grate",(side*13.75,-definitions["drain_grate"]["bounds_m"]["max"][1]+.001,z),collision=False))
for i,x in enumerate([-14,-10,-6,6,10,14]):common.append(place(f"RearWall_{i}","ruin_wall_full",(x,0,-16),math.pi))
for i,x in enumerate(range(-14,15,4)):common.append(place(f"SouthParapet_{i}","ruin_wall_broken",(x,0,16),0,(1,.26,1)))
for i,x in enumerate([-16.0,-7.0,7.0,16.0]):
    common.append(place(f"RearDistrict_{i}","district_facade",(x,0,-21.2),math.pi,(1.0,1.0+(i%2)*.18,1.0)))
    common.append(place(f"RooftopUnit_{i}","ventilation_unit",(x-.7,6.4+(i%2)*1.2,-21.5),math.pi,collision=False))
for i,(x,z) in enumerate([(-14,7),(-13.8,-5),(13.8,8),(14,-8),(-6.4,14.6)]):
    common.append(place(f"WallPlanter_{i}","planter_overgrowth",(x,0,z),i*.36))
for i,(x,z) in enumerate([(-12.5,10.0),(12.8,12.7),(-14.1,-7.8),(13.7,-1.8),(-10,7),(10,5)]):
    common.append(place(f"Debris_{i}","scattered_debris",(x,-.025,z),i*.57,collision=False))

rain=[place("WestCargo","cargo_crate",(-9,0,5),-.34),place("EastCargo","cargo_crate",(10,0,4),.23),place("WestRouteCargo","cargo_crate",(-7,0,-5),.19),place("EastRouteCargo","cargo_crate",(9,0,-3),-.21),place("WestLowPipe","pipe_run",(-14.1,0,2),math.pi/2),place("EastLowPipe","pipe_run",(14.1,0,-1),math.pi/2),place("WestTank","reservoir_tank",(-13.9,0,10)),place("EastTank","reservoir_tank",(14,0,3)),place("CampLamp","industrial_lamp",(-6.1,0,13.9),-math.pi/2),place("EastLamp","industrial_lamp",(12.1,0,8.4)),place("GateLamp","industrial_lamp",(-4.7,0,-13.7),math.pi)]
conduit=[place("ConduitCargoA","cargo_crate",(-10.5,0,4.5),-.2),place("ConduitCargoB","cargo_crate",(10.8,0,3.0),.25),place("ConduitPipeWest","pipe_run",(-13.7,0,1.2),math.pi/2),place("ConduitPipeEastA","pipe_run",(13.6,0,-2.0),math.pi/2),place("ConduitPipeEastB","pipe_run",(13.6,0,-7.5),math.pi/2),place("ConduitTankWest","reservoir_tank",(-13.8,0,8)),place("ConduitTankEastA","reservoir_tank",(13.0,0,6.5)),place("ConduitTankEastB","reservoir_tank",(13.0,0,9.7)),place("ConduitService","ventilation_unit",(-12.3,0,-6.3),-math.pi/2),place("ConduitRelayWest","conductive_anchor",(-11.8,.03,-8.0),0,(1.3,1.3,1.3),False),place("ConduitRelayEast","conductive_anchor",(11.8,.03,-4.0),0,(1.3,1.3,1.3),False),place("ConduitLampA","industrial_lamp",(-6.1,0,13.9),-math.pi/2),place("ConduitLampB","industrial_lamp",(12.2,0,-11.0),math.pi)]
data={"schema_version":1,"units":"metres; Y-up / model forward -Z","model_definitions":definitions,"anchors":{"camp":[0,0,12],"bench":[-3,0,12],"exit":[0,0,9],"gate":[0,0,-13]},"floor":{"surface_y":0.0,"extent":34.0,"physics_thickness":.4,"foundation_clearance":.002,"boundary_half_extent":16.1,"boundary_thickness":.3,"side_wall_height":4.2,"south_wall_height":1.1,"tile_asset":"paving_tiles","tile_spacing":2.0,"tile_count_axis":16,"tile_origin_y":-definitions["paving_tiles"]["bounds_m"]["max"][1],"seed":78431,"floor_material":"res://presentation/courtyard_floor.tres","wet_material":"res://presentation/wet_surface.tres"},"resource_locations":[{"type":"metal","number":"01","position":[-11,0,-1]},{"type":"metal","number":"02","position":[11,0,-6]},{"type":"metal","number":"03","position":[-8,0,-10]},{"type":"crystal","number":"01","position":[2,0,-12]}],"common_placements":common,"regions":{"rain_court":{"display_name":"雨庭","resource_prefix":"rain","metal_type":"scrap","lighting_profile":{"ambient_color":"53676b","ambient_energy":.30,"sun_color":"eee0c1","sun_energy":1.15,"fog_color":"537076","fog_density":.006,"water_color":"324447","ground_tint":"919a95","ground_roughness":.55},"placements":rain,"practical_lights":[{"position":[-6.3,2.8,12.0],"color":"ffca8c","energy":1.4,"range":7.5},{"position":[12.1,3.1,8.0],"color":"ffc992","energy":.9,"range":6.0},{"position":[0,2.4,-13.7],"color":"70d9e0","energy":.9,"range":5.0}],"puddles":[{"center":[-8,.011,-6],"size":[4.2,2.7],"seed":18},{"center":[8,.012,2],"size":[4.4,2.4],"seed":25},{"center":[1,.014,-7],"size":[3.1,2.2],"seed":32},{"center":[-2,.012,5],"size":[3.2,1.9],"seed":49}]},"conduit_yard":{"display_name":"导体工场","resource_prefix":"conduit","metal_type":"alloy","lighting_profile":{"ambient_color":"405963","ambient_energy":.26,"sun_color":"c9dbdc","sun_energy":1.05,"fog_color":"456b77","fog_density":.007,"water_color":"24434b","ground_tint":"7d8e95","ground_roughness":.42},"placements":conduit,"practical_lights":[{"position":[-6.3,2.8,12],"color":"ffbf79","energy":1.2,"range":7.0},{"position":[11.6,2.2,-4],"color":"60ddeb","energy":1.15,"range":6.0},{"position":[-11.5,2.2,-8],"color":"70e1ef","energy":1.15,"range":6.0}],"puddles":[{"center":[-9,.013,3],"size":[4.7,2.1],"seed":61},{"center":[6,.014,-5],"size":[4.4,2.8],"seed":68},{"center":[1,.011,3],"size":[3.2,1.6],"seed":81}]}}}
path=ROOT/"game/config/world_assets.json"
path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"models":len(definitions),"common_placements":len(common),"rain_placements":len(rain),"conduit_placements":len(conduit),"path":str(path)},indent=2))
