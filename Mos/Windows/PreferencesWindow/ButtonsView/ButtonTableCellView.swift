//
//  ButtonTableCellView.swift
//  Mos
//
//  Created by 陈标 on 2025/9/27.
//  Copyright © 2025 Caldis. All rights reserved.
//


import Cocoa

class ButtonTableCellView: NSTableCellView, NSMenuDelegate {
    private static let appearanceChangedNotification = NSNotification.Name("AppleInterfaceThemeChangedNotification")

    // MARK: - IBOutlets
    @IBOutlet weak var keyDisplayContainerView: NSView!
    @IBOutlet weak var actionPopUpButton: NSPopUpButton!

    // MARK: - UI Components
    private var keyPreview: KeyPreview!
    private var dashedLineLayer: CAShapeLayer?
    private let actionDisplayResolver = ActionDisplayResolver()
    private let actionDisplayRenderer = ActionDisplayRenderer()

    // MARK: - Conflict Indicator
    private var conflictIconView: NSImageView?
    private var conflictTrackingArea: NSTrackingArea?
    private var conflictPopover: NSPopover?
    private var currentTriggerCode: UInt16 = 0
    private var conflictObserverTokens: [NSObjectProtocol] = []
    private static let conflictIconSize: CGFloat = 14  // 图标绘制尺寸
    private static let conflictHitSize: CGFloat = 28   // hover 热区尺寸 (外扩以便好点中)
    private static let conflictIconGap: CGFloat = 6    // 图标两侧与虚线的间距

    // MARK: - Callbacks
    private var onShortcutSelected: ((SystemShortcut.Shortcut?) -> Void)?
    private var onDeleteRequested: (() -> Void)?
    private var onCustomShortcutRecorded: ((String) -> Void)?
    /// 当用户从 PopUpButton 菜单选择 "打开…" 时触发,
    /// 由 PreferencesButtonsViewController 弹出 OpenTargetConfigPopover.
    private var onOpenTargetSelectionRequested: (() -> Void)?

    // MARK: - Custom Recording
    private lazy var customRecorder: KeyRecorder = {
        let recorder = KeyRecorder()
        recorder.delegate = self
        return recorder
    }()

    // MARK: - State (单一权威源)
    //
    // 之前用 4 个并列字段 (currentShortcut / currentCustomName / currentOpenTarget /
    // isCustomRecordingActive) 描述"当前展示的动作", 加新动作类型时要在 5+ 处同步,
    // 漏一处就出 bug. 现在 currentBinding 是持久态的单一源, 录制态 isCustomRecordingActive
    // 是 UI 临时叠加; 通过计算属性 actionState 暴露给所有需要判定/展示的代码,
    // 加新动作类型只需在 CellActionState 加一个 case, 编译器强制 switch 覆盖.
    private var currentBinding: ButtonBinding?
    private var isCustomRecordingActive = false
    private var actionState: CellActionState {
        if isCustomRecordingActive { return .recordingPrompt }
        guard let binding = currentBinding else { return .unbound }
        return CellActionState(binding: binding)
    }

    private var originalRowBackgroundColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerAppearanceObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerAppearanceObserver()
    }

    // MARK: - 配置方法
    func configure(
        with binding: ButtonBinding,
        onShortcutSelected: @escaping (SystemShortcut.Shortcut?) -> Void,
        onCustomShortcutRecorded: @escaping (String) -> Void,
        onOpenTargetSelectionRequested: @escaping () -> Void,
        onDeleteRequested: @escaping () -> Void
    ) {
        // 保存回调
        self.onShortcutSelected = onShortcutSelected
        self.onDeleteRequested = onDeleteRequested
        self.onCustomShortcutRecorded = onCustomShortcutRecorded
        self.onOpenTargetSelectionRequested = onOpenTargetSelectionRequested
        // 清理可能残留的录制状态 (cell 复用时)
        customRecorder.stopRecording()
        isCustomRecordingActive = false
        self.currentBinding = binding

        // 保存原始背景色（首次或复用时）
        if originalRowBackgroundColor == nil, let rowView = self.superview as? NSTableRowView {
            originalRowBackgroundColor = rowView.backgroundColor
        }

        // 配置按键显示组件
        setupKeyDisplayView(with: binding.triggerEvent)

        // 判断是否为 Logi 按键 (code >= 1000)
        let isLogiTrigger = binding.triggerEvent.type == .mouse && LogiCenter.shared.isLogiCode(binding.triggerEvent.code)

        // 配置动作选择器
        setupActionPopUpButton(showLogiActions: isLogiTrigger)

        // 记录当前 trigger code 以供冲突检测
        self.currentTriggerCode = isLogiTrigger ? binding.triggerEvent.code : 0

        // 绘制虚线分隔符和冲突指示器(延迟到下一个 runloop,等 AutoLayout 完成布局)
        DispatchQueue.main.async {
            self.refreshConflictIndicator()
        }

        // 订阅 Logitech session / reporting 通知, 保证设备状态变化时自动刷新
        registerConflictObservers()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self, name: Self.appearanceChangedNotification, object: nil)
        unregisterConflictObservers()
    }

    private func registerAppearanceObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: Self.appearanceChangedNotification,
            object: nil
        )
    }

    @objc private func appearanceChanged() {
        refreshForAppearanceChange()
    }

    @available(macOS 10.14, *)
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshForAppearanceChange()
    }

    private func refreshForAppearanceChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshActionDisplayForAppearanceChange()
        }
    }

    private func refreshActionDisplayForAppearanceChange() {
        guard actionPopUpButton != nil else { return }
        refreshActionDisplay()
        actionPopUpButton.needsDisplay = true
    }

    // 高亮该行（重复两次）
    func highlight() {
        guard let rowView = self.superview as? NSTableRowView else { return }
        // 设置主题色高亮
        let highlightColor: NSColor
        if #available(macOS 10.14, *) {
            highlightColor = NSColor.controlAccentColor.withAlphaComponent(1)
        } else {
            highlightColor = NSColor.mainBlue
        }
        let originalColor = originalRowBackgroundColor ?? rowView.backgroundColor
        // 高亮
        rowView.backgroundColor = highlightColor
        // 恢复
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 1.5
            rowView.animator().backgroundColor = originalColor
        })
    }

    // 创建按键视图
    private func setupKeyDisplayView(with recordedEvent: RecordedEvent) {
        // 清理旧的子视图（复用 cell 时会有残留）
        keyDisplayContainerView.subviews.forEach { $0.removeFromSuperview() }

        // 创建新的 KeyDisplayView
        keyPreview = KeyPreview()
        keyDisplayContainerView.addSubview(keyPreview)

        // 靠左对齐，按内容尺寸显示
        NSLayoutConstraint.activate([
            keyPreview.leadingAnchor.constraint(equalTo: keyDisplayContainerView.leadingAnchor),
            keyPreview.centerYAnchor.constraint(equalTo: keyDisplayContainerView.centerYAnchor),
        ])

        // 设置事件内容
        keyPreview.update(from: recordedEvent.displayComponents, status: .normal)
    }

    /// 绘制虚线分隔符
    ///
    /// 在 keyPreview 和 actionPopUpButton 之间绘制垂直居中的虚线
    /// 虚线使用淡灰色,兼容 macOS 10.13+
    /// 若存在冲突指示图标, 在图标左右两侧留 gap, 避免压线.
    private func setupDashedLine() {
        // 清理旧的虚线层(Cell复用时)
        dashedLineLayer?.removeFromSuperlayer()

        // 获取父容器层级
        guard let keyBox = keyDisplayContainerView.superview,
              let contentView = keyBox.superview else {
            return
        }

        // 确保 contentView 有 layer（Core Animation 必需）
        contentView.wantsLayer = true

        // 计算虚线的起点和终点坐标
        // 需要将 keyPreview 的坐标从 keyDisplayContainerView 转换到 contentView 坐标系
        let keyPreviewFrameInContentView = keyDisplayContainerView.convert(keyPreview.frame, to: contentView)
        let buttonFrame = actionPopUpButton.frame

        // 左右边距
        let horizontalMargin: CGFloat = 8.0

        // 起点: keyPreview 右边缘 + 边距
        let startX = keyPreviewFrameInContentView.maxX + horizontalMargin
        // 终点: actionPopUpButton 左边缘 - 边距
        let endX = buttonFrame.minX - horizontalMargin
        // 垂直居中
        let centerY = contentView.bounds.height / 2

        // 创建虚线路径
        let path = CGMutablePath()

        if let iconFrame = conflictIconView?.frame {
            // 图标存在, 在图标实际绘制尺寸两侧留 gap (iconView.frame 是 hit area, 比图标本身大)
            let midX = iconFrame.midX
            let gap = Self.conflictIconGap
            let iconLeft = midX - Self.conflictIconSize / 2 - gap
            let iconRight = midX + Self.conflictIconSize / 2 + gap
            path.move(to: CGPoint(x: startX, y: centerY))
            path.addLine(to: CGPoint(x: iconLeft, y: centerY))
            path.move(to: CGPoint(x: iconRight, y: centerY))
            path.addLine(to: CGPoint(x: endX, y: centerY))
        } else {
            path.move(to: CGPoint(x: startX, y: centerY))
            path.addLine(to: CGPoint(x: endX, y: centerY))
        }

        // 创建 CAShapeLayer 绘制虚线
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path
        shapeLayer.strokeColor = NSColor.getMainLightBlack(for: self).cgColor
        shapeLayer.lineWidth = 1.0
        shapeLayer.lineDashPattern = [2, 2]  // 虚线样式: 4pt 实线, 4pt 间隔

        // 添加到 contentView 的 layer
        contentView.layer?.addSublayer(shapeLayer)

        // 保存引用,便于下次清理
        dashedLineLayer = shapeLayer
    }

    // MARK: - Conflict Indicator

    /// 按当前 trigger code 的 Logi 冲突状态, 显示/隐藏中段的 branch 图标, 并重绘虚线.
    private func refreshConflictIndicator() {
        // 清理旧的图标和 popover
        hideConflictPopover()
        if let view = conflictIconView {
            if let area = conflictTrackingArea {
                view.removeTrackingArea(area)
            }
            view.removeFromSuperview()
        }
        conflictIconView = nil
        conflictTrackingArea = nil

        // 非 Logi 按键 -> 不显示
        guard currentTriggerCode > 0, LogiCenter.shared.isLogiCode(currentTriggerCode) else {
            setupDashedLine()
            return
        }

        let status = LogiCenter.shared.conflictStatus(forMosCode: currentTriggerCode)
        guard status.isConflict else {
            setupDashedLine()
            return
        }

        drawConflictIcon()
        setupDashedLine()
    }

    private func drawConflictIcon() {
        guard let keyBox = keyDisplayContainerView.superview,
              let contentView = keyBox.superview else { return }
        guard let iconImage = conflictIconImage() else { return }

        let keyFrame = keyDisplayContainerView.convert(keyPreview.frame, to: contentView)
        let buttonFrame = actionPopUpButton.frame
        let horizontalMargin: CGFloat = 8.0
        let startX = keyFrame.maxX + horizontalMargin
        let endX = buttonFrame.minX - horizontalMargin
        let hitSize = Self.conflictHitSize
        let iconSize = Self.conflictIconSize
        let centerX = (startX + endX) / 2
        let centerY = contentView.bounds.height / 2

        // NSImageView 的 frame 作为 hover 热区, 图标通过 imageAlignment 居中显示为 iconSize 大小
        let imageView = NSImageView(frame: NSRect(
            x: centerX - hitSize / 2,
            y: centerY - hitSize / 2,
            width: hitSize,
            height: hitSize
        ))
        imageView.image = iconImage
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        if #available(macOS 11.0, *) {
            imageView.contentTintColor = NSColor.systemOrange
        }
        imageView.setAccessibilityLabel(NSLocalizedString("button_conflict_title", comment: ""))

        contentView.addSubview(imageView)
        conflictIconView = imageView

        let area = NSTrackingArea(
            rect: imageView.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        imageView.addTrackingArea(area)
        conflictTrackingArea = area
    }

    /// macOS 11+ 用 SF Symbol `arrow.triangle.branch` (橘色 tint, 14pt);
    /// 10.13~10.15 fallback 到系统 NSCaution (黄三角+感叹号, 内置色彩, 缩放到 14pt).
    private func conflictIconImage() -> NSImage? {
        let size = Self.conflictIconSize
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            return NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        }
        guard let caution = NSImage(named: NSImage.cautionName) else { return nil }
        let scaled = NSImage(size: NSSize(width: size, height: size))
        scaled.lockFocus()
        caution.draw(in: NSRect(origin: .zero, size: NSSize(width: size, height: size)))
        scaled.unlockFocus()
        return scaled
    }

    override func mouseEntered(with event: NSEvent) {
        guard conflictIconView != nil else {
            super.mouseEntered(with: event)
            return
        }
        showConflictPopover()
    }

    override func mouseExited(with event: NSEvent) {
        guard conflictIconView != nil else {
            super.mouseExited(with: event)
            return
        }
        hideConflictPopover()
    }

    private func showConflictPopover() {
        guard let anchor = conflictIconView, conflictPopover == nil else { return }

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true

        let vc = NSViewController()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("button_conflict_title", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let detailLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("button_conflict_detail", comment: ""))
        detailLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = NSColor.secondaryLabelColor
        detailLabel.preferredMaxLayoutWidth = 280
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(detailLabel)

        let padding: CGFloat = 12
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 300),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            detailLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            detailLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])

        vc.view = container
        popover.contentViewController = vc

        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        conflictPopover = popover
    }

    private func hideConflictPopover() {
        conflictPopover?.close()
        conflictPopover = nil
    }

    private func registerConflictObservers() {
        unregisterConflictObservers()
        let center = NotificationCenter.default
        let sessionToken = center.addObserver(
            forName: LogiCenter.sessionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshConflictIndicator()
        }
        let reportingToken = center.addObserver(
            forName: LogiCenter.reportingDidComplete,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshConflictIndicator()
        }
        conflictObserverTokens = [sessionToken, reportingToken]
    }

    private func unregisterConflictObservers() {
        let center = NotificationCenter.default
        for token in conflictObserverTokens {
            center.removeObserver(token)
        }
        conflictObserverTokens.removeAll()
    }

    /// 设置动作选择器 PopUpButton
    ///
    /// 关键设计：
    /// 1. 每次配置创建新的 NSMenu 实例，避免 cell 复用时共享状态
    /// 2. 默认禁用所有菜单项的 keyEquivalent，防止与 ButtonCore 触发的快捷键冲突
    /// 3. 通过 NSMenuDelegate 在菜单打开时临时启用 keyEquivalent（显示快捷键样式）
    private func setupActionPopUpButton(showLogiActions: Bool = false) {
        // 每次配置时创建新的 menu，避免 cell 复用时共享状态
        let menu = NSMenu()
        menu.delegate = self

        // 使用 ShortcutManager 构建菜单
        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: self,
            action: #selector(shortcutSelected(_:)),
            showLogiActions: showLogiActions
        )

        // 初始状态禁用所有 keyEquivalent，防止意外触发
        // 只在菜单打开时（menuWillOpen）临时启用，以显示快捷键样式
        disableKeyEquivalents(in: menu)

        // 替换 PopUpButton 的 menu
        actionPopUpButton.menu = menu

        // 设置当前选择
        refreshActionDisplay()
    }
    
    // MARK: - 私有方法

    func refreshActionDisplay() {
        let presentation = actionDisplayResolver.resolve(state: actionState)
        actionDisplayRenderer.render(presentation, into: actionPopUpButton)
    }

    func beginCustomShortcutSelection(startRecorder: Bool = true) {
        isCustomRecordingActive = true
        refreshActionDisplay()
        DispatchQueue.main.async { [weak self] in
            self?.refreshActionDisplay()
        }

        guard startRecorder else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.window != nil else { return }
            self.startCustomRecording()
        }
    }

    // MARK: - Custom Recording Helpers

    private func startCustomRecording() {
        customRecorder.startRecording(from: actionPopUpButton, mode: .adaptive)
    }

    // MARK: - Actions

    /// 快捷键选择回调
    @objc internal func shortcutSelected(_ sender: NSMenuItem) {
        // "打开…" sentinel: 把后续配置流程交给外部 (popover 提交后 controller reloadData)
        if sender.representedObject as? String == "__open__" {
            restoreTransientSelectorDisplay()
            onOpenTargetSelectionRequested?()
            return
        }

        // 自定义录制: 进入临时态 .recordingPrompt; 录制完成回调到 onEventRecorded
        if sender.representedObject as? String == "__custom__" {
            beginCustomShortcutSelection()
            return
        }

        // 系统/Logi/鼠标 等预定义快捷键, 或 nil = 取消绑定.
        let shortcut = sender.representedObject as? SystemShortcut.Shortcut
        applyLocalBindingChange { old in
            ButtonBinding(
                id: old.id,
                triggerEvent: old.triggerEvent,
                systemShortcutName: shortcut?.identifier ?? "",
                isEnabled: shortcut != nil,
                createdAt: old.createdAt
            )
        }
        refreshActionDisplay()
        onShortcutSelected?(shortcut)

        // 延迟重绘虚线和冲突指示器 (等待 PopUpButton 布局更新)
        DispatchQueue.main.async {
            self.refreshConflictIndicator()
        }
    }

    private func restoreTransientSelectorDisplay() {
        refreshActionDisplay()
        DispatchQueue.main.async { [weak self] in
            self?.refreshActionDisplay()
        }
    }

    /// 助手: 通过 transform 闭包更新本地 currentBinding (cell 内的 in-memory 副本).
    /// 调用方负责后续 refreshActionDisplay() 和 onShortcutSelected? / onCustomShortcutRecorded?
    /// 把变更同步给 controller.
    private func applyLocalBindingChange(_ transform: (ButtonBinding) -> ButtonBinding) {
        guard let old = currentBinding else { return }
        currentBinding = transform(old)
    }

    /// 删除绑定
    @objc private func deleteRecord(_ sender: NSButton) {
        onDeleteRequested?()
    }
}

// MARK: - NSMenuDelegate
/// 通过动态管理  keyEquivalent  解决冲突问题：
///
/// 问题：ButtonCore 触发快捷键时（如 ⌃→），NSMenu 会响应相同的 keyEquivalent，
///      导致错首行作为 firstResponsor 会将 popover 变为所按的快捷键
///
/// 解决方案：
/// - 菜单关闭时：禁用所有 keyEquivalent，防止意外触发
/// - 菜单打开时：启用 keyEquivalent，显示快捷键样式
extension ButtonTableCellView {

    func menuWillOpen(_ menu: NSMenu) {
        // 动态调整菜单结构
        adjustMenuStructure(menu)
        // 启用 keyEquivalent
        enableKeyEquivalents(in: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        disableKeyEquivalents(in: menu)
    }

    /// 根据当前状态动态调整菜单结构
    ///
    /// 根据绑定状态动态调整菜单显示:
    /// - 未绑定时: 隐藏占位符和第一条分割线,菜单只显示"未绑定"选项
    /// - 已绑定时: 显示占位符和第一条分割线,将菜单项改为"取消绑定"
    ///
    /// 这样避免了"未绑定"选项重复显示的问题
    private func adjustMenuStructure(_ menu: NSMenu) {
        guard menu.items.count >= 3 else { return }

        let placeholderItem = menu.items[0]  // 占位符
        let firstSeparator = menu.items[1]   // 第一条分割线
        let unboundItem = menu.items[2]      // "未绑定"/"取消绑定"菜单项

        // 单一权威源: actionState.hasBoundAction 内部 switch 全 case, 加新动作类型时
        // CellActionState 加 case 后这里不需要改 (新 case 默认 hasBoundAction 由 enum 实现统一).
        let hasBoundAction = actionState.hasBoundAction

        if !hasBoundAction {
            // 当前是未绑定状态:隐藏占位符和第一条分割线,显示"未绑定"
            placeholderItem.isHidden = true
            firstSeparator.isHidden = true
            unboundItem.title = NSLocalizedString("unbound", comment: "")
        } else {
            // 当前已绑定:显示占位符和第一条分割线,显示"取消绑定"
            placeholderItem.isHidden = false
            firstSeparator.isHidden = false
            unboundItem.title = NSLocalizedString("unbind", comment: "")
        }
    }

    /// 递归启用菜单的 keyEquivalent（从 representedObject 恢复）
    private func enableKeyEquivalents(in menu: NSMenu) {
        for item in menu.items {
            if let shortcut = item.representedObject as? SystemShortcut.Shortcut {
                let keyEquivalent = shortcut.keyEquivalent
                item.keyEquivalent = keyEquivalent.keyEquivalent
                item.keyEquivalentModifierMask = keyEquivalent.modifierMask
            }

            if let submenu = item.submenu {
                enableKeyEquivalents(in: submenu)
            }
        }
    }

    /// 递归禁用菜单的 keyEquivalent
    private func disableKeyEquivalents(in menu: NSMenu) {
        for item in menu.items {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []

            if let submenu = item.submenu {
                disableKeyEquivalents(in: submenu)
            }
        }
    }
}

// MARK: - KeyRecorderDelegate (Custom Recording)
extension ButtonTableCellView: KeyRecorderDelegate {
    func onRecordingStarted(_ recorder: KeyRecorder) {
        isCustomRecordingActive = true
        DispatchQueue.main.async {
            self.refreshActionDisplay()
        }
    }

    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {
        isCustomRecordingActive = false
        guard !didRecord else { return }
        DispatchQueue.main.async {
            self.refreshActionDisplay()
            self.refreshConflictIndicator()
        }
    }

    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        guard !isDuplicate else { return }
        let customName = ButtonBinding.normalizedCustomBindingName(
            code: event.code,
            modifiers: UInt64(event.modifiers.rawValue)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) { [weak self] in
            guard let self = self else { return }
            self.isCustomRecordingActive = false
            self.applyLocalBindingChange { old in
                ButtonBinding(
                    id: old.id,
                    triggerEvent: old.triggerEvent,
                    systemShortcutName: customName,
                    isEnabled: true,
                    createdAt: old.createdAt
                )
            }
            self.refreshActionDisplay()
            self.onCustomShortcutRecorded?(customName)
            // 重绘虚线和冲突指示器
            DispatchQueue.main.async {
                self.refreshConflictIndicator()
            }
        }
    }

    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        return true
    }
}
