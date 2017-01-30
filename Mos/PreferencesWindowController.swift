//
//  PreferencesWindowController.swift
//  Mos
//  配置界面的Window
//  Created by Cb on 2017/1/15.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var preferenceWindow: NSWindow!
    static var preferenceWindowRef:NSWindow!
    
    override func windowDidLoad() {
        super.windowDidLoad()
        // 共享一下preferenceWindow的引用 (用于IgnoreView中的beginSheetModalForWindow)
        PreferencesWindowController.preferenceWindowRef = preferenceWindow
        // 实现NSWindowDelegate
        window?.delegate = self
        // 在第一个tabItem(general)后面插入一个 NSToolbarFlexibleSpaceItem, 这里的 NSToolbarFlexibleSpaceItem 必须要出现在窗口的toolbar的allow items里面
        window?.toolbar?.insertItem(withItemIdentifier: "NSToolbarFlexibleSpaceItem", at: 3)
    }
    
    func windowWillClose(_ notification: Notification) {
        // 告诉StatusMenu可以打开新实例了
        StatusMenuController.preferencesWindowIsOpen = false
    }
}
