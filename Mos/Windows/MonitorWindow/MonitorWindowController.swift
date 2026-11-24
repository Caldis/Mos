import Cocoa

final class MonitorWindowController: NSWindowController, NSWindowDelegate {
    private let monitor = MonitorViewController()
    private var hasOpened = false

    init() {
        let size = NSSize(width: 1200, height: 750)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .vibrantDark)
        window.isMovableByWindowBackground = true
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
            window.toolbarStyle = .unified
        }
        super.init(window: window)
        window.toolbar = monitor.monitorToolbar.toolbar
        window.contentViewController = monitor
        window.title = NSLocalizedString("Event Monitor", comment: "Event Monitor window title")
            .trimmingCharacters(in: .whitespaces)
        window.setContentSize(size)
        monitor.alignBelowToolbar(in: window)
        window.contentMinSize = NSSize(width: 800, height: 565)
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

/// Presentation values shared by the Monitor panes, matching the HID++ debug HUD.
enum MonitorStyle {
    static let padding: CGFloat = 8
    static let headerControlHeight: CGFloat = 20

    private static var sectionCornerRadius: CGFloat {
        // Inset the unified toolbar window's corner by the content padding.
        if #available(macOS 26.0, *) { return 26 - padding }
        return 5
    }

    static var contentVerticalInset: CGFloat {
        max(4, sectionCornerRadius - headerControlHeight / 2)
    }

    static func styleSection(_ view: NSView, isLog: Bool = false) {
        view.wantsLayer = true
        let background = isLog ? NSColor(calibratedWhite: 0, alpha: 0.4) : NSColor(calibratedWhite: 1, alpha: 0.05)
        view.layer?.backgroundColor = background.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        view.layer?.cornerRadius = sectionCornerRadius
    }

    static func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .tertiaryLabelColor
        return label
    }
}

final class MonitorRoundButton: NSButton {
    enum Style {
        case neutral
        case tinted
        case selected
    }

    // Auto Layout aligns the same frame that the custom background layer fills.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

    init(style: Style = .tinted) {
        super.init(frame: .zero)
        isBordered = false
        controlSize = .small
        font = .systemFont(ofSize: 11, weight: .medium)
        wantsLayer = true
        let diameter = MonitorStyle.headerControlHeight
        widthAnchor.constraint(equalToConstant: diameter).isActive = true
        heightAnchor.constraint(equalToConstant: diameter).isActive = true
        layer?.borderWidth = 1
        layer?.cornerRadius = diameter / 2
        updateStyle(style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(style:)") }

    func updateStyle(_ style: Style) {
        let fill: NSColor
        let border: NSColor
        switch style {
        case .neutral:
            fill = NSColor.white.withAlphaComponent(0.06)
            border = NSColor.white.withAlphaComponent(0.18)
        case .tinted:
            let color = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1, alpha: 1)
            fill = color.withAlphaComponent(0.15)
            border = color.withAlphaComponent(0.3)
        case .selected:
            if #available(macOS 10.14, *) {
                fill = NSColor.selectedContentBackgroundColor.withAlphaComponent(1)
            } else {
                fill = .systemBlue
            }
            border = fill
        }
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = border.cgColor
        if #available(macOS 10.14, *) {
            contentTintColor = style == .selected ? .alternateSelectedControlTextColor : .labelColor
        }
    }
}
