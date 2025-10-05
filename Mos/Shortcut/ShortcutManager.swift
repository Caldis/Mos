//
//  ShortcutManager.swift
//  Mos
//  快捷键管理器 - 菜单构建和快捷键触发
//  Created by Claude on 2025/9/27.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

/// 快捷键管理器
/// 职责:
/// 1. 构建分级快捷键菜单 (PopUpButton 使用)
/// 2. 触发系统快捷键 (模拟键盘事件)
class ShortcutManager {

    // MARK: - 版本检测

    /// 检测当前系统是否支持 SF Symbols (macOS 11.0+)
    private static var supportsSFSymbols: Bool {
        if #available(macOS 11.0, *) {
            return true
        }
        return false
    }

    /// 创建带图标的 NSImage (macOS 11.0+)
    @available(macOS 11.0, *)
    private static func createSymbolImage(_ symbolName: String) -> NSImage? {
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    // MARK: - 菜单构建
    /// 构建分级快捷键菜单 (按分类组织系统快捷键)
    /// - Parameter menu: 目标菜单对象
    /// - Parameter target: 菜单项点击事件的目标对象
    /// - Parameter action: 菜单项点击事件的选择器
    static func buildShortcutMenu(into menu: NSMenu, target: AnyObject, action: Selector) {
        // 清空现有菜单项
        menu.removeAllItems()

        // 添加 placeholder 项
        let placeholderItem = NSMenuItem(title: NSLocalizedString("selectAnAction", comment: ""), action: nil, keyEquivalent: "")
        placeholderItem.isEnabled = false
        menu.addItem(placeholderItem)

        // 添加分割线
        menu.addItem(NSMenuItem.separator())

        var totalShortcuts = 0

        // 按分类构建分级菜单
        for (categoryIdentifier, shortcuts) in SystemShortcut.shortcutsByCategory.sorted(by: { $0.key < $1.key }) {

            // 创建分类主菜单项 (使用本地化名称)
            let categoryName = SystemShortcut.localizedCategoryName(categoryIdentifier)
            let categoryMenuItem = NSMenuItem(title: categoryName, action: nil, keyEquivalent: "")

            // 为分类添加图标 (macOS 11.0+)
            if supportsSFSymbols {
                if #available(macOS 11.0, *) {
                    let symbolName = SystemShortcut.categorySymbolName(categoryIdentifier)
                    categoryMenuItem.image = createSymbolImage(symbolName)
                }
            }

            // 创建子菜单
            let subMenu = NSMenu(title: categoryName)

            // 添加该分类下的所有快捷键到子菜单
            let sortedShortcuts = shortcuts.sorted { $0.localizedName < $1.localizedName }
            for shortcut in sortedShortcuts {
                let menuKeyEquivalent = shortcut.keyEquivalent

                let shortcutMenuItem = NSMenuItem(
                    title: shortcut.localizedName,
                    action: action,
                    keyEquivalent: menuKeyEquivalent.keyEquivalent
                )
                shortcutMenuItem.keyEquivalentModifierMask = menuKeyEquivalent.modifierMask
                shortcutMenuItem.target = target
                shortcutMenuItem.representedObject = shortcut
                shortcutMenuItem.toolTip = shortcut.localizedName

                // 为快捷键添加图标 (macOS 11.0+)
                if supportsSFSymbols {
                    if #available(macOS 11.0, *) {
                        shortcutMenuItem.image = createSymbolImage(shortcut.symbolName)
                    }
                }

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

