import Cocoa
import KlackBrand

// Renders the app icon by stamping the shared brand mark onto a macOS tile.
//
// The mark itself lives in KlackBrand so the icon and the in-app panel are the
// same artwork rather than two drawings that happen to look alike.

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))

canvas.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let corner = size * 0.225 // macOS Big Sur+ corner convention
NSGraphicsContext.current?.saveGraphicsState()
NSBezierPath(roundedRect: bgRect, xRadius: corner, yRadius: corner).addClip()

KlackBrand.charcoal.setFill()
bgRect.fill()

// 0.56 leaves the tile breathing room on all sides; filling more makes the
// icon feel cramped next to Apple's own, which sit well inside their tiles.
KlackBrand.draw(in: NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.22, dy: size * 0.22))

NSGraphicsContext.current?.restoreGraphicsState()
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to render icon")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try? png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
