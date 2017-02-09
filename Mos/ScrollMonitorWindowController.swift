//
//  ScrollMonitorWindowController.swift
//  Mos
//  用于呈现滚动事件数据的Window
//  Created by Cb on 2017/1/15.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class ScrollMonitorWindowController: NSWindowController, NSWindowDelegate {
    
    static var scrollMonitorWindowRef:NSWindow!
    @IBOutlet weak var scrollMonitorWindow: NSWindow!
    
    override func windowDidLoad() {
        super.windowDidLoad()
        // 共享一下scrollMonitorWindow的引用
        ScrollMonitorWindowController.scrollMonitorWindowRef = scrollMonitorWindow
        // 实现NSWindowDelegate
        window?.delegate = self
        // 隐藏标题栏
        if let window = self.window {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(NSWindowStyleMask.fullSizeContentView)
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        // 告诉StatusMenu可以打开新实例了
        StatusMenuController.scrollMonitorWindowIsOpen = false
    }
}
