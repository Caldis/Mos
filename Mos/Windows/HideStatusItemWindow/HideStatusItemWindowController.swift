//
//  HideStatusItemWindowController.swift
//  Mos
//  隐藏图标提示窗口
//  Created by Caldis on 2018/3/23.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class HideStatusItemWindowController: NSWindowController, NSWindowDelegate {

    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.hideStatusItemWindowController, destroy: true)
    }
    
}
