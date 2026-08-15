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

    // Fast-typing reward: track recent keydown timing, give a small volume
    // boost once you're typing fast enough, scaling up the faster you go.
    private var recentKeyDownTimes: [CFAbsoluteTime] = []
    private let speedWindowSize = 6
    private let fastTypingIntervalThreshold: Double = 0.18 // seconds between keys
    private let veryFastIntervalFloor: Double = 0.08
    private let maxSpeedBoost: Float = 0.3 // up to +30% volume at max speed

    private let permissionMenuItem = NSMenuItem()
    private let enabledMenuItem = NSMenuItem()
    private var launchAtLoginItem: NSMenuItem?
    private var packItems: [NSMenuItem] = []
    private var volumeView: SliderMenuItemView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupAudioEngine()
        setupKeyTapHandlers()
        setupStatusItem()
        attemptStartTap()

        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.attemptStartTap()
        }
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
            let boost = self.recordKeyDownAndComputeSpeedBoost()
            self.audioEngine?.playKeyDown(isSpace: isSpace, gainMultiplier: boost)
            NotificationCenter.default.post(name: .klackKeystroke, object: nil,
                                            userInfo: ["boost": boost, "isSpace": isSpace])
        }
        keyTap.onKeyUp = { [weak self] isSpace in
            self?.audioEngine?.playKeyUp(isSpace: isSpace)
        }
        keyTap.isEnabled = true
    }

    /// Returns 1.0 for normal typing, ramping up toward 1.0 + maxSpeedBoost
    /// as your average interval between keystrokes drops below the fast-
    /// typing threshold -- a small "reward" for typing quickly.
    private func recordKeyDownAndComputeSpeedBoost() -> Float {
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
        guard avgInterval < fastTypingIntervalThreshold else { return 1.0 }

        let progress = (fastTypingIntervalThreshold - avgInterval) / (fastTypingIntervalThreshold - veryFastIntervalFloor)
        let clamped = min(1.0, max(0.0, progress))
        return 1.0 + Float(clamped) * maxSpeedBoost
    }

    private func attemptStartTap() {
        let granted = KeyTapManager.hasInputMonitoringPermission()
        if granted {
            keyTap.start()
            permissionMenuItem.isHidden = true
            // Once the tap is live there's nothing left to poll for — this is
            // a menu-bar app that runs all day, so a permanent 3s wakeup is
            // pure battery cost.
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        } else {
            permissionMenuItem.isHidden = false
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

        let testItem = NSMenuItem(title: "Play Test Sound", action: #selector(playTest), keyEquivalent: "t")
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
        playTest()
    }

    @objc private func playTest() {
        audioEngine?.playKeyDown(isSpace: false)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        volume = Float(sender.doubleValue)
        audioEngine?.volume = volume
        volumeView.refreshValueLabel()
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
