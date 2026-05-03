import AppKit

// MARK: - RoundedView

/// Layer-backed rounded rectangle. Holds NSColors (which may be dynamic) and
/// re-resolves them inside `updateLayer()` so colors update when the effective
/// appearance changes.
final class RoundedView: NSView {
    var cornerRadius: CGFloat = 12 { didSet { needsDisplay = true } }
    var borderWidth: CGFloat = 0   { didSet { needsDisplay = true } }
    var borderColor: NSColor = .clear { didSet { needsDisplay = true } }
    var fillColor: NSColor = .clear   { didSet { needsDisplay = true } }
    var gradientTop: NSColor?
    var gradientBottom: NSColor?

    private var gradient: CAGradientLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError() }

    func setGradient(top: NSColor, bottom: NSColor) {
        gradientTop = top
        gradientBottom = bottom
        if gradient == nil {
            let g = CAGradientLayer()
            g.startPoint = CGPoint(x: 0, y: 0)
            g.endPoint = CGPoint(x: 1, y: 1)
            g.cornerCurve = .continuous
            layer?.insertSublayer(g, at: 0)
            gradient = g
        }
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = borderWidth
        layer?.borderColor = borderColor.cgColor
        layer?.backgroundColor = fillColor.cgColor
        if let g = gradient, let top = gradientTop, let bot = gradientBottom {
            g.colors = [top.cgColor, bot.cgColor]
            g.frame = bounds
            g.cornerRadius = cornerRadius
        }
    }

    override func layout() {
        super.layout()
        gradient?.frame = bounds
        gradient?.cornerRadius = cornerRadius
    }
}

// MARK: - Pill

final class Pill: NSView {
    private let label = NSTextField(labelWithString: "")
    private let tint: NSColor
    private let softBg: NSColor

    init(text: String, color: NSColor, softBg: NSColor) {
        self.tint = color
        self.softBg = softBg
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.alignment = .center
        label.attributedStringValue = NSAttributedString(
            string: text.uppercased(),
            attributes: [.kern: 0.6,
                         .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                         .foregroundColor: color]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = softBg.cgColor
        layer?.borderColor = tint.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1
    }
}

// MARK: - IconButton

final class IconButton: NSButton {
    init(symbol: String, accessibility: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(cfg)
        self.imagePosition = .imageOnly
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.setButtonType(.momentaryChange)
        self.focusRingType = .none
        self.refusesFirstResponder = true
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.layer?.cornerCurve = .continuous
        self.layer?.borderWidth = 1
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 30),
            self.heightAnchor.constraint(equalToConstant: 30),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canBecomeKeyView: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override var intrinsicContentSize: NSSize { NSSize(width: 30, height: 30) }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderColor = Theme.cardBorder.cgColor
        layer?.backgroundColor = Theme.cardBg.cgColor
        contentTintColor = Theme.textPrimary
    }
}

// MARK: - TabButton

final class TabButton: NSButton {
    var isSelectedTab: Bool = false { didSet { needsDisplay = true; restyleTitle() } }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.setButtonType(.momentaryChange)
        self.focusRingType = .none
        self.refusesFirstResponder = true
        self.wantsLayer = true
        self.layer?.cornerRadius = 16
        self.layer?.cornerCurve = .continuous
        self.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        restyleTitle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKeyView: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? Theme.font(13, .medium)]
        let s = (title as NSString).size(withAttributes: attrs)
        return NSSize(width: ceil(s.width) + 32, height: 32)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        if isSelectedTab {
            layer?.backgroundColor = Theme.cardBg.cgColor
            layer?.borderWidth = 1.5
            layer?.borderColor = Theme.accentBlue.cgColor
        } else {
            layer?.backgroundColor = Theme.tabInactiveBg.cgColor
            layer?.borderWidth = 0
        }
        restyleTitle()
    }

    private func restyleTitle() {
        let color: NSColor = isSelectedTab ? Theme.accentBlue : Theme.textSecondary
        let weight: NSFont.Weight = isSelectedTab ? .semibold : .medium
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: weight),
                .foregroundColor: color,
            ]
        )
    }
}

// MARK: - SoftButton

final class SoftButton: NSButton {
    private var baseTitle: String = ""
    private var displayTitle: String = ""
    private var revertTimer: Timer?
    private var flashing: Bool = false
    var tint: NSColor = Theme.accentBlue

    init(title: String) {
        super.init(frame: .zero)
        self.baseTitle = title
        self.displayTitle = title
        self.title = title
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.setButtonType(.momentaryChange)
        self.focusRingType = .none
        self.refusesFirstResponder = true
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.layer?.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKeyView: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
        let s = (displayTitle as NSString).size(withAttributes: attrs)
        return NSSize(width: ceil(s.width) + 24, height: 30)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        if !isEnabled {
            layer?.backgroundColor = Theme.tabInactiveBg.cgColor
            attributedTitle = NSAttributedString(
                string: displayTitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: Theme.textTertiary,
                ]
            )
            return
        }
        if flashing {
            layer?.backgroundColor = Theme.paidGreenSoft.cgColor
            attributedTitle = NSAttributedString(
                string: displayTitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: Theme.paidGreen,
                ]
            )
        } else {
            layer?.backgroundColor = Theme.accentBlueSoft.cgColor
            attributedTitle = NSAttributedString(
                string: displayTitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: tint,
                ]
            )
        }
    }

    override var isEnabled: Bool { didSet { needsDisplay = true } }

    func flashCopied() {
        revertTimer?.invalidate()
        flashing = true
        displayTitle = "Copied!"
        invalidateIntrinsicContentSize()
        needsDisplay = true
        revertTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.flashing = false
            self.displayTitle = self.baseTitle
            self.invalidateIntrinsicContentSize()
            self.needsDisplay = true
        }
    }
}

// MARK: - FlippedStackView

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

// MARK: - SkeletonView

final class SkeletonView: NSView {
    init(height: CGFloat = 14, cornerRadius: CGFloat = 6, width: CGFloat? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        if let w = width { widthAnchor.constraint(equalToConstant: w).isActive = true }
        startPulse()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.skeletonBg.cgColor
    }

    private func startPulse() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.45
        anim.duration = 0.9
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(anim, forKey: "pulse")
    }
}

// MARK: - AppearanceAwareView

/// Plain layer-backed view that updates its background color on appearance
/// change. Used for the popover root and the header strip.
final class AppearanceAwareView: NSView {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
    }
}

// MARK: - Helpers

extension NSView {
    func pin(to other: NSView, inset: NSEdgeInsets = NSEdgeInsetsZero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: inset.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -inset.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: inset.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -inset.bottom),
        ])
    }
}

func makeLabel(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.textColor = color
    l.alignment = alignment
    l.lineBreakMode = .byTruncatingTail
    return l
}

func makeKernLabel(_ text: String, font: NSFont, color: NSColor, kern: CGFloat) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.textColor = color
    l.attributedStringValue = NSAttributedString(
        string: text,
        attributes: [.font: font, .foregroundColor: color, .kern: kern]
    )
    return l
}
