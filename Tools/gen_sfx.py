#!/usr/bin/env python3
"""Generates a small pack of original, royalty-free-by-construction SFX as mono 16-bit WAV files.

Every sound here is synthesized from sine oscillators and filtered noise — no third-party
samples, no licensing concerns. This is a placeholder starter pack for the bundled audio
library (Priority 20); swap/extend with better-produced assets later without touching any
app code, since the library only reads the catalog manifest + files in this folder.
"""
import math
import random
import struct
import wave
import os

SR = 44100
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "Features", "Editor", "AudioLibrary", "SFX")


def write_wav(name, samples):
    path = os.path.join(OUT_DIR, name)
    peak = max(0.0001, max(abs(s) for s in samples))
    scale = min(1.0, 0.92 / peak)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s * scale)) * 32767)
            frames += struct.pack("<h", v)
        f.writeframes(bytes(frames))
    print(f"wrote {path} ({len(samples) / SR:.2f}s)")


def n_samples(duration):
    return int(SR * duration)


def lowpass(samples, cutoff_series):
    """One-pole low-pass; cutoff_series is either a float or a per-sample list (Hz)."""
    out = [0.0] * len(samples)
    prev = 0.0
    for i, x in enumerate(samples):
        cutoff = cutoff_series[i] if isinstance(cutoff_series, list) else cutoff_series
        alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
        prev = prev + alpha * (x - prev)
        out[i] = prev
    return out


def highpass(samples, cutoff):
    lp = lowpass(samples, cutoff)
    return [a - b for a, b in zip(samples, lp)]


def noise(count, seed):
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(count)]


def line(count, a, b):
    if count <= 1:
        return [b] * max(count, 0)
    return [a + (b - a) * i / (count - 1) for i in range(count)]


def env_fade(count, attack, release):
    a = n_samples(attack)
    r = n_samples(release)
    out = [1.0] * count
    for i in range(min(a, count)):
        out[i] = i / max(1, a)
    for i in range(min(r, count)):
        out[count - 1 - i] = min(out[count - 1 - i], i / max(1, r))
    return out


def sine_tone(freq_series, duration, amp_env=None):
    count = n_samples(duration)
    out = [0.0] * count
    phase = 0.0
    for i in range(count):
        f = freq_series[i] if isinstance(freq_series, list) else freq_series
        phase += 2 * math.pi * f / SR
        v = math.sin(phase)
        if amp_env is not None:
            v *= amp_env[i]
        out[i] = v
    return out


def mix(*tracks):
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


# --- click.wav ---
c = n_samples(0.07)
body = sine_tone(1400, 0.07, env_fade(c, 0.001, 0.06))
hiss = [x * e * 0.25 for x, e in zip(noise(c, 1), env_fade(c, 0.001, 0.04))]
write_wav("click.wav", mix(body, hiss))

# --- pop.wav ---
c = n_samples(0.16)
freq = line(c, 900, 160)
body = sine_tone(freq, 0.16, env_fade(c, 0.002, 0.14))
write_wav("pop.wav", body)

# --- whoosh_short.wav ---
c = n_samples(0.7)
raw = noise(c, 2)
cutoff = [400 + 3200 * math.sin(math.pi * i / c) for i in range(c)]
filtered = highpass(lowpass(raw, cutoff), 200)
e = env_fade(c, 0.08, 0.35)
write_wav("whoosh_short.wav", [x * ev for x, ev in zip(filtered, e)])

# --- whoosh_long.wav ---
c = n_samples(1.6)
raw = noise(c, 3)
cutoff = [300 + 4500 * (i / c) for i in range(c)]
filtered = highpass(lowpass(raw, cutoff), 150)
e = env_fade(c, 0.25, 0.7)
write_wav("whoosh_long.wav", [x * ev for x, ev in zip(filtered, e)])

# --- riser.wav ---
c = n_samples(2.0)
freq = line(c, 180, 1800)
e = [ (i / c) ** 1.5 for i in range(c) ]
tone = sine_tone(freq, 2.0, e)
raw = noise(c, 4)
cutoff = [500 + 6000 * (i / c) for i in range(c)]
shimmer = [x * ev * 0.35 for x, ev in zip(highpass(lowpass(raw, cutoff), 300), e)]
write_wav("riser.wav", mix(tone, shimmer))

# --- impact.wav ---
c = n_samples(0.65)
thump = sine_tone(70, 0.65, env_fade(c, 0.001, 0.6))
raw = noise(n_samples(0.05), 5)
transient = raw + [0.0] * (c - len(raw))
transient = [x * e for x, e in zip(transient, env_fade(c, 0.0005, 0.05))]
write_wav("impact.wav", mix(thump, transient))

# --- drum_hit.wav ---
c = n_samples(0.3)
freq = line(c, 180, 55)
body = sine_tone(freq, 0.3, env_fade(c, 0.001, 0.28))
write_wav("drum_hit.wav", body)

# --- chime.wav ---
c = n_samples(1.6)
e = env_fade(c, 0.01, 1.5)
h1 = sine_tone(880.0, 1.6, e)
h2 = [v * 0.5 for v in sine_tone(1318.5, 1.6, e)]
h3 = [v * 0.3 for v in sine_tone(1760.0, 1.6, e)]
write_wav("chime.wav", mix(h1, h2, h3))

# --- notification.wav ---
c1 = n_samples(0.12)
c2 = n_samples(0.16)
tone1 = sine_tone(880.0, 0.12, env_fade(c1, 0.005, 0.1))
tone2 = sine_tone(1318.5, 0.16, env_fade(c2, 0.005, 0.14))
gap = [0.0] * n_samples(0.04)
write_wav("notification.wav", tone1 + gap + tone2)

# --- sparkle.wav ---
parts = []
rng = random.Random(7)
for i in range(6):
    d = 0.09
    c = n_samples(d)
    f = rng.uniform(1800, 3600)
    parts.append([v * 0.8 for v in sine_tone(f, d, env_fade(c, 0.002, 0.08))])
    parts.append([0.0] * n_samples(0.03))
flat = []
for p in parts:
    flat.extend(p)
write_wav("sparkle.wav", flat)

# --- transition_swoosh.wav ---
c = n_samples(1.0)
raw = noise(c, 8)
cutoff = [300 + 5000 * math.sin(math.pi * i / c) for i in range(c)]
filtered = highpass(lowpass(raw, cutoff), 250)
e = env_fade(c, 0.15, 0.5)
noise_part = [x * ev for x, ev in zip(filtered, e)]
freq = [220 + 900 * math.sin(math.pi * i / c) for i in range(c)]
tone_part = [v * ev * 0.4 for v, ev in zip(sine_tone(freq, 1.0, [1.0] * c), e)]
write_wav("transition_swoosh.wav", mix(noise_part, tone_part))

# --- camera_shutter.wav ---
c = n_samples(0.04)
click1 = [x * e for x, e in zip(noise(c, 9), env_fade(c, 0.0005, 0.03))]
gap = [0.0] * n_samples(0.05)
c2 = n_samples(0.05)
click2 = [x * e for x, e in zip(noise(c2, 10), env_fade(c2, 0.0005, 0.04))]
write_wav("camera_shutter.wav", click1 + gap + click2)

print("done")
