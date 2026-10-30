"""
Synthesizes the game's original, royalty-free audio: a looping 1v1 battle theme, a calmer menu
theme, and short sound effects. Pure numpy, written as mono 16-bit WAV.

    python tool/make_audio.py
"""

import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
rng = np.random.default_rng(7)


def note(n):
    """MIDI note number -> Hz."""
    return 440.0 * 2 ** ((n - 69) / 12)


def env(length, a=0.005, d=0.1, s=0.6, r=0.05):
    n = int(length * SR)
    t = np.arange(n) / SR
    e = np.ones(n) * s
    an, dn, rn = int(a * SR), int(d * SR), int(r * SR)
    e[:an] = np.linspace(0, 1, max(an, 1))[:an]
    e[an:an + dn] = np.linspace(1, s, max(dn, 1))[:len(e[an:an + dn])]
    if rn:
        e[-rn:] *= np.linspace(1, 0, rn)
    return e, t


def saw(f, t, detune=0.0):
    out = np.zeros_like(t)
    for d in (-detune, 0, detune):
        ph = (t * f * (1 + d)) % 1.0
        out += 2 * ph - 1
    return out / 3


def square(f, t):
    return np.sign(np.sin(2 * np.pi * f * t))


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def add(buf, sig, at):
    i = int(at * SR)
    j = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:j] += sig[: j - i]


def kick(length=0.35):
    e, t = env(length, 0.001, 0.25, 0.0, 0.05)
    f = 110 * np.exp(-t * 18) + 42
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * e * 1.0


def snare(length=0.22):
    e, t = env(length, 0.001, 0.15, 0.0, 0.05)
    noise = rng.uniform(-1, 1, len(t))
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
    return (noise * 0.55 + tone * 0.5) * e


def hat(length=0.05, open_=False):
    e, t = env(length * (3 if open_ else 1), 0.001, 0.03, 0.0, 0.01)
    noise = rng.uniform(-1, 1, len(t))
    return np.diff(noise, prepend=0) * e * 0.25


def tone(n, length, kind="saw", vol=0.3, a=0.005, d=0.1, s=0.6, r=0.06, detune=0.004):
    e, t = env(length, a, d, s, r)
    f = note(n)
    if kind == "saw":
        w = saw(f, t, detune)
    elif kind == "square":
        w = square(f, t) * 0.6
    else:
        w = np.sin(2 * np.pi * f * t)
    return w * e * vol


def battle_theme():
    bpm = 148
    beat = 60 / bpm
    bars = 16
    total = bars * 4 * beat
    buf = np.zeros(int(total * SR) + SR)
    # D minor progression: Dm Bb F C | Dm Bb Gm A
    roots = [50, 46, 41, 48, 50, 46, 43, 45]
    chords = {50: [62, 65, 69], 46: [58, 62, 65], 41: [57, 60, 65], 48: [60, 64, 67], 43: [55, 58, 62], 45: [57, 61, 64]}
    for bar in range(bars):
        root = roots[(bar // 2) % len(roots)]
        t0 = bar * 4 * beat
        intro = bar < 2
        # drums
        for b in range(4):
            if not intro or b % 2 == 0:
                add(buf, kick(), t0 + b * beat)
            if b % 2 == 1 and not intro:
                add(buf, snare() * 0.8, t0 + b * beat)
            if bar % 4 == 3 and b == 3 and not intro:
                for k in range(4):
                    add(buf, snare() * (0.35 + 0.15 * k), t0 + b * beat + k * beat / 4)
        for e8 in range(8):
            add(buf, hat(open_=(e8 % 4 == 2)), t0 + e8 * beat / 2)
        # galloping bass (16ths: 1 . 1 1)
        for b in range(4):
            for k, on in enumerate([1, 0, 1, 1]):
                if on:
                    n = root - 12 + (12 if (b == 3 and k == 3) else 0)
                    add(buf, lowpass(tone(n, beat / 4 * 0.9, "saw", 0.45, 0.002, 0.05, 0.7, 0.02), 0.25), t0 + b * beat + k * beat / 4)
        # arpeggio lead after the intro
        if not intro:
            ch = chords[root]
            pattern = [0, 1, 2, 1, 2, 0, 1, 2]
            for k in range(16):
                n = ch[pattern[k % 8]] + (12 if bar >= 8 else 0)
                add(buf, tone(n, beat / 4 * 0.8, "square", 0.08, 0.002, 0.04, 0.5, 0.02), t0 + k * beat / 4)
        # brass-like pad stabs
        ch = chords[root]
        for n in ch:
            stab = lowpass(tone(n - 12, beat * 1.5, "saw", 0.07, 0.03, 0.3, 0.5, 0.2, 0.006), 0.18)
            add(buf, stab, t0)
            if not intro:
                add(buf, stab * 0.7, t0 + 2.5 * beat)
        # heroic melody in the second half
        if bar >= 8:
            mel = [74, 72, 74, 77, 76, 74, 72, 69] if bar % 2 == 0 else [70, 72, 74, 72, 69, 67, 69, 0]
            for k, n in enumerate(mel):
                if n:
                    add(buf, tone(n, beat / 2 * 0.95, "saw", 0.11, 0.01, 0.1, 0.7, 0.05, 0.003), t0 + k * beat / 2)
    buf = buf[: int(total * SR)]
    return buf


def menu_theme():
    bpm = 84
    beat = 60 / bpm
    bars = 8
    total = bars * 4 * beat
    buf = np.zeros(int(total * SR) + SR)
    roots = [50, 46, 41, 45]
    chords = {50: [62, 65, 69], 46: [58, 62, 65], 41: [57, 60, 65], 45: [57, 61, 64]}
    for bar in range(bars):
        root = roots[bar % 4]
        t0 = bar * 4 * beat
        for n in chords[root]:
            add(buf, lowpass(tone(n - 12, 4 * beat, "saw", 0.06, 0.6, 0.5, 0.8, 0.8, 0.007), 0.08), t0)
        add(buf, lowpass(tone(root - 12, 4 * beat, "sine", 0.25, 0.05, 0.5, 0.7, 0.4), 0.3), t0)
        for k in range(8):
            n = chords[root][[0, 1, 2, 1, 0, 2, 1, 2][k]] + 12
            add(buf, tone(n, beat * 0.45, "sine", 0.06, 0.005, 0.2, 0.2, 0.2), t0 + k * beat / 2)
        add(buf, kick() * 0.4, t0)
        add(buf, kick() * 0.3, t0 + 2 * beat)
    return buf[: int(total * SR)]


def soft_click():
    """A soft, rounded tap: low-mid pitch, a few ms of attack (no sharp edge), quick fade, and the
    highs filtered off. The old click was an 880 Hz sine that started at once, which rang harshly."""
    n = int(0.13 * SR)
    t = np.arange(n) / SR
    f = 330 + 90 * np.exp(-t / 0.012)  # a small downward glide gives it a "pop"
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) + 0.22 * np.sin(2 * ph)
    attack = np.minimum(1.0, t / 0.008)
    attack = 0.5 - 0.5 * np.cos(np.pi * attack)  # raised cosine: no click at the start
    x = body * attack * np.exp(-t / 0.028)
    x *= np.minimum(1.0, (n - 1 - np.arange(n)) / (0.02 * SR))  # ends at exactly zero
    return lowpass(lowpass(x, 0.3), 0.3)


def sfx():
    out = {}
    e, t = env(0.12, 0.001, 0.08, 0.0, 0.03)
    out["card"] = lowpass(rng.uniform(-1, 1, len(t)), 0.35) * e * 0.6
    e, t = env(0.35, 0.001, 0.2, 0.0, 0.1)
    out["hit"] = (kick(0.35) * 0.8 + lowpass(rng.uniform(-1, 1, len(t)), 0.5) * e * 0.5)
    e, t = env(0.4, 0.05, 0.3, 0.0, 0.05)
    sweep = np.sin(2 * np.pi * np.cumsum(300 + 900 * t / 0.4) / SR)
    out["whoosh"] = lowpass(rng.uniform(-1, 1, len(t)), 0.15) * e * 0.5 + sweep * e * 0.05
    e, t = env(0.25, 0.002, 0.1, 0.3, 0.1)
    out["step"] = np.sin(2 * np.pi * 520 * t) * e * 0.25
    clash = np.zeros(int(0.6 * SR))
    for f in (523, 659, 784, 1046):
        e, t = env(0.6, 0.001, 0.4, 0.0, 0.2)
        clash += np.sin(2 * np.pi * f * t) * e * 0.12
    out["reveal"] = clash + snare(0.6)[: len(clash)] * 0.3
    win = np.zeros(int(1.6 * SR))
    for k, n in enumerate([62, 66, 69, 74]):
        add(win, tone(n, 0.9 - k * 0.1, "saw", 0.18, 0.01, 0.2, 0.6, 0.3), k * 0.15)
    out["victory"] = win
    out["click"] = soft_click()
    heal = np.zeros(int(0.7 * SR))
    for k, n in enumerate([72, 76, 79, 84]):
        add(heal, tone(n, 0.35, "sine", 0.12), k * 0.08)
    out["heal"] = heal
    return out


def write(name, x):
    x = x / max(1e-9, np.max(np.abs(x))) * (0.45 if name == "click" else 0.85)  # the click stays gentle
    pcm = (x * 32767).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{name}.wav {len(x) / SR:.1f}s {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("battle", battle_theme())
    write("menu", menu_theme())
    for k, v in sfx().items():
        write(k, v)
