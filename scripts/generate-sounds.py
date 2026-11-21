import sys
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 48000
START_HZ = 392.0
STOP_HZ = 329.63
FAILURE_HZ = (196.0, 174.61)
PEAK_DBFS = {"start": -18, "stop": -19, "failure": -17}


def seconds(duration):
    return np.arange(int(SAMPLE_RATE * duration)) / SAMPLE_RATE


def envelope(duration, attack, decay):
    x = seconds(duration)
    rise = np.sin(np.clip(x / attack, 0, 1) * np.pi / 2) ** 2
    shape = rise * np.exp(-np.maximum(x - attack, 0) / decay)
    fade = int(SAMPLE_RATE * 0.004)
    shape[-fade:] *= np.linspace(1, 0, fade)
    return shape


def lowpass(signal, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SAMPLE_RATE)
    out = np.zeros_like(signal)
    state = 0.0
    for index, value in enumerate(signal):
        state = (1 - a) * value + a * state
        out[index] = state
    return out


def bloop(frequency, duration=0.16, low=0.7, glide=0.035, decay=0.045):
    x = seconds(duration)
    bend = 1 - (1 - low) * np.exp(-x / glide * 3)
    phase = 2 * np.pi * np.cumsum(frequency * bend) / SAMPLE_RATE
    tone = np.sin(phase) + 0.08 * np.sin(2 * phase)
    return lowpass(tone * envelope(duration, 0.003, decay), 1400)


def drop(frequency, duration=0.16, decay=0.045, amount=0.4):
    x = seconds(duration)
    bend = 1 + amount * np.exp(-x / 0.014)
    phase = 2 * np.pi * np.cumsum(frequency * bend) / SAMPLE_RATE
    return lowpass(np.sin(phase) * envelope(duration, 0.003, decay), 1400)


def layered(*parts):
    length = max(int(SAMPLE_RATE * at) + len(part) for at, part in parts)
    out = np.zeros(length)
    for at, part in parts:
        begin = int(SAMPLE_RATE * at)
        out[begin : begin + len(part)] += part
    return out


def finished(signal, peak_dbfs):
    signal = signal - np.mean(signal)
    signal = signal / np.max(np.abs(signal)) * 10 ** (peak_dbfs / 20)
    fade = int(SAMPLE_RATE * 0.005)
    signal[-fade:] *= np.linspace(1, 0, fade)
    return np.concatenate([signal, np.zeros(int(SAMPLE_RATE * 0.01))])


def write(path, signal):
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(SAMPLE_RATE)
        file.writeframes((signal * 32767).astype("<i2").tobytes())


def cues():
    first, second = FAILURE_HZ
    return {
        "start": bloop(START_HZ, low=0.68),
        "stop": drop(STOP_HZ, amount=0.4),
        "failure": layered(
            (0, bloop(first, low=0.9, decay=0.03)),
            (0.09, bloop(second, low=0.9, decay=0.035)),
        ),
    }


def main():
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    folder.mkdir(parents=True, exist_ok=True)
    for name, signal in cues().items():
        write(folder / f"tape-{name}.wav", finished(signal, PEAK_DBFS[name]))


if __name__ == "__main__":
    main()
