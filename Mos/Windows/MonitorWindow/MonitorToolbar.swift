import Cocoa

final class MonitorToolbar: NSObject, NSToolbarDelegate {
    private static let viewsID = NSToolbarItem.Identifier("monitor.views")
    private static let commandsID = NSToolbarItem.Identifier("monitor.commands")

    let toolbar = NSToolbar(identifier: "MosEventMonitor")
    var didSelectChannel: ((MonitorChannel) -> Void)?
    var didToggleRecording: (() -> Void)?
    var didClear: (() -> Void)?
    var didExport: (() -> Void)?

    private let state = NSTextField(labelWithString: "")
    private let captureButton = NSButton()
    private let clearButton = NSButton()
    private let exportButton = NSButton()

    private lazy var modes: NSStackView = {
        let tabs = NSSegmentedControl(
            labels: [MonitorChannel.scroll.title, MonitorChannel.buttons.title],
            trackingMode: .selectOne, target: self, action: #selector(selectChannel(_:))
        )
        tabs.selectedSegment = MonitorChannel.scroll.rawValue
        return row([tabs, state])
    }()

    private lazy var commands: NSStackView = {
        row([captureButton, clearButton, exportButton])
    }()

    override init() {
        super.init()
        state.font = .systemFont(ofSize: 12, weight: .medium)
        configure(captureButton, title: "", action: #selector(toggleRecording))
        configure(clearButton, title: NSLocalizedString("monitor-clear", comment: "Clear Monitor"), action: #selector(clear))
        configure(exportButton, title: NSLocalizedString("monitor-export-log", comment: "Export Monitor events"), action: #selector(export))
        captureButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        update(.paused, canClear: false, canExport: false)
    }

    func update(_ next: MonitorCapture.State, canClear: Bool, canExport: Bool) {
        let caption: String
        let action: String
        let color: NSColor
        switch next {
        case .recording:
            caption = NSLocalizedString("monitor-recording", comment: "Monitor is recording")
            action = NSLocalizedString("monitor-pause", comment: "Pause Monitor")
            color = .systemGreen
        case .paused:
            caption = NSLocalizedString("monitor-paused", comment: "Monitor is paused")
            action = NSLocalizedString("monitor-resume", comment: "Resume Monitor")
            color = .secondaryLabelColor
        case .accessibilityRequired, .tapUnavailable:
            caption = NSLocalizedString("monitor-unavailable", comment: "Monitor capture is unavailable")
            action = NSLocalizedString("monitor-retry", comment: "Retry Monitor capture")
            color = .systemOrange
        }

        state.stringValue = caption
        state.textColor = color
        captureButton.title = action
        clearButton.isEnabled = canClear
        exportButton.isEnabled = canExport
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.viewsID, .flexibleSpace, Self.commandsID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.viewsID:
            item.view = modes
            item.label = NSLocalizedString("monitor-views", comment: "Monitor views toolbar item")
        case Self.commandsID:
            item.view = commands
            item.label = NSLocalizedString("monitor-recording-controls", comment: "Monitor recording actions toolbar item")
        default:
            return nil
        }
        item.autovalidates = false
        return item
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    @objc private func selectChannel(_ sender: NSSegmentedControl) {
        if let channel = MonitorChannel(rawValue: sender.selectedSegment) { didSelectChannel?(channel) }
    }

    @objc private func toggleRecording() { didToggleRecording?() }
    @objc private func clear() { didClear?() }
    @objc private func export() { didExport?() }
}
