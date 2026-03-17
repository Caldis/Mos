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
    static let VIEW_SIZE = CGFloat(25)
    static let FONT_SIZE = CGFloat(11)
    static let WAITING_WORDING = "?"

    // MARK: - Configuration
    enum Status {
        case normal        // 普通状态
        case recorded      // 已录制状态（绿色背景）
        case duplicate     // 重复录制状态（蓝色背景）
        case recording     // 录制中状态（呼吸动画）
    }

    // MARK: - Private Properties
    private var keyComponents: [String] = []
    private var status: Status = .normal
    private var keyViews: [NSView] = []
    private var waitingView: KeyComponentContainer?

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
    /// 对WAITING_WORDING对应的keyView执行红色+晃动动画
    func shakeWarning() {
        waitingView?.shakeWarning()
    }

    // MARK: - View and anim control
    private func clearKeyViews() {
        // 移除所有子视图
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        keyViews.removeAll()
        waitingView = nil
    }
    private static let logiTagMarker = "[Logi]"

    private func createKeyViews() {
        var i = 0
        var viewIndex = 0  // 用于决定是否加 "+" 分隔符
        while i < keyComponents.count {
            let component = keyComponents[i]

            // 跳过 [Logi] 标记 (已在前一个 component 中处理)
            if component == KeyPreview.logiTagMarker { i += 1; continue }

            // 添加分隔符
            if viewIndex > 0 {
                let plusLabel = NSTextField(labelWithString: "+")
                plusLabel.font = NSFont.systemFont(ofSize: KeyPreview.FONT_SIZE)
                plusLabel.textColor = NSColor.secondaryLabelColor
                addArrangedSubview(plusLabel)
            }

            // 检查下一个是否为 [Logi] 标记 → 嵌套渲染
            let nextIsLogi = (i + 1 < keyComponents.count && keyComponents[i + 1] == KeyPreview.logiTagMarker)
            let isWaiting = (component == KeyPreview.WAITING_WORDING)

            if nextIsLogi && !isWaiting {
                let keyView = createKeyViewWithLogiTag(for: component)
                addArrangedSubview(keyView)
                keyViews.append(keyView)
                i += 2  // 跳过 [Logi]
            } else {
                let keyView = createSingleKeyView(for: component, isWaiting: isWaiting)
                addArrangedSubview(keyView)
                keyViews.append(keyView)
                if isWaiting, let container = keyView as? KeyComponentContainer {
                    waitingView = container
                }
                i += 1
            }
            viewIndex += 1
        }
    }

    /// 创建带嵌套 Logi tag 的按键视图 (按键名 + 小 tag 在同一个容器内)
    private func createKeyViewWithLogiTag(for text: String) -> NSView {
        let container = KeyComponentContainer(keyStatus: status, isWaiting: false)

        // 按键名标签
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: KeyPreview.FONT_SIZE, weight: .medium)
        label.textColor = (status == .recorded || status == .duplicate) ? NSColor.white : NSColor.labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        // Logi 小 tag
        let tagBg = NSView()
        tagBg.wantsLayer = true
        tagBg.layer?.cornerRadius = 2.5
        tagBg.layer?.backgroundColor = NSColor(calibratedRed: 0.0, green: 0.992, blue: 0.812, alpha: 1.0).cgColor
        tagBg.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tagBg)

        let tagLabel = NSTextField(labelWithString: "Logi")
        tagLabel.font = NSFont.systemFont(ofSize: 7, weight: .bold)
        tagLabel.textColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
        tagLabel.alignment = .center
        tagLabel.translatesAutoresizingMaskIntoConstraints = false
        tagBg.addSubview(tagLabel)

        NSLayoutConstraint.activate([
            // 按键名: 左侧居中
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            // Tag: 紧跟按键名右侧
            tagBg.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            tagBg.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            tagBg.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            // Tag 内部
            tagLabel.centerXAnchor.constraint(equalTo: tagBg.centerXAnchor),
            tagLabel.centerYAnchor.constraint(equalTo: tagBg.centerYAnchor, constant: -0.5),
            tagBg.widthAnchor.constraint(equalTo: tagLabel.widthAnchor, constant: 5),
            tagBg.heightAnchor.constraint(equalToConstant: 12),
            // 容器高度
            container.heightAnchor.constraint(equalToConstant: KeyPreview.VIEW_SIZE),
        ])

        return container
    }
    private func createSingleKeyView(for text: String, isWaiting: Bool) -> NSView {
        // 创建一个能动态响应外观变化的容器
        let container = KeyComponentContainer(keyStatus: status, isWaiting: isWaiting)

        // 创建文本标签
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: KeyPreview.FONT_SIZE, weight: .medium)
        label.textColor = (status == .recorded || status == .duplicate) ? NSColor.white : NSColor.labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        // 设置约束
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 12),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: KeyPreview.VIEW_SIZE),
            container.heightAnchor.constraint(equalToConstant: KeyPreview.VIEW_SIZE),
        ])

        return container
    }
}

// MARK: - KeyComponentContainer
/// 按键组件容器，通过 updateLayer 动态响应外观变化
private final class KeyComponentContainer: NSView {
    let keyStatus: KeyPreview.Status
    let isWaitingPlaceholder: Bool

    init(keyStatus: KeyPreview.Status, isWaiting: Bool = false) {
        self.keyStatus = keyStatus
        self.isWaitingPlaceholder = isWaiting
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4

        // 如果是录制状态的等待占位符，启动呼吸动画
        if keyStatus == .recording && isWaitingPlaceholder {
            startBreathingAnimation()
        }
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
            return NSColor.getMainLightBlack(for: self)
        case .recorded:
            return NSColor.mainGreen
        case .duplicate:
            return NSColor.mainBlue
        }
    }

    // MARK: - Animation Management
    private func startBreathingAnimation() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.5
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(animation, forKey: "breathingAnimation")
    }

    func shakeWarning() {
        guard let layer = layer else { return }

        // 停止呼吸动画，避免冲突
        layer.removeAnimation(forKey: "breathingAnimation")
        layer.opacity = 1.0

        // 1. 晃动动画
        let shakeAnimation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shakeAnimation.values = [0, -8, 8, -8, 8, -4, 4, 0]
        shakeAnimation.duration = 0.4
        shakeAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // 2. 背景色变化动画（立即变红，然后褪回原色）
        let warningColor: CGColor = NSColor.getWarningColor(for: self).cgColor
        let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
        colorAnimation.fromValue = warningColor  // 从红色开始
        colorAnimation.toValue = layer.backgroundColor  // 褪回原色
        colorAnimation.duration = 0.8  // 和晃动动画同步
        colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // 执行动画
        layer.add(shakeAnimation, forKey: "shakeWarning")
        layer.add(colorAnimation, forKey: "colorWarning")

        // 动画结束后恢复呼吸动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.keyStatus == .recording {
                self.startBreathingAnimation()
            }
        }
    }
}

