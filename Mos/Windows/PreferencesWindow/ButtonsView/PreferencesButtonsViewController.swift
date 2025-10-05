//
//  PreferencesButtonsViewController.swift
//  Mos
//  按钮绑定配置界面
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesButtonsViewController: NSViewController {

    // MARK: - Recorder
    private var recorder = KeyRecorder()

    // MARK: - Data
    private var buttonBindings: [ButtonBinding] = []

    // MARK: - UI Elements
    // 表格
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableEmpty: NSView!
    @IBOutlet weak var tableFoot: NSView!
    // 按钮
    @IBOutlet weak var createButton: PrimaryButton!
    @IBOutlet weak var addButton: NSButton!
    @IBOutlet weak var delButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置代理
        recorder.delegate = self
        tableView.delegate = self
        tableView.dataSource = self
        // 读取设置
        loadOptionsToView()
    }
    
    override func viewWillAppear() {
        // 检查表格数据
        toggleNoDataHint()
        // 设置录制按钮回调
        setupRecordButtonCallback()
    }

    // 添加
    @IBAction func addItemClick(_ sender: NSButton) {
        recorder.startRecording(from: sender)
    }
    // 删除
    @IBAction func removeItemClick(_ sender: NSButton) {
        // 确保选择了行
        guard tableView.selectedRow != -1 else { return }
        // 删除
        buttonBindings.remove(at: tableView.selectedRow)
        // 重新加载
        tableView.reloadData()
        // 立即更新空状态显示
        toggleNoDataHint()
        // 更新删除按钮状态
        updateDelButtonState()
    }
}

/**
 * 数据持久化
 **/
extension PreferencesButtonsViewController {
    // 从 Options 加载到界面
    func loadOptionsToView() {
        buttonBindings = Options.shared.buttons.binding
        tableView.reloadData()
        toggleNoDataHint()
    }

    // 保存界面到 Options
    func syncViewWithOptions() {
        Options.shared.buttons.binding = buttonBindings
    }

    // 更新删除按钮状态
    func updateDelButtonState() {
        delButton.isEnabled = tableView.selectedRow != -1
    }

    // 设置录制按钮回调
    private func setupRecordButtonCallback() {
        createButton.onMouseDown = { [weak self] target in
            self?.recorder.startRecording(from: target)
        }
    }
    
    // 添加录制事件到列表
    private func addRecordedEvent(_ event: CGEvent, isDuplicate: Bool) {
        let recordedEvent = RecordedEvent(from: event)

        // 如果是重复录制,高亮已存在行
        if isDuplicate {
            if let existing = buttonBindings.first(where: { $0.triggerEvent == recordedEvent }) {
                highlightExistingRow(with: existing.id)
            }
            return
        }

        // 新录制的事件不设置默认快捷键，等待用户选择
        let binding = ButtonBinding(triggerEvent: recordedEvent, systemShortcutName: "", isEnabled: false)
        buttonBindings.append(binding)
        tableView.reloadData()
        toggleNoDataHint()
        syncViewWithOptions()
    }

    // 高亮已存在的行 (用于重复录制的视觉反馈)
    private func highlightExistingRow(with id: UUID) {
        guard let row = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        tableView.deselectAll(nil)
        tableView.scrollRowToVisible(row)
        if let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ButtonTableCellView {
            cellView.highlight()
        }
    }

    // 删除按钮绑定
    func removeButtonBinding(id: UUID) {
        buttonBindings.removeAll(where: { $0.id == id })
        tableView.reloadData()
        toggleNoDataHint()
        syncViewWithOptions()
    }

    // 更新按钮绑定 (用快捷键更新)
    func updateButtonBinding(id: UUID, with shortcut: SystemShortcut.Shortcut) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }

        let oldBinding = buttonBindings[index]
        let shortcutName = SystemShortcut.findShortcut(
            modifiers: shortcut.modifiers,
            keyCode: shortcut.code
        ) ?? "copy"

        let updatedBinding = ButtonBinding(
            id: oldBinding.id,
            triggerEvent: oldBinding.triggerEvent,
            systemShortcutName: shortcutName,
            isEnabled: true
        )

        buttonBindings[index] = updatedBinding
        syncViewWithOptions()
    }
}

/**
 * 表格区域渲染及操作
 **/
extension PreferencesButtonsViewController: NSTableViewDelegate, NSTableViewDataSource {
    // 无数据
    func toggleNoDataHint() {
        let hasData = buttonBindings.count != 0
        updateViewVisibility(view: createButton, visible: !hasData)
        updateViewVisibility(view: tableEmpty, visible: !hasData)
        updateViewVisibility(view: tableFoot, visible: hasData)
    }
    private func updateViewVisibility(view: NSView, visible: Bool) {
        view.isHidden = !visible
        view.animator().alphaValue = visible ? 1 : 0
    }
    
    // 表格数据源
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumnIdentifier = tableColumn?.identifier else { return nil }

        // 创建 Cell
        if let cell = tableView.makeView(withIdentifier: tableColumnIdentifier, owner: self) as? ButtonTableCellView {
            let binding = buttonBindings[row]

            cell.configure(
                with: binding,
                onShortcutSelected: { [weak self] shortcut in
                    self?.updateButtonBinding(id: binding.id, with: shortcut)
                },
                onDeleteRequested: { [weak self] in
                    self?.removeButtonBinding(id: binding.id)
                }
            )
            return cell
        }

        return nil
    }
    
    // 行高
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 44
    }
    
    // 行数
    func numberOfRows(in tableView: NSTableView) -> Int {
        return buttonBindings.count
    }

    // 选择变化
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDelButtonState()
    }

    // Type Selection 支持
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard row < buttonBindings.count else { return nil }
        let components = buttonBindings[row].triggerEvent.displayComponents
        // 去掉第一项（修饰键），只保留实际按键用于匹配
        let keyOnly = components.count > 1 ? Array(components.dropFirst()) : components
        return keyOnly.joined(separator: " ")
    }
}

// MARK: - EventRecorderDelegate
extension PreferencesButtonsViewController: KeyRecorderDelegate {
    // 验证录制的事件是否重复
    func validateRecordedEvent(_ recorder: KeyRecorder, event: CGEvent) -> Bool {
        let recordedEvent = RecordedEvent(from: event)
        // 返回 true = 新录制(绿色), false = 重复(蓝色)
        return !buttonBindings.contains(where: { $0.triggerEvent == recordedEvent })
    }

    // Record 回调 (isDuplicate 由 KeyRecorder 传递,避免重复验证)
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: CGEvent, isDuplicate: Bool) {
        // 添加延迟后调用, 确保不要太早消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) { [weak self] in
            self?.addRecordedEvent(event, isDuplicate: isDuplicate)
        }
    }
}
