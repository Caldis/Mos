//
//  StatusItemManager.swift
//  Mos
//  管理状态栏图标以及初始化
//  Created by Caldis on 2018/3/7.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class StatusItemManager: NSMenu {
    
    // 系统状态栏引用
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    override func awakeFromNib() {
        // 设置状态栏图标
        statusItem.image = #imageLiteral(resourceName: "StatusBarIcon")
        // 设置状态栏菜单
        statusItem.menu = self
    }
    
    // 监控
    @IBAction func monitorClick(_ sender: Any) {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.monitorWindowController, withTitle: i18n.monitor)
    }
    // 偏好
    @IBAction func preferencesClick(_ sender: Any) {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.preferencesWindowController, withTitle: i18n.preferences)
    }
    // 退出
    @IBAction func quitClick(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
}
