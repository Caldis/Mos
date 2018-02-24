//
//  StatusBarController.swift
//  Mos
//  状态栏
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class StatusMenuController: NSObject {
    
    // 国际化相关
    let ScrollMonitorWindowTitle = NSLocalizedString("Monitor", comment: "")
    let PreferencesWindowTitle = NSLocalizedString("Preferences", comment: "")
    
    // 状态栏相关
    @IBOutlet weak var statusMenu: NSMenu!
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    override func awakeFromNib() {
        // 初始化状态栏
        let statusBarIcon = #imageLiteral(resourceName: "StatusBarIcon")
        statusBarIcon.isTemplate = true
        statusItem.image = statusBarIcon
        statusItem.menu = statusMenu
    }
    
    // 监控
    @IBAction func monitorClick(_ sender: Any) {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.monitorWindowController, withTitle: ScrollMonitorWindowTitle)
    }
    // 设置
    @IBAction func preferencesClick(_ sender: Any) {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.preferencesWindowController, withTitle: PreferencesWindowTitle)
    }
    // 退出
    @IBAction func quitClick(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
}
