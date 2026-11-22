//
//  ScrollSourceExclusionsViewController.swift
//  Mos
//  Global source application exclusions, separate from target app profiles.
//

import Cocoa

final class ScrollSourceExclusionsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let removeButton = NSButton()
    private var identifiers: [String] { return Options.shared.excludedScrollSourceBundleIdentifiers }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
        let title = NSTextField(labelWithString: NSLocalizedString("Scroll Source Exclusions", comment: "Source exclusion panel title"))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let explanation = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "Choose the app that sends scroll events, such as your device's driver app. Its scrolling will pass through unchanged in every app.",
            comment: "Explain source exclusions versus target application profiles"))
        explanation.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        column.title = NSLocalizedString("Source Application", comment: "Excluded source table column")
        table.addTableColumn(column)
        table.headerView = nil
        table.frame = NSRect(x: 0, y: 0, width: 560, height: 220)
        table.autoresizingMask = [.width]
        table.rowHeight = 44
        table.delegate = self
        table.dataSource = self
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table

        let add = NSButton(title: NSLocalizedString("Add…", comment: "Add source application"), target: self, action: #selector(addSource))
        add.bezelStyle = .rounded
        removeButton.title = NSLocalizedString("Remove", comment: "Remove selected source application")
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeSource)
        removeButton.isEnabled = false
        let done = NSButton(title: NSLocalizedString("Done", comment: "Close source exclusion panel"), target: self, action: #selector(closePanel))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let children: [NSView] = [title, explanation, scroll, add, removeButton, done]
        for child in children {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 600),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            explanation.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            explanation.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            explanation.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 220),
            add.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            add.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            removeButton.leadingAnchor.constraint(equalTo: add.trailingAnchor, constant: 8),
            removeButton.centerYAnchor.constraint(equalTo: add.centerYAnchor),
            done.leadingAnchor.constraint(greaterThanOrEqualTo: removeButton.trailingAnchor, constant: 20),
            done.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: add.centerYAnchor),
            view.bottomAnchor.constraint(equalTo: add.bottomAnchor, constant: 20)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { return identifiers.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = identifiers[row]
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? identifier
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        let bundleLabel = NSTextField(labelWithString: identifier)
        bundleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        bundleLabel.textColor = .secondaryLabelColor
        bundleLabel.lineBreakMode = .byTruncatingMiddle
        let cell = NSStackView(views: [nameLabel, bundleLabel])
        cell.orientation = .vertical
        cell.alignment = .leading
        cell.spacing = 2
        cell.toolTip = identifier
        nameLabel.widthAnchor.constraint(lessThanOrEqualTo: cell.widthAnchor).isActive = true
        bundleLabel.widthAnchor.constraint(lessThanOrEqualTo: cell.widthAnchor).isActive = true
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = table.selectedRow >= 0
    }

    @objc private func addSource() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        // Keep package filtering compatible with macOS 10.13.
        panel.allowedFileTypes = ["app"]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            guard let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty else {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Unable to Add Source", comment: "Invalid source app alert title")
                alert.informativeText = NSLocalizedString("Choose an application with a bundle identifier.", comment: "Invalid source app alert explanation")
                alert.beginSheetModal(for: window, completionHandler: nil)
                return
            }
            if !self.identifiers.contains(identifier) {
                Options.shared.excludedScrollSourceBundleIdentifiers.append(identifier)
                self.table.reloadData()
            }
            if let row = self.identifiers.firstIndex(of: identifier) {
                self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.table.scrollRowToVisible(row)
            }
        }
    }

    @objc private func removeSource() {
        let row = table.selectedRow
        guard identifiers.indices.contains(row) else { return }
        Options.shared.excludedScrollSourceBundleIdentifiers.remove(at: row)
        table.reloadData()
        removeButton.isEnabled = table.selectedRow >= 0
    }

    @objc private func closePanel() {
        dismiss(self)
    }
}
