"""Read-only regression for manually reviewed audit meanings and format contracts."""
from __future__ import annotations
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON = lambda name: json.loads((ROOT / name).read_text(encoding="utf-8-sig"))
fixture = JSON("localization/fragments/semantic_audit_20261010.json")
catalog = JSON("localization/catalog.json")
printf = re.compile(r"%(?:[0-9.]+)?[dsf]")
named = re.compile(r"\{([A-Za-z][A-Za-z0-9_]*)\}")
numbers = re.compile(r"(?<![A-Za-z0-9_])\d+(?![A-Za-z0-9_])")
checks = 0
failures = []
def check(ok, message):
    global checks
    checks += 1
    if not ok:
        failures.append(message)

rows = fixture["rows"]
check(len({r[0] for r in rows}) == len(rows), "Audit source keys must be unique")
matching_ids = 0
for source, targets in rows:
    entries = [(mid, entry) for mid, entry in catalog["messages"].items() if entry["en"] == source]
    check(bool(entries), "Missing audited source: " + source)
    check(len(targets) == len(fixture["languages"]), "Locale arity: " + source)
    matching_ids += len(entries)
    for language, expected in zip(fixture["languages"], targets):
        document = JSON(f"localization/locales/{language}.json")
        check(document["review_status"] == "draft_not_native_approved", language + " approval boundary")
        check(printf.findall(expected) == printf.findall(source), language + " printf contract: " + source)
        check(sorted(named.findall(expected)) == sorted(named.findall(source)), language + " named contract: " + source)
        check(expected.count("\n") == source.count("\n"), language + " newline contract: " + source)
        for literal in numbers.findall(source):
            check(literal in expected, language + " missing required number " + literal + ": " + source)
        for mid, entry in entries:
            actual = document["messages"].get(mid)
            check(actual == expected, language + " regression meaning: " + mid + " " + source)
            check(document.get("provenance", {}).get(mid) == "self_reviewed_critical_ui_not_native_approved",
                  language + " missing manual provenance: " + mid)
            check(printf.findall(actual or "") == entry["printf"], language + " catalog printf: " + mid)
        if source == "Raise elemental dragons, hatch their eggs and choose a daily helper." and language == "th":
            check("ระยํา" not in expected and "ฟักไข่" in expected, "Thai dragon description must mean hatch, without vulgar text")
        if source == "During Autumn, deliver two pumpkins and one milk.":
            if language == "th":
                check("ฤดูใบไม้ร่วง" in expected and "ฟักทองสอง" in expected, "Thai Autumn/2 pumpkins")
            if language == "ms":
                check("musim luruh" in expected and "dua labu" in expected, "Malay Autumn/2 pumpkins")

events = JSON("data/full_game/events.json")
autumn = events["autumn_fair"]
check(autumn["season"] == "autumn", "Autumn event authority")
check(autumn["ingredients"] == {"crop_pumpkin": 2, "milk": 1}, "Autumn ingredient authority")
check(any(source == autumn["description"] for source, _ in rows), "Event source must remain in audited fixture")
print(json.dumps({"checks": checks, "failures": failures, "manual_source_keys": len(rows),
                  "matching_exact_pair_ids": matching_ids, "locales": len(fixture["languages"]),
                  "scope": "Exact audited meanings/format contracts only; not native approval of the complete catalog."}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failures else 0)
