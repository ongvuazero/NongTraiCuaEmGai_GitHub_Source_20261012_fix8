"""Generate local machine-translation drafts, never native-review approval.

Only public UI EN/VI strings enter local M2M100 inference. Model weights stay
outside the Godot project. Placeholder contracts are checked before delivery.
"""
from __future__ import annotations
import argparse
import json
import re
import time
from pathlib import Path

TARGETS = {"th": "th", "ms": "ms", "id": "id", "zh_CN": "zh", "ja": "ja", "ko": "ko", "ru": "ru", "es": "es", "pt_BR": "pt", "de": "de", "fr": "fr", "pl": "pl"}
TOKEN = re.compile(r"%(?:[0-9.]+)?[dsf]|\{[A-Za-z][A-Za-z0-9_]*\}")
BOUNDARY = re.compile(r"(%(?:[0-9.]+)?[dsf]|\{[A-Za-z][A-Za-z0-9_]*\}|\n)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--download-only", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--locales", nargs="*", default=list(TARGETS))
    args = parser.parse_args()
    from huggingface_hub import snapshot_download
    if not (args.model_dir / "pytorch_model.bin").exists():
        snapshot_download("facebook/m2m100_418M", local_dir=str(args.model_dir), allow_patterns=["config.json", "generation_config.json", "pytorch_model.bin", "sentencepiece.bpe.model", "special_tokens_map.json", "tokenizer_config.json", "vocab.json", "README.md"])
    if args.download_only:
        print("DOWNLOAD_COMPLETE", flush=True)
        return
    import torch
    from transformers import M2M100ForConditionalGeneration, M2M100Tokenizer
    tokenizer = M2M100Tokenizer.from_pretrained(str(args.model_dir), local_files_only=True, trust_remote_code=False)
    tokenizer.src_lang = "en"
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = M2M100ForConditionalGeneration.from_pretrained(str(args.model_dir), local_files_only=True, trust_remote_code=False, torch_dtype=torch.float16 if device == "cuda" else torch.float32).to(device).eval()
    catalog = json.loads((args.root / "localization/catalog.json").read_text(encoding="utf-8"))
    messages = catalog["messages"]
    started = time.time()
    report = {"model": "facebook/m2m100_418M", "source": "https://huggingface.co/facebook/m2m100_418M", "license": "MIT", "device": device, "review_status": "draft_not_native_approved", "locales": {}}

    def translate_many(texts, target, source_lang="en"):
        tokenizer.src_lang = source_lang
        result = []
        for offset in range(0, len(texts), 24):
            batch = texts[offset:offset + 24]
            inputs = tokenizer(batch, return_tensors="pt", padding=True, truncation=True, max_length=384).to(device)
            with torch.inference_mode():
                outputs = model.generate(**inputs, forced_bos_token_id=tokenizer.get_lang_id(target), num_beams=2, max_new_tokens=384, early_stopping=True)
            result.extend(tokenizer.batch_decode(outputs, skip_special_tokens=True))
        return result

    for locale in args.locales:
        path = args.root / f"localization/locales/{locale}.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        existing = document.get("messages", {})
        provenance = document.get("provenance", {})
        entries = [(key, entry["en"]) for key, entry in messages.items() if key not in existing or TOKEN.findall(existing[key]) != TOKEN.findall(entry["en"]) or existing[key].count("\n") != entry["en"].count("\n")]
        if args.smoke:
            examples = {"Save game", "Resume", "Choose language", "This field opens on day %d.", "Need %d energy for care.", "Settings", "Feed"}
            entries = [(key, text) for key, text in entries if text in examples][:10]
        source_unique = list(dict.fromkeys(text for _, text in entries))
        # Preserve the exact printf/named tokens with a deliberately conspicuous
        # lexical sentinel. A changed sentinel never gets accepted as a token.
        masked, token_lists = [], {}
        for source in source_unique:
            tokens = TOKEN.findall(source)
            token_lists[source] = tokens
            index = iter(range(len(tokens)))
            masked.append(TOKEN.sub(lambda m: f"QXZ{next(index)}ZXQ", source))
        outputs = translate_many(masked, TARGETS[locale])
        # A rare short proper noun may be blank from EN. Retry the authoritative
        # Vietnamese meaning locally before declaring it explicitly unresolved.
        blank_indices = [i for i, output in enumerate(outputs) if not output.strip()]
        if blank_indices:
            vi_by_en = {entry["en"]: entry["vi"] for entry in messages.values()}
            retries = [vi_by_en[source_unique[i]] for i in blank_indices]
            retry_outputs = translate_many(retries, TARGETS[locale], "vi")
            for i, output in zip(blank_indices, retry_outputs):
                if output.strip() and not token_lists[source_unique[i]]: outputs[i] = output
        cache = {}
        segmented = []
        for source, output in zip(source_unique, outputs):
            tokens = token_lists[source]
            markers = re.findall(r"QXZ([0-9]+)ZXQ", output)
            if markers == [str(i) for i in range(len(tokens))] and output.strip() and output.count("\n") == source.count("\n"):
                for i, token in enumerate(tokens):
                    output = output.replace(f"QXZ{i}ZXQ", token)
                if TOKEN.findall(output) == tokens:
                    cache[source] = (output, "local_m2m100_masked")
                    continue
            segmented.append(source)
        # Exact boundary assembly avoids token corruption. This is explicitly
        # flagged for grammatical review, not hidden as approved translation.
        segments = list(dict.fromkeys(part.strip() for source in segmented for part in BOUNDARY.split(source) if part.strip() and not BOUNDARY.fullmatch(part)))
        segment_cache = dict(zip(segments, translate_many(segments, TARGETS[locale])))
        for source in segmented:
            result = ""
            for part in BOUNDARY.split(source):
                if not part or BOUNDARY.fullmatch(part) or not part.strip():
                    result += part
                else:
                    left = part[:len(part) - len(part.lstrip())]
                    right = part[len(part.rstrip()):]
                    result += left + segment_cache[part.strip()] + right
            if TOKEN.findall(result) != TOKEN.findall(source):
                raise ValueError(f"Unrecoverable placeholder contract: {locale} {source!r}")
            cache[source] = (result, "local_m2m100_segmented_requires_grammar_review") if result.strip() else (source, "explicit_unresolved_english_fallback_not_translated")
        unchanged = 0
        for key, source in entries:
            result, method = cache[source]
            existing[key] = result
            provenance[key] = method
            unchanged += int(result == source)
        document.update(messages=existing, provenance=provenance, generator="facebook/m2m100_418M local; no remote inference", review_status="draft_not_native_approved")
        path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        report["locales"][locale] = {"added": len(entries), "total": len(existing), "segmented_unique": len(segmented), "unchanged": unchanged}
        print(json.dumps({"locale": locale, **report["locales"][locale], "elapsed_seconds": round(time.time() - started)}, ensure_ascii=False), flush=True)
    report["elapsed_seconds"] = round(time.time() - started)
    report_path = args.root / "reports/FIX_AND_LANGUAGES_20261010/local_draft_generation.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
