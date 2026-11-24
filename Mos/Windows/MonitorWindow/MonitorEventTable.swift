import Cocoa

final class MonitorEventTable: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let capture: MonitorCapture
    private let processes = MonitorProcessLabels()
    private var table = NSTableView()
    private let scroller = NSScrollView()
    private let empty = NSTextField(labelWithString: NSLocalizedString("monitor-no-events", comment: "Empty Monitor table"))
    private let typeTitle = MonitorStyle.sectionHeader(MonitorPresentation.typeTitle)
    private let buttonCaptureNote = NSTextField(labelWithString: NSLocalizedString(
        "monitor-button-capture-note", comment: "Primary mouse clicks are excluded from the Monitor button log"
    ))
    private lazy var scrollFilters: NSStackView = {
        let input = makeFilter(.captured, filter: .captured)
        let posted = makeFilter(.posted, filter: .posted)
        let filters = NSStackView(views: [input, posted])
        filters.alignment = .centerY
        filters.spacing = 4
        return filters
    }()
    private lazy var followLatestButton: MonitorRoundButton = {
        let title = NSLocalizedString("monitor-follow-latest", comment: "Keep the newest event in view")
        let button = MonitorRoundButton(style: .neutral)
        button.title = title
        button.target = self
        button.action = #selector(toggleFollowLatest(_:))
        button.setButtonType(.pushOnPushOff)
        button.identifier = NSUserInterfaceItemIdentifier("monitor.followLatest")
        setMonitorButtonIcon(button, symbol: "arrow.up.to.line", fallback: NSImage.touchBarGoUpTemplateName)
        return button
    }()
    private lazy var columnMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        return menu
    }()
    private var channel: MonitorChannel = .scroll
    private var filter: MonitorScrollFilter = .all
    private var list: MonitorCapture.EventList = .scroll(.all)
    private var columns: [MonitorPresentation.Column] = []
    private var columnsByID: [String: MonitorPresentation.Column] = [:]
    private var displayedCount = 0
    private var displayedNewestID: UInt64?
    private var restoringSelection = false

    var didSelect: ((MonitorEvent?) -> Void)?

    init(capture: MonitorCapture) {
        self.capture = capture
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(capture:)") }

    override func loadView() {
        let root = NSView()
        MonitorStyle.styleSection(root, isLog: true)
        buttonCaptureNote.font = .systemFont(ofSize: 10)
        buttonCaptureNote.textColor = .secondaryLabelColor
        buttonCaptureNote.lineBreakMode = .byTruncatingTail
        buttonCaptureNote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonCaptureNote.toolTip = buttonCaptureNote.stringValue
        buttonCaptureNote.isHidden = true
        let header = NSStackView(views: [typeTitle, scrollFilters, buttonCaptureNote, NSView(), followLatestButton])
        header.alignment = .centerY
        header.spacing = 8
        header.detachesHiddenViews = true
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        configureTable()
        scroller.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroller)

        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.textColor = .secondaryLabelColor
        root.addSubview(empty)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: MonitorStyle.contentVerticalInset),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: MonitorStyle.headerControlHeight),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: MonitorStyle.padding),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -MonitorStyle.padding),
            scroller.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            scroller.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            scroller.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            scroller.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -MonitorStyle.contentVerticalInset),
            empty.centerXAnchor.constraint(equalTo: scroller.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroller.centerYAnchor),
        ])
        view = root
    }

    func update(channel: MonitorChannel, selectedID: UInt64?) {
        _ = view
        let nextList: MonitorCapture.EventList = channel == .scroll ? .scroll(filter) : .buttons
        let listChanged = list != nextList
        let previousRow = table.selectedRow
        let selectedWasVisible = !listChanged && previousRow >= 0
            && NSLocationInRange(previousRow, table.rows(in: table.visibleRect))

        restoringSelection = true
        defer { restoringSelection = false }
        list = nextList
        if self.channel != channel {
            // AppKit's cached row views belong to the previous column schema.
            table.delegate = nil
            table.dataSource = nil
            self.channel = channel
            typeTitle.isHidden = channel == .buttons
            scrollFilters.isHidden = channel == .buttons
            buttonCaptureNote.isHidden = channel != .buttons
            table = NSTableView()
            configureTable()
        }
        let count = capture.rowCount(in: list)
        let newestID = capture.event(at: 0, in: list)?.id
        let rowsChanged = listChanged || count != displayedCount || newestID != displayedNewestID
        let showsFirstRow = rowsChanged && (listChanged || displayedCount == 0 || followLatestButton.state == .on)
        if rowsChanged {
            empty.isHidden = count > 0
            if listChanged || count == 0 || displayedCount == 0 {
                table.reloadData()
            } else {
                // Row indexes are slots in the newest-first history. Resize the tail
                // so a new event never moves all the existing AppKit rows.
                if count > displayedCount {
                    table.insertRows(at: IndexSet(integersIn: displayedCount..<count), withAnimation: [])
                } else if count < displayedCount {
                    table.removeRows(at: IndexSet(integersIn: count..<displayedCount), withAnimation: [])
                }
                refreshAvailableRows()
            }
            displayedCount = count
            displayedNewestID = newestID
        }

        // Rows are newest-first and shift on every drain. Keep the ID of the
        // selected snapshot, including when it has just aged out of the ring.
        if let id = selectedID, let row = capture.row(for: id, in: list) {
            if row != table.selectedRow { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            if rowsChanged && selectedWasVisible && !showsFirstRow { table.scrollRowToVisible(row) }
        } else if table.selectedRow >= 0 {
            table.deselectAll(nil)
        }
        if showsFirstRow { scrollToLatest() }
    }

    private func refreshAvailableRows() {
        let visibleColumns = table.tableColumns.enumerated().compactMap { index, column in
            column.isHidden ? nil : columnsByID[column.identifier.rawValue].map { (index, $0) }
        }
        table.enumerateAvailableRowViews { rowView, row in
            guard let event = self.capture.event(at: row, in: self.list) else { return }
            for (index, definition) in visibleColumns {
                guard let cell = rowView.view(atColumn: index) as? NSTableCellView else { continue }
                self.display(event, in: cell, definition: definition)
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        capture.rowCount(in: list)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, let definition = columnsByID[column.identifier.rawValue],
              let event = capture.event(at: row, in: list) else { return nil }
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else if definition.id == "stage" {
            cell = MonitorTypeCell(frame: .zero)
            cell.identifier = column.identifier
        } else if definition.displayTarget != nil {
            cell = MonitorTargetCell()
            cell.identifier = column.identifier
        } else {
            cell = makeMonitorCell(identifier: column.identifier, numeric: definition.numeric, selectable: false)
        }
        display(event, in: cell, definition: definition)
        return cell
    }

    private func display(_ event: MonitorEvent, in cell: NSTableCellView, definition: MonitorPresentation.Column) {
        if let target = definition.displayTarget, let targetCell = cell as? MonitorTargetCell {
            targetCell.display(target(event), using: processes)
            return
        }
        let value = definition.value(event, capture.origin) ?? MonitorPresentation.missing
        if let tag = cell as? MonitorTypeCell {
            tag.display(value, stage: event.stage)
        } else if cell.textField?.stringValue != value {
            cell.textField?.stringValue = value
            cell.textField?.toolTip = value
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !restoringSelection else { return }
        didSelect?(capture.event(at: table.selectedRow, in: list))
    }

    @objc private func toggleFollowLatest(_ sender: MonitorRoundButton) {
        let enabled = sender.state == .on
        sender.updateStyle(enabled ? .selected : .neutral)
        if enabled { scrollToLatest() }
    }

    private func scrollToLatest() {
        guard table.numberOfRows > 0 else { return }
        let clipView = scroller.contentView
        var bounds = clipView.bounds
        // The clip view clamps to the top of the document, including the header inset.
        bounds.origin.y = table.frame.minY - bounds.height
        let origin = clipView.constrainBoundsRect(bounds).origin
        guard origin != clipView.bounds.origin else { return }
        clipView.scroll(to: origin)
        scroller.reflectScrolledClipView(clipView)
    }

    private func makeFilter(_ stage: ScrollMonitorStage, filter: MonitorScrollFilter) -> NSButton {
        let title = MonitorPresentation.stageName(stage)
        let color = MonitorTypeTag.color(for: stage)
        let button = NSButton(title: title, target: self, action: #selector(changeScrollFilter(_:)))
        button.setButtonType(.pushOnPushOff)
        button.state = .on
        button.tag = filter.rawValue
        button.isBordered = false
        button.font = MonitorTypeTag.font
        MonitorTypeTag.style(button, color: color)
        if #available(macOS 10.14, *) { button.contentTintColor = color }
        button.widthAnchor.constraint(equalToConstant: MonitorTypeTag.width(for: title)).isActive = true
        button.heightAnchor.constraint(equalToConstant: MonitorStyle.headerControlHeight).isActive = true
        return button
    }

    @objc private func changeScrollFilter(_ sender: NSButton) {
        let option = MonitorScrollFilter(rawValue: sender.tag)
        let enabled = sender.state == .on
        if enabled { filter.insert(option) } else { filter.remove(option) }
        sender.alphaValue = enabled ? 1 : 0.3
        update(channel: .scroll, selectedID: nil)
        didSelect?(nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === columnMenu else { return }
        menu.removeAllItems()
        let visibleCount = table.tableColumns.filter { !$0.isHidden }.count
        for definition in columns {
            let identifier = NSUserInterfaceItemIdentifier(definition.id)
            guard let column = table.tableColumn(withIdentifier: identifier) else { continue }
            let item = NSMenuItem(title: definition.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = definition.id
            item.state = column.isHidden ? .off : .on
            item.isEnabled = column.isHidden || visibleCount > 1
            item.toolTip = column.headerToolTip
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reset = NSMenuItem(
            title: NSLocalizedString("monitor-reset-columns", comment: "Restore the default event table columns"),
            action: #selector(resetColumns), keyEquivalent: ""
        )
        reset.target = self
        menu.addItem(reset)
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id)) else { return }
        guard column.isHidden || table.tableColumns.filter({ !$0.isHidden }).count > 1 else { return }
        column.isHidden.toggle()
    }

    @objc private func resetColumns() {
        for (index, definition) in columns.enumerated() {
            let id = NSUserInterfaceItemIdentifier(definition.id)
            let currentIndex = table.column(withIdentifier: id)
            guard currentIndex >= 0 else { continue }
            if currentIndex != index { table.moveColumn(currentIndex, toColumn: index) }
            let column = table.tableColumns[index]
            column.isHidden = !definition.visibleByDefault
            column.width = definition.width
        }
    }

    private func configureTable() {
        columns = MonitorPresentation.columnDefinitions(for: channel)
        columnsByID = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })
        for definition in columns {
            let column = addMonitorColumn(
                to: table, title: definition.title, width: definition.width,
                minimum: definition.minimum, identifier: definition.id
            )
            column.isHidden = !definition.visibleByDefault
            if let enumID = definition.enumID {
                column.headerToolTip = "\(definition.title)\nCGEventField \(enumID)"
            }
        }
        table.allowsColumnReordering = true
        configureMonitorTable(table, in: scroller)
        table.headerView?.menu = columnMenu
        if !AppRuntime.isRunningXCTest {
            table.autosaveName = channel == .scroll ? "MosMonitor.ScrollColumns" : "MosMonitor.ButtonColumns"
            table.autosaveTableColumns = true
        }
        if table.tableColumns.allSatisfy(\.isHidden) { table.tableColumns.first?.isHidden = false }
        table.delegate = self
        table.dataSource = self
    }
}

private enum MonitorTypeTag {
    static let font = NSFont.systemFont(ofSize: 9, weight: .medium)

    static func color(for stage: ScrollMonitorStage) -> NSColor {
        switch stage {
        case .captured: return NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1)
        case .posted: return NSColor(calibratedRed: 0.4, green: 0.6, blue: 1, alpha: 1)
        case .frame: return .secondaryLabelColor
        }
    }

    static func width(for title: String) -> CGFloat {
        max(38, ceil((title as NSString).size(withAttributes: [.font: font]).width) + 12)
    }

    static func style(_ view: NSView, color: NSColor) {
        view.wantsLayer = true
        view.layer?.backgroundColor = color.withAlphaComponent(0.3).cgColor
        view.layer?.cornerRadius = 3
    }
}

private final class MonitorTypeCell: NSTableCellView {
    private let badge = NSView()
    private let label = NSTextField(labelWithString: "")
    private lazy var badgeWidth = badge.widthAnchor.constraint(equalToConstant: 38)
    private var stage: ScrollMonitorStage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        badge.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = MonitorTypeTag.font
        label.alignment = .center
        addSubview(badge)
        badge.addSubview(label)
        textField = label
        let verticalInset: CGFloat = 2
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: verticalInset),
            badge.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -verticalInset),
            badge.heightAnchor.constraint(equalToConstant: MonitorStyle.headerControlHeight - verticalInset * 2),
            badgeWidth,
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func display(_ title: String, stage: ScrollMonitorStage) {
        guard self.stage != stage else { return }
        self.stage = stage
        let color = MonitorTypeTag.color(for: stage)
        label.stringValue = title
        label.textColor = color
        badgeWidth.constant = MonitorTypeTag.width(for: title)
        MonitorTypeTag.style(badge, color: color)
    }
}

final class MonitorInspector: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let scroller = NSScrollView()
    private let copyButton = MonitorRoundButton()
    private var fields: [MonitorField] = []

    var didClose: (() -> Void)?

    override func loadView() {
        let root = NSView()
        let panel = NSView()
        MonitorStyle.styleSection(panel)
        panel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(panel)
        let title = MonitorStyle.sectionHeader(NSLocalizedString("monitor-inspector", comment: "Selected event inspector"))
        let closeTitle = NSLocalizedString("monitor-close-inspector", comment: "Close the event inspector")
        let close = MonitorRoundButton(style: .neutral)
        close.title = closeTitle
        close.target = self
        close.action = #selector(closeInspector)
        setMonitorButtonIcon(close, symbol: "xmark", fallback: NSImage.stopProgressFreestandingTemplateName)
        copyButton.title = NSLocalizedString("monitor-copy-raw", comment: "Copy the selected event fields")
        copyButton.target = self
        copyButton.action = #selector(copyRawValues)
        setMonitorButtonIcon(copyButton, symbol: "doc.on.doc", fallback: NSImage.multipleDocumentsName)
        let header = row([title, NSView(), copyButton, close])

        configureMonitorTable(table, in: scroller)
        table.delegate = self
        table.dataSource = self
        addMonitorColumn(to: table, title: NSLocalizedString("ID", comment: "CGEventField enum ID column"), width: 44, minimum: 34)
        table.tableColumns[0].maxWidth = 60
        addMonitorColumn(to: table, title: NSLocalizedString("monitor-field", comment: "Raw field name column"), width: 126, minimum: 94)
        addMonitorColumn(to: table, title: NSLocalizedString("monitor-value", comment: "Raw field value column"), width: 190, minimum: 126)

        let content = NSStackView(views: [header, scroller])
        content.orientation = .vertical
        content.alignment = .leading
        content.distribution = .fill
        content.detachesHiddenViews = true
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: root.topAnchor),
            panel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: MonitorStyle.padding - 1),
            panel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: MonitorStyle.contentVerticalInset),
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: MonitorStyle.padding),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -MonitorStyle.padding),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -MonitorStyle.contentVerticalInset),
            header.widthAnchor.constraint(equalTo: content.widthAnchor),
            scroller.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])
        view = root
    }

    func display(_ event: MonitorEvent) {
        _ = view
        fields = MonitorPresentation.rawFields(event)
        copyButton.isEnabled = !fields.isEmpty
        table.reloadData()
        if !fields.isEmpty { table.scrollRowToVisible(0) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        fields.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, fields.indices.contains(row) else { return nil }
        let field = fields[row]
        let text: String
        switch column.identifier.rawValue {
        case "0": text = field.enumID.map(String.init) ?? "—"
        case "1": text = field.title
        case "2": text = field.value
        default: return nil
        }
        let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView
            ?? makeMonitorCell(identifier: column.identifier, numeric: column.identifier.rawValue != "1", selectable: true)
        cell.textField?.stringValue = text
        cell.textField?.toolTip = text
        return cell
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        return row
    }

    @objc private func closeInspector() {
        didClose?()
    }

    @objc private func copyRawValues() {
        guard !fields.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MonitorPresentation.rawText(fields), forType: .string)
    }
}

private func setMonitorButtonIcon(_ button: MonitorRoundButton, symbol: String, fallback: NSImage.Name) {
    let title = button.title
    if #available(macOS 11.0, *), let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
        button.image = image
    } else {
        button.image = NSImage(named: fallback)
    }
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.setAccessibilityLabel(title)
    button.toolTip = title
}

private func configureMonitorTable(_ table: NSTableView, in scroller: NSScrollView) {
    table.backgroundColor = .clear
    table.allowsEmptySelection = true
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.intercellSpacing = NSSize(width: 8, height: 3)
    table.usesAutomaticRowHeights = true
    if #available(macOS 11.0, *) {
        table.style = .plain
    }
    scroller.hasVerticalScroller = true
    scroller.hasHorizontalScroller = true
    scroller.autohidesScrollers = true
    scroller.scrollerStyle = .overlay
    scroller.scrollerKnobStyle = .light
    scroller.borderType = .noBorder
    scroller.drawsBackground = false
    scroller.documentView = table
}

@discardableResult
private func addMonitorColumn(
    to table: NSTableView, title: String, width: CGFloat, minimum: CGFloat, identifier: String? = nil
) -> NSTableColumn {
    let id = identifier ?? String(table.numberOfColumns)
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
    column.headerCell.attributedStringValue = NSAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor.secondaryLabelColor,
    ])
    column.headerToolTip = title
    column.minWidth = minimum
    column.width = width
    table.addTableColumn(column)
    return column
}

private func makeMonitorCell(
    identifier: NSUserInterfaceItemIdentifier,
    numeric: Bool,
    selectable: Bool
) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: "")
    label.isSelectable = selectable
    label.maximumNumberOfLines = selectable ? 0 : 1
    label.lineBreakMode = selectable ? .byCharWrapping : .byTruncatingTail
    label.font = numeric
        ? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        : .systemFont(ofSize: 11)
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    cell.textField = label
    NSLayoutConstraint.activate([
        label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
        label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2),
        label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
        label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
    ])
    return cell
}
