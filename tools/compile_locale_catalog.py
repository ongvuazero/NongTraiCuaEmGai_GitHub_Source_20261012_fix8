"""Mechanical, lossless pair-catalog compilation; never invent translations.

The legacy JSON stays authoritative for existing source-string calls. New locale
translations use stable pair IDs; existing locale files and drafts are preserved.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path

LOCALES = ["vi", "en", "th", "ms", "id", "zh_CN", "ja", "ko", "ru", "es", "pt_BR", "de", "fr", "pl"]
PRINTF = re.compile(r"%(?:[0-9.]+)?[dsf]")
STRING = r'"(?:[^"\\]|\\.)*"'
PAIR_CALL = re.compile(r'(?:_t|UILocale\.pair)\(\s*(' + STRING + r')\s*,\s*(' + STRING + r')\s*\)')


def compile_catalog(root: Path) -> dict:
    legacy_path = root / "localization/strings.json"
    legacy = json.loads(legacy_path.read_text(encoding="utf-8-sig"))
    additions_path = root / "localization/foundation_additions.json"
    additions = json.loads(additions_path.read_text(encoding="utf-8-sig")) if additions_path.exists() else {}
    for key, pair in additions.items():
        if key in legacy and legacy[key] != pair:
            raise ValueError(f"Refusing to replace legacy meaning for {key!r}")
        legacy.setdefault(key, pair)
    messages, aliases = {}, {}
    for key, pair in legacy.items():
        if not isinstance(pair, list) or len(pair) != 2 or not all(isinstance(x, str) for x in pair):
            raise ValueError(f"Invalid EN/VI pair: {key!r}")
        fingerprint = json.dumps(pair, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        message_id = "m_" + hashlib.sha256(fingerprint).hexdigest()[:16]
        entry = messages.setdefault(message_id, {"en": pair[0], "vi": pair[1], "source_keys": [], "printf": PRINTF.findall(pair[0]), "named_parameters": sorted(set(re.findall(r"\{([A-Za-z][A-Za-z0-9_]*)\}", pair[0])))})
        if PRINTF.findall(pair[0]) != PRINTF.findall(pair[1]):
            raise ValueError(f"Legacy placeholder mismatch: {key!r}")
        entry["source_keys"].append(key)
        aliases[key] = message_id
    # Original source keys take precedence, followed by legacy insertion-order
    # EN/VI aliases, exactly as UILocale did before the schema migration.
    for key, pair in legacy.items():
        for value in pair:
            if value:
                aliases.setdefault(value, aliases[key])
    # Exact runtime VI/EN pairs are included losslessly, even when two pairs
    # share an English alias. Stable IDs are fingerprinted by BOTH meanings.
    pair_calls = 0
    for source_file in list((root / "scripts/screens").glob("*.gd")) + list((root / "scripts/ui").glob("*.gd")):
        for match in PAIR_CALL.finditer(source_file.read_text(encoding="utf-8-sig")):
            vi, en = [json.loads(value) for value in match.groups()]
            if PRINTF.findall(vi) != PRINTF.findall(en):
                raise ValueError(f"Runtime pair token mismatch: {source_file.name} {en!r}")
            pair = [en, vi]
            fingerprint = json.dumps(pair, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            message_id = "m_" + hashlib.sha256(fingerprint).hexdigest()[:16]
            entry = messages.setdefault(message_id, {"en": en, "vi": vi, "source_keys": [], "printf": PRINTF.findall(en), "named_parameters": sorted(set(re.findall(r"\{([A-Za-z][A-Za-z0-9_]*)\}", en)))})
            entry["source_keys"].append("runtime_pair:" + source_file.name)
            aliases.setdefault(en, message_id)
            aliases.setdefault(vi, message_id)
            pair_calls += 1
    catalog = {"schema_version": 1, "legacy_entries": len(legacy), "messages": messages, "aliases": aliases,
               "source": "All exact EN/VI pairs from strings.json plus foundation_additions.json and literal runtime VI/EN pair calls; not English-only deduplication."}
    out = root / "localization/catalog.json"
    out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    locales_dir = root / "localization/locales"
    locales_dir.mkdir(parents=True, exist_ok=True)
    manual_path = root / "localization/manual_ui_overrides.json"
    manual = json.loads(manual_path.read_text(encoding="utf-8-sig")) if manual_path.exists() else {}
    navigation_path = root / "localization/manual_navigation_glossary.json"
    navigation = json.loads(navigation_path.read_text(encoding="utf-8-sig")) if navigation_path.exists() else {}
    safety_path = root / "localization/manual_save_safety_glossary.json"
    safety = json.loads(safety_path.read_text(encoding="utf-8-sig")) if safety_path.exists() else {}
    farm_path = root / "localization/manual_farm_glossary.json"
    farm = json.loads(farm_path.read_text(encoding="utf-8-sig")) if farm_path.exists() else {}
    for locale in LOCALES:
        path = locales_dir / f"{locale}.json"
        existing = json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else {}
        texts = existing.get("messages", {})
        if locale in ("en", "vi"):
            texts = {message_id: entry[locale] for message_id, entry in messages.items()}
        result = dict(existing)
        result.update(schema_version=1, locale=locale, review_status="existing_source" if locale in ("en", "vi") else "draft_not_native_approved", messages=texts)
        glossary = dict(zip(navigation.get("keys", []), navigation.get(locale, [])))
        folded_glossary = {key.casefold(): value for key, value in glossary.items()}
        folded_glossary.update({key.casefold(): value for key, value in zip(safety.get("keys", []), safety.get(locale, []))})
        farm_values = farm.get(locale, [])
        if farm_values and len(farm_values) != len(farm.get("keys", [])):
            raise ValueError(f"Farm glossary length mismatch: {locale}")
        folded_glossary.update({key.casefold(): value for key, value in zip(farm.get("keys", []), farm_values)})
        folded_glossary.update({key.casefold(): value for key, value in farm.get("extras", {}).get(locale, {}).items()})
        for message_id, entry in messages.items():
            override = manual.get(locale, {}).get(entry["en"])
            override = folded_glossary.get(entry["en"].casefold(), override)
            if entry["en"] == "Feed" and entry["vi"] == "Thức ăn":
                # One English word has both noun and action meanings. Preserve
                # the exact-pair distinction instead of applying the verb to food.
                override = {"th":"อาหาร", "ms":"Makanan", "id":"Pakan", "zh_CN":"饲料", "ja":"餌", "ko":"먹이", "ru":"Корм", "es":"Alimento", "pt_BR":"Ração", "de":"Futter", "fr":"Nourriture", "pl":"Karma"}.get(locale)
            if override is not None:
                if PRINTF.findall(override) != entry["printf"]:
                    raise ValueError(f"Manual override token mismatch: {locale} {entry['en']}")
                texts[message_id] = override
                result.setdefault("provenance", {})[message_id] = "self_reviewed_critical_ui_not_native_approved"
        path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"legacy_entries": len(legacy), "runtime_pair_calls": pair_calls, "distinct_pairs": len(messages), "unique_english": len({e["en"] for e in messages.values()}), "aliases": len(aliases), "legacy_source_templates": sum(bool(PRINTF.search(k)) for k in legacy), "pair_templates": sum(bool(e["printf"]) for e in messages.values())}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    print(json.dumps(compile_catalog(args.root), indent=2))
