import AppKit
import QuartzCore

final class WelcomeArtworkView: NSView {
    static let stageSize = NSSize(width: 176, height: 106)
    static let iconSize: CGFloat = 96

    private let iconImageView: NSImageView = {
        let imageView = NSImageView(image: NSApp.applicationIconImage)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        return imageView
    }()

    private let pulseRingLayer = CAShapeLayer()
    private let iconShadowLayer = CALayer()
    private let sheenContainerLayer = CALayer()
    private let sheenLayer = CAGradientLayer()
    private let vectorHostLayer = CALayer()

    private var squircleLayer: CAGradientLayer?
    private var blueLayers: [CAShapeLayer] = []
    private var purpleLayers: [CAShapeLayer] = []
    private var dotContainerLayer: CALayer?

    private var reduceMotion: Bool
    private var hasPlayedBirth = false
    private var stopped = false
    private var retireWorkItem: DispatchWorkItem?

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: NSRect(origin: .zero, size: Self.stageSize))
        wantsLayer = true
        setAccessibilityElement(false)

        // Celebratory emerald halo ring behind the icon (hidden until authorization succeeds).
        pulseRingLayer.fillColor = nil
        pulseRingLayer.lineWidth = 2.5
        pulseRingLayer.opacity = 0
        layer?.addSublayer(pulseRingLayer)

        // Single explicit-path elevation shadow shared across both vector and static icon states
        // so the shadow never doubles during crossfade and stays GPU-fast during 120Hz flight.
        layer?.addSublayer(iconShadowLayer)

        addSubview(iconImageView)
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Vector birth layer aligned directly over iconImageView; hidden at rest.
        vectorHostLayer.isHidden = true
        layer?.addSublayer(vectorHostLayer)

        // Diagonal Liquid-Glass specular sheen masked to the icon squircle silhouette.
        sheenContainerLayer.masksToBounds = true
        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(0.34).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        sheenLayer.locations = [0.0, 0.5, 1.0]
        sheenLayer.startPoint = CGPoint(x: 0.0, y: 0.25)
        sheenLayer.endPoint = CGPoint(x: 1.0, y: 0.75)
        sheenLayer.opacity = 0
        sheenContainerLayer.addSublayer(sheenLayer)
        layer?.addSublayer(sheenContainerLayer)

        buildVectorLogoLayers()
        applyIconShadow()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit {
        stop()
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        applyIconShadow()
    }

    override func layout() {
        super.layout()
        let iconRect = CGRect(
            x: round((bounds.width - Self.iconSize) * 0.5),
            y: round((bounds.height - Self.iconSize) * 0.5),
            width: Self.iconSize,
            height: Self.iconSize
        )
        let s = Self.iconSize / 512.0
        let squircleRectInIcon = CGRect(x: 68 * s, y: (512 - 439) * s, width: 375 * s, height: 374 * s)
        let squircleRect = squircleRectInIcon.offsetBy(dx: iconRect.minX, dy: iconRect.minY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        vectorHostLayer.frame = iconRect

        iconShadowLayer.frame = bounds
        iconShadowLayer.shadowPath = CGPath(
            roundedRect: squircleRect,
            cornerWidth: 85 * s,
            cornerHeight: 85 * s,
            transform: nil
        )

        sheenContainerLayer.frame = squircleRect
        WelcomeAppearance.applyContinuousCorners(to: sheenContainerLayer, radius: 85 * s)
        sheenLayer.frame = CGRect(
            x: -squircleRect.width * 0.85,
            y: -squircleRect.height * 0.2,
            width: squircleRect.width * 0.65,
            height: squircleRect.height * 1.4
        )

        let ringRect = squircleRect.insetBy(dx: -4, dy: -4)
        pulseRingLayer.frame = bounds
        pulseRingLayer.path = CGPath(
            roundedRect: ringRect,
            cornerWidth: 85 * s + 4,
            cornerHeight: 85 * s + 4,
            transform: nil
        )
        CATransaction.commit()
    }

    func setReducedMotion(_ value: Bool) {
        guard reduceMotion != value else { return }
        reduceMotion = value
        if value {
            snapToSettledIcon()
        }
    }

    func updatePlayback() {
        guard !stopped, let window, window.isVisible, !window.isMiniaturized else { return }
        if reduceMotion {
            snapToSettledIcon()
        }
    }

    /// Two-act Xcode-style hero intro:
    /// Act 1: Large vector icon draws itself dead-center in the window.
    /// Act 2: Glides smoothly up into the resting 96pt header slot with a zero-overshoot S-curve,
    ///        then imperceptibly hands off to the native Retina AppIcon once stationary.
    func playHeroEntrance(
        fromCenterOffsetY dy: CGFloat,
        heroScale: CGFloat = 2.65,
        flightDelay: CFTimeInterval = 1.52,
        flightDuration: CFTimeInterval = 1.06
    ) {
        guard !stopped, !hasPlayedBirth else { return }
        if reduceMotion {
            hasPlayedBirth = true
            snapToSettledIcon()
            return
        }
        hasPlayedBirth = true
        layoutSubtreeIfNeeded()
        updateVectorBackingScale(multiplier: heroScale)
        playVectorBirthAnimation(
            fromCenterOffsetY: dy,
            heroScale: heroScale,
            flightDelay: flightDelay,
            flightDuration: flightDuration
        )
    }

    func triggerSuccessPulse() {
        guard !stopped, !reduceMotion else { return }
        snapToSettledIcon()

        let speed = WelcomeMotion.speedMultiplier
        let dark = WelcomeAppearance.isDark(in: self)
        let emerald = WelcomeAppearance.emeraldGreen(dark: dark)

        // 1. Gentle centered spring pop on the icon.
        if let iconLayer = iconImageView.layer {
            let pop = WelcomeMotion.spring(keyPath: "transform", mass: 0.9, stiffness: 210, damping: 16)
            pop.fromValue = NSValue(caTransform3D: WelcomeMotion.centeredTransform(scale: 1.07, dy: 0, in: iconImageView.bounds))
            pop.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            iconLayer.add(pop, forKey: "welcome.iconSuccessPop")
        }

        // 2. Expanding emerald squircle halo ring behind the icon.
        pulseRingLayer.removeAllAnimations()
        pulseRingLayer.strokeColor = emerald.withAlphaComponent(dark ? 0.85 : 0.72).cgColor
        pulseRingLayer.shadowColor = emerald.cgColor
        pulseRingLayer.shadowOpacity = 0.85
        pulseRingLayer.shadowRadius = 8
        pulseRingLayer.shadowOffset = .zero

        let ringScale = CABasicAnimation(keyPath: "transform")
        ringScale.fromValue = NSValue(caTransform3D: WelcomeMotion.centeredTransform(scale: 0.96, dy: 0, for: pulseRingLayer))
        ringScale.toValue = NSValue(caTransform3D: WelcomeMotion.centeredTransform(scale: 1.32, dy: 0, for: pulseRingLayer))
        ringScale.duration = 1.15
        ringScale.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.30, 1.0)
        ringScale.speed = speed

        let ringFade = CAKeyframeAnimation(keyPath: "opacity")
        ringFade.values = [0.0, 0.78, 0.0]
        ringFade.keyTimes = [0.0, 0.18, 1.0]
        ringFade.duration = 1.15
        ringFade.speed = speed

        pulseRingLayer.add(ringScale, forKey: "welcome.pulseScale")
        pulseRingLayer.add(ringFade, forKey: "welcome.pulseOpacity")

        // 3. Celebratory emerald-tinted Liquid-Glass specular sweep across the icon.
        playSheenSweep(delay: 0.06, duration: 1.05, tint: emerald.blended(withFraction: 0.55, of: .white) ?? .white)
    }

    func stop() {
        stopped = true
        retireWorkItem?.cancel()
        retireWorkItem = nil
        layer?.removeAllAnimations()
        iconShadowLayer.removeAllAnimations()
        iconImageView.layer?.removeAllAnimations()
        vectorHostLayer.removeAllAnimations()
        vectorHostLayer.sublayers?.forEach { $0.removeAllAnimations() }
        sheenLayer.removeAllAnimations()
        pulseRingLayer.removeAllAnimations()
    }

    // MARK: - Pure Core Animation Vector Logo Construction (Measured from AppIcon)

    private func buildVectorLogoLayers() {
        let size = Self.iconSize
        let s = size / 512.0
        let rootBounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))

        // 1. Dark obsidian continuous squircle card matching Base-512.png exact bounds.
        let sqRect = CGRect(x: 68 * s, y: (512 - 439) * s, width: 375 * s, height: 374 * s)
        let squircle = CAGradientLayer()
        squircle.frame = sqRect
        WelcomeAppearance.applyContinuousCorners(to: squircle, radius: 85 * s)
        squircle.colors = [
            NSColor(srgbRed: 0.08, green: 0.09, blue: 0.16, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.04, green: 0.04, blue: 0.09, alpha: 1.0).cgColor
        ]
        squircle.startPoint = CGPoint(x: 0.5, y: 1.0)
        squircle.endPoint = CGPoint(x: 0.5, y: 0.0)
        squircle.borderWidth = max(0.5, 2.0 * s)
        squircle.borderColor = NSColor(srgbRed: 0.32, green: 0.36, blue: 0.52, alpha: 0.26).cgColor
        vectorHostLayer.addSublayer(squircle)
        squircleLayer = squircle

        // 2. Outer 299-degree Electric Blue 3D neon arc (extruded depth + luminous rim + electric core).
        let blueTopPath = Self.ellipseArcPath(size: size, cx: 256, cyTop: 243, rx: 122, ry: 109, startDegTop: 163, sweepDegClockwiseTop: 299)
        let blueDepthPath = Self.ellipseArcPath(size: size, cx: 256, cyTop: 263, rx: 122, ry: 109, startDegTop: 163, sweepDegClockwiseTop: 299)

        let blueDepth = makeStrokeLayer(
            frame: rootBounds,
            path: blueDepthPath,
            color: NSColor(srgbRed: 0.16, green: 0.36, blue: 0.92, alpha: 0.92),
            lineWidth: 36 * s,
            glowColor: NSColor(srgbRed: 0.14, green: 0.54, blue: 1.0, alpha: 1.0),
            glowOpacity: 0.85,
            glowRadius: 24 * s
        )
        let blueRim = makeStrokeLayer(
            frame: rootBounds,
            path: blueTopPath,
            color: NSColor(srgbRed: 0.45, green: 0.86, blue: 1.0, alpha: 0.95),
            lineWidth: 36 * s,
            glowColor: NSColor(srgbRed: 0.20, green: 0.72, blue: 1.0, alpha: 1.0),
            glowOpacity: 0.80,
            glowRadius: 14 * s
        )
        let blueCore = makeStrokeLayer(
            frame: rootBounds,
            path: blueTopPath,
            color: NSColor(srgbRed: 0.22, green: 0.50, blue: 0.94, alpha: 1.0),
            lineWidth: 26 * s
        )
        blueLayers = [blueDepth, blueRim, blueCore]
        blueLayers.forEach(vectorHostLayer.addSublayer)

        // 3. Inner Orchid Purple 3D torus ring (split into two 180-degree arcs so full 360° never collapses).
        let purpleTopPath = Self.ellipseArcPath(size: size, cx: 255, cyTop: 241, rx: 61, ry: 52, startDegTop: 270, sweepDegClockwiseTop: 360)
        let purpleDepthPath = Self.ellipseArcPath(size: size, cx: 255, cyTop: 263, rx: 61, ry: 52, startDegTop: 270, sweepDegClockwiseTop: 360)

        let purpleDepth = makeStrokeLayer(
            frame: rootBounds,
            path: purpleDepthPath,
            color: NSColor(srgbRed: 0.50, green: 0.18, blue: 0.90, alpha: 0.94),
            lineWidth: 26 * s,
            glowColor: NSColor(srgbRed: 0.78, green: 0.26, blue: 1.0, alpha: 1.0),
            glowOpacity: 0.85,
            glowRadius: 20 * s
        )
        let purpleRim = makeStrokeLayer(
            frame: rootBounds,
            path: purpleTopPath,
            color: NSColor(srgbRed: 0.94, green: 0.62, blue: 0.98, alpha: 0.96),
            lineWidth: 26 * s,
            glowColor: NSColor(srgbRed: 0.85, green: 0.35, blue: 1.0, alpha: 1.0),
            glowOpacity: 0.72,
            glowRadius: 12 * s
        )
        let purpleCore = makeStrokeLayer(
            frame: rootBounds,
            path: purpleTopPath,
            color: NSColor(srgbRed: 0.72, green: 0.25, blue: 0.93, alpha: 1.0),
            lineWidth: 18 * s
        )
        purpleLayers = [purpleDepth, purpleRim, purpleCore]
        purpleLayers.forEach(vectorHostLayer.addSublayer)

        // 4. Bottom-left Luminous Mint 3D puck grouped into one container so top + depth scale cleanly together.
        let dotGroupRect = CGRect(x: (164 - 23) * s, y: (512 - 355 - 21) * s, width: 46 * s, height: 58 * s)
        let dotGroup = CALayer()
        dotGroup.frame = dotGroupRect

        let dotSize = CGSize(width: 46 * s, height: 42 * s)
        let dotDepth = CAShapeLayer()
        dotDepth.frame = CGRect(origin: .zero, size: dotSize)
        dotDepth.path = CGPath(ellipseIn: CGRect(origin: .zero, size: dotSize), transform: nil)
        dotDepth.fillColor = NSColor(srgbRed: 0.28, green: 0.82, blue: 0.64, alpha: 0.95).cgColor
        dotDepth.shadowColor = NSColor(srgbRed: 0.32, green: 0.98, blue: 0.74, alpha: 1.0).cgColor
        dotDepth.shadowOpacity = 0.92
        dotDepth.shadowRadius = 18 * s
        dotDepth.shadowOffset = .zero

        let dotTop = CAShapeLayer()
        dotTop.frame = CGRect(origin: CGPoint(x: 0, y: 16 * s), size: dotSize)
        dotTop.path = CGPath(ellipseIn: CGRect(origin: .zero, size: dotSize), transform: nil)
        dotTop.fillColor = NSColor(srgbRed: 0.48, green: 0.98, blue: 0.80, alpha: 1.0).cgColor

        dotGroup.addSublayer(dotDepth)
        dotGroup.addSublayer(dotTop)
        vectorHostLayer.addSublayer(dotGroup)
        dotContainerLayer = dotGroup
    }

    private func updateVectorBackingScale(multiplier: CGFloat) {
        let baseScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let targetScale = baseScale * max(1.0, multiplier)
        func applyScale(to layer: CALayer) {
            layer.contentsScale = targetScale
            layer.sublayers?.forEach(applyScale)
        }
        applyScale(to: vectorHostLayer)
    }

    private func makeStrokeLayer(
        frame: CGRect,
        path: CGPath,
        color: NSColor,
        lineWidth: CGFloat,
        glowColor: NSColor? = nil,
        glowOpacity: Float = 0,
        glowRadius: CGFloat = 0
    ) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.frame = frame
        shape.path = path
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        shape.lineWidth = lineWidth
        shape.lineCap = .round
        if let glowColor {
            shape.shadowColor = glowColor.cgColor
            shape.shadowOpacity = glowOpacity
            shape.shadowRadius = glowRadius
            shape.shadowOffset = .zero
        }
        return shape
    }

    private static func ellipseArcPath(
        size: CGFloat,
        cx: CGFloat,
        cyTop: CGFloat,
        rx: CGFloat,
        ry: CGFloat,
        startDegTop: CGFloat,
        sweepDegClockwiseTop: CGFloat
    ) -> CGPath {
        let s = size / 512.0
        let center = CGPoint(x: cx * s, y: (512 - cyTop) * s)
        var t = CGAffineTransform(translationX: center.x, y: center.y)
        t = t.scaledBy(x: 1.0, y: ry / rx)
        let path = CGMutablePath()
        let half = sweepDegClockwiseTop / 2.0
        let a0 = -startDegTop * .pi / 180.0
        let a1 = -(startDegTop + half) * .pi / 180.0
        let a2 = -(startDegTop + sweepDegClockwiseTop) * .pi / 180.0
        path.addArc(center: .zero, radius: rx * s, startAngle: a0, endAngle: a1, clockwise: true, transform: t)
        path.addArc(center: .zero, radius: rx * s, startAngle: a1, endAngle: a2, clockwise: true, transform: t)
        return path
    }

    // MARK: - Two-Act Entrance Choreography

    private func playVectorBirthAnimation(
        fromCenterOffsetY dy: CGFloat,
        heroScale: CGFloat,
        flightDelay: CFTimeInterval,
        flightDuration: CFTimeInterval
    ) {
        let now = CACurrentMediaTime()
        let slowScale = 1.0 / max(WelcomeMotion.previewSlowFactor, 0.05)
        let speed = WelcomeMotion.speedMultiplier
        let smoothCurve = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        let flightCurve = CAMediaTimingFunction(controlPoints: 0.42, 0.0, 0.18, 1.0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        vectorHostLayer.isHidden = false
        vectorHostLayer.opacity = 1
        iconImageView.layer?.opacity = 1
        iconShadowLayer.opacity = 1
        CATransaction.commit()

        // Act 1 -> Act 2 Hero Flight:
        // Hold centered & large (~2.65x) during Act 1 via fillMode = .backwards, then glide smoothly
        // up to 96pt with a zero-overshoot S-curve (eliminates initial velocity jerk and bounce).
        if let rootLayer = layer {
            let heroTransform = WelcomeMotion.centeredTransform(scale: heroScale, dy: dy, for: rootLayer)
            let flight = CABasicAnimation(keyPath: "transform")
            flight.fromValue = NSValue(caTransform3D: heroTransform)
            flight.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            flight.duration = flightDuration
            flight.beginTime = now + flightDelay * slowScale
            flight.fillMode = .backwards
            flight.timingFunction = flightCurve
            flight.speed = speed
            rootLayer.add(flight, forKey: "welcome.heroFlight")
        }

        // Fade the shared squircle shadow cleanly alongside the dark squircle card.
        let shadowFade = CABasicAnimation(keyPath: "opacity")
        shadowFade.fromValue = 0.0
        shadowFade.toValue = 1.0
        shadowFade.duration = 0.44
        shadowFade.beginTime = now
        shadowFade.fillMode = .backwards
        shadowFade.timingFunction = smoothCurve
        shadowFade.speed = speed
        iconShadowLayer.add(shadowFade, forKey: "welcome.shadowFade")

        // Act 1a: Dark obsidian squircle card softly blooms at center stage (0.00s -> 0.48s).
        if let squircleLayer {
            let sqFade = CABasicAnimation(keyPath: "opacity")
            sqFade.fromValue = 0.0
            sqFade.toValue = 1.0
            sqFade.duration = 0.44
            sqFade.beginTime = now
            sqFade.fillMode = .backwards
            sqFade.timingFunction = smoothCurve
            sqFade.speed = speed

            let sqPop = WelcomeMotion.spring(keyPath: "transform", mass: 1.1, stiffness: 105, damping: 17)
            sqPop.fromValue = NSValue(caTransform3D: WelcomeMotion.centeredTransform(scale: 0.84, dy: -4, for: squircleLayer))
            sqPop.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            sqPop.beginTime = now
            sqPop.fillMode = .backwards

            squircleLayer.add(sqFade, forKey: "welcome.sqFade")
            squircleLayer.add(sqPop, forKey: "welcome.sqPop")
        }

        // Act 1b: Bottom-left luminous mint puck springs in concentrically around its own center (0.16s -> 0.70s).
        let dotStart = now + 0.16 * slowScale
        if let dotGroup = dotContainerLayer {
            let dotFade = CABasicAnimation(keyPath: "opacity")
            dotFade.fromValue = 0.0
            dotFade.toValue = 1.0
            dotFade.duration = 0.30
            dotFade.beginTime = dotStart
            dotFade.fillMode = .backwards
            dotFade.timingFunction = smoothCurve
            dotFade.speed = speed

            let dotSpring = WelcomeMotion.spring(keyPath: "transform", mass: 0.85, stiffness: 175, damping: 14)
            dotSpring.fromValue = NSValue(caTransform3D: WelcomeMotion.centeredTransform(scale: 0.08, dy: 0, for: dotGroup))
            dotSpring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            dotSpring.beginTime = dotStart
            dotSpring.fillMode = .backwards

            dotGroup.add(dotFade, forKey: "welcome.dotFade")
            dotGroup.add(dotSpring, forKey: "welcome.dotSpring")
        }

        // Act 1c: Outer Electric Blue 299° arc smoothly draws clockwise (0.26s -> 1.24s).
        let blueStart = now + 0.26 * slowScale
        for shape in blueLayers {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0.0
            draw.toValue = 1.0
            draw.duration = 0.98
            draw.beginTime = blueStart
            draw.fillMode = .backwards
            draw.timingFunction = smoothCurve
            draw.speed = speed

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = 0.22
            fade.beginTime = blueStart
            fade.fillMode = .backwards
            fade.speed = speed

            shape.add(draw, forKey: "welcome.blueDraw")
            shape.add(fade, forKey: "welcome.blueFade")
        }

        // Act 1d: Inner Orchid Purple ring traces 360° while blooming concentrically around its exact center (0.50s -> 1.38s).
        let purpleStart = now + 0.50 * slowScale
        let s = Self.iconSize / 512.0
        let purpleCenter = CGPoint(x: 255 * s, y: (512 - 252) * s)
        for shape in purpleLayers {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0.0
            draw.toValue = 1.0
            draw.duration = 0.88
            draw.beginTime = purpleStart
            draw.fillMode = .backwards
            draw.timingFunction = smoothCurve
            draw.speed = speed

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = 0.24
            fade.beginTime = purpleStart
            fade.fillMode = .backwards
            fade.speed = speed

            let bloom = WelcomeMotion.spring(keyPath: "transform", mass: 1.05, stiffness: 120, damping: 16)
            bloom.fromValue = NSValue(caTransform3D: WelcomeMotion.centeredTransform(scale: 0.84, dy: 0, for: shape, pivot: purpleCenter))
            bloom.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            bloom.beginTime = purpleStart
            bloom.fillMode = .backwards

            shape.add(draw, forKey: "welcome.purpleDraw")
            shape.add(fade, forKey: "welcome.purpleFade")
            shape.add(bloom, forKey: "welcome.purpleBloom")
        }

        // Act 3 stationary handoff: Keep razor-sharp supersampled vector layers throughout the
        // ENTIRE flight, then crossfade to the native Retina AppIcon only once completely landed
        // so there is zero mid-motion texture snap or shadow shift.
        let landedAt = flightDelay + flightDuration
        let crossfadeStart = now + (landedAt + 0.04) * slowScale
        if let iconLayer = iconImageView.layer {
            let realFadeIn = CABasicAnimation(keyPath: "opacity")
            realFadeIn.fromValue = 0.0
            realFadeIn.toValue = 1.0
            realFadeIn.duration = 0.44
            realFadeIn.beginTime = crossfadeStart
            realFadeIn.fillMode = .backwards
            realFadeIn.timingFunction = smoothCurve
            realFadeIn.speed = speed
            iconLayer.add(realFadeIn, forKey: "welcome.realIconReveal")
        }

        let vectorFadeOut = CABasicAnimation(keyPath: "opacity")
        vectorFadeOut.fromValue = 1.0
        vectorFadeOut.toValue = 0.0
        vectorFadeOut.duration = 0.38
        vectorFadeOut.beginTime = crossfadeStart + 0.14 * slowScale
        vectorFadeOut.fillMode = .forwards
        vectorFadeOut.isRemovedOnCompletion = false
        vectorFadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)
        vectorFadeOut.speed = speed
        vectorHostLayer.add(vectorFadeOut, forKey: "welcome.vectorFadeOut")

        playSheenSweep(delay: landedAt + 0.16, duration: 1.15, tint: .white)

        let retire = DispatchWorkItem { [weak self] in
            self?.snapToSettledIcon()
        }
        retireWorkItem?.cancel()
        retireWorkItem = retire
        DispatchQueue.main.asyncAfter(deadline: .now() + (landedAt + 1.45) * slowScale, execute: retire)
    }

    private func playSheenSweep(delay: CFTimeInterval, duration: CFTimeInterval, tint: NSColor) {
        guard !reduceMotion, sheenContainerLayer.bounds.width > 0 else { return }
        sheenLayer.removeAllAnimations()
        sheenLayer.colors = [
            tint.withAlphaComponent(0.0).cgColor,
            tint.withAlphaComponent(0.32).cgColor,
            tint.withAlphaComponent(0.0).cgColor
        ]
        let start = CACurrentMediaTime() + delay / max(WelcomeMotion.previewSlowFactor, 0.05)
        let width = sheenContainerLayer.bounds.width

        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -width * 0.55
        move.toValue = width * 1.55
        move.duration = duration
        move.beginTime = start
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
        move.speed = WelcomeMotion.speedMultiplier

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.20, 0.72, 1.0]
        fade.duration = duration
        fade.beginTime = start
        fade.speed = WelcomeMotion.speedMultiplier

        sheenLayer.add(move, forKey: "welcome.iconSheenMove")
        sheenLayer.add(fade, forKey: "welcome.iconSheenOpacity")
    }

    private func snapToSettledIcon() {
        retireWorkItem?.cancel()
        retireWorkItem = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.removeAnimation(forKey: "welcome.heroFlight")
        iconShadowLayer.removeAnimation(forKey: "welcome.shadowFade")
        iconShadowLayer.opacity = 1
        vectorHostLayer.removeAllAnimations()
        vectorHostLayer.sublayers?.forEach { $0.removeAllAnimations() }
        vectorHostLayer.isHidden = true
        vectorHostLayer.opacity = 0
        iconImageView.layer?.removeAnimation(forKey: "welcome.realIconReveal")
        iconImageView.layer?.opacity = 1
        CATransaction.commit()
    }

    private func applyIconShadow() {
        let isDark = WelcomeAppearance.isDark(in: self)
        iconShadowLayer.shadowColor = NSColor.black.cgColor
        iconShadowLayer.shadowOpacity = isDark ? 0.42 : 0.22
        iconShadowLayer.shadowRadius = isDark ? 14 : 11
        iconShadowLayer.shadowOffset = CGSize(width: 0, height: -5)
    }
}
