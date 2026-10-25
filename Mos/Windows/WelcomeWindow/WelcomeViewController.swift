import Cocoa

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
    private let artwork = WelcomeArtworkView(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private var state = WelcomeAuthorizationState(authorized: InputPermissionMonitor.shared.isAuthorized)
    private var observers: [NSObjectProtocol] = []
    private var motionObserver: NSObjectProtocol?
    private var extras: NSObject?
    private var previewTimer: Timer?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 540))
        let brand = label("Mos", size: 17, weight: .medium, color: .secondaryLabelColor)
        let title = label(NSLocalizedString("Make every scroll flow.", comment: "Welcome headline"), size: 30, weight: .semibold)
        let subtitle = label(NSLocalizedString("Allow Mos to customize scrolling and mouse buttons.", comment: "Welcome permission explanation"), size: 14, color: .secondaryLabelColor)
        subtitle.maximumNumberOfLines = 2
        subtitle.cell?.wraps = true
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let footer = label("Mos \(version)", size: 11, color: .tertiaryLabelColor)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .regular
        actionButton.font = .systemFont(ofSize: 14, weight: .medium)
        actionButton.keyEquivalent = "\r"
        actionButton.target = self
        actionButton.action = #selector(primaryAction)
        for child in [artwork, brand, title, subtitle, actionButton, statusLabel, footer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            artwork.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 440), artwork.heightAnchor.constraint(equalToConstant: 236),
            brand.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 0),
            brand.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            title.heightAnchor.constraint(equalToConstant: 42),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 45),
            subtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -45),
            subtitle.heightAnchor.constraint(equalToConstant: 42),
            actionButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),
            actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            actionButton.heightAnchor.constraint(equalToConstant: 36),
            statusLabel.topAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            footer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
        renderState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        artwork.updatePlayback()
        if observers.isEmpty {
            observers.append(NotificationCenter.default.addObserver(forName: .mosInputPermissionChanged,
                object: nil, queue: .main) { [weak self] _ in
                self?.updateAuthorization(InputPermissionMonitor.shared.isAuthorized)
            })
            motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.artwork.setReducedMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
        if AppRuntime.isOnboardingPreview,
           ProcessInfo.processInfo.arguments.contains("--mos-preview-success") {
            previewTimer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in self?.updateAuthorization(true) }
            RunLoop.main.add(previewTimer!, forMode: .common)
        }
    }

    func updateAuthorization(_ authorized: Bool) {
        let celebrate = state.update(authorized: authorized)
        renderState()
        if authorized { extras?.perform(NSSelectorFromString("closeGuide")) }
        if celebrate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            loadExtras()?.perform(NSSelectorFromString("celebrate"))
        }
    }

    private func renderState() {
        actionButton.title = state.authorized
            ? NSLocalizedString("Start using Mos", comment: "Welcome completion button")
            : NSLocalizedString("Grant Access", comment: "Welcome authorization button")
        statusLabel.stringValue = state.authorized ? NSLocalizedString("Authorized", comment: "") : ""
    }

    @objc private func primaryAction() {
        if state.authorized { view.window?.close(); return }
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

    func finish() {
        previewTimer?.invalidate()
        previewTimer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let observer = motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        motionObserver = nil
        extras?.perform(NSSelectorFromString("finish"))
        extras = nil
        artwork.stop()
    }

    deinit { finish() }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .center
        return field
    }
}
