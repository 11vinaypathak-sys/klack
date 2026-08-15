import Cocoa

// Skinned "hardware faceplate" chrome for Klack's control panel.
// Geometry and colours mirror the Figma reference 1:1 — all these views use
// `isFlipped = true` so their coordinates match Figma's top-left origin
// directly, which keeps the port honest and easy to re-check.

extension NSBezierPath {
    /// `NSBezierPath.cgPath` is macOS 14+, but Klack targets 12 — convert by
    /// walking the elements so the inner-shadow routine works everywhere.
    var compatCGPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }
        return path
    }
}

enum Skin {
    static let panelWidth: CGFloat = 460
    static let panelHeight: CGFloat = 460
    static let titleBarHeight: CGFloat = 28

    static let panelTop = NSColor(calibratedRed: 0.58, green: 0.62, blue: 0.68, alpha: 1)
    static let panelBottom = NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.26, alpha: 1)
    static let titleTop = NSColor(calibratedWhite: 0.38, alpha: 1)
    static let titleBottom = NSColor(calibratedWhite: 0.14, alpha: 1)
    static let wellTop = NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.29, alpha: 1)
    static let wellBottom = NSColor(calibratedRed: 0.34, green: 0.36, blue: 0.40, alpha: 1)
    static let lcdBackground = NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.04, alpha: 1)
    static let lcdGlow = NSColor(calibratedRed: 0.55, green: 1.0, blue: 0.75, alpha: 1)
    static let accentTop = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1)
    static let accentBottom = NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.32, alpha: 1)
    static let chromeTop = NSColor(calibratedRed: 0.50, green: 0.52, blue: 0.56, alpha: 1)
    static let chromeBottom = NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.34, alpha: 1)
    static let capTop = NSColor(calibratedRed: 0.85, green: 0.87, blue: 0.90, alpha: 1)
    static let capBottom = NSColor(calibratedRed: 0.50, green: 0.52, blue: 0.56, alpha: 1)

    /// AppKit has no inner-shadow primitive. The correct trick is to clip to
    /// the shape, then fill it with `.sourceOut` inside a transparency layer —
    /// the shadow of the *inverted* shape then lands inside the path. Both
    /// nested layers are required: the outer applies alpha uniformly, the
    /// inner gives `.sourceOut` a defined backdrop.
    static func drawInnerShadow(in path: NSBezierPath, offset: NSSize, blur: CGFloat, alpha: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.addPath(path.compatCGPath)
        ctx.clip()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let opaque = NSColor.black.cgColor
        ctx.setShadow(offset: offset, blur: blur, color: opaque)
        ctx.setBlendMode(.sourceOut)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(opaque)
        ctx.addPath(path.compatCGPath)
        ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// DSEG7 Classic (SIL OFL) gives a true seven-segment readout. Registered
    /// once from the bundle; falls back to a monospace face if unavailable.
    private static var didRegisterFonts = false
    static func registerBundledFonts() {
        guard !didRegisterFonts else { return }
        didRegisterFonts = true
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func segmentFont(size: CGFloat) -> NSFont {
        registerBundledFonts()
        return NSFont(name: "DSEG7 Classic", size: size)
            ?? NSFont(name: "DSEG7Classic-Bold", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }

    static func fillGradient(_ rect: NSRect, radius: CGFloat, top: NSColor, bottom: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)
    }
}

/// The main faceplate: brushed-metal body, title bar, bevel edge, and the
/// four corner screws that sell the "real hardware panel" read.
final class FaceplateView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSGradient(starting: Skin.panelTop, ending: Skin.panelBottom)?.draw(in: body, angle: -90)

        // Brushed-metal grain. Three striation layers whose periods (3/5/7)
        // share no common factor, so the visible pattern only repeats at their
        // LCM — it reads as random brushing without generating actual noise.
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        for (period, white, alpha) in [(3.0, true, 0.030), (5.0, false, 0.028), (7.0, true, 0.020)] {
            let color = white ? NSColor(calibratedWhite: 1, alpha: alpha)
                              : NSColor(calibratedWhite: 0, alpha: alpha)
            color.setFill()
            for y in stride(from: 0.0, to: bounds.height, by: period) {
                NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
            }
        }
        // Specular sweep across the upper third, where a real panel catches light.
        let sweep = NSRect(x: 0, y: bounds.height * 0.18, width: bounds.width, height: bounds.height * 0.28)
        NSGradient(colors: [NSColor(calibratedWhite: 1, alpha: 0.0),
                            NSColor(calibratedWhite: 1, alpha: 0.06),
                            NSColor(calibratedWhite: 1, alpha: 0.0)])?.draw(in: sweep, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Title bar.
        let titleRect = NSRect(x: 0, y: 0, width: bounds.width, height: Skin.titleBarHeight)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).addClip()
        NSGradient(starting: Skin.titleTop, ending: Skin.titleBottom)?.draw(in: titleRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Wordmark.
        let title = NSAttributedString(string: "K L A C K", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1),
        ])
        title.draw(at: NSPoint(x: 12, y: 7))

        // Bevel highlight where the faceplate catches light under the title bar.
        NSColor(calibratedWhite: 1, alpha: 0.28).setFill()
        NSRect(x: 1, y: Skin.titleBarHeight, width: bounds.width - 2, height: 1).fill()

        // Outer edge.
        NSColor(calibratedWhite: 0.05, alpha: 1).setStroke()
        body.lineWidth = 1
        body.stroke()

        for (sx, sy) in [(8.0, 56.0), (452.0, 56.0), (8.0, 440.0), (452.0, 440.0)] {
            drawScrew(at: NSPoint(x: sx, y: sy))
        }
    }

    private func drawScrew(at center: NSPoint) {
        let r: CGFloat = 4.5
        let rect = NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let head = NSBezierPath(ovalIn: rect)
        NSGradient(starting: NSColor(calibratedWhite: 0.56, alpha: 1),
                   ending: NSColor(calibratedWhite: 0.22, alpha: 1))?.draw(in: head, angle: -45)
        NSColor(calibratedWhite: 0, alpha: 0.5).setStroke()
        head.lineWidth = 0.5
        head.stroke()

        // Slot, rotated so the screws don't all look machine-identical.
        NSGraphicsContext.saveGraphicsState()
        let xform = NSAffineTransform()
        xform.translateX(by: center.x, yBy: center.y)
        xform.rotate(byDegrees: -35)
        xform.concat()
        NSColor(calibratedWhite: 0.08, alpha: 0.8).setFill()
        NSRect(x: -3, y: -0.6, width: 6, height: 1.2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Recessed well the faders sit inside — inverted bevel plus inner shadow so
/// it reads as machined *into* the faceplate rather than sitting on top.
final class RecessedWellView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSGradient(starting: Skin.wellTop, ending: Skin.wellBottom)?.draw(in: path, angle: -90)
        Skin.drawInnerShadow(in: path, offset: NSSize(width: 0, height: 2), blur: 4, alpha: 0.55)
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Sunken LCD readout. Three details do the heavy lifting for authenticity:
/// unlit "ghost" segments behind the live value, a scanline + RGB subpixel
/// mask, and chromatic aberration on the glow.
final class LCDView: NSView {
    override var isFlipped: Bool { true }

    /// Label shown in the small mono field (e.g. the sound pack name).
    var label: String = "" { didSet { needsDisplay = true } }
    /// Numeric value shown on the seven-segment display.
    var segmentValue: String = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        Skin.lcdBackground.setFill()
        path.fill()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // --- Seven-segment field (right side) ---
        let segFont = Skin.segmentFont(size: 17)
        let segX = bounds.width - 96.0

        // Ghost segments: DSEG renders "88" as every segment lit, so drawing
        // it faintly behind the value shows the unlit segments of a real LCD.
        NSAttributedString(string: "888", attributes: [
            .font: segFont,
            .foregroundColor: Skin.lcdGlow.withAlphaComponent(0.10),
        ]).draw(at: NSPoint(x: segX, y: 7))

        let segGlow = NSShadow()
        segGlow.shadowColor = Skin.lcdGlow.withAlphaComponent(0.9)
        segGlow.shadowOffset = .zero
        segGlow.shadowBlurRadius = 5
        NSAttributedString(string: segmentValue, attributes: [
            .font: segFont,
            .foregroundColor: Skin.lcdGlow,
            .shadow: segGlow,
        ]).draw(at: NSPoint(x: segX, y: 7))

        // --- Mono label field (left side) ---
        // Chromatic aberration: the same text offset a fraction of a pixel in
        // blue and red under the main glyphs, which is what a real phosphor
        // display's colour fringing looks like.
        let labelFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let origin = NSPoint(x: 10, y: 9)
        for (dx, color) in [(-0.5, NSColor(calibratedRed: 1, green: 0, blue: 0.3, alpha: 0.35)),
                            (0.5, NSColor(calibratedRed: 0, green: 0.2, blue: 1, alpha: 0.45))] {
            NSAttributedString(string: label, attributes: [
                .font: labelFont, .foregroundColor: color, .kern: 1.6,
            ]).draw(at: NSPoint(x: origin.x + dx, y: origin.y))
        }
        let glow = NSShadow()
        glow.shadowColor = Skin.lcdGlow.withAlphaComponent(0.8)
        glow.shadowOffset = .zero
        glow.shadowBlurRadius = 5
        NSAttributedString(string: label, attributes: [
            .font: labelFont, .foregroundColor: Skin.lcdGlow, .shadow: glow, .kern: 1.6,
        ]).draw(at: origin)

        // --- Display mask ---
        // Horizontal scanlines on a 2px period.
        NSColor(calibratedWhite: 0, alpha: 0.25).setFill()
        for y in stride(from: 0.0, to: bounds.height, by: 2) {
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
        }
        // Vertical RGB subpixel mask on a 3px period. Green gets the lowest
        // alpha because the eye is most sensitive to it.
        for (i, alpha) in [(0, 0.06), (1, 0.02), (2, 0.06)] {
            NSColor(calibratedWhite: 0, alpha: alpha).setFill()
            for x in stride(from: CGFloat(i), to: bounds.width, by: 3) {
                NSRect(x: x, y: 0, width: 1, height: bounds.height).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        Skin.drawInnerShadow(in: path, offset: NSSize(width: 0, height: 2), blur: 3, alpha: 0.6)
    }
}

/// Vertical fader. Subclassing NSSliderCell keeps AppKit's hit-testing and
/// drag handling (which is the reliable part) while letting us draw the
/// recessed track, tick ladder, and grip-lined cap ourselves.
final class FaderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard let view = controlView else { return }
        let cx = view.bounds.midX
        let top: CGFloat = 6
        let height = view.bounds.height - 12

        let track = NSRect(x: cx - 4, y: top, width: 8, height: height)
        let path = NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3)
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        path.fill()
        Skin.drawInnerShadow(in: path, offset: NSSize(width: 0, height: 1), blur: 2, alpha: 0.7)

        // Tick ladder either side of the track.
        for t in 0...8 {
            let y = top + height * (CGFloat(t) / 8)
            let major = (t % 4 == 0)
            let len: CGFloat = major ? 8 : 5
            NSColor(calibratedWhite: 1, alpha: major ? 0.35 : 0.18).setFill()
            NSRect(x: cx + 8, y: y, width: len, height: 1).fill()
            NSRect(x: cx - 8 - len, y: y, width: len, height: 1).fill()
        }
    }

    override func drawKnob(_ knobRect: NSRect) {
        guard let view = controlView else { return }
        let cap = NSRect(x: view.bounds.midX - 11, y: knobRect.midY - 6, width: 22, height: 12)
        let path = NSBezierPath(roundedRect: cap, xRadius: 3, yRadius: 3)
        NSGradient(starting: Skin.capTop, ending: Skin.capBottom)?.draw(in: path, angle: -90)
        NSColor(calibratedWhite: 0.1, alpha: 1).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        // Grip line across the cap.
        NSColor(calibratedWhite: 0.15, alpha: 0.85).setFill()
        NSRect(x: cap.minX + 3, y: cap.midY - 0.5, width: 16, height: 1).fill()
    }
}

/// Horizontal volume slider in the same chrome language.
final class VolumeCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard let view = controlView else { return }
        let track = NSRect(x: 0, y: view.bounds.midY - 3, width: view.bounds.width, height: 6)
        let path = NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3)
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        path.fill()
        Skin.drawInnerShadow(in: path, offset: NSSize(width: 0, height: 1), blur: 2, alpha: 0.6)
    }

    override func drawKnob(_ knobRect: NSRect) {
        let d: CGFloat = 14
        let rect = NSRect(x: knobRect.midX - d / 2, y: knobRect.midY - d / 2, width: d, height: d)
        let path = NSBezierPath(ovalIn: rect)
        NSGradient(starting: NSColor(calibratedWhite: 0.9, alpha: 1),
                   ending: NSColor(calibratedWhite: 0.55, alpha: 1))?.draw(in: path, angle: -90)
        NSColor(calibratedWhite: 0.1, alpha: 1).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

/// Beveled metal button. `isAccent` switches it to the green "active" chrome
/// used for the selected sound pack and the primary action.
final class MetalButton: NSButton {
    var isAccent = false { didSet { needsDisplay = true } }
    var isSelectedPack = false { didSet { needsDisplay = true } }
    private var pressed = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        let useAccent = isAccent || isSelectedPack
        var top = useAccent ? Skin.accentTop : Skin.chromeTop
        var bottom = useAccent ? Skin.accentBottom : Skin.chromeBottom
        if pressed {
            swap(&top, &bottom)
        }
        NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)

        NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 5, y: 1))
        highlight.line(to: NSPoint(x: bounds.width - 5, y: 1))
        highlight.lineWidth = 1
        highlight.stroke()

        NSColor(calibratedWhite: 0, alpha: 0.55).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let label = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = label.size()
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        needsDisplay = true
    }
}

/// Pill toggle for the Enabled switch.
final class PillToggle: NSButton {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let on = (state == .on)
        let track = NSRect(x: 0, y: 0, width: 34, height: 16)
        let path = NSBezierPath(roundedRect: track, xRadius: 8, yRadius: 8)
        (on ? NSColor(calibratedRed: 0.35, green: 0.75, blue: 0.45, alpha: 1)
            : NSColor(calibratedWhite: 0.3, alpha: 1)).setFill()
        path.fill()
        Skin.drawInnerShadow(in: path, offset: NSSize(width: 0, height: 1), blur: 2, alpha: 0.4)

        let knobX: CGFloat = on ? 20 : 2
        let knob = NSBezierPath(ovalIn: NSRect(x: knobX, y: 2, width: 12, height: 12))
        NSColor.white.setFill()
        knob.fill()
    }
}
