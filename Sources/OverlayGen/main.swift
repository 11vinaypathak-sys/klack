import Cocoa
import KlackBrand

// Renders the three lower-third overlays for the Klack film, one per cut.
//
// Generated in code rather than by an image model for two reasons: real alpha
// (image generators fake transparency by drawing a checkerboard), and exact
// brand colour -- these have to be the same lime as the app icon and the
// control panel, not an approximation of it.
//
// Output is 1080x1920 (9:16) with a transparent background, so each drops
// straight onto the footage with no keying or blend-mode trickery.

let W: CGFloat = 1080
let H: CGFloat = 1920
let lime = KlackBrand.lime

func label(_ text: String, size: CGFloat, tracking: CGFloat, alpha: CGFloat = 1) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .heavy),
        .kern: tracking,
        .foregroundColor: lime.withAlphaComponent(alpha),
    ])
}

/// A short rule above the text. Gives each overlay a consistent anchor so the
/// three read as one system when they cut against each other.
func drawRule(atY y: CGFloat, width: CGFloat, x: CGFloat) {
    let r = NSBezierPath(rect: NSRect(x: x, y: y, width: width, height: 4))
    lime.setFill()
    r.fill()
}

func strike(from a: NSPoint, to b: NSPoint, width: CGFloat) {
    let p = NSBezierPath()
    p.move(to: a)
    p.line(to: b)
    p.lineWidth = width
    p.lineCapStyle = .round
    lime.setStroke()
    p.stroke()
}

/// Overlay 1 -- the Klack mark itself, establishing the brand early.
func overlayOne() -> NSImage {
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    let x: CGFloat = 110
    KlackBrand.draw(in: NSRect(x: x, y: 620, width: 96, height: 96))
    drawRule(atY: 596, width: 64, x: x)
    label("PERSONAL SOFTWARE", size: 54, tracking: 4)
        .draw(at: NSPoint(x: x, y: 516))
    label("built for exactly one person", size: 30, tracking: 1, alpha: 0.62)
        .draw(at: NSPoint(x: x, y: 466))
    img.unlockFocus()
    return img
}

/// Overlay 2 -- a struck-through bar chart. The rejection is the message, so
/// the icon has to be something instantly readable as "dashboard".
func overlayTwo() -> NSImage {
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    let x: CGFloat = 110

    // Bars of descending height read as a chart at a glance.
    let heights: [CGFloat] = [56, 88, 40, 72]
    var bx = x
    for h in heights {
        let bar = NSBezierPath(roundedRect: NSRect(x: bx, y: 620, width: 20, height: h),
                               xRadius: 10, yRadius: 10)
        lime.withAlphaComponent(0.55).setFill()
        bar.fill()
        bx += 30
    }
    // Diagonal strike, drawn past the icon on both sides so it reads as a
    // cancellation rather than part of the graphic.
    strike(from: NSPoint(x: x - 16, y: 606), to: NSPoint(x: bx + 4, y: 726), width: 8)

    drawRule(atY: 566, width: 64, x: x)
    label("NOT ANOTHER TRACKER", size: 54, tracking: 4)
        .draw(at: NSPoint(x: x, y: 486))
    label("no dashboards. no charts.", size: 30, tracking: 1, alpha: 0.62)
        .draw(at: NSPoint(x: x, y: 436))
    img.unlockFocus()
    return img
}

/// Overlay 3 -- the kicker. Price struck out, replaced by the real point.
func overlayThree() -> NSImage {
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    let x: CGFloat = 110

    let paid = label("PAID APP", size: 54, tracking: 4, alpha: 0.42)
    paid.draw(at: NSPoint(x: x, y: 620))
    let paidW = paid.size().width
    strike(from: NSPoint(x: x - 8, y: 648), to: NSPoint(x: x + paidW + 8, y: 648), width: 6)

    // Arrow down to the replacement, so the substitution is explicit.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: x + 14, y: 606))
    arrow.line(to: NSPoint(x: x + 14, y: 566))
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    lime.setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: x, y: 578))
    head.line(to: NSPoint(x: x + 14, y: 560))
    head.line(to: NSPoint(x: x + 28, y: 578))
    head.lineWidth = 6
    head.lineJoinStyle = .round
    head.lineCapStyle = .round
    lime.setStroke()
    head.stroke()

    label("BUILT IT FREE", size: 64, tracking: 4)
        .draw(at: NSPoint(x: x, y: 470))
    label("with Claude, over a weekend", size: 30, tracking: 1, alpha: 0.62)
        .draw(at: NSPoint(x: x, y: 420))
    img.unlockFocus()
    return img
}

let outputs: [(String, NSImage)] = [
    ("overlay-1-personal.png", overlayOne()),
    ("overlay-2-not-a-tracker.png", overlayTwo()),
    ("overlay-3-built-free.png", overlayThree()),
]

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for (name, image) in outputs {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    print("wrote \(name)")
}
