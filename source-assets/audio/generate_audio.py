"""Deterministic original audio for Another World; Python standard library only.

Run from any directory: python source-assets/audio/generate_audio.py
No samples, model output, credentials, network, or external content are used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
TAU = math.tau
SEED = 20261013
PROJECT = Path(__file__).resolve().parents[2]


def db(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-12))


def envelope(t: float, duration: float, decay: float, attack: float = 0.004) -> float:
    return min(1.0, t / attack) * math.exp(-decay * t) * min(1.0, max(0.0, duration - t) / 0.018)


def tone_note(buffer: list[float], offset: float, duration: float, frequency: float, gain: float, soft: bool = False) -> None:
    first = round(offset * RATE)
    length = round(duration * RATE)
    for index in range(length):
        t = index / RATE
        phase = TAU * frequency * t
        harmonic = math.sin(phase) + 0.18 * math.sin(2 * phase) + 0.08 * math.sin(3 * phase)
        env = max(0.0, math.sin(math.pi * index / max(1, length - 1))) ** (2.0 if soft else 0.7)
        if not soft:
            env *= math.exp(-2.8 * t)
        buffer[(first + index) % len(buffer)] += gain * env * harmonic


def one_shot(name: str, variant: int = 0) -> list[float]:
    durations = {"electric": 0.32, "impact": 0.22, "dodge": 0.3, "collect": 0.55, "confirm": 0.16, "hurt": 0.4, "pulse": 0.75, "anchor": 0.6, "failure": 1.8, "victory": 1.8}
    duration = durations[name]
    count = round(duration * RATE)
    rng = random.Random(SEED + sum(map(ord, name)) * 17 + variant)
    values = [0.0] * count
    phase = 0.0
    filtered_noise = 0.0
    for index in range(count):
        t = index / RATE
        ratio = t / duration
        noise = rng.uniform(-1.0, 1.0)
        filtered_noise = 0.85 * filtered_noise + 0.15 * noise
        if name == "electric":
            freq = (1800 + variant * 83) * math.exp(-4.5 * t) + 190
            phase += TAU * freq / RATE
            values[index] = envelope(t, duration, 13) * (0.45 * noise + 0.55 * math.sin(phase + 0.5 * math.sin(TAU * 91 * t)))
        elif name == "impact":
            phase += TAU * (110 * math.exp(-12 * t) + 39 + variant * 4) / RATE
            values[index] = envelope(t, duration, 18) * (0.7 * math.sin(phase) + 0.3 * filtered_noise)
        elif name == "dodge":
            values[index] = math.sin(math.pi * ratio) ** 1.8 * (noise - filtered_noise) * (0.7 + 0.3 * math.sin(TAU * 90 * t))
        elif name == "hurt":
            phase += TAU * (100 * math.exp(-4 * t) + 47) / RATE
            values[index] = envelope(t, duration, 7) * math.tanh(2 * (math.sin(phase) + 0.35 * filtered_noise))
        elif name == "pulse":
            phase += TAU * (68 * math.exp(-3.5 * t) + 33) / RATE
            values[index] = envelope(t, duration, 5) * (0.65 * math.sin(phase) + 0.22 * noise * math.exp(-10 * t) + 0.13 * math.sin(TAU * 480 * t))
        elif name == "anchor":
            phase += TAU * (240 + 580 * ratio) / RATE
            values[index] = envelope(t, duration, 4.0) * (0.7 * math.sin(phase) + 0.18 * math.sin(phase * 1.5) + 0.12 * filtered_noise)
    if name == "collect":
        for offset, freq in [(0, 587.33), (0.12, 783.99), (0.24, 1174.66)]:
            tone_note(values, offset, 0.28, freq, 0.5)
    elif name == "confirm":
        tone_note(values, 0, duration, 659.25, 0.7)
        tone_note(values, 0.04, 0.1, 987.77, 0.3)
    elif name == "failure":
        for offset, freq in [(0, 293.66), (0.32, 233.08), (0.68, 220.0)]:
            tone_note(values, offset, 1.05, freq, 0.6, soft=True)
    elif name == "victory":
        for offset, freq in [(0, 293.66), (0.18, 349.23), (0.36, 440.0), (0.58, 587.33)]:
            tone_note(values, offset, 1.1, freq, 0.55, soft=True)
    return values


def periodic_lowpass(values: list[float], coefficient: float) -> list[float]:
    state = 0.0
    for value in values:
        state = coefficient * state + (1 - coefficient) * value
    state /= 1.0 - coefficient ** len(values)
    result = []
    for value in values:
        state = coefficient * state + (1 - coefficient) * value
        result.append(state)
    return result


def match_loop_boundary(values: list[float], window: int = 512) -> None:
    """Distribute a short endpoint correction; first/last PCM samples match.

    The correction tapers smoothly into the existing waveform and removes a
    single exceptional wrap jump without fading the rain or music to silence.
    """
    delta = values[-1] - values[0]
    for index in range(min(window, len(values) // 4)):
        weight = 0.5 * (1.0 + math.cos(math.pi * index / window))
        values[index] += 0.5 * delta * weight
        values[-1 - index] -= 0.5 * delta * weight


def rain_loop() -> list[float]:
    rng = random.Random(SEED)
    count = RATE * 12
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]
    fast = periodic_lowpass(noise, 0.55)
    slow = periodic_lowpass(noise, 0.98)
    values = []
    for index, (high, low) in enumerate(zip(fast, slow)):
        t = index / RATE
        swell = 0.8 + 0.11 * math.sin(TAU * t / 12) + 0.04 * math.sin(TAU * t * 5 / 12)
        values.append((high - 0.65 * low) * swell)
    for _ in range(90):
        tone_note(values, rng.uniform(0, 12), rng.uniform(0.025, 0.09), rng.uniform(480, 2800), rng.uniform(0.012, 0.04))
    match_loop_boundary(values)
    return values


def music_layers() -> tuple[list[float], list[float]]:
    # Original 8-bar D-minor ambient motif, 80 BPM, exactly 24 seconds per stem.
    base = [0.0] * (RATE * 24)
    combat = [0.0] * len(base)
    chords = [(146.83, 174.61, 220.0), (130.81, 164.81, 196.0), (116.54, 146.83, 174.61), (130.81, 164.81, 220.0)]
    for bar in range(8):
        offset = bar * 3.0
        chord = chords[bar % len(chords)]
        for frequency in chord:
            tone_note(base, offset, 5.5, frequency, 0.08, soft=True)
        tone_note(base, offset + 0.75, 1.2, chord[1] * 2, 0.035)
        tone_note(base, offset + 2.25, 1.2, chord[2] * 2, 0.03)
        for beat in range(4):
            start = round((offset + beat * 0.75) * RATE)
            for index in range(round(0.22 * RATE)):
                t = index / RATE
                kick = math.sin(TAU * (52 * t + 7 * (1 - math.exp(-22 * t)))) * math.exp(-24 * t)
                combat[(start + index) % len(combat)] += 0.24 * kick * min(1.0, t / 0.002)
            tone_note(combat, offset + beat * 0.75 + 0.375, 0.12, chord[0] * 3, 0.045)
    match_loop_boundary(base)
    match_loop_boundary(combat)
    return base, combat


def write_and_measure(path: Path, values: list[float], peak_target: float, looping: bool) -> dict:
    mean = sum(values) / len(values)
    values = [value - mean for value in values]
    peak = max(map(abs, values))
    scale = peak_target / max(peak, 1e-12)
    encoded = [round(max(-1.0, min(1.0, value * scale)) * 32767) for value in values]
    pcm = struct.pack(f"<{len(encoded)}h", *encoded)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)
    # Measurements are made after reopening the real written WAV file.
    with wave.open(str(path), "rb") as source:
        channels, width, rate, frames = source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getnframes()
        readback = struct.unpack(f"<{frames}h", source.readframes(frames))
    if (channels, width, rate, frames) != (1, 2, RATE, len(encoded)):
        raise RuntimeError(f"Invalid WAV readback: {path.name}")
    amplitudes = [value / 32768 for value in readback]
    actual_peak = max(map(abs, amplitudes))
    rms = math.sqrt(sum(value * value for value in amplitudes) / len(amplitudes))
    clipped = sum(abs(value) >= 32767 for value in readback)
    seam = abs(amplitudes[-1] - amplitudes[0])
    max_step = max(abs(a - b) for a, b in zip(amplitudes, amplitudes[1:]))
    if clipped or actual_peak > peak_target + 0.0001 or rms <= 0.0001:
        raise RuntimeError(f"Audio quality/format gate failed: {path.name}")
    if looping and seam > 1 / 32768:
        raise RuntimeError(f"Loop seam amplitude gate failed: {path.name}")
    return {
        "file": path.relative_to(PROJECT).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "channels": channels, "sample_width_bits": width * 8, "sample_rate_hz": rate,
        "frames": frames, "duration_seconds": frames / rate, "loop": looping,
        "peak": actual_peak, "peak_dbfs": round(db(actual_peak), 3), "rms": rms, "rms_dbfs": round(db(rms), 3),
        "dc_mean": sum(amplitudes) / len(amplitudes), "clipped_samples": clipped,
        "wrap_jump": seam, "maximum_internal_step": max_step,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=PROJECT / "game/assets/audio")
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(PROJECT):
        raise ValueError("Output must remain inside the project workspace.")
    output.mkdir(parents=True, exist_ok=True)
    assets = []
    for event in ["electric", "impact", "dodge", "collect", "confirm", "hurt", "pulse", "anchor", "failure", "victory"]:
        for variant in range(2 if event in ["electric", "impact"] else 1):
            suffix = f"_{variant + 1}" if event in ["electric", "impact"] else ""
            assets.append(write_and_measure(output / f"{event}{suffix}.wav", one_shot(event, variant), 0.36, False))
    assets.append(write_and_measure(output / "rain_loop.wav", rain_loop(), 0.24, True))
    base, combat = music_layers()
    assets.append(write_and_measure(output / "music_base.wav", base, 0.34, True))
    assets.append(write_and_measure(output / "music_combat.wav", combat, 0.22, True))
    manifest = {
        "version": 1, "seed": SEED, "sample_rate_hz": RATE, "python_runtime": sys.version.split()[0],
        "authoring": "Original deterministic mathematical synthesis; no sampled or generated third-party material.",
        "rights": "Project-original source and PCM assets; no third-party sample attribution or model license required.",
        "source_script": Path(__file__).relative_to(PROJECT).as_posix(),
        "source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "music": {"bpm": 80, "beats_per_bar": 4, "bars": 8, "layer_duration_seconds": 24, "key": "D minor", "loop_start_frame": 0},
        "mix_budget": {"sfx_voices": 8, "sfx_voice_db": -14.0, "rain_player_db": -9.0, "music_base_db": -10.0, "music_combat_db": -12.0, "master_limiter_ceiling_db": -1.0,
                       "conservative_all_volume_max_absolute_sum": 8 * 0.36 * 10 ** (-14 / 20) + 0.24 * 10 ** (-9 / 20) + 0.34 * 10 ** (-10 / 20) + 0.22 * 10 ** (-12 / 20)},
        "verification": "WAV files reopened and measured after writing; peak/RMS/DC/clipped samples/wrap jump checked. No subjective listening or runtime mix acceptance is claimed.",
        "assets": assets,
    }
    path = Path(__file__).parent / "manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(assets), "clipped_samples": sum(asset["clipped_samples"] for asset in assets), "manifest": path.relative_to(PROJECT).as_posix()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
