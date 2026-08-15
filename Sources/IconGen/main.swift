import Cocoa

// One-off tool: renders Klack's app icon as a 1024x1024 PNG using a colored
// squircle background + Apple's own SF Symbol artwork (safe/consistent,
// since it's system-provided vector art rather than freehand shapes).

let size = 1024.0
let canvas = NSImage(size: NSSize(width: size, height: size))

canvas.lockFocus()

// Background: dark charcoal squircle with a subtle diagonal gradient for depth.
let backgroundRect = NSRect(x: 0, y: 0, width: size, height: size)
let cornerRadius = size * 0.225 // matches macOS Big Sur+ icon corner convention
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius)

let topColor = NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1.0)
let bottomColor = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1.0)
let gradient = NSGradient(starting: topColor, ending: bottomColor)
gradient?.draw(in: backgroundPath, angle: -90)

// Foreground: a large keyboard glyph, tinted a bright mint/lime accent.
let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) {
    let accent = NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.55, alpha: 1.0)
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    accent.set()
    let imageRect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: imageRect)
    imageRect.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let symbolSize = tinted.size
    let symbolOrigin = NSPoint(x: (size - symbolSize.width) / 2, y: (size - symbolSize.height) / 2 - size * 0.02)
    tinted.draw(at: symbolOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)
}

canvas.unlockFocus()

guard let tiffData = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to render icon")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try? pngData.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
