//
//  KeyPreview.swift
//  Mos
//  可复用的按键显示组件
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class KeyPreview: NSStackView {

    // MARK: - Constants
    static let FONT_SIZE = CGFloat(9)
    static let WAITING_WORDING = "?"

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
        update(from: [KeyPreview.WAITING_WORDING], status: .recording)
    }

    // MARK: - Public Methods

    /// 更新显示的按键组合
    func update(from components: [String], status: Status = .normal) {
        self.keyComponents = components
        self.status = status

        // 清除现有视图
        clearKeyViews()

        // 如果没有内容，不显示
        guard !components.isEmpty else { return }

        // 创建按键视图
        createKeyViews()
    }

    /// 显示录制中状态
    func updateForRecording(from event: CGEvent) {
        if event.hasModifiers {
            update(from: [event.modifierString, KeyPreview.WAITING_WORDING], status: .recording)
        } else {
            update(from: [KeyPreview.WAITING_WORDING], status: .recording)
        }
    }

    /// 显示警告反馈(不可录制的按键)
    /// 对WAITING_WORDING对应的keyView执行黄色+晃动动画
    func shakeWarning() {
        // 找到WAITING_WORDING对应的view
        guard let waitingView = findWaitingView() else { return }
        guard let layer = waitingView.layer else { return }

        // 停止呼吸动画,避免和警告动画冲突
        layer.removeAnimation(forKey: "breathingAnimation")
        layer.opacity = 1.0

        // 1. 晃动动画
        let shakeAnimation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shakeAnimation.values = [0, -8, 8, -8, 8, -4, 4, 0]
        shakeAnimation.duration = 0.4
        shakeAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // 2. 背景色变化动画
        let warningColor: CGColor
        if Utils.isDarkMode(for: self) {
            // Dark模式: 较深的红色
            warningColor = NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.20, alpha: 1.0).cgColor
        } else {
            // Light模式: 明亮的红色
            warningColor = NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.30, alpha: 1.0).cgColor
        }

        let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
        colorAnimation.toValue = warningColor
        colorAnimation.duration = 0.3
        colorAnimation.autoreverses = true
        colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // 执行动画
        layer.add(shakeAnimation, forKey: "shakeWarning")
        layer.add(colorAnimation, forKey: "colorWarning")

        // 动画结束后恢复呼吸动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            // 只有在recording状态才恢复呼吸动画
            if self.status == .recording {
                self.startBreathingAnimation(for: waitingView)
            }
        }
    }

    /// 查找WAITING_WORDING对应的keyView
    private func findWaitingView() -> NSView? {
        guard let waitingIndex = keyComponents.firstIndex(of: KeyPreview.WAITING_WORDING) else {
            return nil
        }
        guard waitingIndex < keyViews.count else {
            return nil
        }
        return keyViews[waitingIndex]
    }

    // MARK: - View and anim control
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
                plusLabel.font = NSFont.systemFont(ofSize: KeyPreview.FONT_SIZE)
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
        // 创建一个能动态响应外观变化的容器
        let container = KeyComponentContainer(keyStatus: status)

        // 创建文本标签
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: KeyPreview.FONT_SIZE, weight: .medium)
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
        if status == .recording && text == KeyPreview.WAITING_WORDING {
            startBreathingAnimation(for: container)
        }

        return container
    }
    private func startBreathingAnimation(for view: NSView) {
        // 创建呼吸动画
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.5
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(animation, forKey: "breathingAnimation")
    }
}

// MARK: - KeyComponentContainer
/// 按键组件容器，通过 updateLayer 动态响应外观变化
private final class KeyComponentContainer: NSView {
    let keyStatus: KeyPreview.Status

    init(keyStatus: KeyPreview.Status) {
        self.keyStatus = keyStatus
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = getBackgroundColor().cgColor
    }

    private func getBackgroundColor() -> NSColor {
        switch keyStatus {
        case .normal, .recording:
            return NSColor.quaternaryLabelColor
        case .recorded:
            return Utils.isDarkMode(for: self)
                ? NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.30, alpha: 1.0)
                : NSColor(calibratedRed: 0.25, green: 0.70, blue: 0.35, alpha: 1.0)
        }
    }
}

