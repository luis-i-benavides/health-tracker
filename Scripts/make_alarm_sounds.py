#!/usr/bin/env python3
"""Generates the alarm sounds in health-tracker/Sounds (run from the repository root).

Each sound is synthesized here, so there are no licensing concerns. Files are ~28 seconds
(iOS plays custom alert sounds for at most 30 seconds) and are converted to IMA4 .caf with
afconvert to keep them small.
"""
import math, os, struct, subprocess, tempfile, wave

RATE = 22050
LENGTH = 28.0
OUT = "health-tracker/Sounds"


def tone(freq, t, harmonics=((1, 1.0),)):
    return sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in harmonics)


def render(name, sample):
    frames = bytearray()
    for i in range(int(RATE * LENGTH)):
        t = i / RATE
        v = max(-1.0, min(1.0, sample(t)))
        frames += struct.pack("<h", int(v * 32000))
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(bytes(frames))
        subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", wav, os.path.join(OUT, name + ".caf")], check=True)


def chime(t):
    """Two bell notes (E6 then C6) every 2 seconds."""
    period = 2.0
    p = t % period
    bell = ((1, 1.0), (2.76, 0.4), (5.4, 0.2))
    out = 0.0
    for start, freq in ((0.0, 1318.5), (0.5, 1046.5)):
        if p >= start:
            d = p - start
            out += 0.45 * math.exp(-3.0 * d) * tone(freq, d, bell) * min(1, d * 400)
    return out


def classic(t):
    """Classic alarm-clock beeps: four quick beeps, then a pause."""
    p = t % 1.0
    for k in range(4):
        start = k * 0.12
        if start <= p < start + 0.08:
            d = p - start
            env = min(1, d * 300, (0.08 - d) * 300)
            return 0.55 * env * tone(2000, t, ((1, 1.0), (3, 0.15)))
    return 0.0


def gentle(t):
    """Soft rising arpeggio (C5 E5 G5 C6) that gets louder over the first 20 seconds."""
    notes = (523.25, 659.25, 783.99, 1046.5)
    step = 0.35
    cycle = step * len(notes) + 0.6
    p = t % cycle
    k = int(p // step)
    if k >= len(notes):
        return 0.0
    d = p - k * step
    loudness = 0.25 + 0.55 * min(1.0, t / 20.0)
    return loudness * math.exp(-4.0 * d) * tone(notes[k], d, ((1, 1.0), (4, 0.1))) * min(1, d * 300)


def pulse(t):
    """Steady low pulsing tone, half a second on, half off."""
    p = t % 1.0
    if p >= 0.5:
        return 0.0
    env = math.sin(math.pi * p / 0.5)
    return 0.6 * env * tone(660, t, ((1, 1.0), (2, 0.3)))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("alarm-chime", chime), ("alarm-classic", classic), ("alarm-gentle", gentle), ("alarm-pulse", pulse)):
        render(name, fn)
        print("wrote", os.path.join(OUT, name + ".caf"))
