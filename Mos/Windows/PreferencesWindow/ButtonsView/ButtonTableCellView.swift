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
    @IBOutlet weak var keyDisplayContainerView: NSView!
    @IBOutlet weak var actionPopUpButton: NSPopUpButton!
    @IBOutlet weak var deleteButton: NSButton!

    // MARK: - UI Components
    private var keyDisplayView: KeyDisplayView!

    // MARK: - Data
    private weak var viewController: PreferencesButtonsViewController? // 父容器视图
    private var recordedEvent: RecordedEvent? // 事件
    private var row: Int?

    // MARK: - 初始化内容
    func setup(from viewController: PreferencesButtonsViewController, with event: RecordedEvent, at row: Int) {
        self.viewController = viewController
        self.recordedEvent = event
        self.row = row

        // 配置按键显示组件
        setupKeyDisplayView()
        keyDisplayView.updateWithEvent(event, style: .normal)

        // 配置动作选择器
        setupActionPopUpButton()

        // 配置删除按钮
        setupDeleteButton()
    }

    // 创建按键视图
    private func setupKeyDisplayView() {
        // 如果已经创建过，先移除
        keyDisplayView?.removeFromSuperview()

        // 创建新的 KeyDisplayView
        keyDisplayView = KeyDisplayView()
        keyDisplayView.translatesAutoresizingMaskIntoConstraints = false

        // 添加到容器视图
        keyDisplayContainerView.addSubview(keyDisplayView)

        // 靠左对齐，高度自适应
        NSLayoutConstraint.activate([
            keyDisplayView.leadingAnchor.constraint(equalTo: keyDisplayContainerView.leadingAnchor),
            keyDisplayView.centerYAnchor.constraint(equalTo: keyDisplayContainerView.centerYAnchor),
            keyDisplayView.trailingAnchor.constraint(lessThanOrEqualTo: keyDisplayContainerView.trailingAnchor)
        ])
    }
    
    // 设置动作按钮
    private func setupActionPopUpButton() {
        actionPopUpButton.removeAllItems()

        // TODO: 添加实际的动作选项
        let actions = ["No Action", "Scroll Up", "Scroll Down", "Middle Click"]
        actionPopUpButton.addItems(withTitles: actions)

        // 设置选择回调
        actionPopUpButton.target = self
        actionPopUpButton.action = #selector(actionChanged(_:))
    }

    // 设置删除按钮
    private func setupDeleteButton() {
        deleteButton.target = self
        deleteButton.action = #selector(deleteRecord(_:))
    }

    // MARK: - Actions
    // 切换动作
    @objc private func actionChanged(_ sender: NSPopUpButton) {
        guard let event = recordedEvent else { return }

        // let selectedIndex = sender.indexOfSelectedItem
        // TODO: 保存动作配置到 event 或 UserDefaults
        print("Action changed for \(event.displayName()): \(sender.titleOfSelectedItem ?? "")")
    }

    // 删除绑定
    @objc private func deleteRecord(_ sender: NSButton) {
        guard let row = self.row else { return }
        viewController?.removeRecordedEvent(row)
    }
}
