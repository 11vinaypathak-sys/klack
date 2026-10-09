import Cocoa

/// The Klack brand mark, defined once and drawn everywhere.
///
/// The app icon and the in-app panel both render from this, so the mark can
/// never drift between them -- the usual failure mode where an icon gets
/// refined and the copy inside the product silently stays a version behind.
///
/// Design rules the geometry encodes:
/// - **One silhouette.** A keycap with its sound cut out as negative space,
///   rather than a cap *plus* separate decoration. The whole idea lives in a
///   single shape.
/// - **Flat, no shading.** No gradients, bevels or glows. A mark that depends
///   on lighting breaks when it's stamped in one colour, embossed, or shrunk
///   to 16px -- exactly where a brand mark has to hold.
/// - **Proportional throughout.** Every measurement is a ratio of the mark's
///   own size, so it reconstructs identically at any scale.
public enum KlackBrand {

    public static let lime = NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.42, alpha: 1)
    public static let charcoal = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.09, alpha: 1)

    /// Corner softness as a fraction of the side. 0.26 stays recognisably a
    /// keycap; push it much higher and the square starts reading as a circle
    /// once it's small.
    private static let cornerRatio: CGFloat = 0.26

    /// Bar heights as fractions of the cap. Deliberately uneven -- three bars
    /// of equal height read as a list or a menu, not as level.
    private static let barHeights: [CGFloat] = [0.32, 0.62, 0.42]
    private static let barWidthRatio: CGFloat = 0.128
    private static let barGapRatio: CGFloat = 0.108

    /// The complete mark as one even-odd path: the cap with the bars punched
    /// through it. Returning a path rather than drawing lets callers fill it
    /// in any colour, or use it as a clipping shape.
    public static func markPath(side: CGFloat, center: NSPoint) -> NSBezierPath {
        let rect = NSRect(x: center.x - side / 2, y: center.y - side / 2,
                          width: side, height: side)
        let radius = side * cornerRatio
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let barW = side * barWidthRatio
        let gap = side * barGapRatio
        let run = barW * CGFloat(barHeights.count) + gap * CGFloat(barHeights.count - 1)
        var x = center.x - run / 2

        for h in barHeights {
            let barH = side * h
            let bar = NSRect(x: x, y: center.y - barH / 2, width: barW, height: barH)
            path.append(NSBezierPath(roundedRect: bar,
                                     xRadius: barW / 2, yRadius: barW / 2))
            x += barW + gap
        }

        // Even-odd is what turns the appended bars into holes instead of
        // filled shapes stacked on top of the cap.
        path.windingRule = .evenOdd
        return path
    }

    /// Draws the mark filled in `color`, sized to fit `rect` and centred in it.
    public static func draw(in rect: NSRect, color: NSColor = KlackBrand.lime) {
        let side = min(rect.width, rect.height)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        color.setFill()
        markPath(side: side, center: center).fill()
    }
}
