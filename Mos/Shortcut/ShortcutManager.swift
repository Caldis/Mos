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
    ///
    /// 菜单结构设计:
    /// - 索引0: 占位符 PopUpButton 显示此项,动态更新标题和图标
    /// - 索引1: 分割线 #1 - 根据绑定状态动态隐藏/显示
    /// - 索引2: "未绑定"/"取消绑定" - 可选菜单项,representedObject 为 nil
    /// - 索引3: 分割线 #2 - 分隔操作区和分类菜单
    /// - 索引4+: 分类子菜单 (功能键,应用与窗口等)
    ///
    /// - Parameter menu: 目标菜单对象
    /// - Parameter target: 菜单项点击事件的目标对象
    /// - Parameter action: 菜单项点击事件的选择器
    static func buildShortcutMenu(into menu: NSMenu, target: AnyObject, action: Selector) {
        // 清空现有菜单项
        menu.removeAllItems()

        // 添加占位符 (用于显示当前选中的快捷键)
        // NSPopUpButton 不会自动显示子菜单项标题,必须用占位符模式
        let placeholderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(placeholderItem)

        // 添加第一条分割线 (未绑定时会被隐藏)
        menu.addItem(NSMenuItem.separator())

        // 添加"未绑定"选项 (可选菜单项, representedObject 为 nil)
        // 标题会在 menuWillOpen 时根据当前状态动态更新为"未绑定"或"取消绑定"
        let unboundItem = NSMenuItem(title: NSLocalizedString("unbound", comment: ""), action: action, keyEquivalent: "")
        unboundItem.target = target
        unboundItem.representedObject = nil  // nil 表示清除绑定
        menu.addItem(unboundItem)

        // 添加第二条分割线 (分隔"未绑定"操作和分类菜单)
        menu.addItem(NSMenuItem.separator())

        var totalShortcuts = 0

        // 按分类构建分级菜单（顺序由 shortcutsByCategory 数组定义）
        for (categoryIdentifier, shortcuts) in SystemShortcut.shortcutsByCategory {
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

            // 添加该分类下的所有快捷键到子菜单(过滤掉当前系统不支持的,保持原始顺序)
            let availableShortcuts = shortcuts.filter { $0.isAvailable }
            for shortcut in availableShortcuts {
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

