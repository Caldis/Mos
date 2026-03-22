//
//  ToastManager.swift
//  Mos
//  Toast 多实例生命周期管理 - 堆叠、去重、淘汰、动画
//

import Cocoa

/// 管理多个 Toast 的生命周期
///
/// 每个 toast 拥有独立 NSPanel, 用屏幕绝对坐标定位。
/// 系统阴影 (hasShadow) 自然跟随 panel.alphaValue 淡出。
class ToastManager {

    static let shared = ToastManager()

    // MARK: - Active Toasts

    /// 活跃的 toast 条目 (按创建顺序，最旧在前)
    private var activeToasts: [ToastEntry] = []

    /// Toast 条目 (仅主线程使用)
    struct ToastEntry: @unchecked Sendable {
        let id: UInt
        let panel: NSPanel
        let contentView: ToastContentView
        var dismissTimer: Timer?
        let message: String
    }

    /// 递增 ID 生成器
    private var nextId: UInt = 0

    // MARK: - State

    private var currentStackDirection: ToastWindow.StackDirection = .down

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anchorDidChange),
            name: .toastAnchorDidChange,
            object: nil
        )
    }

    // MARK: - Present

    func present(message: String, style: Toast.Style, duration: TimeInterval, icon: NSImage?) {
        // 可见集合去重：检查当前所有可见 toast 是否已有相同消息
        if activeToasts.contains(where: { $0.message == message }) {
            return
        }

        let maxCount = ToastStorage.shared.maxCount

        // 溢出淘汰：超出 maxCount 时，淡出最旧的
        while activeToasts.count >= maxCount {
            dismissOldest(animated: true)
        }

        // 首个 toast 时初始化方向
        if activeToasts.isEmpty {
            recalculateDirection()
        }

        // 创建新 toast
        let resolvedIcon = icon ?? ToastContentView.defaultIcon(for: style)
        let accentColor = ToastContentView.accentColor(for: style)
        let contentView = ToastContentView(message: message, icon: resolvedIcon, accentColor: accentColor)
        let panel = ToastWindow.shared.createPanel(for: contentView)

        // 创建条目
        let id = nextId
        nextId &+= 1
        var entry = ToastEntry(id: id, panel: panel, contentView: contentView, dismissTimer: nil, message: message)

        // 设置自动消失
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss(id: id)
        }
        entry.dismissTimer = timer
        activeToasts.append(entry)

        // 新 toast = depth 0 (最前面, 紧贴锚点)
        let anchorPoint = ToastStorage.shared.savedPosition ?? defaultAnchorPoint()
        let origin = ToastWindow.shared.screenOrigin(
            forDepth: 0,
            toastSize: panel.frame.size,
            anchorPoint: anchorPoint,
            direction: currentStackDirection
        )
        panel.setFrameOrigin(origin)

        // 淡入: 先透明显示, 再动画到不透明
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        })

        // 已有 toast 被推开: 重新计算所有 toast 的层叠深度和位置
        repositionAllToasts(animated: true)
    }

    // MARK: - Dismiss

    /// 关闭指定 ID 的 toast
    func dismiss(id: UInt) {
        guard let index = activeToasts.firstIndex(where: { $0.id == id }) else { return }
        let entry = activeToasts.remove(at: index)
        entry.dismissTimer?.invalidate()

        // 淡出 panel (系统阴影自然跟随)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            entry.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            entry.panel.orderOut(nil)
            // 剩余 toast 归位
            self?.repositionAllToasts(animated: true)
        })
    }

    /// 关闭所有 toast
    func dismissAll() {
        let toasts = activeToasts
        activeToasts.removeAll()

        for entry in toasts {
            entry.dismissTimer?.invalidate()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                entry.panel.animator().alphaValue = 0
            }, completionHandler: {
                entry.panel.orderOut(nil)
            })
        }
    }

    /// 淘汰最旧的 toast
    private func dismissOldest(animated: Bool) {
        guard !activeToasts.isEmpty else { return }
        let entry = activeToasts.removeFirst()
        entry.dismissTimer?.invalidate()

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                entry.panel.animator().alphaValue = 0
            }, completionHandler: {
                entry.panel.orderOut(nil)
            })
        } else {
            entry.panel.orderOut(nil)
        }
    }

    // MARK: - Layout

    /// 计算默认锚点位置 (屏幕上方 1/5 居中)
    func defaultAnchorPoint() -> NSPoint {
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = screen else { return .zero }
        let visibleFrame = targetScreen.visibleFrame
        let x = visibleFrame.midX
        let y = visibleFrame.origin.y + visibleFrame.height - visibleFrame.height / 5.0
        return NSPoint(x: x, y: y)
    }

    /// 计算堆叠方向
    func stackDirection(for anchorPoint: NSPoint) -> ToastWindow.StackDirection {
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = screen else { return .down }
        let visibleFrame = targetScreen.visibleFrame
        let midY = visibleFrame.origin.y + visibleFrame.height / 2.0
        return anchorPoint.y > midY ? .down : .up
    }

    /// 重新计算堆叠方向 (仅在初始化和拖拽松手时调用)
    private func recalculateDirection() {
        let anchorPoint = ToastStorage.shared.savedPosition ?? defaultAnchorPoint()
        currentStackDirection = stackDirection(for: anchorPoint)
        ToastWindow.shared.currentStackDirection = currentStackDirection
    }

    /// 重新定位所有 toast (基于层叠深度)
    ///
    /// 数组末尾 = 最新 = depth 0 (最前, 紧贴锚点)
    /// 数组头部 = 最旧 = depth N-1 (最后, 最远)
    private func repositionAllToasts(animated: Bool) {
        let anchorPoint = ToastStorage.shared.savedPosition ?? defaultAnchorPoint()
        let count = activeToasts.count

        for (arrayIndex, entry) in activeToasts.enumerated() {
            // 最新的在末尾 (depth 0), 最旧的在头部 (depth count-1)
            let depth = count - 1 - arrayIndex

            let targetOrigin = ToastWindow.shared.screenOrigin(
                forDepth: depth,
                toastSize: entry.panel.frame.size,
                anchorPoint: anchorPoint,
                direction: currentStackDirection
            )

            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    entry.panel.animator().setFrameOrigin(targetOrigin)
                })
            } else {
                entry.panel.setFrameOrigin(targetOrigin)
            }
        }
    }

    // MARK: - MaxCount Change

    /// maxCount 变更时调用 (由 ToastPanel 触发)
    func applyMaxCountChange() {
        let maxCount = ToastStorage.shared.maxCount

        // 超出部分立即淘汰
        while activeToasts.count > maxCount {
            dismissOldest(animated: true)
        }

        // 重新布局
        repositionAllToasts(animated: true)
    }

    // MARK: - Anchor Change

    @objc private func anchorDidChange() {
        recalculateDirection()
        repositionAllToasts(animated: true)
    }

    // MARK: - Screen Helpers

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        return nil
    }
}
