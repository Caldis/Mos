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
        // 插入 NSToolbarFlexibleSpaceItem 到 index 位置 3 作为分隔符
        // 仅在 BigSur 版本之前有效
        guard #available(OSX 11.0, *) else {
            window?.toolbar?.insertItem(withItemIdentifier: NSToolbarItem.Identifier(rawValue: "NSToolbarFlexibleSpaceItem"), at: 3)
            return
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController, destroy: true)
    }
}
