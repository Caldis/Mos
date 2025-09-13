//
//  ButtonTableCellView.swift
//  Mos
//  按钮配置表格单元格
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class ButtonTableCellView: NSTableCellView {

    // MARK: - IBOutlets
    @IBOutlet weak var hotkeyLabel: NSTextField!
    @IBOutlet weak var actionPopUpButton: NSPopUpButton!
    @IBOutlet weak var deleteButton: NSButton!

    // MARK: - Data
    private var recordedEvent: RecordedEvent?
    private weak var viewController: PreferencesButtonsViewController?

    // MARK: - Configuration
    func configure(with event: RecordedEvent, viewController: PreferencesButtonsViewController) {
        self.recordedEvent = event
        self.viewController = viewController

        // 配置按键显示
        hotkeyLabel.stringValue = event.displayName()
        hotkeyLabel.textColor = NSColor.labelColor

        // 配置动作选择器
        setupActionPopUpButton()

        // 配置删除按钮
        setupDeleteButton()
    }

    private func setupActionPopUpButton() {
        actionPopUpButton.removeAllItems()

        // TODO: 添加实际的动作选项
        let actions = ["No Action", "Scroll Up", "Scroll Down", "Middle Click"]
        actionPopUpButton.addItems(withTitles: actions)

        // 设置选择回调
        actionPopUpButton.target = self
        actionPopUpButton.action = #selector(actionChanged(_:))
    }

    private func setupDeleteButton() {
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked(_:))
    }

    // MARK: - Actions
    @objc private func actionChanged(_ sender: NSPopUpButton) {
        guard let event = recordedEvent else { return }

        let selectedIndex = sender.indexOfSelectedItem
        // TODO: 保存动作配置到 event 或 UserDefaults
        print("Action changed for \(event.displayName()): \(sender.titleOfSelectedItem ?? "")")
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        guard let event = recordedEvent else { return }

        viewController?.removeRecordedEvent(event)
    }
}