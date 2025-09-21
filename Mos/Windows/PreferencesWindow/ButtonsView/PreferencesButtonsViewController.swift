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
    private var recordedEvents: [KeyEvent] = []
    private var recorder = EventRecorder()

    // MARK: - UI Elements
    // 表格
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableEmpty: NSView!
    @IBOutlet weak var tableFoot: NSView!
    // 按钮
    @IBOutlet weak var createButton: PrimaryButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置代理
        recorder.delegate = self
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

    // 添加
    @IBAction func addItemClick(_ sender: NSButton) {
        recorder.startRecording(from: sender)
    }
}

/**
 * 录制和数据持久化
 **/
extension PreferencesButtonsViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // TODO: 持久化实现
    }
    
    // 设置录制按钮回调
    private func setupRecordButtonCallback() {
        createButton.onMouseDown = { [weak self] target in
            self?.recorder.startRecording(from: target)
        }
    }
    
    // 添加录制事件到列表
    private func addRecordedEvent(_ event: KeyEvent) {
        recordedEvents.append(event)
        tableView.reloadData()
        toggleNoDataHint()
        syncViewWithOptions()
    }

    // 删除记录的事件
    func removeRecordedEvent(_ row: Int) {
        recordedEvents.remove(at: row)
        tableView.reloadData()
        toggleNoDataHint()
        syncViewWithOptions()
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

// MARK: - EventRecorderDelegate
extension PreferencesButtonsViewController: EventRecorderDelegate {
    // Record 回调
    func onEventRecorded(_ recorder: EventRecorder, didRecordEvent event: KeyEvent) {
        NSLog("[RecordButton] Recorded event: \(event.displayName())")
        // 添加延迟后调用, 确保不要太早消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) { [weak self] in
            self?.addRecordedEvent(event)
        }
    }
}
