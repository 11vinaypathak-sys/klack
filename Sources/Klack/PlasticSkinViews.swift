import Cocoa
import KlackBrand

// V2 skin: dark chassis + glossy white plastic plate + backlit amber display.
// All views are `isFlipped` so coordinates match the Figma reference directly.

extension NSBezierPath {
    /// `NSBezierPath.cgPath` is macOS 14+, but Klack targets 12 — walk the
    /// elements instead so the inner-shadow routine works everywhere.
    var compatCGPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

/// A full colour scheme for the panel. Everything tinted — backlight, LEDs,
/// accents, meter ramp, even the chassis temperature — comes from here, so
/// switching themes restyles the whole instrument rather than recolouring
/// one element.
struct Theme {
    let name: String
    let displayCore: NSColor
    let displayMid: NSColor
    let displayEdge: NSColor
    let displayInk: NSColor
    let bezelLeak: NSColor
    let accentTop: NSColor
    let accentMid: NSColor
    let accentBottom: NSColor
    let lampLit: NSColor
    let chassisTop: NSColor
    let chassisMid: NSColor
    let chassisBottom: NSColor
    /// Low → mid → hot stops for the level meter ladder.
    let meterRamp: (NSColor, NSColor, NSColor)

    static let amber = Theme(
        name: "AMBER",
        displayCore: NSColor(srgbRed: 1.00, green: 0.72, blue: 0.30, alpha: 1),
        displayMid: NSColor(srgbRed: 0.94, green: 0.60, blue: 0.17, alpha: 1),
        displayEdge: NSColor(srgbRed: 0.50, green: 0.26, blue: 0.05, alpha: 1),
        displayInk: NSColor(srgbRed: 0.26, green: 0.13, blue: 0.01, alpha: 1),
        bezelLeak: NSColor(srgbRed: 1.00, green: 0.85, blue: 0.63, alpha: 1),
        accentTop: NSColor(srgbRed: 1.00, green: 0.80, blue: 0.32, alpha: 1),
        accentMid: NSColor(srgbRed: 0.98, green: 0.66, blue: 0.16, alpha: 1),
        accentBottom: NSColor(srgbRed: 0.88, green: 0.50, blue: 0.08, alpha: 1),
        lampLit: NSColor(srgbRed: 0.99, green: 0.66, blue: 0.13, alpha: 1),
        chassisTop: NSColor(srgbRed: 0.23, green: 0.27, blue: 0.35, alpha: 1),
        chassisMid: NSColor(srgbRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
        chassisBottom: NSColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 1),
        meterRamp: (NSColor(srgbRed: 0.42, green: 0.86, blue: 0.52, alpha: 1),
                    NSColor(srgbRed: 0.99, green: 0.72, blue: 0.15, alpha: 1),
                    NSColor(srgbRed: 0.95, green: 0.26, blue: 0.20, alpha: 1))
    )

    static let cyan = Theme(
        name: "ICE",
        displayCore: NSColor(srgbRed: 0.62, green: 0.94, blue: 1.00, alpha: 1),
        displayMid: NSColor(srgbRed: 0.24, green: 0.72, blue: 0.90, alpha: 1),
        displayEdge: NSColor(srgbRed: 0.03, green: 0.24, blue: 0.38, alpha: 1),
        displayInk: NSColor(srgbRed: 0.02, green: 0.13, blue: 0.20, alpha: 1),
        bezelLeak: NSColor(srgbRed: 0.72, green: 0.95, blue: 1.00, alpha: 1),
        accentTop: NSColor(srgbRed: 0.48, green: 0.88, blue: 1.00, alpha: 1),
        accentMid: NSColor(srgbRed: 0.16, green: 0.68, blue: 0.90, alpha: 1),
        accentBottom: NSColor(srgbRed: 0.05, green: 0.46, blue: 0.68, alpha: 1),
        lampLit: NSColor(srgbRed: 0.30, green: 0.80, blue: 1.00, alpha: 1),
        chassisTop: NSColor(srgbRed: 0.20, green: 0.26, blue: 0.34, alpha: 1),
        chassisMid: NSColor(srgbRed: 0.10, green: 0.15, blue: 0.21, alpha: 1),
        chassisBottom: NSColor(srgbRed: 0.05, green: 0.08, blue: 0.12, alpha: 1),
        meterRamp: (NSColor(srgbRed: 0.30, green: 0.78, blue: 0.98, alpha: 1),
                    NSColor(srgbRed: 0.55, green: 0.92, blue: 1.00, alpha: 1),
                    NSColor(srgbRed: 0.95, green: 0.98, blue: 1.00, alpha: 1))
    )

    static let phosphor = Theme(
        name: "PHOSPHOR",
        displayCore: NSColor(srgbRed: 0.62, green: 1.00, blue: 0.55, alpha: 1),
        displayMid: NSColor(srgbRed: 0.28, green: 0.76, blue: 0.28, alpha: 1),
        displayEdge: NSColor(srgbRed: 0.03, green: 0.22, blue: 0.06, alpha: 1),
        displayInk: NSColor(srgbRed: 0.02, green: 0.14, blue: 0.03, alpha: 1),
        bezelLeak: NSColor(srgbRed: 0.75, green: 1.00, blue: 0.70, alpha: 1),
        accentTop: NSColor(srgbRed: 0.62, green: 0.98, blue: 0.52, alpha: 1),
        accentMid: NSColor(srgbRed: 0.32, green: 0.80, blue: 0.30, alpha: 1),
        accentBottom: NSColor(srgbRed: 0.16, green: 0.56, blue: 0.18, alpha: 1),
        lampLit: NSColor(srgbRed: 0.44, green: 0.95, blue: 0.40, alpha: 1),
        chassisTop: NSColor(srgbRed: 0.19, green: 0.24, blue: 0.21, alpha: 1),
        chassisMid: NSColor(srgbRed: 0.10, green: 0.14, blue: 0.11, alpha: 1),
        chassisBottom: NSColor(srgbRed: 0.05, green: 0.08, blue: 0.06, alpha: 1),
        meterRamp: (NSColor(srgbRed: 0.34, green: 0.82, blue: 0.34, alpha: 1),
                    NSColor(srgbRed: 0.62, green: 1.00, blue: 0.48, alpha: 1),
                    NSColor(srgbRed: 0.92, green: 1.00, blue: 0.55, alpha: 1))
    )

    static let synthwave = Theme(
        name: "SYNTH",
        displayCore: NSColor(srgbRed: 1.00, green: 0.62, blue: 0.92, alpha: 1),
        displayMid: NSColor(srgbRed: 0.82, green: 0.24, blue: 0.68, alpha: 1),
        displayEdge: NSColor(srgbRed: 0.26, green: 0.04, blue: 0.30, alpha: 1),
        displayInk: NSColor(srgbRed: 0.18, green: 0.02, blue: 0.20, alpha: 1),
        bezelLeak: NSColor(srgbRed: 1.00, green: 0.72, blue: 0.95, alpha: 1),
        accentTop: NSColor(srgbRed: 1.00, green: 0.55, blue: 0.85, alpha: 1),
        accentMid: NSColor(srgbRed: 0.88, green: 0.24, blue: 0.66, alpha: 1),
        accentBottom: NSColor(srgbRed: 0.58, green: 0.12, blue: 0.52, alpha: 1),
        lampLit: NSColor(srgbRed: 1.00, green: 0.38, blue: 0.80, alpha: 1),
        chassisTop: NSColor(srgbRed: 0.24, green: 0.20, blue: 0.36, alpha: 1),
        chassisMid: NSColor(srgbRed: 0.13, green: 0.10, blue: 0.22, alpha: 1),
        chassisBottom: NSColor(srgbRed: 0.07, green: 0.05, blue: 0.13, alpha: 1),
        meterRamp: (NSColor(srgbRed: 0.42, green: 0.55, blue: 1.00, alpha: 1),
                    NSColor(srgbRed: 0.85, green: 0.35, blue: 0.95, alpha: 1),
                    NSColor(srgbRed: 1.00, green: 0.30, blue: 0.55, alpha: 1))
    )

    static let all: [Theme] = [.amber, .cyan, .phosphor, .synthwave]

    /// Read by every view at draw time. Changing it and invalidating the view
    /// tree restyles the whole panel.
    static var current: Theme = .amber
}

/// Drives idle motion — a slow scanline sweep and a breathing pulse — so the
/// panel reads as powered-on rather than as a static picture. One shared
/// clock keeps every element in phase, and it only runs while visible.
final class MotionClock {
    static let shared = MotionClock()
    private var timer: Timer?
    private var subscribers: [() -> Void] = []
    private(set) var phase: CGFloat = 0

    func subscribe(_ block: @escaping () -> Void) { subscribers.append(block) }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 1.0 / 30.0
            for s in self.subscribers { s() }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

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

    /// Chrome reads as chrome because the ramp is *non-monotonic*: it reverses
    /// hard at a horizon line where reflected sky meets reflected ground. The
    /// 0.48 -> 0.52 flip must stay near-instant — smooth it out and you get
    /// brushed aluminium instead of a mirror.
    static let chromeStops: [(CGFloat, NSColor)] = [
        (0.00, NSColor(srgbRed: 0.42, green: 0.45, blue: 0.49, alpha: 1)),
        (0.08, NSColor(srgbRed: 0.72, green: 0.76, blue: 0.80, alpha: 1)),
        (0.30, NSColor(srgbRed: 0.87, green: 0.91, blue: 0.94, alpha: 1)),
        (0.48, NSColor(srgbRed: 0.96, green: 0.98, blue: 1.00, alpha: 1)), // hotspot
        (0.52, NSColor(srgbRed: 0.20, green: 0.23, blue: 0.27, alpha: 1)), // horizon flip
        (0.56, NSColor(srgbRed: 0.31, green: 0.35, blue: 0.40, alpha: 1)),
        (0.74, NSColor(srgbRed: 0.60, green: 0.64, blue: 0.69, alpha: 1)),
        (0.88, NSColor(srgbRed: 0.80, green: 0.84, blue: 0.88, alpha: 1)),
        (1.00, NSColor(srgbRed: 0.46, green: 0.49, blue: 0.53, alpha: 1)),
    ]

    static func drawChrome(in path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let r = path.bounds
        gradient(chromeStops)?.draw(in: r, angle: -90)
        // Edge-wrap: bright at both sides, faking the reflection curling round
        // a cylindrical surface.
        gradient([
            (0.00, NSColor(white: 1, alpha: 0.22)),
            (0.35, NSColor(white: 1, alpha: 0.0)),
            (0.65, NSColor(white: 1, alpha: 0.0)),
            (1.00, NSColor(white: 1, alpha: 0.22)),
        ])?.draw(in: r, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Core Graphics has no inner-shadow primitive. Clipping to the shape and
    /// filling with `.sourceOut` inside a transparency layer puts the shadow of
    /// the *inverted* shape inside the path, which is the standard trick.
    static func innerShadow(in path: NSBezierPath, offset: NSSize, blur: CGFloat, alpha: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.addPath(path.compatCGPath)
        ctx.clip()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setShadow(offset: offset, blur: blur, color: NSColor.black.cgColor)
        ctx.setBlendMode(.sourceOut)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(path.compatCGPath)
        ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Arc sampled as points rather than `addArc`, so it doesn't depend on
    /// flipped-context winding conventions. Degrees are clockwise from 12.
    static func arc(center: NSPoint, radius: CGFloat, fromDeg: CGFloat, toDeg: CGFloat,
                    color: NSColor, width: CGFloat) {
        let path = NSBezierPath()
        let steps = 48
        for i in 0...steps {
            let d = (fromDeg + (toDeg - fromDeg) * CGFloat(i) / CGFloat(steps)) * .pi / 180
            let p = NSPoint(x: center.x + sin(d) * radius, y: center.y - cos(d) * radius)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// Anamorphic star glint — the era's punctuation mark on a gloss peak.
    /// Spikes are deliberately unequal; four equal ones read as a cross.
    static func drawGlint(at c: NSPoint, length L: CGFloat, alpha: CGFloat = 1.0) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.setAlpha(alpha)

        func spike(angle: CGFloat, len: CGFloat) {
            let base = L * 0.045
            let tip = NSPoint(x: c.x + cos(angle) * len, y: c.y + sin(angle) * len)
            let n = angle + .pi / 2
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x + cos(n) * base, y: c.y + sin(n) * base))
            p.line(to: tip)
            p.line(to: NSPoint(x: c.x - cos(n) * base, y: c.y - sin(n) * base))
            p.close()
            NSColor(white: 1, alpha: 0.9).setFill()
            p.fill()
        }
        spike(angle: 0, len: L)
        spike(angle: .pi, len: L)
        spike(angle: .pi / 2, len: L * 0.55)
        spike(angle: -.pi / 2, len: L * 0.55)

        let coreR = L * 0.16
        let coreRect = NSRect(x: c.x - coreR, y: c.y - coreR, width: coreR * 2, height: coreR * 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: coreRect).addClip()
        gradient([
            (0.0, NSColor(white: 1, alpha: 1.0)),
            (0.25, NSColor(white: 1, alpha: 0.5)),
            (1.0, NSColor(white: 1, alpha: 0.0)),
        ])?.draw(fromCenter: c, radius: 0, toCenter: c, radius: coreR, options: [])
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }

    /// DSEG7 Classic (SIL OFL) is a true seven-segment face. Registered once
    /// from the bundle; falls back to a monospace face if it's missing.
    private static var didRegisterFonts = false
    static func segmentFont(size: CGFloat) -> NSFont {
        if !didRegisterFonts {
            didRegisterFonts = true
            if let dir = Bundle.main.resourceURL?.appendingPathComponent("fonts"),
               let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for url in files where url.pathExtension.lowercased() == "ttf" {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                }
            }
        }
        return NSFont(name: "DSEG7 Classic", size: size)
            ?? NSFont(name: "DSEG7Classic-Bold", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
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
        let th = Theme.current
        Plastic.gradient([(0, th.chassisTop), (0.5, th.chassisMid), (1, th.chassisBottom)])?
            .draw(in: path, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // No bitmap grain on the chassis. The tile is 64 *pixels* but was being
        // drawn into a 64-*point* rect, so on a Retina display it upscaled 2x
        // and the noise became coarse, visible speckle instead of a fine
        // finish. A soft-touch surface is better suggested by the gradient and
        // sheen below than by tiled noise.

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

        // Glint on the gloss peak, drifting slightly so it never looks pasted.
        let drift = sin(MotionClock.shared.phase * 0.55) * 4
        Plastic.drawGlint(at: NSPoint(x: bounds.width * 0.26 + drift, y: bounds.height * 0.08),
                          length: 26, alpha: 0.5)
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
        let th = Theme.current
        func lift(_ c: NSColor, _ amount: CGFloat) -> NSColor {
            c.blended(withFraction: amount, of: .white) ?? c
        }
        Plastic.gradient([
            (0.00, lift(th.displayCore, b * 2.2)),
            (0.45, lift(th.displayMid, b * 1.8)),
            (0.80, lift(th.displayMid.blended(withFraction: 0.45, of: th.displayEdge) ?? th.displayMid, b)),
            (1.00, lift(th.displayEdge, b * 0.6)),
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

        // A soft band sweeping down the glass — the refresh cue that makes a
        // display read as running rather than as a printed panel.
        let sweepPeriod: CGFloat = 4.2
        let sweepPos = MotionClock.shared.phase.truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod
        let sweepY = sweepPos * (bounds.height + 60) - 30
        Plastic.gradient([
            (0, NSColor(white: 1, alpha: 0)),
            (0.5, NSColor(white: 1, alpha: 0.10)),
            (1, NSColor(white: 1, alpha: 0)),
        ])?.draw(in: NSRect(x: 0, y: sweepY, width: bounds.width, height: 30), angle: -90)

        // (iv) Grain. Kept very faint and composited normally — `.overlay`
        // amplifies contrast against bright colours, which on amber turned
        // this into visible static rather than a subtle phosphor texture.
        // Drawn at half size so the tile lands 1:1 on Retina pixels instead of
        // being doubled into visible speckle.
        if let noise = Plastic.noiseTile, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setAlpha(0.035)
            ctx.draw(noise, in: NSRect(x: 0, y: 0, width: 32, height: 32), byTiling: true)
            ctx.restoreGState()
        }

        // (iii) Light leak at the bezel — stroked at widening radii with
        // falling alpha, since Core Graphics can't feather a stroke.
        for (w, a) in [(1.0, 0.35), (2.0, 0.22), (3.0, 0.12), (4.0, 0.06)] {
            let leak = NSBezierPath(roundedRect: bounds.insetBy(dx: w / 2, dy: w / 2),
                                    xRadius: 15 - w / 2, yRadius: 15 - w / 2)
            Theme.current.bezelLeak.withAlphaComponent(CGFloat(a)).setStroke()
            leak.lineWidth = CGFloat(w)
            leak.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawContent() {
        let ink = Theme.current.displayInk

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

        // Seven-segment readout. Drawing "888" faintly behind the live value
        // shows the unlit segments a real LCD has — the single biggest cue
        // that separates a segment display from ordinary bold text.
        // Kept faint deliberately: on a real LCD the unlit segments are barely
        // there. Too much alpha and a leading ghost digit reads as part of the
        // number — "83" starts looking like "883".
        let segFont = Plastic.segmentFont(size: 34)
        NSAttributedString(string: "888", attributes: [
            .font: segFont,
            .foregroundColor: ink.withAlphaComponent(0.035),
        ]).draw(at: NSPoint(x: 216, y: 44))

        let padded = String(repeating: " ", count: max(0, 3 - bigValue.count)) + bigValue
        NSAttributedString(string: padded, attributes: [
            .font: segFont,
            .foregroundColor: ink.withAlphaComponent(0.92),
        ]).draw(at: NSPoint(x: 216, y: 44))

        NSAttributedString(string: "%", attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
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

/// Spectrum analyser: quantised bars with peak-hold caps that hang and then
/// fall. The caps are the detail that makes it read as an analyser rather than
/// a bar chart — they mark recent maxima and drop under gravity.
final class SpectrumView: NSView {
    override var isFlipped: Bool { true }

    /// Band energies of the current sound, 0...1.
    var bands: [Float] = [] {
        didSet {
            if levels.count != bands.count {
                levels = [CGFloat](repeating: 0, count: bands.count)
                peaks = [CGFloat](repeating: 0, count: bands.count)
                peakAge = [CGFloat](repeating: 0, count: bands.count)
            }
        }
    }
    /// How hard the user is typing; scales the whole analyser.
    var drive: CGFloat = 0

    private var levels: [CGFloat] = []
    private var peaks: [CGFloat] = []
    private var peakAge: [CGFloat] = []
    private var rng = SystemRandomNumberGenerator()

    /// Advance one frame: bars chase their target, caps hang briefly then fall
    /// with acceleration.
    func step() {
        guard !bands.isEmpty else { return }
        for i in 0..<bands.count {
            // A little per-band jitter so the bars don't move as one block.
            let wobble = 1.0 + 0.22 * sin(MotionClock.shared.phase * (2.6 + CGFloat(i) * 0.31))
            let target = CGFloat(bands[i]) * drive * wobble

            // Fast attack, slow release — standard analyser ballistics.
            if target > levels[i] {
                levels[i] += (target - levels[i]) * 0.55
            } else {
                levels[i] += (target - levels[i]) * 0.16
            }
            levels[i] = min(1, max(0, levels[i]))

            if levels[i] >= peaks[i] {
                peaks[i] = levels[i]
                peakAge[i] = 0
            } else {
                peakAge[i] += 1
                // Hang for ~12 frames, then accelerate downward.
                if peakAge[i] > 12 {
                    peaks[i] -= 0.004 * (peakAge[i] - 12)
                    peaks[i] = max(levels[i], peaks[i])
                }
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !levels.isEmpty else { return }
        let ink = Theme.current.displayInk
        let n = levels.count
        let gap: CGFloat = 2
        let barW = (bounds.width - gap * CGFloat(n - 1)) / CGFloat(n)
        // Quantised into cells, the way a hardware analyser is built.
        let rows = 12
        let cellH = bounds.height / CGFloat(rows)

        for i in 0..<n {
            let x = CGFloat(i) * (barW + gap)
            let lit = Int((levels[i] * CGFloat(rows)).rounded())

            for r in 0..<rows {
                let y = bounds.height - CGFloat(r + 1) * cellH
                let cell = NSRect(x: x, y: y + 0.5, width: barW, height: cellH - 1)
                if r < lit {
                    // Brighter toward the top of each bar.
                    let heat = 0.45 + 0.5 * CGFloat(r) / CGFloat(rows)
                    ink.withAlphaComponent(heat).setFill()
                } else {
                    ink.withAlphaComponent(0.07).setFill()
                }
                NSBezierPath(roundedRect: cell, xRadius: 0.5, yRadius: 0.5).fill()
            }

            // Peak-hold cap.
            let peakRow = min(rows - 1, Int((peaks[i] * CGFloat(rows)).rounded()))
            if peakRow > 0 {
                let y = bounds.height - CGFloat(peakRow + 1) * cellH
                ink.withAlphaComponent(0.95).setFill()
                NSRect(x: x, y: y + 0.5, width: barW, height: 1.5).fill()
            }
        }
    }
}

/// Segmented LED level meter, used for volume. Reads like a hardware VU
/// ladder: green through the working range, amber as it climbs, red at the
/// top. Click or drag anywhere along it to set the level.
final class LevelMeterControl: NSControl {
    override var isFlipped: Bool { true }

    /// The volume setting. Shown as a ceiling marker, not as the lit bar —
    /// this is the level typing is allowed to reach.
    var value: Double = 0.8 { didSet { needsDisplay = true } }

    /// How hard you're currently typing, 0...1. The lit bar tracks this, so
    /// the meter rests low and climbs as you type instead of sitting pinned.
    var activityLevel: CGFloat = 0 { didSet { needsDisplay = true } }

    private let segmentCount = 24
    private let gap: CGFloat = 3

    /// Colour ramp across the ladder — the last few segments run hot.
    private func colorForSegment(_ i: Int) -> NSColor {
        let ramp = Theme.current.meterRamp
        let f = CGFloat(i) / CGFloat(segmentCount - 1)
        if f > 0.88 { return ramp.2 }
        if f > 0.70 { return ramp.1 }
        return ramp.0
    }

    override func draw(_ dirtyRect: NSRect) {
        // Recessed channel the segments sit in.
        let well = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).setFill()
        well.fill()

        NSGraphicsContext.saveGraphicsState()
        well.addClip()

        let inset: CGFloat = 5
        let usable = bounds.width - inset * 2
        let segW = (usable - gap * CGFloat(segmentCount - 1)) / CGFloat(segmentCount)
        let segH = bounds.height - inset * 2

        // The bar shows activity, capped by the volume setting — so typing
        // fills it up toward whatever ceiling you've dialled in.
        let ceiling = CGFloat(min(1.0, max(0.0, value)))
        // A small resting floor plus a slow idle shimmer, so a quiet meter
        // still reads as powered rather than switched off.
        let idle = 0.06 + 0.03 * abs(sin(MotionClock.shared.phase * 1.1))
        let level = min(ceiling, max(idle, max(0.0, activityLevel)) * ceiling)
        let litCount = Int((level * CGFloat(segmentCount)).rounded())
        let ceilingIndex = Int((ceiling * CGFloat(segmentCount)).rounded()) - 1

        for i in 0..<segmentCount {
            let x = inset + CGFloat(i) * (segW + gap)
            let rect = NSRect(x: x, y: inset, width: segW, height: segH)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
            let lit = i < litCount
            let base = colorForSegment(i)

            if lit {
                // Glow behind the lit segment, then the segment itself.
                NSGraphicsContext.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = base.withAlphaComponent(0.9)
                glow.shadowOffset = .zero
                glow.shadowBlurRadius = 6
                glow.set()
                base.setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()

                // Bright core with a highlight along the top edge.
                base.highlight(withLevel: 0.35)?.setFill()
                path.fill()
                NSColor(white: 1, alpha: 0.45).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: inset, width: segW, height: max(1, segH * 0.28)),
                             xRadius: 1, yRadius: 1).fill()
            } else {
                // Unlit segments keep a trace of their colour, like a real LED
                // that's off but still tinted.
                base.withAlphaComponent(0.13).setFill()
                path.fill()
            }

            // Ceiling marker: shows where the volume is set, so the control
            // still reads as a setting even while the bar is bouncing.
            if i == ceilingIndex {
                NSColor(white: 1, alpha: 0.85).setFill()
                NSBezierPath(roundedRect: NSRect(x: x - 1.5, y: inset - 1,
                                                 width: segW + 3, height: segH + 2),
                             xRadius: 2, yRadius: 2).fill()
                base.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        Plastic.gradient([
            (0, NSColor(white: 0, alpha: 0.55)),
            (1, NSColor(white: 0, alpha: 0.0)),
        ])?.draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 4), angle: -90)

        NSColor(white: 1, alpha: 0.10).setStroke()
        well.lineWidth = 1
        well.stroke()
    }

    // MARK: Interaction — click or drag anywhere to set the level.

    private var dragOrigin: NSPoint = .zero
    private var dragStartValue: Double = 0
    private var dragIsVertical: Bool?

    private func valueFromX(_ p: NSPoint) -> Double {
        let inset: CGFloat = 5
        let usable = max(1, bounds.width - inset * 2)
        return Double(min(1, max(0, (p.x - inset) / usable)))
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragStartValue = value
        dragIsVertical = nil
        value = valueFromX(dragOrigin)
        sendAction(action, to: target)
    }

    /// Supports both gestures: drag along the bar to scrub, or drag up/down
    /// anywhere for finer control. Which one you get is decided by the first
    /// few pixels of movement, then locked so it doesn't flip mid-drag.
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - dragOrigin.x
        let dy = dragOrigin.y - p.y

        if dragIsVertical == nil {
            let travel = max(abs(dx), abs(dy))
            if travel > 3 { dragIsVertical = abs(dy) > abs(dx) }
        }

        if dragIsVertical == true {
            let fine = event.modifierFlags.contains(.option) ? 0.3 : 1.0
            value = min(1, max(0, dragStartValue + Double(dy) / 140.0 * fine))
        } else {
            value = valueFromX(p)
        }
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
        let th = Theme.current
        let outerR = min(bounds.width, bounds.height) / 2 - 1
        let c = NSPoint(x: bounds.midX, y: bounds.midY)

        // 1. Recessed socket the button sits down inside.
        let socketRect = NSRect(x: c.x - outerR, y: c.y - outerR, width: outerR * 2, height: outerR * 2)
        let socket = NSBezierPath(ovalIn: socketRect)
        NSColor(srgbRed: 0.74, green: 0.75, blue: 0.78, alpha: 1).setFill()
        socket.fill()
        Plastic.innerShadow(in: socket, offset: NSSize(width: 0, height: 2), blur: 4, alpha: 0.45)

        // 2. Chrome collar — the mirrored horizon reads as a machined bezel.
        let collarR = outerR - 2
        let collar = NSBezierPath(ovalIn: NSRect(x: c.x - collarR, y: c.y - collarR,
                                                 width: collarR * 2, height: collarR * 2))
        Plastic.drawChrome(in: collar)

        // 3. The cap itself, domed and inset from the collar.
        let r = collarR - 5
        let rect = NSRect(x: c.x - r, y: c.y - r + (pressed ? 1 : 0), width: r * 2, height: r * 2)
        let path = NSBezierPath(ovalIn: rect)

        // Cast shadow under the cap so it floats above the collar.
        NSGraphicsContext.saveGraphicsState()
        let drop = NSShadow()
        drop.shadowColor = NSColor(white: 0, alpha: pressed ? 0.30 : 0.55)
        drop.shadowOffset = NSSize(width: 0, height: pressed ? -1 : -3)
        drop.shadowBlurRadius = pressed ? 3 : 7
        drop.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if isAccent {
            Plastic.gradient([
                (0.00, th.accentTop.highlight(withLevel: 0.30) ?? th.accentTop),
                (0.55, th.accentMid),
                (1.00, th.accentBottom),
            ])?.draw(in: rect, angle: pressed ? 90 : -90)
        } else {
            Plastic.gradient([
                (0.00, NSColor(white: 1.0, alpha: 1)),
                (0.55, NSColor(srgbRed: 0.925, green: 0.935, blue: 0.950, alpha: 1)),
                (1.00, NSColor(srgbRed: 0.78, green: 0.80, blue: 0.83, alpha: 1)),
            ])?.draw(in: rect, angle: pressed ? 90 : -90)
        }

        // Broad specular across the top half, hard-terminated at the equator —
        // the same trick that makes the plate read as lacquered.
        let gloss = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.58)
        Plastic.gradient([
            (0.00, NSColor(white: 1, alpha: pressed ? 0.26 : 0.55)),
            (0.55, NSColor(white: 1, alpha: 0.20)),
            (0.86, NSColor(white: 1, alpha: 0.04)),
            (1.00, NSColor(white: 1, alpha: 0.0)),
        ])?.draw(in: gloss, angle: -90)

        // Warm bounce along the lower rim.
        let bounce = NSRect(x: rect.minX, y: rect.maxY - rect.height * 0.34,
                            width: rect.width, height: rect.height * 0.34)
        Plastic.gradient([
            (0.0, NSColor(white: 1, alpha: 0)),
            (0.6, Plastic.bounceLight.withAlphaComponent(0.10)),
            (1.0, Plastic.bounceLight.withAlphaComponent(0.26)),
        ])?.draw(in: bounce, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // 4. Rim: dark seat all round, bright catch-light along the top arc.
        NSColor(white: 0, alpha: 0.30).setStroke()
        path.lineWidth = 1
        path.stroke()
        Plastic.arc(center: NSPoint(x: rect.midX, y: rect.midY), radius: r - 0.5,
                 fromDeg: -150, toDeg: -30, color: NSColor(white: 1, alpha: 0.85), width: 1.6)

        // 5. Glint on the gloss peak — drawn before the label so the spikes
        // never cut across the text.
        if !pressed {
            Plastic.drawGlint(at: NSPoint(x: rect.minX + rect.width * 0.28,
                                          y: rect.minY + rect.height * 0.17),
                              length: r * 0.42, alpha: 0.38)
        }

        // 6. Label.
        let text = glyph.isEmpty ? title : glyph
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: glyph.isEmpty ? 10 : 15, weight: .bold),
            .foregroundColor: isAccent ? NSColor.white : NSColor(srgbRed: 0.26, green: 0.28, blue: 0.33, alpha: 1),
            .kern: glyph.isEmpty ? 0.6 : 0.0,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: isAccent ? 0 : 1, alpha: 0.5)
        shadow.shadowOffset = NSSize(width: 0, height: isAccent ? -1 : 1)
        shadow.shadowBlurRadius = 1
        let embossed = NSMutableAttributedString(attributedString: s)
        embossed.addAttribute(.shadow, value: shadow, range: NSRange(location: 0, length: embossed.length))
        embossed.draw(at: NSPoint(x: c.x - size.width / 2,
                                  y: c.y - size.height / 2 + (pressed ? 1 : 0)))

    }

    override func mouseDown(with event: NSEvent) {
        pressed = true; needsDisplay = true
        emitPressEffects(from: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        pressed = false; needsDisplay = true
    }

    /// Press feedback as Core Animation layers rather than timer-driven
    /// redraws: these are pure compositing, so the GPU can run them without
    /// re-rasterising the button every frame.
    private func emitPressEffects(from point: NSPoint) {
        wantsLayer = true
        guard let host = layer else { return }
        let accent = Theme.current.accentMid

        // Depress: quick down, springier return.
        let depress = CABasicAnimation(keyPath: "transform.scale")
        depress.fromValue = 1.0
        depress.toValue = 0.94
        depress.duration = 0.07
        depress.autoreverses = true
        depress.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        host.add(depress, forKey: "depress")

        let diagonal = sqrt(bounds.width * bounds.width + bounds.height * bounds.height)

        // Ripple from the click point.
        let ripple = CAShapeLayer()
        let r0: CGFloat = 6
        ripple.path = CGPath(ellipseIn: CGRect(x: point.x - r0, y: point.y - r0, width: r0 * 2, height: r0 * 2), transform: nil)
        ripple.fillColor = NSColor.clear.cgColor
        ripple.strokeColor = accent.withAlphaComponent(0.85).cgColor
        ripple.lineWidth = 2
        host.addSublayer(ripple)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.15
        grow.toValue = diagonal / r0 * 0.8
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.55
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.52
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        group.isRemovedOnCompletion = true
        ripple.opacity = 0
        ripple.add(group, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { ripple.removeFromSuperlayer() }

        // Three concentric rings, staggered, expanding out past the edge.
        for i in 0..<3 {
            let ring = CAShapeLayer()
            let rr = bounds.width * 0.34
            ring.path = CGPath(ellipseIn: CGRect(x: bounds.midX - rr, y: bounds.midY - rr,
                                                 width: rr * 2, height: rr * 2), transform: nil)
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = accent.withAlphaComponent(0.7).cgColor
            ring.lineWidth = 3
            ring.opacity = 0
            host.addSublayer(ring)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.55
            scale.toValue = 1.9
            let alpha = CABasicAnimation(keyPath: "opacity")
            alpha.fromValue = 0.40
            alpha.toValue = 0.0
            let width = CABasicAnimation(keyPath: "lineWidth")
            width.fromValue = 3.0
            width.toValue = 0.5
            let g = CAAnimationGroup()
            g.animations = [scale, alpha, width]
            g.duration = 0.7
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.09
            g.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            ring.add(g, forKey: "ring")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + Double(i) * 0.09) {
                ring.removeFromSuperlayer()
            }
        }

        // Glow bloom around the whole button.
        host.shadowColor = accent.cgColor
        host.shadowOffset = .zero
        let bloom = CABasicAnimation(keyPath: "shadowOpacity")
        bloom.fromValue = 0.0
        bloom.toValue = 0.85
        bloom.duration = 0.14
        bloom.autoreverses = true
        bloom.timingFunction = CAMediaTimingFunction(name: .easeOut)
        host.add(bloom, forKey: "bloom")
        let radius = CABasicAnimation(keyPath: "shadowRadius")
        radius.fromValue = 0.0
        radius.toValue = 20.0
        radius.duration = 0.14
        radius.autoreverses = true
        host.add(radius, forKey: "bloomRadius")
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
        let th = Theme.current
        // Slow breath so an idle panel still looks powered rather than frozen.
        let breath = 0.75 + 0.25 * sin(MotionClock.shared.phase * 1.9)
        NSGraphicsContext.saveGraphicsState()
        if isLit {
            let glow = NSShadow()
            glow.shadowColor = th.lampLit.withAlphaComponent(0.55 + 0.4 * breath)
            glow.shadowOffset = .zero
            glow.shadowBlurRadius = 8 + 5 * breath
            glow.set()
        }
        lamp.addClip()
        if isLit {
            Plastic.gradient([
                (0, th.lampLit.highlight(withLevel: 0.55) ?? th.lampLit),
                (0.6, th.lampLit),
                (1, th.lampLit.shadow(withLevel: 0.45) ?? th.lampLit),
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
                (0, th.lampLit.highlight(withLevel: 0.55) ?? th.lampLit),
                (0.6, th.lampLit),
                (1, th.lampLit.shadow(withLevel: 0.45) ?? th.lampLit),
            ])?.draw(in: inset, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

/// The brand mark tooled into the chassis.
///
/// Drawn as an engraving rather than a printed logo: a dark recess with a
/// light lip below it, which is how a stamped or etched mark actually catches
/// light on a physical faceplate. Printing it flat in accent colour would read
/// as a sticker sitting on top of the panel.
final class BrandBadgeView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 2, dy: 2)
        let side = min(inset.width, inset.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        // Lip: the same shape nudged down, catching light from above.
        NSGraphicsContext.current?.saveGraphicsState()
        let lip = KlackBrand.markPath(side: side, center: NSPoint(x: center.x, y: center.y - 1))
        NSColor(white: 1, alpha: 0.10).setFill()
        lip.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // Recess: darker than the chassis so it reads as cut into it.
        let recess = KlackBrand.markPath(side: side, center: center)
        NSColor(srgbRed: 0.03, green: 0.04, blue: 0.06, alpha: 0.72).setFill()
        recess.fill()

        // A trace of the accent so the mark still carries brand colour without
        // looking applied on top.
        Theme.current.accentMid.withAlphaComponent(0.12).setFill()
        recess.fill()
    }
}
