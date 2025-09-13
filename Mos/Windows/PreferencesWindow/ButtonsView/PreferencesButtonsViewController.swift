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
 * 录制功能
 **/
extension PreferencesButtonsViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // TODO: 持久化实现
    }
    
    // 设置录制按钮回调
    private func setupRecordButtonCallback() {
        createButton.onRecordEnd = { [weak self] event in
            self?.addRecordedEvent(event)
        }
    }
    
    // 添加录制事件到列表
    private func addRecordedEvent(_ event: RecordedEvent) {
        recordedEvents.append(event)
        tableView.reloadData()
        toggleNoDataHint()
    }

    // 删除记录的事件
    func removeRecordedEvent(_ row: Int) {
        recordedEvents.remove(at: row)
        tableView.reloadData()
        toggleNoDataHint()
        // TODO: 持久化
    }
}

/**
 * 表格区域渲染及操作
 **/
extension PreferencesButtonsViewController: NSTableViewDelegate, NSTableViewDataSource {
    // 无数据
    func toggleNoDataHint() {
        let hasData = recordedEvents.count != 0
        updateViewVisibility(view: tableEmpty, visible: !hasData)
        updateViewVisibility(view: createButton, visible: !hasData)
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
            cell.setup(from: self, with: recordedEvents[row], at: row)
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
        return recordedEvents.count
    }
}
