//
//  ButtonTableCellView 2.swift
//  Mos
//
//  Created by 陈标 on 2025/9/27.
//  Copyright © 2025 Caldis. All rights reserved.
//


import Cocoa

class ButtonTableCellView: NSTableCellView, NSMenuDelegate {

    // MARK: - IBOutlets
    @IBOutlet weak var keyDisplayContainerView: NSView!
    @IBOutlet weak var actionPopUpButton: NSPopUpButton!

    // MARK: - UI Components
    private var keyPreview: KeyPreview!
    private var dashedLineLayer: CAShapeLayer?
    private var defaultToggle: NSButton!  // Using NSButton for compatibility with macOS < 10.15
    private var appSettingsButton: NSButton!

    // MARK: - Callbacks
    private var onShortcutSelected: ((SystemShortcut.Shortcut?) -> Void)?
    private var onDeleteRequested: (() -> Void)?
    private var onDefaultToggleChanged: ((Bool) -> Void)?
    private var onAppSettingsRequested: (() -> Void)?

    // MARK: - Data (只用于UI显示)
    private var currentShortcut: SystemShortcut.Shortcut?
    private var currentBinding: ButtonBinding?
    private var originalRowBackgroundColor: NSColor?

    // MARK: - 配置方法
    func configure(
        with binding: ButtonBinding,
        onShortcutSelected: @escaping (SystemShortcut.Shortcut?) -> Void,
        onDeleteRequested: @escaping () -> Void,
        onDefaultToggleChanged: @escaping (Bool) -> Void,
        onAppSettingsRequested: @escaping () -> Void
    ) {
        // 保存回调
        self.onShortcutSelected = onShortcutSelected
        self.onDeleteRequested = onDeleteRequested
        self.onDefaultToggleChanged = onDefaultToggleChanged
        self.onAppSettingsRequested = onAppSettingsRequested
        self.currentShortcut = binding.systemShortcut
        self.currentBinding = binding

        // 保存原始背景色（首次或复用时）
        if originalRowBackgroundColor == nil, let rowView = self.superview as? NSTableRowView {
            originalRowBackgroundColor = rowView.backgroundColor
        }

        // 配置按键显示组件
        setupKeyDisplayView(with: binding.triggerEvent)

        // 配置动作选择器
        setupActionPopUpButton(currentShortcut: binding.systemShortcut)
        
        // 配置默认开关和应用设置按钮
        setupDefaultToggleAndAppSettings(binding: binding)

        // 绘制虚线分隔符(延迟到下一个 runloop,等 AutoLayout 完成布局)
        DispatchQueue.main.async {
            self.setupDashedLine()
        }
    }
    
    // 兼容旧的 configure 方法
    func configure(
        with binding: ButtonBinding,
        onShortcutSelected: @escaping (SystemShortcut.Shortcut?) -> Void,
        onDeleteRequested: @escaping () -> Void
    ) {
        configure(
            with: binding,
            onShortcutSelected: onShortcutSelected,
            onDeleteRequested: onDeleteRequested,
            onDefaultToggleChanged: { _ in },
            onAppSettingsRequested: { }
        )
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
        path.move(to: CGPoint(x: startX, y: centerY))
        path.addLine(to: CGPoint(x: endX, y: centerY))

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

    /// 设置动作选择器 PopUpButton
    ///
    /// 关键设计：
    /// 1. 每次配置创建新的 NSMenu 实例，避免 cell 复用时共享状态
    /// 2. 默认禁用所有菜单项的 keyEquivalent，防止与 ButtonCore 触发的快捷键冲突
    /// 3. 通过 NSMenuDelegate 在菜单打开时临时启用 keyEquivalent（显示快捷键样式）
    private func setupActionPopUpButton(currentShortcut: SystemShortcut.Shortcut?) {
        // 每次配置时创建新的 menu，避免 cell 复用时共享状态
        let menu = NSMenu()
        menu.delegate = self

        // 使用 ShortcutManager 构建菜单
        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: self,
            action: #selector(shortcutSelected(_:))
        )

        // 初始状态禁用所有 keyEquivalent，防止意外触发
        // 只在菜单打开时（menuWillOpen）临时启用，以显示快捷键样式
        disableKeyEquivalents(in: menu)

        // 替换 PopUpButton 的 menu
        actionPopUpButton.menu = menu

        // 设置当前选择
        if let shortcut = currentShortcut {
            selectShortcutInMenu(shortcut)
        } else {
            setPlaceholderToUnbound()
        }
    }
    
    // 列位置常量 (与 PreferencesButtonsViewController 中的值保持一致)
    // 从 cell 的右边缘计算各列中心位置
    private static let appColumnCenterFromTrailing: CGFloat = 20
    private static let defaultColumnCenterFromTrailing: CGFloat = 70
    private static let actionColumnTrailingFromTrailing: CGFloat = 100  // Action 列右边缘距 cell 右边缘
    
    /// 设置默认开关和应用设置按钮
    private func setupDefaultToggleAndAppSettings(binding: ButtonBinding) {
        // 移除旧的开关和按钮 (cell 复用时)
        defaultToggle?.removeFromSuperview()
        appSettingsButton?.removeFromSuperview()
        
        // 获取 actionPopUpButton 的父容器 (contentView inside Box)
        guard let contentView = actionPopUpButton.superview else { return }
        
        // 调整 actionPopUpButton 位置
        // 不要修改 storyboard 的约束，只调整 trailing 约束的 constant
        for constraint in contentView.constraints {
            // 找到 actionPopUpButton 的 trailing 约束并调整
            if constraint.firstAttribute == .trailing,
               let secondItem = constraint.secondItem as? NSPopUpButton,
               secondItem == actionPopUpButton {
                constraint.constant = Self.actionColumnTrailingFromTrailing
            }
        }
        
        // 创建默认开关 (使用 NSButton 以兼容旧版本 macOS)
        defaultToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(defaultToggleChanged(_:)))
        defaultToggle.translatesAutoresizingMaskIntoConstraints = false
        defaultToggle.state = binding.isDefaultEnabled ? .on : .off
        defaultToggle.toolTip = NSLocalizedString("button.default.tooltip", comment: "")
        contentView.addSubview(defaultToggle)
        
        // 创建应用设置按钮 (使用与滚动设置相同的图标样式)
        appSettingsButton = NSButton(frame: .zero)
        appSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        appSettingsButton.bezelStyle = .inline
        appSettingsButton.setButtonType(.momentaryPushIn)
        appSettingsButton.image = NSImage(named: NSImage.iconViewTemplateName)
        appSettingsButton.imagePosition = .imageOnly
        appSettingsButton.imageScaling = .scaleProportionallyDown
        appSettingsButton.target = self
        appSettingsButton.action = #selector(appSettingsButtonClicked(_:))
        
        // 设置 tooltip 显示应用规则数量
        let disabledCount = binding.disabledApplications.count
        let enabledCount = binding.enabledApplications.count
        let totalCount = disabledCount + enabledCount
        if totalCount > 0 {
            var parts: [String] = []
            if disabledCount > 0 {
                parts.append("\(disabledCount) \(NSLocalizedString("button.exceptions.disabled", comment: ""))")
            }
            if enabledCount > 0 {
                parts.append("\(enabledCount) \(NSLocalizedString("button.exceptions.enabled", comment: ""))")
            }
            appSettingsButton.toolTip = parts.joined(separator: ", ")
        } else {
            appSettingsButton.toolTip = NSLocalizedString("button.app.settings.tooltip", comment: "")
        }
        contentView.addSubview(appSettingsButton)
        
        // 布局约束 - 使用 contentView 的 trailing anchor
        // contentView 是 Box 内的 content view，与 actionPopUpButton 在同一层级
        NSLayoutConstraint.activate([
            // Apps 按钮: 距 contentView trailing 20pt
            appSettingsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            appSettingsButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            appSettingsButton.widthAnchor.constraint(equalToConstant: 20),
            appSettingsButton.heightAnchor.constraint(equalToConstant: 20),
            
            // Default 开关: 在 Apps 按钮左边
            defaultToggle.trailingAnchor.constraint(equalTo: appSettingsButton.leadingAnchor, constant: -30),
            defaultToggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
    
    // MARK: - Actions for toggle and settings
    
    @objc private func defaultToggleChanged(_ sender: NSButton) {
        let isEnabled = sender.state == .on
        onDefaultToggleChanged?(isEnabled)
    }
    
    @objc private func appSettingsButtonClicked(_ sender: NSButton) {
        onAppSettingsRequested?()
    }
    
    // MARK: - 私有方法

    /// 在菜单中选中指定的快捷键
    private func selectShortcutInMenu(_ shortcut: SystemShortcut.Shortcut) {
        guard let menu = actionPopUpButton.menu else {
            NSLog("[ButtonTableCellView] 无法获取菜单")
            return
        }

        // 在子菜单中查找匹配的快捷键
        for categoryItem in menu.items {
            guard let subMenu = categoryItem.submenu else { continue }

            for shortcutItem in subMenu.items {
                if let itemShortcut = shortcutItem.representedObject as? SystemShortcut.Shortcut,
                   itemShortcut == shortcut {
                    // 将快捷键的标题和图标复制到占位符,然后选中占位符
                    setCustomTitle(shortcutItem.title, image: shortcutItem.image)
                    return
                }
            }
        }
    }

    /// 手动设置 PopUpButton 的显示标题和图标
    private func setCustomTitle(_ title: String, image: NSImage?) {
        guard let menu = actionPopUpButton.menu,
              let placeholderItem = menu.items.first else {
            return
        }

        // 更新占位符的标题为选中的快捷键
        placeholderItem.title = title

        // 更新占位符的图标 (如果有)
        // NSPopUpButton 中图标和文本间距较紧,需要添加右侧边距
        if let originalImage = image {
            placeholderItem.image = createImageWithTrailingSpace(originalImage)
        } else {
            placeholderItem.image = nil
        }

        // 选中占位符项
        actionPopUpButton.selectItem(at: 0)
    }

    /// 创建带右侧边距的图标 (用于 PopUpButton 显示)
    private func createImageWithTrailingSpace(_ originalImage: NSImage) -> NSImage {
        let spacing: CGFloat = 2.0  // 右侧边距
        let originalSize = originalImage.size
        let newSize = NSSize(width: originalSize.width + spacing, height: originalSize.height)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()

        // 在左侧绘制原始图标,右侧留白
        originalImage.draw(
            in: NSRect(x: 0, y: 0, width: originalSize.width, height: originalSize.height),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .sourceOver,
            fraction: 1.0
        )

        newImage.unlockFocus()

        // template 模式,确保图标能适配系统颜色
        newImage.isTemplate = originalImage.isTemplate

        return newImage
    }

    /// 设置占位符为"未绑定"状态
    private func setPlaceholderToUnbound() {
        setCustomTitle(NSLocalizedString("unbound", comment: ""), image: nil)
    }

    // MARK: - Actions

    /// 快捷键选择回调
    @objc private func shortcutSelected(_ sender: NSMenuItem) {
        // representedObject 为 nil 时表示用户选择了"未绑定"
        let shortcut = sender.representedObject as? SystemShortcut.Shortcut

        // 更新本地状态
        self.currentShortcut = shortcut

        // 更新占位符显示
        if shortcut != nil {
            // 选择了具体快捷键,复制标题和图标到占位符
            setCustomTitle(sender.title, image: sender.image)
        } else {
            // 选择了"未绑定",设置占位符为未绑定状态
            setPlaceholderToUnbound()
        }

        // 通知外部更新(nil 表示清除绑定)
        onShortcutSelected?(shortcut)
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

        if currentShortcut == nil {
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
