#!/usr/bin/env python3
"""Synthesises the keyboard themes' key sounds (docs/THEMES.md §4.3).

    python3 tools/gen_theme_sounds.py

Every sample is made here from sines, filtered noise and envelopes, so the
sounds are our own work and carry no licence. They stand in for the CC0
Freesound takes the spec names (which need an account to download) and
follow its descriptions: a typewriter's slab clack, bell and carriage
return; a rangefinder's focus detent and shutter; a wooden clap; a clicky
mechanical switch; a square-wave blip; a sonar ping.

Processing as §4.3 asks: mono, 3 ms fades, peaks normalised to -18 dBFS
(the sonar to -20), letters under 120 ms, the return under 600 ms. Each is
rendered at 22.05 kHz, 16-bit, then packed by macOS's afconvert as IMA4
in a .caf into app/ios/GlyfKeyboard/Sounds/, well under 20 KB each. The
Android keyboard gets the same samples as plain 22.05 kHz 16-bit mono WAVs
in app/android/app/src/main/res/raw/ (theme_<pack>_<role>.wav, under 30 KB
each), which SoundPool plays as they are.
Deterministic: the noise is seeded, so a rerun writes the same files.
"""
import math, os, random, struct, subprocess, sys, tempfile, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'app', 'ios', 'GlyfKeyboard', 'Sounds')
OUT_ANDROID = os.path.join(ROOT, 'app', 'android', 'app', 'src', 'main', 'res', 'raw')
SR = 22050


def silence(ms):
    return [0.0] * int(SR * ms / 1000)


def noise(n, rng):
    return [rng.uniform(-1, 1) for _ in range(n)]


def highpass(x, fc):
    rc = 1 / (2 * math.pi * fc)
    a = rc / (rc + 1 / SR)
    y, prev_x, prev_y = [], 0.0, 0.0
    for v in x:
        prev_y = a * (prev_y + v - prev_x)
        prev_x = v
        y.append(prev_y)
    return y


def lowpass(x, fc):
    a = (1 / SR) / (1 / (2 * math.pi * fc) + 1 / SR)
    y, p = [], 0.0
    for v in x:
        p += a * (v - p)
        y.append(p)
    return y


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def decay(n, tau_ms, attack_ms=0.5):
    att = max(1, int(SR * attack_ms / 1000))
    tau = SR * tau_ms / 1000
    return [(i / att if i < att else 1.0) * math.exp(-max(0, i - att) / tau) for i in range(n)]


def mode(freq, tau_ms, ms, phase=0.0, attack_ms=0.3):
    """One damped resonance: a struck body's partial."""
    n = int(SR * ms / 1000)
    env = decay(n, tau_ms, attack_ms)
    return [env[i] * math.sin(2 * math.pi * freq * i / SR + phase) for i in range(n)]


def burst(ms, tau_ms, lo, hi, rng):
    """A filtered noise transient: the click of two hard things meeting."""
    n = int(SR * ms / 1000)
    env = decay(n, tau_ms, 0.2)
    return [a * b for a, b in zip(bandpass(noise(n, rng), lo, hi), env)]


def mix(*parts):
    """(offset_ms, gain, samples) parts summed into one buffer."""
    n = max(int(SR * off / 1000) + len(s) for off, _, s in parts)
    out = [0.0] * n
    for off, gain, s in parts:
        o = int(SR * off / 1000)
        for i, v in enumerate(s):
            out[o + i] += gain * v
    return out


def square(freq, ms):
    """Band-limited square: odd harmonics under Nyquist."""
    n = int(SR * ms / 1000)
    ks = [k for k in range(1, 40, 2) if k * freq < SR / 2 * 0.9]
    return [sum(math.sin(2 * math.pi * k * freq * i / SR) / k for k in ks) * 4 / math.pi for i in range(n)]


def shape(x, env):
    return [a * b for a, b in zip(x, env)]


def resample(x, factor):
    """Pitch down by `factor` (>1 plays slower and lower)."""
    n = int(len(x) * factor)
    out = []
    for i in range(n):
        p = i / factor
        j = int(p)
        f = p - j
        a = x[j] if j < len(x) else 0.0
        b = x[j + 1] if j + 1 < len(x) else 0.0
        out.append(a + (b - a) * f)
    return out


def finish(x, peak_dbfs=-18.0, gain=1.0, max_ms=None):
    if max_ms:
        x = x[:int(SR * max_ms / 1000)]
    # Trim the tail once it has fallen 60 dB under the peak.
    top = max(abs(v) for v in x) or 1.0
    end = len(x)
    while end > 1 and abs(x[end - 1]) < top * 1e-3:
        end -= 1
    x = x[:end]
    fade = int(SR * 0.003)
    for i in range(min(fade, len(x))):
        x[i] *= i / fade
        x[-1 - i] *= i / fade
    target = 10 ** (peak_dbfs / 20) * gain
    top = max(abs(v) for v in x) or 1.0
    return [v * target / top for v in x]


# MARK: The packs

def typewriter(rng):
    def stroke(body=1.0):
        # Typebar on the platen: a sharp crack, the slab's ring, the
        # carriage's dull thunk, and the escapement's tick a beat later.
        return mix((0, 1.0, burst(30, 3.5, 1800, 7000, rng)),
                   (0, 0.55 * body, mode(1150, 9, 60)),
                   (0, 0.45 * body, mode(210, 18, 90)),
                   (18, 0.35, burst(20, 2.5, 2500, 8000, rng)))
    letter = finish(stroke(), max_ms=116)
    space = finish(resample(stroke(1.2), 2 ** (2 / 12)), gain=0.7, max_ms=120)
    delete = finish(mix((0, 1.0, burst(25, 3.0, 1500, 6000, rng)),
                        (0, 0.5, mode(900, 8, 50)),
                        (0, 0.4, mode(180, 15, 70))), max_ms=90)
    # The bell, then the carriage coming home: a ratchet run and a stop.
    bell_parts = [(2100, 1.0, 380), (2100 * 2.76, 0.35, 160), (2100 * 5.40, 0.15, 80), (2100 * 1.51, 0.2, 220)]
    bell = mix(*[(0, g, mode(f, tau, 420)) for f, g, tau in bell_parts])
    ratchet = mix(*[(i * 11, 0.4 * (0.6 + 0.4 * rng.random()), burst(10, 1.5, 2000, 7000, rng))
                    for i in range(12)])
    ret = finish(mix((0, 1.0, bell), (300, 0.8, ratchet),
                     (440, 1.0, stroke(1.6))), max_ms=600)
    return {'letter': letter, 'space': space, 'delete': delete, 'return': ret}


def shutter(rng):
    # The focus ring's detent: one tiny, bright tick.
    letter = finish(mix((0, 1.0, burst(25, 2.0, 2500, 9000, rng)),
                        (0, 0.3, mode(3200, 3, 25))), max_ms=25)
    # One full shutter: release, first curtain, a short whir, second curtain.
    whir = shape(bandpass(noise(int(SR * 0.06), rng), 600, 3000), decay(int(SR * 0.06), 25, 5))
    ret = finish(mix((0, 0.6, burst(15, 2.0, 1500, 6000, rng)),
                     (8, 1.0, burst(30, 4.0, 1200, 8000, rng)),
                     (8, 0.4, mode(700, 10, 40)),
                     (20, 0.25, whir),
                     (70, 0.9, burst(35, 5.0, 900, 7000, rng)),
                     (70, 0.45, mode(520, 14, 60))), max_ms=220)
    return {'letter': letter, 'return': ret}


def wood(rng):
    def clap(f=1.0, ms=61):
        # Hard wood on wood: a few inharmonic body modes over a short knock.
        return mix((0, 0.8, burst(12, 1.5, 600 * f, 5000 * f, rng)),
                   (0, 1.0, mode(820 * f, 10, ms)),
                   (0, 0.6, mode(1460 * f, 7, ms)),
                   (0, 0.35, mode(2630 * f, 4, ms)),
                   (0, 0.3, mode(410 * f, 14, ms)))
    letter = finish(clap(), max_ms=61)
    # Pitched down five semitones: the hyoshigi's clap.
    ret = finish(resample(clap(ms=120), 2 ** (5 / 12)), max_ms=200)
    return {'letter': letter, 'return': ret}


def mech(rng):
    def stroke(low, ms):
        # A clicky switch: the click jacket's snap, then the keycap bottoming
        # out on the plate, then the spring's faint ping.
        return mix((0, 1.0, burst(12, 1.2, 3500, 9500, rng)),
                   (4, 0.7, burst(30, 4.0, 400, 3000, rng)),
                   (4, 0.5, mode(low, 12, ms)),
                   (6, 0.08, mode(5200, 30, ms)))
    letter = finish(stroke(330, 70), max_ms=90)
    # The space bar: deeper, and its stabiliser's rattle.
    space = finish(mix((0, 1.0, stroke(190, 110)),
                       (14, 0.3, burst(25, 4.0, 800, 4000, rng))), max_ms=120)
    return {'letter': letter, 'space': space}


def synth(rng):
    def blip(freq, ms):
        n = int(SR * ms / 1000)
        return shape(square(freq, ms), decay(n, ms / 3.2, 3))
    letter = finish(blip(2400, 18))
    ret = finish(mix((0, 1.0, blip(1600, 30)), (30, 1.0, blip(2400, 30))))
    return {'letter': letter, 'return': ret}


def sonar(rng):
    # Letters keep the system click; the return pings.
    n = int(SR * 0.45)
    env = decay(n, 280 / 3.0, 5)
    ping = [env[i] * math.sin(2 * math.pi * 1200 * i / SR) for i in range(n)]
    return {'return': finish(ping, peak_dbfs=-20, max_ms=450)}


PACKS = {'typewriter': typewriter, 'shutter': shutter, 'wood': wood,
         'mech': mech, 'synth': synth, 'sonar': sonar}


def write_wav(samples, path):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', max(-32767, min(32767, int(v * 32767)))) for v in samples))


def write(samples, path):
    tmp = tempfile.NamedTemporaryFile(suffix='.wav', delete=False).name
    write_wav(samples, tmp)
    subprocess.run(['afconvert', '-f', 'caff', '-d', 'ima4', tmp, path], check=True)
    os.remove(tmp)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(OUT_ANDROID, exist_ok=True)
    for name, make in PACKS.items():
        rng = random.Random(name)
        for role, samples in make(rng).items():
            path = os.path.join(OUT, 'theme-%s-%s.caf' % (name, role))
            write(samples, path)
            # Android resource names: lowercase letters, digits, underscores.
            wav = os.path.join(OUT_ANDROID, 'theme_%s_%s.wav' % (name, role))
            write_wav(samples, wav)
            print('%-34s %4d ms %6d bytes (wav %6d)' % (os.path.basename(path), len(samples) * 1000 // SR,
                                                         os.path.getsize(path), os.path.getsize(wav)))


if __name__ == '__main__':
    sys.exit(main())
