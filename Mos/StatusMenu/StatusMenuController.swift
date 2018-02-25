//
//  StatusBarController.swift
//  Mos
//  状态栏
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class StatusMenuController: NSObject {
    
    // 状态栏相关
    @IBOutlet weak var statusMenu: NSMenu!
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    override func awakeFromNib() {
        // 初始化状态栏
        statusItem.image = #imageLiteral(resourceName: "StatusBarIcon")
        statusItem.menu = statusMenu
    }
    
    // 监控
    @IBAction func monitorClick(_ sender: Any) {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.monitorWindowController, withTitle: i18n.monitor)
    }
    // 设置
    @IBAction func preferencesClick(_ sender: Any) {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.preferencesWindowController, withTitle: i18n.preferences)
    }
    // 退出
    @IBAction func quitClick(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
}
