//
//  KeyDisplayView.swift
//  Mos
//  可复用的按键显示组件
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class KeyDisplayView: NSStackView {
    
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
        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // 显示空状态
        updateKeys([keyWaiting], style: .recording)
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
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        keyViews.removeAll()
    }
    
    private func createKeyViews() {
        for (index, component) in keyComponents.enumerated() {
            // 添加分隔符
            if index > 0 {
                let plusLabel = NSTextField(labelWithString: "+")
                plusLabel.font = NSFont.systemFont(ofSize: fontSize)
                plusLabel.textColor = NSColor.secondaryLabelColor
                addArrangedSubview(plusLabel)
            }

            // 创建按键视图
            let keyView = createSingleKeyView(for: component)
            addArrangedSubview(keyView)
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
            if Utils.isDarkMode(for: self) {
                // Dark 模式：较深的绿色，降低亮度
                container.layer?.backgroundColor = NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.30, alpha: 1.0).cgColor
            } else {
                // Light 模式：柔和的绿色，保持可读性
                container.layer?.backgroundColor = NSColor(calibratedRed: 0.25, green: 0.70, blue: 0.35, alpha: 1.0).cgColor
            }
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
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            container.heightAnchor.constraint(equalToConstant: 20),
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
}

