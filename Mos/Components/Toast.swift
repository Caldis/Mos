//
//  Toast.swift
//  Mos
//  轻量级 Toast 通知组件 - 浮动半透明提示, 支持多显示器、队列去重、自动消失
//  Created by Mos on 2026/3/22.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - Toast (Public API)

/// 轻量级 Toast 通知
///
/// 在鼠标所在屏幕的上方区域显示一条短暂的浮动提示, 不会抢占焦点。
///
/// 基本用法:
/// ```swift
/// Toast.show("当前设备不支持此功能")
/// Toast.show("Hi-Res 滚轮已开启", style: .success)
/// Toast.show("当前设备不支持 Hi-Res 滚轮", style: .warning)
/// ```
struct Toast {

    /// 提示样式
    enum Style {
        /// 中性提示, 用于一般信息
        case info
        /// 绿色强调, 用于操作确认
        case success
        /// 橙色强调, 用于警告/不支持的功能
        case warning
        /// 红色强调, 用于错误
        case error
    }

    /// 显示一条 Toast 通知
    ///
    /// - Parameters:
    ///   - message: 提示文本 (建议不超过两行)
    ///   - style: 提示样式, 默认为 `.info`
    ///   - duration: 显示时长 (秒), 默认 2.5 秒
    ///   - icon: 自定义图标, 传 nil 则使用样式默认图标
    static func show(_ message: String, style: Style = .info, duration: TimeInterval = 2.5, icon: NSImage? = nil) {
        // 始终异步调度到主线程
        // 即使已在主线程也必须 async, 因为调用方可能在 IOKit/CGEventTap 等
        // RunLoop source 回调中, 同步创建 NSPanel 会导致 RunLoop 递归死锁
        DispatchQueue.main.async {
            ToastWindow.shared.present(message: message, style: style, duration: duration, icon: icon)
        }
    }
}

// MARK: - ToastWindow (Window Management)

/// Toast 窗口管理器 (内部使用)
///
/// 单例模式, 负责窗口的创建、显示、定时消失和去重。
/// 新的 `present()` 调用会立即替换当前正在显示的内容, 不做堆叠。
private class ToastWindow {

    static let shared = ToastWindow()

    // MARK: - Properties

    private var panel: NSPanel?
    private var contentView: ToastContentView?
    private var dismissTimer: Timer?

    /// 上一条消息及其时间戳, 用于去重
    private var lastMessage: String?
    private var lastMessageTime: TimeInterval = 0

    /// 代际计数器, 防止旧的淡出 completion 清除新复用的 panel
    private var generation: UInt = 0

    /// 去重间隔 (秒): 同一条消息在此时间内不会重复显示
    private let deduplicateInterval: TimeInterval = 0.5

    // MARK: - Presentation

    func present(message: String, style: Toast.Style, duration: TimeInterval, icon: NSImage?) {
        // 去重: 短时间内相同消息不再重复弹出
        let now = ProcessInfo.processInfo.systemUptime
        if message == lastMessage && (now - lastMessageTime) < deduplicateInterval {
            return
        }
        lastMessage = message
        lastMessageTime = now

        // 取消正在进行的消失计时, 递增 generation 使旧的淡出 completion 失效
        dismissTimer?.invalidate()
        dismissTimer = nil
        generation &+= 1

        // 准备内容
        let resolvedIcon = icon ?? Self.defaultIcon(for: style)
        let accentColor = Self.accentColor(for: style)

        if let existingPanel = panel, let existingContent = contentView {
            // 已有窗口: 更新内容并重新定位
            existingContent.update(message: message, icon: resolvedIcon, accentColor: accentColor)
            existingContent.layoutSubtreeIfNeeded()
            let size = existingContent.fittingSize
            existingPanel.setContentSize(size)
            positionPanel(existingPanel, size: size)

            // 如果窗口当前是透明的 (正在淡出), 重新淡入
            if existingPanel.alphaValue < 1.0 {
                animateAppear(existingPanel)
            }
        } else {
            // 创建新窗口
            let content = ToastContentView(message: message, icon: resolvedIcon, accentColor: accentColor)
            content.layoutSubtreeIfNeeded()
            let size = content.fittingSize

            let newPanel = createPanel(contentView: content, size: size)
            positionPanel(newPanel, size: size)

            panel = newPanel
            contentView = content

            // 显示并执行淡入动画
            newPanel.alphaValue = 0
            newPanel.orderFrontRegardless()
            animateAppear(newPanel)
        }

        // 设置自动消失
        scheduleDismiss(after: duration)
    }

    // MARK: - Panel Creation

    private func createPanel(contentView: NSView, size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.contentView = contentView
        return panel
    }

    // MARK: - Positioning

    /// 将窗口定位到鼠标所在屏幕的上方 1/5 区域, 水平居中
    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = screen else { return }

        let visibleFrame = targetScreen.visibleFrame
        let x = visibleFrame.origin.x + (visibleFrame.width - size.width) / 2.0
        // setFrameOrigin 使用窗口左下角坐标, 需减去窗口高度
        let y = visibleFrame.origin.y + visibleFrame.height - visibleFrame.height / 5.0 - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 获取包含鼠标指针的屏幕
    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        return nil
    }

    // MARK: - Animation

    private func animateAppear(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        })
    }

    private func animateDisappear(_ panel: NSPanel, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    // MARK: - Dismiss

    private func scheduleDismiss(after duration: TimeInterval) {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let existingPanel = panel else { return }
        let dismissGeneration = generation
        animateDisappear(existingPanel) { [weak self] in
            guard let self = self, self.generation == dismissGeneration else { return }
            self.panel?.orderOut(nil)
            self.panel = nil
            self.contentView = nil
            self.lastMessage = nil
        }
    }

    // MARK: - Style Helpers

    /// 根据样式返回默认图标
    private static func defaultIcon(for style: Toast.Style) -> NSImage? {
        if #available(macOS 11.0, *) {
            let symbolName: String
            switch style {
            case .info:    symbolName = "info.circle.fill"
            case .success: symbolName = "checkmark.circle.fill"
            case .warning: symbolName = "exclamationmark.triangle.fill"
            case .error:   symbolName = "xmark.circle.fill"
            }
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
        // macOS 10.13-10.15: 使用系统内置图标作为 fallback
        switch style {
        case .info:    return NSImage(named: NSImage.infoName)
        case .success: return NSImage(named: NSImage.statusAvailableName)
        case .warning: return NSImage(named: NSImage.cautionName)
        case .error:   return NSImage(named: NSImage.stopProgressFreestandingTemplateName)
        }
    }

    /// 根据样式返回强调色
    private static func accentColor(for style: Toast.Style) -> NSColor? {
        switch style {
        case .info:
            return nil // 无特殊强调
        case .success:
            return NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0)
        case .warning:
            return NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.20, alpha: 1.0)
        case .error:
            return NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.30, alpha: 1.0)
        }
    }
}

// MARK: - ToastContentView (Rendering)

/// Toast 内容视图 (内部使用)
///
/// 使用 NSVisualEffectView 实现毛玻璃背景, 包含可选图标和文本标签。
private class ToastContentView: NSView {

    // MARK: - Subviews

    private let effectView: NSVisualEffectView
    private let iconView: NSImageView
    private let messageLabel: NSTextField
    private let accentIndicator: NSView

    // MARK: - Constants

    private let cornerRadius: CGFloat = 10
    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 8
    private let iconSize: CGFloat = 20
    private let iconMessageSpacing: CGFloat = 8
    private let accentIndicatorWidth: CGFloat = 3

    // MARK: - State

    private var hasIcon: Bool = false
    private var hasAccent: Bool = false

    // MARK: - Initialization

    init(message: String, icon: NSImage?, accentColor: NSColor?) {
        effectView = NSVisualEffectView()
        iconView = NSImageView()
        messageLabel = NSTextField(labelWithString: "")
        accentIndicator = NSView()

        super.init(frame: .zero)

        setupEffectView()
        setupIconView()
        setupMessageLabel()
        setupAccentIndicator()
        setupLayout()

        update(message: message, icon: icon, accentColor: accentColor)
    }

    required init?(coder: NSCoder) {
        fatalError("ToastContentView does not support Interface Builder")
    }

    // MARK: - Setup

    private func setupEffectView() {
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.state = .active
        effectView.blendingMode = .behindWindow

        // 根据系统版本选择最佳视觉效果
        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
            effectView.appearance = NSAppearance(named: .vibrantDark)
        } else {
            effectView.material = .dark
        }

        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
    }

    private func setupIconView() {
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        // 默认隐藏, 有图标时再显示
        iconView.isHidden = true
        effectView.addSubview(iconView)
    }

    private func setupMessageLabel() {
        messageLabel.font = NSFont.systemFont(ofSize: 13)
        // 在 vibrantDark / dark material 下, labelColor 自动为白色
        // 如果未来改为跟随系统外观, labelColor 也会自动适应
        messageLabel.textColor = NSColor.labelColor
        messageLabel.backgroundColor = .clear
        messageLabel.isBezeled = false
        messageLabel.isEditable = false
        messageLabel.isSelectable = false
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.cell?.truncatesLastVisibleLine = true
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(messageLabel)
    }

    private func setupAccentIndicator() {
        accentIndicator.wantsLayer = true
        accentIndicator.layer?.cornerRadius = accentIndicatorWidth / 2.0
        accentIndicator.isHidden = true
        accentIndicator.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(accentIndicator)
    }

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // 毛玻璃背景填充整个视图
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            // 强调指示条 (左侧竖线)
            accentIndicator.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 5),
            accentIndicator.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            accentIndicator.widthAnchor.constraint(equalToConstant: accentIndicatorWidth),
            accentIndicator.heightAnchor.constraint(equalTo: effectView.heightAnchor, multiplier: 0.5),

            // 图标
            iconView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            // 文本标签
            messageLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: verticalPadding),
            messageLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -verticalPadding),
            messageLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -horizontalPadding),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
    }

    // MARK: - Update Content

    func update(message: String, icon: NSImage?, accentColor: NSColor?) {
        // 更新文本
        messageLabel.stringValue = message

        // 更新图标
        if let img = icon {
            let tintedIcon = tintImage(img, color: accentColor ?? NSColor.white)
            iconView.image = tintedIcon
            iconView.isHidden = false
            hasIcon = true
        } else {
            iconView.image = nil
            iconView.isHidden = true
            hasIcon = false
        }

        // 更新强调指示条
        if let color = accentColor {
            accentIndicator.layer?.backgroundColor = color.cgColor
            accentIndicator.isHidden = false
            hasAccent = true
        } else {
            accentIndicator.isHidden = true
            hasAccent = false
        }

        // 动态调整 messageLabel 的 leading 约束
        updateMessageLeadingConstraint()
    }

    // MARK: - Dynamic Layout

    /// 根据是否有图标/强调色动态调整消息标签的左边距
    private var messageLeadingConstraint: NSLayoutConstraint?

    private func updateMessageLeadingConstraint() {
        // 移除旧约束
        if let old = messageLeadingConstraint {
            old.isActive = false
        }

        let leadingOffset: CGFloat
        if hasIcon {
            // 图标右侧
            leadingOffset = horizontalPadding + iconSize + iconMessageSpacing
        } else if hasAccent {
            // 强调条右侧
            leadingOffset = 5 + accentIndicatorWidth + horizontalPadding
        } else {
            // 无图标无强调条
            leadingOffset = horizontalPadding
        }

        let constraint = messageLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: leadingOffset)
        constraint.isActive = true
        messageLeadingConstraint = constraint
    }

    // MARK: - Image Tinting

    /// 对图标进行着色 (兼容 macOS 10.13+)
    private func tintImage(_ image: NSImage, color: NSColor) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        // 绘制原始图标
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0)
        // 用指定颜色叠加着色 (仅对非透明像素生效)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

}
