//
//  KeyPopover.swift
//  Mos
//  录制按键时显示的 Popover UI 组件
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class KeyPopover: NSObject {
    private enum RecordingHint {
        case escape
        case duplicate

        var localizedText: String {
            switch self {
            case .escape:
                return NSLocalizedString("Press ESC to cancel recording", comment: "ESC hint in key recording popover")
            case .duplicate:
                return NSLocalizedString("button-recording-duplicate-hint", comment: "Duplicate key hint in key recording popover")
            }
        }
    }

    // MARK: - Properties
    private var popover: NSPopover?
    var keyPreview: KeyPreview!
    private var hintLabel: NSTextField?
    private var hintHeightConstraint: NSLayoutConstraint?
    private var hintBottomConstraint: NSLayoutConstraint?
    private var contentView: NSView?

    // MARK: - Constants
    private let baseHeight: CGFloat = 45
    private let hintHeight: CGFloat = 18
    private let hiddenHintBottomPadding: CGFloat = 10
    private let visibleHintBottomPadding: CGFloat = 5

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

    // MARK: - Public Methods
    /// 显示 ESC 退出提示
    func showEscHint() {
        showHint(.escape)
    }

    /// 显示重复录制提示
    func showDuplicateHint() {
        showHint(.duplicate)
    }

    private func showHint(_ hint: RecordingHint) {
        guard let label = hintLabel,
              let heightConstraint = hintHeightConstraint else { return }

        label.stringValue = hint.localizedText
        hintBottomConstraint?.constant = -visibleHintBottomPadding
        guard heightConstraint.constant == 0 else { return }

        guard popover?.isShown == true else {
            label.alphaValue = 1
            heightConstraint.constant = hintHeight
            updatePopoverContentSize()
            return
        }

        // 动画展开提示
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ANIMATION.duration
            context.allowsImplicitAnimation = true
            label.animator().alphaValue = 1
            heightConstraint.animator().constant = hintHeight
        }, completionHandler: { [weak self] in
            self?.updatePopoverContentSize()
        })
    }

#if DEBUG
    func testingPrepareContent() {
        hide()
        setupPopover()
    }

    var testingHintText: String? {
        hintLabel?.stringValue
    }

    var testingHintFontPointSize: CGFloat? {
        hintLabel?.font?.pointSize
    }

    var testingHintAlignment: NSTextAlignment? {
        hintLabel?.alignment
    }

    var testingHintBottomPadding: CGFloat? {
        hintBottomConstraint.map { abs($0.constant) }
    }
#endif

    // MARK: - Private Methods
    private func updatePopoverContentSize() {
        contentView?.layout()
        if let size = contentView?.fittingSize {
            popover?.contentSize = size
        }
    }

    private func getContentView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        contentView = view

        // 创建按键显示组件
        keyPreview = KeyPreview()
        keyPreview.translatesAutoresizingMaskIntoConstraints = false
        // 创建录制提示标签
        let hintLabel = NSTextField(labelWithString: RecordingHint.escape.localizedText)
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = NSColor.secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.alphaValue = 0
        hintLabel.setContentHuggingPriority(.required, for: .vertical)
        self.hintLabel = hintLabel

        // 创建高度约束（初始为 0）
        let heightConstraint = hintLabel.heightAnchor.constraint(equalToConstant: 0)
        hintHeightConstraint = heightConstraint
        let bottomConstraint = hintLabel.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -hiddenHintBottomPadding
        )
        hintBottomConstraint = bottomConstraint

        // 添加到内容视图
        view.addSubview(keyPreview)
        view.addSubview(hintLabel)

        // 设置约束
        NSLayoutConstraint.activate([
            // 按键显示约束
            keyPreview.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            keyPreview.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),

            // 录制提示约束
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: keyPreview.bottomAnchor, constant: 4),
            bottomConstraint,
            heightConstraint,

            // 内容视图宽度约束
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 165),
        ])

        return view
    }

    private func setupPopover() {
        let newPopover = NSPopover()
        newPopover.contentViewController = NSViewController()
        newPopover.contentViewController?.view = getContentView()
        newPopover.behavior = .transient
        popover = newPopover
    }
}
