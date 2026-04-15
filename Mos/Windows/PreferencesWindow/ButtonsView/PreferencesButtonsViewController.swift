//
//  PreferencesButtonsViewController.swift
//  Mos
//  按钮绑定 + 鼠标手势配置界面
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

// MARK: - ViewMode

private enum ViewMode {
    case bindings
    case gestures
}

// MARK: - PreferencesButtonsViewController

class PreferencesButtonsViewController: NSViewController {

    // MARK: - Recorder
    private var recorder = KeyRecorder()

    // MARK: - Data
    private var buttonBindings: [ButtonBinding] = []
    private var gestureBindings: [GestureBinding] = []

    // MARK: - Mode
    private var currentMode: ViewMode = .bindings

    // MARK: - UI Elements
    // 表格
    @IBOutlet weak var tableHead: NSVisualEffectView!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableEmpty: NSView!
    @IBOutlet weak var tableFoot: NSView!
    // 按钮
    @IBOutlet weak var createButton: PrimaryButton!
    @IBOutlet weak var addButton: NSButton!
    @IBOutlet weak var delButton: NSButton!

    // 模式切换
    private var segmentedControl: NSSegmentedControl!

    // 手势 Cell 标识
    private static let gestureCellIdentifier = NSUserInterfaceItemIdentifier("gestureCellView")

    override func viewDidLoad() {
        super.viewDidLoad()
        recorder.delegate = self
        tableView.delegate = self
        tableView.dataSource = self
        setupSegmentedControl()
        loadOptionsToView()
    }

    override func viewWillAppear() {
        toggleNoDataHint()
        setupRecordButtonCallback()
    }

    // MARK: - Segmented Control Setup

    private func setupSegmentedControl() {
        let labels = [
            NSLocalizedString("bindings", comment: ""),
            NSLocalizedString("gestures", comment: ""),
        ]
        segmentedControl = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: self,
            action: #selector(segmentChanged(_:))
        )
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        tableFoot.addSubview(segmentedControl)

        // Move +/- buttons to the trailing edge so they don't overlap the segmented control.
        // The storyboard placed addButton at leading+6 and delButton immediately after it.
        // Deactivate those conflicting constraints before adding new trailing ones.
        for constraint in tableFoot.constraints {
            let firstView  = constraint.firstItem  as? NSView
            let secondView = constraint.secondItem as? NSView
            let touchesButton = (firstView === addButton || firstView === delButton ||
                                 secondView === addButton || secondView === delButton)
            if touchesButton {
                constraint.isActive = false
            }
        }

        NSLayoutConstraint.activate([
            // Segmented control: leading
            segmentedControl.leadingAnchor.constraint(equalTo: tableFoot.leadingAnchor, constant: 8),
            segmentedControl.centerYAnchor.constraint(equalTo: tableFoot.centerYAnchor),

            // Delete button: trailing edge
            delButton.trailingAnchor.constraint(equalTo: tableFoot.trailingAnchor, constant: -6),
            delButton.centerYAnchor.constraint(equalTo: tableFoot.centerYAnchor),

            // Add button: immediately to the left of delete button
            addButton.trailingAnchor.constraint(equalTo: delButton.leadingAnchor, constant: -2),
            addButton.centerYAnchor.constraint(equalTo: tableFoot.centerYAnchor),
        ])
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        currentMode = sender.selectedSegment == 0 ? .bindings : .gestures
        tableView.reloadData()
        toggleNoDataHint()
        updateDelButtonState()
    }

    // MARK: - 添加/删除

    @IBAction func addItemClick(_ sender: NSButton) {
        recorder.startRecording(from: sender)
    }

    @IBAction func removeItemClick(_ sender: NSButton) {
        guard tableView.selectedRow != -1 else { return }
        switch currentMode {
        case .bindings:
            let binding = buttonBindings[tableView.selectedRow]
            removeButtonBinding(id: binding.id)
        case .gestures:
            let binding = gestureBindings[tableView.selectedRow]
            removeGestureBinding(id: binding.id)
        }
        updateDelButtonState()
    }
}

// MARK: - Data Persistence

extension PreferencesButtonsViewController {

    func loadOptionsToView() {
        buttonBindings = Options.shared.buttons.binding
        gestureBindings = Options.shared.gestures.binding
        tableView.reloadData()
        toggleNoDataHint()
    }

    // 保存按钮绑定并同步 HID++ divert
    func syncButtonsWithOptions() {
        Options.shared.buttons.binding = buttonBindings
        ButtonUtils.shared.invalidateCache()
        LogitechHIDManager.shared.syncDivertWithBindings()
    }

    // 保存手势绑定
    func syncGesturesWithOptions() {
        Options.shared.gestures.binding = gestureBindings
        GestureProcessor.shared.invalidateCache()
    }

    func updateDelButtonState() {
        delButton.isEnabled = tableView.selectedRow != -1
    }

    private func setupRecordButtonCallback() {
        createButton.onMouseDown = { [weak self] target in
            self?.recorder.startRecording(from: target)
        }
    }

    // MARK: - Button Binding CRUD

    private func addButtonRecordedEvent(_ event: InputEvent, isDuplicate: Bool) {
        let recordedEvent = RecordedEvent(from: event)
        if isDuplicate {
            if let existing = buttonBindings.first(where: { $0.triggerEvent == recordedEvent }) {
                highlightExistingRow(with: existing.id)
            }
            return
        }
        let binding = ButtonBinding(triggerEvent: recordedEvent, systemShortcutName: "", isEnabled: false)
        buttonBindings.append(binding)
        tableView.reloadData()
        toggleNoDataHint()
        syncButtonsWithOptions()
    }

    private func highlightExistingRow(with id: UUID) {
        guard let row = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        tableView.deselectAll(nil)
        tableView.scrollRowToVisible(row)
        if let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ButtonTableCellView {
            cellView.highlight()
        }
    }

    func removeButtonBinding(id: UUID) {
        buttonBindings.removeAll(where: { $0.id == id })
        tableView.reloadData()
        toggleNoDataHint()
        syncButtonsWithOptions()
    }

    func updateButtonBinding(id: UUID, with shortcut: SystemShortcut.Shortcut?) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        let old = buttonBindings[index]
        if let shortcut = shortcut {
            buttonBindings[index] = ButtonBinding(id: old.id, triggerEvent: old.triggerEvent, systemShortcutName: shortcut.identifier, isEnabled: true)
        } else {
            buttonBindings[index] = ButtonBinding(id: old.id, triggerEvent: old.triggerEvent, systemShortcutName: "", isEnabled: false)
        }
        syncButtonsWithOptions()
    }

    func updateButtonBinding(id: UUID, withCustomName name: String) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        let old = buttonBindings[index]
        buttonBindings[index] = ButtonBinding(id: old.id, triggerEvent: old.triggerEvent, systemShortcutName: name, isEnabled: true, createdAt: old.createdAt)
        syncButtonsWithOptions()
    }

    // MARK: - Gesture Binding CRUD

    private func addGestureRecordedEvent(_ event: InputEvent, isDuplicate: Bool) {
        let recordedEvent = RecordedEvent(from: event)
        if isDuplicate {
            // 高亮已存在的手势行 (无特殊 highlight 方法, 只滚动到可见)
            if let row = gestureBindings.firstIndex(where: { $0.triggerEvent == recordedEvent }) {
                tableView.deselectAll(nil)
                tableView.scrollRowToVisible(row)
            }
            return
        }
        let binding = GestureBinding(triggerEvent: recordedEvent)
        gestureBindings.append(binding)
        tableView.reloadData()
        toggleNoDataHint()
        syncGesturesWithOptions()
    }

    func removeGestureBinding(id: UUID) {
        gestureBindings.removeAll(where: { $0.id == id })
        tableView.reloadData()
        toggleNoDataHint()
        syncGesturesWithOptions()
    }

    func updateGestureBinding(id: UUID, direction: GestureDirection, shortcut: SystemShortcut.Shortcut?) {
        guard let index = gestureBindings.firstIndex(where: { $0.id == id }) else { return }
        gestureBindings[index] = gestureBindings[index].withAction(shortcut?.identifier, for: direction)
        syncGesturesWithOptions()
    }

    func updateGestureScrollAction(id: UUID, direction: GestureDirection, shortcut: SystemShortcut.Shortcut?) {
        guard let index = gestureBindings.firstIndex(where: { $0.id == id }) else { return }
        gestureBindings[index] = gestureBindings[index].withScrollAction(shortcut?.identifier, for: direction)
        syncGesturesWithOptions()
    }
}

// MARK: - Table View Delegate & Data Source

extension PreferencesButtonsViewController: NSTableViewDelegate, NSTableViewDataSource {

    func toggleNoDataHint() {
        let rowCount = currentRowCount
        let hasData = rowCount != 0
        updateViewVisibility(view: createButton, visible: !hasData)
        updateViewVisibility(view: tableEmpty, visible: !hasData)
        updateViewVisibility(view: tableHead, visible: hasData)
        // tableFoot always visible so the segmented control stays accessible
        updateViewVisibility(view: tableFoot, visible: true)
    }

    private func updateViewVisibility(view: NSView, visible: Bool) {
        view.isHidden = !visible
        view.animator().alphaValue = visible ? 1 : 0
    }

    private var currentRowCount: Int {
        switch currentMode {
        case .bindings: return buttonBindings.count
        case .gestures: return gestureBindings.count
        }
    }

    // MARK: - Data Source

    func numberOfRows(in tableView: NSTableView) -> Int {
        return currentRowCount
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumnIdentifier = tableColumn?.identifier else { return nil }

        switch currentMode {
        case .bindings:
            if let cell = tableView.makeView(withIdentifier: tableColumnIdentifier, owner: self) as? ButtonTableCellView {
                let binding = buttonBindings[row]
                cell.configure(
                    with: binding,
                    onShortcutSelected: { [weak self] shortcut in
                        self?.updateButtonBinding(id: binding.id, with: shortcut)
                    },
                    onCustomShortcutRecorded: { [weak self] customName in
                        self?.updateButtonBinding(id: binding.id, withCustomName: customName)
                    },
                    onDeleteRequested: { [weak self] in
                        self?.removeButtonBinding(id: binding.id)
                    }
                )
                return cell
            }

        case .gestures:
            var cell = tableView.makeView(withIdentifier: Self.gestureCellIdentifier, owner: self) as? GestureTableCellView
            if cell == nil {
                cell = GestureTableCellView(frame: .zero)
                cell?.identifier = Self.gestureCellIdentifier
            }
            if let cell = cell {
                let binding = gestureBindings[row]
                cell.configure(
                    with: binding,
                    onMovementActionChanged: { [weak self] direction, shortcut in
                        self?.updateGestureBinding(id: binding.id, direction: direction, shortcut: shortcut)
                    },
                    onScrollActionChanged: { [weak self] direction, shortcut in
                        self?.updateGestureScrollAction(id: binding.id, direction: direction, shortcut: shortcut)
                    },
                    onDeleteRequested: { [weak self] in
                        self?.removeGestureBinding(id: binding.id)
                    }
                )
                return cell
            }
        }

        return nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch currentMode {
        case .bindings: return 44
        case .gestures: return 150
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDelButtonState()
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        switch currentMode {
        case .bindings:
            guard row < buttonBindings.count else { return nil }
            let components = buttonBindings[row].triggerEvent.displayComponents
            let keyOnly = components.count > 1 ? Array(components.dropFirst()) : components
            return keyOnly.joined(separator: " ")
        case .gestures:
            guard row < gestureBindings.count else { return nil }
            let components = gestureBindings[row].triggerEvent.displayComponents
            let keyOnly = components.count > 1 ? Array(components.dropFirst()) : components
            return keyOnly.joined(separator: " ")
        }
    }
}

// MARK: - KeyRecorderDelegate

extension PreferencesButtonsViewController: KeyRecorderDelegate {

    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        let recordedEvent = RecordedEvent(from: event)
        switch currentMode {
        case .bindings:
            return !buttonBindings.contains(where: { $0.triggerEvent == recordedEvent })
        case .gestures:
            return !gestureBindings.contains(where: { $0.triggerEvent == recordedEvent })
        }
    }

    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) { [weak self] in
            guard let self = self else { return }
            switch self.currentMode {
            case .bindings:
                self.addButtonRecordedEvent(event, isDuplicate: isDuplicate)
            case .gestures:
                self.addGestureRecordedEvent(event, isDuplicate: isDuplicate)
            }
        }
    }
}
