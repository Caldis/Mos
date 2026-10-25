import Cocoa

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let identifier: String

    init(identifier: String = WINDOW_IDENTIFIER.welcomeWindowController) {
        self.identifier = identifier
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Mos"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = WelcomeViewController()
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use init(identifier:)") }

    func windowWillClose(_ notification: Notification) {
        (contentViewController as? WelcomeViewController)?.finish()
        WindowManager.shared.hideWindow(withIdentifier: identifier, destroy: true)
    }
}
