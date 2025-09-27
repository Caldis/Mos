//
//  ShortcutManager.swift
//  Mos
//  快捷键管理器 - 统一处理快捷键菜单构建和事件发送
//  Created by Claude on 2025/9/27.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

/// 快捷键管理器 - 负责快捷键菜单构建和事件触发
class ShortcutManager {

    // MARK: - 单例
    static let shared = ShortcutManager()
    private init() {}

    // MARK: - 菜单构建

    /// 构建分级快捷键菜单 (用于 MonitorViewController)
    /// - Parameter menu: 目标菜单对象
    /// - Parameter target: 菜单项点击事件的目标对象
    /// - Parameter action: 菜单项点击事件的选择器
    func buildHierarchicalShortcutMenu(into menu: NSMenu, target: AnyObject, action: Selector) {
        // 清空现有菜单项
        menu.removeAllItems()

        NSLog("[ShortcutManager] 开始构建分级快捷键菜单...")

        // 添加 placeholder 项
        let placeholderItem = NSMenuItem(title: "Select an action", action: nil, keyEquivalent: "")
        placeholderItem.isEnabled = false
        menu.addItem(placeholderItem)

        // 添加分割线
        menu.addItem(NSMenuItem.separator())

        var totalShortcuts = 0

        // 按分类构建分级菜单
        for (categoryName, shortcuts) in SystemShortcut.shortcutsByCategory.sorted(by: { $0.key < $1.key }) {
            NSLog("[ShortcutManager] 创建分类子菜单: \(categoryName) (\(shortcuts.count) 个快捷键)")

            // 创建分类主菜单项
            let categoryMenuItem = NSMenuItem(title: categoryName, action: nil, keyEquivalent: "")

            // 创建子菜单
            let subMenu = NSMenu(title: categoryName)

            // 添加该分类下的所有快捷键到子菜单
            let sortedShortcuts = shortcuts.sorted { $0.key < $1.key }
            for (shortcutName, shortcut) in sortedShortcuts {
                let shortcutMenuItem = NSMenuItem(
                    title: "\(formatDisplayName(shortcutName)) - \(shortcut.displayName)",
                    action: action,
                    keyEquivalent: ""
                )
                shortcutMenuItem.target = target
                shortcutMenuItem.representedObject = shortcut
                shortcutMenuItem.toolTip = "快捷键: \(shortcut.displayName)"

                subMenu.addItem(shortcutMenuItem)
                totalShortcuts += 1
            }

            // 将子菜单关联到分类菜单项
            categoryMenuItem.submenu = subMenu

            // 将分类菜单项添加到主菜单
            menu.addItem(categoryMenuItem)
        }

        NSLog("[ShortcutManager] 分级快捷键菜单构建完成: \(SystemShortcut.shortcutsByCategory.count) 个分类，\(totalShortcuts) 个快捷键")
    }

    /// 构建多级快捷键菜单 (修复 NSPopUpButton 显示问题)
    /// - Parameter menu: 目标菜单对象
    /// - Parameter target: 菜单项点击事件的目标对象
    /// - Parameter action: 菜单项点击事件的选择器
    func buildShortcutMenu(into menu: NSMenu, target: AnyObject, action: Selector) {
        // 清空现有菜单项
        menu.removeAllItems()

        NSLog("[ShortcutManager] 开始构建多级快捷键菜单...")

        // 添加 placeholder 项
        let placeholderItem = NSMenuItem(title: "Select an action", action: nil, keyEquivalent: "")
        placeholderItem.isEnabled = false
        menu.addItem(placeholderItem)

        // 添加分割线
        menu.addItem(NSMenuItem.separator())

        var totalShortcuts = 0

        // 按分类构建分级菜单
        for (categoryName, shortcuts) in SystemShortcut.shortcutsByCategory.sorted(by: { $0.key < $1.key }) {
            NSLog("[ShortcutManager] 创建分类子菜单: \(categoryName) (\(shortcuts.count) 个快捷键)")

            // 创建分类主菜单项
            let categoryMenuItem = NSMenuItem(title: categoryName, action: nil, keyEquivalent: "")

            // 创建子菜单
            let subMenu = NSMenu(title: categoryName)

            // 添加该分类下的所有快捷键到子菜单
            let sortedShortcuts = shortcuts.sorted { $0.key < $1.key }
            for (shortcutName, shortcut) in sortedShortcuts {
                let shortcutMenuItem = NSMenuItem(
                    title: "\(formatDisplayName(shortcutName)) - \(shortcut.displayName)",
                    action: action,
                    keyEquivalent: ""
                )
                shortcutMenuItem.target = target
                shortcutMenuItem.representedObject = shortcut
                shortcutMenuItem.toolTip = "快捷键: \(shortcut.displayName)"

                subMenu.addItem(shortcutMenuItem)
                totalShortcuts += 1
            }

            // 将子菜单关联到分类菜单项
            categoryMenuItem.submenu = subMenu

            // 将分类菜单项添加到主菜单
            menu.addItem(categoryMenuItem)
        }

        NSLog("[ShortcutManager] 多级快捷键菜单构建完成: \(SystemShortcut.shortcutsByCategory.count) 个分类，\(totalShortcuts) 个快捷键")
    }

    // MARK: - 事件创建与发送

    /// 触发系统快捷键
    /// - Parameter shortcut: 要触发的快捷键
    /// - Parameter completion: 完成回调
    func triggerShortcut(_ shortcut: SystemShortcut.Shortcut, completion: ((Bool) -> Void)? = nil) {
        NSLog("[ShortcutManager] 触发快捷键: \(shortcut.displayName)")

        do {
            // 构造键盘按下事件 (keyDown)
            guard let keyDownEvent = createKeyEvent(
                type: .keyDown,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers
            ) else {
                throw NSError(domain: "ShortcutManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "keyDown 事件构造失败"])
            }

            // 构造键盘抬起事件 (keyUp)
            guard let keyUpEvent = createKeyEvent(
                type: .keyUp,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers
            ) else {
                throw NSError(domain: "ShortcutManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "keyUp 事件构造失败"])
            }

            // 发送事件
            postKeyboardEvents(keyDownEvent: keyDownEvent, keyUpEvent: keyUpEvent) { success in
                NSLog("[ShortcutManager] 快捷键 \(shortcut.displayName) 发送完成: \(success)")
                completion?(success)
            }

        } catch {
            NSLog("[ShortcutManager] 快捷键触发失败: \(error.localizedDescription)")
            completion?(false)
        }
    }

    /// 延迟触发系统快捷键
    /// - Parameter shortcut: 要触发的快捷键
    /// - Parameter delay: 延迟时间(秒)
    /// - Parameter completion: 完成回调
    func triggerShortcut(_ shortcut: SystemShortcut.Shortcut, delay: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        NSLog("[ShortcutManager] ⏱️ \(delay)秒后发送 \(shortcut.displayName)")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.triggerShortcut(shortcut, completion: completion)
        }
    }

    // MARK: - 私有方法

    /// 创建键盘事件
    private func createKeyEvent(type: CGEventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> CGEvent? {
        // 创建基础键盘事件
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: type == .keyDown
        ) else {
            NSLog("[ShortcutManager] 无法创建基础键盘事件")
            return nil
        }

        // 设置修饰键
        var cgFlags: CGEventFlags = []

        if modifiers.contains(.command) {
            cgFlags.insert(.maskCommand)
        }
        if modifiers.contains(.shift) {
            cgFlags.insert(.maskShift)
        }
        if modifiers.contains(.option) {
            cgFlags.insert(.maskAlternate)
        }
        if modifiers.contains(.control) {
            cgFlags.insert(.maskControl)
        }
        if modifiers.contains(.function) {
            cgFlags.insert(.maskSecondaryFn)
        }

        event.flags = cgFlags
        event.timestamp = CGEventTimestamp(mach_absolute_time())

        return event
    }

    /// 发送键盘事件到系统
    private func postKeyboardEvents(keyDownEvent: CGEvent, keyUpEvent: CGEvent, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 发送 keyDown 事件
            let keyDownLocation = CGEventTapLocation.cghidEventTap
            keyDownEvent.post(tap: keyDownLocation)

            // 短暂延迟，模拟真实按键时序
            usleep(10000) // 10ms

            // 发送 keyUp 事件
            let keyUpLocation = CGEventTapLocation.cghidEventTap
            keyUpEvent.post(tap: keyUpLocation)

            DispatchQueue.main.async {
                completion?(true)
            }
        }
    }

    /// 将驼峰命名转换为用户友好的显示名称
    private func formatDisplayName(_ camelCaseName: String) -> String {
        // 插入空格在小写字母和大写字母之间
        var result = camelCaseName.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)

        // 处理数字和字母之间的空格
        result = result.replacingOccurrences(of: "([a-z])([0-9])", with: "$1 $2", options: .regularExpression)
        result = result.replacingOccurrences(of: "([0-9])([A-Z])", with: "$1 $2", options: .regularExpression)

        // 首字母大写
        return result.prefix(1).capitalized + result.dropFirst()
    }
}