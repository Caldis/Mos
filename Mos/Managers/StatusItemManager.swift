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
    
    override func awakeFromNib() {
        // 设置图标
        item.image = #imageLiteral(resourceName: "StatusBarIcon")
        // 设置菜单代理
        item.menu = self
        item.menu?.delegate = self
    }
    
    // 显示菜单
    class func showStatusItem() {
        StatusItemManager.statusItem.length = NSStatusItem.variableLength
    }
    // 隐藏菜单
    class func hideStatusItem() {
        StatusItemManager.statusItem.length = 0.0
    }
    
    // 打开菜单时监控
    // 当没有获取到访问权限时, 菜单栏变为对应提示
    // 若按下按键 Option 时显示额外的菜单栏
    func menuWillOpen(_ menu: NSMenu) {
        if let event = NSApp.currentEvent {
            if AXIsProcessTrusted() {
                if event.modifierFlags.contains(.option) {
                    buildOptionMenu()
                } else {
                    buildNormalMenu()
                }
            } else {
                buildRequireAccessibilityMenu()
            }
        }
    }
    
    // 普通菜单
    @objc func buildNormalMenu() {
        if let menu = item.menu {
            menu.removeAllItems()
            menu.addItem(withTitle: i18n.monitor, action: #selector(monitorClick), keyEquivalent: "").target = self
            menu.item(at: 0)?.image = #imageLiteral(resourceName: "MonitorLogo")
            menu.addItem(withTitle: i18n.preferences, action: #selector(preferencesClick), keyEquivalent: "").target = self
            menu.item(at: 1)?.image = #imageLiteral(resourceName: "PreferencesLogo")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: i18n.quit, action: #selector(quitClick), keyEquivalent: "").target = self
        }
    }
    // 无辅助功能访问权限菜单
    @objc func buildRequireAccessibilityMenu() {
        if let menu = item.menu {
            menu.removeAllItems()
            menu.addItem(withTitle: i18n.needsAccessToAccessibilityControls, action: #selector(accessibilityRequire), keyEquivalent: "").target = self
        }
    }
    // 按下 Option 按钮的菜单
    @objc func buildOptionMenu() {
        if let menu = item.menu {
            menu.removeAllItems()
            menu.addItem(withTitle: i18n.hideIcon, action: #selector(hideStatusItem), keyEquivalent: "").target = self
        }
    }
    
    // 监控
    @objc func monitorClick() {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.monitorWindowController, withTitle: "")
    }
    // 偏好
    @objc func preferencesClick() {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.preferencesWindowController, withTitle: i18n.preferences)
    }
    // 退出
    @objc func quitClick() {
        NSApplication.shared.terminate(self)
    }
    
    // 隐藏
    @objc func hideStatusItem() {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.hideStatusItemWindowController, withTitle: "")
    }
    
    // 辅助权限
    @objc func accessibilityRequire() {
        Utils.requireAccessibilityPermissions()
    }
    
}
