//
//  StatusItemManager.swift
//  Mos
//  管理状态栏图标以及初始化
//  Created by Caldis on 2018/3/7.
//  Copyright © 2018年 Caldis. All rights reserved.
//
import Cocoa

class StatusItemManager: NSMenu, NSMenuDelegate {
    
    // 状态栏引用
    static let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let item = StatusItemManager.statusItem
    
    // 初始化
    override func awakeFromNib() {
        NSLog("Module initialized: StatusItemManager")
        // 设置图标/行为
        item.button?.image = #imageLiteral(resourceName: "AppStatusBarIcon")
        // 设置事件响应
        item.menu = self
        item.menu?.delegate = self
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
            // DEBUG: 直接弹出设置窗口
            #if DEBUG
            buildOptionMenu()
            #else
            // 当按下 option 键显示特殊菜单
            guard !event.modifierFlags.contains(.option) else {
                buildOptionMenu()
                return
            }
            // 弹出菜单
            buildNormalMenu()
            #endif
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
            menu.addItem(withTitle: NSLocalizedString("Needs access to Accessibility controls", comment: ""), action: #selector(accessibilityRequire), keyEquivalent: "").target = self
            // Quit
            Utils.addMenuItemWithSeparator(to: menu, title: NSLocalizedString("Quit", comment: ""), icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
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
            Utils.addMenuItem(to: menu, title: NSLocalizedString("Event Monitor", comment: ""), icon: #imageLiteral(resourceName: "SF.square.stack.3d.down.right"), action: #selector(monitorClick))
            // Preferences
            Utils.addMenuItem(to: menu, title: NSLocalizedString("Preferences", comment: ""), icon: #imageLiteral(resourceName: "SF.gauge"), action: #selector(preferencesClick))
            // Quit
            Utils.addMenuItemWithSeparator(to: menu, title: NSLocalizedString("Quit", comment: ""), icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
        }
    }
    // 常规菜单
    @objc func buildNormalMenu() {
        if let menu = item.menu {
            // Reset
            menu.removeAllItems()
            // Preferences
            Utils.addMenuItem(to: menu, title: NSLocalizedString("Preferences", comment: ""), icon: #imageLiteral(resourceName: "SF.gauge"), action: #selector(preferencesClick))
            // Quit
            Utils.addMenuItemWithSeparator(to: menu, title: NSLocalizedString("Quit", comment: ""), icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
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
