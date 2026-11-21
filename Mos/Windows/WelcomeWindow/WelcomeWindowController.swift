import Cocoa

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let windowSize = NSSize(width: 392, height: 584)
    private let identifier: String

    init(identifier: String = WINDOW_IDENTIFIER.welcomeWindowController) {
        self.identifier = identifier
        let window = WelcomeFloatingWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mos"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)
        window.contentViewController = WelcomeViewController()
        window.delegate = self
        positionAtOpticalCenter(window)
    }

    required init?(coder: NSCoder) { fatalError("Use init(identifier:)") }

    private func positionAtOpticalCenter(_ window: NSWindow) {
        if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
            let x = visibleFrame.midX - window.frame.width / 2
            let y = visibleFrame.midY - window.frame.height / 2 + min(24, visibleFrame.height * 0.03)
            window.setFrameOrigin(NSPoint(x: round(x), y: round(y)))
        } else {
            window.center()
        }
    }

    func windowWillClose(_ notification: Notification) {
        (contentViewController as? WelcomeViewController)?.finish()
        WindowManager.shared.hideWindow(withIdentifier: identifier, destroy: true)
        if AppRuntime.isOnboardingPreview {
            NSApp.terminate(nil)
        }
    }
}

private final class WelcomeFloatingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
