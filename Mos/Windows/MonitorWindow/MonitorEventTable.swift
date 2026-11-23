import Cocoa

final class MonitorEventTable: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let capture: MonitorCapture
    private var table = NSTableView()
    private let scroller = NSScrollView()
    private let empty = NSTextField(labelWithString: NSLocalizedString("monitor-no-events", comment: "Empty Monitor table"))
    private lazy var scrollFilter = NSSegmentedControl(
        labels: [MonitorPresentation.stageName(.captured), MonitorPresentation.stageName(.posted)],
        trackingMode: .selectOne, target: self, action: #selector(changeScrollFilter(_:))
    )
    private var scrollStage: ScrollMonitorStage = .captured
    private var list: MonitorCapture.EventList = .scroll(.captured)
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
        let title = MonitorStyle.sectionHeader(NSLocalizedString("monitor-events", comment: "Events table heading"))
        scrollFilter.selectedSegment = 0
        scrollFilter.controlSize = .small
        scrollFilter.segmentStyle = .smallSquare
        scrollFilter.setAccessibilityLabel(NSLocalizedString("monitor-stage", comment: "Scroll event filter"))
        let header = NSStackView(views: [title, NSView(), scrollFilter])
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
        let nextList: MonitorCapture.EventList = channel == .scroll ? .scroll(scrollStage) : .buttons
        let listChanged = list != nextList
        let previousRow = table.selectedRow
        let selectedWasVisible = !listChanged && previousRow >= 0
            && NSLocationInRange(previousRow, table.rows(in: table.visibleRect))

        restoringSelection = true
        defer { restoringSelection = false }
        if listChanged {
            // AppKit's cached row views belong to the previous column schema.
            table.delegate = nil
            table.dataSource = nil
            list = nextList
            scrollFilter.isHidden = channel == .buttons
            table = NSTableView()
            configureTable()
            scroller.contentView.scroll(to: .zero)
        }
        let count = capture.rowCount(in: list)
        let newestID = capture.event(at: 0, in: list)?.id
        let rowsChanged = listChanged || count != displayedCount || newestID != displayedNewestID
        if rowsChanged {
            displayedCount = count
            displayedNewestID = newestID
            empty.isHidden = count > 0
            table.reloadData()
        }

        // Rows are newest-first and shift on every drain. Keep the ID of the
        // selected snapshot, including when it has just aged out of the ring.
        if let id = selectedID, let row = capture.row(for: id, in: list) {
            if row != table.selectedRow { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            if rowsChanged && selectedWasVisible { table.scrollRowToVisible(row) }
        } else if table.selectedRow >= 0 {
            table.deselectAll(nil)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        capture.rowCount(in: list)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, let index = Int(column.identifier.rawValue),
              let event = capture.event(at: row, in: list) else { return nil }
        let cells = MonitorPresentation.columns(event, origin: capture.origin)
        guard cells.indices.contains(index) else { return nil }
        let isNumber = index == 0 || (list != .buttons && index >= cells.count - 2)
        return monitorCell(cells[index], in: tableView, identifier: column.identifier, numeric: isNumber)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !restoringSelection else { return }
        didSelect?(capture.event(at: table.selectedRow, in: list))
    }

    @objc private func changeScrollFilter(_ sender: NSSegmentedControl) {
        scrollStage = sender.selectedSegment == 0 ? .captured : .posted
        update(channel: .scroll, selectedID: nil)
        didSelect?(nil)
    }

    private func configureTable() {
        addMonitorColumn(to: table, title: NSLocalizedString("monitor-time", comment: "Time column"), width: 82, minimum: 67)
        switch list {
        case .scroll(let stage):
            if stage == .captured {
                addMonitorColumn(to: table, title: NSLocalizedString("monitor-tap", comment: "Tap where the input was seen"), width: 168, minimum: 120)
            }
            addMonitorColumn(to: table, title: "ΔX", width: 58, minimum: 44)
            addMonitorColumn(to: table, title: "ΔY", width: 58, minimum: 44)
        case .buttons:
            addMonitorColumn(to: table, title: NSLocalizedString("monitor-input", comment: "Button or key column"), width: 135, minimum: 96)
            addMonitorColumn(to: table, title: NSLocalizedString("monitor-tap", comment: "Tap where the input was seen"), width: 168, minimum: 120)
        }
        configureMonitorTable(table, in: scroller)
        table.delegate = self
        table.dataSource = self
    }
}

final class MonitorInspector: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let scroller = NSScrollView()
    private let sourceTitle = NSTextField(labelWithString: "")
    private let sourceValue = NSTextField(labelWithString: "")
    private let source = NSStackView()
    private let copyButton = NSButton()
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
        let close = NSButton(title: closeTitle, target: self, action: #selector(closeInspector))
        MonitorStyle.styleButton(close, neutral: true)
        close.widthAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
        close.heightAnchor.constraint(equalToConstant: MonitorStyle.headerControlHeight).isActive = true
        if #available(macOS 11.0, *), let icon = NSImage(systemSymbolName: "xmark", accessibilityDescription: closeTitle) {
            close.image = icon
            close.imagePosition = .imageOnly
            close.setAccessibilityLabel(closeTitle)
            close.toolTip = closeTitle
        }
        let header = row([title, NSView(), close])

        sourceTitle.textColor = .secondaryLabelColor
        sourceValue.font = .systemFont(ofSize: 11, weight: .medium)
        sourceValue.lineBreakMode = .byTruncatingTail
        sourceValue.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        source.orientation = .horizontal
        source.alignment = .centerY
        source.spacing = 8
        for view in [sourceTitle, sourceValue, NSView()] { source.addArrangedSubview(view) }

        let rawTitle = MonitorStyle.sectionHeader(NSLocalizedString("monitor-raw-values", comment: "Raw Values inspector section"))
        copyButton.title = NSLocalizedString("monitor-copy-raw", comment: "Copy the selected event fields")
        copyButton.target = self
        copyButton.action = #selector(copyRawValues)
        MonitorStyle.styleButton(copyButton)
        copyButton.heightAnchor.constraint(equalToConstant: MonitorStyle.headerControlHeight).isActive = true
        let rawHeader = row([rawTitle, NSView(), copyButton])

        configureMonitorTable(table, in: scroller)
        table.delegate = self
        table.dataSource = self
        addMonitorColumn(to: table, title: NSLocalizedString("ID", comment: "CGEventField enum ID column"), width: 44, minimum: 34)
        table.tableColumns[0].maxWidth = 60
        addMonitorColumn(to: table, title: NSLocalizedString("monitor-field", comment: "Raw field name column"), width: 126, minimum: 94)
        addMonitorColumn(to: table, title: NSLocalizedString("monitor-value", comment: "Raw field value column"), width: 190, minimum: 126)

        let content = NSStackView(views: [header, source, rawHeader, scroller])
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
            source.widthAnchor.constraint(equalTo: content.widthAnchor),
            rawHeader.widthAnchor.constraint(equalTo: content.widthAnchor),
            scroller.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])
        view = root
    }

    func display(_ event: MonitorEvent) {
        _ = view
        let details = MonitorPresentation.detail(event)
        sourceTitle.stringValue = details.source?.title ?? ""
        sourceValue.stringValue = details.source?.value ?? ""
        sourceValue.toolTip = details.source?.value
        source.isHidden = details.source == nil
        fields = details.fields
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
        return monitorCell(
            text, in: tableView, identifier: column.identifier,
            numeric: column.identifier.rawValue != "1", selectable: true
        )
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

private final class MonitorTableHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInterior(withFrame: cellFrame, in: controlView)
    }
}

private final class MonitorTableHeaderView: NSTableHeaderView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        guard let table = tableView else { return }
        for (index, column) in table.tableColumns.enumerated() {
            let rect = headerRect(ofColumn: index)
            if dirtyRect.intersects(rect) {
                column.headerCell.draw(withFrame: rect, in: self)
            }
        }
    }
}

private func configureMonitorTable(_ table: NSTableView, in scroller: NSScrollView) {
    table.backgroundColor = .clear
    table.headerView = MonitorTableHeaderView()
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

private func addMonitorColumn(to table: NSTableView, title: String, width: CGFloat, minimum: CGFloat) {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(table.numberOfColumns)))
    let header = MonitorTableHeaderCell(textCell: title)
    header.attributedStringValue = NSAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor.secondaryLabelColor,
    ])
    column.headerCell = header
    column.headerToolTip = title
    column.minWidth = minimum
    column.width = width
    table.addTableColumn(column)
}

private func monitorCell(
    _ value: String,
    in table: NSTableView,
    identifier: NSUserInterfaceItemIdentifier,
    numeric: Bool,
    selectable: Bool = false
) -> NSTableCellView {
    let cell: NSTableCellView
    if let reused = table.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
        cell = reused
    } else {
        cell = NSTableCellView()
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
    }
    cell.textField?.stringValue = value
    cell.textField?.toolTip = value
    return cell
}
