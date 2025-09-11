//
//  PreferencesButtonsViewController.swift
//  Mos
//  按钮绑定配置界面
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesButtonsViewController: NSViewController {
    
    // MARK: - Data
    private var recordedEvents: [RecordedEvent] = []
    
    // MARK: - UI Elements
    // 表格
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableEmpty: NSView!
    // 按钮
    @IBOutlet weak var createButton: CreateRecordsButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置表格代理
        tableView.delegate = self
        tableView.dataSource = self
        // 读取设置
        syncViewWithOptions()
    }
    
    override func viewWillAppear() {
        // 检查表格数据
        toggleNoDataHint()
        // 设置录制按钮回调
        setupRecordButtonCallback()
    }
}

/**
 * 设置同步
 **/
extension PreferencesButtonsViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // TODO: 实现按钮相关设置的同步逻辑
    }
    
    // 设置录制按钮回调
    private func setupRecordButtonCallback() {
        createButton.onRecordEnd = { [weak self] event in
            self?.addRecordedEvent(event)
        }
    }
    
    // 添加记录的事件到列表
    private func addRecordedEvent(_ event: RecordedEvent) {
        recordedEvents.append(event)
        tableView.reloadData()
        toggleNoDataHint()
    }
}

/**
 * 表格区域渲染及操作
 **/
extension PreferencesButtonsViewController: NSTableViewDelegate, NSTableViewDataSource {
    // Cell Identifiers (需要与 Storyboard 中设置的 identifier 匹配)
    fileprivate enum CellIdentifiers {
        static let hotkeyCell = "HotkeyCell"    // Hotkey 列
        static let actionCell = "ActionCell"     // Item 1 列
    }
    
    // 切换无数据显示
    func toggleNoDataHint() {
        let hasData = recordedEvents.count != 0
        updateViewVisibility(view: tableEmpty, visible: !hasData)
        updateViewVisibility(view: createButton, visible: !hasData)
    }
    
    private func updateViewVisibility(view: NSView, visible: Bool) {
        view.isHidden = !visible
        view.animator().alphaValue = visible ? 1 : 0
    }
    
    // 表格数据源方法
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumnIdentifier = tableColumn?.identifier,
              let cell = tableView.makeView(withIdentifier: tableColumnIdentifier, owner: self) as? NSTableCellView,
              row < recordedEvents.count else {
            return nil
        }
        
        let event = recordedEvents[row]
        configureCellForColumn(cell: cell, columnId: tableColumnIdentifier.rawValue, event: event, row: row)
        return cell
    }
    
    private func configureCellForColumn(cell: NSTableCellView, columnId: String, event: RecordedEvent, row: Int) {
        switch columnId {
        case CellIdentifiers.hotkeyCell:
            configureHotkeyCell(cell: cell, event: event)
        case CellIdentifiers.actionCell:
            configureActionCell(cell: cell, row: row)
        default:
            break
        }
    }
    
    private func configureHotkeyCell(cell: NSTableCellView, event: RecordedEvent) {
        // 根据 Storyboard 层级：Table Cell View > Box > View > Hotkey Label
        // 使用 viewWithTag 或者层级访问找到 Hotkey 标签
        if let hotkeyLabel = findHotkeyLabel(in: cell) {
            hotkeyLabel.stringValue = event.displayName()
            hotkeyLabel.textColor = NSColor.labelColor
        }
    }
    
    private func findHotkeyLabel(in cell: NSTableCellView) -> NSTextField? {
        // 最佳实践：先尝试使用 tag 查找 (建议在 Storyboard 中设置 Hotkey Label tag = 100)
        if let labelWithTag = cell.viewWithTag(100) as? NSTextField {
            return labelWithTag
        }
        
        // 备用方案：根据层级结构查找 cell > box > view > hotkey label
        for subview in cell.subviews {
            if let box = subview as? NSBox {
                for boxSubview in box.subviews {
                    if let view = boxSubview as? NSView {
                        for viewSubview in view.subviews {
                            if let label = viewSubview as? NSTextField {
                                return label
                            }
                        }
                    }
                }
            }
        }
        
        // 最后备用方案：递归搜索所有 NSTextField
        return findTextFieldRecursively(in: cell)
    }
    
    private func findTextFieldRecursively(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField {
            return textField
        }
        
        for subview in view.subviews {
            if let found = findTextFieldRecursively(in: subview) {
                return found
            }
        }
        
        return nil
    }
    
    private func configureActionCell(cell: NSTableCellView, row: Int) {
        cell.textField?.stringValue = "TODO: Action"
    }
    
    // 行高
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 44
    }
    
    // 行数
    func numberOfRows(in tableView: NSTableView) -> Int {
        return recordedEvents.count
    }
}
