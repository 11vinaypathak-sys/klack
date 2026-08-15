import Cocoa

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
    controller.simulateActivityForRender()

    guard let view = controller.window?.contentView else { exit(1) }
    view.layoutSubtreeIfNeeded()

    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? data.write(to: URL(fileURLWithPath: outPath))
    print("rendered \(Int(view.bounds.width))x\(Int(view.bounds.height)) -> \(outPath)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
