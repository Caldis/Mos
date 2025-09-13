//
//  RecordingPopover.swift
//  Mos
//  录制按键时显示的 Popover UI 组件
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class RecordingPopover: NSObject {

    // MARK: - Properties
    private var popover: NSPopover?
    private var keyDisplayView: KeyDisplayView!
    private var instructionLabel: NSTextField!
    private var contentView: NSView!

    // MARK: - Public Methods

    /// 显示录制 popover
    func show(at sourceView: NSView, instruction: String = "Press any key...") {
        hide() // 确保之前的 popover 被关闭

        setupContentView(instruction: instruction)
        setupPopover()
        popover?.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }

    /// 隐藏 popover
    func hide() {
        popover?.close()
        popover = nil
    }

    /// 更新显示的修饰键状态（录制过程中实时更新）
    func updateForModifiers(_ modifiers: NSEvent.ModifierFlags) {
        // 隐藏指导文字，显示按键预览
        instructionLabel.isHidden = true
        keyDisplayView.isHidden = false

        // 更新按键显示
        keyDisplayView.showRecordingState(withModifiers: modifiers)
    }

    /// 显示录制完成的按键
    func showRecordedEvent(_ event: RecordedEvent) {
        instructionLabel.isHidden = true
        keyDisplayView.isHidden = false

        keyDisplayView.updateWithEvent(event, style: .recorded)
    }

    /// 显示取消录制状态
    func showCancelledState() {
        instructionLabel.isHidden = false
        keyDisplayView.isHidden = true
    }

    // MARK: - Private Methods

    private func setupContentView(instruction: String) {
        let contentController = NSViewController()
        contentView = NSView()
        contentView.wantsLayer = true

        // 创建指导文字标签
        instructionLabel = NSTextField(labelWithString: NSLocalizedString(instruction, comment: ""))
        instructionLabel.font = NSFont.systemFont(ofSize: 13)
        instructionLabel.textColor = NSColor.secondaryLabelColor
        instructionLabel.alignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false

        // 创建按键显示组件
        keyDisplayView = KeyDisplayView()
        keyDisplayView.translatesAutoresizingMaskIntoConstraints = false
        keyDisplayView.isHidden = true // 初始隐藏

        // 添加到内容视图
        contentView.addSubview(instructionLabel)
        contentView.addSubview(keyDisplayView)

        // 设置约束
        NSLayoutConstraint.activate([
            // 指导文字约束
            instructionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            instructionLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // 按键显示约束
            keyDisplayView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            keyDisplayView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // 内容视图尺寸约束
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 165),
            contentView.heightAnchor.constraint(equalToConstant: 50)
        ])

        contentController.view = contentView
        popover?.contentViewController = contentController
    }

    private func setupPopover() {
        let newPopover = NSPopover()
        newPopover.contentViewController = NSViewController()
        newPopover.behavior = .transient

        // 先设置内容控制器，再设置内容视图
        setupContentView(instruction: "Press any key...")
        newPopover.contentViewController?.view = contentView

        popover = newPopover
    }
}
