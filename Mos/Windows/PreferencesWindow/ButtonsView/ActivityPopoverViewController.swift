//
//  ActivityPopoverViewController.swift
//  Mos
//  Hover popover 内容: 一行或多行描述 Logi HID 当前活动 (phase / 设备 / 进度).
//  继承 AdaptivePopover 复用组件级的"按内容自适应 popover 尺寸"逻辑
//  (AdaptivePopover 会在 viewDidLoad / viewDidLayout 里自动读第一个 subview 的
//  intrinsicContentSize / fittingSize 并补 12pt 水平 + 10pt 垂直 padding).
//  Created by Mos on 2026/4/25.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

class ActivityPopoverViewController: AdaptivePopover {

    /// popover 最大内容宽度; 短文本时 fittingSize 小于此值 popover 会收窄, 长文本换行不超过该宽度.
    /// 取值和冲突 popover 的 preferredMaxLayoutWidth=280 对齐, 保持视觉一致.
    static let maxContentWidth: CGFloat = 256

    private let label: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        // 决定 intrinsicContentSize 的换行上界; fittingSize 会在此宽度内计算高度.
        l.preferredMaxLayoutWidth = maxContentWidth
        return l
    }()

    override func loadView() {
        // label 必须是 view.subviews.first — AdaptivePopover 以此为 contentView 读 size,
        // 并把 preferredContentSize 设为 contentSize + 24(h) + 20(v).
        // 它不负责 subview 的定位: 我们需要手动把 label 居中到 container,
        // 否则 popover 放大后 label 依旧贴在 (0,0) 左下角, 右上留白.
        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        view = container
    }

    /// 更新文案并让 AdaptivePopover 重新计算 preferredContentSize (popover 窗口随之变大小).
    func setMessage(_ text: String) {
        label.stringValue = text
        view.needsLayout = true
        updatePreferredContentSize()
    }
}
