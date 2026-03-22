# Toast Component Evolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve the Toast component from single-file single-toast to multi-toast, draggable, configurable, product-grade module with independent persistence.

**Architecture:** Split the existing `Toast.swift` (666 lines) into 6 focused files under `Mos/Components/Toast/`. Use a single transparent container NSPanel to host all toast content views as subviews, enabling drag-to-reposition with zero multi-window sync overhead. ToastManager coordinates lifecycle, ToastStorage handles independent UserDefaults persistence, and ToastPanel provides a product-grade debug UI.

**Tech Stack:** Swift 4+, AppKit (NSPanel, NSVisualEffectView, NSAnimationContext), UserDefaults, macOS 10.13+ compatibility

**Spec:** `docs/superpowers/specs/2026-03-22-toast-component-evolution-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Mos/Components/Toast/Toast.swift` | **Rewrite** | Public API only (~80 lines): `show()`, `dismissAll()`, `showTestPanel()`, `debugMenuItem()`, `Style` enum |
| `Mos/Components/Toast/ToastStorage.swift` | **Create** | Independent UserDefaults persistence (~60 lines): position, maxCount |
| `Mos/Components/Toast/ToastContentView.swift` | **Create** | Visual rendering (~200 lines): extracted from existing ToastContentView class |
| `Mos/Components/Toast/ToastWindow.swift` | **Create** | Container NSPanel + drag + hitTest (~200 lines) |
| `Mos/Components/Toast/ToastManager.swift` | **Create** | Multi-toast lifecycle, stacking, dedup, dismiss (~250 lines) |
| `Mos/Components/Toast/ToastPanel.swift` | **Create** | Product-grade debug panel (~400 lines) |
| `Mos/Components/Toast/README.md` | **Update** | Updated docs reflecting new API |
| `Mos/Managers/StatusItemManager.swift` | **Modify** (lines 84-85, 109-111) | Replace hardcoded menu item with `Toast.debugMenuItem()` |

---

### Task 1: ToastStorage — Independent Persistence

**Files:**
- Create: `Mos/Components/Toast/ToastStorage.swift`

This is the foundation with zero dependencies. Other tasks depend on it.

- [ ] **Step 1: Create ToastStorage.swift**

```swift
//
//  ToastStorage.swift
//  Mos
//  Toast 组件独立持久化 - 使用独立 UserDefaults suite
//

import Cocoa

/// Toast 组件的独立持久化存储
///
/// 使用独立的 UserDefaults suite (基于 Bundle ID)，不与宿主应用的 UserDefaults 混合。
/// 这确保 Toast 模块可作为独立组件在任何 macOS 应用中复用。
class ToastStorage {

    static let shared = ToastStorage()

    private let defaults: UserDefaults

    private enum Keys {
        static let positionX = "positionX"
        static let positionY = "positionY"
        static let maxCount = "maxCount"
    }

    init() {
        let suiteName = "\(Bundle.main.bundleIdentifier ?? "app").toast"
        defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
    }

    // MARK: - Position

    /// 保存的锚点位置 (绝对屏幕坐标)。nil 表示使用默认位置。
    var savedPosition: NSPoint? {
        get {
            guard defaults.object(forKey: Keys.positionX) != nil,
                  defaults.object(forKey: Keys.positionY) != nil else {
                return nil
            }
            let point = NSPoint(
                x: CGFloat(defaults.double(forKey: Keys.positionX)),
                y: CGFloat(defaults.double(forKey: Keys.positionY))
            )
            // 坐标有效性校验：检查是否在任何可见屏幕范围内
            for screen in NSScreen.screens {
                if screen.frame.contains(point) {
                    return point
                }
            }
            // 不在任何屏幕上 (如外接显示器已断开)，回退到默认
            return nil
        }
        set {
            if let point = newValue {
                defaults.set(Double(point.x), forKey: Keys.positionX)
                defaults.set(Double(point.y), forKey: Keys.positionY)
            } else {
                defaults.removeObject(forKey: Keys.positionX)
                defaults.removeObject(forKey: Keys.positionY)
            }
        }
    }

    /// 是否有保存的自定义位置
    var hasCustomPosition: Bool {
        return savedPosition != nil
    }

    // MARK: - Max Count

    /// 最大同时显示数 (1-8，默认 4)
    var maxCount: Int {
        get {
            let val = defaults.integer(forKey: Keys.maxCount)
            return val > 0 ? min(max(val, 1), 8) : 4
        }
        set {
            defaults.set(min(max(newValue, 1), 8), forKey: Keys.maxCount)
        }
    }

    // MARK: - Reset

    /// 重置位置到默认
    func resetPosition() {
        savedPosition = nil
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project Mos.xcodeproj -scheme Mos -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Mos/Components/Toast/ToastStorage.swift
git commit -m "feat(toast): add ToastStorage with independent UserDefaults persistence"
```

---

### Task 2: ToastContentView — Extract Visual Rendering

**Files:**
- Create: `Mos/Components/Toast/ToastContentView.swift`

Extract the existing `ToastContentView` class from `Toast.swift` (lines 276-486) into its own file. Change access level from `private` to `internal`. Also extract the style helper methods (defaultIcon, accentColor) that belong to the rendering layer.

**Note:** During Tasks 2-4, both the old `private class ToastContentView` (in Toast.swift) and the new `internal class ToastContentView` (in this file) coexist. This is safe because Swift treats them as distinct types due to access level scoping. The old private class is removed when Toast.swift is rewritten in Task 5.

- [ ] **Step 1: Create ToastContentView.swift**

Extract from current `Toast.swift` lines 276-486. Change `private class` → `class` (internal). Add style helper static methods (currently on ToastWindow lines 236-268).

```swift
//
//  ToastContentView.swift
//  Mos
//  Toast 内容视图 - 毛玻璃背景 + 图标 + 消息文本 + 强调条
//

import Cocoa

/// Toast 内容视图 (模块内部使用)
///
/// 使用 NSVisualEffectView 实现毛玻璃背景, 包含可选图标和文本标签。
class ToastContentView: NSView {

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
        iconView.isHidden = true
        effectView.addSubview(iconView)
    }

    private func setupMessageLabel() {
        messageLabel.font = NSFont.systemFont(ofSize: 13)
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
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            accentIndicator.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 5),
            accentIndicator.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            accentIndicator.widthAnchor.constraint(equalToConstant: accentIndicatorWidth),
            accentIndicator.heightAnchor.constraint(equalTo: effectView.heightAnchor, multiplier: 0.5),

            iconView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            messageLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: verticalPadding),
            messageLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -verticalPadding),
            messageLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -horizontalPadding),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
    }

    // MARK: - Update Content

    func update(message: String, icon: NSImage?, accentColor: NSColor?) {
        messageLabel.stringValue = message

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

        if let color = accentColor {
            accentIndicator.layer?.backgroundColor = color.cgColor
            accentIndicator.isHidden = false
            hasAccent = true
        } else {
            accentIndicator.isHidden = true
            hasAccent = false
        }

        updateMessageLeadingConstraint()
    }

    // MARK: - Dynamic Layout

    private var messageLeadingConstraint: NSLayoutConstraint?

    private func updateMessageLeadingConstraint() {
        if let old = messageLeadingConstraint {
            old.isActive = false
        }

        let leadingOffset: CGFloat
        if hasIcon {
            leadingOffset = horizontalPadding + iconSize + iconMessageSpacing
        } else if hasAccent {
            leadingOffset = 5 + accentIndicatorWidth + horizontalPadding
        } else {
            leadingOffset = horizontalPadding
        }

        let constraint = messageLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: leadingOffset)
        constraint.isActive = true
        messageLeadingConstraint = constraint
    }

    // MARK: - Image Tinting

    private func tintImage(_ image: NSImage, color: NSColor) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    // MARK: - Style Helpers (moved from ToastWindow)

    /// 根据样式返回默认图标
    static func defaultIcon(for style: Toast.Style) -> NSImage? {
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
        switch style {
        case .info:    return NSImage(named: NSImage.infoName)
        case .success: return NSImage(named: NSImage.statusAvailableName)
        case .warning: return NSImage(named: NSImage.cautionName)
        case .error:   return NSImage(named: NSImage.stopProgressFreestandingTemplateName)
        }
    }

    /// 根据样式返回强调色
    static func accentColor(for style: Toast.Style) -> NSColor? {
        switch style {
        case .info:    return nil
        case .success: return NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0)
        case .warning: return NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.20, alpha: 1.0)
        case .error:   return NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.30, alpha: 1.0)
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project Mos.xcodeproj -scheme Mos -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Mos/Components/Toast/ToastContentView.swift
git commit -m "feat(toast): extract ToastContentView into separate file"
```

---

### Task 3: ToastWindow — Container Window with Drag & Hit Testing

**Files:**
- Create: `Mos/Components/Toast/ToastWindow.swift`

New container window design: single transparent NSPanel that hosts all toast content views as subviews. Handles drag-to-reposition and hit testing for event passthrough.

- [ ] **Step 1: Create ToastWindow.swift**

```swift
//
//  ToastWindow.swift
//  Mos
//  Toast 容器窗口 - 单 NSPanel 承载所有 toast 子视图, 支持拖拽定位
//

import Cocoa

/// Toast 容器窗口
///
/// 单个透明 NSPanel 作为所有 toast 的容器。子视图 (ToastContentView) 在其中排列。
/// 拖拽移动整个容器窗口 = 移动所有 toast 的锚点位置。
/// 透明区域通过 hitTest 返回 nil 实现事件穿透。
class ToastWindow {

    static let shared = ToastWindow()

    /// 容器 NSPanel
    private(set) var panel: NSPanel?

    /// 容器内的 contentView（重写 hitTest 用于事件穿透）
    private var containerView: ToastContainerView?

    // MARK: - Stack Direction (set by ToastManager)

    var currentStackDirection: StackDirection = .down

    // MARK: - Drag State

    private var isDragging = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    // MARK: - Panel Lifecycle

    /// 确保容器窗口存在并返回 containerView
    func ensurePanel(maxSlots: Int) -> ToastContainerView {
        if let existing = containerView, panel != nil {
            return existing
        }

        let slotHeight = ToastLayoutConstants.toastHeight + ToastLayoutConstants.spacing
        let containerHeight = CGFloat(maxSlots) * slotHeight
        let containerWidth = ToastLayoutConstants.containerWidth

        let container = ToastContainerView(
            frame: NSRect(origin: .zero, size: NSSize(width: containerWidth, height: containerHeight))
        )
        container.toastWindow = self

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: containerWidth, height: containerHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = false
        newPanel.ignoresMouseEvents = false  // hitTest 控制事件穿透
        newPanel.contentView = container

        panel = newPanel
        containerView = container
        return container
    }

    /// 更新容器窗口大小 (maxCount 变更时调用)
    func resizePanel(maxSlots: Int) {
        guard let p = panel else { return }
        let slotHeight = ToastLayoutConstants.toastHeight + ToastLayoutConstants.spacing
        let newHeight = CGFloat(maxSlots) * slotHeight
        var frame = p.frame
        let heightDiff = newHeight - frame.height
        frame.size.height = newHeight
        frame.origin.y -= heightDiff  // macOS 坐标系左下角，向下扩展
        p.setFrame(frame, display: true)
    }

    /// 将容器定位到指定的锚点位置
    func positionPanel(anchorPoint: NSPoint, stackDirection: StackDirection, maxSlots: Int) {
        guard let p = panel else { return }
        let frame = p.frame

        let x: CGFloat
        let y: CGFloat

        // 锚点是第一个 toast 的中心位置
        x = anchorPoint.x - frame.width / 2.0

        switch stackDirection {
        case .down:
            // 锚点在顶部，向下生长
            y = anchorPoint.y - frame.height
        case .up:
            // 锚点在底部，向上生长
            y = anchorPoint.y
        }

        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 显示容器窗口
    func showPanel() {
        panel?.orderFrontRegardless()
    }

    /// 隐藏容器窗口 (所有 toast 消失后)
    func hidePanel() {
        panel?.orderOut(nil)
    }

    /// 释放容器窗口
    func releasePanel() {
        panel?.orderOut(nil)
        panel = nil
        containerView = nil
    }

    // MARK: - Drag Handling (called by ToastContainerView)

    func handleMouseDown(event: NSEvent) {
        guard let p = panel else { return }
        isDragging = true
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = p.frame.origin
    }

    func handleMouseDragged(event: NSEvent) {
        guard isDragging, let p = panel else { return }
        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - dragStartMouseLocation.x
        let dy = currentMouse.y - dragStartMouseLocation.y
        let newOrigin = NSPoint(
            x: dragStartWindowOrigin.x + dx,
            y: dragStartWindowOrigin.y + dy
        )
        p.setFrameOrigin(newOrigin)
    }

    func handleMouseUp(event: NSEvent) {
        guard isDragging, let p = panel else {
            isDragging = false
            return
        }
        isDragging = false

        // 计算新的锚点位置
        // 锚点 X: 容器水平中心
        // 锚点 Y: 根据当前堆叠方向确定 — 向下堆叠时锚点在顶部，向上堆叠时锚点在底部
        let frame = p.frame
        let anchorX = frame.midX
        let anchorY: CGFloat
        switch currentStackDirection {
        case .down:
            anchorY = frame.origin.y + frame.height  // 容器顶部
        case .up:
            anchorY = frame.origin.y  // 容器底部
        }
        let newAnchor = NSPoint(x: anchorX, y: anchorY)

        // 写入持久化
        ToastStorage.shared.savedPosition = newAnchor

        // 通知 manager 重新计算堆叠方向 (只在拖拽松手时重算)
        NotificationCenter.default.post(name: .toastAnchorDidChange, object: nil)
    }

    // MARK: - Types

    enum StackDirection {
        case up
        case down
    }
}

// MARK: - Layout Constants

enum ToastLayoutConstants {
    static let toastHeight: CGFloat = 40
    static let spacing: CGFloat = 8
    static let containerWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 10
}

// MARK: - Notifications

extension Notification.Name {
    static let toastAnchorDidChange = Notification.Name("toastAnchorDidChange")
}

// MARK: - ToastContainerView (Hit Test + Drag Forwarding)

/// 容器窗口的 contentView，负责 hitTest 事件穿透和拖拽转发
class ToastContainerView: NSView {

    weak var toastWindow: ToastWindow?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 遍历所有 toast 子视图，命中则响应拖拽
        for subview in subviews {
            if subview is ToastContentView {
                let localPoint = convert(point, to: subview)
                if subview.bounds.contains(localPoint) {
                    return self  // 返回 self 接管拖拽
                }
            }
        }
        return nil  // 透明区域穿透
    }

    override func mouseDown(with event: NSEvent) {
        toastWindow?.handleMouseDown(event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        toastWindow?.handleMouseDragged(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        toastWindow?.handleMouseUp(event: event)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project Mos.xcodeproj -scheme Mos -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Mos/Components/Toast/ToastWindow.swift
git commit -m "feat(toast): add ToastWindow container with drag and hit-test passthrough"
```

---

### Task 4: ToastManager — Multi-Toast Lifecycle

**Files:**
- Create: `Mos/Components/Toast/ToastManager.swift`

Core multi-toast orchestration: stacking, dedup, eviction, animation, direction calculation.

- [ ] **Step 1: Create ToastManager.swift**

```swift
//
//  ToastManager.swift
//  Mos
//  Toast 多实例生命周期管理 - 堆叠、去重、淘汰、动画
//

import Cocoa

/// 管理多个 Toast 的生命周期
///
/// 维护活跃 toast 列表，计算堆叠位置和方向，处理溢出淘汰。
/// 依赖 ToastWindow (容器窗口) 和 ToastStorage (持久化)。
class ToastManager {

    static let shared = ToastManager()

    // MARK: - Active Toasts

    /// 活跃的 toast 条目 (按创建顺序，最旧在前)
    private var activeToasts: [ToastEntry] = []

    /// Toast 条目
    struct ToastEntry {
        let id: UInt
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

        // 创建新 toast 内容视图
        let resolvedIcon = icon ?? ToastContentView.defaultIcon(for: style)
        let accentColor = ToastContentView.accentColor(for: style)
        let contentView = ToastContentView(message: message, icon: resolvedIcon, accentColor: accentColor)
        contentView.alphaValue = 0

        // 注册到容器
        let container = ToastWindow.shared.ensurePanel(maxSlots: maxCount)
        container.addSubview(contentView)

        // 创建条目
        let id = nextId
        nextId &+= 1
        var entry = ToastEntry(id: id, contentView: contentView, dismissTimer: nil, message: message)

        // 设置自动消失
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss(id: id)
        }
        entry.dismissTimer = timer
        activeToasts.append(entry)

        // 重新布局所有 toast
        recalculateLayout(animated: activeToasts.count > 1)

        // 显示容器
        ToastWindow.shared.showPanel()

        // 淡入新 toast
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            contentView.animator().alphaValue = 1.0
        })
    }

    // MARK: - Dismiss

    /// 关闭指定 ID 的 toast
    func dismiss(id: UInt) {
        guard let index = activeToasts.firstIndex(where: { $0.id == id }) else { return }
        let entry = activeToasts.remove(at: index)
        entry.dismissTimer?.invalidate()

        // 淡出并移除
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            entry.contentView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            entry.contentView.removeFromSuperview()
            self?.recalculateLayout(animated: true)

            // 全部消失后隐藏容器
            if self?.activeToasts.isEmpty == true {
                ToastWindow.shared.hidePanel()
            }
        })
    }

    /// 关闭所有 toast
    func dismissAll() {
        // 先移除再动画，确保无竞态
        let toasts = activeToasts
        activeToasts.removeAll()

        for entry in toasts {
            entry.dismissTimer?.invalidate()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                entry.contentView.animator().alphaValue = 0
            }, completionHandler: {
                entry.contentView.removeFromSuperview()
            })
        }

        // 延迟释放容器 (等待动画完成)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if self?.activeToasts.isEmpty == true {
                ToastWindow.shared.releasePanel()
            }
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
                entry.contentView.animator().alphaValue = 0
            }, completionHandler: {
                entry.contentView.removeFromSuperview()
            })
        } else {
            entry.contentView.removeFromSuperview()
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

    /// 重新计算所有 toast 的布局位置 (不改变方向)
    private func recalculateLayout(animated: Bool) {
        let anchorPoint = ToastStorage.shared.savedPosition ?? defaultAnchorPoint()
        let direction = currentStackDirection

        let maxCount = ToastStorage.shared.maxCount

        // 定位容器窗口
        ToastWindow.shared.positionPanel(
            anchorPoint: anchorPoint,
            stackDirection: direction,
            maxSlots: maxCount
        )

        // 布局子视图
        let slotHeight = ToastLayoutConstants.toastHeight + ToastLayoutConstants.spacing
        let containerWidth = ToastLayoutConstants.containerWidth

        for (i, entry) in activeToasts.enumerated() {
            let toastSize = entry.contentView.fittingSize
            let x = (containerWidth - toastSize.width) / 2.0

            let y: CGFloat
            switch direction {
            case .down:
                // 从容器顶部向下排列
                let containerHeight = CGFloat(maxCount) * slotHeight
                y = containerHeight - CGFloat(i + 1) * slotHeight + ToastLayoutConstants.spacing / 2.0
            case .up:
                // 从容器底部向上排列
                y = CGFloat(i) * slotHeight + ToastLayoutConstants.spacing / 2.0
            }

            let targetFrame = NSRect(
                x: x, y: y,
                width: toastSize.width,
                height: ToastLayoutConstants.toastHeight
            )

            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeInOut)
                    entry.contentView.animator().frame = targetFrame
                })
            } else {
                entry.contentView.frame = targetFrame
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

        // 调整容器窗口大小
        ToastWindow.shared.resizePanel(maxSlots: maxCount)

        // 重新布局
        recalculateLayout(animated: true)
    }

    // MARK: - Anchor Change

    @objc private func anchorDidChange() {
        // 拖拽松手时重新计算方向和布局
        recalculateDirection()
        recalculateLayout(animated: true)
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
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project Mos.xcodeproj -scheme Mos -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Mos/Components/Toast/ToastManager.swift
git commit -m "feat(toast): add ToastManager with multi-toast stacking, dedup, and eviction"
```

---

### Task 5: Toast.swift — Rewrite Public API

**Files:**
- Rewrite: `Mos/Components/Toast/Toast.swift`

Slim down to public API only. Remove all private classes (now in separate files). Add `dismissAll()` and `debugMenuItem()`.

**Note:** This task references `ToastPanel` which is created in Task 6. To resolve the forward dependency, this task first creates a minimal ToastPanel stub, which Task 6 will replace with the full implementation.

- [ ] **Step 1: Rewrite Toast.swift**

```swift
//
//  Toast.swift
//  Mos
//  轻量级 Toast 通知组件 - 多 toast 同时显示, 可拖拽, 可配置
//  Created by Mos on 2026/3/22.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - Toast (Public API)

/// 轻量级 Toast 通知
///
/// 在鼠标所在屏幕显示浮动提示, 支持多条同时展示、拖拽定位、自动堆叠。
/// 不抢占焦点, 不阻塞交互。
///
/// 基本用法:
/// ```swift
/// Toast.show("Hi-Res 滚轮已开启", style: .success)
/// Toast.show("当前设备不支持此功能", style: .warning)
/// Toast.dismissAll()
/// ```
///
/// 集成 Debug 面板:
/// ```swift
/// menu.addItem(Toast.debugMenuItem())
/// ```
struct Toast {

    /// 提示样式
    enum Style: CaseIterable {
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
            ToastManager.shared.present(message: message, style: style, duration: duration, icon: icon)
        }
    }

    /// 关闭所有通知
    static func dismissAll() {
        DispatchQueue.main.async {
            ToastManager.shared.dismissAll()
        }
    }

    /// 显示 Toast Debug 面板
    static func showTestPanel() {
        ToastPanel.shared.show()
    }

    /// 返回可直接加入菜单的 Debug 面板入口 MenuItem
    ///
    /// 内部自包含 target/action/icon/title, 调用方无需额外配置。
    /// ```swift
    /// menu.addItem(Toast.debugMenuItem())
    /// ```
    static func debugMenuItem() -> NSMenuItem {
        return ToastPanel.shared.createMenuItem()
    }
}
```

- [ ] **Step 2: Create ToastPanel minimal stub**

Create `Mos/Components/Toast/ToastPanel.swift` with the minimum interface needed for Toast.swift to compile. Task 6 will replace this with the full implementation.

```swift
//
//  ToastPanel.swift
//  Mos
//  产品级 Toast Debug 面板 (stub — Task 6 will replace with full implementation)
//

import Cocoa

/// Toast Debug 面板 (minimal stub)
class ToastPanel: NSObject {
    static let shared = ToastPanel()

    func show() {
        // TODO: Task 6 will implement full panel
    }

    func createMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Toast Debug", comment: "Toast debug panel menu item"),
            action: #selector(menuItemClicked),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    @objc private func menuItemClicked() {
        show()
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -project Mos.xcodeproj -scheme Mos -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Mos/Components/Toast/Toast.swift Mos/Components/Toast/ToastPanel.swift
git commit -m "feat(toast): rewrite public API with dismissAll and debugMenuItem

Includes ToastPanel minimal stub to be replaced in next task."
```

---

### Task 6: ToastPanel — Product-Grade Debug Panel

**Files:**
- Replace: `Mos/Components/Toast/ToastPanel.swift` (replace Task 5 stub with full implementation)

Full rebuild of the debug panel with three-section layout, NSVisualEffectView glass, and new test scenarios. **All user-visible strings must use `NSLocalizedString()`. Use `Toast.Style.allCases` instead of manual arrays.**

- [ ] **Step 1: Replace ToastPanel.swift with full implementation**

```swift
//
//  ToastPanel.swift
//  Mos
//  产品级 Toast Debug 面板 - 配置、自定义发送、场景测试
//

import Cocoa

/// Toast Debug 面板
///
/// 面向用户的产品功能, 提供 Toast 配置、自定义发送和一键场景测试。
/// 作为 NSObject 子类可直接作为 NSMenuItem 的 target。
class ToastPanel: NSObject {

    static let shared = ToastPanel()

    private var window: NSPanel?

    // MARK: - UI Controls (Configuration)
    private var maxCountSlider: NSSlider!
    private var maxCountLabel: NSTextField!
    private var positionStatusLabel: NSTextField!

    // MARK: - UI Controls (Send Toast)
    private var messageField: NSTextField!
    private var styleButtons: [NSButton] = []
    private var selectedStyle: Toast.Style = .info
    private var durationSlider: NSSlider!
    private var durationLabel: NSTextField!
    private var useCustomIconCheckbox: NSButton!

    // MARK: - Menu Item

    /// 创建可直接加入菜单的 MenuItem
    func createMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Toast Debug", comment: "Toast debug panel menu item"),
            action: #selector(menuItemClicked),
            keyEquivalent: ""
        )
        item.target = self
        // 图标: macOS 11+ 用 SF Symbol, 低版本用 imageLiteral fallback
        if #available(macOS 11.0, *) {
            if let img = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil) {
                img.isTemplate = true
                item.image = img
            }
        } else {
            item.image = #imageLiteral(resourceName: "SF.bubble.left.fill")
        }
        return item
    }

    @objc private func menuItemClicked() {
        show()
    }

    // MARK: - Show

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = buildWindow()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build Window

    private func buildWindow() -> NSPanel {
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 520

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = NSLocalizedString("Toast Debug", comment: "Toast debug panel window title")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true

        // 毛玻璃背景
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)))
        effectView.autoresizingMask = [.width, .height]
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
            panel.appearance = NSAppearance(named: .vibrantDark)
        } else {
            effectView.material = .dark
        }
        panel.contentView = effectView

        // 构建内容
        buildContent(in: effectView, width: panelWidth, height: panelHeight)

        return panel
    }

    private func buildContent(in container: NSView, width: CGFloat, height: CGFloat) {
        let margin: CGFloat = 20
        let contentWidth = width - margin * 2
        var y = height - 50  // 从顶部开始 (留出 titlebar 空间)

        // --- Header ---
        let titleLabel = makeLabel(text: NSLocalizedString("Toast Debug", comment: "Toast debug panel title"), fontSize: 18, weight: .semibold, color: .white)
        titleLabel.frame = NSRect(x: margin, y: y, width: contentWidth, height: 22)
        container.addSubview(titleLabel)
        y -= 18

        let subtitleLabel = makeLabel(text: NSLocalizedString("Component testing & configuration", comment: "Toast debug panel subtitle"), fontSize: 12, weight: .regular, color: .secondaryLabelColor)
        subtitleLabel.frame = NSRect(x: margin, y: y, width: contentWidth, height: 16)
        container.addSubview(subtitleLabel)
        y -= 28

        // === SECTION: Configuration ===
        y = addSectionHeader(to: container, title: NSLocalizedString("CONFIGURATION", comment: "Toast debug section header"), y: y, margin: margin, width: contentWidth)

        // Max Simultaneous
        let maxCountRow = makeLabel(text: NSLocalizedString("Max Simultaneous", comment: "Toast debug max count label"), fontSize: 12, weight: .regular, color: .labelColor)
        maxCountRow.frame = NSRect(x: margin, y: y, width: 140, height: 18)
        container.addSubview(maxCountRow)

        maxCountSlider = NSSlider(frame: NSRect(x: margin + 180, y: y, width: 150, height: 18))
        maxCountSlider.minValue = 1
        maxCountSlider.maxValue = 8
        maxCountSlider.integerValue = ToastStorage.shared.maxCount
        maxCountSlider.target = self
        maxCountSlider.action = #selector(maxCountChanged)
        container.addSubview(maxCountSlider)

        maxCountLabel = makeLabel(text: "\(ToastStorage.shared.maxCount)", fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        maxCountLabel.frame = NSRect(x: margin + 340, y: y, width: 30, height: 18)
        maxCountLabel.alignment = .right
        container.addSubview(maxCountLabel)
        y -= 28

        // Position
        let posLabel = makeLabel(text: NSLocalizedString("Position", comment: "Toast debug position label"), fontSize: 12, weight: .regular, color: .labelColor)
        posLabel.frame = NSRect(x: margin, y: y, width: 140, height: 18)
        container.addSubview(posLabel)

        positionStatusLabel = makeLabel(
            text: ToastStorage.shared.hasCustomPosition ? "Saved" : "Default",
            fontSize: 11, weight: .medium,
            color: ToastStorage.shared.hasCustomPosition ? NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0) : .secondaryLabelColor
        )
        positionStatusLabel.frame = NSRect(x: margin + 180, y: y, width: 60, height: 18)
        container.addSubview(positionStatusLabel)

        let resetBtn = NSButton(frame: NSRect(x: margin + 260, y: y - 2, width: 60, height: 22))
        resetBtn.title = NSLocalizedString("Reset", comment: "Toast debug reset position button")
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 11)
        resetBtn.target = self
        resetBtn.action = #selector(resetPosition)
        container.addSubview(resetBtn)
        y -= 32

        // === SECTION: Send Toast ===
        y = addSectionHeader(to: container, title: NSLocalizedString("SEND TOAST", comment: "Toast debug section header"), y: y, margin: margin, width: contentWidth)

        // Message
        messageField = NSTextField(frame: NSRect(x: margin, y: y, width: contentWidth, height: 22))
        messageField.stringValue = "Hello, this is a toast message"
        messageField.placeholderString = "Enter toast message..."
        container.addSubview(messageField)
        y -= 32

        // Style buttons
        let styles: [(String, Toast.Style)] = [
            ("ℹ️ Info", .info), ("✅ Success", .success), ("⚠️ Warning", .warning), ("❌ Error", .error)
        ]
        let btnWidth: CGFloat = (contentWidth - CGFloat(styles.count - 1) * 6) / CGFloat(styles.count)
        styleButtons = []
        for (i, (title, _)) in styles.enumerated() {
            let btn = NSButton(frame: NSRect(x: margin + CGFloat(i) * (btnWidth + 6), y: y, width: btnWidth, height: 24))
            btn.title = title
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.tag = i
            btn.target = self
            btn.action = #selector(styleSelected(_:))
            if i == 0 { btn.state = .on }
            container.addSubview(btn)
            styleButtons.append(btn)
        }
        y -= 32

        // Duration
        let durLabel = makeLabel(text: NSLocalizedString("Duration", comment: "Toast debug duration label"), fontSize: 12, weight: .regular, color: .labelColor)
        durLabel.frame = NSRect(x: margin, y: y, width: 60, height: 18)
        container.addSubview(durLabel)

        durationSlider = NSSlider(frame: NSRect(x: margin + 80, y: y, width: 240, height: 18))
        durationSlider.minValue = 0.5
        durationSlider.maxValue = 10.0
        durationSlider.doubleValue = 2.5
        durationSlider.target = self
        durationSlider.action = #selector(durationChanged)
        container.addSubview(durationSlider)

        durationLabel = makeLabel(text: "2.5s", fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        durationLabel.frame = NSRect(x: margin + 330, y: y, width: 50, height: 18)
        durationLabel.alignment = .right
        container.addSubview(durationLabel)
        y -= 28

        // Custom Icon
        useCustomIconCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Custom Icon (app icon)", comment: "Toast debug custom icon checkbox"), target: nil, action: nil)
        useCustomIconCheckbox.frame = NSRect(x: margin, y: y, width: contentWidth, height: 18)
        useCustomIconCheckbox.font = NSFont.systemFont(ofSize: 12)
        container.addSubview(useCustomIconCheckbox)
        y -= 32

        // Show Toast button
        let fireButton = NSButton(frame: NSRect(x: margin, y: y, width: contentWidth, height: 30))
        fireButton.title = NSLocalizedString("Show Toast", comment: "Toast debug show toast button")
        fireButton.bezelStyle = .rounded
        fireButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        fireButton.target = self
        fireButton.action = #selector(fireToast)
        container.addSubview(fireButton)
        y -= 36

        // === SECTION: Quick Tests ===
        y = addSectionHeader(to: container, title: NSLocalizedString("QUICK TESTS", comment: "Toast debug section header"), y: y, margin: margin, width: contentWidth)

        let tests: [(String, String, Selector)] = [
            ("🎨 All Styles", "Show each style", #selector(testAllStyles)),
            ("📚 Stack Test", "Fill to max count", #selector(testStackFill)),
            ("🔁 Overflow", "Exceed max, test eviction", #selector(testOverflow)),
            ("🔇 Dedup", "Rapid same message", #selector(testDedup)),
            ("📏 Long Text", "Truncation test", #selector(testLongText)),
            ("🧹 Dismiss All", "Clear all toasts", #selector(testDismissAll)),
        ]
        let gridCols = 2
        let cellWidth = (contentWidth - 8) / CGFloat(gridCols)
        let cellHeight: CGFloat = 44
        for (i, (title, subtitle, action)) in tests.enumerated() {
            let col = i % gridCols
            let row = i / gridCols
            let cellX = margin + CGFloat(col) * (cellWidth + 8)
            let cellY = y - CGFloat(row) * (cellHeight + 6)

            let btn = NSButton(frame: NSRect(x: cellX, y: cellY, width: cellWidth, height: cellHeight))
            btn.title = "\(title)\n\(subtitle)"
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.target = self
            btn.action = action
            container.addSubview(btn)
        }
    }

    // MARK: - Layout Helpers

    private func addSectionHeader(to parent: NSView, title: String, y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        let label = makeLabel(text: title, fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
        label.frame = NSRect(x: margin, y: y, width: width, height: 14)
        parent.addSubview(label)
        return y - 22
    }

    private func makeLabel(text: String, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        return label
    }

    // MARK: - Actions (Configuration)

    @objc private func maxCountChanged() {
        let value = maxCountSlider.integerValue
        maxCountLabel.stringValue = "\(value)"
        ToastStorage.shared.maxCount = value
        ToastManager.shared.applyMaxCountChange()
    }

    @objc private func resetPosition() {
        ToastStorage.shared.resetPosition()
        positionStatusLabel.stringValue = "Default"
        positionStatusLabel.textColor = .secondaryLabelColor
    }

    // MARK: - Actions (Send Toast)

    @objc private func styleSelected(_ sender: NSButton) {
        let allStyles = Array(Toast.Style.allCases)
        guard sender.tag < allStyles.count else { return }
        selectedStyle = allStyles[sender.tag]
        // 更新按钮状态
        for (i, btn) in styleButtons.enumerated() {
            btn.state = (i == sender.tag) ? .on : .off
        }
    }

    @objc private func durationChanged() {
        durationLabel.stringValue = String(format: "%.1fs", durationSlider.doubleValue)
    }

    @objc private func fireToast() {
        let message = messageField.stringValue.isEmpty ? "Test Toast" : messageField.stringValue
        let duration = durationSlider.doubleValue
        let icon: NSImage? = useCustomIconCheckbox.state == .on ? NSApp.applicationIconImage : nil
        Toast.show(message, style: selectedStyle, duration: duration, icon: icon)
    }

    // MARK: - Actions (Quick Tests)

    @objc private func testAllStyles() {
        let styles: [(String, Toast.Style)] = [
            ("Info style", .info), ("Success style", .success),
            ("Warning style", .warning), ("Error style", .error)
        ]
        for (i, (name, style)) in styles.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                Toast.show("Style: \(name)", style: style, duration: 3.0)
            }
        }
    }

    @objc private func testStackFill() {
        let max = ToastStorage.shared.maxCount
        for i in 0..<max {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                Toast.show("Toast \(i + 1) of \(max)", style: .info, duration: 5.0)
            }
        }
    }

    @objc private func testOverflow() {
        let max = ToastStorage.shared.maxCount
        let total = max + 2
        for i in 0..<total {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                Toast.show("Overflow \(i + 1) of \(total)", style: .warning, duration: 8.0)
            }
        }
    }

    @objc private func testDedup() {
        for _ in 0..<5 {
            Toast.show("Dedup test - same message", style: .info, duration: 2.0)
        }
    }

    @objc private func testLongText() {
        Toast.show("This is a very long toast message that should be truncated after two lines because nobody wants to read a novel in a toast notification, right? Let's see how this handles.", style: .warning, duration: 4.0)
    }

    @objc private func testDismissAll() {
        Toast.dismissAll()
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project Mos.xcodeproj -scheme Mos -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Mos/Components/Toast/ToastPanel.swift
git commit -m "feat(toast): add product-grade debug panel with three-section layout"
```

---

### Task 7: StatusItemManager Integration & Cleanup

**Files:**
- Modify: `Mos/Managers/StatusItemManager.swift` (lines 84-85, 109-111)

Replace hardcoded Toast menu item with `Toast.debugMenuItem()`. Remove the `toastTestClick()` method.

- [ ] **Step 1: Update StatusItemManager.swift**

Replace lines 84-85:
```swift
// Before:
// Toast Test
Utils.addMenuItem(to: menu, title: " Toast Test", icon: #imageLiteral(resourceName: "SF.bubble.left.fill"), action: #selector(toastTestClick))

// After:
// Toast Debug
menu.addItem(Toast.debugMenuItem())
```

Remove lines 109-111:
```swift
// Remove:
@objc func toastTestClick() {
    Toast.showTestPanel()
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -project Mos.xcodeproj -scheme Mos -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Mos/Managers/StatusItemManager.swift
git commit -m "refactor(toast): decouple StatusItemManager via Toast.debugMenuItem()"
```

---

### Task 8: Update README & Final Verification

**Files:**
- Update: `Mos/Components/Toast/README.md`

- [ ] **Step 1: Update README.md**

Update the README to reflect the new multi-toast architecture, public API, drag-to-reposition, and debug panel. Include usage examples for both basic usage and integration.

- [ ] **Step 2: Full build verification**

Run: `xcodebuild build -project Mos.xcodeproj -scheme Mos -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual test checklist**

Verify by running the app:
- [ ] Status bar menu shows "Toast Debug" with correct icon
- [ ] Clicking opens the debug panel with glass effect
- [ ] "Show Toast" displays a toast notification
- [ ] Multiple toasts stack correctly
- [ ] Dragging a toast moves all toasts together
- [ ] Position persists after drag
- [ ] "Stack Test" fills to max count
- [ ] "Overflow" shows eviction of oldest
- [ ] "Dedup" shows only one toast
- [ ] "Dismiss All" clears everything
- [ ] Max Simultaneous slider works in real-time
- [ ] Reset position restores default

- [ ] **Step 4: Commit**

```bash
git add Mos/Components/Toast/README.md
git commit -m "docs(toast): update README for multi-toast architecture"
```

---

## Task Dependencies

```
Task 1 (ToastStorage)     ─┐
Task 2 (ToastContentView) ─┼─→ Task 3 (ToastWindow) ─→ Task 4 (ToastManager) ─→ Task 5 (Toast.swift) ─→ Task 6 (ToastPanel) ─→ Task 7 (Integration) ─→ Task 8 (README + Verify)
                           ─┘
```

Tasks 1 and 2 can run in parallel. All others are sequential.
