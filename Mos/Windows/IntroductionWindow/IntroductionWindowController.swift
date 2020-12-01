//
//  IntroductionWindowController.swift
//  Mos
//  简介界面
//  Created by Caldis on 15/11/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class IntroductionWindowController: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var introductionWindow: NSWindow!
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, destroy: true)
    }
    
}
