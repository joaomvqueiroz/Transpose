"""Build six short PCM piano references from public-domain Splendid Grand samples.

One-time asset preparation only (not an app runtime dependency):
  python -m pip install numpy soundfile
  python tool/prepare_piano_samples.py
"""

from __future__ import annotations

import io
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen

import numpy as np
import soundfile as sf


SOURCE_COMMIT = "1c595d827b7fd7f0be3134aaed0f90b3662a09cf"
SAMPLES = {
    "E2": "MF E2.flac",
    "A2": "MF A2.flac",
    "D3": "MF D3.flac",
    "G3": "MF G3.flac",
    "B3": "MF B3.flac",
    "E4": "Mf E4.flac",
}
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "piano"


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for note, filename in SAMPLES.items():
        url = (
            "https://raw.githubusercontent.com/sfzinstruments/"
            f"SplendidGrandPiano/{SOURCE_COMMIT}/Samples/{quote(filename)}"
        )
        with urlopen(url, timeout=30) as response:
            samples, sample_rate = sf.read(io.BytesIO(response.read()), dtype="float32")
        if samples.ndim == 2:
            samples = samples.mean(axis=1)
        samples = samples[: round(sample_rate * 2.8)].copy()
        peak = float(np.max(np.abs(samples)))
        if peak > 0:
            samples *= min(2.0, 0.72 / peak)
        fade_frames = min(round(sample_rate * 0.35), len(samples))
        samples[-fade_frames:] *= np.linspace(1, 0, fade_frames, dtype="float32")
        destination = OUTPUT / f"{note}.wav"
        sf.write(destination, samples, sample_rate, subtype="PCM_16")
        print(f"{note}: {destination.name}, {len(samples) / sample_rate:.2f}s")


if __name__ == "__main__":
    main()
