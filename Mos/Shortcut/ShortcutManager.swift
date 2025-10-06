//
//  ShortcutManager.swift
//  Mos
//  快捷键管理器 - 菜单构建和快捷键触发
//  Created by Claude on 2025/9/27.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

/// 快捷键管理器
/// 职责: 构建分级快捷键菜单 (PopUpButton 使用)
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

        // 按分类构建分级菜单（使用显式的分类顺序）
        for categoryIdentifier in SystemShortcut.categoryOrder {
            guard let shortcuts = SystemShortcut.shortcutsByCategory[categoryIdentifier] else { continue }

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

}

