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
}
