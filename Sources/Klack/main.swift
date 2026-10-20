import Cocoa
import AVFoundation
import KlackObjC

/// What the copy of Klack actually sitting in the menu bar reports about its
/// own Input Monitoring grant, read from the heartbeat file it writes.
///
/// The only trustworthy source: a test process can only ever see its own
/// (inherited) permission, never the running app's.
func installedAppPermission() -> String {
    let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Klack/diagnostic.json")
    guard let data = try? Data(contentsOf: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let granted = json["permission"] as? Bool,
          let updated = json["updated"] as? String else {
        return "no diagnostic file -- is the app running?"
    }
    let heard = json["keysHeard"] as? Int ?? 0
    return "permission \(granted), keysHeard \(heard), as of \(updated)"
}

// Benchmark mode: times the synthesis path so the performance claims in the
// docs are measured rather than asserted.
// Any KLACK_* mode is an instrument, not the app. Instruments must not leave
// fingerprints in the user's settings.
if ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("KLACK_") }) {
    ClickAudioEngine.persistsSettings = false
}

if ProcessInfo.processInfo.environment["KLACK_BENCH"] != nil {
    func measure(_ label: String, _ iterations: Int, _ body: () -> Void) {
        body() // warm up
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations { body() }
        let total = CFAbsoluteTimeGetCurrent() - start
        let perMs = total / Double(iterations) * 1000
        let padded = label.padding(toLength: 40, withPad: " ", startingAt: 0)
        print("\(padded) \(String(format: "%7.3f", perMs)) ms/call  (\(iterations) runs)")
    }

    let defaults = SynthParams()
    measure("render 70ms, default params", 200) {
        _ = SoundSynth.render(params: defaults, durationMs: 70, seed: 1)
    }

    // Worst case: longest decay and full reverb, which is the O(n·delay) path.
    var worst = SynthParams()
    worst.pitch = 3200
    worst.snappiness = 0
    worst.reverb = 1.0
    measure("render 70ms, worst case (reverb 1.0)", 200) {
        _ = SoundSynth.render(params: worst, durationMs: 70, seed: 1)
    }

    measure("render 110ms spacebar, worst case", 100) {
        _ = SoundSynth.render(params: worst, durationMs: 110, seed: 1)
    }

    // A full profile save renders 11 variants back to back.
    measure("full profile save (11 renders)", 30) {
        for i in 1...6 { _ = SoundSynth.render(params: defaults, durationMs: 70, seed: i) }
        for i in 1...3 { _ = SoundSynth.render(params: defaults, durationMs: 40, seed: 100 + i) }
        _ = SoundSynth.render(params: defaults, durationMs: 95, seed: 999)
        _ = SoundSynth.render(params: defaults, durationMs: 50, seed: 998)
    }

    print("\nA 60fps frame budget is 16.667 ms.")
    exit(0)
}

// Self-test: verifies the app can actually make sound, and exits non-zero if
// not. A silent-audio bug is invisible to a clean build and to the render
// harness, so this is the check that catches it before shipping.
if ProcessInfo.processInfo.environment["KLACK_SELFTEST"] != nil {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    var failures: [String] = []

    let resourceDir = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    guard let engine = ClickAudioEngine(resourceDirectory: resourceDir) else {
        print("FAIL  audio engine could not be constructed at all")
        exit(1)
    }

    // Input Monitoring is granted against the app's code identity, which
    // changes with every rebuild while the app is ad-hoc signed -- so this
    // silently flips to false after an install and the app goes deaf.
    //
    // Reporting this process's own grant here is a trap, and it cost us hours
    // once already. A binary spawned from a terminal inherits the *terminal's*
    // grant, so it prints true while the copy in the menu bar is stone deaf.
    //
    // A self-test process is never the menu-bar app -- that's the whole point
    // of it being a separate launch -- so its own answer is worthless by
    // construction. Quote the running app's heartbeat file instead.
    print("input monitoring : n/a from a test process (it inherits the caller's grant)")
    print("     running app : \(installedAppPermission())")
    let h = engine.health()
    print("engine running   : \(h.engineRunning)")
    print("keydown samples  : \(h.downBufferCount)")
    print("keyup samples    : \(h.upBufferCount)")
    print("space samples    : \(h.hasSpaceBuffers)")
    print("buffer format    : \(h.bufferFormat)")
    print("output format    : \(h.outputFormat)")
    failures.append(contentsOf: h.problems)

    // Scheduling is the real proof — a graph can be "running" and still throw
    // when a buffer whose format doesn't match the connection is scheduled.
    engine.playKeyDown(isSpace: false)
    engine.playKeyDown(isSpace: true)
    engine.playKeyUp(isSpace: false)
    RunLoop.current.run(until: Date().addingTimeInterval(0.35))

    let after = engine.health()
    if !after.engineRunning {
        failures.append("engine stopped after playing — the graph fell over on a real buffer")
    }

    // Synthesis path, used by the live mixer.
    let samples = SoundSynth.render(params: SynthParams(), durationMs: 70, seed: 1)
    if samples.isEmpty {
        failures.append("SoundSynth produced no samples")
    } else if samples.allSatisfy({ $0 == 0 }) {
        failures.append("SoundSynth produced pure silence")
    } else if samples.contains(where: { !$0.isFinite }) {
        failures.append("SoundSynth produced non-finite samples (NaN/inf)")
    }

    // Every selectable pack must be loadable, not just the current one.
    for pack in engine.availableProfiles {
        guard engine.switchProfile(to: pack) else {
            failures.append("pack '\(pack)' failed to load")
            continue
        }
        let ph = engine.health()
        if !ph.isHealthy {
            failures.append("pack '\(pack)': \(ph.problems.joined(separator: "; "))")
        }
    }

    print("")
    if failures.isEmpty {
        print("PASS  audio is healthy (\(engine.availableProfiles.count) packs verified)")
        exit(0)
    }
    for f in failures { print("FAIL  \(f)") }
    exit(1)
}

// Riser generator: builds the cold-open sound bed for the Klack film out of
// Klack's own synthesis engine.
//
// The build is made entirely of accelerating clicks rather than a stock
// trailer riser. That keeps the audio ownable (nobody else's footage can sound
// like this), sidesteps music licensing completely, and seeds the product's
// actual voice in the first seconds so the later reveal pays off something the
// ear already met.
//
//   KLACK_RISER=out.wav [KLACK_RISER_SECONDS=3.5]
if let riserPath = ProcessInfo.processInfo.environment["KLACK_RISER"] {
    let sr = SoundSynth.sampleRate
    let buildSeconds = Double(ProcessInfo.processInfo.environment["KLACK_RISER_SECONDS"]
        .flatMap { Double($0) } ?? 3.5)
    // Silence between the build and the hit. The gap is what makes the hit
    // land -- without it the ear never gets the contrast.
    let gapSeconds = 0.14
    let tailSeconds = 2.0
    let total = Int((buildSeconds + gapSeconds + tailSeconds) * sr)
    var mix = [Float](repeating: 0, count: total)

    func overlay(_ samples: [Float], atSecond t: Double, gain: Float) {
        let start = Int(t * sr)
        for (i, s) in samples.enumerated() where start + i < mix.count {
            mix[start + i] += s * gain
        }
    }

    // Click times follow an exponential curve: sparse and deliberate at the
    // top, collapsing into a blur by the end. Linear spacing reads as a
    // metronome, which is the opposite of tension.
    var t = 0.0
    var interval = 0.30
    var seed = 1
    while t < buildSeconds {
        let progress = t / buildSeconds

        var p = SynthParams()
        // Pitch and tightness both climb, so the clicks get smaller and more
        // urgent rather than just faster.
        p.pitch = 900 + Float(progress) * 1700
        p.snappiness = 0.35 + Float(progress) * 0.5
        p.brightness = 0.55 + Float(progress) * 0.4
        p.body = 0.5 - Float(progress) * 0.3
        p.attack = 0.4 + Float(progress) * 0.4
        p.reverb = 0.15

        let click = SoundSynth.render(params: p, durationMs: 70, seed: seed)
        // Loudness ramps with a curve, not a straight line -- the last third
        // is where a build should actually take off.
        overlay(click, atSecond: t, gain: 0.28 + Float(progress * progress) * 0.72)

        t += interval
        interval *= 0.86 // acceleration
        interval = max(interval, 0.028)
        seed += 1
    }

    // The hit: the same engine, pitched right down with a long tail. Using the
    // click's own voice for the impact keeps it in the family instead of
    // importing a generic boom.
    var hit = SynthParams()
    hit.pitch = 180
    hit.body = 1.0
    hit.brightness = 0.22
    hit.snappiness = 0.0
    hit.attack = 0.9
    hit.reverb = 0.85
    let hitSamples = SoundSynth.render(params: hit, durationMs: 1600, seed: 99)
    overlay(hitSamples, atSecond: buildSeconds + gapSeconds, gain: 1.0)

    // A second, higher layer stacked on the hit gives it a crack on top of the
    // low end so it cuts through on phone speakers.
    var crack = SynthParams()
    crack.pitch = 1400
    crack.body = 0.3
    crack.brightness = 1.0
    crack.snappiness = 0.2
    crack.attack = 1.0
    crack.reverb = 0.6
    overlay(SoundSynth.render(params: crack, durationMs: 900, seed: 7),
            atSecond: buildSeconds + gapSeconds, gain: 0.7)

    // Normalise to just under full scale so the file is loud enough to sit in
    // an edit without being clipped on the way in.
    let peak = mix.map { abs($0) }.max() ?? 1
    if peak > 0 {
        let target: Float = 0.92
        for i in mix.indices { mix[i] *= target / peak }
    }

    // 16-bit mono PCM WAV -- universally importable by any editor.
    var data = Data()
    func le32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func le16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let byteCount = UInt32(mix.count * 2)
    data.append(contentsOf: Array("RIFF".utf8)); le32(36 + byteCount)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8)); le32(16); le16(1); le16(1)
    le32(UInt32(sr)); le32(UInt32(sr) * 2); le16(2); le16(16)
    data.append(contentsOf: Array("data".utf8)); le32(byteCount)
    for s in mix {
        le16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767)))
    }
    try? data.write(to: URL(fileURLWithPath: riserPath))

    print("build      : \(String(format: "%.2f", buildSeconds))s")
    print("hit lands  : \(String(format: "%.2f", buildSeconds + gapSeconds))s")
    print("total      : \(String(format: "%.2f", Double(total) / sr))s")
    print("wrote      : \(riserPath)")
    exit(0)
}

// Audio proof: taps the real mixer output and measures the signal actually
// produced. Distinguishes "the app makes no sound" from "the app makes sound
// and it's going to a device you can't hear" -- the two look identical from
// the outside and every other check confuses them.
if ProcessInfo.processInfo.environment["KLACK_AUDIOPROOF"] != nil {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let resourceDir = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    guard let engine = ClickAudioEngine(resourceDirectory: resourceDir) else {
        print("FAIL  audio engine could not be constructed")
        exit(1)
    }

    print("pack             : \(engine.currentProfile)")
    print("volume           : \(engine.volume)")

    let peak = engine.measureOutputPeak(seconds: 1.2) {
        for _ in 0..<6 { engine.playKeyDown(isSpace: false) }
    }
    print("measured peak    : \(String(format: "%.4f", peak))")
    print("")

    // Anything above the noise floor means real audio reached the output.
    if peak < 0.001 {
        print("FAIL  the engine produced silence — this is a genuine audio bug")
        exit(1)
    }
    print("PASS  real audio is being produced (peak \(String(format: "%.3f", peak)))")
    print("      If you can't hear it, the sound is going to another output device.")
    exit(0)
}

// Live tap test: the one thing no other check can prove -- whether real
// keystrokes actually reach Klack. Permission can read as granted while macOS
// silently delivers nothing, so this waits for genuine key presses and reports
// what arrived, rather than inferring health from the tap's own status.
if ProcessInfo.processInfo.environment["KLACK_TAPTEST"] != nil {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    print("permission       : \(KeyTapManager.hasInputMonitoringPermission())")

    let tap = KeyTapManager()
    var seen = 0
    tap.onKeyDown = { isSpace in
        seen += 1
        print("  key #\(seen)\(isSpace ? " (space)" : "")")
        fflush(stdout)
    }
    let started = tap.start()
    print("tap created      : \(started)")
    print("tap live         : \(tap.isLive)")
    print("")
    print("TYPE SOME KEYS NOW — listening for 15 seconds…")
    fflush(stdout)

    RunLoop.current.run(until: Date().addingTimeInterval(15))

    print("")
    if seen == 0 {
        print("FAIL  no keystrokes reached Klack in 15s — the listener is deaf")
        exit(1)
    }
    print("PASS  \(seen) keystroke(s) reached Klack")
    exit(0)
}

// Crash-survival test: AVAudioEngine *raises* (rather than returning an error)
// when the graph is in an invalid state, which is what killed the app during
// audio-device changes. This deliberately provokes such a raise and checks the
// process survives it -- the whole point of the ObjC shim.
if ProcessInfo.processInfo.environment["KLACK_CRASHTEST"] != nil {
    let engine = AVAudioEngine()
    let orphan = AVAudioPlayerNode() // never attached -- connecting it raises

    var thrown: NSError?
    let survived = KlackRunCatchingExceptions({
        engine.connect(orphan, to: engine.mainMixerNode, format: nil)
    }, &thrown)

    if survived {
        print("FAIL  expected AVAudioEngine to raise, but it did not — test is not exercising the guard")
        exit(1)
    }
    print("caught           : \(thrown?.localizedDescription ?? "nil")")
    print("")
    print("PASS  raise was caught; process still alive instead of aborting")
    exit(0)
}

// Ducking test: fires a fast burst of keydowns and inspects the live voice
// levels. Without ducking every tail sits at full volume and they sum into
// mush; the fix is only real if older voices measurably fall behind the
// newest one, so this measures that rather than trusting it.
if ProcessInfo.processInfo.environment["KLACK_DUCKTEST"] != nil {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let resourceDir = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    guard let engine = ClickAudioEngine(resourceDirectory: resourceDir) else {
        print("FAIL  audio engine could not be constructed")
        exit(1)
    }

    var failures: [String] = []

    // Tail length differs per pack, and a long-tailed pack is exactly where
    // leftover stacking would hide -- so check every one, not just the default.
    for pack in engine.availableProfiles {
        guard engine.switchProfile(to: pack) else {
            failures.append("pack '\(pack)' failed to load")
            continue
        }

        // Long enough to wrap past the whole voice pool: recycled nodes are
        // where a fresh click can get caught by a leftover fade, and that
        // only shows up after the pool has been exhausted once.
        for _ in 0..<40 {
            engine.playKeyDown(isSpace: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }

        let levels = engine.activeVoiceLevels
        let printed = levels.prefix(6).map { String(format: "%.2f", $0) }.joined(separator: ", ")
        print(String(format: "%-18@", pack as NSString), terminator: "")
        print("voices: \(levels.count)  levels: \(printed)")

        guard let loudest = levels.first else {
            failures.append("\(pack): no voices sounding after a burst")
            continue
        }
        // The newest strike must stay at full level -- ducking should thin
        // the tails, never swallow the click the user just made.
        if loudest < 0.9 {
            failures.append("\(pack): newest voice ducked to \(loudest), should stay ~1.0")
        }
        // Everything older must be measurably below it, otherwise nothing faded.
        let stacked = levels.dropFirst().filter { $0 > 0.9 }
        if !stacked.isEmpty {
            failures.append("\(pack): \(stacked.count) older voice(s) still at full level")
        }

        // Let the burst fully decay so the next pack starts from silence
        // rather than inheriting these tails.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    // Burst shaping. The same keystrokes at the same interval should leave
    // fewer tails ringing when the engine believes you're mid-run, because the
    // release shortens with flow. This is the whole claim behind "don't stack
    // when I type fast", so it gets measured rather than eyeballed.
    func ringingTails(flow: Float) -> Int {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        for _ in 0..<12 {
            engine.playKeyDown(isSpace: false, flow: flow)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return engine.activeVoiceLevels.filter { $0 > 0.1 }.count
    }

    if let pack = engine.availableProfiles.first, engine.switchProfile(to: pack) {
        let slowTails = ringingTails(flow: 0)
        let fastTails = ringingTails(flow: 1)
        print("")
        print("tails still ringing   slow: \(slowTails)   burst: \(fastTails)")
        if fastTails >= slowTails {
            failures.append("burst shaping: \(fastTails) tails at full flow vs \(slowTails) at rest -- should be fewer")
        }
    }

    print("")
    if failures.isEmpty {
        print("PASS  newest click dominates, and bursts leave fewer tails")
        exit(0)
    }
    for f in failures { print("FAIL  \(f)") }
    exit(1)
}

// Headless render mode: builds the control panel offscreen, writes a PNG, and
// exits. Lets the UI be inspected without a human having to describe it.
if let outPath = ProcessInfo.processInfo.environment["KLACK_RENDER_TEST"] {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let resourceDir = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    let engine = ClickAudioEngine(resourceDirectory: resourceDir)
    let tap = KeyTapManager()

    // Pick a theme up front so each one can be captured for review.
    if let themeName = ProcessInfo.processInfo.environment["KLACK_THEME"],
       let match = Theme.all.first(where: { $0.name.caseInsensitiveCompare(themeName) == .orderedSame }) {
        Theme.current = match
    }

    let controller = ShowcaseWindowController(audioEngine: engine, keyTap: tap)

    if ProcessInfo.processInfo.environment["KLACK_RENDER_MIXER"] != nil {
        controller.openMixerForRender()
    }

    guard let view = controller.window?.contentView else { exit(1) }
    view.layoutSubtreeIfNeeded()

    func snapshot(to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    // Frame-sequence mode: write a numbered PNG per frame so the panel can be
    // turned into a video without any screen recording.
    if let frameCountText = ProcessInfo.processInfo.environment["KLACK_RENDER_FRAMES"],
       let frameCount = Int(frameCountText), frameCount > 0 {
        let dir = URL(fileURLWithPath: outPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in 0..<frameCount {
            let t = CGFloat(f) / CGFloat(frameCount)
            controller.setRenderState(progress: t)
            view.displayIfNeeded()
            snapshot(to: dir.appendingPathComponent(String(format: "frame_%04d.png", f)))
        }
        print("rendered \(frameCount) frames -> \(outPath)")
        exit(0)
    }

    // Social mode: composes the panel onto a branded canvas at a given aspect
    // ratio, so Behance/LinkedIn/Instagram assets regenerate from source
    // instead of being cropped by hand every time the design changes.
    if let spec = ProcessInfo.processInfo.environment["KLACK_SOCIAL"] {
        let parts = spec.split(separator: "x").compactMap { Int($0) }
        let canvasW = CGFloat(parts.first ?? 1080)
        let canvasH = CGFloat(parts.count > 1 ? parts[1] : 1080)
        let caption = ProcessInfo.processInfo.environment["KLACK_CAPTION"] ?? ""

        controller.simulateActivityForRender()
        guard let panelRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: panelRep)

        let canvas = NSImage(size: NSSize(width: canvasW, height: canvasH))
        canvas.lockFocus()

        let th = Theme.current
        NSGradient(colors: [th.chassisMid.blended(withFraction: 0.55, of: .black) ?? .black,
                            NSColor.black],
                   atLocations: [0, 1], colorSpace: .sRGB)?
            .draw(fromCenter: NSPoint(x: canvasW / 2, y: canvasH * 0.62), radius: 0,
                  toCenter: NSPoint(x: canvasW / 2, y: canvasH * 0.62),
                  radius: max(canvasW, canvasH) * 0.85, options: [])

        // Faint accent wash so the backdrop carries the active theme.
        NSGradient(colors: [th.accentMid.withAlphaComponent(0.20), .clear],
                   atLocations: [0, 1], colorSpace: .sRGB)?
            .draw(fromCenter: NSPoint(x: canvasW * 0.5, y: canvasH * 0.66), radius: 0,
                  toCenter: NSPoint(x: canvasW * 0.5, y: canvasH * 0.66),
                  radius: canvasW * 0.55, options: [])

        let margin = canvasW * 0.09
        let captionRoom: CGFloat = caption.isEmpty ? 0 : canvasH * 0.14
        let maxW = canvasW - margin * 2
        let maxH = canvasH - margin * 2 - captionRoom
        let scale = min(maxW / view.bounds.width, maxH / view.bounds.height)
        let drawW = view.bounds.width * scale
        let drawH = view.bounds.height * scale
        let drawRect = NSRect(x: (canvasW - drawW) / 2,
                              y: (canvasH - drawH) / 2 + captionRoom * 0.5,
                              width: drawW, height: drawH)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.75)
        shadow.shadowOffset = NSSize(width: 0, height: -canvasH * 0.02)
        shadow.shadowBlurRadius = canvasH * 0.055
        shadow.set()
        panelRep.draw(in: drawRect)
        NSGraphicsContext.restoreGraphicsState()

        if !caption.isEmpty {
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: canvasW * 0.032, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                .kern: canvasW * 0.004,
                .paragraphStyle: para,
            ]
            let s = NSAttributedString(string: caption, attributes: attrs)
            let h = s.boundingRect(with: NSSize(width: maxW, height: 400),
                                   options: [.usesLineFragmentOrigin]).height
            s.draw(with: NSRect(x: margin, y: margin * 0.5, width: maxW, height: h),
                   options: [.usesLineFragmentOrigin])
        }

        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: outPath))
        print("social \(Int(canvasW))x\(Int(canvasH)) -> \(outPath)")
        exit(0)
    }

    controller.simulateActivityForRender()
    snapshot(to: URL(fileURLWithPath: outPath))
    print("rendered \(Int(view.bounds.width))x\(Int(view.bounds.height)) -> \(outPath)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
