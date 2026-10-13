"""Build an original modular repair-district kit through native Blender MCP."""
from pathlib import Path
import sys
import math
import argparse

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
from mesh_authoring import ModuleLibrary


def shape(size,offset):
    return {"type":"box","size":list(size),"local_offset":list(offset)}


def wall_full(lib):
    lib.asset("ruin_wall_full","fortified industrial boundary",[shape((4.0,4.45,.70),(0,2.225,0)),shape((4.30,.40,1.05),(0,.20,0))],"closed wall, no traversal; decorate inside a real boundary")
    lib.profile("WallMass",[(-2,0),(2,0),(2,4.10),(1.63,4.16),(1.46,3.99),(.60,4.22),(.30,4.07),(-.60,4.32),(-1.04,4.14),(-2,4.35)],.60,"concrete")
    lib.box("Foundation",(0,0,.20),(4.30,1.05,.40),"graphite",.05)
    for side in [-1,1]:
        lib.box("Buttress",(side*1.74,.03,2.15),(.40,1.0,4.30),"steel",.045)
        lib.box("Capstone",(side*1.74,.05,4.35),(.62,1.07,.23),"concrete",.04,rot=(0,side*.05,0))
        for z in [.75,2.15,3.25]:
            lib.box("Brace",(side*1.74,.56,z),(.58,.17,.21),"graphite")
    for i in range(6):
        lib.box("PatchPlate",(-1.18+i*.47,.345,1.15+(i%2)*.065),(.43,.085,1.6),"graphite",.018)
        lib.box("PlateEdge",(-1.18+i*.47,.397,1.15+(i%2)*.065),(.027,.019,1.45),"steel",0)
    lib.bar("TopPipe",(-1.46,.54,3.12),(1.43,.54,3.12),.075)
    for x in [-1.25,-.35,.45,1.22]:
        lib.box("PipeBracket",(x,.43,3.12),(.13,.28,.30),"orange",.016)
    lib.vent("Duct",(.44,.44,2.5),.77,.34,6)
    lib.box("SignalRecess",(-.84,.40,2.72),(.57,.18,.29),"graphite")
    lib.box("Signal",(-.84,.506,2.72),(.34,.025,.055),"cyan",.005)
    for i in range(3):
        lib.profile("Fracture"+str(i),[(-1.55+i*.46,3.55),(-1.49+i*.46,3.75),(-1.37+i*.46,3.88),(-1.46+i*.46,3.60)],.024,"graphite",y=.315,bevel=0)


def wall_broken(lib):
    lib.asset("ruin_wall_broken","damaged closed boundary",[shape((4.0,3.30,.65),(0,1.65,0)),shape((4.2,.3,1.0),(0,.15,0))],"closed damaged wall; top damage is not a ground-level doorway; collision may remain a continuous level boundary")
    lib.profile("BrokenMass",[(-2,0),(2,0),(2,2.45),(1.36,2.65),(1.18,2.20),(.75,2.42),(.60,2.98),(-.20,2.95),(-.50,3.52),(-1.07,3.82),(-1.32,3.32),(-2,3.35)],.60,"concrete")
    lib.box("Footing",(0,0,.15),(4.2,1,.3),"graphite",.04)
    for x,height in [(-1.73,3.4),(1.73,2.45)]:
        lib.box("Support",(x,0,height*.5),(.42,.95,height),"steel")
    for i in range(4):
        lib.box("OldArmor",(-1.23+i*.69,.355,1.23),(.59,.12,1.83-(i%2)*.4),"graphite")
    for i in range(4):
        x=-.40+i*.26
        lib.bar("ExposedRebar",(x,.05,2.5),(x+.09,.01,3.55-i*.16),.025,"steel",8)
    for a,b in [((-1.37,.46,2.90),(-.3,.55,2.25)),((-.3,.55,2.25),(1.32,.48,2.32))]:
        lib.bar("DamagedCable",a,b,.039,"graphite",8)
    for i in range(4):
        lib.box("GroundRubble",(-1.55+i*.97,.61,.16),(.39,.39,.31),"concrete",.04,rot=(.1,.15,i*.38))


def gateway(lib):
    lib.asset("conduit_gateway","closed realm conduit gate",[shape((6.6,5.25,1.2),(0,2.625,0))],"closed grille door; signal interaction only, no ground traversal opening at this region boundary")
    for side in [-1,1]:
        x=side*2.45
        lib.box("GatePier",(x,0,2.35),(1.10,1.40,4.70),"concrete",.08)
        lib.box("PierArmor",(x,.78,2.35),(.58,.20,3.95),"graphite",.045)
        for z in [.50,3.35,4.48]:
            lib.box("PierBand",(x,.05,z),(1.40,1.53,.23),"steel",.03)
        lib.box("SignalRail",(x,.92,2.63),(.075,.035,2.30),"cyan",.01)
        lib.box("ShoulderFrame",(side*3.08,.04,2.10),(.21,1.27,3.90),"graphite")
        lib.bar("FlankPipe",(side*2.9,.79,.37),(side*2.9,.79,4.74),.08,"orange")
    lib.box("Lintel",(0,0,4.76),(6.65,1.65,.55),"graphite",.065)
    for x in [-2,-1,0,1,2]:
        lib.box("RoofCap",(x,-.04,5.07),(.91,1.82,.23),"concrete",.035,rot=(0,.025*x,.02*x))
    lib.box("ClosedDoor",(0,-.08,1.92),(3.85,.23,3.80),"graphite",.025)
    for x in [-1.60,-1.20,-.80,-.40,0,.40,.80,1.20,1.60]:
        lib.box("DoorRib",(x,.12,1.96),(.12,.13,3.63),"steel",.015)
    for z in [.48,1.54,2.60,3.65]:
        lib.box("DoorBar",(0,.20,z),(3.7,.10,.13),"steel",.015)
    lib.box("InterfacePlate",(0,.295,2.32),(1.13,.12,.87),"orange",.04)
    lib.box("InterfaceInset",(0,.372,2.32),(.87,.065,.60),"graphite",.02)
    lib.box("InterfaceSignal",(0,.412,2.32),(.52,.025,.13),"cyan",.009)
    lib.bar("HeaderCable",(-1.8,.85,4.34),(1.8,.85,4.34),.06)


def paving(lib):
    lib.asset("paving_tiles","2m modular worn courtyard paving",[],"walkable surface decoration; main flat ground supplies continuous collision")
    lib.box("Foundation",(0,0,.02),(2,2,.04),"graphite",0)
    for i,(x,y,w,h,angle) in enumerate([(-.50,-.51,.93,.94,.005),(.50,-.49,.94,.96,-.008),(-.49,.49,.95,.94,.012),(.50,.51,.93,.93,-.003)]):
        lib.box("WornSlab"+str(i),(x,y,.07+(i%2)*.006),(w,h,.10),"concrete",.018,rot=(0,0,angle))
    for i in range(3):
        lib.box("RepairStaple",(-.22+i*.07,-.47,.127),(.025,.28,.014),"steel",0)


def facade(lib):
    lib.asset("district_facade","background industrial building facade",[shape((8.0,6.3,3.6),(0,3.15,0))],"closed background building; place beyond playable boundary; no fake traversable doors")
    lib.box("BuildingMass",(0,0,3.0),(8.0,3.6,6.0),"graphite",.09)
    for x in [-3.82,-1.28,1.28,3.82]:
        lib.box("FacadePier",(x,1.90,3.01),(.22,.35,6.03),"concrete",.035)
    for z in [.4,3.05,5.84]:
        lib.box("FloorBand",(0,1.87,z),(8.22,.26,.21),"steel",.02)
    for i,x in enumerate([-2.55,0,2.55]):
        for row,z in enumerate([1.45,4.48]):
            lib.box("WindowFrame",(x,1.92,z),(1.45,.17,.92),"steel",.02)
            lib.box("WindowDark",(x,2.02,z),(1.27,.07,.74),"amber" if (i+row)%3==0 else "graphite",.015)
            for offset in [-.34,.34]:
                lib.box("Mullion",(x+offset,2.07,z),(.062,.045,.76),"steel",0)
    for x,z in [(-1.18,1.70),(3.42,4.22)]:
        lib.box("UtilityBox",(x,2.10,z),(.50,.42,.76),"orange")
        lib.vent("UtilityGrill",(x,2.34,z),.38,.48,7)
    for x in [-3.53,3.54]:
        lib.bar("DrainPipe",(x,2.11,.26),(x,2.11,6.28),.08)
    for i in range(4):
        x=-3.0+i*2.0
        lib.profile("RoofProfile",[(x-1.05,6),(x+1.05,6),(x+.98,6.75),(x-.95,6.44)],3.84,"steel",bevel=.035)
        lib.box("RoofSeam",(x,0,6.89),(.055,3.8,.09),"graphite",0)
    lib.box("ServiceDoor",(0,2.035,.98),(1.43,.085,1.90),"graphite")
    lib.box("DoorWarning",(0,2.09,.75),(.84,.02,.12),"orange",0)


def shelter(lib):
    collision=[shape((6.0,2.65,.42),(0,1.325,1.14))]
    collision.extend(shape((.22,2.55,.22),(x,1.275,z)) for x in [-2.72,2.72] for z in [-1.13,1.13])
    collision.append(shape((1.55,1.10,.62),(-1.8,.55,.72)))
    lib.asset("maintenance_shelter","compact side-camp maintenance awning",collision,"walkable beneath front canopy; collide only four columns, rear wall and work cabinet; do not use one full footprint box")
    lib.box("BackWall",(0,-1.14,1.32),(6,.42,2.65),"graphite")
    for x in [-2.72,2.72]:
        for y in [-1.13,1.13]:
            lib.box("Column",(x,y,1.27),(.22,.22,2.55),"steel")
            lib.box("ColumnFoot",(x,y,.16),(.34,.34,.32),"concrete")
        lib.bar("Beam",(x,-1.22,2.58),(x,1.31,2.58),.08)
    lib.box("Canopy",(0,0,2.70),(6.36,3.02,.15),"graphite",.025,rot=(.11,0,0))
    for x in [-2.8,-1.4,0,1.4,2.8]:
        lib.box("RoofStandingSeam",(x,0,2.78),(.045,3.0,.05),"steel",0,rot=(.11,0,0))
    lib.box("RearCabinet",(-1.8,-.72,.55),(1.55,.62,1.10),"orange")
    lib.vent("CabinetGrill",(-1.8,-.385,.65),1.1,.46,7)
    for x in [-1.85,1.85]:
        lib.box("UnderLampHousing",(x,.82,2.43),(.62,.23,.14),"steel")
        lib.box("UnderLamp",(x,.83,2.355),(.45,.18,.025),"amber",.005)
    lib.bar("ServicePipe",(2.0,-.77,.10),(2.0,-.77,2.56),.10,"orange")


def pipe_run(lib):
    lib.asset("pipe_run","4m wall-side flanged pipe",[shape((4.25,.65,.74),(0,.56,0))],"solid utility pipe; put next to wall outside combat movement corridors")
    lib.bar("MainPipe",(-2,0,.62),(2,0,.62),.22,"steel",14)
    for x in [-1.75,-.70,.72,1.74]:
        lib.cylinder("Flange",(x,0,.62),.30,.10,"graphite",rot=(0,math.pi/2,0),vertices=14)
        for angle in [0,math.pi/2,math.pi,math.pi*1.5]:
            lib.cylinder("Bolt",(x+.06,.26*math.cos(angle),.62+.26*math.sin(angle)),.025,.06,"ivory",rot=(0,math.pi/2,0),vertices=6)
    for x in [-1.50,1.50]:
        lib.box("Cradle",(x,0,.23),(.29,.70,.45),"concrete")
    lib.bar("ValveStem",(.42,0,.62),(.42,.43,.62),.09)
    lib.cylinder("ValveWheel",(.42,.49,.62),.28,.065,"orange",rot=(math.pi/2,0,0))
    lib.box("Gauge",(-.70,.245,.77),(.28,.10,.30),"graphite")
    lib.box("GaugeFace",(-.70,.307,.77),(.19,.02,.19),"ivory",0)


def lamp(lib):
    lib.asset("industrial_lamp","readable warm industrial path lamp",[shape((.50,3.70,.50),(0,1.85,0))],"solid narrow post; emitting mesh does not create a runtime light; use sparse separately budgeted lights")
    lib.box("Foot",(0,0,.15),(.60,.60,.3),"concrete")
    lib.box("Mast",(0,0,1.85),(.16,.17,3.45),"graphite")
    lib.bar("CrossArm",(0,0,3.57),(0,.59,3.57),.065)
    lib.box("LampHood",(0,.61,3.46),(.65,.58,.28),"steel",.04)
    lib.box("LampDiffuser",(0,.63,3.305),(.44,.42,.035),"amber",.008)
    lib.box("PowerBox",(0,.13,1.13),(.39,.24,.48),"orange")
    lib.bar("Conduit",(.08,.11,1.3),(.08,.11,3.43),.018,"steel",8)


def planter(lib):
    lib.asset("planter_overgrowth","compact opaque-leaf overgrowth planter",[shape((1.22,.57,.91),(0,.285,0))],"solid planter at wall; upper foliage decorative, no transparent leaf cards or contact-damage implication")
    lib.box("Container",(0,0,.25),(1.18,.88,.50),"orange",.04)
    lib.box("Rim",(0,0,.53),(1.27,.97,.10),"graphite")
    lib.box("Soil",(0,0,.53),(1.04,.74,.065),"moss",0)
    for i in range(7):
        x=-.44+i*.14;y=math.sin(i*1.9)*.22;height=.8+(i%3)*.16
        lib.bar("Stem",(x,y,.55),(x+.07,y,height),.018,"moss",6)
        for j in range(3):
            lib.leaf("Leaf",(x+.05,y,height-.25+j*.09),.16,.31,angle=i*.91+j*2.2)


def drain(lib):
    lib.asset("drain_grate","3.6m recessed drainage strip",[],"walkable flush grate; continuous ground collision supplies support")
    lib.box("Channel",(0,0,.025),(.54,3.6,.05),"graphite",0)
    for x in [-.235,.235]:lib.box("Edge",(x,0,.07),(.055,3.6,.07),"steel",0)
    for i in range(19):
        lib.box("Bar",(0,-1.68+i*.187,.071),(.44,.065,.057),"steel",.006)


def ventilation(lib):
    lib.asset("ventilation_unit","roof or wall service intake",[shape((1.36,1.47,1.08),(0,.735,0))],"solid machinery; avoid routes and use on roofs/edge service pads")
    lib.box("Body",(0,0,.72),(1.26,.98,1.44),"steel")
    lib.box("Top",(0,0,1.48),(1.38,1.1,.10),"graphite")
    lib.box("Face",(0,.518,.82),(1.05,.06,1.06),"graphite")
    lib.vent("Intake",(0,.57,.82),.87,.82,10)
    for side in [-1,1]:lib.box("SideRail",(side*.68,0,.72),(.12,.82,1.19),"orange")
    lib.box("AccessPanel",(0,.57,.20),(.64,.035,.19),"steel")


def tank(lib):
    lib.asset("reservoir_tank","industrial coolant reservoir",[shape((1.48,2.70,1.48),(0,1.35,0))],"solid tank placed by walls; no walkable hollow interior")
    lib.cylinder("Reservoir",(0,0,1.34),.63,2.36,"graphite",vertices=16)
    for z in [.28,1.33,2.48]:lib.cylinder("Band",(0,0,z),.69,.13,"steel",vertices=16)
    lib.cylinder("Cap",(0,0,2.60),.59,.14,"orange",vertices=16)
    for x in [-.45,.45]:lib.box("Support",(x,0,.14),(.26,.98,.28),"concrete")
    for x in [-.20,.20]:lib.bar("LadderRail",(x,.70,.23),(x,.70,2.65),.025)
    for i in range(8):lib.bar("LadderRung",(-.20,.71,.35+i*.30),(.20,.71,.35+i*.30),.023)
    lib.box("SightGlass",(.10,.654,1.54),(.075,.065,.65),"cyan",.008)
    lib.bar("Outflow",(-.63,0,.60),(-1.14,0,.60),.12)


def debris(lib):
    lib.asset("scattered_debris","sparse ground scale/detail cluster",[],"decorative debris under .2m tall; no solid obstruction or loot affordance")
    for i in range(8):
        x=math.sin(i*2.21)*.63;y=math.cos(i*1.71)*.47
        lib.box("Fragment",(x,y,.055+(i%2)*.02),(.19+(i%3)*.07,.13+(i%2)*.16,.11),"concrete" if i%3 else "graphite",.015,rot=(i*.01,-i*.013,i*.61))
    for i in range(5):
        lib.leaf("FallenLeaf",(math.sin(i*2.8)*.66,math.cos(i*1.8)*.44,.027),.10,.16,i*1.3)


BUILDERS={"ruin_wall_full":wall_full,"ruin_wall_broken":wall_broken,"conduit_gateway":gateway,"paving_tiles":paving,"district_facade":facade,"maintenance_shelter":shelter,"pipe_run":pipe_run,"industrial_lamp":lamp,"planter_overgrowth":planter,"drain_grate":drain,"ventilation_unit":ventilation,"reservoir_tank":tank,"scattered_debris":debris}


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only",nargs="*",choices=list(BUILDERS))
    args=parser.parse_args(argv)
    lib=ModuleLibrary(ROOT,"AnotherWorld_DistrictModules")
    for name,builder in BUILDERS.items():
        if args.only is None or name in args.only:builder(lib)
    exported=lib.export()
    lib.save(exported)
    return lib


if __name__=="__main__":main()
