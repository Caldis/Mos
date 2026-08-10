//
//  PreferencesWindowController.swift
//  Mos
//  偏好设置面板容器 Window
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var preferenceWindow: NSWindow!
    
    override func windowDidLoad() {
        super.windowDidLoad()
        // 插入分隔符
        if #available(OSX 10.16, *) {
            window?.toolbar?.insertItem(withItemIdentifier: NSToolbarItem.Identifier.flexibleSpace, at: 4)
            window?.toolbar?.insertItem(withItemIdentifier: NSToolbarItem.Identifier.flexibleSpace, at: 3)
            window?.toolbar?.insertItem(withItemIdentifier: NSToolbarItem.Identifier.flexibleSpace, at: 2)
            window?.toolbar?.insertItem(withItemIdentifier: NSToolbarItem.Identifier.flexibleSpace, at: 1)
        } else {
            window?.toolbar?.insertItem(withItemIdentifier: NSToolbarItem.Identifier.flexibleSpace, at: 3)
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController, destroy: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // 窗口获得焦点时 (打开面板 / App 从后台切回 / 从其他应用切回) 触发一次冲突状态刷新.
        // Manager 内部有 30s 防抖,不会对 HID 链路造成压力;查询全异步,不阻塞 UI.
        LogiCenter.shared.refreshReportingStates()
    }
}
