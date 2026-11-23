import Cocoa

final class MonitorWindowController: NSWindowController, NSWindowDelegate {
    private let monitor = MonitorViewController()
    private var hasOpened = false

    init() {
        let size = NSSize(width: 1080, height: 680)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        super.init(window: window)
        window.contentViewController = monitor
        window.title = NSLocalizedString("Event Monitor", comment: "Event Monitor window title")
            .trimmingCharacters(in: .whitespaces)
        window.setContentSize(size)
        window.contentMinSize = NSSize(width: 800, height: 550)
        window.center()
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init()") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if !hasOpened {
            hasOpened = true
            monitor.startRecording()
        }
    }

    func windowWillClose(_ notification: Notification) {
        monitor.stopRecording()
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController, destroy: true)
    }
}
