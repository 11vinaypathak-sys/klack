import Cocoa

/// A labeled slider embedded directly inside an NSMenuItem — the same
/// pattern macOS itself uses for the volume/brightness sliders in its own
/// menu bar. AppKit dispatches drag events straight to this view's NSSlider
/// without closing the enclosing menu, so it behaves like a real live mixer.
final class SliderMenuItemView: NSView {
    let slider: NSSlider
    private let valueLabel: NSTextField
    private let formatter: (Float) -> String

    init(title: String, value: Float, min: Float, max: Float,
         formatter: @escaping (Float) -> String, target: AnyObject, action: Selector) {
        self.formatter = formatter

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)

        valueLabel = NSTextField(labelWithString: formatter(value))
        valueLabel.font = .systemFont(ofSize: 10)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        let topRow = NSStackView(views: [titleLabel, valueLabel])
        topRow.orientation = .horizontal
        topRow.distribution = .equalSpacing
        topRow.translatesAutoresizingMaskIntoConstraints = false

        slider = NSSlider(value: Double(value), minValue: Double(min), maxValue: Double(max), target: target, action: action)
        slider.isContinuous = true

        let stack = NSStackView(views: [topRow, slider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: NSRect(x: 0, y: 0, width: 232, height: 42))
        autoresizingMask = [.width]

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func refreshValueLabel() {
        valueLabel.stringValue = formatter(Float(slider.doubleValue))
    }
}
