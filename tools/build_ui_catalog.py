"""Merge authored locale fragments; no gameplay data or scene mutation."""
import csv
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
catalog = {}
conflicts = []
for path in sorted((ROOT / "localization/fragments").glob("*.json")):
    fragment = json.loads(path.read_text(encoding="utf-8-sig"))
    for source, values in fragment.items():
        if not isinstance(values, list) or len(values) != 2 or not all(isinstance(v, str) for v in values):
            raise ValueError(f"Invalid locale row: {path.name}: {source}")
        if source in catalog and catalog[source] != values:
            conflicts.append(f"{path.name}: {source!r}: {catalog[source]!r} -> {values!r}")
        catalog[source] = values
out = ROOT / "localization/strings.json"
if conflicts:
    raise ValueError("Conflicting locale entries: " + "\n".join(conflicts))
# Short season names are canonical in compact shared HUD chips; all aliases
# must agree so automatic Label retranslation is deterministic.
for original, english, vietnamese in [
    ("spring", "Spring", "Xuân"), ("summer", "Summer", "Hạ"),
    ("autumn", "Autumn", "Thu"), ("winter", "Winter", "Đông")
]:
    catalog[original] = [english, vietnamese]
    catalog[english] = [english, vietnamese]
out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
with (ROOT / "localization/ui_strings.csv").open("w", encoding="utf-8-sig", newline="") as stream:
    writer = csv.writer(stream)
    writer.writerow(["key", "en", "vi"])
    writer.writerows((key, *value) for key, value in catalog.items())
print(f"UI_CATALOG: {len(catalog)} rows, {len(conflicts)} duplicate overrides")
for conflict in conflicts:
    print("OVERRIDE:", conflict)
