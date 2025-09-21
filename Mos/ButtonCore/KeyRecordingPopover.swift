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
    private var keyPreview: KeyPreview!

    // MARK: - Visibility
    /// 显示录制 popover
    func show(at sourceView: NSView) {
        hide() // 确保之前的 popover 被关闭
        setupPopover()
        popover?.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }
    
    /// 隐藏 popover
    func hide() {
        popover?.close()
        popover = nil
    }

    // MARK: - Status
    /// 更新显示的修饰键状态（录制过程中实时更新）
    func updateForModifiers(_ keyEvent: KeyEvent) {
        // 更新按键显示
        keyPreview.showRecordingState(with: keyEvent)
    }
    
    /// 显示录制完成的按键
    func showRecordedEvent(_ event: KeyEvent) {
        keyPreview.updateWithEvent(event, style: .recorded)
    }

    // MARK: - Private Methods
    private func getContentView() -> NSView {
        let contentView = NSView()
        contentView.wantsLayer = true

        // 创建按键显示组件
        keyPreview = KeyPreview()
        keyPreview.translatesAutoresizingMaskIntoConstraints = false

        // 添加到内容视图
        contentView.addSubview(keyPreview)

        // 设置约束
        NSLayoutConstraint.activate([
            // 按键显示约束
            keyPreview.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            keyPreview.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // 内容视图尺寸约束
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 165),
            contentView.heightAnchor.constraint(equalToConstant: 45)
        ])

        return contentView
    }
    
    private func setupPopover() {
        let newPopover = NSPopover()
        newPopover.contentViewController = NSViewController()
        newPopover.contentViewController?.view = getContentView()
        newPopover.behavior = .transient
        popover = newPopover
    }
}
