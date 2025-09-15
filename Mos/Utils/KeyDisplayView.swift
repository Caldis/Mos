//
//  KeyDisplayView.swift
//  Mos
//  可复用的按键显示组件
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class KeyDisplayView: NSView {
    
    // MARK: - Constants
    private let fontSize = CGFloat(9)
    private let keyWaiting = "?"

    // MARK: - Configuration
    enum Status {
        case normal        // 普通状态
        case recorded      // 已录制状态（绿色背景）
        case recording     // 录制中状态（呼吸动画）
    }

    // MARK: - Private Properties
    private var keyComponents: [String] = []
    private var status: Status = .normal
    private var keyViews: [NSView] = []
    private var stackView: NSStackView!

    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    private func setupView() {
        wantsLayer = true

        // 创建水平堆栈视图
        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.wantsLayer = true
        stackView.layer?.backgroundColor = CGColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        addSubview(stackView)

        // 默认居中对齐，父组件可以通过约束覆盖
        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
//            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
//            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
//            stackView.trailingAnchor.constraint(greaterThanOrEqualTo: trailingAnchor)
        ])
    }

    // MARK: - Public Methods

    /// 更新显示的按键组合
    func updateKeys(_ components: [String], style: Status = .normal) {
        self.keyComponents = components
        self.status = style

        // 清除现有视图
        clearKeyViews()

        // 如果没有内容，显示空状态
        guard !components.isEmpty else {
            showEmptyState()
            return
        }

        // 创建按键视图
        createKeyViews()
    }

    /// 便利方法：从 RecordedEvent 更新
    func updateWithEvent(_ event: RecordedEvent, style: Status = .normal) {
        let displayName = event.displayName()
        let components = displayName.components(separatedBy: " + ").filter { !$0.isEmpty }
        updateKeys(components, style: style)
    }

    /// 显示录制中状态
    func showRecordingState(withModifiers modifiers: NSEvent.ModifierFlags = NSEvent.ModifierFlags()) {
        let modifierString = modifiers.formattedString()

        if modifierString.isEmpty {
            updateKeys([keyWaiting], style: .recording)
        } else {
            updateKeys([modifierString, keyWaiting], style: .recording)
        }
    }

    // MARK: - Private Methods

    private func clearKeyViews() {
        // 停止所有动画
        keyViews.forEach { keyView in
            keyView.layer?.removeAllAnimations()
        }

        // 移除所有子视图
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        keyViews.removeAll()
    }

    private func showEmptyState() {
        NSLog("showEmptyState")
        let emptyLabel = NSTextField(labelWithString: "No key assigned")
        emptyLabel.font = NSFont.systemFont(ofSize: fontSize)
        emptyLabel.textColor = NSColor.secondaryLabelColor
        emptyLabel.alignment = .center

        stackView.addArrangedSubview(emptyLabel)
    }

    private func createKeyViews() {
        for (index, component) in keyComponents.enumerated() {
            // 添加分隔符
            if index > 0 {
                let plusLabel = NSTextField(labelWithString: "+")
                plusLabel.font = NSFont.systemFont(ofSize: fontSize)
                plusLabel.textColor = NSColor.secondaryLabelColor
                stackView.addArrangedSubview(plusLabel)
            }

            // 创建按键视图
            let keyView = createSingleKeyView(for: component)
            stackView.addArrangedSubview(keyView)
            keyViews.append(keyView)
        }
    }

    private func createSingleKeyView(for text: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        // 根据样式设置背景色
        switch status {
        case .normal:
            container.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        case .recorded:
            container.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case .recording:
            container.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
        // 圆角
        container.layer?.cornerRadius = 4
        // 创建文本标签
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        label.textColor = status == .recorded ? NSColor.white : NSColor.labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        // 设置约束
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 12),
            container.heightAnchor.constraint(equalToConstant: 20),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 20)
        ])
        // 如果是录制状态且内容是 keyWaiting(问号)，添加呼吸动画
        if status == .recording && text == keyWaiting {
            startBreathingAnimation(for: container)
        }
        return container
    }

    private func startBreathingAnimation(for view: NSView) {
        // 创建呼吸动画
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 0.35
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(animation, forKey: "breathingAnimation")
    }

    // MARK: - Intrinsic Content Size
    override var intrinsicContentSize: NSSize {
        // 让父容器决定高度，这里只提供内容宽度
        let stackSize = stackView.fittingSize
        return NSSize(width: max(stackSize.width + 16, 60), height: NSView.noIntrinsicMetric)
    }
}
