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
        var isDismissing: Bool
    }

    /// 递增 ID 生成器
    private var nextId: UInt = 0

    // MARK: - State

    private var currentStackDirection: ToastStackDirection = .down
    private var transientAnchorPoint: NSPoint?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anchorDidChange),
            name: .toastAnchorDidChange,
            object: nil
        )
    }

    // MARK: - Present

    func present(
        message: String,
        style: Toast.Style,
        duration: TimeInterval,
        icon: NSImage?,
        allowDuplicateVisibleMessage: Bool = false
    ) {
        // 可见集合去重：淡出中的 toast 仍然在屏幕上，因此也参与去重
        if !allowDuplicateVisibleMessage,
           ToastVisibilityRules.containsVisibleMessage(message, in: visibilityEntries()) {
            return
        }

        let maxCount = ToastStorage.shared.maxCount

        // 溢出淘汰：仅 active toast 参与容量限制，淡出中的不阻塞新 toast
        while ToastVisibilityRules.activeCount(in: visibilityEntries()) >= maxCount {
            dismissOldest(animated: true)
        }

        // 首个 active toast 时固定本轮默认锚点，避免鼠标换屏后整组 toast 跳动
        if ToastVisibilityRules.activeCount(in: visibilityEntries()) == 0,
           ToastStorage.shared.savedPosition == nil {
            transientAnchorPoint = defaultAnchorPoint()
        }

        // 首个 active toast 时初始化方向
        if ToastVisibilityRules.activeCount(in: visibilityEntries()) == 0 {
            recalculateDirection()
        }

        // 创建新 toast
        let resolvedIcon = icon ?? ToastContentView.defaultIcon(for: style)
        let accentColor = ToastContentView.accentColor(for: style)
        let contentView = ToastContentView(
            message: message,
            icon: resolvedIcon,
            accentColor: accentColor,
            showsAccentIndicator: ToastStorage.shared.showsAccentIndicator
        )
        let panel = ToastWindow.shared.createPanel(for: contentView)

        // 创建条目
        let id = nextId
        nextId &+= 1
        var entry = ToastEntry(
            id: id,
            panel: panel,
            contentView: contentView,
            dismissTimer: nil,
            message: message,
            isDismissing: false
        )

        // 设置自动消失
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss(id: id)
        }
        entry.dismissTimer = timer
        activeToasts.append(entry)

        // 新 toast = depth 0 (最前面, 紧贴锚点)
        let anchorPoint = resolvedAnchorPoint()
        let origin = ToastWindow.shared.screenOrigin(
            toastSize: panel.frame.size,
            anchorPoint: anchorPoint,
            direction: currentStackDirection,
            offsetFromAnchor: 0
        )
        panel.setFrameOrigin(origin)

        // 淡入: 先透明显示, 再动画到不透明
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // 已有 toast 被推开: 重新计算所有 toast 的层叠深度和位置
        repositionAllToasts(animated: true)
    }

    // MARK: - Dismiss

    /// 关闭指定 ID 的 toast
    func dismiss(id: UInt) {
        guard let index = activeToasts.firstIndex(where: { $0.id == id }) else { return }
        guard !activeToasts[index].isDismissing else { return }

        activeToasts[index].dismissTimer?.invalidate()
        activeToasts[index].dismissTimer = nil
        activeToasts[index].isDismissing = true
        let entry = activeToasts[index]

        // 淡出 panel (系统阴影自然跟随)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            entry.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            entry.panel.orderOut(nil)
            self?.removeToast(id: id)
            // 剩余 toast 归位
            self?.repositionAllToasts(animated: true)
        })
    }

    /// 关闭所有 toast
    func dismissAll() {
        let activeIds = activeToasts.filter { !$0.isDismissing }.map { $0.id }
        for id in activeIds {
            dismiss(id: id)
        }
    }

    /// 淘汰最旧的 toast
    private func dismissOldest(animated: Bool) {
        guard let index = ToastVisibilityRules.oldestActiveIndex(in: visibilityEntries()) else { return }
        activeToasts[index].dismissTimer?.invalidate()
        activeToasts[index].dismissTimer = nil
        activeToasts[index].isDismissing = true
        let entry = activeToasts[index]

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                entry.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                entry.panel.orderOut(nil)
                self?.removeToast(id: entry.id)
                self?.repositionAllToasts(animated: true)
            })
        } else {
            entry.panel.orderOut(nil)
            removeToast(id: entry.id)
        }
    }

    // MARK: - Layout

    /// 计算默认锚点位置 (屏幕上方 1/5 居中)
    func defaultAnchorPoint() -> NSPoint {
        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = screen else { return .zero }
        return ToastLayout.defaultAnchorPoint(in: targetScreen.visibleFrame)
    }

    /// 计算堆叠方向
    func stackDirection(for anchorPoint: NSPoint) -> ToastStackDirection {
        let screen = screenContaining(point: anchorPoint) ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = screen else { return .down }
        return ToastLayout.stackDirection(for: anchorPoint, in: targetScreen.visibleFrame)
    }

    /// 重新计算堆叠方向 (仅在初始化和拖拽松手时调用)
    private func recalculateDirection() {
        let anchorPoint = resolvedAnchorPoint()
        currentStackDirection = stackDirection(for: anchorPoint)
        ToastWindow.shared.currentStackDirection = currentStackDirection
    }

    /// 重新定位所有 toast (基于层叠深度)
    ///
    /// 数组末尾 = 最新 = depth 0 (最前, 紧贴锚点)
    /// 数组头部 = 最旧 = depth N-1 (最后, 最远)
    private func repositionAllToasts(animated: Bool) {
        guard !activeToasts.isEmpty else {
            transientAnchorPoint = nil
            return
        }

        let anchorPoint = resolvedAnchorPoint()
        let targetOrigins = ToastLayout.stackOrigins(
            toastSizes: activeToasts.map { $0.panel.frame.size },
            anchorPoint: anchorPoint,
            direction: currentStackDirection,
            spacing: ToastLayoutConstants.spacing
        )
        let targetAlphas = ToastLayout.stackOpacities(
            count: activeToasts.count,
            maxVisibleCount: ToastStorage.shared.maxCount
        )

        guard animated else {
            for index in activeToasts.indices {
                let entry = activeToasts[index]
                let targetOrigin = targetOrigins[index]
                let targetAlpha = targetAlphas[index]
                let targetFrame = NSRect(origin: targetOrigin, size: entry.panel.frame.size)

                entry.panel.setFrame(targetFrame, display: false)
                if !entry.isDismissing {
                    entry.panel.alphaValue = targetAlpha
                }
            }
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            for index in activeToasts.indices {
                let entry = activeToasts[index]
                let targetOrigin = targetOrigins[index]
                let targetAlpha = targetAlphas[index]
                let targetFrame = NSRect(origin: targetOrigin, size: entry.panel.frame.size)

                entry.panel.animator().setFrame(targetFrame, display: false)
                if !entry.isDismissing {
                    entry.panel.animator().alphaValue = targetAlpha
                }
            }
        })
    }

    // MARK: - MaxCount Change

    /// maxCount 变更时调用 (由 ToastPanel 触发)
    func applyMaxCountChange() {
        let maxCount = ToastStorage.shared.maxCount

        // 超出部分立即淘汰
        while ToastVisibilityRules.activeCount(in: visibilityEntries()) > maxCount {
            dismissOldest(animated: true)
        }

        // 重新布局
        repositionAllToasts(animated: true)
    }

    /// 当前有 toast 可见时, 立即恢复到默认锚点并归位
    func resetToDefaultAnchor() {
        ToastStorage.shared.resetPosition()
        transientAnchorPoint = defaultAnchorPoint()
        recalculateDirection()
        repositionAllToasts(animated: true)
    }

    /// 拖拽结束后保存锚点位置并触发整组归位
    func saveAnchor(for panel: NSPanel) {
        guard let anchorPoint = anchorPoint(for: panel) else { return }
        transientAnchorPoint = nil
        ToastStorage.shared.savedPosition = anchorPoint
        NotificationCenter.default.post(name: .toastAnchorDidChange, object: nil)
    }

    func applyAccentIndicatorVisibilityChange() {
        let showsAccentIndicator = ToastStorage.shared.showsAccentIndicator
        for entry in activeToasts {
            entry.contentView.setShowsAccentIndicator(showsAccentIndicator)
        }
    }

    func snappedOrigin(for panel: NSPanel, proposedOrigin: NSPoint) -> NSPoint {
        guard let arrayIndex = activeToasts.firstIndex(where: { $0.panel == panel }) else {
            return proposedOrigin
        }

        let offsetFromAnchor = stackOffset(forArrayIndex: arrayIndex)
        let proposedAnchorPoint = ToastLayout.anchorPoint(
            for: proposedOrigin,
            toastSize: panel.frame.size,
            direction: currentStackDirection,
            offsetFromAnchor: offsetFromAnchor
        )
        let screen = screenContaining(point: proposedAnchorPoint) ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = screen else { return proposedOrigin }

        let snappedAnchorPoint = ToastLayout.snappedAnchorPoint(proposedAnchorPoint, in: targetScreen.visibleFrame)
        return ToastLayout.origin(
            toastSize: panel.frame.size,
            anchorPoint: snappedAnchorPoint,
            direction: currentStackDirection,
            offsetFromAnchor: offsetFromAnchor
        )
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

    private func screenContaining(point: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return nil
    }

    private func resolvedAnchorPoint() -> NSPoint {
        if let savedPosition = ToastStorage.shared.savedPosition {
            return savedPosition
        }
        if let transientAnchorPoint = transientAnchorPoint {
            return transientAnchorPoint
        }

        let defaultPoint = defaultAnchorPoint()
        transientAnchorPoint = defaultPoint
        return defaultPoint
    }

    private func removeToast(id: UInt) {
        activeToasts.removeAll(where: { $0.id == id })
        if activeToasts.isEmpty {
            transientAnchorPoint = nil
        }
    }

    private func visibilityEntries() -> [ToastVisibilityEntry] {
        return activeToasts.map {
            ToastVisibilityEntry(id: $0.id, message: $0.message, isDismissing: $0.isDismissing)
        }
    }

    private func anchorPoint(for panel: NSPanel) -> NSPoint? {
        guard let arrayIndex = activeToasts.firstIndex(where: { $0.panel == panel }) else {
            return nil
        }

        return ToastLayout.anchorPoint(
            for: panel.frame.origin,
            toastSize: panel.frame.size,
            direction: currentStackDirection,
            offsetFromAnchor: stackOffset(forArrayIndex: arrayIndex)
        )
    }

    private func stackOffset(forArrayIndex arrayIndex: Int) -> CGFloat {
        let toastSizes = activeToasts.map { $0.panel.frame.size }
        let offsets = ToastLayout.stackOffsets(toastSizes: toastSizes, spacing: ToastLayoutConstants.spacing)
        guard arrayIndex < offsets.count else { return 0 }
        return offsets[arrayIndex]
    }
}
