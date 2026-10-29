"""Read-only RGBA source measurement; never changes or renders the image."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

project = Path(__file__).resolve().parents[1]
source = "assets/living_world_gait_pilot_v4/chicken_turn_care_source.png"
rgba = np.asarray(Image.open(project / source).convert("RGBA"))
# Complete alpha8 connected-occupant bounds, not a guessed 4x4 grid.
bounds = [[101,527,220,247],[466,523,226,251],[837,524,224,249],[1203,526,244,249],[107,768,249,252],[447,787,281,232],[823,774,242,245],[1199,776,263,243]]
# Manually reviewed visible beak/seam positions, independently alpha checked.
mouths = [[303,599],[584,608],[856,599],[1428,604],[338,829],[644,890],[1031,822],[1402,837]]
entries = []
for index, (x, y, width, height) in enumerate(bounds):
    torso = rgba[y+int(height*.45):y+int(height*.72), x+int(width*.2):x+int(width*.8)]
    white = (torso[:,:,3] >= 96) & (torso[:,:,0] >= 180)
    axis = float(np.median(np.where(white)[1])) + x + int(width*.2)
    mouth = mouths[index]
    entries.append({"rect": bounds[index], "feet": [round(axis,4), y+height], "mouth": mouth, "source": "res://"+source, "source_scale": 396/249, "alpha_pixels": int((rgba[y:y+height,x:x+width,3] >= 96).sum()), "mouth_rgba": rgba[mouth[1],mouth[0]].tolist()})
print(json.dumps(entries, ensure_ascii=False))
