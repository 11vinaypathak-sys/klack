#!/usr/bin/env python3
"""Synthesizes mechanical-keyboard click sounds procedurally (no sampled audio).

Uses modal synthesis: a struck plastic/switch object is modeled as a brief
noise "knock" transient plus a small bank of decaying sine oscillators at
inharmonic frequency ratios (the resonant "modes" of the object), plus a
low-frequency body resonance for weight ("thock"). This is the standard
technique for synthesizing convincing percussive impacts -- a single filtered
noise burst reads as static/pop, not a solid object being struck.

Generates several distinct sound "profiles" (switch/board characters) into
Resources/profiles/<name>/, so the app can let you switch between them live.
"""
import math
import random
import struct
import wave
import os

SR = 44100


def make_modal_click(duration_ms, base_freq, mode_ratios, mode_decays_ms, mode_amps,
                      noise_burst_ms, noise_decay_ms, noise_mix,
                      thump_freq, thump_decay_ms, thump_mix, seed):
    rng = random.Random(seed)
    n = int(SR * duration_ms / 1000)
    out = [0.0] * n

    # 1. Brief broadband noise transient -- the mechanical "knock" of impact.
    for i in range(n):
        t_ms = i * 1000 / SR
        if t_ms >= noise_burst_ms:
            break
        env = math.exp(-t_ms / noise_decay_ms)
        out[i] += rng.uniform(-1, 1) * env * noise_mix

    # 2. Resonant modes -- decaying sinusoids at inharmonic ratios, like the
    #    ringing of a small struck plastic/metal part.
    for ratio, decay_ms, amp in zip(mode_ratios, mode_decays_ms, mode_amps):
        freq = base_freq * ratio
        phase = rng.uniform(0, 2 * math.pi)
        for i in range(n):
            t_ms = i * 1000 / SR
            env = math.exp(-t_ms / decay_ms)
            out[i] += math.sin(2 * math.pi * freq * i / SR + phase) * env * amp

    # 3. Low body resonance -- the "thock", gives it weight/roundness.
    thump_phase = rng.uniform(0, 2 * math.pi)
    for i in range(n):
        t_ms = i * 1000 / SR
        env = math.exp(-t_ms / thump_decay_ms)
        out[i] += math.sin(2 * math.pi * thump_freq * i / SR + thump_phase) * env * thump_mix

    attack_samples = max(1, int(SR * 0.0003))
    for i in range(min(attack_samples, n)):
        out[i] *= i / attack_samples

    peak = max(abs(s) for s in out) or 1.0
    target = 0.85
    return [s * (target / peak) for s in out]


def write_wav(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        f.writeframes(frames)


def jitter(values, pct, rng):
    return [v * rng.uniform(1 - pct, 1 + pct) for v in values]


def allpass(signal, delay_ms, g=0.5):
    """Standard Schroeder allpass filter: y[n] = -g*x[n] + x[n-D] + g*y[n-D]."""
    d = max(1, int(SR * delay_ms / 1000))
    n = len(signal)
    y = [0.0] * n
    for i in range(n):
        x_delayed = signal[i - d] if i - d >= 0 else 0.0
        y_delayed = y[i - d] if i - d >= 0 else 0.0
        y[i] = -g * signal[i] + x_delayed + g * y_delayed
    return y


def comb(signal, delay_ms, gain):
    d = max(1, int(SR * delay_ms / 1000))
    n = len(signal)
    out = [0.0] * n
    for i in range(n):
        delayed = out[i - d] if i - d >= 0 else 0.0
        out[i] = signal[i] + delayed * gain
    return out


def apply_reverb(dry, room_decay=0.55):
    """Small Schroeder-style reverb: parallel combs (the smooth diffuse wash)
    feeding into a couple of allpass stages (extra smearing/diffusion)."""
    comb_delays = [29.7, 37.1, 41.3, 43.7]
    wet = [0.0] * len(dry)
    for delay_ms in comb_delays:
        c = comb(dry, delay_ms, room_decay)
        for i in range(len(wet)):
            wet[i] += c[i] / len(comb_delays)
    wet = allpass(wet, 5.0, g=0.5)
    wet = allpass(wet, 1.7, g=0.5)
    return wet


def make_soft_chime(total_ms, base_freq, ratios, amps, attack_ms, decay_ms,
                     reverb_mix, room_decay, seed):
    """A tonal, soft-attack chime (not a percussive knock) with an algorithmic
    reverb tail layered on -- this is what gives it that airy/spacious,
    'premium UI sound' character instead of a mechanical click."""
    rng = random.Random(seed)
    n = int(SR * total_ms / 1000)
    dry = [0.0] * n
    for ratio, amp in zip(ratios, amps):
        freq = base_freq * ratio
        phase = rng.uniform(0, 2 * math.pi)
        for i in range(n):
            t_ms = i * 1000 / SR
            attack = min(1.0, t_ms / attack_ms) if attack_ms > 0 else 1.0
            attack = math.sin(attack * math.pi / 2)  # smooth ease-in, not a hard onset
            env = attack * math.exp(-t_ms / decay_ms)
            dry[i] += math.sin(2 * math.pi * freq * i / SR + phase) * env * amp

    wet = apply_reverb(dry, room_decay=room_decay)
    mixed = [d * (1 - reverb_mix) + w * reverb_mix for d, w in zip(dry, wet)]

    peak = max(abs(s) for s in mixed) or 1.0
    target = 0.7  # softer overall than the mechanical profiles
    return [s * (target / peak) for s in mixed]


def generate_airy_profile(out_dir, seed_base):
    name = "airy"
    rng = random.Random(seed_base)
    ratios = [1.0, 2.0, 3.0]

    for i in range(1, 7):
        samples = make_soft_chime(
            total_ms=280,
            base_freq=rng.uniform(720, 980),
            ratios=ratios,
            amps=[0.5, 0.20, 0.09],
            attack_ms=rng.uniform(6, 10),
            decay_ms=rng.uniform(35, 55),
            reverb_mix=0.42,
            room_decay=0.55,
            seed=seed_base + i,
        )
        write_wav(os.path.join(out_dir, name, f"click_down_{i}.wav"), samples)

    for i in range(1, 4):
        samples = make_soft_chime(
            total_ms=200,
            base_freq=rng.uniform(950, 1250),
            ratios=ratios,
            amps=[0.35, 0.14, 0.06],
            attack_ms=rng.uniform(4, 7),
            decay_ms=rng.uniform(20, 32),
            reverb_mix=0.35,
            room_decay=0.5,
            seed=seed_base + 100 + i,
        )
        write_wav(os.path.join(out_dir, name, f"click_up_{i}.wav"), samples)

    space_down = make_soft_chime(
        total_ms=340, base_freq=560, ratios=ratios, amps=[0.55, 0.22, 0.10],
        attack_ms=9, decay_ms=60, reverb_mix=0.48, room_decay=0.6, seed=seed_base + 999,
    )
    write_wav(os.path.join(out_dir, name, "click_space_down.wav"), space_down)

    space_up = make_soft_chime(
        total_ms=220, base_freq=780, ratios=ratios, amps=[0.32, 0.13, 0.05],
        attack_ms=5, decay_ms=28, reverb_mix=0.35, room_decay=0.5, seed=seed_base + 998,
    )
    write_wav(os.path.join(out_dir, name, "click_space_up.wav"), space_up)

    print(f"Generated profile '{name}': Soft, tonal, reverb-tailed chime (airy/premium UI style)")


# Each profile is a distinct "switch/board character". Ratios are inharmonic
# (not 1x/2x/3x) so it reads as plastic/metal, not a musical tone.
PROFILES = {
    "deep_thock": {
        "desc": "Deep, round, satisfying thock (lubed/silent-ish switches)",
        "ratios": [1.0, 1.55, 2.1, 2.85],
        "down_base": (1500, 2200), "down_dur": 75,
        "down_mode_decays": [11, 7, 5, 3.5], "down_mode_amps": [0.28, 0.20, 0.14, 0.09],
        "down_noise_ms": 2.5, "down_noise_decay": 1.8, "down_noise_mix": 0.45,
        "down_thump": (130, 190), "down_thump_decay": (22, 32), "down_thump_mix": 0.55,
        "up_base": (2000, 2700), "up_dur": 45,
        "up_mode_decays": [6, 4, 3, 2], "up_mode_amps": [0.22, 0.15, 0.10, 0.06],
        "up_noise_ms": 1.5, "up_noise_decay": 1.2, "up_noise_mix": 0.35,
        "up_thump": (160, 220), "up_thump_decay": (10, 16), "up_thump_mix": 0.25,
        "space_base": 1150, "space_thump": 95, "space_thump_decay": 42, "space_thump_mix": 0.75,
    },
    "the_bench": {
        "desc": "Flagship tuning aimed at the classic 'most satisfying' consensus: deep and rounded, with just enough high-end definition to feel crisp, tight clean decay, no rattle",
        "ratios": [1.0, 1.5, 2.05, 2.7],
        "down_base": (1350, 1850), "down_dur": 68,
        "down_mode_decays": [9, 6, 4, 3], "down_mode_amps": [0.24, 0.19, 0.15, 0.10],
        "down_noise_ms": 2.0, "down_noise_decay": 1.5, "down_noise_mix": 0.4,
        "down_thump": (140, 195), "down_thump_decay": (20, 27), "down_thump_mix": 0.6,
        "up_base": (1900, 2450), "up_dur": 38,
        "up_mode_decays": [5, 3.5, 2.5, 1.8], "up_mode_amps": [0.18, 0.13, 0.09, 0.06],
        "up_noise_ms": 1.3, "up_noise_decay": 1.0, "up_noise_mix": 0.3,
        "up_thump": (170, 210), "up_thump_decay": (9, 14), "up_thump_mix": 0.3,
        "space_base": 1050, "space_thump": 100, "space_thump_decay": 36, "space_thump_mix": 0.8,
    },
    "clicky": {
        "desc": "Sharp, bright, snappy click (Cherry-MX-blue-ish)",
        "ratios": [1.0, 1.6, 2.3, 3.2],
        "down_base": (2800, 3600), "down_dur": 55,
        "down_mode_decays": [7, 5, 3, 2.2], "down_mode_amps": [0.30, 0.22, 0.16, 0.10],
        "down_noise_ms": 2.0, "down_noise_decay": 1.4, "down_noise_mix": 0.6,
        "down_thump": (170, 230), "down_thump_decay": (12, 18), "down_thump_mix": 0.25,
        "up_base": (3200, 4000), "up_dur": 35,
        "up_mode_decays": [4, 3, 2, 1.5], "up_mode_amps": [0.24, 0.17, 0.11, 0.07],
        "up_noise_ms": 1.2, "up_noise_decay": 1.0, "up_noise_mix": 0.45,
        "up_thump": (200, 260), "up_thump_decay": (6, 10), "up_thump_mix": 0.15,
        "space_base": 2000, "space_thump": 150, "space_thump_decay": 20, "space_thump_mix": 0.4,
    },
    "creamy": {
        "desc": "Smooth, buttery, muted -- lubed-switch character with almost no high-click",
        "ratios": [1.0, 1.5, 2.0, 2.7],
        "down_base": (1100, 1500), "down_dur": 80,
        "down_mode_decays": [14, 10, 7, 5], "down_mode_amps": [0.16, 0.11, 0.07, 0.045],
        "down_noise_ms": 3.0, "down_noise_decay": 2.2, "down_noise_mix": 0.22,
        "down_thump": (110, 160), "down_thump_decay": (32, 42), "down_thump_mix": 0.6,
        "up_base": (1500, 1900), "up_dur": 45,
        "up_mode_decays": [7, 5, 3.5, 2.5], "up_mode_amps": [0.12, 0.08, 0.05, 0.03],
        "up_noise_ms": 1.6, "up_noise_decay": 1.4, "up_noise_mix": 0.18,
        "up_thump": (130, 180), "up_thump_decay": (14, 20), "up_thump_mix": 0.3,
        "space_base": 900, "space_thump": 85, "space_thump_decay": 48, "space_thump_mix": 0.7,
    },
    "clacky": {
        "desc": "Hard, dry plastic clack -- brighter and tighter than Thocky, less bassy",
        "ratios": [1.0, 1.6, 2.2, 3.0],
        "down_base": (2100, 2700), "down_dur": 58,
        "down_mode_decays": [8, 6, 4, 2.8], "down_mode_amps": [0.27, 0.20, 0.14, 0.09],
        "down_noise_ms": 2.2, "down_noise_decay": 1.5, "down_noise_mix": 0.5,
        "down_thump": (160, 210), "down_thump_decay": (12, 17), "down_thump_mix": 0.32,
        "up_base": (2500, 3100), "up_dur": 36,
        "up_mode_decays": [5, 3.5, 2.5, 1.8], "up_mode_amps": [0.20, 0.14, 0.09, 0.06],
        "up_noise_ms": 1.3, "up_noise_decay": 1.0, "up_noise_mix": 0.4,
        "up_thump": (190, 240), "up_thump_decay": (7, 11), "up_thump_mix": 0.18,
        "space_base": 1650, "space_thump": 125, "space_thump_decay": 18, "space_thump_mix": 0.4,
    },
    "poppy": {
        "desc": "Bouncy, quick 'pop' -- short and tight with barely any ring, mid-range emphasis",
        "ratios": [1.0, 1.45, 1.9, 2.5],
        "down_base": (1900, 2400), "down_dur": 42,
        "down_mode_decays": [5, 3.5, 2.5, 1.8], "down_mode_amps": [0.24, 0.17, 0.11, 0.07],
        "down_noise_ms": 1.8, "down_noise_decay": 1.1, "down_noise_mix": 0.42,
        "down_thump": (200, 260), "down_thump_decay": (7, 10), "down_thump_mix": 0.28,
        "up_base": (2200, 2700), "up_dur": 26,
        "up_mode_decays": [3, 2.2, 1.6, 1.2], "up_mode_amps": [0.18, 0.12, 0.08, 0.05],
        "up_noise_ms": 1.0, "up_noise_decay": 0.8, "up_noise_mix": 0.35,
        "up_thump": (230, 280), "up_thump_decay": (4, 7), "up_thump_mix": 0.15,
        "space_base": 1500, "space_thump": 160, "space_thump_decay": 11, "space_thump_mix": 0.35,
    },
    "vintage": {
        "desc": "Vintage metallic clack (buckling-spring-ish)",
        "ratios": [1.0, 1.7, 2.4, 4.4],
        "down_base": (2600, 3400), "down_dur": 90,
        "down_mode_decays": [9, 7, 11, 14], "down_mode_amps": [0.26, 0.18, 0.13, 0.10],
        "down_noise_ms": 2.2, "down_noise_decay": 1.6, "down_noise_mix": 0.5,
        "down_thump": (150, 210), "down_thump_decay": (18, 26), "down_thump_mix": 0.4,
        "up_base": (2900, 3700), "up_dur": 40,
        "up_mode_decays": [5, 4, 6, 7], "up_mode_amps": [0.2, 0.14, 0.10, 0.08],
        "up_noise_ms": 1.4, "up_noise_decay": 1.2, "up_noise_mix": 0.4,
        "up_thump": (180, 240), "up_thump_decay": (9, 14), "up_thump_mix": 0.2,
        "space_base": 1900, "space_thump": 130, "space_thump_decay": 24, "space_thump_mix": 0.45,
    },
}


def generate_profile(name, cfg, out_dir, seed_base):
    rng = random.Random(seed_base)

    for i in range(1, 7):
        samples = make_modal_click(
            duration_ms=cfg["down_dur"],
            base_freq=rng.uniform(*cfg["down_base"]),
            mode_ratios=jitter(cfg["ratios"], 0.06, rng),
            mode_decays_ms=jitter(cfg["down_mode_decays"], 0.15, rng),
            mode_amps=cfg["down_mode_amps"],
            noise_burst_ms=cfg["down_noise_ms"],
            noise_decay_ms=cfg["down_noise_decay"],
            noise_mix=cfg["down_noise_mix"],
            thump_freq=rng.uniform(*cfg["down_thump"]),
            thump_decay_ms=rng.uniform(*cfg["down_thump_decay"]),
            thump_mix=cfg["down_thump_mix"],
            seed=seed_base + i,
        )
        write_wav(os.path.join(out_dir, name, f"click_down_{i}.wav"), samples)

    for i in range(1, 4):
        samples = make_modal_click(
            duration_ms=cfg["up_dur"],
            base_freq=rng.uniform(*cfg["up_base"]),
            mode_ratios=jitter(cfg["ratios"], 0.06, rng),
            mode_decays_ms=jitter(cfg["up_mode_decays"], 0.2, rng),
            mode_amps=cfg["up_mode_amps"],
            noise_burst_ms=cfg["up_noise_ms"],
            noise_decay_ms=cfg["up_noise_decay"],
            noise_mix=cfg["up_noise_mix"],
            thump_freq=rng.uniform(*cfg["up_thump"]),
            thump_decay_ms=rng.uniform(*cfg["up_thump_decay"]),
            thump_mix=cfg["up_thump_mix"],
            seed=seed_base + 100 + i,
        )
        write_wav(os.path.join(out_dir, name, f"click_up_{i}.wav"), samples)

    space_down = make_modal_click(
        duration_ms=cfg["down_dur"] + 35, base_freq=cfg["space_base"],
        mode_ratios=cfg["ratios"], mode_decays_ms=[d * 1.3 for d in cfg["down_mode_decays"]],
        mode_amps=cfg["down_mode_amps"],
        noise_burst_ms=cfg["down_noise_ms"] + 0.5, noise_decay_ms=cfg["down_noise_decay"] + 0.4,
        noise_mix=cfg["down_noise_mix"],
        thump_freq=cfg["space_thump"], thump_decay_ms=cfg["space_thump_decay"],
        thump_mix=cfg["space_thump_mix"], seed=seed_base + 999,
    )
    write_wav(os.path.join(out_dir, name, "click_space_down.wav"), space_down)

    space_up = make_modal_click(
        duration_ms=cfg["up_dur"] + 15, base_freq=cfg["space_base"] * 1.3,
        mode_ratios=cfg["ratios"], mode_decays_ms=[d * 1.2 for d in cfg["up_mode_decays"]],
        mode_amps=cfg["up_mode_amps"],
        noise_burst_ms=cfg["up_noise_ms"], noise_decay_ms=cfg["up_noise_decay"],
        noise_mix=cfg["up_noise_mix"],
        thump_freq=cfg["space_thump"] * 1.3, thump_decay_ms=cfg["space_thump_decay"] * 0.5,
        thump_mix=cfg["space_thump_mix"] * 0.6, seed=seed_base + 998,
    )
    write_wav(os.path.join(out_dir, name, "click_space_up.wav"), space_up)


def main():
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "profiles")
    for i, (name, cfg) in enumerate(PROFILES.items()):
        generate_profile(name, cfg, out_dir, seed_base=100 * (i + 1))
        print(f"Generated profile '{name}': {cfg['desc']}")
    generate_airy_profile(out_dir, seed_base=900)
    print("All profiles generated in", out_dir)


if __name__ == "__main__":
    main()
