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

    // 背景光晕
    private var glowWindowController: GlowWindowController?

    override func windowDidLoad() {
        super.windowDidLoad()
        if let window = window {
            glowWindowController = GlowWindowController.attach(to: window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        glowWindowController?.detach()
        glowWindowController = nil
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, destroy: true)
    }

}
