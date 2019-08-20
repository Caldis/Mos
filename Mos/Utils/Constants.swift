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

// 默认设置项
// 全局参数
class OPTIONS_GLOBAL_DEFAULT {
    // 自启
    var autoLaunch = false {
        willSet {LaunchStarter.launchAtStartup(on: newValue)}
        didSet {Options.shared.saveOptions()}
    }
    // 隐藏
    var hideStatusItem = false {
        willSet {newValue ? StatusItemManager.hideStatusItem() : StatusItemManager.showStatusItem()}
        didSet {Options.shared.saveOptions()}
    }
    // 例外
    var whitelist = false {
        didSet {Options.shared.saveOptions()}
    }
    var applications = EnhanceArray<ExceptionalApplication>() {
        didSet {Options.shared.saveOptions()}
    }
}
// 滚动参数
class OPTIONS_SCROLL_DEFAULT: Codable {
    // 基础
    var smooth = true {
        didSet {Options.shared.saveOptions()}
    }
    var reverse = true {
        didSet {Options.shared.saveOptions()}
    }
    // 高级
    var toggle = 0 {
        didSet {Options.shared.saveOptions()}
    }
    var block = 0 {
        didSet {Options.shared.saveOptions()}
    }
    var step = 35.0 {
        didSet {Options.shared.saveOptions()}
    }
    var speed = 3.00 {
        didSet {Options.shared.saveOptions()}
    }
    var duration = 3.90 {
        willSet {self.durationTransition = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: newValue)}
        didSet {Options.shared.saveOptions()}
    }
    var durationTransition = 0.1340 {
        didSet {}
    }
    var precision = 1.00 {
        didSet {Options.shared.saveOptions()}
    }
    // 工具
    static func generateDurationTransition(with duration: Double) -> Double {
        // 上界, 此处需要与界面的 Slider 上界保持同步, 并添加 0.2 的偏移令结果不为 0
        let upperLimit = 5.0 + 0.2
        // 生成数据 (https://www.wolframalpha.com/input/?i=1+-+(sqrt+x%2F5)+%3D+y)
        return 1-(duration/upperLimit).squareRoot()
    }
}
