import Cocoa

// Benchmark mode: times the synthesis path so the performance claims in the
// docs are measured rather than asserted.
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

    var defaults = SynthParams()
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

// Headless render mode: builds the control panel offscreen, writes a PNG, and
// exits. Lets the UI be inspected without a human having to describe it.
if let outPath = ProcessInfo.processInfo.environment["KLACK_RENDER_TEST"] {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let resourceDir = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    let engine = ClickAudioEngine(resourceDirectory: resourceDir)
    let tap = KeyTapManager()
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
