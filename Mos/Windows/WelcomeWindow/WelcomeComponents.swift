import Cocoa
import QuartzCore

// MARK: - Appearance & Motion Helpers

enum WelcomeAppearance {
    static var isLiquidGlassOS: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        )
    }

    static func isDark(in view: NSView) -> Bool {
        if #available(macOS 10.14, *) {
            return view.effectiveAppearance.bestMatch(from: [
                .darkAqua,
                .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark,
                .aqua,
                .vibrantLight
            ]).map {
                $0 == .darkAqua || $0 == .vibrantDark ||
                $0 == .accessibilityHighContrastDarkAqua ||
                $0 == .accessibilityHighContrastVibrantDark
            } ?? false
        }
        return Utils.isDarkMode(for: view)
    }

    static func withCurrentAppearance(of view: NSView, _ body: () -> Void) {
        if #available(macOS 11.0, *) {
            view.effectiveAppearance.performAsCurrentDrawingAppearance(body)
        } else if #available(macOS 10.14, *) {
            let previous = NSAppearance.current
            NSAppearance.current = view.effectiveAppearance
            body()
            NSAppearance.current = previous
        } else {
            body()
        }
    }

    static func accentColor(in view: NSView) -> NSColor {
        if #available(macOS 10.14, *) {
            var resolved = NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
            withCurrentAppearance(of: view) {
                resolved = NSColor.controlAccentColor
            }
            return resolved
        }
        return NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
    }

    static func electricBlue(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.25, green: 0.66, blue: 1.00, alpha: 1.0)
            : NSColor(srgbRed: 0.04, green: 0.48, blue: 0.96, alpha: 1.0)
    }

    static func orchidViolet(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.74, green: 0.44, blue: 1.00, alpha: 1.0)
            : NSColor(srgbRed: 0.56, green: 0.24, blue: 0.92, alpha: 1.0)
    }

    static func emeraldGreen(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0.22, green: 0.85, blue: 0.54, alpha: 1.0)
            : NSColor(srgbRed: 0.09, green: 0.65, blue: 0.36, alpha: 1.0)
    }

    static func applyContinuousCorners(to layer: CALayer?, radius: CGFloat) {
        guard let layer else { return }
        layer.cornerRadius = radius
        if #available(macOS 10.15, *) {
            layer.cornerCurve = .continuous
        }
    }
}

enum WelcomeMotion {
    static var previewSlowFactor: Double {
        #if DEBUG
        if AppRuntime.isOnboardingPreview,
           ProcessInfo.processInfo.arguments.contains("--mos-preview-slow-animation") {
            return 0.2
        }
        #endif
        return 1.0
    }

    static var speedMultiplier: Float {
        Float(previewSlowFactor)
    }

    static func centeredTransform(scale: CGFloat, dy: CGFloat, in bounds: CGRect) -> CATransform3D {
        var t = CATransform3DIdentity
        let cx = bounds.midX
        let cy = bounds.midY
        t = CATransform3DTranslate(t, cx, cy + dy, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        return t
    }

    /// Anchor-point-aware transform that works identically on AppKit view-backed layers
    /// (`anchorPoint == (0, 0)`) and standalone Core Animation layers (`anchorPoint == (0.5, 0.5)`).
    static func centeredTransform(scale: CGFloat, dy: CGFloat, for layer: CALayer, pivot: CGPoint? = nil) -> CATransform3D {
        let bounds = layer.bounds
        let target = pivot ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let anchor = CGPoint(
            x: bounds.minX + bounds.width * layer.anchorPoint.x,
            y: bounds.minY + bounds.height * layer.anchorPoint.y
        )
        let ox = target.x - anchor.x
        let oy = target.y - anchor.y
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, ox, oy + dy, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -ox, -oy, 0)
        return t
    }

    static func spring(keyPath: String, mass: CGFloat = 0.85, stiffness: CGFloat = 240, damping: CGFloat = 23) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = mass
        animation.stiffness = stiffness
        animation.damping = damping
        animation.duration = animation.settlingDuration
        animation.speed = speedMultiplier
        return animation
    }

    /// Staggers a view's entrance using `fillMode = .backwards` so the model layer always
    /// keeps its settled visible state (`opacity = 1`, `transform = identity`).
    static func animateStaggeredEntrance(
        view: NSView,
        delay: CFTimeInterval,
        dy: CGFloat = -18,
        scale: CGFloat = 0.975,
        duration: CFTimeInterval = 1.02
    ) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let startTime = CACurrentMediaTime() + delay / max(previewSlowFactor, 0.05)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0
        opacity.duration = duration
        opacity.beginTime = startTime
        opacity.fillMode = .backwards
        opacity.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        opacity.speed = speedMultiplier

        let rise = spring(keyPath: "transform", mass: 1.4, stiffness: 52, damping: 16.5)
        rise.fromValue = NSValue(caTransform3D: centeredTransform(scale: scale, dy: dy, in: view.bounds))
        rise.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        rise.beginTime = startTime
        rise.fillMode = .backwards

        layer.add(opacity, forKey: "welcome.staggerOpacity")
        layer.add(rise, forKey: "welcome.staggerTransform")
    }
}

// MARK: - Frosted Backdrop & Atmospheric Glow

final class WelcomeBackdropView: NSView {
    private let visualEffect = NSVisualEffectView()
    private let surfaceVeilLayer = CALayer()
    private let glowLayer = CAGradientLayer()
    private let secondaryGlowLayer = CAGradientLayer()
    private let topHighlightLayer = CALayer()
    private var isAuthorized = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func setup() {
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        if #available(macOS 10.14, *) {
            visualEffect.material = .popover
        } else {
            visualEffect.material = .appearanceBased
        }
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffect)
        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let overlay = NSView()
        overlay.wantsLayer = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        glowLayer.type = .radial
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        glowLayer.locations = [0.0, 0.52, 1.0]

        secondaryGlowLayer.type = .radial
        secondaryGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        secondaryGlowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        secondaryGlowLayer.locations = [0.0, 0.55, 1.0]

        overlay.layer?.addSublayer(surfaceVeilLayer)
        overlay.layer?.addSublayer(glowLayer)
        overlay.layer?.addSublayer(secondaryGlowLayer)
        overlay.layer?.addSublayer(topHighlightLayer)

        refreshPalette(animated: false)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        refreshPalette(animated: false)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = bounds.width
        let h = bounds.height
        surfaceVeilLayer.frame = bounds
        glowLayer.frame = CGRect(x: w * 0.5 - 195, y: h - 265, width: 390, height: 290)
        secondaryGlowLayer.frame = CGRect(x: w * 0.5 - 135, y: h - 210, width: 270, height: 200)
        topHighlightLayer.frame = CGRect(x: 0, y: h - 1, width: w, height: 1)
        CATransaction.commit()
    }

    func playHeroGlowTransition(delay: CFTimeInterval, duration: CFTimeInterval = 1.06) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, bounds.height > 0 else { return }
        let now = CACurrentMediaTime()
        let slowScale = 1.0 / max(WelcomeMotion.previewSlowFactor, 0.05)
        let speed = WelcomeMotion.speedMultiplier
        let centerY = bounds.midY + 14
        let flightCurve = CAMediaTimingFunction(controlPoints: 0.42, 0.0, 0.18, 1.0)

        for target in [glowLayer, secondaryGlowLayer] {
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            fadeIn.duration = 0.55
            fadeIn.beginTime = now
            fadeIn.fillMode = .backwards
            fadeIn.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            fadeIn.speed = speed
            target.add(fadeIn, forKey: "welcome.glowFadeIn")

            let rise = CABasicAnimation(keyPath: "position.y")
            rise.fromValue = centerY
            rise.toValue = target.position.y
            rise.duration = duration
            rise.beginTime = now + delay * slowScale
            rise.fillMode = .backwards
            rise.timingFunction = flightCurve
            rise.speed = speed
            target.add(rise, forKey: "welcome.glowRise")
        }
    }

    func setAuthorized(_ authorized: Bool, animated: Bool) {
        guard isAuthorized != authorized else { return }
        isAuthorized = authorized
        refreshPalette(animated: animated)
    }

    private func refreshPalette(animated: Bool) {
        let dark = WelcomeAppearance.isDark(in: self)
        let primaryColor: NSColor
        let secondaryColor: NSColor
        if isAuthorized {
            primaryColor = WelcomeAppearance.emeraldGreen(dark: dark)
            secondaryColor = WelcomeAppearance.electricBlue(dark: dark)
        } else {
            primaryColor = WelcomeAppearance.electricBlue(dark: dark)
            secondaryColor = WelcomeAppearance.orchidViolet(dark: dark)
        }

        let primaryAlpha: CGFloat = dark ? (isAuthorized ? 0.20 : 0.17) : (isAuthorized ? 0.13 : 0.10)
        let secondaryAlpha: CGFloat = dark ? 0.12 : 0.07

        let primaryColors: [CGColor] = [
            primaryColor.withAlphaComponent(primaryAlpha).cgColor,
            primaryColor.withAlphaComponent(primaryAlpha * 0.34).cgColor,
            primaryColor.withAlphaComponent(0.0).cgColor
        ]
        let secondaryColors: [CGColor] = [
            secondaryColor.withAlphaComponent(secondaryAlpha).cgColor,
            secondaryColor.withAlphaComponent(secondaryAlpha * 0.26).cgColor,
            secondaryColor.withAlphaComponent(0.0).cgColor
        ]

        let veilColor = dark
            ? NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 0.44).cgColor
            : NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.52).cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(0.55)
        }
        surfaceVeilLayer.backgroundColor = veilColor
        glowLayer.colors = primaryColors
        secondaryGlowLayer.colors = secondaryColors
        topHighlightLayer.backgroundColor = NSColor.white.withAlphaComponent(dark ? 0.12 : 0.65).cgColor
        CATransaction.commit()
    }
}

// MARK: - Non-Interactive Static Label

final class WelcomeStaticLabel: NSTextField {
    convenience init(staticText: String = "", wrapping: Bool = false) {
        if wrapping {
            self.init(wrappingLabelWithString: staticText)
        } else {
            self.init(labelWithString: staticText)
        }
        isEditable = false
        isSelectable = false
        allowsEditingTextAttributes = false
        refusesFirstResponder = true
        isBezeled = false
        drawsBackground = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Feature Highlight Row (Bare Outline SF Symbol)

final class WelcomeFeatureRowView: NSView {
    private let symbolNames: [String]
    private let iconView = NSImageView()
    private let titleLabel = WelcomeStaticLabel(staticText: "")
    private let descriptionLabel = WelcomeStaticLabel(staticText: "", wrapping: true)

    init(symbols: [String], title: String, description: String) {
        self.symbolNames = symbols
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.allowsEditingTextAttributes = false
        titleLabel.refusesFirstResponder = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.isEditable = false
        descriptionLabel.isSelectable = false
        descriptionLabel.allowsEditingTextAttributes = false
        descriptionLabel.refusesFirstResponder = true
        descriptionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        descriptionLabel.setContentHuggingPriority(.required, for: .vertical)
        setDescriptionText(description)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: iconView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 15),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),

            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            descriptionLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        renderSymbol()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        renderSymbol()
    }

    private func renderSymbol() {
        let tint = WelcomeAppearance.accentColor(in: self)
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            for name in symbolNames {
                if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    symbol.isTemplate = true
                    iconView.image = symbol
                    iconView.contentTintColor = tint
                    return
                }
            }
        }
        // Minimal system fallback for macOS 10.13–10.15 where SF Symbols are unavailable.
        let fallback = NSImage(named: NSImage.actionTemplateName)
        fallback?.isTemplate = true
        iconView.image = fallback
        if #available(macOS 10.14, *) {
            iconView.contentTintColor = tint
        }
    }

    private func setDescriptionText(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.0
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        descriptionLabel.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
    }
}

// MARK: - Prominent Apple-Style Primary CTA Button

final class WelcomeActionButton: NSButton {
    private let gradientLayer = CAGradientLayer()
    private let hoverOverlayLayer = CALayer()
    private let innerStrokeLayer = CALayer()
    private let sheenContainerLayer = CALayer()
    private let sheenLayer = CAGradientLayer()
    private let labelField = WelcomeStaticLabel(staticText: "")
    private var displayTitle = ""
    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override var title: String {
        get { displayTitle }
        set {
            displayTitle = newValue
            labelField.stringValue = newValue
            setAccessibilityTitle(newValue)
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = ceil(labelField.intrinsicContentSize.width)
        return NSSize(width: max(248, textWidth + 56), height: 36)
    }

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 248, height: 36))
        self.target = target
        self.action = action
        super.title = ""
        isBordered = false
        imagePosition = .noImage
        setButtonType(.momentaryChange)
        keyEquivalent = "\r"
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)

        sheenContainerLayer.masksToBounds = true
        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(0.32).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        sheenLayer.locations = [0.0, 0.5, 1.0]
        sheenLayer.startPoint = CGPoint(x: 0.0, y: 0.35)
        sheenLayer.endPoint = CGPoint(x: 1.0, y: 0.65)
        sheenLayer.opacity = 0
        sheenContainerLayer.addSublayer(sheenLayer)

        layer?.addSublayer(gradientLayer)
        layer?.addSublayer(hoverOverlayLayer)
        layer?.addSublayer(sheenContainerLayer)
        layer?.addSublayer(innerStrokeLayer)

        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.font = .systemFont(ofSize: 13.5, weight: .semibold)
        labelField.textColor = .white
        labelField.alignment = .center
        labelField.lineBreakMode = .byTruncatingTail
        labelField.isEditable = false
        labelField.isSelectable = false
        labelField.isBezeled = false
        labelField.drawsBackground = false
        addSubview(labelField)
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            labelField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        self.title = title
        refreshAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var wantsUpdateLayer: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Rendered entirely by sublayers and labelField for crisp Core Animation states.
    }

    override func updateLayer() {
        super.updateLayer()
        refreshAppearance(animated: false)
    }

    override func layout() {
        super.layout()
        let isCapsule = WelcomeAppearance.isLiquidGlassOS
        let radius: CGFloat = isCapsule ? bounds.height / 2.0 : 9.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        hoverOverlayLayer.frame = bounds
        sheenContainerLayer.frame = bounds
        innerStrokeLayer.frame = bounds
        sheenLayer.frame = CGRect(x: -bounds.width * 0.6, y: 0, width: bounds.width * 0.55, height: bounds.height)

        for targetLayer in [layer, gradientLayer, hoverOverlayLayer, sheenContainerLayer, innerStrokeLayer] {
            if isCapsule {
                targetLayer?.cornerRadius = radius
                if #available(macOS 10.15, *) {
                    targetLayer?.cornerCurve = .circular
                }
            } else {
                WelcomeAppearance.applyContinuousCorners(to: targetLayer, radius: radius)
            }
        }
        gradientLayer.masksToBounds = true
        hoverOverlayLayer.masksToBounds = true
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        refreshAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        isPressed = false
        setPressedScale(false)
        refreshAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        setPressedScale(true)
        refreshAppearance(animated: true)
        super.mouseDown(with: event)
        isPressed = false
        setPressedScale(false)
        refreshAppearance(animated: true)
    }

    func playSheenSweep(delay: CFTimeInterval = 0) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, bounds.width > 0 else { return }
        sheenLayer.removeAllAnimations()
        let start = CACurrentMediaTime() + delay / max(WelcomeMotion.previewSlowFactor, 0.05)

        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -bounds.width * 0.45
        move.toValue = bounds.width * 1.45
        move.duration = 1.35
        move.beginTime = start
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
        move.speed = WelcomeMotion.speedMultiplier

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.18, 0.72, 1.0]
        fade.duration = 1.35
        fade.beginTime = start
        fade.speed = WelcomeMotion.speedMultiplier

        sheenLayer.add(move, forKey: "welcome.sheenMove")
        sheenLayer.add(fade, forKey: "welcome.sheenOpacity")
    }

    func animateStateTransition() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if let layer {
            let bounce = WelcomeMotion.spring(keyPath: "transform", mass: 0.75, stiffness: 300, damping: 18)
            bounce.fromValue = NSValue(caTransform3D: WelcomeMotion.centeredTransform(scale: 0.96, dy: 0, in: bounds))
            bounce.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            layer.add(bounce, forKey: "welcome.buttonStatePop")
        }
        playSheenSweep(delay: 0.08)
    }

    private func setPressedScale(_ pressed: Bool) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
        let targetTransform = pressed
            ? WelcomeMotion.centeredTransform(scale: 0.975, dy: 0, in: bounds)
            : CATransform3DIdentity
        let spring = WelcomeMotion.spring(keyPath: "transform", mass: 0.6, stiffness: 420, damping: 26)
        spring.fromValue = layer.presentation()?.value(forKey: "transform") ?? NSValue(caTransform3D: layer.transform)
        spring.toValue = NSValue(caTransform3D: targetTransform)
        layer.transform = targetTransform
        layer.add(spring, forKey: "welcome.buttonPress")
    }

    private func refreshAppearance(animated: Bool) {
        let dark = WelcomeAppearance.isDark(in: self)
        let accent = WelcomeAppearance.accentColor(in: self)
        let topAccent = accent.blended(withFraction: dark ? 0.14 : 0.12, of: .white) ?? accent
        let bottomAccent = accent.blended(withFraction: dark ? 0.10 : 0.08, of: .black) ?? accent

        let overlayColor: CGColor
        if isPressed {
            overlayColor = NSColor.black.withAlphaComponent(0.14).cgColor
        } else if isHovered {
            overlayColor = NSColor.white.withAlphaComponent(0.09).cgColor
        } else {
            overlayColor = NSColor.clear.cgColor
        }

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.14) }
        gradientLayer.colors = [topAccent.cgColor, bottomAccent.cgColor]
        hoverOverlayLayer.backgroundColor = overlayColor
        innerStrokeLayer.borderWidth = 0.75
        innerStrokeLayer.borderColor = NSColor.white.withAlphaComponent(dark ? 0.24 : 0.30).cgColor
        layer?.shadowColor = accent.cgColor
        layer?.shadowOpacity = isHovered ? (dark ? 0.40 : 0.32) : (dark ? 0.26 : 0.20)
        layer?.shadowRadius = isHovered ? 11 : 8
        layer?.shadowOffset = CGSize(width: 0, height: -2.5)
        CATransaction.commit()
    }
}

// MARK: - Footer Live Permission Status Strip

final class WelcomeFooterStatusView: NSView {
    enum State: Equatable {
        case required
        case waiting
        case authorized
    }

    private var currentState: State = .required
    private let indicatorDot = NSView()
    private let glyphView = NSImageView()
    private let label = WelcomeStaticLabel(staticText: "")
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        indicatorDot.wantsLayer = true
        indicatorDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicatorDot.widthAnchor.constraint(equalToConstant: 6),
            indicatorDot.heightAnchor.constraint(equalToConstant: 6)
        ])

        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.imageScaling = .scaleProportionallyDown
        NSLayoutConstraint.activate([
            glyphView.widthAnchor.constraint(equalToConstant: 13),
            glyphView.heightAnchor.constraint(equalToConstant: 13)
        ])

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 11.5, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isSelectable = false
        label.allowsEditingTextAttributes = false
        label.refusesFirstResponder = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(indicatorDot)
        stack.addArrangedSubview(glyphView)
        stack.addArrangedSubview(label)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        renderColors()
    }

    func applyState(_ state: State, animated: Bool = false) {
        let changed = currentState != state
        currentState = state
        switch state {
        case .required:
            indicatorDot.isHidden = true
            glyphView.isHidden = false
            label.stringValue = NSLocalizedString("Accessibility permission required", comment: "Welcome permission footer hint")
            label.font = .systemFont(ofSize: 11.5, weight: .regular)
        case .waiting:
            indicatorDot.isHidden = false
            glyphView.isHidden = true
            label.stringValue = NSLocalizedString("Waiting for Accessibility permission…", comment: "Welcome waiting footer status")
            label.font = .systemFont(ofSize: 11.5, weight: .regular)
        case .authorized:
            indicatorDot.isHidden = true
            glyphView.isHidden = false
            label.stringValue = NSLocalizedString("Authorized", comment: "")
            label.font = .systemFont(ofSize: 12, weight: .medium)
        }
        renderColors()
        updatePulse()

        if animated && changed, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer {
            let pop = WelcomeMotion.spring(keyPath: "transform", mass: 0.7, stiffness: 320, damping: 18)
            pop.fromValue = NSValue(caTransform3D: WelcomeMotion.centeredTransform(scale: 0.90, dy: 0, in: bounds))
            pop.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            layer.add(pop, forKey: "welcome.footerPop")
        }
    }

    func updatePulse() {
        indicatorDot.layer?.removeAnimation(forKey: "welcome.footerPulse")
        guard currentState == .waiting, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            indicatorDot.layer?.opacity = 1
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.25
        pulse.duration = 0.75
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        indicatorDot.layer?.add(pulse, forKey: "welcome.footerPulse")
    }

    func stopAnimations() {
        indicatorDot.layer?.removeAllAnimations()
    }

    private func renderColors() {
        let dark = WelcomeAppearance.isDark(in: self)
        switch currentState {
        case .required:
            let tint = NSColor.secondaryLabelColor
            label.textColor = .secondaryLabelColor
            glyphView.image = makeSymbol("lock.shield", color: tint)
            if #available(macOS 10.14, *) {
                glyphView.contentTintColor = tint
            }
        case .waiting:
            let amber = dark
                ? NSColor(srgbRed: 1.0, green: 0.68, blue: 0.24, alpha: 1.0)
                : NSColor(srgbRed: 0.84, green: 0.45, blue: 0.0, alpha: 1.0)
            indicatorDot.layer?.cornerRadius = 3
            indicatorDot.layer?.backgroundColor = amber.cgColor
            label.textColor = .secondaryLabelColor
        case .authorized:
            let emerald = WelcomeAppearance.emeraldGreen(dark: dark)
            label.textColor = emerald
            glyphView.image = makeSymbol("checkmark.circle", color: emerald)
            if #available(macOS 10.14, *) {
                glyphView.contentTintColor = emerald
            }
        }
    }

    private func makeSymbol(_ name: String, color: NSColor) -> NSImage? {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                image.isTemplate = true
                return image
            }
        }
        let fallback = NSImage(named: name == "checkmark.circle" ? NSImage.statusAvailableName : NSImage.lockLockedTemplateName)
        fallback?.isTemplate = true
        return fallback
    }
}
