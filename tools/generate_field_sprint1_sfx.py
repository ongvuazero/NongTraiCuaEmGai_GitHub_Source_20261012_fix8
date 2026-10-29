"""Generate original, dependency-free Field feedback WAVs for Sprint 1."""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
ROOT = Path(__file__).resolve().parents[1] / "assets" / "audio" / "field_sprint1"
random.seed(713)


def env(t: float, duration: float, attack: float = 0.015, release: float = 0.22) -> float:
    return min(1.0, t / attack) * min(1.0, max(0.0, duration - t) / release)


def noise() -> float:
    return random.uniform(-1.0, 1.0)


def write(name: str, duration: float, synth) -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    samples = []
    low = 0.0
    for i in range(int(RATE * duration)):
        t = i / RATE
        raw = synth(t, duration)
        low += 0.12 * (raw - low)
        value = max(-0.94, min(0.94, low))
        samples.append(struct.pack("<h", int(value * 32767)))
    with wave.open(str(ROOT / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(samples))


def till(t: float, d: float) -> float:
    thump = math.sin(2 * math.pi * (82 - 28 * t / d) * t) * math.exp(-18 * t)
    grit = noise() * math.exp(-7 * t) * (0.45 + 0.55 * math.sin(math.pi * min(1, t / 0.12)))
    return (0.55 * thump + 0.26 * grit) * env(t, d, 0.004, 0.18)


def plant(t: float, d: float) -> float:
    taps = sum(math.sin(2 * math.pi * (520 + 80 * k) * t) * math.exp(-85 * max(0, t - 0.055 * k)) if t >= 0.055 * k else 0 for k in range(3))
    puff = noise() * math.exp(-20 * max(0, t - 0.13)) if t >= 0.13 else 0
    return (0.16 * taps + 0.10 * puff) * env(t, d, 0.003, 0.13)


def water(t: float, d: float) -> float:
    shimmer = noise() * 0.16 + math.sin(2 * math.pi * (720 + 90 * math.sin(9 * t)) * t) * 0.06
    drops = math.sin(2 * math.pi * 1250 * t) * (0.5 + 0.5 * math.sin(2 * math.pi * 13 * t)) * 0.05
    return (shimmer + drops) * env(t, d, 0.03, 0.20)


def fertilize(t: float, d: float) -> float:
    bells = sum(math.sin(2 * math.pi * f * t) for f in (660, 880, 1100)) / 3
    sprinkle = noise() * (0.5 + 0.5 * math.sin(2 * math.pi * 17 * t))
    return (0.14 * bells + 0.08 * sprinkle) * env(t, d, 0.015, 0.25)


def harvest(t: float, d: float) -> float:
    pop = math.sin(2 * math.pi * (180 + 380 * t / d) * t) * math.exp(-13 * t)
    chime = math.sin(2 * math.pi * 1046 * max(0, t - 0.09)) * math.exp(-7 * max(0, t - 0.09)) if t >= 0.09 else 0
    leaf = noise() * math.exp(-10 * t)
    return (0.34 * pop + 0.12 * chime + 0.08 * leaf) * env(t, d, 0.004, 0.23)


def ready(t: float, d: float) -> float:
    notes = [(0.00, 659), (0.10, 784), (0.20, 988)]
    value = 0.0
    for start, frequency in notes:
        if t >= start:
            u = t - start
            value += math.sin(2 * math.pi * frequency * u) * math.exp(-6 * u)
    return 0.16 * value * env(t, d, 0.006, 0.30)


def step(t: float, d: float) -> float:
    crunch = noise() * math.exp(-24 * t)
    body = math.sin(2 * math.pi * 105 * t) * math.exp(-20 * t)
    return (0.15 * crunch + 0.20 * body) * env(t, d, 0.002, 0.10)


write("field_till.wav", 0.34, till)
write("field_plant.wav", 0.32, plant)
write("field_water.wav", 0.52, water)
write("field_fertilize.wav", 0.46, fertilize)
write("field_harvest.wav", 0.48, harvest)
write("field_crop_ready.wav", 0.64, ready)
write("farmer_step_grass.wav", 0.18, step)
print(ROOT)
