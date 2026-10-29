"""Package a review patch and evidence, never a full project or release build."""
import csv
import hashlib
import json
import re
import shutil
import sys
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "REPORTS/MASTER_PLAN_V1"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent
OUT.mkdir(parents=True, exist_ok=True)
ZIP_NAME = "MY_SISTERS_FARM_MASTER_PLAN_EXECUTION_REVIEW_V1.zip"
ZIP_PATH = OUT / ZIP_NAME
if ZIP_PATH.exists():
    ZIP_PATH = OUT / f"{ZIP_PATH.stem}_{datetime.now():%Y%m%d_%H%M%S}.zip"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

positive_logs = {
    "VERIFIED_core.log": "CURRENT_CORE_LOOP_TEST_PASS",
    "VERIFIED_phase1.log": "PHASE1_CROP_PROGRESSION_TEST_PASS",
    "VERIFIED_phase2.log": "PHASE2_FIRST_SESSION_TEST_PASS",
    "VERIFIED_full.log": "FULL_GAME_INTEGRATION_TEST_PASS",
    "FULL_INTEGRATION_EN_RUN.log": "FULL_GAME_INTEGRATION_TEST_PASS",
    "UI_FINAL_RUN.log": "MASTER_UI_QA_PASS",
    "FIELD_UI_FINAL_RUN.log": "MASTER_FIELD_UI_QA_PASS",
    "QA_ISOLATION_RUN.log": "QA_RICH_ISOLATION_PASS",
}
for name, marker in positive_logs.items():
    source = (REPORT / name).read_text(encoding="utf-8-sig")
    if marker not in source or re.search(r"(?:SCRIPT ERROR:|ERROR:|WARNING:)", source):
        raise RuntimeError(f"Final positive evidence is not clean: {name}")
for name in ("GUARD_master_ui_qa.log", "GUARD_master_field_ui_qa.log"):
    if "QA_ISOLATION_REQUIRED" not in (REPORT / name).read_text(encoding="utf-8-sig"):
        raise RuntimeError(f"Missing safety guard evidence: {name}")

with (REPORT / "CHANGED_EXISTING_FILES.csv").open(encoding="utf-8-sig", newline="") as stream:
    changes = {row["relative_path"]: row for row in csv.DictReader(stream)}

# These files were already edited in the current run but no pre-edit copy was kept.
# Never invent a before hash or claim the backed-up subset is the full change list.
for relative in (
    "scripts/ui/item_card_state_presenter.gd",
    "scripts/phase1_crop_progression_test.gd",
    "scripts/phase2_first_session_test.gd",
    "scripts/full_game_integration_test.gd",
):
    path = ROOT / relative
    changes[relative] = {
        "relative_path": relative, "kind": "MODIFIED",
        "before_sha256": "UNAVAILABLE_PRE_EDIT_COPY_NOT_RETAINED",
        "after_sha256": sha(path), "size_bytes": path.stat().st_size,
    }
added = [
    "scripts/ui_locale.gd", "scripts/qa_rich_fixture.gd",
    "scripts/master_ui_qa.gd", "scripts/master_field_ui_qa.gd",
    "scripts/master_qa_isolation_test.gd", "resources/ui/game_theme.tres",
    "qa/master_ui_qa.tscn", "qa/master_field_ui_qa.tscn", "qa/master_qa_isolation_test.tscn",
    "tools/build_ui_catalog.py", "tools/master_qa_evidence.py", "tools/package_master_ui_review.py",
    "tools/START_QA_999.ps1", "START_QA_999.cmd", "START_GAME.cmd",
    "BACKUPS/.gdignore", "REPORTS/.gdignore", "assets/production_ui_v1/review/.gdignore",
    "assets/fonts/BeVietnamPro-Regular.ttf", "assets/fonts/BeVietnamPro-SemiBold.ttf",
    "assets/fonts/BeVietnamPro-Bold.ttf", "assets/fonts/OFL.txt", "assets/fonts/SOURCE.md",
    "localization/strings.json", "localization/ui_strings.csv",
    *[f"localization/fragments/{name}.json" for name in ("core", "field", "screens", "world")],
    *[f"assets/production_ui_v1/items/{name}.png" for name in ("crop_pumpkin", "seed_pumpkin", "dragon_treat")],
    *[f"assets/production_ui_v1/vfx/{name}_sheet.png" for name in ("till", "plant", "water", "fertilize", "harvest")],
]
for relative in added:
    path = ROOT / relative
    if not path.is_file():
        raise FileNotFoundError(path)
    changes[relative] = {
        "relative_path": relative, "kind": "ADDED", "before_sha256": "NOT_APPLICABLE",
        "after_sha256": sha(path), "size_bytes": path.stat().st_size,
    }
with (REPORT / "ALL_CHANGED_AND_ADDED_FILES.csv").open("w", encoding="utf-8-sig", newline="") as stream:
    fields = ["relative_path", "kind", "before_sha256", "after_sha256", "size_bytes"]
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    writer.writerows(changes[key] for key in sorted(changes))

asset_originals = {
    "crop_pumpkin": "exec-75e327ef-1a9a-4772-ad17-fc49d58567e9.png",
    "seed_pumpkin": "exec-aba88e63-6cb4-4e89-a593-cf3612134c2f.png",
    "dragon_treat": "exec-455f2e10-2c78-43bc-a81f-7fe8d51ef0c8.png",
    "till": "exec-e29666eb-4fb2-4171-bee9-e534a4ce191c.png",
    "plant": "exec-1cedead1-5dd8-48d5-868d-5efafe12407a.png",
    "water": "exec-d9a98dce-7682-4b77-8568-f15c3cfe01b6.png",
    "fertilize": "exec-c021263c-93f6-4d74-bbf6-f164047e7fe8.png",
    "harvest": "exec-f6d225c0-5d37-4c03-86ce-789b6acd43dc.png",
}
with (REPORT / "05_ASSETS/ASSET_SOURCE_MANIFEST.csv").open("w", encoding="utf-8-sig", newline="") as stream:
    writer = csv.writer(stream)
    writer.writerow(["runtime_path", "original_generated_file", "width", "height", "mode", "bytes", "sha256", "role", "source_status", "commercial_review"])
    for relative in added:
        if not relative.endswith(".png"):
            continue
        path = ROOT / relative
        name = path.stem.removesuffix("_sheet")
        with Image.open(path) as picture:
            writer.writerow([relative, asset_originals[name], picture.width, picture.height, picture.mode,
                             path.stat().st_size, sha(path), "VFX feedback only" if "vfx/" in relative else "UI inventory icon only",
                             "INTEGRATED AFTER CONTACT REVIEW", "USER REVIEW REQUIRED; NOT GLOBAL PRODUCTION PASS"])
    for path, original in (
        (ROOT / "assets/production_ui_v1/review/farmer_till_rejected_sheet.png", "exec-c7d10876-8dd4-4492-854a-6bc8ae80bbfc.png"),
        (REPORT / "FARMER_TILL_RETRY_REJECTED.png", "exec-5b2486db-46e4-4d05-a39a-6913e30fd7b4.png"),
    ):
        with Image.open(path) as picture:
            writer.writerow(["NONE; REVIEW ONLY", original, picture.width, picture.height, picture.mode, path.stat().st_size,
                             sha(path), "Farmer TILL candidate", "REJECTED; NOT REFERENCED BY RUNTIME", "FAIL ROOT/CONTINUITY/FRINGE/CLIPPING"])

stage = Path(tempfile.mkdtemp(prefix="msf_ui_review_", dir=OUT))
manifest = []
def copy(source, destination, category):
    if not source.is_file():
        raise FileNotFoundError(source)
    target = stage / destination
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    manifest.append([destination.replace("\\", "/"), category, source.stat().st_size, sha(source)])

for relative in sorted(changes):
    copy(ROOT / relative, "PATCH_RUNTIME/" + relative, changes[relative]["kind"])

# Read-only supporting code/resources. No heavyweight original art or whole project.
context = {
    "scenes/main.tscn", "autoload/screen_router.gd", "scripts/farm_data.gd", "scripts/save_service.gd",
    "scripts/current_core_loop_test.gd", "qa/current_core_loop_test.tscn",
    "qa/phase1_crop_progression_test.tscn", "qa/phase2_first_session_test.tscn", "qa/full_game_integration_test.tscn",
    "scenes/screens/title_screen.tscn", "scenes/screens/save_slot_screen.tscn", "scenes/screens/home_hub_screen.tscn",
    "scenes/screens/orders_screen.tscn", "icon.svg",
}
context.update(path.relative_to(ROOT).as_posix() for path in (ROOT / "data/full_game").glob("*.json"))
allowed = {".gd", ".tscn", ".tres", ".json", ".cfg"}
queue = [ROOT / relative for relative in set(changes) | context if (ROOT / relative).suffix in allowed]
seen = set()
missing_context = set()
while queue:
    path = queue.pop()
    if path in seen:
        continue
    seen.add(path)
    if not path.is_file():
        missing_context.add(path.relative_to(ROOT).as_posix())
        continue
    for dependency in re.findall(r'res://[^"\s)]+', path.read_text(encoding="utf-8-sig")):
        candidate = ROOT / dependency[6:]
        if candidate.suffix in allowed and not any(part in {".godot", ".git", "BACKUPS", "REPORTS"} for part in candidate.parts):
            relative = candidate.relative_to(ROOT).as_posix()
            if relative not in changes:
                context.add(relative)
            queue.append(candidate)
for relative in sorted(context - set(changes)):
    path = ROOT / relative
    if path.is_file():
        copy(path, "CONTEXT_READ_ONLY/" + relative, "UNMODIFIED CONTEXT")
    else:
        missing_context.add(relative)

for path in REPORT.rglob("*"):
    if not path.is_file() or path.suffix not in {".md", ".csv", ".txt", ".json", ".log"}:
        continue
    relative = path.relative_to(REPORT).as_posix()
    if relative.startswith(("CAPTURES/", "FIELD/", "CONTACTS/", "USER_BASELINE/")) or relative.endswith("PACKAGE_METADATA.json"):
        continue
    # Final logs plus explicitly classified rejected invocations, not obsolete logs.
    if path.suffix == ".log" and path.name not in positive_logs and not path.name.startswith(("GUARD_", "INVALID_HEADLESS_")):
        continue
    copy(path, "REPORTS/" + relative, "REPORT OR CLASSIFIED LOG")
copy(ROOT / "REPORTS/FULL_GAME_INTEGRATION_RESULTS.txt", "REPORTS/06_QA/FULL_GAME_INTEGRATION_RESULTS.txt", "FINAL TEST RESULTS")

capture_count = 0
for folder in ("CAPTURES", "FIELD"):
    for path in sorted((REPORT / folder).glob("*.png")):
        with Image.open(path) as picture:
            if picture.size != (1280, 720):
                raise RuntimeError(f"Wrong runtime capture size: {path}")
        copy(path, f"QA_CAPTURES/{folder}/{path.name}", "RUNTIME SCREENSHOT")
        capture_count += 1
if capture_count != 91:
    raise RuntimeError(f"Expected 91 screenshots, found {capture_count}")
for path in sorted((REPORT / "CONTACTS").glob("*.png")):
    copy(path, "QA_CONTACTS/" + path.name, "REVIEW COMPOSITE ONLY")

for path in sorted((ROOT / "REPORTS/SPRINT1_FIELD_FEEL").glob("FARMER_*_CONTACT.png")):
    copy(path, "ASSET_REVIEW/CURRENT_FARMER/" + path.name, "EXISTING SOURCE DEFECT EVIDENCE")
copy(ROOT / "REPORTS/SPRINT1_FIELD_FEEL/FARMER_SOURCE_METRICS.csv", "ASSET_REVIEW/CURRENT_FARMER/FARMER_SOURCE_METRICS.csv", "SOURCE METRICS")
copy(ROOT / "assets/production_ui_v1/review/farmer_till_rejected_sheet.png", "ASSET_REVIEW/REJECTED/farmer_till_trial1.png", "REJECTED SOURCE; NOT RUNTIME")
copy(REPORT / "FARMER_TILL_RETRY_REJECTED.png", "ASSET_REVIEW/REJECTED/farmer_till_trial2.png", "REJECTED SOURCE; NOT RUNTIME")

checkpoint = ROOT / "BACKUPS/MASTER_PLAN_V1"
for relative, change in sorted(changes.items()):
    if change["kind"] != "MODIFIED" or str(change["before_sha256"]).startswith("UNAVAILABLE"):
        continue
    before = checkpoint / relative
    if relative.endswith("world_system_screen.gd") or relative.endswith("world_system_screen.tscn"):
        before = checkpoint / "world_presentation" / Path(relative).name
    if sha(before) != change["before_sha256"]:
        raise RuntimeError(f"Before-source proof mismatch: {relative}")
    copy(before, "BEFORE_SOURCE/" + relative, "BASELINE FOR DIFF; DO NOT INSTALL")

readme = stage / "00_READ_THIS_FIRST_VI.md"
readme.write_text(
    "# My Sister's Farm — mã sửa và bằng chứng review\n\n"
    "Đã sửa trực tiếp trong project; không phải bản release, không phải project tự chạy độc lập.\n\n"
    "1. Đọc REPORTS/00_OVERVIEW/README_VI.md và PROGRESS_LEDGER.md.\n"
    "2. Xem QA_CONTACTS/BEFORE_AFTER_* và ALL_15_*; ảnh full 1280×720 trong QA_CAPTURES.\n"
    "3. Đối chiếu PATCH_RUNTIME với BEFORE_SOURCE. CONTEXT_READ_ONLY chỉ giúp đọc luồng hiện tại.\n"
    "4. Đọc report riêng FONT / FIELD / SCREENS / WORLD / ASSETS / QA; điểm hình ảnh là chủ quan, không đo similarity.\n"
    "5. Xem ASSET_REVIEW: hai sheet farmer bị loại, tuyệt đối không gắn vào game.\n\n"
    "Không chép cả ZIP lên project. Runtime cũ vẫn cung cấp art approved không được lặp lại trong ZIP.\n"
    "Chỉ mục ALL_CHANGED_AND_ADDED_FILES.csv có toàn bộ file thay đổi; bốn file không còn before-copy được ghi UNAVAILABLE, không bịa hash.\n"
    "Test master UI/Field yêu cầu MSF_TEST_SAVE_DIR riêng và tự dừng nếu thiếu. Các regression cũ cũng phải chạy với save root riêng.\n"
    "Core/Phase1/Phase2 cần renderer, không chạy headless. QA999 chỉ test/debug: 999 item, không đổi New Game thật hay save người chơi.\n\n"
    "KẾT LUẬN: test chức năng PASS trong phạm vi có log; farmer source FAIL; World art PARTIAL; release HOLD.\n"
    "Không cho global PASS chỉ từ node boxes, chuỗi PASS hoặc fixture inventory. Đây chưa phải audit toàn bộ GDD và chưa chứng minh pacing toàn game.\n",
    encoding="utf-8",
)
manifest.append([readme.name, "PACKAGE README", readme.stat().st_size, sha(readme)])
if missing_context:
    unresolved = stage / "REPORTS/CONTEXT_DEPENDENCIES_NOT_FOUND.txt"
    unresolved.write_text("\n".join(sorted(missing_context)) + "\n", encoding="utf-8")
    manifest.append(["REPORTS/" + unresolved.name, "UNRESOLVED READ ONLY CONTEXT", unresolved.stat().st_size, sha(unresolved)])

with (stage / "REPORTS/PACKAGE_FILE_MANIFEST.csv").open("w", encoding="utf-8-sig", newline="") as stream:
    writer = csv.writer(stream)
    writer.writerow(["zip_relative_path", "category", "size_bytes", "sha256"])
    writer.writerows(sorted(manifest))

with zipfile.ZipFile(ZIP_PATH, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(stage.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(stage).as_posix())
with zipfile.ZipFile(ZIP_PATH) as archive:
    broken = archive.testzip()
    if broken:
        raise RuntimeError(f"ZIP CRC failed: {broken}")
    names = archive.namelist()
    forbidden = [name for name in names if any(part in {".godot", ".git", "node_modules"} for part in Path(name).parts) or Path(name).suffix in {".exe", ".pck", ".import", ".zip"}]
    if forbidden:
        raise RuntimeError(f"Forbidden cache/build files: {forbidden}")
    result = {
        "zip_path": str(ZIP_PATH), "size_bytes": ZIP_PATH.stat().st_size, "size_mib": round(ZIP_PATH.stat().st_size / 1048576, 2),
        "file_count": len(names), "modified_existing_files": sum(row["kind"] == "MODIFIED" for row in changes.values()),
        "added_runtime_tool_asset_files": sum(row["kind"] == "ADDED" for row in changes.values()),
        "runtime_screenshots": capture_count, "context_missing": sorted(missing_context),
        "crc_check": "PASS", "release_status": "HOLD; NO RELEASE EXPORT", "staging_path": str(stage),
    }
(REPORT / "PACKAGE_METADATA.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(result, ensure_ascii=False, indent=2))
