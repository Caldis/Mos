//
//  ToastWindow.swift
//  Mos
//  Toast 窗口工厂 - 每个 toast 独立 NSPanel, 自带系统阴影
//

import Cocoa

/// Toast 窗口管理
///
/// 每个 toast 拥有独立的 NSPanel, 系统阴影 (hasShadow) 自然跟随淡出动画。
/// 拖拽任一 toast 移动锚点, 松手后其他 toast 动画归位。
class ToastWindow {

    static let shared = ToastWindow()

    // MARK: - Stack Direction (set by ToastManager)

    var currentStackDirection: ToastStackDirection = .down

    // MARK: - Panel Factory

    /// 为单个 toast 创建独立 NSPanel
    func createPanel(for contentView: ToastContentView) -> NSPanel {
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize

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
        panel.ignoresMouseEvents = false
        panel.contentView = contentView

        return panel
    }

    // MARK: - Positioning (屏幕绝对坐标)

    /// 计算 toast 的屏幕位置
    ///
    /// - Parameters:
    ///   - toastSize: toast 的尺寸
    ///   - anchorPoint: 锚点 (屏幕坐标)
    ///   - direction: 堆叠方向
    ///   - offsetFromAnchor: 与锚点的累计偏移, 由所有更靠近锚点的 toast 高度和间距累加得到
    func screenOrigin(toastSize: NSSize, anchorPoint: NSPoint, direction: ToastStackDirection, offsetFromAnchor: CGFloat) -> NSPoint {
        return ToastLayout.origin(
            toastSize: toastSize,
            anchorPoint: anchorPoint,
            direction: direction,
            offsetFromAnchor: offsetFromAnchor
        )
    }
}

// MARK: - Layout Constants

enum ToastLayoutConstants {
    static let spacing: CGFloat = 8
    static let containerWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 10
}

// MARK: - Notifications

extension Notification.Name {
    static let toastAnchorDidChange = Notification.Name("toastAnchorDidChange")
}
