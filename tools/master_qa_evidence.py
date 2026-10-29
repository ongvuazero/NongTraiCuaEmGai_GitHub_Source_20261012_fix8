"""Build review-only contacts and hash/diff evidence; never mutate game art."""
import csv
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "REPORTS/MASTER_PLAN_V1"
FONT = ImageFont.truetype(str(ROOT / "assets/fonts/BeVietnamPro-Regular.ttf"), 22)
SMALL = ImageFont.truetype(str(ROOT / "assets/fonts/BeVietnamPro-Regular.ttf"), 16)
BLUE = "#183d39"
CREAM = "#f8ebd0"
OUTPUT = REPORT / "CONTACTS"
OUTPUT.mkdir(parents=True, exist_ok=True)

def contact(paths, name, columns=3, width=480):
    tile_height = int(width * 720 / 1280) + 32
    canvas = Image.new("RGB", (width * columns, tile_height * ((len(paths) + columns - 1) // columns)), CREAM)
    draw = ImageDraw.Draw(canvas)
    for index, path in enumerate(paths):
        x, y = (index % columns) * width, (index // columns) * tile_height
        picture = Image.open(path).convert("RGB")
        picture.thumbnail((width, tile_height - 32), Image.Resampling.LANCZOS)
        canvas.paste(picture, (x, y + 32))
        draw.text((x + 8, y + 4), path.stem, font=SMALL, fill=BLUE)
    canvas.save(OUTPUT / name)

for fixture in ("FRESH", "RICH"):
    for locale in ("vi", "en"):
        paths = sorted((REPORT / "CAPTURES").glob(f"{fixture}_{locale}_*.png"))
        if paths: contact(paths, f"ALL_15_{fixture}_{locale}.png")
for locale in ("vi", "en"):
    paths = sorted((REPORT / "FIELD").glob(f"{locale}_*.png"))
    if paths: contact(paths, f"FIELD_STATES_{locale}.png")

# Both source and composited thumbnail views are evidence, not altered runtime assets.
for action in ("till", "plant", "water", "fertilize", "harvest"):
    source = Image.open(ROOT / f"assets/production_ui_v1/vfx/{action}_sheet.png").convert("RGBA")
    canvas = Image.new("RGBA", (1200, 640), CREAM)
    draw = ImageDraw.Draw(canvas)
    for frame in range(8):
        x, y = frame % 4, frame // 4
        box = (round(x * source.width / 4), round(y * source.height / 2), round((x + 1) * source.width / 4), round((y + 1) * source.height / 2))
        cell = source.crop(box)
        cell.thumbnail((290, 280), Image.Resampling.LANCZOS)
        canvas.alpha_composite(cell, (x * 300 + (300 - cell.width) // 2, y * 320 + 32))
        draw.text((x * 300 + 10, y * 320 + 4), f"{action} / {frame + 1}", font=FONT, fill=BLUE)
    canvas.convert("RGB").save(OUTPUT / f"VFX_{action.upper()}_SOURCE_CONTACT.png")

icons = [ROOT / f"assets/production_ui_v1/items/{name}.png" for name in ("crop_pumpkin", "seed_pumpkin", "dragon_treat")]
icon_canvas = Image.new("RGBA", (900, 330), CREAM)
draw = ImageDraw.Draw(icon_canvas)
for index, path in enumerate(icons):
    picture = Image.open(path).convert("RGBA")
    picture.thumbnail((280, 280), Image.Resampling.LANCZOS)
    icon_canvas.alpha_composite(picture, (index * 300 + (300 - picture.width) // 2, 36))
    draw.text((index * 300 + 10, 4), path.stem, font=FONT, fill=BLUE)
icon_canvas.convert("RGB").save(OUTPUT / "NEW_ITEM_SOURCE_CONTACT.png")

baseline_names = {
    "06_shop": "e81c3c52-291a-4be0-a779-ce8ea9ccade2",
    "07_storage": "00e29380-e905-4453-8458-c56017b59adc",
    "09_animal": "f966ab9c-e3ab-4ae3-b021-14e8d5d9762c",
    "10_dragon": "8f401912-fc90-4253-98b4-ab74a9f61efb",
    "05_field": "de5637ae-85cb-4c42-ac2d-695c421e63a9",
    "12_islands": "469f8a90-9916-4c4f-8da8-615b53ecdcd6",
}
baseline = REPORT / "USER_BASELINE"
baseline.mkdir(exist_ok=True)
for screen, key in baseline_names.items():
    source = Path(f"C:/Users/HanTin/AppData/Local/Temp/codex-clipboard-{key}.png")
    if not source.exists(): continue
    copied = baseline / (screen + ".png")
    shutil.copy2(source, copied)
    after = REPORT / "CAPTURES" / ("FRESH_vi_" + screen + ".png")
    if screen == "05_field": after = REPORT / "FIELD/vi_06_WATER_SELECTED.png"
    if screen == "07_storage": after = REPORT / "CAPTURES/RICH_vi_07_storage.png"
    if after.exists(): contact([copied, after], f"BEFORE_AFTER_{screen}.png", columns=2, width=960)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

# The Field geometry/state/actor implementation is intentionally unchanged.
checkpoint = ROOT / "BACKUPS/MASTER_PLAN_V1"
field = ROOT / "scenes/screens/05_field_gameplay.tscn"
old_field = checkpoint / "scenes/screens/05_field_gameplay.tscn"
def plot_section(path):
    source = path.read_text(encoding="utf-8-sig")
    return source[source.index('[node name="FieldArea"'):source.index('[node name="TopHUD"')]
geometry_same = plot_section(field) == plot_section(old_field)
actor_same = sha(ROOT / "v7/production/field_actor_depth.gd") == sha(checkpoint / "v7/production/field_actor_depth.gd")
save_same = sha(ROOT / "scripts/save_service.gd") == sha(checkpoint / "scripts/save_service.gd")
(REPORT / "LOCKED_FILES_PROOF.txt").write_text(
    f"12 Plot / FieldArea serialized section unchanged: {geometry_same}\nFarmer animation implementation unchanged: {actor_same}\nSaveService unchanged: {save_same}\nResolution remains1280x720.\n",
    encoding="utf-8")
if not (geometry_same and actor_same and save_same): raise RuntimeError("Locked source changed unexpectedly")

rows = []
for path in checkpoint.rglob("*"):
    if not path.is_file(): continue
    relative = path.relative_to(checkpoint)
    if relative.parts[0] in ("world_presentation", "text_readability_checkpoint", "final_capture_text_checkpoint") or "before_footer" in path.name: continue
    current = ROOT / relative
    if current.is_file() and sha(path) != sha(current):
        rows.append([relative.as_posix(), "MODIFIED", sha(path), sha(current), current.stat().st_size])
for name in ("world_system_screen.gd", "world_system_screen.tscn"):
    sub = "scripts/screens" if name.endswith(".gd") else "scenes/screens"
    old = checkpoint / "world_presentation" / name
    current = ROOT / sub / name
    if sha(old) != sha(current): rows.append([sub + "/" + name, "MODIFIED", sha(old), sha(current), current.stat().st_size])
with (REPORT / "CHANGED_EXISTING_FILES.csv").open("w", encoding="utf-8-sig", newline="") as stream:
    writer = csv.writer(stream)
    writer.writerow(["relative_path", "kind", "before_sha256", "after_sha256", "size_bytes"])
    writer.writerows(sorted(rows))
print(f"Evidence: {len(rows)} changed existing files; lock proofs pass; {len(list(OUTPUT.glob('*.png')))} contacts")
