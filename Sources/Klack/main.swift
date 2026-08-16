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
