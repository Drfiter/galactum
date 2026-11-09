#!/usr/bin/env python3
"""Genera los efectos de sonido y la música de Galactum por síntesis.

Todo el audio del juego sale de este script (sin archivos de terceros), así que
no hay licencias que revisar y se puede regenerar o ajustar cuando se quiera.

Uso:  python3 tools/gen_audio.py            (escribe assets/audio/*.wav)
Requiere: numpy.
"""
import os
import wave

import numpy as np

SR = 22050  # Hz, mono, 16 bits: suficiente para efectos y liviano para Android.
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(1234)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack=0.005, release=0.08):
    """Envolvente lineal de ataque y caída exponencial."""
    e = np.ones(n)
    a = max(1, int(SR * attack))
    e[:a] = np.linspace(0.0, 1.0, a)
    decay = np.exp(-np.arange(n) / (SR * release))
    return e * decay


def tone(freq, sec, shape="sine", attack=0.005, release=0.1):
    t = t_axis(sec)
    phase = 2 * np.pi * np.cumsum(np.broadcast_to(freq, t.shape)) / SR
    if shape == "square":
        w = np.sign(np.sin(phase)) * 0.6
    elif shape == "tri":
        w = 2 / np.pi * np.arcsin(np.sin(phase))
    else:
        w = np.sin(phase)
    return w * env(len(t), attack, release)


def lowpass(x, cutoff):
    """Filtro pasa-bajos de un polo (suficiente para suavizar ruido)."""
    a = np.exp(-2 * np.pi * np.asarray(cutoff) / SR)
    a = np.broadcast_to(a, x.shape)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


def seq(*parts):
    return np.concatenate(parts)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def write(name, x, peak=0.85):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    data = (x * 32767).astype("<i2").tobytes()
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("%-10s %5.2f s" % (name, len(x) / SR))


def sfx_click():
    t = t_axis(0.07)
    return tone(np.linspace(1500, 900, len(t)), 0.07, "tri", 0.002, 0.02)


def sfx_collect():
    return seq(tone(988, 0.07, "sine", 0.002, 0.05), tone(1319, 0.22, "sine", 0.002, 0.09)) + \
        0.3 * seq(tone(1976, 0.07, "sine", 0.002, 0.04), tone(2637, 0.22, "sine", 0.002, 0.06))


def sfx_upgrade():
    notes = [523, 659, 784, 1047]
    return seq(*[tone(f, 0.09, "tri", 0.003, 0.08) for f in notes[:-1]], tone(notes[-1], 0.35, "tri", 0.003, 0.15))


def sfx_launch():
    t = t_axis(0.55)
    noise = rng.uniform(-1, 1, len(t))
    sweep = lowpass(noise, np.linspace(300, 3200, len(t)))
    e = np.sin(np.pi * np.linspace(0, 1, len(t))) ** 1.5
    return sweep * e + 0.25 * tone(np.linspace(180, 420, len(t)), 0.55, "sine", 0.05, 0.4)


def sfx_laser():
    t = t_axis(0.18)
    return tone(np.linspace(1900, 320, len(t)), 0.18, "square", 0.001, 0.06)


def sfx_explosion():
    t = t_axis(0.9)
    noise = rng.uniform(-1, 1, len(t))
    body = lowpass(noise, np.linspace(1800, 120, len(t))) * env(len(t), 0.002, 0.28)
    thump = tone(np.linspace(110, 40, len(t)), 0.9, "sine", 0.001, 0.2)
    return body * 1.6 + thump


def sfx_alert():
    parts = []
    for _ in range(3):
        parts += [tone(880, 0.16, "square", 0.004, 0.5), tone(660, 0.16, "square", 0.004, 0.5)]
    return seq(*parts) * 0.6


def sfx_reward():
    arp = seq(*[tone(f, 0.08, "tri", 0.003, 0.1) for f in (523, 659, 784)])
    chord = mix(tone(1047, 0.7, "tri", 0.01, 0.35), tone(1319, 0.7, "tri", 0.01, 0.35), tone(1568, 0.7, "tri", 0.01, 0.35))
    return seq(arp, chord)


def sfx_error():
    return seq(tone(196, 0.1, "square", 0.002, 0.08), np.zeros(int(SR * 0.04)), tone(165, 0.16, "square", 0.002, 0.1)) * 0.7


def music_ambient():
    """Pad espacial en La menor (Am - F - C - G), 8 s por acorde, en bucle."""
    chord_sec = 8.0
    chords = [(220.0, 261.63, 329.63), (174.61, 220.0, 261.63), (130.81, 196.0, 261.63), (196.0, 246.94, 293.66)]
    total = chord_sec * len(chords)
    tail = 4.0
    n = int(SR * (total + tail))
    out = np.zeros(n)
    t_full = np.arange(n) / SR
    for i, notes in enumerate(chords):
        start = int(SR * i * chord_sec)
        length = int(SR * (chord_sec + tail))
        t = t_full[:length]
        shape = np.minimum(1.0, t / 2.5) * np.exp(-np.maximum(0.0, t - chord_sec + 1.0) / 1.6)
        pad = np.zeros(length)
        for f in notes:
            for detune in (-0.7, 0.0, 0.8):
                pad += np.sin(2 * np.pi * (f + detune) * t) + 0.25 * np.sin(2 * np.pi * 2 * (f + detune) * t)
        sub = 0.6 * np.sin(2 * np.pi * notes[0] / 2 * t)
        out[start:start + length] += (pad / 9.0 + sub) * shape
        # Arpegio suave de "sensores" sobre cada acorde.
        for k in range(16):
            f = notes[k % 3] * 2
            s0 = start + int(SR * k * 0.5)
            blip = tone(f, 0.45, "sine", 0.01, 0.18) * 0.18
            out[s0:s0 + len(blip)] += blip[: max(0, min(len(blip), n - s0))]
    # Bucle sin cortes: la cola posterior al final se suma al inicio.
    loop = out[: int(SR * total)].copy()
    loop[: int(SR * tail)] += out[int(SR * total):]
    return loop


def main():
    os.makedirs(OUT, exist_ok=True)
    write("click", sfx_click(), 0.5)
    write("collect", sfx_collect(), 0.7)
    write("upgrade", sfx_upgrade(), 0.7)
    write("launch", sfx_launch(), 0.7)
    write("laser", sfx_laser(), 0.45)
    write("explosion", sfx_explosion(), 0.85)
    write("alert", sfx_alert(), 0.6)
    write("reward", sfx_reward(), 0.7)
    write("error", sfx_error(), 0.5)
    write("music_ambient", music_ambient(), 0.55)


if __name__ == "__main__":
    main()
