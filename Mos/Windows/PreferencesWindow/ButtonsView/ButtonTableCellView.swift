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

    // MARK: - Data
    private weak var viewController: PreferencesButtonsViewController? // 父容器视图
    private var buttonBinding: ButtonBinding? // 按钮绑定
    private var row: Int?
    private var originalRowBackgroundColor: NSColor? // 保存原始行背景色

    // MARK: - 初始化内容
    func setup(from viewController: PreferencesButtonsViewController, with binding: ButtonBinding, at row: Int) {
        self.viewController = viewController
        self.buttonBinding = binding
        self.row = row

        // 保存原始背景色（首次或复用时）
        if originalRowBackgroundColor == nil, let rowView = self.superview as? NSTableRowView {
            originalRowBackgroundColor = rowView.backgroundColor
        }

        // 配置按键显示组件
        setupKeyDisplayView(with: binding.triggerEvent)

        // 配置动作选择器
        setupActionPopUpButton()
    }

    // 高亮该行（重复两次）
    func highlight() {
        guard let rowView = self.superview as? NSTableRowView else { return }
        // 设置高亮色
        let isDarkMode = Utils.isDarkMode(for: rowView)
        let highlightColor = isDarkMode ? NSColor(white: 1.0, alpha: 0.2) : NSColor(white: 0.0, alpha: 0.15)
        let originalColor = originalRowBackgroundColor ?? rowView.backgroundColor
        // 高亮
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0
            rowView.animator().backgroundColor = highlightColor
        }, completionHandler: {
            // 恢复
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 1.0
                rowView.animator().backgroundColor = originalColor
            })
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
    private func setupActionPopUpButton() {
        guard let menu = actionPopUpButton.menu else { return }

        // 使用 ShortcutManager 构建菜单
        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: self,
            action: #selector(shortcutSelected(_:))
        )

        // 延迟设置当前选择，确保菜单完全构建完成
        DispatchQueue.main.async { [weak self] in
            if let binding = self?.buttonBinding,
               !binding.systemShortcutName.isEmpty,
               let shortcut = binding.systemShortcut {
                self?.selectShortcutInMenu(shortcut)
            } else {
                // 如果没有绑定快捷键，确保显示默认占位符
                self?.resetPlaceholder()
            }
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

                    // 关键修复：手动设置显示标题
                    setCustomTitle(shortcutItem.title)

                    NSLog("[ButtonTableCellView] 已设置显示标题: \(shortcutItem.title)")
                    return
                }
            }
        }
    }

    /// 手动设置 PopUpButton 的显示标题
    private func setCustomTitle(_ title: String) {
        guard let menu = actionPopUpButton.menu,
              let placeholderItem = menu.items.first else {
            NSLog("[ButtonTableCellView] 无法找到占位符菜单项")
            return
        }

        // 更新占位符的标题为选中的快捷键
        placeholderItem.title = title

        // 确保占位符保持 disabled 状态
        placeholderItem.isEnabled = false

        // 选中占位符项
        actionPopUpButton.selectItem(at: 0)

        NSLog("[ButtonTableCellView] 已更新占位符显示: \(title)")
    }

    /// 重置占位符为默认状态
    private func resetPlaceholder() {
        guard let menu = actionPopUpButton.menu,
              let placeholderItem = menu.items.first else {
            return
        }

        // 重置为默认占位符文本
        placeholderItem.title = "Select an action"
        placeholderItem.isEnabled = false

        // 选中占位符项
        actionPopUpButton.selectItem(at: 0)
    }

    // MARK: - Actions

    /// 快捷键选择回调
    @objc private func shortcutSelected(_ sender: NSMenuItem) {
        guard let shortcut = sender.representedObject as? SystemShortcut.Shortcut,
              let binding = buttonBinding,
              let row = self.row else {
            NSLog("[ButtonTableCellView] 无法获取快捷键或绑定信息")
            return
        }

        // 更新绑定的快捷键
        let updatedBinding = ButtonBinding(
            triggerEvent: binding.triggerEvent,
            systemShortcutName: SystemShortcut.findShortcut(
                modifiers: shortcut.modifiers,
                keyCode: shortcut.code
            ) ?? "copy",
            isEnabled: true  // 选择快捷键后启用绑定
        )

        // 更新本地绑定状态
        self.buttonBinding = updatedBinding

        // 设置自定义显示标题
        setCustomTitle(sender.title)

        // 通知父视图控制器更新
        viewController?.updateButtonBinding(at: row, with: updatedBinding)

        NSLog("[ButtonTableCellView] 当前选择显示: \(actionPopUpButton.titleOfSelectedItem ?? "无")")
    }

    /// 删除绑定
    @objc private func deleteRecord(_ sender: NSButton) {
        guard let row = self.row else { return }
        viewController?.removeButtonBinding(row)
    }
}
