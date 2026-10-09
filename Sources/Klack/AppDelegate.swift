import Cocoa
import ServiceManagement

extension Notification.Name {
    /// Broadcast on each keydown so open UI can react. userInfo["boost"]
    /// carries the fast-typing multiplier.
    static let klackKeystroke = Notification.Name("com.vinaypathak.klack.keystroke")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var audioEngine: ClickAudioEngine?
    private let keyTap = KeyTapManager()
    private var permissionCheckTimer: Timer?

    private var volume: Float = 0.8
    private var mixerParams = SynthParams()
    private var showcaseWindowController: ShowcaseWindowController?

    // Set while the Test & Fix flow is waiting for the user to press a key.
    private var keysHeard = 0
    private var lastDiagnosticWrite: CFAbsoluteTime = 0
    private var pendingKeystrokeProof: (() -> Void)?
    private var diagnosticPanel: NSPanel?
    private var diagnosticLabel: NSTextField?
    private var diagnosticTimeout: Timer?

    // Typing flow: track recent keydown timing so the engine can tell an
    // isolated keystroke from a run and shape level, tone and release to match.
    private var recentKeyDownTimes: [CFAbsoluteTime] = []
    private let speedWindowSize = 6
    private let fastTypingIntervalThreshold: Double = 0.18 // seconds between keys
    private let veryFastIntervalFloor: Double = 0.08

    private let permissionMenuItem = NSMenuItem()
    private let enabledMenuItem = NSMenuItem()
    private var launchAtLoginItem: NSMenuItem?
    private var packItems: [NSMenuItem] = []
    private var volumeView: SliderMenuItemView!
    private var softnessView: SliderMenuItemView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupAudioEngine()
        setupKeyTapHandlers()
        setupStatusItem()
        attemptStartTap()

        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.attemptStartTap()
        }

        // The event tap and the audio engine both sit on OS resources
        // (a mach port, a hardware audio device) that don't reliably survive
        // sleep. Rebuilding both on wake is what actually fixes "works, then
        // silently stops after the lid's been shut" -- waiting for the next
        // keystroke to notice isn't good enough, since a dead tap never
        // fires at all.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        startDiagnosticHeartbeat()
    }

    @objc private func handleWake() {
        keyTap.restart()
        audioEngine?.restartIfNeeded()
        lastDiagnosticWrite = 0
        recordDiagnostic(keyHeard: false)
    }

    /// Keeps the diagnostic file current even while nothing is being typed --
    /// a stalled keysHeard count next to a live timestamp is precisely the
    /// signature of a deaf listener.
    private func startDiagnosticHeartbeat() {
        recordDiagnostic(keyHeard: false)
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.lastDiagnosticWrite = 0
            self.recordDiagnostic(keyHeard: false)
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Klack") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⌨︎"
            }
        }
        statusItem.menu = buildMenu()
    }

    private func setupAudioEngine() {
        let resourceDir = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        audioEngine = ClickAudioEngine(resourceDirectory: resourceDir)
        audioEngine?.volume = volume
        if audioEngine == nil {
            NSLog("Klack: could not load click sounds from \(resourceDir.path)")
        }
    }

    private func setupKeyTapHandlers() {
        keyTap.onKeyDown = { [weak self] isSpace in
            guard let self else { return }
            // A real keystroke arriving here is the only honest proof the tap
            // works end to end -- "tap is enabled" can be true while macOS
            // silently delivers nothing.
            if let confirm = self.pendingKeystrokeProof {
                self.pendingKeystrokeProof = nil
                confirm()
            }
            let flow = self.recordKeyDownAndComputeFlow()
            self.audioEngine?.playKeyDown(isSpace: isSpace, flow: flow)
            self.recordDiagnostic(keyHeard: true)
            NotificationCenter.default.post(name: .klackKeystroke, object: nil,
                                            userInfo: ["boost": ClickAudioEngine.burstGain(for: flow),
                                                       "flow": flow, "isSpace": isSpace])
        }
        keyTap.onKeyUp = { [weak self] isSpace in
            self?.audioEngine?.playKeyUp(isSpace: isSpace)
        }
        keyTap.isEnabled = true
    }

    /// Writes what the *running* app is actually experiencing to disk.
    ///
    /// Every check so far spawned a fresh process, which is always healthy, so
    /// it could never see the state of the copy in the menu bar. This is the
    /// only way to tell "the listener is deaf" apart from "the audio is silent"
    /// without guessing.
    private func recordDiagnostic(keyHeard: Bool) {
        if keyHeard { keysHeard += 1 }
        let now = CFAbsoluteTimeGetCurrent()
        // Throttled: this runs on every keystroke, and typing shouldn't mean
        // writing a file hundreds of times a second.
        guard now - lastDiagnosticWrite > 2.0 else { return }
        lastDiagnosticWrite = now

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Klack")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "keysHeard": keysHeard,
            "tapEnabled": keyTap.isEnabled,
            "tapLive": keyTap.isLive,
            "permission": KeyTapManager.hasInputMonitoringPermission(),
            "accessibility": KeyTapManager.hasAccessibilityPermission(),
            "engineRunning": audioEngine?.health().engineRunning ?? false,
            "currentPack": audioEngine?.currentProfile ?? "none",
            "volume": volume,
            "softness": audioEngine?.softness ?? -1,
            "updated": ISO8601DateFormatter().string(from: Date()),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? data.write(to: dir.appendingPathComponent("diagnostic.json"))
        }
    }

    /// 0 while keystrokes are isolated, ramping to 1 as the average interval
    /// between them drops below the fast-typing threshold. The engine reads
    /// this as "how much of a run are we in" and softens accordingly.
    private func recordKeyDownAndComputeFlow() -> Float {
        let now = CFAbsoluteTimeGetCurrent()
        recentKeyDownTimes.append(now)
        if recentKeyDownTimes.count > speedWindowSize {
            recentKeyDownTimes.removeFirst(recentKeyDownTimes.count - speedWindowSize)
        }
        guard recentKeyDownTimes.count >= 3 else { return 1.0 }

        var intervals: [Double] = []
        for i in 1..<recentKeyDownTimes.count {
            intervals.append(recentKeyDownTimes[i] - recentKeyDownTimes[i - 1])
        }
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard avgInterval < fastTypingIntervalThreshold else { return 0 }

        let progress = (fastTypingIntervalThreshold - avgInterval) / (fastTypingIntervalThreshold - veryFastIntervalFloor)
        return Float(min(1.0, max(0.0, progress)))
    }

    /// One request per launch. `CGRequestListenEventAccess` only raises a
    /// prompt the first time for a given identity; calling it repeatedly from
    /// the permission poll would be pure noise.
    private var hasRequestedPermission = false

    /// Asks for the permissions in a way that the prompt can actually be seen.
    ///
    /// This is the bug that made Klack look like it simply refused to work.
    /// The app runs as an accessory (`LSUIElement`), so it has no Dock tile and
    /// no way to bring a window forward -- and the permission dialogs are
    /// presented *by our own process*. As an accessory it can raise them but
    /// not front them, so they open behind every other window, or never render.
    /// The request "succeeds", nothing is ever shown, and the only apparent
    /// route left is toggling the entry in System Settings by hand -- which
    /// silently fails whenever that entry is bound to a stale code identity.
    ///
    /// Becoming a regular app for a few seconds is what lets the dialog come to
    /// the front. The delay before reverting matters: switching straight back
    /// to accessory takes the dialog's front-most status with it.
    private func requestPermissionsVisibly() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Input Monitoring only. Asking for Accessibility as well looks like a
        // harmless second chance, but granting it flipped the old "either one
        // works" check to true and convinced the app it was fine -- a second
        // dialog that buys nothing and can actively mask the real failure.
        KeyTapManager.requestInputMonitoringPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func attemptStartTap() {
        // Gate on the capability itself, never on a permission flag that claims
        // to predict it. `tapCreate` is the only authority on whether we can
        // hear keys, and it disagrees with the flags: Accessibility trust reads
        // as granted while still refusing a keyboard tap, because listening to
        // keys needs Input Monitoring specifically.
        //
        // Trusting the flag is what wedged this app for weeks. Accessibility
        // came back true, the old check said "granted", and the app hid the
        // permission menu item and cancelled its own retry timer -- then sat
        // there convinced it was healthy while stone deaf, with every route to
        // recovery switched off. Asking the tap costs one syscall and cannot
        // lie.
        keyTap.start()
        if keyTap.isLive {
            permissionMenuItem.isHidden = true
            // Only now is there nothing left to poll for. This is a menu-bar
            // app that runs all day, so a permanent 3s wakeup is pure battery
            // cost -- but it has to be bought with a live tap, not a boolean.
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            return
        }

        // No tap means Input Monitoring is missing, whatever else is granted.
        permissionMenuItem.isHidden = false
        if !hasRequestedPermission {
            hasRequestedPermission = true
            // Checking never prompts -- only requesting does. Without this the
            // app launches silently denied and waits for the user to discover
            // a menu item, which is why the only route to a grant was toggling
            // the entry in System Settings by hand. That entry can be stale
            // while looking correct; a system prompt always binds to the
            // identity that is actually running.
            requestPermissionsVisibly()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        keyTap.stop()
    }

    // MARK: Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        packItems.removeAll()

        let showcaseItem = NSMenuItem(title: "Open Control Panel Window…", action: #selector(openShowcaseWindow), keyEquivalent: "")
        showcaseItem.target = self
        menu.addItem(showcaseItem)
        menu.addItem(.separator())

        enabledMenuItem.title = "Enabled"
        enabledMenuItem.state = keyTap.isEnabled ? .on : .off
        enabledMenuItem.action = #selector(toggleEnabled)
        enabledMenuItem.target = self
        menu.addItem(enabledMenuItem)

        let available = audioEngine?.availableProfiles ?? []
        let signature = ClickAudioEngine.signatureProfileNames.filter { available.contains($0) }
        let extra = ClickAudioEngine.extraProfileNames.filter { available.contains($0) }
        let recorded = available.filter { !ClickAudioEngine.builtInProfileNames.contains($0) }

        if !signature.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header("The 5 Signature Sounds"))
            for name in signature {
                addPackItem(name, to: menu)
            }
        }

        if !extra.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header("More Options"))
            for name in extra {
                addPackItem(name, to: menu)
            }
        }

        menu.addItem(.separator())
        menu.addItem(header("Sound Pack"))
        if recorded.isEmpty {
            let empty = NSMenuItem(title: "(none yet — waiting on recordings)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for name in recorded {
                addPackItem(name, to: menu)
            }
        }

        let testItem = NSMenuItem(title: "Reset & Test Klack…", action: #selector(testAndFix), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(.separator())
        menu.addItem(header("Volume"))
        let volItem = NSMenuItem()
        volumeView = SliderMenuItemView(title: "Volume", value: volume, min: 0, max: 1,
                                         formatter: { "\(Int($0 * 100))%" },
                                         target: self, action: #selector(volumeChanged(_:)))
        volItem.view = volumeView
        menu.addItem(volItem)

        let softItem = NSMenuItem()
        softnessView = SliderMenuItemView(title: "Softness", value: audioEngine?.softness ?? ClickAudioEngine.defaultSoftness,
                                          min: 0, max: 1,
                                          formatter: { "\(Int($0 * 100))%" },
                                          target: self, action: #selector(softnessChanged(_:)))
        softItem.view = softnessView
        menu.addItem(softItem)

        menu.addItem(.separator())
        menu.addItem(header("Design Your Own"))
        menu.addItem(buildMixerItem(title: "Pitch", value: mixerParams.pitch, min: 400, max: 3200,
                                     formatter: { "\(Int($0)) Hz" }, action: #selector(pitchChanged(_:))))
        menu.addItem(buildMixerItem(title: "Body / Thock", value: mixerParams.body, min: 0, max: 1,
                                     formatter: { "\(Int($0 * 100))%" }, action: #selector(bodyChanged(_:))))
        menu.addItem(buildMixerItem(title: "Brightness / Click", value: mixerParams.brightness, min: 0, max: 1,
                                     formatter: { "\(Int($0 * 100))%" }, action: #selector(brightnessChanged(_:))))
        menu.addItem(buildMixerItem(title: "Snappiness", value: mixerParams.snappiness, min: 0, max: 1,
                                     formatter: { "\(Int($0 * 100))%" }, action: #selector(snappinessChanged(_:))))
        menu.addItem(buildMixerItem(title: "Attack (mechanical bite)", value: mixerParams.attack, min: 0, max: 1,
                                     formatter: { "\(Int($0 * 100))%" }, action: #selector(attackChanged(_:))))
        menu.addItem(buildMixerItem(title: "Reverb", value: mixerParams.reverb, min: 0, max: 1,
                                     formatter: { "\(Int($0 * 100))%" }, action: #selector(reverbChanged(_:))))

        let previewItem = NSMenuItem(title: "Preview My Mix", action: #selector(previewMix), keyEquivalent: "p")
        previewItem.target = self
        menu.addItem(previewItem)

        let saveItem = NSMenuItem(title: "Save as My Sound", action: #selector(saveMix), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        menu.addItem(.separator())

        permissionMenuItem.title = "Grant Input Monitoring Access…"
        permissionMenuItem.action = #selector(openInputMonitoringSettings)
        permissionMenuItem.target = self
        permissionMenuItem.isHidden = true
        menu.addItem(permissionMenuItem)

        if #available(macOS 13.0, *) {
            let item = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            item.target = self
            item.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            launchAtLoginItem = item
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About Klack", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Klack", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openShowcaseWindow() {
        if showcaseWindowController == nil {
            showcaseWindowController = ShowcaseWindowController(audioEngine: audioEngine, keyTap: keyTap) { [weak self] in
                self?.showcaseWindowController = nil
            }
        }
        showcaseWindowController?.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Klack",
            .applicationVersion: "1.0",
            .credits: NSAttributedString(
                string: "A real-time mechanical keyboard sound engine.\nCustom DSP synthesis, live audio mixer, and recorded switch samples.\n\nBuilt with Claude.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func addPackItem(_ name: String, to menu: NSMenu) {
        let label = ClickAudioEngine.label(for: name)
        let item = NSMenuItem(title: label, action: #selector(selectPack(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = name
        item.state = (name == audioEngine?.currentProfile) ? .on : .off
        if let desc = ClickAudioEngine.profileDescriptions[name] {
            item.toolTip = desc
        }
        menu.addItem(item)
        packItems.append(item)
    }

    private func buildMixerItem(title: String, value: Float, min: Float, max: Float,
                                 formatter: @escaping (Float) -> String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SliderMenuItemView(title: title, value: value, min: min, max: max, formatter: formatter, target: self, action: action)
        return item
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        keyTap.isEnabled.toggle()
        enabledMenuItem.state = keyTap.isEnabled ? .on : .off
    }

    @objc private func selectPack(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        guard audioEngine?.switchProfile(to: name) == true else { return }
        for item in packItems {
            item.state = (item.representedObject as? String == name) ? .on : .off
        }
        audioEngine?.playKeyDown(isSpace: false)
    }

    /// One-button combo: reset both subsystems, play an actual sound, and
    /// verify the whole pipeline actually worked rather than assuming it
    /// did. Reports the true outcome instead of leaving it to be inferred
    /// from silence -- if the retry doesn't fix it either, says so plainly
    /// rather than pretending the reset button is a guarantee.
    @objc private func testAndFix() {
        showDiagnostic(text: "Resetting Klack…")
        keyTap.restart()
        audioEngine?.restartIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.verifyAfterReset(isRetry: false)
        }
    }

    private func verifyAfterReset(isRetry: Bool) {
        guard let engine = audioEngine else {
            finishDiagnostic(success: false, detail: "the sound engine didn't load at all")
            return
        }

        // Measure the signal actually leaving the mixer. Every status flag can
        // read healthy while the app emits pure silence -- that mismatch is
        // exactly what made this so hard to pin down -- so trust the waveform,
        // not the flags.
        let peak = engine.measureOutputPeak(seconds: 0.6) {
            engine.playKeyDown(isSpace: false)
            engine.playKeyDown(isSpace: true)
        }
        let health = engine.health()
        let permission = KeyTapManager.hasInputMonitoringPermission()

        if peak < 0.001 {
            if !isRetry {
                keyTap.restart()
                audioEngine?.restartIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.verifyAfterReset(isRetry: true)
                }
                return
            }
            finishDiagnostic(success: false,
                             detail: "the engine is emitting no signal at all (measured silence)")
            return
        }

        guard permission, keyTap.isLive, health.isHealthy else {
            if !isRetry {
                // One honest retry before reporting failure -- a single
                // transient hiccup shouldn't look like a broken app.
                keyTap.restart()
                audioEngine?.restartIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.verifyAfterReset(isRetry: true)
                }
                return
            }
            var reasons: [String] = []
            if !permission { reasons.append("Input Monitoring permission isn't granted") }
            else if !keyTap.isLive { reasons.append("the keyboard listener won't stay on") }
            reasons.append(contentsOf: health.problems)
            finishDiagnostic(success: false, detail: reasons.joined(separator: "; "))
            return
        }

        // Everything reports healthy -- but reporting healthy is exactly what
        // the broken state did too. Wait for a real keystroke as the proof.
        updateDiagnostic(text: "Audio confirmed (level \(String(format: "%.2f", peak))).\n\nIf you heard nothing, check which output device your Mac is using.\n\nNow press any key…")
        pendingKeystrokeProof = { [weak self] in
            self?.finishDiagnostic(success: true, detail: nil)
        }
        diagnosticTimeout?.invalidate()
        diagnosticTimeout = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self, self.pendingKeystrokeProof != nil else { return }
            self.pendingKeystrokeProof = nil
            self.finishDiagnostic(success: false,
                                  detail: "sound works, but keystrokes aren't reaching Klack")
        }
    }

    // MARK: Diagnostic panel

    private func showDiagnostic(text: String) {
        diagnosticPanel?.close()

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 130),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Klack"
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = NSRect(x: 20, y: 20, width: 280, height: 90)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13)
        panel.contentView?.addSubview(label)

        panel.center()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        diagnosticPanel = panel
        diagnosticLabel = label
    }

    private func updateDiagnostic(text: String) {
        diagnosticLabel?.stringValue = text
    }

    private func finishDiagnostic(success: Bool, detail: String?) {
        diagnosticTimeout?.invalidate()
        diagnosticTimeout = nil
        pendingKeystrokeProof = nil

        if success {
            updateDiagnostic(text: "✓ Working.\n\nSound and keyboard are both live.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.diagnosticPanel?.close()
                self?.diagnosticPanel = nil
            }
            return
        }

        diagnosticPanel?.close()
        diagnosticPanel = nil

        let needsPermission = !KeyTapManager.hasInputMonitoringPermission()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Still not working"
        alert.informativeText = "Reset didn't fix it — \(detail ?? "unknown issue")."
            + (needsPermission
               ? "\n\nKlack needs Input Monitoring access to hear your keyboard."
               : "\n\nQuitting and reopening Klack usually clears this.")
        if needsPermission { alert.addButton(withTitle: "Open Settings") }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn && needsPermission {
            openInputMonitoringSettings()
        }
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        volume = Float(sender.doubleValue)
        audioEngine?.volume = volume
        volumeView.refreshValueLabel()
    }

    @objc private func softnessChanged(_ sender: NSSlider) {
        audioEngine?.setSoftness(Float(sender.doubleValue))
        softnessView.refreshValueLabel()
    }

    @objc private func pitchChanged(_ sender: NSSlider) {
        mixerParams.pitch = Float(sender.doubleValue)
        (sender.superview as? SliderMenuItemView)?.refreshValueLabel()
        previewMix()
    }

    @objc private func bodyChanged(_ sender: NSSlider) {
        mixerParams.body = Float(sender.doubleValue)
        (sender.superview as? SliderMenuItemView)?.refreshValueLabel()
        previewMix()
    }

    @objc private func brightnessChanged(_ sender: NSSlider) {
        mixerParams.brightness = Float(sender.doubleValue)
        (sender.superview as? SliderMenuItemView)?.refreshValueLabel()
        previewMix()
    }

    @objc private func snappinessChanged(_ sender: NSSlider) {
        mixerParams.snappiness = Float(sender.doubleValue)
        (sender.superview as? SliderMenuItemView)?.refreshValueLabel()
        previewMix()
    }

    @objc private func attackChanged(_ sender: NSSlider) {
        mixerParams.attack = Float(sender.doubleValue)
        (sender.superview as? SliderMenuItemView)?.refreshValueLabel()
        previewMix()
    }

    @objc private func reverbChanged(_ sender: NSSlider) {
        mixerParams.reverb = Float(sender.doubleValue)
        (sender.superview as? SliderMenuItemView)?.refreshValueLabel()
        previewMix()
    }

    @objc private func previewMix() {
        let samples = SoundSynth.render(params: mixerParams, durationMs: 70, seed: 42)
        audioEngine?.previewSamples(samples)
    }

    @objc private func saveMix() {
        guard audioEngine?.saveCustomProfile(params: mixerParams) == true else { return }
        statusItem.menu = buildMenu()
    }

    @objc private func openInputMonitoringSettings() {
        KeyTapManager.requestInputMonitoringPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @available(macOS 13.0, *)
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Klack: failed to toggle launch at login: \(error)")
        }
        launchAtLoginItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
