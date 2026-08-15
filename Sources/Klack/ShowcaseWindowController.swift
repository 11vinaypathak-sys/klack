import Cocoa

/// Klack's control panel — a dark chassis with a glossy white plastic plate,
/// a backlit amber display, and machined rotary controls. Layout mirrors the
/// Figma reference. The menu-bar dropdown remains the everyday interface;
/// this is the full-fat panel.
final class ShowcaseWindowController: NSWindowController, NSWindowDelegate {
    private let audioEngine: ClickAudioEngine?
    private let keyTap: KeyTapManager
    private var onClosed: (() -> Void)?

    private var display: BacklitDisplayView!
    private var waveform: WaveformView!
    private var volumeKnob: KnobControl!
    private var trimKnobs: [String: KnobControl] = [:]
    private var lamps: [(name: String, lamp: LEDLamp, label: NSTextField)] = []
    private var mixerParams = SynthParams()

    private var mixerDrawer: NSView!
    private var mixerOpen = false
    private var keystrokeObserver: NSObjectProtocol?
    private var backlightDecay: Timer?
    private var isBoosting = false
    private var lastWasSpace = false

    private let chassisW: CGFloat = 560
    private let chassisH: CGFloat = 400
    private let drawerWidth: CGFloat = 190
    private let plateOrigin = NSPoint(x: 80, y: 22)
    private let plateSize = NSSize(width: 400, height: 356)

    /// The four params that live in the slide-out drawer; TONE and BODY stay
    /// on the front panel as the two you reach for most.
    private let drawerSpecs: [(key: String, label: String, min: Double, max: Double)] = [
        ("brightness", "BRIGHT", 0, 1),
        ("snappiness", "SNAP", 0, 1),
        ("attack", "ATTACK", 0, 1),
        ("reverb", "REVERB", 0, 1),
    ]

    init(audioEngine: ClickAudioEngine?, keyTap: KeyTapManager, onClosed: (() -> Void)? = nil) {
        self.audioEngine = audioEngine
        self.keyTap = keyTap
        self.onClosed = onClosed

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        super.init(window: window)
        window.delegate = self
        window.contentView = buildChassis()
        refreshDisplay()

        keystrokeObserver = NotificationCenter.default.addObserver(
            forName: .klackKeystroke, object: nil, queue: .main
        ) { [weak self] note in
            let boost = (note.userInfo?["boost"] as? Float) ?? 1.0
            let isSpace = (note.userInfo?["isSpace"] as? Bool) ?? false
            self?.handleKeystroke(boost: CGFloat(boost), isSpace: isSpace)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        if let obs = keystrokeObserver { NotificationCenter.default.removeObserver(obs) }
        backlightDecay?.invalidate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        backlightDecay?.invalidate()
        backlightDecay = nil
        onClosed?()
    }

    /// Drive the live parts of the panel from real typing: the trace scrolls,
    /// the backlight lifts, and the active lamp flickers brighter.
    private func handleKeystroke(boost: CGFloat, isSpace: Bool) {
        guard window?.isVisible == true else { return }
        // boost is 1.0 at normal speed, rising toward ~1.3 when typing fast.
        let intensity = min(1.0, max(0.2, (boost - 0.9) * 2.4))
        waveform.pulse(intensity: intensity)

        isBoosting = boost > 1.02
        lastWasSpace = isSpace
        display.backlightBoost = min(0.18, display.backlightBoost + 0.09)
        refreshDisplay()
        startBacklightDecay()
    }

    private func startBacklightDecay() {
        guard backlightDecay == nil else { return }
        backlightDecay = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.display.backlightBoost *= 0.82
            self.display.needsDisplay = true
            if self.display.backlightBoost < 0.005 {
                self.display.backlightBoost = 0
                self.display.needsDisplay = true
                t.invalidate()
                self.backlightDecay = nil
            }
        }
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refreshDisplay()
    }

    // MARK: Build

    private func buildChassis() -> NSView {
        let chassis = ChassisView(frame: NSRect(origin: .zero, size: NSSize(width: chassisW, height: chassisH)))
        chassis.wantsLayer = true
        chassis.layer?.cornerRadius = 26
        chassis.layer?.masksToBounds = true

        buildLamps(into: chassis)
        buildChassisFurniture(into: chassis)

        let plate = PlasticPlateView(frame: NSRect(origin: plateOrigin, size: plateSize))
        plate.wantsLayer = true
        // Layered shadow: a tight contact shadow plus a wide soft ambient one.
        // shadowPath keeps Core Animation from rasterising the alpha each frame.
        plate.layer?.shadowColor = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.09, alpha: 1).cgColor
        plate.layer?.shadowOpacity = 0.45
        plate.layer?.shadowOffset = CGSize(width: 0, height: -10)
        plate.layer?.shadowRadius = 16
        plate.layer?.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: plateSize),
                                         cornerWidth: 30, cornerHeight: 30, transform: nil)
        chassis.addSubview(plate)

        buildDisplay(into: plate)
        buildControls(into: plate)

        return chassis
    }

    private func buildLamps(into chassis: NSView) {
        let packs = audioEngine?.availableProfiles ?? []
        for (i, name) in packs.prefix(4).enumerated() {
            let cy = 132 + CGFloat(i) * 40
            let lamp = LEDLamp(frame: NSRect(x: 29, y: cy - 11, width: 22, height: 22))
            lamp.isLit = (name == audioEngine?.currentProfile)
            lamp.identifier = NSUserInterfaceItemIdentifier(name)
            lamp.target = self
            lamp.action = #selector(selectPack(_:))
            chassis.addSubview(lamp)

            let label = NSTextField(labelWithString: ClickAudioEngine.label(for: name).uppercased())
            label.font = .systemFont(ofSize: 7, weight: .bold)
            label.textColor = NSColor(white: 1, alpha: lamp.isLit ? 0.85 : 0.35)
            label.alignment = .center
            label.backgroundColor = .clear
            label.frame = NSRect(x: 6, y: cy + 13, width: 68, height: 10)
            chassis.addSubview(label)

            lamps.append((name, lamp, label))
        }
    }

    private func buildChassisFurniture(into chassis: NSView) {
        // The drawer lives to the right of the base chassis width and is
        // revealed by widening the window, so it appears to slide out.
        mixerDrawer = FlippedContainer(frame: NSRect(x: chassisW - 10, y: 60, width: drawerWidth, height: 280))
        mixerDrawer.wantsLayer = true
        mixerDrawer.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.12, blue: 0.17, alpha: 1).cgColor
        mixerDrawer.layer?.cornerRadius = 16
        mixerDrawer.isHidden = true
        chassis.addSubview(mixerDrawer)
        buildDrawerContents()

        let tab = NSButton(frame: NSRect(x: 512, y: 105, width: 30, height: 190))
        tab.wantsLayer = true
        tab.isBordered = false
        tab.title = ""
        tab.layer?.backgroundColor = NSColor(srgbRed: 0.16, green: 0.18, blue: 0.24, alpha: 1).cgColor
        tab.layer?.cornerRadius = 8
        tab.target = self
        tab.action = #selector(toggleMixer)
        chassis.addSubview(tab)

        let tabLabel = NSTextField(labelWithString: "MIXER")
        tabLabel.font = .systemFont(ofSize: 10, weight: .bold)
        tabLabel.textColor = NSColor(white: 1, alpha: 0.55)
        tabLabel.backgroundColor = .clear
        tabLabel.alignment = .center
        tabLabel.frame = NSRect(x: 512, y: 185, width: 30, height: 14)
        tabLabel.frameCenterRotation = -90
        chassis.addSubview(tabLabel)

        let close = NSButton(frame: NSRect(x: 510, y: 24, width: 30, height: 30))
        close.title = "✕"
        close.isBordered = false
        close.font = .systemFont(ofSize: 17, weight: .medium)
        close.contentTintColor = NSColor(white: 1, alpha: 0.7)
        close.target = self
        close.action = #selector(closeWindow)
        chassis.addSubview(close)

        for i in 0..<3 {
            let ridge = NSView(frame: NSRect(x: 508, y: 330 + CGFloat(i) * 7, width: 22, height: 3))
            ridge.wantsLayer = true
            ridge.layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
            ridge.layer?.cornerRadius = 1.5
            chassis.addSubview(ridge)
        }
    }

    private func buildDisplay(into plate: NSView) {
        let bezel = FlippedContainer(frame: NSRect(x: 28, y: 26, width: 344, height: 172))
        bezel.wantsLayer = true
        bezel.layer?.backgroundColor = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1).cgColor
        bezel.layer?.cornerRadius = 20
        plate.addSubview(bezel)

        display = BacklitDisplayView(frame: NSRect(x: 8, y: 8, width: 328, height: 156))
        display.wantsLayer = true
        // Bloom spilling onto the housing — without this the screen still
        // looks pasted on rather than emitting.
        display.layer?.shadowColor = NSColor(srgbRed: 1, green: 0.65, blue: 0.20, alpha: 1).cgColor
        display.layer?.shadowOpacity = 0.6
        display.layer?.shadowOffset = .zero
        display.layer?.shadowRadius = 20
        bezel.addSubview(display)

        // Live activity trace, bottom-right — clear of the pack name.
        waveform = WaveformView(frame: NSRect(x: 168, y: 108, width: 142, height: 36))
        display.addSubview(waveform)
    }

    private func buildControls(into plate: NSView) {
        let preview = RoundButton(frame: NSRect(x: 70 - 32, y: 272 - 32, width: 64, height: 64))
        preview.isBordered = false
        preview.title = ""
        preview.glyph = "▶"
        preview.target = self
        preview.action = #selector(previewMix)
        plate.addSubview(preview)

        let save = RoundButton(frame: NSRect(x: 136 - 32, y: 272 - 32, width: 64, height: 64))
        save.isBordered = false
        save.title = "SAVE"
        save.isAccent = true
        save.target = self
        save.action = #selector(saveMix)
        plate.addSubview(save)

        addTrimKnob(key: "pitch", label: "TONE", center: NSPoint(x: 200, y: 264), into: plate,
                    min: 400, max: 3200, value: Double(mixerParams.pitch))
        addTrimKnob(key: "body", label: "BODY", center: NSPoint(x: 246, y: 264), into: plate,
                    min: 0, max: 1, value: Double(mixerParams.body))

        volumeKnob = KnobControl(frame: NSRect(x: 312 - 54, y: 272 - 54, width: 108, height: 108))
        volumeKnob.minValue = 0
        volumeKnob.maxValue = 1
        volumeKnob.value = Double(audioEngine?.volume ?? 0.8)
        volumeKnob.target = self
        volumeKnob.action = #selector(volumeChanged(_:))
        plate.addSubview(volumeKnob)
    }

    private func buildDrawerContents() {
        let header = NSTextField(labelWithString: "SYNTH MIXER")
        header.font = .systemFont(ofSize: 9, weight: .bold)
        header.textColor = NSColor(white: 1, alpha: 0.5)
        header.backgroundColor = .clear
        header.alignment = .center
        header.frame = NSRect(x: 20, y: 16, width: drawerWidth - 40, height: 12)
        mixerDrawer.addSubview(header)

        // Two-by-two grid of the remaining synth params.
        for (i, spec) in drawerSpecs.enumerated() {
            let col = CGFloat(i % 2), row = CGFloat(i / 2)
            let cx = 52 + col * 86
            let cy = 78 + row * 108

            let knob = KnobControl(frame: NSRect(x: cx - 28, y: cy - 28, width: 56, height: 56))
            knob.minValue = spec.min
            knob.maxValue = spec.max
            knob.value = Double(value(for: spec.key))
            knob.identifier = NSUserInterfaceItemIdentifier(spec.key)
            knob.target = self
            knob.action = #selector(trimChanged(_:))
            mixerDrawer.addSubview(knob)
            trimKnobs[spec.key] = knob

            let caption = NSTextField(labelWithString: spec.label)
            caption.font = .systemFont(ofSize: 8, weight: .bold)
            caption.textColor = NSColor(white: 1, alpha: 0.55)
            caption.alignment = .center
            caption.backgroundColor = .clear
            caption.frame = NSRect(x: cx - 34, y: cy + 32, width: 68, height: 11)
            mixerDrawer.addSubview(caption)
        }

        let reset = NSButton(frame: NSRect(x: 30, y: 232, width: drawerWidth - 60, height: 26))
        reset.title = "Reset"
        reset.bezelStyle = .rounded
        reset.font = .systemFont(ofSize: 11)
        reset.target = self
        reset.action = #selector(resetMixer)
        mixerDrawer.addSubview(reset)
    }

    private func value(for key: String) -> Float {
        switch key {
        case "pitch": return mixerParams.pitch
        case "body": return mixerParams.body
        case "brightness": return mixerParams.brightness
        case "snappiness": return mixerParams.snappiness
        case "attack": return mixerParams.attack
        case "reverb": return mixerParams.reverb
        default: return 0
        }
    }

    private func addTrimKnob(key: String, label: String, center: NSPoint, into plate: NSView,
                             min: Double, max: Double, value: Double) {
        let knob = KnobControl(frame: NSRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48))
        knob.minValue = min
        knob.maxValue = max
        knob.value = value
        knob.showsValueArc = false
        knob.identifier = NSUserInterfaceItemIdentifier(key)
        knob.target = self
        knob.action = #selector(trimChanged(_:))
        plate.addSubview(knob)
        trimKnobs[key] = knob

        let caption = NSTextField(labelWithString: label)
        caption.font = .systemFont(ofSize: 8, weight: .bold)
        caption.textColor = NSColor(srgbRed: 0.42, green: 0.44, blue: 0.49, alpha: 1)
        caption.alignment = .center
        caption.backgroundColor = .clear
        caption.frame = NSRect(x: center.x - 30, y: center.y + 26, width: 60, height: 12)
        plate.addSubview(caption)
    }

    // MARK: State

    private func refreshDisplay() {
        let volume = audioEngine?.volume ?? 0
        // Flags reflect live state rather than being decorative.
        display.flags = [
            ("ENABLED", keyTap.isEnabled),
            ("FAST BOOST", isBoosting),
            ("SPACEBAR", lastWasSpace),
        ]
        display.volumeFraction = CGFloat(volume)
        display.bigValue = String(Int(volume * 100))
        display.packName = audioEngine.map { ClickAudioEngine.label(for: $0.currentProfile).uppercased() } ?? ""
        display.needsDisplay = true
    }

    // MARK: Actions

    @objc private func closeWindow() { window?.close() }

    @objc private func selectPack(_ sender: LEDLamp) {
        guard let name = sender.identifier?.rawValue,
              audioEngine?.switchProfile(to: name) == true else { return }
        for entry in lamps {
            entry.lamp.isLit = (entry.name == name)
            entry.label.textColor = NSColor(white: 1, alpha: entry.lamp.isLit ? 0.85 : 0.35)
        }
        audioEngine?.playKeyDown(isSpace: false)
        refreshDisplay()
    }

    @objc private func volumeChanged(_ sender: KnobControl) {
        audioEngine?.volume = Float(sender.value)
        refreshDisplay()
    }

    @objc private func trimChanged(_ sender: KnobControl) {
        guard let key = sender.identifier?.rawValue else { return }
        let v = Float(sender.value)
        switch key {
        case "pitch": mixerParams.pitch = v
        case "body": mixerParams.body = v
        case "brightness": mixerParams.brightness = v
        case "snappiness": mixerParams.snappiness = v
        case "attack": mixerParams.attack = v
        case "reverb": mixerParams.reverb = v
        default: break
        }
        previewMix()
    }

    @objc private func toggleMixer() {
        guard let window else { return }
        mixerOpen.toggle()
        let targetWidth = mixerOpen ? chassisW + drawerWidth - 10 : chassisW
        var frame = window.frame
        frame.size.width = targetWidth

        if mixerOpen { mixerDrawer.isHidden = false }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if !self.mixerOpen { self.mixerDrawer.isHidden = true }
        })
    }

    // MARK: Render-test hooks

    /// Reveal the drawer without the window animation, for offscreen renders.
    func openMixerForRender() {
        mixerOpen = true
        mixerDrawer.isHidden = false
        if let window {
            var f = window.frame
            f.size.width = chassisW + drawerWidth - 10
            window.setFrame(f, display: false)
        }
    }

    /// Populate the waveform so a static render shows the trace populated.
    func simulateActivityForRender() {
        for i in 0..<26 {
            let t = CGFloat(i) / 26
            waveform.pulse(intensity: 0.25 + 0.7 * abs(sin(t * 7)))
        }
        display.backlightBoost = 0.1
        display.needsDisplay = true
    }

    @objc private func resetMixer() {
        mixerParams = SynthParams()
        for (key, knob) in trimKnobs {
            knob.value = Double(value(for: key))
        }
        volumeKnob.needsDisplay = true
        previewMix()
    }

    @objc private func previewMix() {
        let samples = SoundSynth.render(params: mixerParams, durationMs: 70, seed: 42)
        audioEngine?.previewSamples(samples)
    }

    @objc private func saveMix() {
        _ = audioEngine?.saveCustomProfile(params: mixerParams)
        refreshDisplay()
    }
}
