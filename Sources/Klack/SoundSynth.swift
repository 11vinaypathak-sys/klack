import Foundation

/// Pure-Swift port of the modal-synthesis click generator (see
/// Resources/generate_sounds.py for the original design notes) — this lets
/// the live mixer sliders render a new click sound instantly in memory,
/// with no Python round-trip and no app rebuild needed.
struct SynthParams {
    var pitch: Float = 1650       // base frequency in Hz
    var body: Float = 0.55        // thump/body mix, 0-1
    var brightness: Float = 0.7   // upper-mode click presence, 0-1
    var snappiness: Float = 0.5   // 0 = long/loose decay, 1 = short/tight decay
    var attack: Float = 0.45      // noise-transient mix, 0-1 (mechanical bite)
    var reverb: Float = 0.0       // reverb wash amount, 0-1
}

enum SoundSynth {
    static let sampleRate: Double = 44100
    // Two modes near the same ratio (1.0 / 1.03) create natural beating —
    // real struck materials never ring at one perfectly pure frequency.
    private static let modeRatios: [Float] = [1.0, 1.03, 1.55, 2.1, 2.42, 2.85]
    private static let baseModeDecaysMs: [Float] = [11, 10, 7, 5, 4.5, 3.5]
    private static let baseModeAmps: [Float] = [0.22, 0.16, 0.17, 0.12, 0.09, 0.08]

    static func render(params: SynthParams, durationMs: Float, seed: Int) -> [Float] {
        var rng = SeededGenerator(seed: seed)
        // A zero/negative/NaN duration would make an empty buffer, which
        // scheduleBuffer rejects at runtime -- always render something.
        let safeDurationMs = durationMs.isFinite ? max(1, durationMs) : 1
        let n = Int(sampleRate * Double(safeDurationMs) / 1000)
        var out = [Float](repeating: 0, count: n)

        // Callers jitter these (and sliders can be driven to their ends), so
        // clamp into the ranges the maths below is actually valid over rather
        // than trusting the incoming values.
        let pitch = params.pitch.isFinite ? min(20000, max(20, params.pitch)) : 1650
        let body = params.body.isFinite ? min(1, max(0, params.body)) : 0
        let brightness = params.brightness.isFinite ? min(1, max(0, params.brightness)) : 0
        let snappiness = params.snappiness.isFinite ? min(1, max(0, params.snappiness)) : 0
        let attack = params.attack.isFinite ? min(1, max(0, params.attack)) : 0
        let reverb = params.reverb.isFinite ? min(1, max(0, params.reverb)) : 0

        // Decay multiplier: snappiness 0 -> 1.8x longer, 1 -> 0.5x shorter.
        // Clamped snappiness keeps this >= 0.5, so the -t/decay divisions below
        // can never hit zero (which would yield NaN at t = 0).
        let decayScale = 1.8 - Float(1.3) * snappiness

        // 1. Impact transient -- two overlapping noise bursts (a fast micro-
        //    burst plus a slightly coarser one) instead of one clean burst.
        //    A single uniform noise decay reads as a synthetic "pop"; layering
        //    two different grain/decay rates gives it a more textured, less
        //    obviously-generated knock.
        let noiseBurstMs: Float = 2.0 + 1.5 * attack
        let noiseDecayMs: Float = 1.2 + 0.8 * attack
        for i in 0..<n {
            let tMs = Float(i) * 1000 / Float(sampleRate)
            if tMs >= noiseBurstMs { break }
            let env = expf(-tMs / noiseDecayMs)
            let env2 = expf(-tMs / (noiseDecayMs * 2.4))
            let grain = rng.nextUniform(-1, 1)
            let coarse = rng.nextUniform(-1, 1)
            out[i] += (grain * env * 0.7 + coarse * env2 * 0.3) * (0.25 + 0.45 * attack)
        }

        // 1b. A second, quieter impulse a couple ms later -- real switches
        //     have a spring/keycap double-contact, not one instantaneous hit.
        let secondHitDelayMs: Float = 1.6 + rng.nextUniform(-0.3, 0.3)
        let secondHitSample = Int(secondHitDelayMs * Float(sampleRate) / 1000)
        for i in 0..<n {
            let j = i - secondHitSample
            guard j >= 0 else { continue }
            let tMs = Float(j) * 1000 / Float(sampleRate)
            if tMs >= noiseBurstMs * 0.8 { break }
            let env = expf(-tMs / (noiseDecayMs * 0.8))
            out[i] += rng.nextUniform(-1, 1) * env * (0.10 + 0.15 * attack)
        }

        // 2. Resonant modes -- decaying sinusoids at inharmonic ratios, each
        //    with a touch of random detune and a little band-limited noise
        //    riding along (real resonances aren't infinitely pure tones).
        for (ratio, (decayMs, amp)) in zip(modeRatios, zip(baseModeDecaysMs, baseModeAmps)) {
            let detune = rng.nextUniform(0.985, 1.015)
            let freq = pitch * ratio * detune
            let phase = rng.nextUniform(0, 2 * .pi)
            let decay = decayMs * decayScale
            var prevNoise: Float = 0
            for i in 0..<n {
                let tMs = Float(i) * 1000 / Float(sampleRate)
                let env = expf(-tMs / decay)
                let tone = sinf(2 * .pi * freq * Float(i) / Float(sampleRate) + phase)
                // Light one-pole smoothed noise riding on the tone, not raw
                // noise -- adds grit without turning the mode into static.
                let rawNoise = rng.nextUniform(-1, 1)
                prevNoise = prevNoise * 0.85 + rawNoise * 0.15
                let textured = tone * 0.88 + prevNoise * 0.12
                out[i] += textured * env * amp * brightness
            }
        }

        // 3. Low body/thump resonance.
        let thumpFreq = 90 + 0.06 * pitch // slightly track pitch so it stays coherent
        let thumpDecay: Float = (20 + 10 * brightness) * decayScale
        let thumpPhase = rng.nextUniform(0, 2 * .pi)
        for i in 0..<n {
            let tMs = Float(i) * 1000 / Float(sampleRate)
            let env = expf(-tMs / thumpDecay)
            out[i] += sinf(2 * .pi * thumpFreq * Float(i) / Float(sampleRate) + thumpPhase) * env * body
        }

        // Near-instant attack ramp to avoid a digital pop at sample 0.
        let attackSamples = max(1, Int(sampleRate * 0.0003))
        for i in 0..<min(attackSamples, n) {
            out[i] *= Float(i) / Float(attackSamples)
        }

        if reverb > 0.001 {
            let wet = applyReverb(out, roomDecay: 0.5 + 0.15 * reverb)
            for i in 0..<out.count {
                out[i] = out[i] * (1 - reverb * 0.5) + wet[i] * (reverb * 0.5)
            }
        }

        // Gentle soft-clip saturation -- adds a bit of the odd-harmonic
        // "grit" real audio picks up going through actual mechanics/air,
        // instead of the perfectly clean sum of ideal sine waves.
        // Also the last line of defence against a non-finite sample: one NaN
        // reaching the render thread poisons the mix and can silence the graph.
        for i in 0..<out.count {
            out[i] = out[i].isFinite ? softClip(out[i] * 1.4) : 0
        }

        normalize(&out, target: 0.85)
        return out
    }

    private static func softClip(_ x: Float) -> Float {
        tanhf(x)
    }

    private static func normalize(_ signal: inout [Float], target: Float) {
        let peak = signal.map { abs($0) }.max() ?? 1
        // `peak > x` is false for NaN, so this also covers a poisoned buffer.
        guard peak.isFinite, peak > 0.0001 else { return }
        let scale = target / peak
        for i in 0..<signal.count { signal[i] *= scale }
    }

    // MARK: Small Schroeder-style reverb (comb filters + allpass diffusion)

    private static func comb(_ signal: [Float], delayMs: Float, gain: Float) -> [Float] {
        let d = max(1, Int(sampleRate * Double(delayMs) / 1000))
        var out = [Float](repeating: 0, count: signal.count)
        for i in 0..<signal.count {
            let delayed = i - d >= 0 ? out[i - d] : 0
            out[i] = signal[i] + delayed * gain
        }
        return out
    }

    private static func allpass(_ signal: [Float], delayMs: Float, g: Float = 0.5) -> [Float] {
        let d = max(1, Int(sampleRate * Double(delayMs) / 1000))
        var y = [Float](repeating: 0, count: signal.count)
        for i in 0..<signal.count {
            let xDelayed = i - d >= 0 ? signal[i - d] : 0
            let yDelayed = i - d >= 0 ? y[i - d] : 0
            y[i] = -g * signal[i] + xDelayed + g * yDelayed
        }
        return y
    }

    private static func applyReverb(_ dry: [Float], roomDecay: Float) -> [Float] {
        let combDelays: [Float] = [29.7, 37.1, 41.3, 43.7]
        var wet = [Float](repeating: 0, count: dry.count)
        for delayMs in combDelays {
            let c = comb(dry, delayMs: delayMs, gain: roomDecay)
            for i in 0..<wet.count { wet[i] += c[i] / Float(combDelays.count) }
        }
        wet = allpass(wet, delayMs: 5.0)
        wet = allpass(wet, delayMs: 1.7)
        return wet
    }
}

/// Simple deterministic PRNG so preview/save renders are reproducible per seed.
struct SeededGenerator {
    private var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15 }

    private mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextUniform(_ lower: Float, _ upper: Float) -> Float {
        let fraction = Float(next() % 1_000_000) / 1_000_000
        return lower + fraction * (upper - lower)
    }
}
