import Cocoa

// V2 skin: dark chassis + glossy white plastic plate + backlit amber display.
// All views are `isFlipped` so coordinates match the Figma reference directly.

enum Plastic {
    // White plastic is never neutral grey — the body runs cool at the
    // highlight and warm in shadow, which is what separates moulded plastic
    // from flat grey fill.
    static let bodyTop = NSColor(srgbRed: 0.969, green: 0.973, blue: 0.980, alpha: 1)
    static let bodyMid = NSColor(srgbRed: 0.910, green: 0.902, blue: 0.882, alpha: 1)
    static let bodyBottom = NSColor(srgbRed: 0.847, green: 0.831, blue: 0.800, alpha: 1)
    static let bounceLight = NSColor(srgbRed: 1.0, green: 0.965, blue: 0.910, alpha: 1)

    // Chassis runs darker than the Figma draft — the plate needs something
    // genuinely dark to sit against or the whole thing reads washed out.
    static let chassisTop = NSColor(srgbRed: 0.23, green: 0.27, blue: 0.35, alpha: 1)
    static let chassisMid = NSColor(srgbRed: 0.13, green: 0.16, blue: 0.22, alpha: 1)
    static let chassisBottom = NSColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 1)

    static let amberCore = NSColor(srgbRed: 1.0, green: 0.72, blue: 0.30, alpha: 1)
    static let amberMid = NSColor(srgbRed: 0.94, green: 0.60, blue: 0.17, alpha: 1)
    static let amberEdge = NSColor(srgbRed: 0.54, green: 0.29, blue: 0.06, alpha: 1)
    static let displayInk = NSColor(srgbRed: 0.26, green: 0.13, blue: 0.01, alpha: 1)

    /// Tiled grain, generated once. Kept under 5% alpha — more reads as dirt.
    static let noiseTile: CGImage? = {
        let side = 64
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(side * side) {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            let v = UInt8(truncatingIfNeeded: seed >> 24)
            let a = UInt8(10)
            buf[i * 4 + 0] = v; buf[i * 4 + 1] = v; buf[i * 4 + 2] = v; buf[i * 4 + 3] = a
        }
        return ctx.makeImage()
    }()

    static func gradient(_ stops: [(CGFloat, NSColor)]) -> NSGradient? {
        NSGradient(colors: stops.map { $0.1 }, atLocations: stops.map { $0.0 }, colorSpace: .sRGB)
    }
}

/// Plain container that uses top-left origin, matching every other view in
/// this skin. Without it a container's children lay out bottom-up while its
/// own frame is positioned top-down, which silently inverts the contents.
final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

/// Dark outer chassis with a soft-touch grain.
final class ChassisView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 26, yRadius: 26)
        Plastic.gradient([(0, Plastic.chassisTop), (0.5, Plastic.chassisMid), (1, Plastic.chassisBottom)])?
            .draw(in: path, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // Soft-touch grain, so the dark areas aren't dead flat.
        if let noise = Plastic.noiseTile, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setAlpha(0.5)
            ctx.setBlendMode(.overlay)
            ctx.draw(noise, in: NSRect(x: 0, y: 0, width: 64, height: 64), byTiling: true)
            ctx.restoreGState()
        }

        // Cool sheen down the upper left, warm bounce along the bottom — the
        // temperature split keeps a near-black surface from going muddy.
        Plastic.gradient([
            (0, NSColor(srgbRed: 0.55, green: 0.68, blue: 0.85, alpha: 0.10)),
            (0.4, NSColor(white: 1, alpha: 0.0)),
        ])?.draw(in: bounds, angle: -60)

        let lip = NSRect(x: 0, y: bounds.height - 40, width: bounds.width, height: 40)
        Plastic.gradient([
            (0, NSColor(white: 1, alpha: 0)),
            (1, NSColor(srgbRed: 1.0, green: 0.82, blue: 0.60, alpha: 0.07)),
        ])?.draw(in: lip, angle: -90)

        // Crisp top edge highlight, dark bottom edge.
        NSColor(white: 1, alpha: 0.22).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        NSColor(white: 0, alpha: 0.55).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Live activity trace across the display — reacts to real keystrokes, so the
/// panel reads as an instrument that's actually monitoring something.
final class WaveformView: NSView {
    override var isFlipped: Bool { true }

    private var samples = [CGFloat](repeating: 0, count: 64)
    private var decayTimer: Timer?

    var inkColor = Plastic.displayInk

    /// Push a new hit. `intensity` is the fast-typing boost, so typing harder
    /// visibly drives the trace higher.
    func pulse(intensity: CGFloat) {
        samples.removeFirst()
        samples.append(min(1.0, max(0.15, intensity)))
        needsDisplay = true
        startDecayIfNeeded()
    }

    private func startDecayIfNeeded() {
        guard decayTimer == nil else { return }
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            var anyEnergy = false
            // Scroll left and bleed off, so the trace drifts back to flat.
            self.samples.removeFirst()
            self.samples.append(0)
            for i in 0..<self.samples.count {
                self.samples[i] *= 0.90
                if self.samples[i] > 0.01 { anyEnergy = true }
            }
            self.needsDisplay = true
            if !anyEnergy {
                t.invalidate()
                self.decayTimer = nil
            }
        }
    }

    deinit { decayTimer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        let barW = bounds.width / CGFloat(samples.count)

        // Baseline.
        inkColor.withAlphaComponent(0.18).setFill()
        NSRect(x: 0, y: midY - 0.5, width: bounds.width, height: 1).fill()

        for (i, s) in samples.enumerated() {
            guard s > 0.01 else { continue }
            let h = s * bounds.height * 0.46
            let x = CGFloat(i) * barW
            // Newer samples (to the right) sit at higher opacity.
            let recency = 0.35 + 0.65 * (CGFloat(i) / CGFloat(samples.count))
            inkColor.withAlphaComponent(0.75 * recency).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + barW * 0.22, y: midY - h,
                                             width: max(1.5, barW * 0.56), height: h * 2),
                         xRadius: 1, yRadius: 1).fill()
        }
    }
}

/// Glossy white plastic plate. The gloss is a hard terminator, not a soft
/// airbrush — that near-zero-width step at the midpoint is what reads as a
/// lacquered surface.
final class PlasticPlateView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 30, yRadius: 30)

        Plastic.gradient([(0, Plastic.bodyTop), (0.55, Plastic.bodyMid), (1, Plastic.bodyBottom)])?
            .draw(in: path, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // (a) Broad top sweep.
        Plastic.gradient([
            (0.00, NSColor(white: 1, alpha: 0.85)),
            (0.08, NSColor(white: 1, alpha: 0.62)),
            (0.45, NSColor(white: 1, alpha: 0.10)),
            (1.00, NSColor(white: 1, alpha: 0.0)),
        ])?.draw(in: bounds, angle: -90)

        // (b) Hard-edged gloss band across the upper 48%.
        let band = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.48)
        Plastic.gradient([
            (0.0000, NSColor(white: 1, alpha: 0.60)),
            (0.5000, NSColor(white: 1, alpha: 0.30)),
            (0.5001, NSColor(white: 1, alpha: 0.0)),
            (1.0000, NSColor(white: 1, alpha: 0.18)),
        ])?.draw(in: band, angle: -90)

        // (c) Warm bounce light along the bottom lip.
        let lip = NSRect(x: 0, y: bounds.height * 0.86, width: bounds.width, height: bounds.height * 0.14)
        Plastic.gradient([
            (0, NSColor(white: 1, alpha: 0)),
            (1, Plastic.bounceLight.withAlphaComponent(0.55)),
        ])?.draw(in: lip, angle: -90)

        NSGraphicsContext.restoreGraphicsState()

        // Moulded edges.
        let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 29.5, yRadius: 29.5)
        NSColor(white: 1, alpha: 0.9).setStroke()
        inner.lineWidth = 1
        inner.stroke()
    }
}

/// Backlit amber display. Four cues make it read as lit rather than filled:
/// an off-centre bloom, a *tighter* vignette, a light leak at the bezel, and
/// a faint grain over the top.
final class BacklitDisplayView: NSView {
    override var isFlipped: Bool { true }

    var flags: [(String, Bool)] = []
    var volumeFraction: CGFloat = 0.8
    var bigValue: String = "80"
    var packName: String = ""
    /// Brief lift in backlight brightness on each keystroke.
    var backlightBoost: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 15, yRadius: 15)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // (i) Bloom — light source sits behind and slightly above centre.
        // The boost lifts the whole backlight momentarily as you type.
        let b = min(0.18, backlightBoost)
        let centre = NSPoint(x: bounds.midX, y: bounds.height * 0.40)
        let radius = max(bounds.width, bounds.height) * 0.78
        Plastic.gradient([
            (0.00, NSColor(srgbRed: min(1, 1.0 + b), green: min(1, 0.72 + b), blue: min(1, 0.30 + b * 1.4), alpha: 1)),
            (0.45, NSColor(srgbRed: min(1, 0.94 + b), green: min(1, 0.60 + b), blue: min(1, 0.17 + b), alpha: 1)),
            (0.80, NSColor(srgbRed: 0.77 + b * 0.5, green: 0.44 + b * 0.5, blue: 0.10, alpha: 1)),
            (1.00, NSColor(srgbRed: 0.50 + b * 0.4, green: 0.26 + b * 0.3, blue: 0.05, alpha: 1)),
        ])?.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: radius, options: [])

        // (ii) Vignette, deliberately tighter than the bloom — the radius
        // mismatch is what creates depth behind the glass.
        Plastic.gradient([
            (0.0, NSColor(white: 0, alpha: 0)),
            (0.7, NSColor(white: 0, alpha: 0)),
            (1.0, NSColor(white: 0, alpha: 0.45)),
        ])?.draw(fromCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: 0,
                 toCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: bounds.width * 0.62, options: [])

        drawContent()

        // (iv) Grain.
        if let noise = Plastic.noiseTile, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setBlendMode(.overlay)
            ctx.draw(noise, in: NSRect(x: 0, y: 0, width: 64, height: 64), byTiling: true)
            ctx.restoreGState()
        }

        // (iii) Light leak at the bezel — stroked at widening radii with
        // falling alpha, since Core Graphics can't feather a stroke.
        for (w, a) in [(1.0, 0.35), (2.0, 0.22), (3.0, 0.12), (4.0, 0.06)] {
            let leak = NSBezierPath(roundedRect: bounds.insetBy(dx: w / 2, dy: w / 2),
                                    xRadius: 15 - w / 2, yRadius: 15 - w / 2)
            NSColor(srgbRed: 1.0, green: 0.85, blue: 0.63, alpha: CGFloat(a)).setStroke()
            leak.lineWidth = CGFloat(w)
            leak.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawContent() {
        let ink = Plastic.displayInk

        for (i, flag) in flags.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: ink.withAlphaComponent(flag.1 ? 1.0 : 0.32),
                .kern: 0.8,
            ]
            NSAttributedString(string: flag.0, attributes: attrs)
                .draw(at: NSPoint(x: 22, y: 24 + CGFloat(i) * 20))
        }

        NSAttributedString(string: "VOL", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: ink.withAlphaComponent(0.75),
        ]).draw(at: NSPoint(x: 200, y: 25))

        let lit = Int((volumeFraction * 10).rounded())
        for i in 0..<10 {
            ink.withAlphaComponent(i < lit ? 0.9 : 0.22).setFill()
            NSBezierPath(roundedRect: NSRect(x: 232 + CGFloat(i) * 7, y: 24, width: 4, height: 11),
                         xRadius: 1, yRadius: 1).fill()
        }

        NSAttributedString(string: bigValue, attributes: [
            .font: NSFont.systemFont(ofSize: 40, weight: .bold),
            .foregroundColor: ink.withAlphaComponent(0.92),
        ]).draw(at: NSPoint(x: 232, y: 40))

        NSAttributedString(string: "%", attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: ink.withAlphaComponent(0.55),
        ]).draw(at: NSPoint(x: 296, y: 60))

        // Pack name sits bottom-left; the waveform occupies the bottom-right,
        // so the two no longer overlap.
        NSAttributedString(string: packName, attributes: [
            .font: NSFont.systemFont(ofSize: 19, weight: .bold),
            .foregroundColor: ink.withAlphaComponent(0.42),
            .kern: 1.0,
        ]).draw(at: NSPoint(x: 22, y: 112))
    }
}

/// Machined rotary knob. Static layers are rendered once into a CGImage; only
/// the indicator and value arc redraw per frame.
final class KnobControl: NSControl {
    override var isFlipped: Bool { true }

    var minValue: Double = 0
    var maxValue: Double = 1
    var value: Double = 0.5 { didSet { needsDisplay = true } }
    var accentColor = NSColor(srgbRed: 0.98, green: 0.63, blue: 0.13, alpha: 1)
    var showsValueArc = true

    // 270° sweep, centred on 12 o'clock: -135° through +135°, measured
    // clockwise from the top.
    private let sweepStart: CGFloat = -135 * .pi / 180
    private let sweepEnd: CGFloat = 135 * .pi / 180

    private var cachedBody: NSImage?
    private var cachedSize: NSSize = .zero
    private var dragOrigin: NSPoint = .zero
    private var dragStartValue: Double = 0

    /// Every angle in this control is measured clockwise from 12 o'clock, and
    /// this is the single place that converts one to a point. Keeping one
    /// convention avoids the flipped-context sign errors that plague arcs.
    private func point(_ a: CGFloat, _ r: CGFloat, _ c: NSPoint) -> NSPoint {
        NSPoint(x: c.x + sin(a) * r, y: c.y - cos(a) * r)
    }

    private var fraction: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat((value - minValue) / (maxValue - minValue))
    }

    private var angle: CGFloat { sweepStart + fraction * (sweepEnd - sweepStart) }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        cachedBody = nil
    }

    /// Knob radius. The extra inset leaves room for the value arc to sit
    /// outside the body without being clipped by the view bounds.
    private var knobRadius: CGFloat { min(bounds.width, bounds.height) / 2 - (showsValueArc ? 12 : 5) }

    override func draw(_ dirtyRect: NSRect) {
        if cachedBody == nil || cachedSize != bounds.size {
            cachedBody = renderBodyImage()
            cachedSize = bounds.size
        }
        cachedBody?.draw(in: bounds)

        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let r = knobRadius

        if showsValueArc {
            drawArc(center: c, radius: r + 7, from: sweepStart, to: sweepEnd,
                    color: NSColor(white: 0, alpha: 0.14), width: 3.5)
            drawArc(center: c, radius: r + 7, from: sweepStart, to: angle,
                    color: accentColor, width: 3.5)
        }

        // Indicator notch, with a light leading edge so it reads as engraved.
        let inner = point(angle, r * 0.50, c)
        let outer = point(angle, r * 0.86, c)
        let notch = NSBezierPath()
        notch.move(to: inner)
        notch.line(to: outer)
        notch.lineWidth = 3
        notch.lineCapStyle = .round
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1).setStroke()
        notch.stroke()
    }

    /// Points are sampled rather than using `addArc` so the result doesn't
    /// depend on flipped-context winding conventions.
    private func drawArc(center: NSPoint, radius: CGFloat, from a0: CGFloat, to a1: CGFloat,
                         color: NSColor, width: CGFloat) {
        guard abs(a1 - a0) > 0.001 else { return }
        let path = NSBezierPath()
        let steps = 48
        for i in 0...steps {
            let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
            let p = NSPoint(x: center.x + sin(a) * radius, y: center.y - cos(a) * radius)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// Rendered through NSImage with a flipped handler so the body is drawn in
    /// the same coordinate space as the view. Drawing a raw CGImage into a
    /// flipped context silently vertically-flips it, which previously put the
    /// highlight and bevel on the wrong sides.
    private func renderBodyImage() -> NSImage {
        let size = bounds.size
        let image = NSImage(size: size, flipped: true) { [weak self] _ in
            self?.drawBodyContents()
            return true
        }
        image.cacheMode = .always
        return image
    }

    private func drawBodyContents() {
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let r = knobRadius
        guard r > 4 else { return }

        // Collar.
        NSColor(srgbRed: 0.38, green: 0.40, blue: 0.45, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r - 2.5, y: c.y - r - 2.5,
                                    width: (r + 2.5) * 2, height: (r + 2.5) * 2)).fill()

        let bodyRect = NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let bodyPath = NSBezierPath(ovalIn: bodyRect)

        NSGraphicsContext.saveGraphicsState()
        bodyPath.addClip()

        // Body: radial gradient with its centre pushed up-left (smaller y is
        // up in this flipped space), which makes a flat disc read as a lit
        // cylinder rather than a sticker.
        let hotspot = NSPoint(x: c.x - r * 0.28, y: c.y - r * 0.28)
        Plastic.gradient([
            (0.00, NSColor(white: 1.0, alpha: 1)),
            (0.45, NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1)),
            (0.80, NSColor(srgbRed: 0.74, green: 0.76, blue: 0.80, alpha: 1)),
            (1.00, NSColor(srgbRed: 0.52, green: 0.54, blue: 0.59, alpha: 1)),
        ])?.draw(fromCenter: hotspot, radius: 0, toCenter: c, radius: r * 1.45, options: [])

        // Lathe finish. Radial brushing is anisotropic — brightness varies with
        // angle, not radius — so these are fine radial spokes with a hashed
        // per-angle alpha, not concentric rings.
        //
        // Two things keep it from turning into a starburst: the spokes start
        // well out from the middle (radial lines converge at the centre, so
        // density — and therefore brightness — would spike there), and each
        // one is jittered in length so they don't share a hard inner edge.
        let spokes = r > 30 ? 640 : 320
        for i in 0..<spokes {
            let a = CGFloat(i) / CGFloat(spokes) * 2 * .pi
            let hash = sin(a * 137.5) * 43758.5453
            let n = abs(hash - hash.rounded(.down))
            let jitter = abs((sin(a * 311.7) * 24634.6345).truncatingRemainder(dividingBy: 1))
            NSColor(white: n > 0.5 ? 1 : 0, alpha: 0.010 + 0.020 * n).setStroke()
            let p = NSBezierPath()
            p.move(to: point(a, r * (0.34 + 0.10 * jitter), c))
            p.line(to: point(a, r * (0.94 + 0.05 * jitter), c))
            p.lineWidth = 0.7
            p.stroke()
        }

        // Two-lobe angular sheen — the specular signature of turned metal.
        // Deliberately faint; it should suggest a direction of light, not
        // draw a fan across the face.
        for i in 0..<200 {
            let a = CGFloat(i) / 200 * 2 * .pi
            let alpha = max(0, cos(2 * (a - .pi * 0.25))) * 0.055
            guard alpha > 0.002 else { continue }
            NSColor(white: 1, alpha: alpha).setStroke()
            let p = NSBezierPath()
            p.move(to: point(a, r * 0.36, c))
            p.line(to: point(a, r * 0.95, c))
            p.lineWidth = 3.0
            p.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Polar bevel — light across the top-left, dark across the bottom-right.
        strokeArc(center: c, radius: r - 1.5, from: -140, to: -20,
                  color: NSColor(white: 1, alpha: 0.8), width: 2)
        strokeArc(center: c, radius: r - 1.5, from: 40, to: 160,
                  color: NSColor(white: 0, alpha: 0.32), width: 2)

        // Outer edge.
        NSColor(white: 0, alpha: 0.28).setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()

        // Centre cap — kept small so it reads as a fixing screw, not a donut.
        let capR = max(3, r * 0.22)
        let capRect = NSRect(x: c.x - capR, y: c.y - capR, width: capR * 2, height: capR * 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: capRect).addClip()
        Plastic.gradient([
            (0, NSColor(white: 1, alpha: 1)),
            (1, NSColor(srgbRed: 0.72, green: 0.74, blue: 0.79, alpha: 1)),
        ])?.draw(in: capRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0, alpha: 0.18).setStroke()
        let capPath = NSBezierPath(ovalIn: capRect)
        capPath.lineWidth = 0.75
        capPath.stroke()
    }

    /// Arc in the same clockwise-from-top convention as everything else here.
    private func strokeArc(center: NSPoint, radius: CGFloat, from d0: CGFloat, to d1: CGFloat,
                           color: NSColor, width: CGFloat) {
        drawArc(center: center, radius: radius,
                from: d0 * .pi / 180, to: d1 * .pi / 180, color: color, width: width)
    }

    // MARK: Interaction — vertical drag, the convention audio hardware UIs use
    // because it's far more precise than trying to trace a circle.

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragStartValue = value
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Flipped view: dragging up decreases y, and should raise the value.
        let dy = dragOrigin.y - p.y
        let fine = event.modifierFlags.contains(.option) ? 0.25 : 1.0
        let delta = Double(dy) / 160.0 * (maxValue - minValue) * fine
        value = min(maxValue, max(minValue, dragStartValue + delta))
        sendAction(action, to: target)
    }
}

/// Circular glossy button.
final class RoundButton: NSButton {
    override var isFlipped: Bool { true }
    var isAccent = false { didSet { needsDisplay = true } }
    var glyph: String = ""
    private var pressed = false

    override func draw(_ dirtyRect: NSRect) {
        let r = min(bounds.width, bounds.height) / 2 - 4
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let rect = NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let path = NSBezierPath(ovalIn: rect)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if isAccent {
            Plastic.gradient([
                (0, NSColor(srgbRed: 1.00, green: 0.80, blue: 0.32, alpha: 1)),
                (0.5, NSColor(srgbRed: 0.98, green: 0.66, blue: 0.16, alpha: 1)),
                (1, NSColor(srgbRed: 0.88, green: 0.50, blue: 0.08, alpha: 1)),
            ])?.draw(in: rect, angle: pressed ? 90 : -90)
        } else {
            Plastic.gradient([
                (0, NSColor(white: 1, alpha: 1)),
                (0.5, NSColor(srgbRed: 0.97, green: 0.975, blue: 0.985, alpha: 1)),
                (1, NSColor(srgbRed: 0.82, green: 0.835, blue: 0.86, alpha: 1)),
            ])?.draw(in: rect, angle: pressed ? 90 : -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 0, alpha: 0.22).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        let text = glyph.isEmpty ? title : glyph
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: glyph.isEmpty ? 10 : 15, weight: .bold),
            .foregroundColor: isAccent ? NSColor.white : NSColor(srgbRed: 0.28, green: 0.30, blue: 0.35, alpha: 1),
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: c.x - size.width / 2, y: c.y - size.height / 2))
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true; needsDisplay = true
        super.mouseDown(with: event)
        pressed = false; needsDisplay = true
    }
}

/// Indicator lamp used for pack selection.
final class LEDLamp: NSControl {
    override var isFlipped: Bool { true }
    var isLit = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let socket = NSBezierPath(ovalIn: bounds)
        NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1).setFill()
        socket.fill()

        let inset = bounds.insetBy(dx: 4, dy: 4)
        let lamp = NSBezierPath(ovalIn: inset)
        NSGraphicsContext.saveGraphicsState()
        if isLit {
            let glow = NSShadow()
            glow.shadowColor = NSColor(srgbRed: 1, green: 0.62, blue: 0.12, alpha: 0.9)
            glow.shadowOffset = .zero
            glow.shadowBlurRadius = 10
            glow.set()
        }
        lamp.addClip()
        if isLit {
            Plastic.gradient([
                (0, NSColor(srgbRed: 1.0, green: 0.90, blue: 0.55, alpha: 1)),
                (0.6, NSColor(srgbRed: 0.99, green: 0.66, blue: 0.13, alpha: 1)),
                (1, NSColor(srgbRed: 0.75, green: 0.38, blue: 0.03, alpha: 1)),
            ])?.draw(in: inset, angle: -90)
        } else {
            Plastic.gradient([
                (0, NSColor(srgbRed: 0.34, green: 0.36, blue: 0.41, alpha: 1)),
                (1, NSColor(srgbRed: 0.22, green: 0.24, blue: 0.29, alpha: 1)),
            ])?.draw(in: inset, angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        if isLit {
            // Redraw the lit face without the shadow so the glow sits behind it.
            NSGraphicsContext.saveGraphicsState()
            lamp.addClip()
            Plastic.gradient([
                (0, NSColor(srgbRed: 1.0, green: 0.90, blue: 0.55, alpha: 1)),
                (0.6, NSColor(srgbRed: 0.99, green: 0.66, blue: 0.13, alpha: 1)),
                (1, NSColor(srgbRed: 0.75, green: 0.38, blue: 0.03, alpha: 1)),
            ])?.draw(in: inset, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}
