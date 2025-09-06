//
//  StatusItemManager.swift
//  Mos
//  管理状态栏图标以及初始化
//  Created by Caldis on 2018/3/7.
//  Copyright © 2018年 Caldis. All rights reserved.
//
import Cocoa

enum STATUS_ITEM_TYPE {
    case menu
    case popover
}

class StatusItemManager: NSMenu, NSMenuDelegate {
    
    // 状态栏类型
    let TYPE = STATUS_ITEM_TYPE.menu
    
    // 状态栏引用
    static let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let item = StatusItemManager.statusItem
    
    // 初始化
    override func awakeFromNib() {
        NSLog("Module initialized: StatusItemManager")
        // 设置图标/行为
        item.button?.image = #imageLiteral(resourceName: "AppStatusBarIcon")
        // 设置事件响应
        switch TYPE {
            // 类型: 菜单
            case STATUS_ITEM_TYPE.menu:
                // 设置菜单代理
                item.menu = self
                item.menu?.delegate = self
                break
            // 类型: 弹出面板
            case STATUS_ITEM_TYPE.popover:
                // 点击事件 (需要设置 target 才能响应此处方法)
                item.button?.action = #selector(onMenuClick)
                item.button?.target = self
                break
        }
    }
    
}

/**
 * 菜单响应
 **/
extension StatusItemManager {
    // 打开菜单
    func menuWillOpen(_ menu: NSMenu) {
        onMenuClick()
    }
    @objc func onMenuClick()  {
        if let event = NSApp.currentEvent {
            // 无辅助功能选项显示要求权限菜单
            guard AXIsProcessTrusted() else {
                buildRequireAccessibilityMenu()
                return
            }
            // 当按下 option 键显示特殊菜单
            guard !event.modifierFlags.contains(.option) else {
                buildOptionMenu()
                return
            }
            // 根据类型弹出菜单
            switch TYPE {
                // 类型: 菜单
                case STATUS_ITEM_TYPE.menu:
                    buildNormalMenu()
                    break
                // 类型: 弹出面板
                case STATUS_ITEM_TYPE.popover:
                    PopoverManager.shared.togglePopover(withIdentifier: POPOVER_IDENTIFIER.statusItemPopoverViewController, relativeTo: item.button!)
                    break
            }
        }
    }
}

/**
 * 菜单构建
 **/
extension StatusItemManager {
    // 无辅助功能访问权限菜单
    @objc func buildRequireAccessibilityMenu() {
        if let menu = item.menu {
            menu.removeAllItems()
            menu.addItem(withTitle: i18n.needsAccessToAccessibilityControls, action: #selector(accessibilityRequire), keyEquivalent: "").target = self
            // Quit
            Utils.addMenuItemWithSeparator(to: menu, title: i18n.quit, icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
        }
    }
    @objc func accessibilityRequire() {
        Utils.requireAccessibilityPermissions()
    }
    // 按下 Option 按钮的菜单
    @objc func buildOptionMenu() {
        if let menu = item.menu {
            // Reset
            menu.removeAllItems()
            // Monitor
            Utils.addMenuItem(to: menu, title: i18n.monitor, icon: #imageLiteral(resourceName: "SF.square.stack.3d.down.right"), action: #selector(monitorClick))
            // Preferences
            Utils.addMenuItem(to: menu, title: i18n.preferences, icon: #imageLiteral(resourceName: "SF.gauge"), action: #selector(preferencesClick))
            // Quit
            Utils.addMenuItemWithSeparator(to: menu, title: i18n.quit, icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
        }
    }
    // 常规菜单
    @objc func buildNormalMenu() {
        if let menu = item.menu {
            // Reset
            menu.removeAllItems()
            // Preferences
            Utils.addMenuItem(to: menu, title: i18n.preferences, icon: #imageLiteral(resourceName: "SF.gauge"), action: #selector(preferencesClick))
            // Quit
            Utils.addMenuItemWithSeparator(to: menu, title: i18n.quit, icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
        }
    }
    @objc func monitorClick() {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController)
    }
    @objc func preferencesClick() {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
    }
    @objc func quitClick() {
        NSApplication.shared.terminate(self)
    }
}

/**
 * 图标显示
 **/
extension StatusItemManager {
    // 显示状态栏图标
    class func showStatusItem() {
        if #available(OSX 10.12, *) {
            self.statusItem.isVisible = true
        } else {
            self.statusItem.length = NSStatusItem.variableLength
        }
    }
    // 隐藏状态栏图标
    class func hideStatusItem() {
        if #available(OSX 10.12, *) {
            self.statusItem.isVisible = false
        } else {
            self.statusItem.length = 0.0
        }
    }
}
