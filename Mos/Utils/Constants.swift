//
//  Constants.swift
//  Mos
//  常量
//  Created by Caldis on 2019/3/4.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Foundation

// 修饰键
struct MODIFIER_KEY {
    static let controlLeft = CGKeyCode(59)
    static let controlRight = CGKeyCode(62)
    static let optionLeft = CGKeyCode(58)
    static let optionRight = CGKeyCode(61)
    static let commandLeft = CGKeyCode(55)
    static let commandRight = CGKeyCode(54)
    static let shiftLeft = CGKeyCode(56)
    static let shiftRight = CGKeyCode(60)
    static let list = [
        controlLeft,
        optionLeft,
        commandLeft,
        shiftLeft,
    ]
}

// 窗口
struct WINDOW_IDENTIFIER {
    static let welcomeWindowController = "welcomeWindowController"
    static let monitorWindowController = "monitorWindowController"
    static let preferencesWindowController = "preferencesWindowController"
    static let hideStatusItemWindowController = "hideStatusItemWindowController"
}

// 视图
struct PANEL_IDENTIFIER {
    static let general = "general"
    static let advanced = "advanced"
    static let exception = "exception"
    static let list = [
        general,
        advanced,
        exception,
    ]
}
let PANEL_PADDING = CGFloat(41.0)

// 气泡弹窗
struct POPOVER_IDENTIFIER {
    static let preferencesPopoverController = "preferencesPopoverController"
}
