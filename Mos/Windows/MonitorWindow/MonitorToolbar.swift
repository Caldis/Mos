import Cocoa

final class MonitorToolbar: NSObject, NSToolbarDelegate {
    private static let viewsID = NSToolbarItem.Identifier("monitor.views")
    private static let statusID = NSToolbarItem.Identifier("monitor.status")
    private static let captureID = NSToolbarItem.Identifier("monitor.capture")
    private static let clearID = NSToolbarItem.Identifier("monitor.clear")
    private static let exportID = NSToolbarItem.Identifier("monitor.export")

    let toolbar = NSToolbar(identifier: "MosEventMonitor")
    var didSelectChannel: ((MonitorChannel) -> Void)?
    var didToggleRecording: (() -> Void)?
    var didClear: (() -> Void)?
    var didExport: (() -> Void)?

    private let state = NSTextField(labelWithString: "")
    private let captureButton = NSButton()
    private let clearButton = NSButton()
    private let exportButton = NSButton()

    private lazy var modes: NSSegmentedControl = {
        let tabs = NSSegmentedControl(
            labels: [MonitorChannel.scroll.title, MonitorChannel.buttons.title],
            trackingMode: .selectOne, target: self, action: #selector(selectChannel(_:))
        )
        tabs.selectedSegment = MonitorChannel.scroll.rawValue
        return tabs
    }()

    override init() {
        super.init()
        state.font = .systemFont(ofSize: 12, weight: .medium)
        state.setContentCompressionResistancePriority(.required, for: .horizontal)
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

        if state.stringValue != caption {
            state.stringValue = caption
            state.textColor = color
        }
        if captureButton.title != action {
            captureButton.title = action
            toolbar.items.first { $0.itemIdentifier == Self.captureID }?.label = action
        }
        clearButton.isEnabled = canClear
        exportButton.isEnabled = canExport
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // A spacer breaks AppKit's automatic shared glass background.
        [Self.viewsID, .space, Self.statusID, .flexibleSpace,
         Self.captureID, .space, Self.clearID, .space, Self.exportID]
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
        case Self.statusID:
            item.view = state
            item.label = state.stringValue
            if #available(macOS 10.15, *) { item.isBordered = false }
        case Self.captureID:
            attach(captureButton, to: item)
        case Self.clearID:
            attach(clearButton, to: item)
        case Self.exportID:
            attach(exportButton, to: item)
        default:
            return nil
        }
        item.autovalidates = false
        return item
    }

    private func attach(_ button: NSButton, to item: NSToolbarItem) {
        item.view = button
        item.label = button.title
        item.target = self
        item.action = button.action
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @objc private func selectChannel(_ sender: NSSegmentedControl) {
        if let channel = MonitorChannel(rawValue: sender.selectedSegment) { didSelectChannel?(channel) }
    }

    @objc private func toggleRecording() { didToggleRecording?() }
    @objc private func clear() { didClear?() }
    @objc private func export() { didExport?() }
}
