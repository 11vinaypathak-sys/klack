"""Measures what the Softness filter actually does to a sound pack.

Mirrors `ClickAudioEngine.soften(_:amount:)` in Sources/Klack/AudioEngine.swift.
If that filter changes, change this too -- the point of this script is to prove
the tone claim with numbers rather than by ear.

Usage: python3 build-scripts/tone_check.py path/to/click_down_1.wav [amount]
"""

import wave
import struct
import math
import sys
import os


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr, n, ch, sw = w.getframerate(), w.getnframes(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(n)
    if sw != 2:
        raise SystemExit("expected 16-bit PCM, got %d-bit" % (sw * 8))
    vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
    return sr, [vals[i * ch] / 32768.0 for i in range(n)]


def soften(x, sr, amount):
    if amount <= 0.001:
        return list(x)
    coeff = 1 - math.exp(-2 * math.pi * 2000 / sr)
    keep = 1 - amount
    low1 = low2 = 0.0
    out = []
    for s in x:
        low1 += coeff * (s - low1)
        low2 += coeff * (low1 - low2)
        out.append(low2 + (s - low2) * keep)
    return out


def band_energy(x, sr, lo, hi, bins=24):
    """Goertzel over log-spaced probes across the band."""
    total = 0.0
    for k in range(bins):
        f = lo * (hi / lo) ** (k / (bins - 1))
        w = 2 * math.pi * f / sr
        c = 2 * math.cos(w)
        s1 = s2 = 0.0
        for v in x:
            s0 = v + c * s1 - s2
            s2, s1 = s1, s0
        total += s1 * s1 + s2 * s2 - c * s1 * s2
    return total / bins


def main():
    path = sys.argv[1]
    amount = float(sys.argv[2]) if len(sys.argv) > 2 else 0.45
    sr, x = read_wav(path)
    label = os.path.join(os.path.basename(os.path.dirname(path)), os.path.basename(path))
    print("%s  %d Hz, %d frames, softness %.2f\n" % (label, sr, len(x), amount))

    y = soften(x, sr, amount)
    bands = [
        ("low   60-800 Hz", 60, 800),
        ("mid   800-3k", 800, 3000),
        ("HARSH 3k-6k", 3000, 6000),
        ("air   6k-14k", 6000, 14000),
    ]

    print("%-16s %10s %12s %10s" % ("band", "raw", "softened", "change"))
    print("-" * 51)
    for name, lo, hi in bands:
        a = band_energy(x, sr, lo, hi)
        b = band_energy(y, sr, lo, hi)
        db = 10 * math.log10(b / a) if a > 1e-20 and b > 1e-20 else float("nan")
        print("%-16s %10.4f %12.4f %+9.1f dB" % (name, a, b, db))

    print("\n%-16s %10.4f %12.4f   (no make-up gain: see soften() notes)"
          % ("peak level", max(abs(v) for v in x), max(abs(v) for v in y)))


if __name__ == "__main__":
    main()
