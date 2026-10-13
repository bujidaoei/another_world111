"""Read-only texture QA, plus a repeat contact sheet for visual inspection."""
from pathlib import Path
import json
import hashlib
import statistics
import argparse
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("input_image",type=Path)
parser.add_argument("--report",type=Path,default=ROOT/"source-assets/evidence/texture-validation.json")
parser.add_argument("--repeat-preview",type=Path,default=ROOT/"source-assets/previews/wet_concrete_repeat_3x3.png")
args=parser.parse_args()
path=args.input_image.resolve()
image=Image.open(path).convert("RGB")
if image.size!=(512,512):
    raise RuntimeError(f"Unexpected texture dimensions: {image.size}")
px=image.load()
w,h=image.size
lr=[abs(px[0,y][channel]-px[w-1,y][channel]) for y in range(h) for channel in range(3)]
tb=[abs(px[x,0][channel]-px[x,h-1][channel]) for x in range(w) for channel in range(3)]
pixels=[px[x,y] for y in range(h) for x in range(w)]
monochrome=max(max(rgb)-min(rgb) for rgb in pixels)
values=[rgb[0] for rgb in pixels]
report={"date":"2026-10-13","file":str(path.relative_to(ROOT)).replace("\\","/"),"bytes":path.stat().st_size,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"size":[w,h],"mode":"RGB","edge_difference_8bit":{"left_right_max":max(lr),"left_right_mean":statistics.mean(lr),"top_bottom_max":max(tb),"top_bottom_mean":statistics.mean(tb)},"max_rgb_channel_difference":monochrome,"intensity":{"min":min(values),"max":max(values),"mean":statistics.mean(values),"stddev":statistics.pstdev(values)},"seam_method":"ComfyUI core ImageFlip and ImageBlend averages, horizontal then vertical; mirror symmetry is intentional","acceptance":"technical sample only; Godot material and Android quality/performance pending"}
if max(lr)>1 or max(tb)>1 or monochrome:
    raise RuntimeError(f"Texture tile constraints failed: {report}")
out=args.report
out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(report,indent=2),encoding="utf-8")
preview=Image.new("RGB",(w*3,h*3))
for y in range(3):
    for x in range(3):
        preview.paste(image,(x*w,y*h))
args.repeat_preview.parent.mkdir(parents=True,exist_ok=True)
preview.save(args.repeat_preview)
print(json.dumps(report,indent=2))
