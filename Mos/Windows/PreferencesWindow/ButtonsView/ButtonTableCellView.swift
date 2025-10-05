//
//  ButtonTableCellView 2.swift
//  Mos
//
//  Created by 陈标 on 2025/9/27.
//  Copyright © 2025 Caldis. All rights reserved.
//


import Cocoa

class ButtonTableCellView: NSTableCellView {

    // MARK: - IBOutlets
    @IBOutlet weak var keyDisplayContainerView: NSView!
    @IBOutlet weak var actionPopUpButton: NSPopUpButton!

    // MARK: - UI Components
    private var keyPreview: KeyPreview!

    // MARK: - Callbacks
    private var onShortcutSelected: ((SystemShortcut.Shortcut) -> Void)?
    private var onDeleteRequested: (() -> Void)?

    // MARK: - Data (只用于UI显示)
    private var currentShortcut: SystemShortcut.Shortcut?
    private var originalRowBackgroundColor: NSColor?

    // MARK: - 配置方法
    func configure(
        with binding: ButtonBinding,
        onShortcutSelected: @escaping (SystemShortcut.Shortcut) -> Void,
        onDeleteRequested: @escaping () -> Void
    ) {
        // 保存回调
        self.onShortcutSelected = onShortcutSelected
        self.onDeleteRequested = onDeleteRequested
        self.currentShortcut = binding.systemShortcut

        // 保存原始背景色（首次或复用时）
        if originalRowBackgroundColor == nil, let rowView = self.superview as? NSTableRowView {
            originalRowBackgroundColor = rowView.backgroundColor
        }

        // 配置按键显示组件
        setupKeyDisplayView(with: binding.triggerEvent)

        // 配置动作选择器
        setupActionPopUpButton(currentShortcut: binding.systemShortcut)
    }

    // 高亮该行（重复两次）
    func highlight() {
        guard let rowView = self.superview as? NSTableRowView else { return }
        // 设置高亮色
        let isDarkMode = Utils.isDarkMode(for: rowView)
        let highlightColor = isDarkMode ? NSColor(white: 1.0, alpha: 0.2) : NSColor(white: 0.0, alpha: 0.2)
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
    
    // 设置动作按钮
    private func setupActionPopUpButton(currentShortcut: SystemShortcut.Shortcut?) {
        guard let menu = actionPopUpButton.menu else { return }

        // 使用 ShortcutManager 构建菜单
        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: self,
            action: #selector(shortcutSelected(_:))
        )

        // 设置当前选择
        if let shortcut = currentShortcut {
            selectShortcutInMenu(shortcut)
        } else {
            resetPlaceholder()
        }
    }
    
    // MARK: - 私有方法

    /// 在菜单中选中指定的快捷键
    private func selectShortcutInMenu(_ shortcut: SystemShortcut.Shortcut) {
        guard let menu = actionPopUpButton.menu else {
            NSLog("[ButtonTableCellView] 无法获取菜单")
            return
        }

        // 首先尝试在子菜单中查找匹配的快捷键
        for categoryItem in menu.items {
            guard let subMenu = categoryItem.submenu else { continue }

            for shortcutItem in subMenu.items {
                if let itemShortcut = shortcutItem.representedObject as? SystemShortcut.Shortcut,
                   itemShortcut == shortcut {
                    NSLog("[ButtonTableCellView] 找到匹配项: \(shortcutItem.title)")

                    // 设置显示标题和图标
                    setCustomTitle(shortcutItem.title, image: shortcutItem.image)

                    NSLog("[ButtonTableCellView] 已设置显示标题: \(shortcutItem.title)")
                    return
                }
            }
        }
    }

    /// 手动设置 PopUpButton 的显示标题和图标
    private func setCustomTitle(_ title: String, image: NSImage?) {
        guard let menu = actionPopUpButton.menu,
              let placeholderItem = menu.items.first else {
            NSLog("[ButtonTableCellView] 无法找到占位符菜单项")
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

        // 确保占位符保持 disabled 状态
        placeholderItem.isEnabled = false

        // 选中占位符项
        actionPopUpButton.selectItem(at: 0)

        NSLog("[ButtonTableCellView] 已更新占位符显示: \(title)")
    }

    /// 创建带右侧边距的图标 (用于 PopUpButton 显示)
    private func createImageWithTrailingSpace(_ originalImage: NSImage) -> NSImage {
        let spacing: CGFloat = 4.0  // 右侧边距
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

    /// 重置占位符为默认状态
    private func resetPlaceholder() {
        guard let menu = actionPopUpButton.menu,
              let placeholderItem = menu.items.first else {
            return
        }

        // 重置为默认占位符文本
        placeholderItem.title = NSLocalizedString("selectAnAction", comment: "")
        placeholderItem.isEnabled = false

        // 选中占位符项
        actionPopUpButton.selectItem(at: 0)
    }

    // MARK: - Actions

    /// 快捷键选择回调
    @objc private func shortcutSelected(_ sender: NSMenuItem) {
        guard let shortcut = sender.representedObject as? SystemShortcut.Shortcut else {
            NSLog("[ButtonTableCellView] 无法获取快捷键信息")
            return
        }

        // 更新本地状态
        self.currentShortcut = shortcut

        // 设置自定义显示标题和图标
        setCustomTitle(sender.title, image: sender.image)

        // 通知外部更新
        onShortcutSelected?(shortcut)

        NSLog("[ButtonTableCellView] 选中快捷键: \(sender.title)")
    }

    /// 删除绑定
    @objc private func deleteRecord(_ sender: NSButton) {
        onDeleteRequested?()
    }
}
