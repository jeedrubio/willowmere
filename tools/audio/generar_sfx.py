#!/usr/bin/env python3
"""Sintetiza los efectos de sonido del juego (estilo chiptune) y los guarda como WAV.

    python tools/audio/generar_sfx.py --salida audio/sfx

No usa ningún sonido externo: todo son ondas cuadradas, triangulares y ruido generadas aquí.
Cambia las notas o duraciones y vuelve a ejecutarlo para ajustar el sonido.
"""
import argparse
import os
import wave

import numpy as np

SR = 22050


def wave_shape(kind, phase, duty=0.5):
    if kind == "square":
        return np.where((phase % 1.0) < duty, 1.0, -1.0)
    if kind == "triangle":
        return 4.0 * np.abs((phase % 1.0) - 0.5) - 1.0
    if kind == "saw":
        return 2.0 * (phase % 1.0) - 1.0
    return np.sin(2 * np.pi * phase)


def tone(f0, dur, kind="square", f1=None, vol=0.4, duty=0.5, attack=0.004, decay=6.0, vibrato=0.0):
    """Una nota (o un barrido de f0 a f1) con ataque corto y caída exponencial."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = np.linspace(f0, f1 if f1 is not None else f0, n)
    if vibrato:
        f = f * (1 + 0.02 * np.sin(2 * np.pi * vibrato * t))
    phase = np.cumsum(f) / SR
    sig = wave_shape(kind, phase, duty)
    env = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-decay * t / max(dur, 1e-3))
    return sig * env * vol


def noise(dur, vol=0.4, lowpass=0.2, decay=8.0, seed=1):
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    raw = rng.uniform(-1, 1, n)
    out = np.zeros(n)
    acc = 0.0
    for i in range(n):  # filtro paso bajo de un polo
        acc += lowpass * (raw[i] - acc)
        out[i] = acc
    t = np.arange(n) / SR
    return out * np.exp(-decay * t / max(dur, 1e-3)) * vol * 3.0


def seq(*parts):
    return np.concatenate(parts)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def silence(dur):
    return np.zeros(int(SR * dur))


NOTE = {"C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "A5": 880.0, "B5": 987.77, "C6": 1046.5, "E6": 1318.5, "G6": 1568.0}

SOUNDS = {
    "ui_hover": lambda: tone(1500, 0.03, "square", vol=0.14, decay=8, duty=0.25),
    "ui_click": lambda: seq(tone(620, 0.035, "square", vol=0.28, duty=0.25), tone(930, 0.06, "square", vol=0.28, duty=0.25)),
    "ui_back": lambda: tone(720, 0.09, "triangle", f1=380, vol=0.4, decay=4),
    "ui_confirm": lambda: seq(*[tone(NOTE[n], 0.06, "triangle", vol=0.4, decay=3) for n in ("C5", "E5", "G5")]),
    "menu_open": lambda: tone(440, 0.08, "triangle", f1=700, vol=0.4, decay=3),
    "pickup": lambda: seq(tone(880, 0.05, "square", f1=1100, vol=0.28, duty=0.5, decay=3), tone(1320, 0.09, "square", vol=0.28, duty=0.5, decay=5)),
    "coin": lambda: seq(tone(NOTE["B5"], 0.05, "square", vol=0.28, decay=2), mix(tone(NOTE["E6"], 0.3, "square", vol=0.26, decay=7), tone(NOTE["E6"] / 2, 0.3, "triangle", vol=0.2, decay=7))),
    "harvest": lambda: mix(noise(0.09, vol=0.35, lowpass=0.35, decay=6), tone(420, 0.11, "triangle", f1=170, vol=0.5, decay=5)),
    "error": lambda: tone(170, 0.18, "saw", f1=105, vol=0.3, decay=3, vibrato=28),
    "bump": lambda: seq(tone(230, 0.05, "square", vol=0.25, duty=0.25, decay=3), tone(170, 0.07, "square", vol=0.22, duty=0.25, decay=4)),
    "quest_start": lambda: seq(*[tone(NOTE[n], 0.07, "triangle", vol=0.42, decay=3) for n in ("E5", "G5")], tone(NOTE["B5"], 0.18, "triangle", vol=0.42, decay=5)),
    "quest_complete": lambda: seq(*[tone(NOTE[n], 0.085, "square", vol=0.3, duty=0.25, decay=2) for n in ("C5", "E5", "G5", "C6")],
                                  mix(tone(NOTE["C6"], 0.5, "square", vol=0.25, duty=0.25, decay=5), tone(NOTE["E6"], 0.5, "triangle", vol=0.3, decay=5), tone(NOTE["G6"], 0.5, "triangle", vol=0.22, decay=5))),
    "door": lambda: mix(noise(0.15, vol=0.5, lowpass=0.08, decay=7), tone(105, 0.15, "sine", f1=58, vol=0.7, decay=5)),
    "save": lambda: seq(tone(NOTE["G5"], 0.08, "triangle", vol=0.4, decay=3), tone(NOTE["C6"], 0.22, "triangle", vol=0.4, decay=6)),
    "load": lambda: tone(300, 0.25, "triangle", f1=950, vol=0.35, decay=2.5),
    "talk": lambda: seq(tone(520, 0.035, "square", vol=0.2, duty=0.25), silence(0.01), tone(680, 0.045, "square", vol=0.2, duty=0.25)),
}


def save(path, data):
    peak = float(np.max(np.abs(data))) or 1.0
    data = data / max(peak, 1.0) * 0.9  # sin saturar
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--salida", default="audio/sfx")
    args = parser.parse_args()
    os.makedirs(args.salida, exist_ok=True)
    for name, build in SOUNDS.items():
        data = build()
        save(os.path.join(args.salida, name + ".wav"), data)
        print("  %-15s %.2f s" % (name, len(data) / SR))


if __name__ == "__main__":
    main()
