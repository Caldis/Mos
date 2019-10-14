//
//  StatusItemPopoverView.swift
//  Mos
//  状态栏弹出 View 层
//  Created by Caldis on 2019/1/2.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class StatusItemPopoverView: NSView {
    
    override var isFlipped: Bool {
        get {
            return true
        }
    }
    
    override func viewDidMoveToWindow() {
        // 设定背景色 (包括箭头部分)
        // Ref: https://stackoverflow.com/questions/19978620/how-to-change-nspopover-background-color-include-triangle-part
        if let frameView = window?.contentView?.superview {
            let backgroundView = NSVisualEffectView(frame: frameView.bounds)
            backgroundView.wantsLayer = true
            backgroundView.autoresizingMask = [.width, .height]
            frameView.addSubview(backgroundView, positioned: .below, relativeTo: frameView)
        }
    }
    
}
