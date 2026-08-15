import AVFoundation
import AudioToolbox

/// Plays overlapping click samples with low latency using a small round-robin
/// pool of player nodes on one AVAudioEngine graph — this lets rapid typing
/// trigger overlapping sounds instead of cutting each other off.
final class ClickAudioEngine {
    /// Procedural profiles are intentionally not exposed as selectable Sound
    /// Packs right now -- only real recorded audio is, per explicit request.
    /// The generation code/resources still exist (Resources/generate_sounds.py,
    /// SoundSynth.swift) so this can be turned back on by repopulating these.
    static let signatureProfileNames: [String] = []
    static let extraProfileNames: [String] = []
    static let builtInProfileNames: [String] = []

    static let profileLabels: [String: String] = [
        "creamy": "Creamy",
        "deep_thock": "Thocky",
        "clacky": "Clacky",
        "poppy": "Poppy",
        "clicky": "Clicky",
        "the_bench": "The Bench (Flagship)",
        "vintage": "Vintage",
        "airy": "Airy (Soft/Reverb)",
        "my_sound": "My Sound",
        "my_keyboard": "My Keyboard",
    ]
    static let profileDescriptions: [String: String] = [
        "creamy": "Smooth, buttery, muted — lubed-switch character",
        "deep_thock": "Round, bassy, satisfying — the classic deep thock",
        "clacky": "Hard, dry plastic clack — brighter and tighter than Thocky",
        "poppy": "Bouncy, quick pop — short and tight, barely any ring",
        "clicky": "Sharp, bright, snappy — Cherry MX Blue-ish",
        "the_bench": "Deep and rounded with crisp definition — tuned for the classic 'most satisfying' feel",
        "vintage": "Metallic clack — buckling-spring character",
        "airy": "Soft tonal chime with a reverb tail — premium UI style",
        "my_sound": "Your custom-mixed sound",
        "my_keyboard": "Your own recorded keyboard",
    ]

    /// Any subfolder here containing click_down_1.wav is treated as a
    /// selectable custom profile — lets the mixer-saved sound and a
    /// recorded-audio profile coexist without hardcoding a single slot.
    private static var customProfilesRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Klack/CustomProfiles")
    }

    private static func customProfileDirectory(named name: String) -> URL {
        customProfilesRoot.appendingPathComponent(name)
    }

    static func label(for profileName: String) -> String {
        if let known = profileLabels[profileName] { return known }
        // Imported recordings are prefixed "real_" to distinguish them on
        // disk; that's an implementation detail, not something to show.
        let stripped = profileName.hasPrefix("real_")
            ? String(profileName.dropFirst("real_".count))
            : profileName
        return stripped
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private let engine = AVAudioEngine()
    private var pool: [AVAudioPlayerNode] = []
    private var poolIndex = 0
    // Every keystroke consumes two slots (down + up), so this is really
    // ~12 keystrokes of polyphony — enough that a fast burst doesn't wrap
    // the ring and truncate a still-ringing 90ms tail.
    private let poolSize = 24
    private let profilesRoot: URL
    private var format: AVAudioFormat?

    private(set) var currentProfile: String = "real_clicky"

    var availableProfiles: [String] {
        var names = Self.builtInProfileNames
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(atPath: Self.customProfilesRoot.path) {
            for entry in entries.sorted() {
                let dir = Self.customProfileDirectory(named: entry)
                if fm.fileExists(atPath: dir.appendingPathComponent("click_down_1.wav").path) {
                    names.append(entry)
                }
            }
        }
        return names
    }

    private func directory(forProfile name: String) -> URL {
        Self.builtInProfileNames.contains(name) ? profilesRoot.appendingPathComponent(name) : Self.customProfileDirectory(named: name)
    }

    private var downBuffers: [AVAudioPCMBuffer] = []
    private var upBuffers: [AVAudioPCMBuffer] = []
    private var spaceDownBuffer: AVAudioPCMBuffer?
    private var spaceUpBuffer: AVAudioPCMBuffer?

    var volume: Float = 0.8 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    init?(resourceDirectory: URL) {
        profilesRoot = resourceDirectory.appendingPathComponent("profiles")

        var startupFormat: AVAudioFormat?
        if let fmt = try? loadBuffers(directory: directory(forProfile: currentProfile)) {
            startupFormat = fmt
        } else {
            // Default profile missing (e.g. fresh install with no recordings
            // imported yet) -- fall back to whatever's actually available.
            let fm = FileManager.default
            let fallbackCandidates = (try? fm.contentsOfDirectory(atPath: Self.customProfilesRoot.path))?.sorted() ?? []
            for candidate in fallbackCandidates {
                if let fmt = try? loadBuffers(directory: Self.customProfileDirectory(named: candidate)) {
                    currentProfile = candidate
                    startupFormat = fmt
                    break
                }
            }
        }

        guard let fmt = startupFormat else {
            NSLog("Klack: no usable Sound Pack found at startup (profiles root: \(profilesRoot.path), custom root: \(Self.customProfilesRoot.path))")
            return nil
        }
        format = fmt

        for _ in 0..<poolSize {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: fmt)
            pool.append(node)
        }

        // Fast typing means many clicks overlap and sum together, which can
        // clip/distort into a harsh mess. A limiter after the mixer catches
        // that instead of letting it clip -- this is the real fix for
        // "sounds bad when typing fast," not throttling which clicks play.
        let limiterDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0
        )
        let limiter = AVAudioUnitEffect(audioComponentDescription: limiterDescription)
        engine.attach(limiter)
        engine.connect(engine.mainMixerNode, to: limiter, format: fmt)
        engine.connect(limiter, to: engine.outputNode, format: fmt)

        engine.mainMixerNode.outputVolume = volume

        do {
            try engine.start()
        } catch {
            NSLog("Klack: failed to start audio engine: \(error)")
            return nil
        }
    }

    @discardableResult
    func switchProfile(to name: String) -> Bool {
        guard name != currentProfile else { return true }
        let previous = currentProfile
        currentProfile = name
        do {
            let newFormat = try loadBuffers(directory: directory(forProfile: name))
            reconnectPoolIfNeeded(for: newFormat)
            return true
        } catch {
            NSLog("Klack: failed to switch to profile \(name): \(error), reverting to \(previous)")
            currentProfile = previous
            do {
                let revertedFormat = try loadBuffers(directory: directory(forProfile: previous))
                reconnectPoolIfNeeded(for: revertedFormat)
            } catch {
                NSLog("Klack: CRITICAL — revert to \(previous) also failed: \(error). Audio may be silent until another pack is selected.")
            }
            return false
        }
    }

    /// Player nodes are connected with a specific format at init. A profile
    /// imported at a different sample rate or channel count would otherwise
    /// throw an uncatchable NSException when its buffer is scheduled, so the
    /// graph has to be rewired whenever the format actually changes.
    private func reconnectPoolIfNeeded(for newFormat: AVAudioFormat) {
        guard let current = format, !current.isEqual(newFormat) else { return }
        NSLog("Klack: audio format changed (\(current) -> \(newFormat)), reconnecting pool")
        for node in pool {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: newFormat)
        }
        format = newFormat
    }

    @discardableResult
    private func loadBuffers(directory dir: URL) throws -> AVAudioFormat {
        var loadedFormat: AVAudioFormat?

        func load(_ name: String) -> AVAudioPCMBuffer? {
            let url = dir.appendingPathComponent(name)
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            if loadedFormat == nil { loadedFormat = file.processingFormat }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            // A failed read leaves a valid-but-empty buffer, which would load
            // "successfully" and then play silence — reject it explicitly.
            guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else {
                NSLog("Klack: unreadable or empty sample at \(url.lastPathComponent)")
                return nil
            }
            return buffer
        }

        var newDown: [AVAudioPCMBuffer] = []
        var newUp: [AVAudioPCMBuffer] = []
        for i in 1...6 {
            if let b = load("click_down_\(i).wav") { newDown.append(b) }
        }
        for i in 1...3 {
            if let b = load("click_up_\(i).wav") { newUp.append(b) }
        }
        let newSpaceDown = load("click_space_down.wav")
        let newSpaceUp = load("click_space_up.wav")

        guard let fmt = loadedFormat, !newDown.isEmpty else {
            throw NSError(domain: "Klack", code: 1, userInfo: [NSLocalizedDescriptionKey: "No click sounds found in \(dir.path)"])
        }

        downBuffers = newDown
        upBuffers = newUp
        spaceDownBuffer = newSpaceDown
        spaceUpBuffer = newSpaceUp
        return fmt
    }

    /// Prefer an idle node so a still-ringing tail is never hard-truncated;
    /// only fall back to round-robin (and an audible cut) when every node is
    /// genuinely busy.
    private func nextNode() -> AVAudioPlayerNode {
        for offset in 0..<pool.count {
            let candidate = pool[(poolIndex + offset) % pool.count]
            if !candidate.isPlaying {
                poolIndex = (poolIndex + offset + 1) % pool.count
                return candidate
            }
        }
        let node = pool[poolIndex]
        poolIndex = (poolIndex + 1) % pool.count
        return node
    }

    private func play(_ buffer: AVAudioPCMBuffer, gain: Float = 1.0) {
        let node = nextNode()
        node.volume = max(0.0, min(2.0, gain))
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        node.play()
    }

    /// `gainMultiplier` is the fast-typing reward boost (1.0 = normal,
    /// >1.0 = typing fast enough to earn a little extra volume).
    func playKeyDown(isSpace: Bool, gainMultiplier: Float = 1.0) {
        if isSpace, let b = spaceDownBuffer {
            play(b, gain: gainMultiplier)
        } else if let b = downBuffers.randomElement() {
            play(b, gain: gainMultiplier)
        }
    }

    func playKeyUp(isSpace: Bool) {
        if isSpace, let b = spaceUpBuffer {
            play(b)
        } else if let b = upBuffers.randomElement() {
            play(b)
        }
    }

    // MARK: Live mixer support

    /// Renders raw samples straight into the player pool for instant preview
    /// while dragging a mixer slider — no disk round-trip.
    func previewSamples(_ samples: [Float]) {
        guard let fmt = format,
              let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { ptr in
                channelData[0].update(from: ptr.baseAddress!, count: samples.count)
            }
        }
        play(buffer)
    }

    /// Renders a full set of variants from the given mixer params and writes
    /// them to disk as a named custom profile, then switches to it.
    @discardableResult
    func saveCustomProfile(params: SynthParams, name: String = "my_sound") -> Bool {
        guard let fmt = format else { return false }
        let dir = Self.customProfileDirectory(named: name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            func write(_ samples: [Float], to name: String) throws {
                let url = dir.appendingPathComponent(name)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                if let channelData = buffer.floatChannelData {
                    samples.withUnsafeBufferPointer { ptr in
                        channelData[0].update(from: ptr.baseAddress!, count: samples.count)
                    }
                }
                let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
                try file.write(from: buffer)
            }

            for i in 1...6 {
                var jittered = params
                jittered.pitch *= Float.random(in: 0.94...1.06)
                let samples = SoundSynth.render(params: jittered, durationMs: 70, seed: i)
                try write(samples, to: "click_down_\(i).wav")
            }
            for i in 1...3 {
                var jittered = params
                jittered.pitch *= Float.random(in: 1.1...1.3)
                jittered.body *= 0.5
                let samples = SoundSynth.render(params: jittered, durationMs: 40, seed: 100 + i)
                try write(samples, to: "click_up_\(i).wav")
            }
            var spaceDown = params
            spaceDown.pitch *= 0.7
            spaceDown.body = min(1.0, spaceDown.body * 1.3)
            try write(SoundSynth.render(params: spaceDown, durationMs: 95, seed: 999), to: "click_space_down.wav")

            var spaceUp = params
            spaceUp.pitch *= 0.9
            spaceUp.body *= 0.5
            try write(SoundSynth.render(params: spaceUp, durationMs: 50, seed: 998), to: "click_space_up.wav")

            return switchProfile(to: name)
        } catch {
            NSLog("Klack: failed to save custom profile: \(error)")
            return false
        }
    }
}
