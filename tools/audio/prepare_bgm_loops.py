"""Prepare stereo WAV music for a bounded engine-loop seam and OGG/VORBIS.

These are sample-level checks, not LUFS measurements or approval of musical
phrasing, rhythm, harmony, or auditory suitability. Source files are untouched.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

TARGET_RMS_DBFS = -20.0
MAX_BOOST_DB = 4.0
PEAK_CEILING_DBFS = -2.0
SILENCE_DBFS = -70.0


def dbfs(value: float) -> float | None:
    return 20.0 * math.log10(value) if value > 0 else None


def metrics(audio: np.ndarray, sample_rate: int) -> dict:
    finite = np.isfinite(audio)
    valid = np.where(finite, audio, 0.0)
    peak = float(np.max(np.abs(valid), initial=0.0))
    # Scaling before squaring avoids overflow on malformed floating-point WAVs.
    rms = peak * float(np.sqrt(np.mean((valid / peak) ** 2))) if peak else 0.0
    jump = np.abs(valid[-1] - valid[0]) if len(valid) > 1 else np.zeros(audio.shape[1])
    seam = float(np.max(jump, initial=0.0))
    return {
        "frames": len(audio), "channels": audio.shape[1],
        "sample_rate_hz": sample_rate, "duration_seconds": len(audio) / sample_rate,
        "peak_linear": peak, "peak_dbfs": dbfs(peak),
        "rms_linear": rms, "rms_dbfs": dbfs(rms),
        "seam_jump_per_channel": jump.tolist(), "seam_jump_max_linear": seam,
        "seam_jump_dbfs": dbfs(seam),
        "clipped_sample_count": int(np.count_nonzero(finite & (np.abs(audio) >= 1.0))),
        "nonfinite_sample_count": int(np.count_nonzero(~finite)),
    }


def prepare_samples(audio: np.ndarray, sample_rate: int, overlap_seconds: float = 0.20,
                    edge_trim_seconds: float = 0.75) -> tuple[np.ndarray, dict]:
    if audio.ndim != 2 or audio.shape[1] != 2 or not len(audio):
        raise ValueError("Expected a nonempty stereo source; no downmix is performed")
    if not np.isfinite(audio).all():
        raise ValueError("Nonfinite source samples are rejected, not silently replaced")
    if not 0 <= overlap_seconds <= 0.25 or not 0 <= edge_trim_seconds <= 1.0:
        raise ValueError("Overlap must be 0..0.25 s; each edge trim must be 0..1 s")
    active = np.flatnonzero(np.max(np.abs(audio), axis=1) > 10 ** (SILENCE_DBFS / 20))
    trim_limit = min(round(edge_trim_seconds * sample_rate), len(audio) // 4)
    leading = min(int(active[0]), trim_limit) if len(active) else 0
    trailing = min(len(audio) - 1 - int(active[-1]), trim_limit) if len(active) else 0
    trimmed = audio[leading:len(audio) - trailing if trailing else len(audio)]
    overlap = min(round(overlap_seconds * sample_rate), len(trimmed) // 4)
    if overlap < 2:
        overlap = 0
        loop = trimmed.copy()
    else:
        weight = (0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, overlap)))[:, None]
        blend = trimmed[-overlap:] * (1.0 - weight) + trimmed[:overlap] * weight
        loop = np.concatenate((trimmed[overlap:-overlap], blend))
    before_gain = metrics(loop, sample_rate)
    rms = before_gain["rms_linear"]
    gain_db = min(MAX_BOOST_DB, TARGET_RMS_DBFS - dbfs(rms)) if rms else 0.0
    if before_gain["peak_linear"]:
        gain_db = min(gain_db, PEAK_CEILING_DBFS - dbfs(before_gain["peak_linear"]))
    loop *= 10 ** (gain_db / 20)
    return loop, {
        "trim": {"threshold_dbfs": SILENCE_DBFS, "max_each_edge_seconds": edge_trim_seconds,
                 "effective_each_edge_limit_frames": trim_limit,
                 "leading_frames": leading, "trailing_frames": trailing,
                 "leading_seconds": leading / sample_rate, "trailing_seconds": trailing / sample_rate,
                 "all_input_below_threshold": not bool(len(active)), "interior_silence_removed": False},
        "circular_overlap": {"requested_seconds": overlap_seconds, "frames": overlap,
                             "actual_seconds": overlap / sample_rate,
                             "method": "raised-cosine amplitude tail-to-head overlap",
                             "order": "interior[m:n-m], then tail*(1-w)+head*w",
                             "frames_removed": overlap, "stable_interior_changed_before_gain": False},
        "normalization": {"target_rms_dbfs": TARGET_RMS_DBFS, "max_boost_db": MAX_BOOST_DB,
                          "peak_ceiling_dbfs": PEAK_CEILING_DBFS, "initial_gain_db": gain_db,
                          "digital_silence": not bool(rms)},
        "loop_before_gain": before_gain,
    }


def prepare_file(source: Path, output: Path, report_path: Path,
                 overlap_seconds: float = 0.20, edge_trim_seconds: float = 0.75,
                 ffmpeg: Path | None = None) -> dict:
    source, output, report_path = source.resolve(), output.resolve(), report_path.resolve()
    if len({source, output, report_path}) != 3:
        raise ValueError("Input, output and report must be distinct paths")
    for target in (output, report_path):
        if target.exists():
            raise FileExistsError(f"Refusing to overwrite existing output: {target}")
    if ffmpeg is not None and not ffmpeg.is_file():
        raise FileNotFoundError(f"FFmpeg executable not found: {ffmpeg}")
    info = sf.info(source)
    if info.format not in ("WAV", "WAVEX", "RF64"):
        raise ValueError("Input must be a WAV source")
    audio, sample_rate = sf.read(source, dtype="float64", always_2d=True)
    input_metrics = metrics(audio, sample_rate)
    loop, operations = prepare_samples(audio, sample_rate, overlap_seconds, edge_trim_seconds)
    output.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    peak_limit = 10 ** (PEAK_CEILING_DBFS / 20)
    passes, additional_gain_db = [], 0.0
    # Encode in a private temporary file; the final output is created exclusively.
    with tempfile.TemporaryDirectory(prefix="bgm_encode_", dir=output.parent) as temporary:
        encoded = Path(temporary) / "loop.ogg"
        normalized = Path(temporary) / "normalized.wav"
        for index in range(3):
            if ffmpeg is None:
                sf.write(encoded, loop, sample_rate, format="OGG", subtype="VORBIS")
            else:
                sf.write(normalized, loop.astype(np.float32), sample_rate, format="WAV", subtype="FLOAT")
                subprocess.run([str(ffmpeg), "-hide_banner", "-nostdin", "-loglevel", "error",
                                "-y", "-i", str(normalized), "-c:a", "libvorbis", "-q:a", "4",
                                str(encoded)], check=True, capture_output=True)
            decoded, decoded_rate = sf.read(encoded, dtype="float32", always_2d=True)
            output_metrics = metrics(decoded, decoded_rate)
            passes.append({"pass": index + 1, "decoded_peak_dbfs": output_metrics["peak_dbfs"],
                           "decoded_rms_dbfs": output_metrics["rms_dbfs"]})
            if output_metrics["nonfinite_sample_count"]:
                raise ValueError("Encoder produced nonfinite samples")
            if output_metrics["peak_linear"] <= peak_limit + 1e-12:
                break
            if index == 2:
                raise ValueError("Decoded Vorbis peak remains above the -2 dBFS ceiling")
            attenuation_db = 20 * math.log10(peak_limit / output_metrics["peak_linear"]) - 0.05
            additional_gain_db += attenuation_db
            loop *= 10 ** (attenuation_db / 20)
            passes[-1]["attenuation_before_next_encode_db"] = attenuation_db
        with output.open("xb") as destination:
            destination.write(encoded.read_bytes())
    operations["normalization"]["encoder_correction_gain_db"] = additional_gain_db
    operations["normalization"]["total_gain_db"] = operations["normalization"]["initial_gain_db"] + additional_gain_db
    operations["encoding"] = {"format": "OGG", "subtype": "VORBIS",
                              "settings": "FFmpeg libvorbis quality4 via temporary FLOAT WAV" if ffmpeg else "libsndfile default Vorbis encoding",
                              "ffmpeg_executable": str(ffmpeg) if ffmpeg else None,
                              "passes": passes,
                              "native_encode_limit": "A full-array48kHz stereo soundfile Vorbis write terminated with0xC00000FD (native stack overflow); FFmpeg avoids that write path. Exact underlying cause not isolated." if ffmpeg else None}
    report = {
        "status": "PROCESSED_NUMERIC_CHECKS", "input_path": str(source), "output_path": str(output),
        "original_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "output_bytes": output.stat().st_size, "input": input_metrics, "output": output_metrics,
        "operations": operations,
        "metric_definitions": {"rms": "Unweighted sample RMS over both stereo channels; not LUFS",
                               "clipped_sample_count": "Samples at or above full scale; not proof of waveform clipping",
                               "zero_dbfs_values": "null represents zero amplitude",
                               "seam_jump": "Absolute last-to-first sample difference, maximum across channels"},
        "limits": "Numeric boundary checks do not establish seamless musical phrasing, rhythmic/harmonic quality or auditory suitability. Audition is required.",
        "source_modified": False,
    }
    with report_path.open("x", encoding="utf-8") as destination:
        json.dump(report, destination, indent=2, allow_nan=False)
        destination.write("\n")
    return report


def self_test() -> None:
    rate = 16000
    # Distinct channels expose reversed weights and accidental channel mixing.
    tagged = np.column_stack((np.linspace(0.2, 0.6, rate), np.linspace(-0.4, -0.1, rate)))
    loop, ops = prepare_samples(tagged, rate, 0.20, 0.0)
    m = ops["circular_overlap"]["frames"]
    gain = 10 ** (ops["normalization"]["initial_gain_db"] / 20)
    np.testing.assert_allclose(loop[:len(tagged) - 2 * m] / gain, tagged[m:-m], atol=1e-12)
    np.testing.assert_allclose(loop[-1] / gain, tagged[m - 1], atol=1e-12)
    assert len(loop) == len(tagged) - m
    # Bound only the edges; do not remove an intentional interior silence gap.
    padded = np.concatenate((np.zeros((rate * 3 // 2, 2)), tagged,
                             np.zeros((rate // 5, 2)), tagged, np.zeros((rate * 3 // 5, 2))))
    _, trim_ops = prepare_samples(padded, rate, 0.0, 1.0)
    assert trim_ops["trim"]["leading_frames"] == rate
    assert trim_ops["trim"]["trailing_frames"] == rate * 3 // 5
    _, quiet_ops = prepare_samples(tagged * 0.001, rate, 0.0, 0.0)
    assert abs(quiet_ops["normalization"]["initial_gain_db"] - 4.0) < 1e-9
    hot = tagged.copy()
    hot[rate // 2] = 10.0
    limited, _ = prepare_samples(hot, rate, 0.0, 0.0)
    assert metrics(limited, rate)["peak_linear"] <= 10 ** (-2 / 20) + 1e-12
    invalid = tagged.copy()
    invalid[0, 0] = np.nan
    try:
        prepare_samples(invalid, rate)
        raise AssertionError("Nonfinite audio must be rejected")
    except ValueError:
        pass
    with tempfile.TemporaryDirectory(prefix="bgm_loop_test_") as directory:
        directory = Path(directory)
        time = np.arange(rate * 3) / rate
        tone = np.column_stack((0.25 * np.sin(2 * np.pi * 220 * time + 0.3),
                                0.2 * np.sin(2 * np.pi * 330 * time + 0.7)))
        source, output, report_path = directory / "source.wav", directory / "loop.ogg", directory / "report.json"
        sf.write(source, tone, rate, subtype="FLOAT")
        report = prepare_file(source, output, report_path)
        assert report["output"]["frames"] == len(tone) - round(0.2 * rate)
        assert report["output"]["peak_dbfs"] <= -2.0 + 1e-9
        assert report["output"]["clipped_sample_count"] == report["output"]["nonfinite_sample_count"] == 0
        assert report["original_sha256"] == hashlib.sha256(source.read_bytes()).hexdigest()
        assert json.loads(report_path.read_text()) == report
        try:
            prepare_file(source, output, report_path)
            raise AssertionError("Existing output must be preserved")
        except FileExistsError:
            pass
    print("BGM_LOOP_SELF_TEST: PASS; bounded stereo/trim/gain/Vorbis/report/no-overwrite checks")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--overlap", type=float, default=0.20)
    parser.add_argument("--edge-trim", type=float, default=0.75)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--ffmpeg", type=Path, help="Use external libvorbis encoding when native soundfile encoding is unsuitable")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.input is None or args.output is None or args.report is None:
        parser.error("input WAV, output OGG and --report are required")
    report = prepare_file(args.input, args.output, args.report, args.overlap, args.edge_trim, args.ffmpeg)
    print(json.dumps({"output": report["output_path"], "duration_seconds": report["output"]["duration_seconds"],
                      "peak_dbfs": report["output"]["peak_dbfs"], "rms_dbfs": report["output"]["rms_dbfs"],
                      "report": str(args.report.resolve())}, indent=2))


if __name__ == "__main__":
    main()
