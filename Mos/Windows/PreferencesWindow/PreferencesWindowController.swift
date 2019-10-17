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
        // 此处 NSToolbarFlexibleSpaceItem 必须包含在窗口的 toolbar 的 allow items 列表内
        window?.toolbar?.insertItem(withItemIdentifier: NSToolbarItem.Identifier(rawValue: "NSToolbarFlexibleSpaceItem"), at: 3)
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController, destroy: true)
    }
    
}
