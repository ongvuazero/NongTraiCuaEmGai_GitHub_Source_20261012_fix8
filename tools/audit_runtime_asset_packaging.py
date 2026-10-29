"""Conservative packaging preflight. Never deletes assets or changes presets.

This is NOT a complete GDScript interpreter or a licence certification. It
checks explicit raw-source exclusions against production resource literals,
all motion annotation sources and font redistribution files. A runtime closure
manifest records directory-prefix expansion so dynamic IDs are not forgotten.
"""
from __future__ import annotations
import argparse
import json
import re
import zipfile
from pathlib import Path

RAW_SOURCE_DIRS = (
    "assets/canonical_v2/02_ART_SOURCE_CANONICAL",
    "assets/field_approved_v1/source",
    "assets/production_ui_v1/review",
    "assets/reference",
    "assets/library",
)
TEXT_SUFFIXES = {".gd", ".gdshader", ".json", ".tscn", ".tres", ".godot"}
RESOURCE_LITERAL = re.compile(r'''["'](res://[^"'\r\n]+)["']''')
SKIP_SCRIPT = re.compile(r"(?:test|regression|capture|_qa)\.gd$")

def uri(path: Path, root: Path) -> str:
    return "res://" + path.relative_to(root).as_posix()

def references(text: str) -> list[str]:
    return sorted(set(RESOURCE_LITERAL.findall(text)))

def resolve_literal(value: str, root: Path) -> tuple[list[Path], str]:
    tail = value.removeprefix("res://")
    if not tail or ".." in Path(tail).parts:
        return [], "unresolved"
    # Format placeholders denote generated paths: keep the containing subtree,
    # not one guessed frame/locale/island. Directory constants are treated alike.
    prefix = tail.split("%", 1)[0]
    candidate = root / prefix
    if "%" in tail:
        candidate = candidate if prefix.endswith("/") else candidate.parent
    if candidate.is_dir():
        return sorted(p for p in candidate.rglob("*") if p.is_file() and p.suffix != ".import" and not p.name.startswith(".")), "directory_prefix"
    if candidate.is_file() and "%" not in tail:
        return [candidate], "exact"
    return [], "missing_or_optional"

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--apk", type=Path)
    args = parser.parse_args()
    root = args.project.resolve()
    out = args.output or root / "reports/RELEASE_FIX_20261011/asset_runtime/PACKAGING_PREFLIGHT.json"
    blockers, literals, source_files = [], {}, []
    # Scan production text, not reports/docs/QA provenance. Explicit old source
    # roots in data/asset_mapping.json are provenance metadata, not a load API.
    production_roots = ["scripts", "autoload", "scenes", "resources", "data", "localization", "v6/runtime", "v6/data", "v7/runtime", "v7/production", "v7/data"]
    for folder in production_roots:
        for path in sorted((root / folder).rglob("*")):
            if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
                continue
            rel = path.relative_to(root).as_posix()
            if "/qa/" in rel or SKIP_SCRIPT.search(path.name) or rel == "data/asset_mapping.json":
                continue
            source_files.append(path)
    source_files.append(root / "project.godot")
    for path in source_files:
        for literal in references(path.read_text(encoding="utf-8-sig")):
            literals.setdefault(literal, []).append(uri(path, root))
            tail = literal.removeprefix("res://").rstrip("/")
            for folder in RAW_SOURCE_DIRS:
                if tail == folder or tail.startswith(folder + "/") or (literal.endswith("/") and folder.startswith(tail + "/")):
                    blockers.append({"reference": literal, "in": uri(path, root), "excluded_source_dir": folder})
    closure, generated, unknown = {}, [], []
    for literal, owners in sorted(literals.items()):
        resolved, mode = resolve_literal(literal, root)
        if mode == "directory_prefix":
            generated.append({"literal": literal, "owners": owners, "files": len(resolved)})
        if not resolved:
            unknown.append({"literal": literal, "owners": owners, "classification": "missing/optional/provenance; not used to strip anything"})
        for path in resolved:
            closure.setdefault(uri(path, root), []).extend(owners)
    motion = json.loads((root / "data/presentation/creature_motion_sources_v1.json").read_text(encoding="utf-8-sig"))
    motion_paths = set()
    for spec in motion.values():
        if not isinstance(spec, dict) or "source" not in spec or "frames" not in spec:
            continue
        motion_paths.add(spec["source"])
        for frame in spec["frames"]:
            motion_paths.add(frame.get("source", spec["source"]))
    missing_motion = [value for value in sorted(motion_paths) if not (root / value.removeprefix("res://")).is_file()]
    notices = sorted(uri(path, root) for path in (root / "assets/fonts").rglob("*.txt"))
    raw_files = []
    imported_paths = set()
    for folder in RAW_SOURCE_DIRS:
        for path in sorted((root / folder).rglob("*")):
            if not path.is_file() or path.suffix == ".import" or path.name.startswith("."):
                continue
            imports = []
            import_file = path.with_name(path.name + ".import")
            if import_file.is_file():
                imports = sorted(set(re.findall(r'res://(\.godot/imported/[^"\r\n]+\.ctex)', import_file.read_text(encoding="utf-8-sig"))))
                imported_paths.update(imports)
            raw_files.append({"path": uri(path, root), "source_bytes": path.stat().st_size, "imported_ctex": imports})
    raw_ctex = sum((root / path).stat().st_size for path in imported_paths if (root / path).is_file())
    apk_measure = None
    if args.apk:
        with zipfile.ZipFile(args.apk) as archive:
            entries = [entry for entry in archive.infolist() if entry.filename.removeprefix("assets/") in imported_paths]
        apk_measure = {"apk": str(args.apk), "matching_ctex_entries": len(entries), "compressed_payload_bytes": sum(entry.compress_size for entry in entries)}
    result = {
        "status": "PASS_CONSERVATIVE_EXCLUSIONS" if not blockers and not missing_motion and notices else "FAIL",
        "source_files_scanned": len(source_files), "production_literal_count": len(literals),
        "runtime_reference_manifest": sorted(closure), "dynamic_directory_expansions": generated,
        "unresolved_optional_or_provenance_literals": unknown, "raw_source_reference_blockers": blockers,
        "motion_sources": sorted(motion_paths), "missing_motion_sources": missing_motion,
        "font_license_passthrough_files": notices,
        "safe_explicit_source_exclusions": [folder + "/*" for folder in RAW_SOURCE_DIRS],
        "raw_source_files": raw_files, "raw_source_imported_ctex_bytes": raw_ctex, "prior_apk_matching_payload": apk_measure,
        "safety_boundary": "All-resource export remains enabled. Only explicit source/review/retired folders are excluded. This manifest does not authorize stripping unresolved resources or changing texture compression/locale coverage; no file is deleted. APK saving is measured only when prior archive match is provided."
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in ["status", "source_files_scanned", "production_literal_count", "missing_motion_sources", "raw_source_reference_blockers", "raw_source_imported_ctex_bytes", "prior_apk_matching_payload"]}, ensure_ascii=False))
    return 0 if result["status"].startswith("PASS") else 1

if __name__ == "__main__":
    raise SystemExit(main())
