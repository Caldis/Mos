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
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    override func awakeFromNib() {
        // 设置图标
        statusItem.image = #imageLiteral(resourceName: "StatusBarIcon")
        // 设置菜单代理
        statusItem.menu = self
        statusItem.menu?.delegate = self
    }
    
    // 打开菜单时监控
    // 若按下按键 Option 时显示额外的菜单栏
    func menuWillOpen(_ menu: NSMenu) {
        if let event = NSApp.currentEvent {
            if event.modifierFlags.contains(.option) {
                buildOptionMenu()
            } else {
                buildNormalMenu()
            }
        }
    }
    
    @objc func buildNormalMenu() {
        if let menu = statusItem.menu {
            menu.removeAllItems()
            menu.addItem(withTitle: i18n.monitor, action: #selector(monitorClick), keyEquivalent: "").target = self
            menu.addItem(withTitle: i18n.preferences, action: #selector(preferencesClick), keyEquivalent: "").target = self
            menu.addItem(withTitle: i18n.quit, action: #selector(quitClick), keyEquivalent: "").target = self
        }
    }
    @objc func buildOptionMenu() {
        if let menu = statusItem.menu {
            menu.removeAllItems()
            menu.addItem(withTitle: i18n.hideIcons, action: #selector(hideIcons), keyEquivalent: "").target = self
        }
    }
    
    // 监控
    @objc func monitorClick() {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.monitorWindowController, withTitle: i18n.monitor)
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
    @objc func hideIcons() {
        
    }
    
}
