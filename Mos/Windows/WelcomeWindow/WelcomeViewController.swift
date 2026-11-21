import Cocoa
import QuartzCore

struct WelcomeAuthorizationState {
    private(set) var authorized: Bool
    private var hasCelebrated = false

    init(authorized: Bool) { self.authorized = authorized }

    mutating func update(authorized value: Bool) -> Bool {
        let celebrate = value && !authorized && !hasCelebrated
        authorized = value
        if celebrate { hasCelebrated = true }
        return celebrate
    }
}

final class WelcomeViewController: NSViewController {
    private let backdropView = WelcomeBackdropView()
    private let contentStage = NSView()
    private let artwork = WelcomeArtworkView(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    private let headerStack = NSStackView()
    private let titleLabel = WelcomeStaticLabel(staticText: "", wrapping: true)
    private let taglineLabel = WelcomeStaticLabel(staticText: "", wrapping: true)
    private let featuresStack = NSStackView()
    private let featureRows: [WelcomeFeatureRowView]
    private let actionDock = NSStackView()
    private let actionButton = WelcomeActionButton(title: "", target: nil, action: nil)
    private let footerStatus = WelcomeFooterStatusView()

    private var state: WelcomeAuthorizationState
    private var hasRequestedAuthorization = false
    private var hasPlayedEntrance = false
    private var observers: [NSObjectProtocol] = []
    private var motionObserver: NSObjectProtocol?
    private var extras: NSObject?
    private var previewTimer: Timer?

    init(initialAuthorized: Bool = InputPermissionMonitor.shared.isAuthorized) {
        self.state = WelcomeAuthorizationState(authorized: initialAuthorized)
        self.featureRows = [
            WelcomeFeatureRowView(
                symbols: ["computermouse", "arrow.up.and.down.circle"],
                title: NSLocalizedString("Smooth & Natural Scrolling", comment: "Welcome feature 1 title"),
                description: NSLocalizedString("Turn stepped mouse wheels into fluid inertial scrolling with tunable speed, step size, and duration—while keeping scroll direction separate from your trackpad.", comment: "Welcome feature 1 description")
            ),
            WelcomeFeatureRowView(
                symbols: ["macwindow.on.rectangle", "square.on.square"],
                title: NSLocalizedString("Per-App Profiles & Exceptions", comment: "Welcome feature 2 title"),
                description: NSLocalizedString("Create per-application profiles or exclusion lists so browsers, code editors, games, and creative tools each feel just the way you expect.", comment: "Welcome feature 2 description")
            ),
            WelcomeFeatureRowView(
                symbols: ["cursorarrow.click.2", "command"],
                title: NSLocalizedString("Custom Mouse Buttons", comment: "Welcome feature 3 title"),
                description: NSLocalizedString("Map extra mouse buttons and modifier combinations to macOS system shortcuts, Mission Control, Space switching, or media controls for effortless navigation.", comment: "Welcome feature 3 description")
            )
        ]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: WelcomeWindowController.windowSize))
        root.wantsLayer = true
        view = root

        backdropView.translatesAutoresizingMaskIntoConstraints = false
        contentStage.translatesAutoresizingMaskIntoConstraints = false
        contentStage.wantsLayer = true

        root.addSubview(backdropView)
        root.addSubview(contentStage)

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: root.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            backdropView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            contentStage.topAnchor.constraint(equalTo: root.topAnchor),
            contentStage.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentStage.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentStage.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])

        configureHeader()
        configureFeatures()
        configureActionDock()

        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentStage.addSubview(headerStack)
        contentStage.addSubview(featuresStack)
        contentStage.addSubview(actionDock)
        contentStage.addSubview(artwork)

        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentStage.topAnchor, constant: 22),
            artwork.centerXAnchor.constraint(equalTo: contentStage.centerXAnchor),
            artwork.widthAnchor.constraint(equalToConstant: WelcomeArtworkView.stageSize.width),
            artwork.heightAnchor.constraint(equalToConstant: WelcomeArtworkView.stageSize.height),

            headerStack.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 6),
            headerStack.leadingAnchor.constraint(equalTo: contentStage.leadingAnchor, constant: 32),
            headerStack.trailingAnchor.constraint(equalTo: contentStage.trailingAnchor, constant: -32),

            featuresStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 24),
            featuresStack.leadingAnchor.constraint(equalTo: contentStage.leadingAnchor, constant: 34),
            featuresStack.trailingAnchor.constraint(equalTo: contentStage.trailingAnchor, constant: -34),

            actionDock.topAnchor.constraint(greaterThanOrEqualTo: featuresStack.bottomAnchor, constant: 20),
            actionDock.leadingAnchor.constraint(equalTo: contentStage.leadingAnchor, constant: 34),
            actionDock.trailingAnchor.constraint(equalTo: contentStage.trailingAnchor, constant: -34),
            actionDock.bottomAnchor.constraint(equalTo: contentStage.bottomAnchor, constant: -24)
        ])

        renderState(animated: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        artwork.updatePlayback()
        playEntranceAnimationIfNeeded()
        installObserversIfNeeded()
        schedulePreviewSuccessIfNeeded()
    }

    override func cancelOperation(_ sender: Any?) {
        view.window?.performClose(sender)
    }

    func updateAuthorization(_ authorized: Bool) {
        let celebrate = state.update(authorized: authorized)
        if authorized {
            hasRequestedAuthorization = false
            extras?.perform(NSSelectorFromString("closeGuide"))
        }
        renderState(animated: true)

        if celebrate {
            actionButton.animateStateTransition()
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                artwork.triggerSuccessPulse()
                loadExtras()?.perform(NSSelectorFromString("celebrate"))
            }
        }
    }

    func finish() {
        previewTimer?.invalidate()
        previewTimer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let observer = motionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        motionObserver = nil
        footerStatus.stopAnimations()
        extras?.perform(NSSelectorFromString("finish"))
        extras = nil
        artwork.stop()
    }

    deinit { finish() }

    // MARK: - View Construction

    private func configureHeader() {
        let headline = NSLocalizedString("Welcome to Mos", comment: "Welcome window title")
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .center
        titleParagraph.lineBreakMode = .byWordWrapping
        titleLabel.attributedStringValue = NSAttributedString(
            string: headline,
            attributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: NSColor.labelColor,
                .kern: -0.25,
                .paragraphStyle: titleParagraph
            ]
        )
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.allowsEditingTextAttributes = false
        titleLabel.refusesFirstResponder = true
        titleLabel.maximumNumberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let tagline = NSLocalizedString("Make every scroll flow.", comment: "Welcome headline")
        let taglineParagraph = NSMutableParagraphStyle()
        taglineParagraph.alignment = .center
        taglineParagraph.lineSpacing = 1.2
        taglineParagraph.lineBreakMode = .byWordWrapping
        taglineLabel.attributedStringValue = NSAttributedString(
            string: tagline,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: taglineParagraph
            ]
        )
        taglineLabel.isEditable = false
        taglineLabel.isSelectable = false
        taglineLabel.allowsEditingTextAttributes = false
        taglineLabel.refusesFirstResponder = true
        taglineLabel.maximumNumberOfLines = 2
        taglineLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        headerStack.orientation = .vertical
        headerStack.alignment = .centerX
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.wantsLayer = true
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(taglineLabel)

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
            taglineLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor)
        ])
    }

    private func configureFeatures() {
        featuresStack.orientation = .vertical
        featuresStack.alignment = .leading
        featuresStack.spacing = 22
        featuresStack.translatesAutoresizingMaskIntoConstraints = false

        for row in featureRows {
            featuresStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: featuresStack.widthAnchor).isActive = true
        }
    }

    private func configureActionDock() {
        actionButton.target = self
        actionButton.action = #selector(primaryAction)

        actionDock.orientation = .vertical
        actionDock.alignment = .centerX
        actionDock.spacing = 10
        actionDock.translatesAutoresizingMaskIntoConstraints = false
        actionDock.wantsLayer = true
        actionDock.addArrangedSubview(actionButton)
        actionDock.addArrangedSubview(footerStatus)

        NSLayoutConstraint.activate([
            actionButton.heightAnchor.constraint(equalToConstant: 36),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 248),
            actionButton.widthAnchor.constraint(lessThanOrEqualTo: actionDock.widthAnchor),
            footerStatus.widthAnchor.constraint(equalTo: actionDock.widthAnchor)
        ])
    }

    // MARK: - Two-Act Entrance Choreography ("What's New in Xcode" Rhythm)

    private func playEntranceAnimationIfNeeded() {
        guard !hasPlayedEntrance,
              let window = view.window, window.isVisible,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        hasPlayedEntrance = true
        view.layoutSubtreeIfNeeded()

        // Act 1 -> Act 2: Hero logo draws at ~2.65x dead-center in the window,
        // then glides & scales smoothly up into its 96pt resting header slot.
        let flightDelay: CFTimeInterval = 1.52
        let flightDuration: CFTimeInterval = 1.06
        let centerOffsetY = (contentStage.bounds.midY + 14) - artwork.frame.midY
        backdropView.playHeroGlowTransition(delay: flightDelay, duration: flightDuration)
        artwork.playHeroEntrance(
            fromCenterOffsetY: centerOffsetY,
            heroScale: 2.65,
            flightDelay: flightDelay,
            flightDuration: flightDuration
        )

        // Act 2 Content Reveal (unhurried 1/3-speed cascade synchronized with logo liftoff).
        WelcomeMotion.animateStaggeredEntrance(view: headerStack, delay: flightDelay + 0.34, dy: -16, scale: 0.98)
        for (index, row) in featureRows.enumerated() {
            WelcomeMotion.animateStaggeredEntrance(
                view: row,
                delay: flightDelay + 0.58 + Double(index) * 0.22,
                dy: -18,
                scale: 0.98
            )
        }
        WelcomeMotion.animateStaggeredEntrance(view: actionDock, delay: flightDelay + 1.28, dy: -16, scale: 0.985)

        actionButton.playSheenSweep(delay: flightDelay + 2.25)
    }

    // MARK: - State & Actions

    private func renderState(animated: Bool) {
        let authorized = state.authorized
        let waiting = !authorized && hasRequestedAuthorization

        actionButton.title = authorized
            ? NSLocalizedString("Start using Mos", comment: "Welcome completion button")
            : NSLocalizedString("Grant Access", comment: "Welcome authorization button")

        backdropView.setAuthorized(authorized, animated: animated)

        if authorized {
            footerStatus.applyState(.authorized, animated: animated)
        } else if waiting {
            footerStatus.applyState(.waiting, animated: animated)
        } else {
            footerStatus.applyState(.required, animated: animated)
        }
    }

    @objc private func primaryAction() {
        if state.authorized {
            view.window?.close()
            return
        }
        hasRequestedAuthorization = true
        renderState(animated: true)

        if AppRuntime.isOnboardingPreview,
           !ProcessInfo.processInfo.arguments.contains("--mos-preview-guide") {
            updateAuthorization(true)
            return
        }
        if let extras = loadExtras(), let window = actionButton.window {
            let frame = window.convertToScreen(actionButton.convert(actionButton.bounds, to: nil))
            extras.perform(NSSelectorFromString("authorize:"), with: NSValue(rect: frame))
        } else {
            Utils.requireAccessibilityPermissions()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: .mosInputPermissionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAuthorization(InputPermissionMonitor.shared.isAuthorized)
        })
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.artwork.setReducedMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            self.footerStatus.updatePulse()
        }
    }

    private func schedulePreviewSuccessIfNeeded() {
        guard previewTimer == nil,
              AppRuntime.isOnboardingPreview,
              ProcessInfo.processInfo.arguments.contains("--mos-preview-success") else { return }
        let timer = Timer(timeInterval: 6.0, repeats: false) { [weak self] _ in
            self?.updateAuthorization(true)
        }
        previewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func loadExtras() -> NSObject? {
        if let extras = extras { return extras }
        // Optional dependencies load only on systems that support their runtime.
        guard #available(macOS 13, *), let directory = Bundle.main.builtInPlugInsURL,
              let bundle = Bundle(url: directory.appendingPathComponent("MosOnboardingExtras.bundle")),
              bundle.load(), let type = NSClassFromString("MosOnboardingExtras") as? NSObject.Type else { return nil }
        let instance = type.init()
        extras = instance
        return instance
    }
}
