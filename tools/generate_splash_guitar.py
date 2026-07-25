"""Génère assets/audio/splash_guitar_soft.wav — arpège grave type guitare nylon."""
import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
DURATION = 3.2

# Arpège grave Mi-La-Ré-Sol (Hz) — cordes plus graves
NOTES = [
    (0.00, 82.41),   # E2
    (0.42, 110.00),  # A2
    (0.84, 146.83),  # D3
    (1.30, 196.00),  # G3
    (1.85, 246.94),  # B3
    (2.35, 329.63),  # E4
]


def pluck(freq: float, t: float, attack: float = 0.018, decay: float = 2.2) -> float:
    if t < 0:
        return 0.0
    env = math.exp(-t / decay) * (1 - math.exp(-t / attack))
    s = math.sin(2 * math.pi * freq * t)
    s += 0.42 * math.sin(2 * math.pi * freq * 2 * t) * math.exp(-t / 0.85)
    s += 0.18 * math.sin(2 * math.pi * freq * 3 * t) * math.exp(-t / 0.45)
    s += 0.06 * math.sin(2 * math.pi * freq * 4 * t) * math.exp(-t / 0.25)
    return s * env


def main() -> None:
    n = int(SAMPLE_RATE * DURATION)
    samples = [0.0] * n
    for start, freq in NOTES:
        i0 = int(start * SAMPLE_RATE)
        for i in range(i0, n):
            t = (i - i0) / SAMPLE_RATE
            samples[i] += pluck(freq, t) * 0.19

    peak = max(abs(s) for s in samples) or 1.0
    samples = [int(32767 * 0.9 * s / peak) for s in samples]

    out = Path(__file__).resolve().parents[1] / "assets" / "audio" / "splash_guitar_soft.wav"
    out.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out), "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(b"".join(struct.pack("<h", s) for s in samples))
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
