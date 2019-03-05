//
//  WelcomeWindowController.swift
//  Mos
//  欢迎界面的 Window
//  Created by Caldis on 2018/7/9.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var welcomeWindow: NSWindow!
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.welcomeWindowController)
    }
    
}
