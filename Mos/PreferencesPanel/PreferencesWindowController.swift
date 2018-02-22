//
//  PreferencesWindowController.swift
//  Mos
//  选项界面的容器 Window
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var preferenceWindow: NSWindow!
    static var preferenceWindowRef:NSWindow!
    
    // 加载前
    override func windowDidLoad() {
        super.windowDidLoad()
        // 暴露 preferenceWindow 的引用 (用于 ExceptionView 中的 beginSheetModalForWindow 方法)
        PreferencesWindowController.preferenceWindowRef = preferenceWindow
        // 实现NSWindowDelegate
        window?.delegate = self
        // 在第一个tabItem(general)后面插入一个 NSToolbarFlexibleSpaceItem, 这里的 NSToolbarFlexibleSpaceItem 必须要出现在窗口的toolbar的allow items里面
        window?.toolbar?.insertItem(withItemIdentifier: NSToolbarItem.Identifier(rawValue: "NSToolbarFlexibleSpaceItem"), at: 3)
    }
    
    // 关闭前
    func windowWillClose(_ notification: Notification) {
        // 告诉StatusMenu可以打开新实例了
        StatusMenuController.preferencesWindowIsOpen = false
    }
}
