import AVFoundation
import AudioToolbox
import KlackObjC

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

    // Voice ducking. Without this, every still-ringing tail keeps summing at
    // full level, so a fast burst becomes a wall of overlapping decays rather
    // than distinct clicks. A real keyboard behaves the opposite way: the
    // newest strike dominates and the previous ones recede. So each new
    // keydown fades whatever is still ringing.
    /// A tail being faded out, with the shape of its fade.
    private struct DuckingVoice {
        let node: AVAudioPlayerNode
        /// Where the fade started, so the curve is applied to the note's own
        /// level rather than compounding a per-tick multiplier.
        let startVolume: Float
        var elapsed: Double
        /// Seconds from full to silence. Tracks typing speed -- see `release(forFlow:)`.
        let release: Double
    }

    private var duckingVoices: [DuckingVoice] = []
    private var duckTimer: Timer?
    private var lastDuckTick: CFAbsoluteTime = 0
    /// Release bounds, seconds. Isolated keystrokes get the long one so the
    /// note rings; a fast burst gets the short one so each click has cleared
    /// before the next lands.
    private let duckReleaseSlow: Double = 0.13
    private let duckReleaseFast: Double = 0.045
    /// Below this the tail is inaudible, so it's silenced outright and the
    /// buffer left to run itself out.
    private let duckFloor: Float = 0.05
    // Held so the graph can be rewired after an output-device change.
    private var limiterNode: AVAudioUnitEffect?
    private var lastRestartAttempt: CFAbsoluteTime = 0
    private var restartFailureLogged = false
    private var configChangeObserver: NSObjectProtocol?
    /// Bounded so a permanently dead output device can't produce an endless
    /// retry loop. Reset whenever the engine is running again.
    private var configRetriesLeft = 6

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

    private var spectrumCache: [String: [Float]] = [:]
    private var downBuffers: [AVAudioPCMBuffer] = []
    private var upBuffers: [AVAudioPCMBuffer] = []
    private var spaceDownBuffer: AVAudioPCMBuffer?
    private var spaceUpBuffer: AVAudioPCMBuffer?

    /// A darker copy of the down samples, used once typing turns into a burst.
    private var softDownBuffers: [AVAudioPCMBuffer] = []
    private var softSpaceDownBuffer: AVAudioPCMBuffer?
    /// Extra shelf applied on top of `softness` for the burst set.
    private static let burstExtraSoftness: Float = 0.35

    /// Position and direction of the walk through the sample variants.
    private var melodyIndex = 0
    private var melodyStep = 1

    var volume: Float = 0.8 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    static let defaultSoftness: Float = 0.45
    private static let softnessKey = "klack.softness"

    /// UserDefaults bridges Float to NSNumber, so `as? Float` never matches a
    /// value written with `set(_ : Float, forKey:)`.
    private static func storedSoftness() -> Float {
        guard let number = UserDefaults.standard.object(forKey: softnessKey) as? NSNumber else {
            return defaultSoftness
        }
        return min(1, max(0, number.floatValue))
    }

    /// How much high-frequency energy to take out of each sample as it loads.
    /// 0 is the raw recording, 1 is fully dark. See `soften(_:amount:)`.
    private(set) var softness: Float = ClickAudioEngine.storedSoftness()

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
        limiterNode = limiter
        engine.attach(limiter)
        // The mixer side runs at the sample's format, but the output node only
        // accepts the *hardware* format — typically 48kHz stereo, while our
        // packs are 44.1kHz mono. Handing it the file format is what produced
        // kAudioUnitErr_FormatNotSupported (-10868) and left the engine unable
        // to start. The mixer does the rate/channel conversion for us.
        // The whole post-mixer chain must run at the *hardware* format. Our
        // packs are 44.1kHz mono; the output chain is typically 48kHz stereo,
        // and Apple's DynamicsProcessor won't initialize on a mono bus at all.
        // Passing the file format here is what produced
        // kAudioUnitErr_FormatNotSupported (-10868). The mixer converts for us,
        // so only the player->mixer side uses the sample's format.
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let chainFormat = hardwareFormat.sampleRate > 0 ? hardwareFormat : fmt
        engine.connect(engine.mainMixerNode, to: limiter, format: chainFormat)
        engine.connect(limiter, to: engine.outputNode, format: chainFormat)

        engine.mainMixerNode.outputVolume = volume

        do {
            try engine.start()
        } catch {
            NSLog("Klack: failed to start audio engine: \(error)")
            return nil
        }

        // Switching output device (headphones in/out, sleep-wake, a display
        // with speakers connecting) tears down the engine's connections and
        // stops it. Without handling this the app goes permanently silent
        // until relaunch.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            // A genuine new device event deserves a fresh retry budget --
            // otherwise a bad swap earlier in the session leaves later,
            // recoverable ones with nothing left to retry with.
            self?.configRetriesLeft = 6
            self?.handleConfigurationChange()
        }
    }

    deinit {
        // The timer retains its closure until invalidated; leaving it running
        // keeps firing against a deallocating engine.
        duckTimer?.invalidate()
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// The output format can change with the device (e.g. 44.1k -> 48k), so
    /// rewire the whole graph to the new hardware format before restarting.
    private func handleConfigurationChange() {
        cancelDucking()
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        // A zero-rate or zero-channel format means the device isn't ready
        // yet -- mid-swap the old device is gone and the new one hasn't
        // settled. Connecting against that is exactly what raises.
        guard outputFormat.sampleRate > 0, outputFormat.channelCount > 0,
              let bufferFormat = format, let limiter = limiterNode else {
            NSLog("Klack: configuration change with no usable output format yet")
            // The device may settle a moment later without posting another
            // notification, so re-check rather than staying disconnected.
            scheduleConfigurationRetry()
            return
        }

        // Reconnecting the mixer/limiter is what actually re-establishes the
        // broken links to the new device. Both post-mixer links use the
        // hardware format — the limiter can't run on our mono sample format.
        //
        // Wrapped because AVAudioEngine *raises* on invalid state here rather
        // than returning an error, and an uncaught raise takes the whole app
        // down -- which is the real cause of Klack silently disappearing after
        // headphones/Bluetooth/sleep. A failed rewire must degrade to "no
        // sound for a moment", never to "app is gone".
        var thrown: NSError?
        let ok = KlackRunCatchingExceptions({
            self.engine.connect(self.engine.mainMixerNode, to: limiter, format: outputFormat)
            self.engine.connect(limiter, to: self.engine.outputNode, format: outputFormat)
            for node in self.pool {
                self.engine.connect(node, to: self.engine.mainMixerNode, format: bufferFormat)
            }
        }, &thrown)

        guard ok else {
            NSLog("Klack: audio graph rewire failed (\(thrown?.localizedDescription ?? "unknown")) — retrying")
            scheduleConfigurationRetry()
            return
        }

        engine.mainMixerNode.outputVolume = volume
        restartIfNeeded()
    }

    /// Device transitions can leave the hardware unusable for a beat, and
    /// macOS doesn't always post a second notification once it settles. Without
    /// a retry the app stays silent until it's relaunched.
    private func scheduleConfigurationRetry() {
        guard configRetriesLeft > 0 else {
            NSLog("Klack: giving up on audio rewire after repeated failures")
            return
        }
        configRetriesLeft -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.handleConfigurationChange()
        }
    }

    /// Engine can also be stopped by the system (sleep/wake, device loss), so
    /// every play path checks this rather than scheduling into a dead graph.
    @discardableResult
    /// Restart is attempted at most once a second. Without the throttle a
    /// persistently unstartable engine retries on every single keystroke,
    /// which spins the CPU and floods the log with the same error. Not
    /// private: also called directly on wake-from-sleep, since waiting for
    /// the next keystroke to trigger it means the very first keystroke
    /// after waking is silently dropped.
    func restartIfNeeded() -> Bool {
        guard !engine.isRunning else {
            restartFailureLogged = false
            configRetriesLeft = 6
            return true
        }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRestartAttempt > 1.0 else { return false }
        lastRestartAttempt = now

        // start() throws a Swift error for some failures but *raises* for
        // others (a half-attached device mid-swap), so both have to be handled
        // or the raise kills the app.
        var startError: Error?
        var thrown: NSError?
        let noRaise = KlackRunCatchingExceptions({
            do { try self.engine.start() } catch { startError = error }
        }, &thrown)

        if noRaise && startError == nil {
            NSLog("Klack: audio engine restarted")
            restartFailureLogged = false
            configRetriesLeft = 6
            return true
        }

        // Log the reason once per outage rather than once per attempt.
        if !restartFailureLogged {
            restartFailureLogged = true
            let reason = startError.map { "\($0)" } ?? thrown?.localizedDescription ?? "unknown"
            NSLog("Klack: failed to start audio engine: \(reason)")
        }
        return false
    }

    @discardableResult
    func switchProfile(to name: String) -> Bool {
        guard name != currentProfile else { return true }
        // Tails from the outgoing pack shouldn't keep fading over the new
        // one, and the pool may be reconnected to a different format below.
        cancelDucking()
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
            Self.soften(buffer, amount: softness)
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

        // Built once here rather than filtered per keystroke -- softening runs
        // a two-pole filter over every sample, which has no business happening
        // on a keypress.
        let darkened = newDown.compactMap { Self.darkerCopy(of: $0, extra: Self.burstExtraSoftness) }
        // A partial set would desynchronise the melodic walk from the normal
        // set, so it's all or nothing.
        softDownBuffers = darkened.count == newDown.count ? darkened : []
        softSpaceDownBuffer = newSpaceDown.flatMap { Self.darkerCopy(of: $0, extra: Self.burstExtraSoftness) }
        return fmt
    }

    private static func darkerCopy(of buffer: AVAudioPCMBuffer, extra: Float) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity),
              let source = buffer.floatChannelData,
              let destination = copy.floatChannelData else { return nil }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel], count: frames)
        }
        soften(copy, amount: extra)
        return copy
    }

    /// Reloads the current pack through the new filter setting.
    ///
    /// Re-reading 11 short files is cheap enough to do on a slider drag, and it
    /// keeps the tone shaping in one place. The alternative -- an EQ node in the
    /// live graph -- means another node to rewire on every output-device change,
    /// and that path is exactly where this app used to die.
    func setSoftness(_ value: Float) {
        let clamped = value.isFinite ? min(1, max(0, value)) : Self.defaultSoftness
        guard abs(clamped - softness) > 0.001 else { return }
        softness = clamped
        UserDefaults.standard.set(clamped, forKey: Self.softnessKey)
        // The panel's spectrum display is drawn from the buffers, so a stale
        // cache would keep showing the old, brighter curve.
        spectrumCache.removeAll()
        _ = try? loadBuffers(directory: directory(forProfile: currentProfile))
    }

    /// High-shelf cut, applied in place.
    ///
    /// The shipped packs are real recordings, and on laptop speakers their
    /// energy lands in the 3-6kHz band the ear is most sensitive to -- which
    /// reads as thin and stabby rather than as a keyboard. Two cascaded
    /// one-poles give the low band; subtracting it leaves the high band, and
    /// only that gets attenuated. So this is a shelf, not a brick wall: the
    /// click keeps its edge and just stops cutting.
    ///
    /// Deliberately no make-up gain. A shelf leaves everything below the corner
    /// untouched, so the body of the click keeps its level on its own. Peak
    /// normalising here actively defeats the filter -- on a click the peak *is*
    /// the harsh transient, so restoring it puts back exactly the energy this
    /// is meant to remove. (Measured: it reduced the 3-6kHz cut to -0.1dB.)
    /// A bright pack getting quieter as it softens is correct; that's what the
    /// Volume slider is for.
    private static func soften(_ buffer: AVAudioPCMBuffer, amount: Float) {
        guard amount > 0.001, let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let sampleRate = Float(buffer.format.sampleRate)
        guard frames > 0, sampleRate > 0 else { return }

        // 2kHz corner, two poles: by 5kHz the low band has rolled off far
        // enough that the shelf bites, while the sub-1kHz body is untouched.
        let coeff = 1 - expf(-2 * .pi * 2000 / sampleRate)
        let keepHighs = 1 - amount

        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = data[channel]
            var lowStage1: Float = 0
            var lowStage2: Float = 0
            for i in 0..<frames {
                let x = samples[i]
                lowStage1 += coeff * (x - lowStage1)
                lowStage2 += coeff * (lowStage1 - lowStage2)
                samples[i] = lowStage2 + (x - lowStage2) * keepHighs
            }
        }
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

    private func play(_ buffer: AVAudioPCMBuffer, gain: Float = 1.0, ducksOthers: Bool = false,
                      release fadeTime: Double? = nil) {
        // Scheduling into a stopped engine is silently dropped, so recover
        // first -- this covers the sleep/wake and device-loss cases.
        guard buffer.frameLength > 0, restartIfNeeded() else { return }
        let node = nextNode()
        if ducksOthers {
            duckVoices(except: node, release: fadeTime ?? duckReleaseSlow)
        }
        // This node may still be mid-fade from an earlier keystroke: player
        // nodes stay "playing" until stopped, so the pool wraps and voices get
        // recycled while ducking. Left in the list, the fade would immediately
        // swallow the click being started here.
        duckingVoices.removeAll { $0.node === node }
        // NaN fails every comparison, so min/max would let it through as the
        // upper bound (full blast); reject it explicitly.
        node.volume = gain.isFinite ? max(0.0, min(2.0, gain)) : 1.0
        // scheduleBuffer/play raise if the node's connection was invalidated
        // by a device change we haven't rewired yet. A dropped click is a
        // non-event; an uncaught raise here would kill the app mid-keystroke.
        var thrown: NSError?
        if !KlackRunCatchingExceptions({
            node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            node.play()
        }, &thrown) {
            NSLog("Klack: dropped a click (\(thrown?.localizedDescription ?? "unknown")) — rewiring")
            handleConfigurationChange()
        }
    }

    /// Marks every voice still ringing from an earlier keystroke to be faded.
    /// Only a new *strike* ducks -- a key-up belongs to the keystroke that's
    /// already sounding, so letting it duck would swallow the click it's
    /// supposed to complete.
    private func duckVoices(except newNode: AVAudioPlayerNode, release: Double) {
        // Nodes stay "playing" after their buffer runs out, so isPlaying alone
        // would sweep in long-finished voices; the volume check keeps this to
        // the ones actually still making sound.
        for node in pool where node !== newNode && node.isPlaying && node.volume > duckFloor {
            if !duckingVoices.contains(where: { $0.node === node }) {
                duckingVoices.append(DuckingVoice(node: node, startVolume: node.volume,
                                                  elapsed: 0, release: release))
            }
        }
        guard !duckingVoices.isEmpty, duckTimer == nil else { return }
        lastDuckTick = CFAbsoluteTimeGetCurrent()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stepDucking()
        }
        // Common modes so the fade keeps running while a menu is open --
        // otherwise tails freeze mid-duck whenever the menu bar is showing.
        RunLoop.main.add(timer, forMode: .common)
        duckTimer = timer
    }

    private func stepDucking() {
        let now = CFAbsoluteTimeGetCurrent()
        // Time-based rather than per-tick so a dropped or late timer fire
        // fades by the right amount instead of stretching the decay.
        let dt = max(0, now - lastDuckTick)
        lastDuckTick = now

        // Raised cosine rather than an exponential. An exponential is steepest
        // the instant the next key lands, which is what made a fast run sound
        // like clicks piling onto each other. This one is flat at the start so
        // the note keeps its identity, steepest in the middle, and flat again
        // into silence -- so a tail eases out of the way and the next click
        // arrives in clear air while still feeling joined to the one before.
        var survivors: [DuckingVoice] = []
        survivors.reserveCapacity(duckingVoices.count)
        for var voice in duckingVoices {
            guard voice.node.isPlaying else { continue }
            voice.elapsed += dt
            let progress = Float(min(1, voice.elapsed / voice.release))
            let next = voice.startVolume * 0.5 * (1 + cosf(.pi * progress))
            if progress >= 1 || next <= duckFloor {
                // Silence it but let the scheduled buffer run itself out.
                // Calling stop() here would make the node look idle to
                // nextNode(), which then reuses it and calls play() before the
                // render thread has cycled -- AVFoundation throws
                // "player did not see an IO cycle" and the app dies.
                voice.node.volume = 0
                continue
            }
            voice.node.volume = next
            survivors.append(voice)
        }
        duckingVoices = survivors

        if duckingVoices.isEmpty {
            duckTimer?.invalidate()
            duckTimer = nil
        }
    }

    /// Levels of every currently-sounding voice, loudest first. Used by the
    /// ducking self-test to check that a fast burst actually produces one
    /// dominant click over fading tails, rather than a stack of equals.
    var activeVoiceLevels: [Float] {
        pool.filter { $0.isPlaying }.map { $0.volume }.sorted(by: >)
    }

    /// Measures the actual signal leaving the mixer while `body` runs.
    ///
    /// Every other check tests intent -- engine running, buffers loaded, voice
    /// volumes set. None of them prove sound is genuinely being produced. This
    /// taps the real output, so "the app is silent" and "the sound is going to
    /// a device you aren't listening to" can finally be told apart.
    func measureOutputPeak(seconds: Double, _ body: () -> Void) -> Float {
        var peak: Float = 0
        let mixer = engine.mainMixerNode
        mixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            for ch in 0..<Int(buffer.format.channelCount) {
                let samples = data[ch]
                for i in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(samples[i]))
                }
            }
        }
        defer { mixer.removeTap(onBus: 0) }
        body()
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        return peak
    }

    /// Voices belong to the graph being torn down or replaced, so any pending
    /// fade is meaningless -- clear it rather than let the timer keep poking
    /// nodes that are about to be reconnected.
    private func cancelDucking() {
        duckTimer?.invalidate()
        duckTimer = nil
        duckingVoices.removeAll()
    }

    /// `gainMultiplier` is the fast-typing reward boost (1.0 = normal,
    /// >1.0 = typing fast enough to earn a little extra volume).
    /// Level applied to a keystroke at a given flow.
    ///
    /// Deliberately downward. This used to be a "fast typing reward" that made
    /// bursts up to 30% *louder*, which is the opposite of what a run of typing
    /// needs -- it stacked the clicks that were already stacking. A burst
    /// should settle into the background and read as texture.
    static func burstGain(for flow: Float) -> Float {
        1 - 0.28 * min(1, max(0, flow))
    }

    private func release(forFlow flow: Float) -> Double {
        duckReleaseSlow + (duckReleaseFast - duckReleaseSlow) * Double(flow)
    }

    /// `flow` is 0 for an isolated keystroke and 1 in a fast burst. It drives
    /// level, tone and release together, so the faster you type the quieter,
    /// darker and tighter each click becomes.
    func playKeyDown(isSpace: Bool, flow: Float = 0) {
        let f = flow.isFinite ? min(1, max(0, flow)) : 0
        let gain = Self.burstGain(for: f)
        let fade = release(forFlow: f)
        // Past the halfway point the darker set takes over. There's no audible
        // switch to worry about: every keystroke is a separate sound anyway,
        // and flow moves gradually, so the character shifts rather than jumps.
        let inBurst = f > 0.5

        if isSpace {
            if let b = (inBurst ? softSpaceDownBuffer : spaceDownBuffer) ?? spaceDownBuffer {
                play(b, gain: gain, ducksOthers: true, release: fade)
            }
            return
        }
        let source = (inBurst && !softDownBuffers.isEmpty) ? softDownBuffers : downBuffers
        if let b = nextDownVariant(from: source, melodic: f > 0.35) {
            play(b, gain: gain, ducksOthers: true, release: fade)
        }
    }

    /// Walks the variants up and down instead of picking at random.
    ///
    /// Random selection is what makes a fast run sound like gravel: successive
    /// clicks have no relationship, so the ear hears noise. Stepping through
    /// the variants in order gives a burst a rising-then-falling contour, which
    /// is enough for it to read as a phrase. Slow typing stays random, where
    /// variety matters more than shape.
    private func nextDownVariant(from buffers: [AVAudioPCMBuffer], melodic: Bool) -> AVAudioPCMBuffer? {
        guard !buffers.isEmpty else { return nil }
        guard melodic, buffers.count > 1 else { return buffers.randomElement() }
        melodyIndex += melodyStep
        if melodyIndex >= buffers.count - 1 {
            melodyIndex = buffers.count - 1
            melodyStep = -1
        } else if melodyIndex <= 0 {
            melodyIndex = 0
            melodyStep = 1
        }
        return buffers[melodyIndex]
    }

    func playKeyUp(isSpace: Bool) {
        if isSpace, let b = spaceUpBuffer {
            play(b)
        } else if let b = upBuffers.randomElement() {
            play(b)
        }
    }

    // MARK: Health

    /// Whether the engine is actually able to produce sound right now.
    ///
    /// Exists because a silent-audio regression is invisible to every other
    /// check we have: the app launches, the UI renders, the build is clean,
    /// and nothing sounds. `KLACK_SELFTEST` asserts on this so a broken audio
    /// graph fails loudly instead of shipping quiet.
    struct Health {
        var engineRunning = false
        var downBufferCount = 0
        var upBufferCount = 0
        var hasSpaceBuffers = false
        var outputFormat = ""
        var bufferFormat = ""
        var problems: [String] = []
        var isHealthy: Bool { problems.isEmpty }
    }

    func health() -> Health {
        var h = Health()
        h.engineRunning = engine.isRunning
        h.downBufferCount = downBuffers.count
        h.upBufferCount = upBuffers.count
        h.hasSpaceBuffers = spaceDownBuffer != nil && spaceUpBuffer != nil
        h.outputFormat = "\(engine.outputNode.outputFormat(forBus: 0))"
        h.bufferFormat = format.map { "\($0)" } ?? "nil"

        if !engine.isRunning {
            h.problems.append("audio engine is not running — nothing will be audible")
        }
        if downBuffers.isEmpty {
            h.problems.append("no keydown samples loaded")
        }
        if downBuffers.contains(where: { $0.frameLength == 0 }) {
            h.problems.append("a keydown sample has zero frames and would play silence")
        }
        if upBuffers.isEmpty {
            h.problems.append("no keyup samples loaded")
        }
        if pool.isEmpty {
            h.problems.append("player pool is empty")
        }
        return h
    }

    // MARK: Analysis

    /// Band energies of the current pack's sample, for the spectrum display.
    ///
    /// Uses Goertzel per band rather than a full FFT: we only need a handful of
    /// band magnitudes, and Goertzel is O(n) per band with no transform setup
    /// or power-of-two padding. Cached per pack, since the sample doesn't
    /// change until the pack does.
    func currentSpectrum(bands: Int = 20) -> [Float] {
        if let cached = spectrumCache[currentProfile], cached.count == bands {
            return cached
        }
        guard let buffer = downBuffers.first,
              let data = buffer.floatChannelData?[0] else {
            return [Float](repeating: 0, count: bands)
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 64 else { return [Float](repeating: 0, count: bands) }

        let sampleRate = Float(buffer.format.sampleRate)
        // Logarithmic spacing from 80Hz up — matches how the ear divides the
        // range, so bars spread out instead of bunching at the bottom.
        let lowHz: Float = 80
        let highHz = min(Float(12_000), sampleRate / 2 - 100)
        var out = [Float](repeating: 0, count: bands)

        for b in 0..<bands {
            let t = Float(b) / Float(max(1, bands - 1))
            let freq = lowHz * powf(highHz / lowHz, t)
            let k = 2 * Float.pi * freq / sampleRate
            let coeff = 2 * cosf(k)
            var s1: Float = 0, s2: Float = 0
            for i in 0..<frameCount {
                let s0 = data[i] + coeff * s1 - s2
                s2 = s1
                s1 = s0
            }
            let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
            let magnitude = sqrtf(max(0, power)) / Float(frameCount)
            // Compress toward a decibel-ish curve so quiet bands stay visible.
            out[b] = min(1, max(0, log10f(magnitude * 400 + 1) * 0.85))
        }

        // Normalise so every pack fills the display instead of some rendering
        // as a flat line.
        if let peak = out.max(), peak > 0.001 {
            for i in 0..<out.count { out[i] = min(1, out[i] / peak) }
        }
        spectrumCache[currentProfile] = out
        return out
    }

    // MARK: Live mixer support

    /// Renders raw samples straight into the player pool for instant preview
    /// while dragging a mixer slider — no disk round-trip.
    func previewSamples(_ samples: [Float]) {
        // A zero-capacity buffer is created successfully rather than returning
        // nil, so the empty case has to be rejected before that.
        guard !samples.isEmpty, let fmt = format,
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
                // An empty file would load fine and then play silence.
                guard !samples.isEmpty else {
                    throw NSError(domain: "Klack", code: 2, userInfo: [NSLocalizedDescriptionKey: "Refusing to write empty sample \(name)"])
                }
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
