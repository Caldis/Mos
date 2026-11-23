import Cocoa

final class MonitorEventTable: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let capture: MonitorCapture
    private var table = NSTableView()
    private let scroller = NSScrollView()
    private let empty = NSTextField(labelWithString: NSLocalizedString("monitor-no-events", comment: "Empty Monitor table"))
    private var channel: MonitorChannel = .scroll
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
        let title = NSTextField(labelWithString: NSLocalizedString("monitor-events", comment: "Events table heading"))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(title)

        configureTable()
        scroller.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroller)

        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.textColor = .secondaryLabelColor
        root.addSubview(empty)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 5),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroller.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7),
            scroller.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroller.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: scroller.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroller.centerYAnchor),
        ])
        view = root
    }

    func update(channel: MonitorChannel, selectedID: UInt64?) {
        _ = view
        let previousRow = table.selectedRow
        let selectedWasVisible = previousRow >= 0 && NSLocationInRange(previousRow, table.rows(in: table.visibleRect))

        restoringSelection = true
        defer { restoringSelection = false }
        if self.channel != channel {
            // Scroll and Buttons have different schemas. Replacing the table
            // keeps AppKit's cached row views tied to their original columns.
            table.delegate = nil
            table.dataSource = nil
            self.channel = channel
            table = NSTableView()
            configureTable()
            scroller.contentView.scroll(to: .zero)
        }
        empty.isHidden = capture.count(channel) > 0
        table.reloadData()

        // Rows are newest-first and shift on every drain. Keep the ID of the
        // selected snapshot, including when it has just aged out of the ring.
        if let id = selectedID, let row = capture.row(for: id, in: channel) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if selectedWasVisible { table.scrollRowToVisible(row) }
        } else {
            table.deselectAll(nil)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        capture.count(channel)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, let index = Int(column.identifier.rawValue),
              let event = capture.event(at: row, in: channel) else { return nil }
        let cells = MonitorPresentation.columns(event, origin: capture.origin)
        guard cells.indices.contains(index) else { return nil }
        let isNumber = index == 0 || (channel == .scroll && index >= 3)
        return monitorCell(cells[index], in: tableView, identifier: column.identifier, numeric: isNumber)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !restoringSelection else { return }
        didSelect?(capture.event(at: table.selectedRow, in: channel))
    }

    private func configureTable() {
        addMonitorColumn(to: table, title: NSLocalizedString("monitor-time", comment: "Time column"), width: 82, minimum: 67)
        switch channel {
        case .scroll:
            addMonitorColumn(to: table, title: NSLocalizedString("monitor-stage", comment: "Scroll stage column"), width: 96, minimum: 64)
            addMonitorColumn(to: table, title: NSLocalizedString("monitor-route", comment: "Tap or posting API column"), width: 170, minimum: 144)
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
        let title = NSTextField(labelWithString: NSLocalizedString("monitor-inspector", comment: "Selected event inspector"))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let closeTitle = NSLocalizedString("monitor-close-inspector", comment: "Close the event inspector")
        let close = NSButton(title: closeTitle, target: self, action: #selector(closeInspector))
        close.bezelStyle = .rounded
        close.controlSize = .small
        if #available(macOS 11.0, *), let icon = NSImage(systemSymbolName: "xmark", accessibilityDescription: closeTitle) {
            close.image = icon
            close.imagePosition = .imageOnly
            close.setAccessibilityLabel(closeTitle)
            close.toolTip = closeTitle
        }
        let header = row([title, NSView(), close])

        sourceTitle.textColor = .secondaryLabelColor
        sourceValue.font = .systemFont(ofSize: 12, weight: .medium)
        sourceValue.lineBreakMode = .byTruncatingTail
        sourceValue.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        source.orientation = .horizontal
        source.alignment = .centerY
        source.spacing = 8
        for view in [sourceTitle, sourceValue, NSView()] { source.addArrangedSubview(view) }

        let rawTitle = NSTextField(labelWithString: NSLocalizedString("monitor-raw-values", comment: "Raw Values inspector section"))
        rawTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        copyButton.title = NSLocalizedString("monitor-copy-raw", comment: "Copy the selected event fields")
        copyButton.target = self
        copyButton.action = #selector(copyRawValues)
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        let rawHeader = row([rawTitle, NSView(), copyButton])

        configureMonitorTable(table, in: scroller)
        table.delegate = self
        table.dataSource = self
        addMonitorColumn(to: table, title: NSLocalizedString("monitor-field", comment: "Raw field name column"), width: 148, minimum: 98)
        addMonitorColumn(to: table, title: NSLocalizedString("monitor-value", comment: "Raw field value column"), width: 190, minimum: 137)

        let content = NSStackView(views: [header, source, rawHeader, scroller])
        content.orientation = .vertical
        content.alignment = .leading
        content.distribution = .fill
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 5),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
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
        let isValue = column.identifier.rawValue == "1"
        let field = fields[row]
        return monitorCell(
            isValue ? field.value : field.title,
            in: tableView, identifier: column.identifier, numeric: isValue, selectable: true
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

private func configureMonitorTable(_ table: NSTableView, in scroller: NSScrollView) {
    table.usesAlternatingRowBackgroundColors = true
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
    scroller.borderType = .lineBorder
    scroller.documentView = table
}

private func addMonitorColumn(to table: NSTableView, title: String, width: CGFloat, minimum: CGFloat) {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(table.numberOfColumns)))
    column.title = title
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
            : .systemFont(ofSize: 12)
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
