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

    // MARK: - 菜单构建
    /// 构建分级快捷键菜单 (用于 MonitorViewController)
    /// - Parameter menu: 目标菜单对象
    /// - Parameter target: 菜单项点击事件的目标对象
    /// - Parameter action: 菜单项点击事件的选择器
    static func buildHierarchicalShortcutMenu(into menu: NSMenu, target: AnyObject, action: Selector) {
        // 清空现有菜单项
        menu.removeAllItems()

        // 添加 placeholder 项
        let placeholderItem = NSMenuItem(title: "Select an action", action: nil, keyEquivalent: "")
        placeholderItem.isEnabled = false
        menu.addItem(placeholderItem)

        // 添加分割线
        menu.addItem(NSMenuItem.separator())

        var totalShortcuts = 0

        // 按分类构建分级菜单
        for (categoryName, shortcuts) in SystemShortcut.shortcutsByCategory.sorted(by: { $0.key < $1.key }) {

            // 创建分类主菜单项
            let categoryMenuItem = NSMenuItem(title: categoryName, action: nil, keyEquivalent: "")

            // 创建子菜单
            let subMenu = NSMenu(title: categoryName)

            // 添加该分类下的所有快捷键到子菜单
            let sortedShortcuts = shortcuts.sorted { $0.name < $1.name }
            for shortcut in sortedShortcuts {
                let menuKeyEquivalent = shortcut.keyEquivalent

                let shortcutMenuItem = NSMenuItem(
                    title: shortcut.name,
                    action: action,
                    keyEquivalent: menuKeyEquivalent.keyEquivalent
                )
                shortcutMenuItem.keyEquivalentModifierMask = menuKeyEquivalent.modifierMask
                shortcutMenuItem.target = target
                shortcutMenuItem.representedObject = shortcut
                shortcutMenuItem.toolTip = shortcut.name

                subMenu.addItem(shortcutMenuItem)
                totalShortcuts += 1
            }

            // 将子菜单关联到分类菜单项
            categoryMenuItem.submenu = subMenu

            // 将分类菜单项添加到主菜单
            menu.addItem(categoryMenuItem)
        }
    }

    /// 构建多级快捷键菜单 (修复 NSPopUpButton 显示问题)
    /// - Parameter menu: 目标菜单对象
    /// - Parameter target: 菜单项点击事件的目标对象
    /// - Parameter action: 菜单项点击事件的选择器
    static func buildShortcutMenu(into menu: NSMenu, target: AnyObject, action: Selector) {
        // 清空现有菜单项
        menu.removeAllItems()

        // 添加 placeholder 项
        let placeholderItem = NSMenuItem(title: "Select an action", action: nil, keyEquivalent: "")
        placeholderItem.isEnabled = false
        menu.addItem(placeholderItem)

        // 添加分割线
        menu.addItem(NSMenuItem.separator())

        var totalShortcuts = 0

        // 按分类构建分级菜单
        for (categoryName, shortcuts) in SystemShortcut.shortcutsByCategory.sorted(by: { $0.key < $1.key }) {

            // 创建分类主菜单项
            let categoryMenuItem = NSMenuItem(title: categoryName, action: nil, keyEquivalent: "")

            // 创建子菜单
            let subMenu = NSMenu(title: categoryName)

            // 添加该分类下的所有快捷键到子菜单
            let sortedShortcuts = shortcuts.sorted { $0.name < $1.name }
            for shortcut in sortedShortcuts {
                let menuKeyEquivalent = shortcut.keyEquivalent

                let shortcutMenuItem = NSMenuItem(
                    title: shortcut.name,
                    action: action,
                    keyEquivalent: menuKeyEquivalent.keyEquivalent
                )
                shortcutMenuItem.keyEquivalentModifierMask = menuKeyEquivalent.modifierMask
                shortcutMenuItem.target = target
                shortcutMenuItem.representedObject = shortcut
                shortcutMenuItem.toolTip = shortcut.name

                subMenu.addItem(shortcutMenuItem)
                totalShortcuts += 1
            }

            // 将子菜单关联到分类菜单项
            categoryMenuItem.submenu = subMenu

            // 将分类菜单项添加到主菜单
            menu.addItem(categoryMenuItem)
        }
    }

    // MARK: - 事件创建与发送

    /// 触发系统快捷键
    /// - Parameter shortcut: 要触发的快捷键
    /// - Parameter completion: 完成回调
    static func triggerShortcut(_ shortcut: SystemShortcut.Shortcut, completion: ((Bool) -> Void)? = nil) {
        do {
            // 构造键盘按下事件 (keyDown)
            guard let keyDownEvent = createKeyEvent(
                type: .keyDown,
                keyCode: shortcut.code,
                modifiers: shortcut.modifiers
            ) else {
                throw NSError(domain: "ShortcutManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "keyDown 事件构造失败"])
            }

            // 构造键盘抬起事件 (keyUp)
            guard let keyUpEvent = createKeyEvent(
                type: .keyUp,
                keyCode: shortcut.code,
                modifiers: shortcut.modifiers
            ) else {
                throw NSError(domain: "ShortcutManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "keyUp 事件构造失败"])
            }

            // 发送事件
            postKeyboardEvents(keyDownEvent: keyDownEvent, keyUpEvent: keyUpEvent) { success in
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
    static func triggerShortcut(_ shortcut: SystemShortcut.Shortcut, delay: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.triggerShortcut(shortcut, completion: completion)
        }
    }

    // MARK: - 私有方法


    /// 创建键盘事件
    static func createKeyEvent(type: CGEventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> CGEvent? {
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
    static func postKeyboardEvents(keyDownEvent: CGEvent, keyUpEvent: CGEvent, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 发送 keyDown 事件
            keyDownEvent.post(tap: .cghidEventTap)

            // 短暂延迟，模拟真实按键时序
            usleep(10000) // 10ms

            // 发送 keyUp 事件
            keyUpEvent.post(tap: .cghidEventTap)

            DispatchQueue.main.async { completion?(true) }
        }
    }

}

