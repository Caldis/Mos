import Cocoa

final class MonitorToolbar: NSObject, NSToolbarDelegate {
    private static let viewsID = NSToolbarItem.Identifier("monitor.views")
    private static let captureID = NSToolbarItem.Identifier("monitor.capture")
    private static let clearID = NSToolbarItem.Identifier("monitor.clear")
    private static let exportID = NSToolbarItem.Identifier("monitor.export")

    let toolbar = NSToolbar(identifier: "MosEventMonitor")
    var didSelectChannel: ((MonitorChannel) -> Void)?
    var didToggleRecording: (() -> Void)?
    var didClear: (() -> Void)?
    var didExport: (() -> Void)?

    private var presentedState: MonitorCapture.State?
    private lazy var captureItem = command(Self.captureID, action: #selector(toggleRecording))
    private lazy var clearItem = command(Self.clearID, action: #selector(clear))
    private lazy var exportItem = command(Self.exportID, action: #selector(export))

    private lazy var modes: NSSegmentedControl = {
        let titles = [MonitorChannel.scroll.title, MonitorChannel.buttons.title]
        let action = #selector(selectChannel(_:))
        let tabs: NSSegmentedControl
        if let scroll = symbol("waveform", named: titles[0]), let buttons = symbol("keyboard", named: titles[1]) {
            tabs = NSSegmentedControl(images: [scroll, buttons], trackingMode: .selectOne, target: self, action: action)
        } else {
            tabs = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: self, action: action)
        }
        for (index, title) in titles.enumerated() {
            tabs.setToolTip(title, forSegment: index)
        }
        tabs.setAccessibilityLabel(NSLocalizedString("monitor-views", comment: "Monitor views toolbar item"))
        tabs.selectedSegment = MonitorChannel.scroll.rawValue
        return tabs
    }()

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false

        let clearSymbol: String
        if #available(macOS 12.0, *) {
            clearSymbol = "eraser"
        } else {
            clearSymbol = "clear"
        }
        let clearTitle = NSLocalizedString("monitor-clear", comment: "Clear Monitor")
        let exportTitle = NSLocalizedString("monitor-export-log", comment: "Export Monitor events")
        setAppearance(of: clearItem, named: clearTitle, image: symbol(clearSymbol, named: clearTitle))
        setAppearance(of: exportItem, named: exportTitle, image: symbol("square.and.arrow.up", named: exportTitle))
        update(.paused, canClear: false, canExport: false)
    }

    func update(_ next: MonitorCapture.State, canClear: Bool, canExport: Bool) {
        if presentedState != next {
            presentedState = next
            updateCaptureItem(for: next)
        }
        if !captureItem.isEnabled { captureItem.isEnabled = true }
        if clearItem.isEnabled != canClear { clearItem.isEnabled = canClear }
        if exportItem.isEnabled != canExport { exportItem.isEnabled = canExport }
    }

    private func updateCaptureItem(for state: MonitorCapture.State) {
        let caption: String
        let action: String
        let actionIcon: String
        let statusIcon: String
        let statusTint: NSColor
        switch state {
        case .recording:
            caption = NSLocalizedString("monitor-recording", comment: "Monitor is recording")
            action = NSLocalizedString("monitor-pause", comment: "Pause Monitor")
            actionIcon = "pause.fill"
            statusIcon = "circle.fill"
            statusTint = .systemGreen
        case .paused:
            caption = NSLocalizedString("monitor-paused", comment: "Monitor is paused")
            action = NSLocalizedString("monitor-resume", comment: "Resume Monitor")
            actionIcon = "play.fill"
            statusIcon = "circle"
            statusTint = .secondaryLabelColor
        case .accessibilityRequired, .tapUnavailable:
            caption = NSLocalizedString("monitor-unavailable", comment: "Monitor capture is unavailable")
            action = NSLocalizedString("monitor-retry", comment: "Retry Monitor capture")
            actionIcon = "arrow.clockwise"
            statusIcon = "exclamationmark.circle"
            statusTint = .systemOrange
        }
        let title = "\(caption) · \(action)"
        let image = captureSymbol(status: statusIcon, tint: statusTint, action: actionIcon, named: title)
        setAppearance(of: captureItem, named: title, image: image)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.viewsID, .space, Self.captureID, .flexibleSpace, Self.clearID, .space, Self.exportID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.viewsID:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = modes
            item.label = NSLocalizedString("monitor-views", comment: "Monitor views toolbar item")
            item.autovalidates = false
            return item
        case Self.captureID: return captureItem
        case Self.clearID: return clearItem
        case Self.exportID: return exportItem
        default: return nil
        }
    }

    private func command(_ identifier: NSToolbarItem.Identifier, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        item.action = action
        item.autovalidates = false
        if #available(macOS 10.15, *) { item.isBordered = true }
        return item
    }

    private func setAppearance(of item: NSToolbarItem, named title: String, image: NSImage?) {
        item.label = title
        item.paletteLabel = title
        item.toolTip = title

        if let image = image {
            item.image = image
        } else {
            let button = item.view as? NSButton ?? NSButton(title: title, target: self, action: item.action)
            button.bezelStyle = .rounded
            button.title = title
            button.toolTip = title
            button.setAccessibilityLabel(title)
            item.view = button
        }
    }

    private func symbol(_ name: String, named title: String) -> NSImage? {
        guard #available(macOS 11.0, *) else { return nil }
        return NSImage(systemSymbolName: name, accessibilityDescription: title)
    }

    private func captureSymbol(status: String, tint: NSColor, action: String, named title: String) -> NSImage? {
        guard #available(macOS 11.0, *),
              let statusImage = symbol(status, named: title)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold)),
              let actionImage = symbol(action, named: title)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) else { return nil }
        let image = NSImage(size: NSSize(width: 30, height: 18), flipped: false) { bounds in
            Self.drawSymbol(statusImage, color: tint, center: NSPoint(x: bounds.minX + 6, y: bounds.midY))
            Self.drawSymbol(actionImage, color: .labelColor, center: NSPoint(x: bounds.maxX - 8, y: bounds.midY))
            return true
        }
        image.accessibilityDescription = title
        // Resolve semantic colors against the toolbar's current appearance.
        image.cacheMode = .never
        return image
    }

    private static func drawSymbol(_ image: NSImage, color: NSColor, center: NSPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let size = image.size
        let rect = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(in: rect)
        color.setFill()
        rect.fill(using: .sourceIn)
        context.endTransparencyLayer()
    }

    @objc private func selectChannel(_ sender: NSSegmentedControl) {
        if let channel = MonitorChannel(rawValue: sender.selectedSegment) { didSelectChannel?(channel) }
    }

    @objc private func toggleRecording() { didToggleRecording?() }
    @objc private func clear() { didClear?() }
    @objc private func export() { didExport?() }
}
