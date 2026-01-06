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
    @IBOutlet weak var tableHead: NSVisualEffectView!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableEmpty: NSView!
    @IBOutlet weak var tableFoot: NSView!
    // 按钮
    @IBOutlet weak var createButton: PrimaryButton!
    @IBOutlet weak var addButton: NSButton!
    @IBOutlet weak var delButton: NSButton!
    // 帮助按钮 (programmatically added)
    private var helpButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置代理
        recorder.delegate = self
        tableView.delegate = self
        tableView.dataSource = self
        // 添加额外的表头标签
        setupAdditionalHeaderLabels()
        // 添加帮助按钮
        setupHelpButton()
        // 读取设置
        loadOptionsToView()
    }
    
    // 列位置常量 (从右边缘计算的中心点位置)
    // 这些值会在 ButtonTableCellView 中使用相同的值以保持对齐
    static let appColumnCenterFromTrailing: CGFloat = 20      // Apps 列中心距右边缘
    static let defaultColumnCenterFromTrailing: CGFloat = 70  // Default 列中心距右边缘
    static let actionColumnTrailingFromTrailing: CGFloat = 100  // Action 列右边缘距右边缘
    static let actionColumnCenterFromTrailing: CGFloat = 160  // Action 列中心距右边缘 (用于标题居中)
    
    /// 添加额外的表头标签 (Action, Default, Apps)
    /// 使用固定位置以确保与单元格控件对齐
    private func setupAdditionalHeaderLabels() {
        // 隐藏 storyboard 中原有的 "Action" 标签
        for subview in tableHead.subviews {
            if let textField = subview as? NSTextField,
               textField.stringValue == "Action" {
                textField.isHidden = true
            }
        }
        
        // 创建 Apps 标签
        let appsLabel = NSTextField(labelWithString: NSLocalizedString("button.header.app", comment: ""))
        appsLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        appsLabel.textColor = NSColor.secondaryLabelColor
        appsLabel.alignment = .center
        appsLabel.translatesAutoresizingMaskIntoConstraints = false
        tableHead.addSubview(appsLabel)
        
        // 创建 Default 标签
        let defaultLabel = NSTextField(labelWithString: NSLocalizedString("button.header.default", comment: ""))
        defaultLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        defaultLabel.textColor = NSColor.secondaryLabelColor
        defaultLabel.alignment = .center
        defaultLabel.translatesAutoresizingMaskIntoConstraints = false
        tableHead.addSubview(defaultLabel)
        
        // 创建 Action 标签
        let actionLabel = NSTextField(labelWithString: NSLocalizedString("button.header.action", comment: ""))
        actionLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        actionLabel.textColor = NSColor.secondaryLabelColor
        actionLabel.alignment = .center
        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        tableHead.addSubview(actionLabel)
        
        // 布局约束 - 使用固定位置
        NSLayoutConstraint.activate([
            // Apps 标签
            appsLabel.centerXAnchor.constraint(equalTo: tableHead.trailingAnchor, constant: -Self.appColumnCenterFromTrailing),
            appsLabel.centerYAnchor.constraint(equalTo: tableHead.centerYAnchor),
            
            // Default 标签
            defaultLabel.centerXAnchor.constraint(equalTo: tableHead.trailingAnchor, constant: -Self.defaultColumnCenterFromTrailing),
            defaultLabel.centerYAnchor.constraint(equalTo: tableHead.centerYAnchor),
            
            // Action 标签
            actionLabel.centerXAnchor.constraint(equalTo: tableHead.trailingAnchor, constant: -Self.actionColumnCenterFromTrailing),
            actionLabel.centerYAnchor.constraint(equalTo: tableHead.centerYAnchor),
        ])
    }
    
    /// 添加帮助按钮到 tableFoot 的右下角
    /// 参考 PreferencesApplicationViewController 中的实现方式
    private func setupHelpButton() {
        // 创建帮助按钮，使用与 Application 视图相同的样式
        helpButton = NSButton()
        helpButton.setButtonType(.momentaryPushIn)
        helpButton.bezelStyle = .helpButton
        helpButton.title = ""
        helpButton.target = self
        helpButton.action = #selector(helpButtonClick(_:))
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.controlSize = .mini
        tableFoot.addSubview(helpButton)
        
        NSLayoutConstraint.activate([
            helpButton.trailingAnchor.constraint(equalTo: tableFoot.trailingAnchor, constant: -8),
            helpButton.centerYAnchor.constraint(equalTo: tableFoot.centerYAnchor),
            helpButton.widthAnchor.constraint(equalToConstant: 16),
            helpButton.heightAnchor.constraint(equalToConstant: 16),
        ])
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
        // 统一通过 removeButtonBinding 处理删除逻辑
        let binding = buttonBindings[tableView.selectedRow]
        removeButtonBinding(id: binding.id)
        // 更新删除按钮状态
        updateDelButtonState()
    }
    
    // 帮助按钮 - 显示帮助信息弹出窗口
    /// 参考 Application 视图中的 segue 方式，这里用程序化方式实现相同效果
    @objc private func helpButtonClick(_ sender: NSButton) {
        let helpViewController = ButtonsHelpPopoverViewController()
        present(helpViewController, asPopoverRelativeTo: sender.bounds, of: sender, preferredEdge: .maxY, behavior: .transient)
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

        // 检查是否有相同触发事件的绑定
        let hasExistingBinding = buttonBindings.contains(where: { $0.triggerEvent == recordedEvent })
        
        // 新录制的事件:
        // - 如果已有相同按钮的绑定, 则新绑定的 isDefaultEnabled = false
        // - 如果是全新的按钮, 则新绑定的 isDefaultEnabled = true
        let binding = ButtonBinding(
            triggerEvent: recordedEvent,
            systemShortcutName: "",
            isEnabled: false,
            isDefaultEnabled: !hasExistingBinding  // 如果已有相同按钮的绑定, 新绑定默认关闭
        )
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

    /// 更新按钮绑定
    /// - Parameters:
    ///   - id: 绑定记录的唯一标识
    ///   - shortcut: 系统快捷键对象,nil 表示清除绑定
    func updateButtonBinding(id: UUID, with shortcut: SystemShortcut.Shortcut?) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }

        let oldBinding = buttonBindings[index]

        let updatedBinding: ButtonBinding
        if let shortcut = shortcut {
            // 绑定快捷键:直接使用快捷键的 identifier
            updatedBinding = ButtonBinding(
                id: oldBinding.id,
                triggerEvent: oldBinding.triggerEvent,
                systemShortcutName: shortcut.identifier,
                isEnabled: true,
                isDefaultEnabled: oldBinding.isDefaultEnabled,
                disabledApplications: oldBinding.disabledApplications,
                enabledApplications: oldBinding.enabledApplications
            )
        } else {
            // 清除绑定:保持触发事件,清空快捷键名称并禁用
            updatedBinding = ButtonBinding(
                id: oldBinding.id,
                triggerEvent: oldBinding.triggerEvent,
                systemShortcutName: "",
                isEnabled: false,
                isDefaultEnabled: oldBinding.isDefaultEnabled,
                disabledApplications: oldBinding.disabledApplications,
                enabledApplications: oldBinding.enabledApplications
            )
        }

        buttonBindings[index] = updatedBinding
        syncViewWithOptions()
    }
    
    /// 更新按钮绑定的默认启用状态
    /// - Parameters:
    ///   - id: 绑定记录的唯一标识
    ///   - isDefaultEnabled: 是否默认启用
    func updateButtonBindingDefaultMode(id: UUID, isDefaultEnabled: Bool) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        
        var binding = buttonBindings[index]
        
        // 如果启用默认模式,需要禁用同一触发事件的其他绑定的默认模式
        if isDefaultEnabled {
            let triggerEvent = binding.triggerEvent
            for i in 0..<buttonBindings.count {
                if buttonBindings[i].triggerEvent == triggerEvent && buttonBindings[i].id != id {
                    buttonBindings[i].isDefaultEnabled = false
                }
            }
        }
        
        binding.isDefaultEnabled = isDefaultEnabled
        buttonBindings[index] = binding
        syncViewWithOptions()
        
        // 刷新表格以更新其他行的显示
        tableView.reloadData()
    }
    
    /// 更新按钮绑定的禁用应用列表
    /// - Parameters:
    ///   - id: 绑定记录的唯一标识
    ///   - apps: 禁用应用列表
    func updateButtonBindingDisabledApps(id: UUID, apps: [ButtonApplicationRule]) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        
        var binding = buttonBindings[index]
        binding.disabledApplications = apps
        buttonBindings[index] = binding
        syncViewWithOptions()
    }
    
    /// 更新按钮绑定的启用应用列表
    /// - Parameters:
    ///   - id: 绑定记录的唯一标识
    ///   - apps: 启用应用列表
    func updateButtonBindingEnabledApps(id: UUID, apps: [ButtonApplicationRule]) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        
        var binding = buttonBindings[index]
        binding.enabledApplications = apps
        buttonBindings[index] = binding
        syncViewWithOptions()
    }
    
    /// 获取指定绑定
    /// - Parameter id: 绑定记录的唯一标识
    /// - Returns: ButtonBinding 对象,如果不存在返回 nil
    func getButtonBinding(id: UUID) -> ButtonBinding? {
        return buttonBindings.first { $0.id == id }
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
        updateViewVisibility(view: tableHead, visible: hasData)
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
                },
                onDefaultToggleChanged: { [weak self] isDefaultEnabled in
                    self?.updateButtonBindingDefaultMode(id: binding.id, isDefaultEnabled: isDefaultEnabled)
                },
                onAppSettingsRequested: { [weak self] in
                    self?.showAppSettingsPopover(for: binding, from: cell)
                }
            )
            return cell
        }

        return nil
    }
    
    /// 显示应用设置弹出窗口
    private func showAppSettingsPopover(for binding: ButtonBinding, from cell: ButtonTableCellView) {
        // 获取最新的 binding 数据，而不是使用 cell 配置时捕获的旧数据
        guard let freshBinding = getButtonBinding(id: binding.id) else { return }
        
        let popoverVC = ButtonAppSettingsPopoverViewController()
        popoverVC.configure(
            with: freshBinding,
            onDisabledAppsChanged: { [weak self] apps in
                self?.updateButtonBindingDisabledApps(id: binding.id, apps: apps)
            },
            onEnabledAppsChanged: { [weak self] apps in
                self?.updateButtonBindingEnabledApps(id: binding.id, apps: apps)
            },
            onDefaultModeChanged: { [weak self] isDefaultEnabled in
                self?.updateButtonBindingDefaultMode(id: binding.id, isDefaultEnabled: isDefaultEnabled)
                // 刷新 cell 显示
                self?.tableView.reloadData()
            }
        )
        
        // 使用 .semitransient 允许在弹窗中交互而不自动关闭
        present(popoverVC, asPopoverRelativeTo: cell.bounds, of: cell, preferredEdge: .maxX, behavior: .semitransient)
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
    // 验证录制的事件是否重复 - 现在允许重复,始终返回 true
    func validateRecordedEvent(_ recorder: KeyRecorder, event: CGEvent) -> Bool {
        // 始终返回 true,允许为同一个按钮添加多个绑定
        return true
    }

    // Record 回调
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: CGEvent, isDuplicate: Bool) {
        // 添加延迟后调用, 确保不要太早消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) { [weak self] in
            // isDuplicate 参数现在忽略,因为我们允许重复
            self?.addRecordedEvent(event, isDuplicate: false)
        }
    }
}
